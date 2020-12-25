import Foundation
import XCTest

private let kModelPath = "Tests/DataModel/SlateTests.xcdatamodel"
private let kSlateTestPath = "Tests/SlateTests"

/**
 These tests create the generated slate files in `Tests/SlateTests/Generated` that are used in the
 actual Slate library tests.
 */
class GenerationTests: XCTestCase {
  func testClassFiles() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kSlateTestPath)/Class/Generated/Slate --output-core-data-entity-path \(kSlateTestPath)/Class/Generated/CoreData -f --cast-int --name-transform Slate%@"]
    task.launch()
    task.waitUntilExit()
    XCTAssertEqual(task.terminationStatus, 0)
  }

  func testStructFiles() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kSlateTestPath)/Struct/Generated/Slate --output-core-data-entity-path \(kSlateTestPath)/Struct/Generated/CoreData -f --use-struct --name-transform Struct%@ --file-transform Struct%@"]
    task.launch()
    task.waitUntilExit()
    XCTAssertEqual(task.terminationStatus, 0)
  }

  func testSingleClassFile() {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "swift run slategen --input-model \(kModelPath) --output-slate-object-path \(kSlateTestPath)/Single/Generated/Slate --output-core-data-entity-path \(kSlateTestPath)/Single/Generated/CoreData -f --cast-int --name-transform Single%@ --file-transform SingleFile"]
    task.launch()
    task.waitUntilExit()
    XCTAssertEqual(task.terminationStatus, 0)
  }
}
