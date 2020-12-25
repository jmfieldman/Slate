//
//  main.swift
//  slate
//
//  Created by Jason Fieldman on 5/28/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import ArgumentParser
import Foundation

let kStringArgVar: String = "%@"

enum ErrorCode: Int32 {
  case fileNotFound = 1
  case pathNotFound = 2
  case invalidArgument = 3
}

func printError(_ str: String) {
  fputs(str + "\n", stderr)
}

struct SlateGenerator: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Generates Slate model objects from a Core Data xcdatamodel file"
  )

  // MARK: - Arguments

  @Option(name: .long, help: "Path to the Core Data xcdatamodel file")
  var inputModel: String

  @Option(name: .long, help: "Directory to write generated slate object files")
  var outputSlateObjectPath: String

  @Option(name: .long, help: "Directory to write generated core data entity files; do not supply this if you are using the natively-generated Core Data entities.")
  var outputCoreDataEntityPath: String = ""

  @Flag(name: .short, help: "Create specified output paths if they don't exist yet")
  var force: Bool = false

  @Flag(name: .short, help: "Enable verbose output")
  var verbose: Bool = false

  @Flag(name: .long, help: "Ouptut generates code using struct instead of class")
  var useStruct: Bool = false

  @Flag(name: .long, help: "All Int16, Int32, Int64 values will be cast to Int in Slate code")
  var castInt: Bool = false

  @Option(name: .long, help: "Transform for generated Slate object names; %@ is replaced by the data object name.")
  var nameTransform: String = kStringArgVar

  @Option(name: .long, help: "Transform for the generated file names; If the value does not contain %@ then all generated classes are put in one file.")
  var fileTransform: String = kStringArgVar

  @Option(name: .long, help: "This string is placed in the tranditional import section of each generated file.")
  var imports: String = ""

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

    guard force || outputCoreDataEntityPath.count == 0 || FileManager.default.fileExists(atPath: outputCoreDataEntityPath) else {
      printError("Could not find core data entity output directory at \(outputCoreDataEntityPath)")
      try exit(.pathNotFound)
    }

    if force {
      try? FileManager.default.createDirectory(atPath: outputSlateObjectPath, withIntermediateDirectories: true, attributes: nil)
      if outputCoreDataEntityPath.count > 0 {
        try? FileManager.default.createDirectory(atPath: outputCoreDataEntityPath, withIntermediateDirectories: true, attributes: nil)
      }
    }

    guard nameTransform.contains("%@") else {
      printError("--name-transform must contain the %@ element")
      try exit(.invalidArgument)
    }

    let entities = ParseCoreData(contentsPath: contentsPath)
    CoreDataSwiftGenerator.generateCoreData(
      entities: entities,
      useStruct: useStruct,
      nameTransform: nameTransform,
      fileTransform: fileTransform,
      castInt: castInt,
      outputPath: outputSlateObjectPath,
      entityPath: outputCoreDataEntityPath,
      imports: imports
    )
  }
}

SlateGenerator.main()

// var _useInt: Bool = false
// var _embedCommand: Bool = false
//
////try?
// command(
//    Argument<String>("modelPath", description: "Path to the xcdatamodel file"),
//    Argument<String>("outputPath", description: "Directory to write generated files"),
//    Option<Int>("useclass", default: 0, description: "0 to use struct, 1 to use class"),
//    Option<Int>("useint", default: 0, description: "0 to use declared values (Int16, etc), 1 to force Int"),
//    Option<String>("name", default: "Slate%@", description: "Immutable class name transform; %@ is replaced by Entity name."),
//    Option<String>("file", default: "", description: "File name transform; %@ is replaced by Entity name.  No %@ puts all classes in one file."),
//    Option<String>("import", default: "", description: "Import an additional swift module"),
//    Option<Int>("embedcommand", default: 0, description: "set 1 to embed the full command used to generate files."),
//    Option<String>("entityPath", default: "", description: "The path to generate core data entities")
// ) { modelPath, outputPath, useclass, useint, classXform, fileXform, importModule, embedCommand, entityPath in
//
//    let contentsPath = ((modelPath as NSString).expandingTildeInPath as NSString).appendingPathComponent("contents")
//    if !FileManager.default.fileExists(atPath: contentsPath) {
//        print("Could not find data model contents at \(contentsPath)")
//    }
//
//    if !FileManager.default.fileExists(atPath: outputPath) {
//        print("Could not find output directory at \(outputPath)")
//    }
//
//    if !classXform.contains("%@") {
//        print("class transform must contain the %@ element")
//        exit(10)
//    }
//
//    let realFileXform = (fileXform == "") ? classXform : fileXform
//    let shouldUseClass = useclass != 0
//    _useInt = useint != 0
//    _embedCommand = embedCommand != 0
//
//    let entities = ParseCoreData(contentsPath: contentsPath)
//    CoreDataSwiftGenerator.generateCoreData(entities: entities,
//                                            useClass: shouldUseClass,
//                                            classXform: classXform,
//                                            fileXform: realFileXform,
//                                            outputPath: outputPath,
//                                            entityPath: entityPath,
//                                            importModule: importModule)
//
// }.run(
//    //["/Users/jasonfieldman/Development/Slate_Start/SlatePlayground/SlatePlayground/SlatePlayground.xcdatamodeld/SlatePlayground 2.xcdatamodel",
//    //"/Users/jasonfieldman/Development/Slate_Start/SlatePlayground/SlatePlayground/CoreData/"]
// )
