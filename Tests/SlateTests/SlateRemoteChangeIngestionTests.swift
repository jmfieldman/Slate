@preconcurrency import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite("Remote change ingestion", .serialized)
struct SlateRemoteChangeIngestionTests {
    @Test
    func missingHistoryTokenSidecarReturnsNil() throws {
        let directory = try SlateRemoteChangeIngestionTestSupport.temporaryDirectory(
            prefix: "SlateHistoryTokenMissing"
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SlateHistoryTokenStore(storeURL: directory.appendingPathComponent("Test.sqlite"))

        #expect(try store.load() == nil)
    }

    @Test
    func savedHistoryTokenRoundTripsThroughSidecar() throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateHistoryTokenRoundTrip"
        )
        defer {
            fixture.remove()
        }

        let token = try fixture.makeHistoryToken(authorName: "Ada")
        let store = SlateHistoryTokenStore(storeURL: fixture.storeURL)

        try store.save(token)

        let loadedToken = try #require(try store.load())
        #expect(try fixture.historyTransactionCount(after: loadedToken) == 0)
    }

    @Test
    func savingNilHistoryTokenRemovesSidecar() throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateHistoryTokenReset"
        )
        defer {
            fixture.remove()
        }

        let token = try fixture.makeHistoryToken(authorName: "Ada")
        let store = SlateHistoryTokenStore(storeURL: fixture.storeURL)

        try store.save(token)
        #expect(FileManager.default.fileExists(atPath: store.tokenURL.path))

        try store.save(nil)

        #expect(!FileManager.default.fileExists(atPath: store.tokenURL.path))
        #expect(try store.load() == nil)
    }

    @Test
    func standardizedStoreURLsDeriveStableDistinctSidecarURLs() throws {
        let directory = try SlateRemoteChangeIngestionTestSupport.temporaryDirectory(
            prefix: "SlateHistoryTokenURLs"
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let nestedDirectory = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )

        let canonicalStoreURL = directory.appendingPathComponent("Canonical.sqlite")
        let unstandardizedStoreURL = nestedDirectory
            .appendingPathComponent("..")
            .appendingPathComponent("Canonical.sqlite")
        let otherStoreURL = directory.appendingPathComponent("Other.sqlite")

        let canonicalStore = SlateHistoryTokenStore(storeURL: canonicalStoreURL)
        let unstandardizedStore = SlateHistoryTokenStore(storeURL: unstandardizedStoreURL)
        let otherStore = SlateHistoryTokenStore(storeURL: otherStoreURL)

        #expect(canonicalStore.tokenURL == unstandardizedStore.tokenURL)
        #expect(canonicalStore.tokenURL != otherStore.tokenURL)
    }

    @Test
    func localOwnersHaveNoRemoteChangeIngestor() throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)

        try slate.configure()

        #expect(try slateStoreOwner(for: slate).remoteChangeIngestor == nil)
    }

    @Test
    func cloudKitMirroredOwnerRetainsStartedIngestorAfterLoad() throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeCloudKitSlate(
            prefix: "SlateRemoteChangeIngestorRetained"
        )
        defer {
            fixture.remove()
        }

        try fixture.configureWithSuccessfulCloudKitLoad()

        let ingestor = try #require(try fixture.owner().remoteChangeIngestor)
        #expect(ingestor.isObservingForTesting)
    }

    @Test
    func stoppedIngestorIgnoresLaterRemoteChangeNotifications() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeCloudKitSlate(
            prefix: "SlateRemoteChangeIngestorStop"
        )
        defer {
            fixture.remove()
        }

        try fixture.configureWithSuccessfulCloudKitLoad()
        let owner = try fixture.owner()
        let ingestor = try #require(owner.remoteChangeIngestor)
        let counter = LockedCounter()
        ingestor.setIngestionHookForTesting {
            counter.increment()
        }

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: owner.coordinator
        )
        try await counter.waitForValue(1)

        ingestor.stop()
        #expect(!ingestor.isObservingForTesting)

        NotificationCenter.default.post(
            name: .NSPersistentStoreRemoteChange,
            object: owner.coordinator
        )
        try await Task.sleep(nanoseconds: 75_000_000)

        #expect(counter.value == 1)
    }

    @Test
    func testingIngestionWaitsForOwnerLoadReadiness() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeCloudKitSlate(
            prefix: "SlateRemoteChangeIngestorReadiness"
        )
        defer {
            fixture.remove()
        }
        let load = PausedCloudKitLoad()

        try fixture.configureWithPausedCloudKitLoad(load)
        let ingestor = try #require(try fixture.owner().remoteChangeIngestor)
        let enteredIngestion = LockedCounter()
        ingestor.setIngestionHookForTesting {
            enteredIngestion.increment()
        }

        let task = Task {
            try await ingestor.ingestRemoteChangeForTesting()
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(enteredIngestion.value == 0)

        try load.succeed()
        try await task.value

        #expect(enteredIngestion.value == 1)
    }

    @Test
    func firstHistoryFetchWithoutTokenIncludesInsertedUpdatedAndDeletedRows() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateHistoryFetchChanges"
        )
        defer {
            fixture.remove()
        }

        let changedIDs = try fixture.writeInsertedUpdatedAndDeletedRowsFromSecondContext()

        let window = try await fixture.ingestor.fetchPersistentHistoryForTesting()

        #expect(window.transactions.count >= 4)
        #expect(window.mergeNotificationPayloads.count == window.transactions.count)
        #expect(window.changedObjectIDs.isSuperset(of: changedIDs.all))
        #expect(window.changedObjectIDs.contains(changedIDs.inserted))
        #expect(window.changedObjectIDs.contains(changedIDs.updated))
        #expect(window.changedObjectIDs.contains(changedIDs.deleted))
        #expect(window.nextToken != nil)
        #expect(try fixture.tokenStore.load() == nil)
    }

    @Test
    func historyFetchAfterSavedTokenReturnsEmptyWindow() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateHistoryFetchAfterToken"
        )
        defer {
            fixture.remove()
        }

        _ = try fixture.writeInsertedUpdatedAndDeletedRowsFromSecondContext()
        let firstWindow = try await fixture.ingestor.fetchPersistentHistoryForTesting()
        try fixture.tokenStore.save(firstWindow.nextToken)

        let secondWindow = try await fixture.ingestor.fetchPersistentHistoryForTesting()

        #expect(secondWindow.transactions.isEmpty)
        #expect(secondWindow.mergeNotificationPayloads.isEmpty)
        #expect(secondWindow.changedObjectIDs.isEmpty)
        #expect(secondWindow.nextToken == nil)
    }

    @Test
    func ingestionSetsIsMergingDuringBarrierHeldMergeAndPersistsTokenAfterSuccess() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateRemoteMergeStateSuccess"
        )
        defer {
            fixture.remove()
        }

        _ = try fixture.writeInsertedUpdatedAndDeletedRowsFromSecondContext()
        let observedMergeState = LockedCounter()
        fixture.ingestor.setMergeHookForTesting {
            #expect(fixture.owner.isMerging)
            observedMergeState.increment()
        }

        #expect(!fixture.owner.isMerging)

        try await fixture.ingestor.ingestRemoteChangeForTesting()

        #expect(observedMergeState.value == 1)
        #expect(!fixture.owner.isMerging)
        let token = try #require(try fixture.tokenStore.load())
        #expect(try fixture.historyTransactionCount(after: token) == 0)
    }

    @Test
    func ingestionRestoresIsMergingAndLeavesTokenAfterInjectedMergeFailure() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateRemoteMergeStateFailure"
        )
        defer {
            fixture.remove()
        }

        _ = try fixture.writeInsertedUpdatedAndDeletedRowsFromSecondContext()
        fixture.ingestor.setMergeHookForTesting {
            #expect(fixture.owner.isMerging)
            throw InjectedMergeFailure()
        }

        await #expect(throws: InjectedMergeFailure.self) {
            try await fixture.ingestor.ingestRemoteChangeForTesting()
        }

        #expect(!fixture.owner.isMerging)
        #expect(try fixture.tokenStore.load() == nil)
        #expect(try fixture.historyTransactionCount(after: nil) > 0)
    }

    @Test
    func localMutationAndRemoteIngestionCriticalSectionsDoNotOverlap() async throws {
        let fixture = try SlateRemoteChangeIngestionTestSupport.makeHistoryFixture(
            prefix: "SlateRemoteMergeGateOrdering"
        )
        defer {
            fixture.remove()
        }

        _ = try fixture.writeInsertedUpdatedAndDeletedRowsFromSecondContext()
        let tracker = CriticalSectionTracker()
        fixture.ingestor.setMergeHookForTesting {
            tracker.enter("ingestion")
            tracker.exit("ingestion")
        }

        let mutationTask = Task {
            try await fixture.runLocalWriterCriticalSectionForTesting {
                tracker.enter("mutation")
                Thread.sleep(forTimeInterval: 0.05)
                tracker.exit("mutation")
            }
        }

        try await tracker.waitForEntryCount(1)

        let ingestionTask = Task {
            try await fixture.ingestor.ingestRemoteChangeForTesting()
        }

        try await mutationTask.value
        try await ingestionTask.value

        #expect(tracker.entryCount == 2)
        #expect(!tracker.didOverlap)
    }
}

