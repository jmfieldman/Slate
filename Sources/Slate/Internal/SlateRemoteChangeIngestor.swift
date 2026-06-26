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
    private var mergeHookForTesting: (@Sendable () throws -> Void)?

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

    func setMergeHookForTesting(_ hook: (@Sendable () throws -> Void)?) {
        lock.lock()
        mergeHookForTesting = hook
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
        let owner = try await requireLoadedOwner()

        try await owner.accessGate.write {
            owner.setIsMerging(true)
            defer {
                owner.setIsMerging(false)
            }

            do {
                let window = try await fetchPersistentHistory(for: owner)
                guard !window.isEmpty else {
                    return
                }

                try await applyMerge(window, to: owner)
                if let nextToken = window.nextToken {
                    try tokenStore.save(nextToken)
                }
            } catch {
                try? await owner.writerContext.slatePerform {
                    owner.writerContext.rollback()
                }
                throw error
            }
        }

        currentIngestionHookForTesting()?()
    }

    private func fetchPersistentHistory() async throws -> SlateRemoteChangeHistoryWindow {
        let owner = try await requireLoadedOwner()
        return try await fetchPersistentHistory(for: owner)
    }

    private func fetchPersistentHistory(
        for owner: SlateStoreOwner<Schema>
    ) async throws -> SlateRemoteChangeHistoryWindow {
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

    private func applyMerge(
        _ window: SlateRemoteChangeHistoryWindow,
        to owner: SlateStoreOwner<Schema>
    ) async throws {
        let payloads = SlateUncheckedMergePayloads(window.mergeNotificationPayloads)

        try await owner.writerContext.slatePerform {
            do {
                try self.currentMergeHookForTesting()?()

                for payload in payloads.value {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: payload,
                        into: [owner.writerContext]
                    )
                }
            } catch {
                owner.writerContext.rollback()
                throw error
            }
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

    private func currentMergeHookForTesting() -> (@Sendable () throws -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let hook = mergeHookForTesting
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

private struct SlateUncheckedMergePayloads: @unchecked Sendable {
    let value: [[AnyHashable: Any]]

    init(_ value: [[AnyHashable: Any]]) {
        self.value = value
    }
}
