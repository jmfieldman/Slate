@preconcurrency import CoreData
import Foundation
import SlateSchema

struct SlateRemoteChangeHistoryWindow {
    let transactions: [NSPersistentHistoryTransaction]
    let mergeNotificationPayloads: [[AnyHashable: Any]]
    let changedObjectIDs: Set<NSManagedObjectID>
    let nextToken: NSPersistentHistoryToken?

    var isEmpty: Bool {
        transactions.isEmpty && changedObjectIDs.isEmpty
    }
}

final class SlateRemoteChangeIngestor<Schema: SlateSchema>: @unchecked Sendable {
    private weak var owner: SlateStoreOwner<Schema>?
    private let tokenStore: SlateHistoryTokenStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var ingestionHookForTesting: (@Sendable () -> Void)?

    init(
        owner: SlateStoreOwner<Schema>,
        tokenStore: SlateHistoryTokenStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.owner = owner
        self.tokenStore = tokenStore
        self.notificationCenter = notificationCenter
    }

    deinit {
        stop()
    }

    func start() {
        guard let coordinator = owner?.coordinator else {
            return
        }

        lock.lock()
        if observer != nil {
            lock.unlock()
            return
        }
        let newObserver = notificationCenter.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: nil
        ) { [weak self] _ in
            self?.ingestRemoteChangeFromNotification()
        }
        observer = newObserver
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let currentObserver = observer
        observer = nil
        lock.unlock()

        if let currentObserver {
            notificationCenter.removeObserver(currentObserver)
        }
    }

    func ingestRemoteChangeForTesting() async throws {
        try await ingestRemoteChange()
    }

    func fetchPersistentHistoryForTesting() async throws -> SlateRemoteChangeHistoryWindow {
        try await fetchPersistentHistory()
    }

    func setIngestionHookForTesting(_ hook: (@Sendable () -> Void)?) {
        lock.lock()
        ingestionHookForTesting = hook
        lock.unlock()
    }

    var isObservingForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    private func ingestRemoteChangeFromNotification() {
        Task { [weak self] in
            try? await self?.ingestRemoteChange()
        }
    }

    private func ingestRemoteChange() async throws {
        _ = try await fetchPersistentHistory()

        currentIngestionHookForTesting()?()
    }

    private func fetchPersistentHistory() async throws -> SlateRemoteChangeHistoryWindow {
        let owner = try await requireLoadedOwner()
        let token = SlateUncheckedPersistentHistoryToken(try tokenStore.load())
        let targetStore = try targetStore(in: owner)
        let targetStoreBox = SlateUncheckedPersistentStore(targetStore)

        return try await owner.writerContext.slatePerform {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token.value)
            request.resultType = .transactionsAndChanges
            request.affectedStores = [targetStoreBox.value]

            guard let result = try owner.writerContext.execute(request) as? NSPersistentHistoryResult else {
                throw SlateError.coreData("Persistent history fetch returned an unexpected result")
            }

            let transactions = (result.result as? [NSPersistentHistoryTransaction]) ?? []
            var changedObjectIDs = Set<NSManagedObjectID>()
            var mergeNotificationPayloads: [[AnyHashable: Any]] = []

            for transaction in transactions {
                let payload = transaction.objectIDNotification().userInfo ?? [:]
                mergeNotificationPayloads.append(payload)
                changedObjectIDs.formUnion(Self.changedObjectIDs(from: transaction, payload: payload))
            }

            return SlateRemoteChangeHistoryWindow(
                transactions: transactions,
                mergeNotificationPayloads: mergeNotificationPayloads,
                changedObjectIDs: changedObjectIDs,
                nextToken: transactions.last?.token
            )
        }
    }

    private func targetStore(in owner: SlateStoreOwner<Schema>) throws -> NSPersistentStore {
        let matchingStore = owner.coordinator.persistentStores.first { store in
            store.url?.standardizedFileURL == tokenStore.storeURL
        }
        if let matchingStore {
            return matchingStore
        }

        throw SlateError.coreData(
            "No loaded persistent store matches history token URL \(tokenStore.storeURL.path)"
        )
    }

    private static func changedObjectIDs(
        from transaction: NSPersistentHistoryTransaction,
        payload: [AnyHashable: Any]
    ) -> Set<NSManagedObjectID> {
        var ids = Set<NSManagedObjectID>()

        if let changes = transaction.changes {
            for change in changes {
                ids.insert(change.changedObjectID)
            }
        }

        for key in [NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey, NSDeletedObjectIDsKey] {
            if let set = payload[key] as? Set<NSManagedObjectID> {
                ids.formUnion(set)
            } else if let array = payload[key] as? [NSManagedObjectID] {
                ids.formUnion(array)
            }
        }

        return ids
    }

    private func currentIngestionHookForTesting() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let hook = ingestionHookForTesting
        return hook
    }

    private func requireLoadedOwner() async throws -> SlateStoreOwner<Schema> {
        while true {
            guard let owner else {
                throw SlateError.closed
            }

            switch owner.loadState {
            case .loaded:
                return owner
            case .failed(let error):
                throw error.slateError
            case .loading:
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

private struct SlateUncheckedPersistentHistoryToken: @unchecked Sendable {
    let value: NSPersistentHistoryToken?

    init(_ value: NSPersistentHistoryToken?) {
        self.value = value
    }
}

private struct SlateUncheckedPersistentStore: @unchecked Sendable {
    let value: NSPersistentStore

    init(_ value: NSPersistentStore) {
        self.value = value
    }
}