struct HistoryChangeIDs: Sendable {
    let inserted: NSManagedObjectID
    let updated: NSManagedObjectID
    let deleted: NSManagedObjectID

    var all: Set<NSManagedObjectID> {
        [inserted, updated, deleted]
    }
}

enum SlateRemoteChangeIngestionTestSupport {
    static func temporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func makeHistoryFixture(prefix: String) throws -> HistoryFixture {
        let directory = try temporaryDirectory(prefix: prefix)
        let storeURL = directory.appendingPathComponent("Test.sqlite")
        do {
            return try HistoryFixture(directory: directory, storeURL: storeURL)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func makeCloudKitSlate(prefix: String) throws -> CloudKitSlateFixture {
        let directory = try temporaryDirectory(prefix: prefix)
        let storeURL = directory.appendingPathComponent("Test.sqlite")
        let slate = Slate<TestCloudKitSchema>(
            storeURL: storeURL,
            storeType: NSSQLiteStoreType,
            storageMode: .cloudKitMirrored(containerIdentifier: "iCloud.com.example")
        )
        return CloudKitSlateFixture(directory: directory, slate: slate)
    }

    final class HistoryFixture: @unchecked Sendable {
        let directory: URL
        let storeURL: URL
        let tokenStore: SlateHistoryTokenStore
        let owner: SlateStoreOwner<TestCloudKitRuntimeSchema>
        let ingestor: SlateRemoteChangeIngestor<TestCloudKitRuntimeSchema>

        private let coordinator: NSPersistentStoreCoordinator
        private let writerContext: NSManagedObjectContext
        private let secondContext: NSManagedObjectContext

        init(directory: URL, storeURL: URL) throws {
            self.directory = directory
            self.storeURL = storeURL
            self.tokenStore = SlateHistoryTokenStore(storeURL: storeURL)

            coordinator = NSPersistentStoreCoordinator(
                managedObjectModel: try TestCloudKitRuntimeSchema.makeManagedObjectModel()
            )

            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

            var capturedError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            coordinator.addPersistentStore(with: description) { _, error in
                capturedError = error
                semaphore.signal()
            }
            semaphore.wait()

            if let capturedError {
                throw capturedError
            }

            writerContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            writerContext.persistentStoreCoordinator = coordinator
            writerContext.undoManager = nil
            writerContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            secondContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            secondContext.persistentStoreCoordinator = coordinator
            secondContext.undoManager = nil
            secondContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            var registry = SlateTableRegistry()
            TestCloudKitRuntimeSchema.registerTables(&registry)
            owner = SlateStoreOwner<TestCloudKitRuntimeSchema>(
                registry: registry,
                coordinator: coordinator,
                writerContext: writerContext,
                storageMode: .cloudKitMirrored(containerIdentifier: "iCloud.com.example"),
                loadState: .loaded
            )
            ingestor = SlateRemoteChangeIngestor(
                owner: owner,
                tokenStore: tokenStore
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        func makeHistoryToken(authorName: String) throws -> NSPersistentHistoryToken {
            try secondContext.performAndWaitReturning {
                let record = DatabaseTestCloudKitRuntimeRecord.create(in: secondContext)
                record.title = authorName
                try secondContext.save()
            }

            return try latestHistoryToken()
        }

        func writeInsertedUpdatedAndDeletedRowsFromSecondContext() throws -> HistoryChangeIDs {
            try secondContext.performAndWaitReturning {
                let inserted = DatabaseTestCloudKitRuntimeRecord.create(in: secondContext)
                inserted.title = "Inserted"
                try secondContext.save()
                let insertedID = inserted.objectID

                let updated = DatabaseTestCloudKitRuntimeRecord.create(in: secondContext)
                updated.title = "Before update"
                try secondContext.save()
                let updatedID = updated.objectID

                updated.title = "After update"
                try secondContext.save()

                let deleted = DatabaseTestCloudKitRuntimeRecord.create(in: secondContext)
                deleted.title = "Deleted"
                try secondContext.save()
                let deletedID = deleted.objectID

                secondContext.delete(deleted)
                try secondContext.save()

                return HistoryChangeIDs(
                    inserted: insertedID,
                    updated: updatedID,
                    deleted: deletedID
                )
            }
        }

        func historyTransactionCount(after token: NSPersistentHistoryToken?) throws -> Int {
            let tokenBox = UncheckedPersistentHistoryToken(token)
            return try writerContext.performAndWaitReturning {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: tokenBox.value)
                request.resultType = .transactionsOnly
                let result = try #require(
                    try writerContext.execute(request) as? NSPersistentHistoryResult
                )
                let transactions = (result.result as? [NSPersistentHistoryTransaction]) ?? []
                return transactions.count
            }
        }

        func runLocalWriterCriticalSectionForTesting(
            _ body: @Sendable @escaping () throws -> Void
        ) async throws {
            try await owner.accessGate.write {
                try await writerContext.slatePerform {
                    try body()
                }
            }
        }

        private func latestHistoryToken() throws -> NSPersistentHistoryToken {
            try writerContext.performAndWaitReturning {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(
                    after: nil as NSPersistentHistoryToken?
                )
                request.resultType = .transactionsOnly
                let result = try #require(
                    try writerContext.execute(request) as? NSPersistentHistoryResult
                )
                let transactions = try #require(result.result as? [NSPersistentHistoryTransaction])
                let transaction = try #require(transactions.last)
                return transaction.token
            }
        }
    }

    final class CloudKitSlateFixture: @unchecked Sendable {
        let directory: URL
        let slate: Slate<TestCloudKitSchema>

        init(directory: URL, slate: Slate<TestCloudKitSchema>) {
            self.directory = directory
            self.slate = slate
        }

        func configureWithSuccessfulCloudKitLoad() throws {
            try SlateCloudKitContainer.withLoadPersistentStoresOverride({ container, completion in
                do {
                    try Self.installDeterministicStore(in: container)
                    completion(nil)
                } catch {
                    completion(error)
                }
            }) {
                try slate.configure()
            }
        }

        fileprivate func configureWithPausedCloudKitLoad(_ load: PausedCloudKitLoad) throws {
            try SlateCloudKitContainer.withLoadPersistentStoresOverride({ container, completion in
                load.capture(container: container, completion: completion)
            }) {
                try slate.configure()
            }
            try load.requireCaptured()
        }

        func owner() throws -> SlateStoreOwner<TestCloudKitSchema> {
            try slateStoreOwner(for: slate)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        fileprivate static func installDeterministicStore(in container: NSPersistentCloudKitContainer) throws {
            guard container.persistentStoreCoordinator.persistentStores.isEmpty else {
                return
            }
            let sourceDescription = try #require(container.persistentStoreDescriptions.first)
            let description = NSPersistentStoreDescription()
            description.type = sourceDescription.type
            description.url = sourceDescription.url
            description.shouldMigrateStoreAutomatically = sourceDescription.shouldMigrateStoreAutomatically
            description.shouldInferMappingModelAutomatically = sourceDescription.shouldInferMappingModelAutomatically
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )

            var capturedError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            container.persistentStoreCoordinator.addPersistentStore(with: description) { _, error in
                capturedError = error
                semaphore.signal()
            }
            semaphore.wait()

            if let capturedError {
                throw capturedError
            }
        }
    }
}

private struct InjectedMergeFailure: Error, Equatable {}

private final class CriticalSectionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var activeName: String?
    private var storedDidOverlap = false
    private var storedEntryCount = 0

