import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@MainActor
@Suite
struct SlateStreamTests {
    @Test
    func initialValuesAreLoaded() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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
        try slate.configure()

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

    @Test
    func lazyMainStreamBindsAfterLoadingCompletesAndEmitsInitialValues() async throws {
        let loading = LockedBoolean(true)
        let builderCalls = LockedCounter()
        let stream = SlateStream<TestAuthor>(
            loading: {
                loading.value
            },
            coreBuilder: {
                builderCalls.increment()
                return try makeTestAuthorStreamCore(initialNames: ["Ada", "Bea"])
            }
        )

        var iterator = stream.valuesAsync.makeAsyncIterator()
        let loadingValues = try await iterator.next()
        #expect(loadingValues?.isEmpty == true)

        try await Task.sleep(for: .milliseconds(70))
        #expect(stream.state == .loading)
        #expect(builderCalls.value == 0)

        loading.set(false)
        try await waitForReady(stream)

        #expect(stream.state == .ready)
        #expect(builderCalls.value == 1)
        #expect(stream.values.map(\.name) == ["Ada", "Bea"])

        let readyValues = try await iterator.next()
        #expect(readyValues?.map(\.name) == ["Ada", "Bea"])

        stream.cancel()
        let terminal = try await iterator.next()
        #expect(terminal == nil)
    }

    @Test
    func lazyBackgroundStreamBindsAfterLoadingCompletesAndEmitsInitialValues() async throws {
        let loading = LockedBoolean(true)
        let builderCalls = LockedCounter()
        let stream = SlateBackgroundStream<TestAuthor>(
            loading: {
                loading.value
            },
            coreBuilder: {
                builderCalls.increment()
                return try makeTestAuthorStreamCore(initialNames: ["Ada", "Bea"])
            }
        )

        try await Task.sleep(for: .milliseconds(70))
        let loadingState = await SlateStreamActor.shared.run { stream.state }
        #expect(loadingState == .loading)
        #expect(builderCalls.value == 0)

        loading.set(false)
        try await waitForBackgroundReady(stream)

        let readyState = await SlateStreamActor.shared.run { stream.state }
        let names = await SlateStreamActor.shared.run { stream.values.map(\.name) }
        #expect(readyState == .ready)
        #expect(builderCalls.value == 1)
        #expect(names == ["Ada", "Bea"])

        await SlateStreamActor.shared.run { stream.cancel() }
    }

    @Test
    func lazyMainStreamDefersBuilderUntilLoadingCompletesAndSurfacesFailure() async throws {
        let loading = LockedBoolean(true)
        let builderCalls = LockedCounter()
        let stream = SlateStream<TestAuthor>(
            loading: {
                loading.value
            },
            coreBuilder: {
                builderCalls.increment()
                throw SlateError.coreData("builder failed")
            }
        )

        var iterator = stream.valuesAsync.makeAsyncIterator()
        let loadingValues = try await iterator.next()
        #expect(loadingValues?.isEmpty == true)

        try await Task.sleep(for: .milliseconds(70))
        #expect(stream.state == .loading)
        #expect(builderCalls.value == 0)

        loading.set(false)
        try await waitFor(stream) { $0.state == .failed }
        #expect(builderCalls.value == 1)
        #expect(stream.error != nil)
        do {
            _ = try await iterator.next()
            Issue.record("Expected valuesAsync to finish with the builder error")
        } catch {
            #expect(error as? SlateError == .coreData("builder failed"))
        }
    }

