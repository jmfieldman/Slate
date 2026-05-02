import ArgumentParser
import Foundation
import SlateGeneratorLib

@main
struct SlateGeneratorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slate-generator",
        abstract: "Source-based code generator for Slate 3 schemas.",
        subcommands: [
            DumpSchema.self,
            Generate.self,
            Check.self,
            Clean.self,
        ]
    )
}

// MARK: - Shared option groups

/// Options that select the Swift source files to scan.
struct InputOptions: ParsableArguments {
    @Option(
        name: [.long, .customShort("i")],
        parsing: .singleValue,
        help: ArgumentHelp("Swift source file or directory to parse. Repeat to add more.", valueName: "path")
    )
    var input: [String] = []

    @Option(
        parsing: .singleValue,
        help: ArgumentHelp("Path to exclude from scanning. Repeat to add more.", valueName: "path")
    )
    var exclude: [String] = []

    @Argument(
        help: ArgumentHelp(
            "Positional Swift source files or directories. Equivalent to --input.",
            valueName: "input-path",
            visibility: .default
        )
    )
    var positionalInputs: [String] = []

    /// Resolved list of `.swift` URLs after expanding directories and applying excludes.
    func resolvedInputURLs() throws -> [URL] {
        let combined = input + positionalInputs
        guard !combined.isEmpty else {
            throw ValidationError("At least one --input or positional input path is required.")
        }
        return try resolveInputURLs(inputs: combined, excludes: exclude)
    }
}

/// Options that name the schema and the modules that consume it.
struct SchemaIdentityOptions: ParsableArguments {
    @Option(help: "Generated schema type name.")
    var schemaName: String = "GeneratedSlateSchema"

    @Option(help: "Module containing public immutable models.")
    var modelModule: String = "Models"

    @Option(help: "Module receiving generated persistence code.")
    var runtimeModule: String = "Persistence"
}

/// Logging-style flags shared by every subcommand.
struct GlobalOptions: ParsableArguments {
    @Flag(name: [.long, .customShort("v")], help: "Verbose logging.")
    var verbose: Bool = false

    @Flag(help: "Suppress informational output.")
    var quiet: Bool = false
}

/// Options that route generated artifacts to per-kind output directories.
///
/// The design spec ships separate `--output-mutable`, `--output-bridge`,
/// `--output-schema`, and `--output-manifest` paths so that mutable
/// `NSManagedObject` classes can live in the persistence module while
/// bridge/schema files can live elsewhere. The legacy `--output` collapses
/// every kind into a single directory and is kept for now.
struct OutputOptions: ParsableArguments {
    @Option(help: "Output directory for generated NSManagedObject classes.")
    var outputMutable: String?

    @Option(help: "Output directory for generated persistence bridge files.")
    var outputBridge: String?

    @Option(help: "Output directory for generated schema/model builder.")
    var outputSchema: String?

    @Option(help: "Path to write the generation manifest JSON. Defaults to <output-schema>/SlateGenerationManifest.json.")
    var outputManifest: String?

    @Option(help: "Legacy single output directory. Equivalent to setting all of --output-mutable/-bridge/-schema to the same path.")
    var output: String?

    @Flag(inversion: .prefixedNo, help: "Create output directories if missing.")
    var createOutputDirs: Bool = true

    func resolvedLayout() throws -> GeneratedOutputLayout {
        let mutable = (outputMutable ?? output).map { URL(fileURLWithPath: $0) }
        let bridge = (outputBridge ?? output).map { URL(fileURLWithPath: $0) }
        let schema = (outputSchema ?? output).map { URL(fileURLWithPath: $0) }
        let manifest = outputManifest.map { URL(fileURLWithPath: $0) }

        guard mutable != nil || bridge != nil || schema != nil else {
            throw ValidationError("At least one of --output, --output-mutable, --output-bridge, or --output-schema must be provided.")
        }

        return GeneratedOutputLayout(
            mutable: mutable,
            bridge: bridge,
            schema: schema,
            manifest: manifest
        )
    }
}

// MARK: - dump-schema

struct DumpSchema: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dump-schema",
        abstract: "Parse Swift sources and print the normalized schema model as JSON."
    )

    @OptionGroup var inputs: InputOptions
    @OptionGroup var identity: SchemaIdentityOptions
    @OptionGroup var globals: GlobalOptions

    @Flag(help: "Pretty-print JSON output.")
    var pretty: Bool = false

    func run() throws {
        let urls = try inputs.resolvedInputURLs()
        let schema = try parseAndValidate(urls: urls, identity: identity)
        print(try SchemaDumper().dump(schema, pretty: pretty))
    }
}

// MARK: - generate

