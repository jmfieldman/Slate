import Foundation

/// Per-kind output directories for generated files. Any kind set to `nil`
/// falls back to a default (the manifest defaults to
/// `<schema>/SlateGenerationManifest.json`; mutable/bridge default to the
/// schema directory if not provided). Use ``GeneratedOutputLayout/single(_:)``
/// to collapse every kind into a single output dir.
public struct GeneratedOutputLayout: Sendable {
    public var mutable: URL?
    public var bridge: URL?
    public var schema: URL?
    public var manifest: URL?

    public init(
        mutable: URL? = nil,
        bridge: URL? = nil,
        schema: URL? = nil,
        manifest: URL? = nil
    ) {
        self.mutable = mutable
        self.bridge = bridge
        self.schema = schema
        self.manifest = manifest
    }

    /// Convenience for the legacy single-output mode used by tests and the
    /// older CLI shape.
    public static func single(_ url: URL, manifest: URL? = nil) -> GeneratedOutputLayout {
        GeneratedOutputLayout(
            mutable: url,
            bridge: url,
            schema: url,
            manifest: manifest
        )
    }
}

public struct GeneratedFileWriter: Sendable {
    public static let manifestFileName = "SlateGenerationManifest.json"

    public init() {}

    public func write(
        files: [GeneratedFile],
        layout: GeneratedOutputLayout,
        createDirectories: Bool = true
    ) throws {
        for file in files {
            let destination = url(for: file, layout: layout)
            let parent = destination.deletingLastPathComponent()
            if createDirectories {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try file.contents.write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    public func staleFiles(
        files: [GeneratedFile],
        layout: GeneratedOutputLayout
    ) throws -> [String] {
        try files.compactMap { file in
            let destination = url(for: file, layout: layout)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                return file.path
            }
            let existing = try String(contentsOf: destination, encoding: .utf8)
            return existing == file.contents ? nil : file.path
        }
    }

    public func readManifest(layout: GeneratedOutputLayout) throws -> GenerationManifest {
        let url = manifestURL(layout: layout)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GenerationManifest.self, from: data)
    }

    /// Cleans every file recorded in the manifest. Each path is resolved
    /// against the layout — sources land in `mutable`/`bridge`/`schema`,
    /// the manifest itself in its dedicated `manifest` URL (or the schema
    /// directory by default).
    public func clean(layout: GeneratedOutputLayout) throws -> [String] {
        let manifest = try readManifest(layout: layout)
        let fileManager = FileManager.default
        var removed: [String] = []

        for path in manifest.files {
            // We do not know the kind here because the manifest only stores
            // bare paths; try all known kinds in priority order.
            let candidates = candidateURLs(forPath: path, layout: layout)
            for url in candidates where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                removed.append(path)
                break
            }
        }

        let manifestLocation = manifestURL(layout: layout)
        if fileManager.fileExists(atPath: manifestLocation.path) {
            try fileManager.removeItem(at: manifestLocation)
            removed.append(Self.manifestFileName)
        }

        return removed
    }

    // MARK: - Legacy single-output overloads

    public func write(
        files: [GeneratedFile],
        to outputDirectory: URL,
        manifestURL: URL? = nil
    ) throws {
        try write(files: files, layout: .single(outputDirectory, manifest: manifestURL))
    }

    public func staleFiles(
        files: [GeneratedFile],
        in outputDirectory: URL,
        manifestURL: URL? = nil
    ) throws -> [String] {
        try staleFiles(files: files, layout: .single(outputDirectory, manifest: manifestURL))
    }

    public func readManifest(from outputDirectory: URL, manifestURL: URL? = nil) throws -> GenerationManifest {
        try readManifest(layout: .single(outputDirectory, manifest: manifestURL))
    }

    public func clean(outputDirectory: URL, manifestURL: URL? = nil) throws -> [String] {
        try clean(layout: .single(outputDirectory, manifest: manifestURL))
    }

    private func directory(for kind: GeneratedFileKind, layout: GeneratedOutputLayout) -> URL {
        switch kind {
        case .mutable:
            return layout.mutable ?? layout.schema ?? layout.bridge
                ?? URL(fileURLWithPath: ".")
        case .bridge:
            return layout.bridge ?? layout.schema ?? layout.mutable
                ?? URL(fileURLWithPath: ".")
        case .schema:
            return layout.schema ?? layout.mutable ?? layout.bridge
                ?? URL(fileURLWithPath: ".")
        case .manifest:
            return URL(fileURLWithPath: ".")
        }
    }

    private func url(for file: GeneratedFile, layout: GeneratedOutputLayout) -> URL {
        if file.kind == .manifest {
            return manifestURL(layout: layout)
        }
        return directory(for: file.kind, layout: layout).appendingPathComponent(file.path)
    }

    private func manifestURL(layout: GeneratedOutputLayout) -> URL {
        if let manifest = layout.manifest {
            return manifest
        }
        let directory = layout.schema ?? layout.mutable ?? layout.bridge
            ?? URL(fileURLWithPath: ".")
        return directory.appendingPathComponent(Self.manifestFileName)
    }

    private func candidateURLs(forPath path: String, layout: GeneratedOutputLayout) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for kind: GeneratedFileKind in [.mutable, .bridge, .schema] {
            let url = directory(for: kind, layout: layout).appendingPathComponent(path)
            if seen.insert(url.path).inserted {
                urls.append(url)
            }
        }
        return urls
    }
}