    @Test
    func lazyBackgroundStreamDefersBuilderUntilLoadingCompletesAndSurfacesFailure() async throws {
        let loading = LockedBoolean(true)
        let builderCalls = LockedCounter()
        let stream = SlateBackgroundStream<TestAuthor>(
            loading: {
                loading.value
            },
            coreBuilder: {
                builderCalls.increment()
                throw SlateError.coreData("builder failed")
            }
        )

        let valuesAsync = await SlateStreamActor.shared.run { stream.valuesAsync }
        var iterator = valuesAsync.makeAsyncIterator()
        let loadingValues = try await iterator.next()
        #expect(loadingValues?.isEmpty == true)

        try await Task.sleep(for: .milliseconds(70))
        let loadingState = await SlateStreamActor.shared.run { stream.state }
        #expect(loadingState == .loading)
        #expect(builderCalls.value == 0)

        loading.set(false)
        try await waitForBackground(stream) { $0.state == .failed }
        #expect(builderCalls.value == 1)
        let error = await SlateStreamActor.shared.run { stream.error }
        #expect(error != nil)
        do {
            _ = try await iterator.next()
            Issue.record("Expected background valuesAsync to finish with the builder error")
        } catch {
            #expect(error as? SlateError == .coreData("builder failed"))
        }
    }

    @Test
    func cancelledLazyMainStreamDoesNotBuildAfterReadiness() async throws {
        let loading = LockedBoolean(true)
        let builderCalls = LockedCounter()
        let stream = SlateStream<TestAuthor>(
            loading: {
                loading.value
            },
            coreBuilder: {
                builderCalls.increment()
                throw SlateError.coreData("unexpected builder call")
            }
        )

        var iterator = stream.valuesAsync.makeAsyncIterator()
        let loadingValues = try await iterator.next()
        #expect(loadingValues?.isEmpty == true)

        try await Task.sleep(for: .milliseconds(20))
        stream.cancel()
        loading.set(false)
        try await Task.sleep(for: .milliseconds(70))

        #expect(stream.state == .cancelled)
        #expect(builderCalls.value == 0)
        let terminal = try await iterator.next()
        #expect(terminal == nil)
    }

    @Test
    func droppedLazyMainStreamStopsPolling() async throws {
        let loadingCalls = LockedCounter()
        weak var releasedStream: SlateStream<TestAuthor>?

        var stream: SlateStream<TestAuthor>? = SlateStream(
            loading: {
                loadingCalls.increment()
                return true
            },
            coreBuilder: {
                throw SlateError.coreData("unexpected builder call")
            }
        )
        releasedStream = stream
        stream = nil

        try await waitUntilReleased { releasedStream == nil }
        try await Task.sleep(for: .milliseconds(100))
        let countAfterRelease = loadingCalls.value
        try await Task.sleep(for: .milliseconds(120))

        #expect(loadingCalls.value == countAfterRelease)
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

private func makeTestAuthorStreamCore(initialNames: [String]) throws -> SlateStreamCore<TestAuthor> {
    let model = try TestSchema.makeManagedObjectModel()
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    try coordinator.addPersistentStore(
        ofType: NSInMemoryStoreType,
        configurationName: nil,
        at: nil
    )

    let writerContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    writerContext.persistentStoreCoordinator = coordinator
    writerContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

    try writerContext.performAndWait {
        for name in initialNames {
            let author = DatabaseTestAuthor.create(in: writerContext)
            author.name = name
        }
        try writerContext.save()
    }

    let streamContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    streamContext.persistentStoreCoordinator = coordinator
    streamContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

    let request = NSFetchRequest<NSFetchRequestResult>(entityName: DatabaseTestAuthor.slateEntityName)
    request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

    let controller = NSFetchedResultsController(
        fetchRequest: request,
        managedObjectContext: streamContext,
        sectionNameKeyPath: nil,
        cacheName: nil
    )

    return SlateStreamCore(
        context: streamContext,
        frc: controller,
        convert: { object in
            guard let author = object as? DatabaseTestAuthor else {
                throw SlateError.coreData("Unexpected stream object \(type(of: object))")
            }
            return author.slateObject
        },
        writerContext: writerContext
    )
}

private enum StreamWaitTimeout: Error {
    case timedOut
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

@MainActor
private func waitUntilReleased(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
        if ContinuousClock.now > deadline {
            throw StreamWaitTimeout.timedOut
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

extension SlateStreamActor {
    @SlateStreamActor
    fileprivate func run<T>(_ body: @SlateStreamActor () throws -> T) rethrows -> T {
        try body()
    }
}
