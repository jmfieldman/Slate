//
//  main.swift
//  Copyright © 2020 Jason Fieldman.
//

import Foundation

private let kModelPath = "Tests/DataModel/SlateTests.xcdatamodel"
private let kSlateTestPath = "Tests/SlateTests"

let task = Process()
task.launchPath = "/bin/sh"
task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kSlateTestPath)/Generated/Class/Slate --output-core-data-entity-path \(kSlateTestPath)/Generated/Class/CoreData -f --cast-int --name-transform Slate%@ --file-transform Slate%@ --imports \"import Slate\""]
task.launch()
task.waitUntilExit()
if task.terminationStatus != 0 {
    print("Test setup completed with error code \(task.terminationStatus)")
} else {
    print("Test setup completed successfully")
}
