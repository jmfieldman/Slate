//
//  TestUtils.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import Slate
import Testing

let kMomSlateTests: NSManagedObjectModel = {
    guard let basePath = Bundle.module.path(forResource: "SlateTests", ofType: "mom") else {
        Issue.record("Coult not find managed object model")
        return NSManagedObjectModel(contentsOf: URL(fileURLWithPath: "Crash"))!
    }

    return NSManagedObjectModel(contentsOf: URL(fileURLWithPath: basePath))!
}()

func ConfigureTest(
    slate: Slate,
    mom: NSManagedObjectModel
) async {
    let desc = NSPersistentStoreDescription()
    desc.type = NSInMemoryStoreType

    let success: Bool = await withCheckedContinuation { continuation in
        slate.configure(
            managedObjectModel: mom,
            persistentStoreDescription: desc
        ) { _, error in
            if let error {
                Issue.record("Configuration error: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
            continuation.resume(returning: true)
        }
    }

    #expect(success)
}
