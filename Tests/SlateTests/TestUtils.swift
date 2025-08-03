//
//  TestUtils.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import Slate
import Testing

func ConfigureTest(
    slate: Slate
) async {
    guard let basePath = Bundle.module.path(forResource: "SlateTests", ofType: "mom") else {
        Issue.record("Coult not find managed object model")
        return
    }

    let momd = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: basePath))!
    let desc = NSPersistentStoreDescription()
    desc.type = NSInMemoryStoreType

    let success: Bool = await withCheckedContinuation { continuation in
        slate.configure(
            managedObjectModel: momd,
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