    var didOverlap: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedDidOverlap
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedEntryCount
    }

    func enter(_ name: String) {
        lock.lock()
        if activeName != nil {
            storedDidOverlap = true
        }
        activeName = name
        storedEntryCount += 1
        lock.unlock()
    }

    func exit(_ name: String) {
        lock.lock()
        if activeName != name {
            storedDidOverlap = true
        }
        activeName = nil
        lock.unlock()
    }

    func waitForEntryCount(_ expectedCount: Int) async throws {
        for _ in 0..<40 {
            if entryCount >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for entry count \(expectedCount); current value \(entryCount)")
    }
}

private func slateStoreOwner<Schema: SlateSchema>(for slate: Slate<Schema>) throws -> SlateStoreOwner<Schema> {
    let mirror = Mirror(reflecting: slate)
    for child in mirror.children where child.label == "owner" {
        if let owner = child.value as? SlateStoreOwner<Schema> {
            return owner
        }
    }
    throw NSError(domain: "SlateRemoteChangeIngestionTests", code: -1)
}

private final class PausedCloudKitLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedContainer: NSPersistentCloudKitContainer?
    private var capturedCompletion: ((Error?) -> Void)?

    func capture(
        container: NSPersistentCloudKitContainer,
        completion: @escaping (Error?) -> Void
    ) {
        lock.lock()
        precondition(capturedCompletion == nil, "CloudKit load was captured more than once")
        capturedContainer = container
        capturedCompletion = completion
        lock.unlock()
    }

    func requireCaptured() throws {
        lock.lock()
        let hasCompletion = capturedCompletion != nil
        lock.unlock()
        if !hasCompletion {
            throw NSError(
                domain: "SlateRemoteChangeIngestionTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit load was not captured"]
            )
        }
    }

    func succeed() throws {
        let (container, completion) = try capturedLoad()
        try SlateRemoteChangeIngestionTestSupport.CloudKitSlateFixture.installDeterministicStore(in: container)
        completion(nil)
    }

    private func capturedLoad() throws -> (NSPersistentCloudKitContainer, (Error?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let capturedContainer, let capturedCompletion else {
            throw NSError(
                domain: "SlateRemoteChangeIngestionTests",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "CloudKit load has not started"]
            )
        }
        self.capturedContainer = nil
        self.capturedCompletion = nil
        return (capturedContainer, capturedCompletion)
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

    func waitForValue(_ expectedValue: Int) async throws {
        for _ in 0..<40 {
            if value >= expectedValue {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for counter to reach \(expectedValue); current value \(value)")
    }
}

private struct UncheckedPersistentHistoryToken: @unchecked Sendable {
    let value: NSPersistentHistoryToken?

    init(_ value: NSPersistentHistoryToken?) {
        self.value = value
    }
}

private extension NSManagedObjectContext {
    func performAndWaitReturning<T>(_ work: @Sendable () throws -> T) throws -> T {
        nonisolated(unsafe) var result: Result<T, Error>?
        performAndWait {
            result = Result {
                try work()
            }
        }
        return try result!.get()
    }
}
