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

        private let coordinator: NSPersistentStoreCoordinator
        private let context: NSManagedObjectContext

        init(directory: URL, storeURL: URL) throws {
            self.directory = directory
            self.storeURL = storeURL

            coordinator = NSPersistentStoreCoordinator(
                managedObjectModel: try TestSchema.makeManagedObjectModel()
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

            context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            context.undoManager = nil
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        func makeHistoryToken(authorName: String) throws -> NSPersistentHistoryToken {
            try context.performAndWaitReturning {
                let author = DatabaseTestAuthor.create(in: context)
                author.name = authorName
                try context.save()
            }

            return try latestHistoryToken()
        }

        func historyTransactionCount(after token: NSPersistentHistoryToken?) throws -> Int {
            let tokenBox = UncheckedPersistentHistoryToken(token)
            return try context.performAndWaitReturning {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: tokenBox.value)
                request.resultType = .transactionsOnly
                let result = try #require(
                    try context.execute(request) as? NSPersistentHistoryResult
                )
                let transactions = (result.result as? [NSPersistentHistoryTransaction]) ?? []
                return transactions.count
            }
        }

        private func latestHistoryToken() throws -> NSPersistentHistoryToken {
            try context.performAndWaitReturning {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(
                    after: nil as NSPersistentHistoryToken?
                )
                request.resultType = .transactionsOnly
                let result = try #require(
                    try context.execute(request) as? NSPersistentHistoryResult
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
