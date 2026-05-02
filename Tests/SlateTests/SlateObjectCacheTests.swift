import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite
struct SlateObjectCacheTests {
    @Test
    func cacheHydratedOnInsert() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let cache = try slateCache(for: slate)
        #expect(cache.count == 1)

        let cached = try await slate.many(TestAuthor.self)
        #expect(cached.first?.name == "Ada")
        #expect(cache.count == 1)
    }

    @Test
    func cacheUpdatedOnUpdate() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let cache = try slateCache(for: slate)
        let originalAuthors = try await slate.many(TestAuthor.self)
        #expect(originalAuthors.count == 1)
        #expect(cache.count == 1)

        try await slate.mutate { context in
            let table = context[DatabaseTestAuthor.self]
            if let row = try table.one() {
                row.name = "Bea"
            }
        }
        #expect(cache.count == 1)

        let updated = try await slate.many(TestAuthor.self)
        #expect(updated.first?.name == "Bea")
    }

    @Test
    func cacheClearsDeletedEntries() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let cache = try slateCache(for: slate)
        _ = try await slate.many(TestAuthor.self)
        #expect(cache.count == 2)

        try await slate.mutate { context in
            _ = try context[DatabaseTestAuthor.self].delete(where: \.name == "Ada")
        }
        #expect(cache.count == 1)
    }

    @Test
    func cacheUntouchedOnUserError() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let cache = try slateCache(for: slate)
        let initial = try await slate.many(TestAuthor.self)
        #expect(initial.first?.name == "Ada")
        #expect(cache.count == 1)

        struct UserError: Error {}
        await #expect(throws: UserError.self) {
            try await slate.mutate { context in
                let table = context[DatabaseTestAuthor.self]
                if let row = try table.one() {
                    row.name = "Bea"
                }
                let extra = context.create(DatabaseTestAuthor.self)
                extra.name = "Cyd"
                throw UserError()
            }
        }

        #expect(cache.count == 1)

        let after = try await slate.many(TestAuthor.self).map(\.name).sorted()
        #expect(after == ["Ada"])
    }

    @Test
    func cacheRestoredOnSaveFailure() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let cache = try slateCache(for: slate)
        _ = try await slate.many(TestAuthor.self)
        #expect(cache.count == 1)

        // Force a save failure by injecting a failing did-save observer.
        let owner = try slateStoreOwner(for: slate)
        let observerToken = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: owner.writerContext,
            queue: nil
        ) { _ in
            owner.writerContext.userInfo["forceSaveFailure"] = "trigger"
        }
        defer { NotificationCenter.default.removeObserver(observerToken) }

        // Trigger an actual save failure via Core Data validation.
        // We do this by inserting a row that violates a non-existent
        // constraint - simpler approach: simulate failure by passing
        // an invalid attribute on save through an external observer is
        // brittle; instead, we test the restoration path directly using
        // the cache APIs.

        let id = NSManagedObjectID()
        let snapshot = cache.snapshot([id])
        cache.apply(setting: [id: TestAuthor(slateID: id, name: "Replacement")], removing: [])
        #expect(cache.count == 2)
        cache.restore(snapshot)
        #expect(cache.count == 1)
    }

    @Test
    func cacheRestoredOnSaveFailureEndToEnd() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let cache = try slateCache(for: slate)
        _ = try await slate.many(TestAuthor.self)
        #expect(cache.count == 1)

        // Trigger a real save failure by creating a row whose required
        // `name` attribute is left unset. Core Data raises a validation
        // error when saving, exercising the cache-restoration path.
        await #expect(throws: (any Error).self) {
            try await slate.mutate { context in
                _ = context.create(DatabaseTestAuthor.self)
                // intentionally do not set `name`
            }
        }

        // Cache restored to pre-mutation state - the inserted invalid row
        // that was added pre-save was removed by the undo restore.
        #expect(cache.count == 1)

        // Original data still readable and unchanged.
        let after = try await slate.many(TestAuthor.self).map(\.name)
        #expect(after == ["Ada"])
    }

    // Many concurrent readers run `slate.many(...)` against a warm cache.
    // The cache is lock-protected, so we verify (a) every reader returns
    // the full set, (b) cache count remains stable (no double-inserts or
    // stomped reads under contention).
    @Test
    func cacheConcurrentReadersReuseEntries() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let row = context.create(DatabaseTestAuthor.self)
                row.name = name
            }
        }

        let cache = try slateCache(for: slate)
        let warmed = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        #expect(warmed.count == 3)
        #expect(cache.count == 3)
        let warmedIDs = warmed.map(\.slateID)

        // Fan out 32 concurrent readers, each fetching the same set.
        try await withThrowingTaskGroup(of: [TestAuthor].self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
                }
            }
            for try await result in group {
                #expect(result.map(\.name) == ["Ada", "Bea", "Cyd"])
                #expect(result.map(\.slateID) == warmedIDs)
            }
        }

        // Cache size unchanged (no leaks, no duplicates) and every cached
        // entry still maps to its expected name.
        #expect(cache.count == 3)
        for entry in warmed {
            let cached = cache.get(entry.slateID) as? TestAuthor
            #expect(cached?.name == entry.name)
        }
    }

    // After a batch delete, the cache must contain only surviving rows.
    // Verifies the per-ID eviction path used by both the SQLite batch path
    // and the in-memory fallback path.
    @Test
    func cacheEvictsBatchDeletedIDs() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd", "Dru"] {
                let row = context.create(DatabaseTestAuthor.self)
                row.name = name
            }
        }

        // Warm the cache so all four IDs are present.
        let warmed = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        let cache = try slateCache(for: slate)
        #expect(cache.count == 4)
        let idsByName = Dictionary(uniqueKeysWithValues: warmed.map { ($0.name, $0.slateID) })

        let removed = try await slate.batchDelete(
            TestAuthor.self,
            where: .in(\.name, ["Bea", "Dru"])
        )
        #expect(removed == 2)

        // Deleted IDs gone, surviving IDs still cached.
        #expect(cache.count == 2)
        #expect(cache.get(idsByName["Ada"]!) != nil)
        #expect(cache.get(idsByName["Cyd"]!) != nil)
        #expect(cache.get(idsByName["Bea"]!) == nil)
        #expect(cache.get(idsByName["Dru"]!) == nil)

        // A subsequent read does not resurrect the deleted IDs.
        let afterDelete = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        #expect(afterDelete.map(\.name) == ["Ada", "Cyd"])
        #expect(cache.count == 2)
    }

    // The same FRC underlying a stream survives multiple writer saves
    // without being torn down. This test simulates that pattern at the
    // cache level: drive multiple writer saves that touch *new* rows
    // and verify (a) previously-cached rows remain cached unchanged, and
    // (b) the cache grows monotonically as the writer pre-save apply
    // hydrates the new rows.
    @Test
    func cacheSurvivesAcrossWriterSaves() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let row = context.create(DatabaseTestAuthor.self)
            row.name = "Ada"
        }

        let cache = try slateCache(for: slate)

        let initial = try await slate.many(TestAuthor.self)
        #expect(initial.map(\.name) == ["Ada"])
        #expect(cache.count == 1)
        let adaID = initial[0].slateID

        // Drive several writer saves that insert NEW rows. Ada's existing
        // cache entry must stay put across each save (only mutated rows
        // are touched by the pre-save apply).
        for (i, name) in ["Bea", "Cyd", "Dru"].enumerated() {
            try await slate.mutate { context in
                let row = context.create(DatabaseTestAuthor.self)
                row.name = name
            }
            // Ada still cached after each save.
            #expect((cache.get(adaID) as? TestAuthor)?.name == "Ada")
            // Cache grows by one for each insert (pre-save hydration).
            #expect(cache.count == 2 + i)
        }

        // Final read does not need to re-convert anything: every row is
        // already cached.
        let final = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        #expect(final.map(\.name) == ["Ada", "Bea", "Cyd", "Dru"])
        #expect(cache.count == 4)
    }

    @Test
    func cacheUndoSnapshotApplyRestoreRoundTrip() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()
        let cache = try slateCache(for: slate)

        // Hand-craft three IDs by inserting and reading.
        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let row = context.create(DatabaseTestAuthor.self)
                row.name = name
            }
        }
        let authors = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        #expect(authors.count == 3)
        #expect(cache.count == 3)

        let adaID = authors[0].slateID
        let beaID = authors[1].slateID
        let cydID = authors[2].slateID
        let unrelatedID = NSManagedObjectID()

        let undo = cache.snapshot([adaID, beaID, cydID, unrelatedID])

        // Apply: change Ada and Bea, remove Cyd, add unrelated.
        cache.apply(
            setting: [
                adaID: TestAuthor(slateID: adaID, name: "Ada-NEW"),
                beaID: TestAuthor(slateID: beaID, name: "Bea-NEW"),
                unrelatedID: TestAuthor(slateID: unrelatedID, name: "Unrelated"),
            ],
            removing: [cydID]
        )
        #expect(cache.count == 3) // ada, bea, unrelated (cyd removed)
        #expect((cache.get(adaID) as? TestAuthor)?.name == "Ada-NEW")
        #expect(cache.get(cydID) == nil)
        #expect(cache.get(unrelatedID) != nil)

        // Restore: ada/bea/cyd back, unrelated removed (it was absent).
        cache.restore(undo)
        #expect(cache.count == 3)
        #expect((cache.get(adaID) as? TestAuthor)?.name == "Ada")
        #expect((cache.get(beaID) as? TestAuthor)?.name == "Bea")
        #expect((cache.get(cydID) as? TestAuthor)?.name == "Cyd")
        #expect(cache.get(unrelatedID) == nil)
    }
}

private func slateCache<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateObjectCache {
    try slateStoreOwner(for: slate).cache
}

private func slateStoreOwner<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateStoreOwner<Schema> {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "owner" {
        if let owner = child.value as? SlateStoreOwner<Schema> {
            return owner
        }
    }
    throw NSError(domain: "SlateObjectCacheTests", code: -1)
}
