import Foundation
import XCTest

private let kModelPath = "Tests/DataModel/SlateTests.xcdatamodel"
private let kOutputPath = "Tests/SlateTests/Generated"
private let kCoreDataPath = "Tests/SlateTests/Generated/CoreData"

class GenerationTests: XCTestCase {
  func testClassFiles() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kOutputPath)/Class --output-core-data-entity-path \(kCoreDataPath) -f --cast-int"]
    task.launch()
    task.waitUntilExit()
    print("foo: \(task.terminationStatus)")
  }

  func testStructFiles() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kOutputPath)/Struct --output-core-data-entity-path \(kCoreDataPath) -f --use-struct --name-transform Struct%@ --file-transform Struct%@"]
    task.launch()
    task.waitUntilExit()
    print("foo: \(task.terminationStatus)")
  }

  func testSingleClassFile() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kOutputPath)/Single --output-core-data-entity-path \(kCoreDataPath) -f --cast-int --file-transform SingleFile"]
    task.launch()
    task.waitUntilExit()
    print("foo: \(task.terminationStatus)")
  }
}