struct Generate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Parse Swift sources, validate, and write generated files."
    )

    @OptionGroup var inputs: InputOptions
    @OptionGroup var identity: SchemaIdentityOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var globals: GlobalOptions

    @Flag(help: "Print planned writes without writing.")
    var dryRun: Bool = false

    @Flag(help: "Delete generated files no longer present in the new manifest.")
    var prune: Bool = false

    func run() throws {
        let urls = try inputs.resolvedInputURLs()
        let schema = try parseAndValidate(urls: urls, identity: identity)
        let files = GeneratedSchemaRenderer().render(schema: schema)
        let layout = try output.resolvedLayout()

        if dryRun {
            for file in files {
                print("would write \(file.kind.rawValue) \(file.path)")
            }
            return
        }

        let previousManifest = (try? GeneratedFileWriter().readManifest(layout: layout)) ?? nil
        try GeneratedFileWriter().write(
            files: files,
            layout: layout,
            createDirectories: output.createOutputDirs
        )

        if prune, let previous = previousManifest {
            let newPaths = Set(files.map(\.path))
            let stalePaths = previous.files.filter { !newPaths.contains($0) }
            for path in stalePaths {
                try removeIfPresent(path: path, layout: layout)
            }
            if !globals.quiet, !stalePaths.isEmpty {
                print("Pruned \(stalePaths.count) stale file(s).")
            }
        }

        if !globals.quiet {
            print("Generated \(files.count) files.")
        }
    }

    private func removeIfPresent(path: String, layout: GeneratedOutputLayout) throws {
        for kind in [GeneratedFileKind.mutable, .bridge, .schema] {
            let dir = layout.directory(for: kind)
            guard let dir else { continue }
            let candidate = dir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
                return
            }
        }
    }
}

// MARK: - check

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Verify that generated files on disk match what would be generated."
    )

    @OptionGroup var inputs: InputOptions
    @OptionGroup var identity: SchemaIdentityOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var globals: GlobalOptions

    @Flag(help: "Treat missing generated dirs as empty instead of an error.")
    var allowMissingOutput: Bool = false

    func run() throws {
        let urls = try inputs.resolvedInputURLs()
        let schema = try parseAndValidate(urls: urls, identity: identity)
        let files = GeneratedSchemaRenderer().render(schema: schema)
        let layout = try output.resolvedLayout()

        do {
            let stale = try GeneratedFileWriter().staleFiles(files: files, layout: layout)
            guard stale.isEmpty else {
                throw ValidationError("Generated files are stale: \(stale.joined(separator: ", "))")
            }
        } catch let error as ValidationError {
            throw error
        } catch {
            if allowMissingOutput {
                throw ValidationError("Generated files are stale: \(files.map(\.path).joined(separator: ", "))")
            }
            throw error
        }

        if !globals.quiet {
            print("Generated files are up to date.")
        }
    }
}

// MARK: - clean

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove generated files identified by the manifest."
    )

    @OptionGroup var output: OutputOptions
    @OptionGroup var globals: GlobalOptions

    @Flag(help: "Print planned removals without removing.")
    var dryRun: Bool = false

    func run() throws {
        let layout = try output.resolvedLayout()
        if dryRun {
            let manifest = try GeneratedFileWriter().readManifest(layout: layout)
            for path in manifest.files {
                print("would remove \(path)")
            }
            print("would remove \(GeneratedFileWriter.manifestFileName)")
            return
        }
        let removed = try GeneratedFileWriter().clean(layout: layout)
        if !globals.quiet {
            print("Removed \(removed.count) files.")
        }
    }
}

// MARK: - Helpers

private func parseAndValidate(urls: [URL], identity: SchemaIdentityOptions) throws -> NormalizedSchema {
    let schema = try SwiftSchemaParser().parseFiles(
        at: urls,
        schemaName: identity.schemaName,
        modelModule: identity.modelModule,
        runtimeModule: identity.runtimeModule
    )
    try SchemaValidator().validate(schema)
    return schema
}

private func resolveInputURLs(inputs: [String], excludes: [String]) throws -> [URL] {
    let fileManager = FileManager.default
    let excludePaths = excludes.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    var urls: [URL] = []

    func isExcluded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return excludePaths.contains { excluded in
            path == excluded || path.hasPrefix(excluded + "/")
        }
    }

    for input in inputs {
        let url = URL(fileURLWithPath: input)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ValidationError("Input does not exist: \(input)")
        }

        if isDirectory.boolValue {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let fileURL as URL in enumerator
            where fileURL.pathExtension == "swift" && !isExcluded(fileURL) {
                urls.append(fileURL)
            }
        } else if url.pathExtension == "swift", !isExcluded(url) {
            urls.append(url)
        }
    }

    return urls.sorted { $0.path < $1.path }
}

extension GeneratedOutputLayout {
    /// Returns the resolved directory for the given kind (mirrors the
    /// internal logic in `GeneratedFileWriter`). Used by the CLI's `--prune`
    /// flow to locate stale files for removal.
    fileprivate func directory(for kind: GeneratedFileKind) -> URL? {
        switch kind {
        case .mutable: return mutable ?? schema ?? bridge
        case .bridge:  return bridge ?? schema ?? mutable
        case .schema:  return schema ?? mutable ?? bridge
        case .manifest: return manifest
        }
    }
}
