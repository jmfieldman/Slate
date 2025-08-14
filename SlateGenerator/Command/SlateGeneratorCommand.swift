//
//  SlateGeneratorCommand.swift
//  Copyright © 2020 Jason Fieldman.
//

import ArgumentParser
import Foundation
import SlateGeneratorLib

enum ErrorCode: Int32 {
    case fileNotFound = 1
    case pathNotFound = 2
    case invalidArgument = 3
}

func printError(_ str: String) {
    fputs(str + "\n", stderr)
}

struct GenCoreData: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generates Slate model objects from a Core Data xcdatamodel file"
    )

    // MARK: - Arguments

    @Option(name: .long, help: "Path to the Core Data xcdatamodel file")
    var inputModel: String

    @Option(name: .long, help: "Directory to write generated slate object files")
    var outputSlateObjectPath: String

    @Option(name: .long, help: "Directory to write generated core data entity files")
    var outputCoreDataEntityPath: String

    @Flag(name: .short, help: "Create specified output paths if they don't exist yet")
    var force: Bool = false

    @Flag(name: .short, help: "Enable verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "All Int16, Int32, Int64 values will be cast to Int in Slate code unless this flag is set")
    var noIntCast: Bool = false

    @Option(name: .long, help: "Transform for generated Slate object names; %@ is replaced by the data object name.")
    var nameTransform: String = kStringArgVar

    @Option(name: .long, help: "Transform for the generated file names; If the value does not contain %@ then all generated classes are put in one file.")
    var fileTransform: String = kStringArgVar

    @Option(name: .long, help: "Comma-separated list of modules to import for generated database files.")
    var coreDataFileImports: String = ""

    // MARK: - Utility

    func printVerbose(_ str: String) {
        if verbose { print(str) }
    }

    func exit(_ code: ErrorCode) throws -> Never {
        throw ExitCode(code.rawValue)
    }

    // MARK: - Run

    func run() throws {
        // MARK: - Environment Sanity Checking

        let contentsPath = ((inputModel as NSString).expandingTildeInPath as NSString).appendingPathComponent("contents")
        guard FileManager.default.fileExists(atPath: contentsPath) else {
            printError("Could not find data model contents at \(contentsPath)")
            try exit(.fileNotFound)
        }

        guard force || FileManager.default.fileExists(atPath: outputSlateObjectPath) else {
            printError("Could not find slate object output directory at \(outputSlateObjectPath)")
            try exit(.pathNotFound)
        }

        guard force || FileManager.default.fileExists(atPath: outputCoreDataEntityPath) else {
            printError("Could not find core data entity output directory at \(outputCoreDataEntityPath)")
            try exit(.pathNotFound)
        }

        if force {
            try FileManager.default.createDirectory(atPath: outputSlateObjectPath, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(atPath: outputCoreDataEntityPath, withIntermediateDirectories: true, attributes: nil)
        }

        guard fileTransform.contains(kStringArgVar) else {
            printError("--file-transform must contain the \(kStringArgVar) element")
            try exit(.invalidArgument)
        }

        guard nameTransform.contains(kStringArgVar) else {
            printError("--name-transform must contain the \(kStringArgVar) element")
            try exit(.invalidArgument)
        }

        CoreDataSwiftGenerator.generateCoreData(
            contentsPath: contentsPath,
            nameTransform: nameTransform,
            fileTransform: fileTransform,
            castInt: !noIntCast,
            outputPath: outputSlateObjectPath,
            entityPath: outputCoreDataEntityPath,
            coreDataFileImports: coreDataFileImports
        )
    }
}

/// The main command collection for the command line tool.
@main struct Slate: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Contains commands for the Slate package.",
        subcommands: [
            GenCoreData.self,
        ]
    )
}

/// Common options for ParsableCommands
public struct CommonOptions: ParsableArguments {
    @Flag(name: [.long], help: "Print verbose output")
    public var verbose: Bool = false

    @Flag(name: [.long], help: "Quiet all normal output")
    public var quiet: Bool = false

    @Flag(name: [.long], help: "Print debug output (higher than verbose)")
    public var debug: Bool = false

    public init() {}
}

public extension CommonOptions {
    var verbosity: Verbosity {
        if debug { return .debug }
        if verbose { return .verbose }
        if quiet { return .quiet }
        return .normal
    }
}
