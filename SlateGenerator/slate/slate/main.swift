//
//  main.swift
//  slate
//
//  Created by Jason Fieldman on 5/28/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation

var _useInt: Bool = false
var _embedCommand: Bool = false

//try?
command(
    Argument<String>("modelPath", description: "Path to the xcdatamodel file"),
    Argument<String>("outputPath", description: "Directory to write generated files"),
    Option<Int>("useclass", default: 0, description: "0 to use struct, 1 to use class"),
    Option<Int>("useint", default: 0, description: "0 to use declared values (Int16, etc), 1 to force Int"),
    Option<String>("name", default: "Slate%@", description: "Immutable class name transform; %@ is replaced by Entity name."),
    Option<String>("file", default: "", description: "File name transform; %@ is replaced by Entity name.  No %@ puts all classes in one file."),
    Option<String>("import", default: "", description: "Import an additional swift module"),
    Option<Int>("embedcommand", default: 0, description: "set 1 to embed the full command used to generate files."),
    Option<String>("entityPath", default: "", description: "The path to generate core data entities")
) { modelPath, outputPath, useclass, useint, classXform, fileXform, importModule, embedCommand, entityPath in

    let contentsPath = ((modelPath as NSString).expandingTildeInPath as NSString).appendingPathComponent("contents")
    if !FileManager.default.fileExists(atPath: contentsPath) {
        print("Could not find data model contents at \(contentsPath)")
    }
    
    if !FileManager.default.fileExists(atPath: outputPath) {
        print("Could not find output directory at \(outputPath)")
    }
    
    if !classXform.contains("%@") {
        print("class transform must contain the %@ element")
        exit(10)
    }
    
    let realFileXform = (fileXform == "") ? classXform : fileXform
    let shouldUseClass = useclass != 0
    _useInt = useint != 0
    _embedCommand = embedCommand != 0

    let entities = ParseCoreData(contentsPath: contentsPath)
    CoreDataSwiftGenerator.generateCoreData(entities: entities,
                                            useClass: shouldUseClass,
                                            classXform: classXform,
                                            fileXform: realFileXform,
                                            outputPath: outputPath,
                                            entityPath: entityPath,
                                            importModule: importModule)
    
}.run(
    //["/Users/jasonfieldman/Development/Slate_Start/SlatePlayground/SlatePlayground/SlatePlayground.xcdatamodeld/SlatePlayground 2.xcdatamodel",
    //"/Users/jasonfieldman/Development/Slate_Start/SlatePlayground/SlatePlayground/CoreData/"]
)
