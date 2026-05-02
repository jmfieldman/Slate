import CoreData
import Foundation
import Slate
import SlateSchema
import Testing

@MainActor
@Suite
struct SlateStreamTests {
    @Test
    func initialValuesAreLoaded() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)

        #expect(stream.state == .ready)
        #expect(stream.values.map(\.name) == ["Ada", "Bea", "Cyd"])
        stream.cancel()
    }

    @Test
    func streamUpdatesAfterInsert() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.isEmpty)

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        try await waitForValueCount(stream, equals: 1)
        #expect(stream.values.map(\.name) == ["Ada"])

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Bea"
        }

        try await waitForValueCount(stream, equals: 2)
        #expect(stream.values.map(\.name) == ["Ada", "Bea"])

        stream.cancel()
    }

    @Test
    func streamUpdatesAfterUpdate() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.map(\.name) == ["Ada"])

        try await slate.mutate { context in
            let table = context[DatabaseTestAuthor.self]
            if let row = try table.one() {
                row.name = "Bea"
            }
        }

        try await waitFor(stream) { $0.values.first?.name == "Bea" }
        stream.cancel()
    }

    @Test
    func streamShrinksOnDelete() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.count == 2)

        try await slate.mutate { context in
            _ = try context[DatabaseTestAuthor.self].delete(where: \.name == "Ada")
        }

        try await waitForValueCount(stream, equals: 1)
        #expect(stream.values.map(\.name) == ["Bea"])
        stream.cancel()
    }

    @Test
    func streamFiltersByPredicate() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.stream(
            TestAuthor.self,
            where: \.name != "Bea",
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.map(\.name) == ["Ada", "Cyd"])
        stream.cancel()
    }

    @Test
    func cancelStopsFurtherUpdates() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        stream.cancel()
        #expect(stream.state == .cancelled)

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(stream.values.isEmpty)
        #expect(stream.state == .cancelled)
    }

    @Test
    func valuesAsyncEmitsUpdates() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)

        var iterator = stream.valuesAsync.makeAsyncIterator()
        let initial = try await iterator.next()
        #expect(initial?.isEmpty == true)

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let next = try await iterator.next()
        #expect(next?.map(\.name) == ["Ada"])

        stream.cancel()
        let terminal = try await iterator.next()
        #expect(terminal == nil)
    }

    // `NSBatchDeleteRequest` bypasses `NSManagedObjectContextDidSave`, which
    // is the writer-context observer streams normally rely on. The store
    // owner instead notifies a per-stream batch-delete sink. This test
    // confirms the fallback (in-memory) path's natural didSave still drives
    // streams; `batchDeleteOnSQLiteStorePathDrivesStreams` covers the real
    // batch path.
    @Test
    func batchDeleteFallbackDrivesStreams() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.count == 3)

        _ = try await slate.batchDelete(
            TestAuthor.self,
            where: .in(\.name, ["Ada", "Cyd"])
        )

        try await waitForValueCount(stream, equals: 1)
        #expect(stream.values.map(\.name) == ["Bea"])
        stream.cancel()
    }

    @Test
    func batchDeleteOnSQLiteStorePathDrivesStreams() async throws {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("SlateBatchDeleteStreamTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("Stream.sqlite")
        let slate = Slate<TestSchema>(storeURL: storeURL, storeType: NSSQLiteStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.stream(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForReady(stream)
        #expect(stream.values.count == 3)

        _ = try await slate.batchDelete(
            TestAuthor.self,
            where: .in(\.name, ["Ada", "Cyd"])
        )

        try await waitForValueCount(stream, equals: 1)
        #expect(stream.values.map(\.name) == ["Bea"])
        stream.cancel()
        await slate.close()
    }

    @Test
    func backgroundStreamLoadsAndUpdates() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let stream = slate.streamBackground(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )

        try await waitForBackgroundReady(stream)
        let initialNames = await SlateStreamActor.shared.run { stream.values.map(\.name) }
        #expect(initialNames == ["Ada", "Bea"])

        try await slate.mutate { context in
            _ = try context[DatabaseTestAuthor.self].delete(where: \.name == "Ada")
        }

        try await waitForBackground(stream) { $0.values.count == 1 }
        let afterNames = await SlateStreamActor.shared.run { stream.values.map(\.name) }
        #expect(afterNames == ["Bea"])

        await SlateStreamActor.shared.run { stream.cancel() }
    }
}

@MainActor
private func waitForReady<V>(_ stream: SlateStream<V>) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while stream.state == .loading {
        if ContinuousClock.now > deadline {
            throw StreamWaitTimeout.timedOut
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
private func waitForValueCount<V>(_ stream: SlateStream<V>, equals count: Int) async throws {
    try await waitFor(stream) { $0.values.count == count }
}

@MainActor
private func waitFor<V>(_ stream: SlateStream<V>, condition: @MainActor (SlateStream<V>) -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(stream) {
        if ContinuousClock.now > deadline {
            throw StreamWaitTimeout.timedOut
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private func waitForBackgroundReady<V>(_ stream: SlateBackgroundStream<V>) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while await SlateStreamActor.shared.run({ stream.state == .loading }) {
        if ContinuousClock.now > deadline {
            throw StreamWaitTimeout.timedOut
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private func waitForBackground<V>(
    _ stream: SlateBackgroundStream<V>,
    condition: @SlateStreamActor @Sendable (SlateBackgroundStream<V>) -> Bool
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while await SlateStreamActor.shared.run({ condition(stream) }) == false {
        if ContinuousClock.now > deadline {
            throw StreamWaitTimeout.timedOut
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private enum StreamWaitTimeout: Error {
    case timedOut
}

extension SlateStreamActor {
    @SlateStreamActor
    fileprivate func run<T>(_ body: @SlateStreamActor () throws -> T) rethrows -> T {
        try body()
    }
}
