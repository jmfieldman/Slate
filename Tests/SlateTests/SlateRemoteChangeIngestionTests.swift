@preconcurrency import CoreData
import Foundation
import Testing
@testable import Slate

@Suite("Remote change ingestion")
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
