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

struct SlateRemoteChangeIngestionSlot: Sendable {
    let storeURL: URL
    let tokenStore: SlateHistoryTokenStore

    init(storeURL: URL) {
        self.storeURL = storeURL.standardizedFileURL
        self.tokenStore = SlateHistoryTokenStore(storeURL: storeURL)
    }
}

private struct SlateResolvedRemoteChangeIngestionSlot {
    let storeURL: URL
    let store: NSPersistentStore
    let tokenStore: SlateHistoryTokenStore
}

final class SlateRemoteChangeIngestor<Schema: SlateSchema>: @unchecked Sendable {
    private weak var owner: SlateStoreOwner<Schema>?
    private let configuredSlots: [SlateRemoteChangeIngestionSlot]
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var ingestionHookForTesting: (@Sendable () -> Void)?
    private var ingestionStoreURLHookForTesting: (@Sendable (URL?) -> Void)?
    private var mergeHookForTesting: (@Sendable () throws -> Void)?

    init(
        owner: SlateStoreOwner<Schema>,
        storeURLs: [URL],
        notificationCenter: NotificationCenter = .default
    ) {
        self.owner = owner
        self.configuredSlots = storeURLs.map(SlateRemoteChangeIngestionSlot.init(storeURL:))
        self.notificationCenter = notificationCenter
    }

    convenience init(
        owner: SlateStoreOwner<Schema>,
        tokenStore: SlateHistoryTokenStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            owner: owner,
            storeURLs: [tokenStore.storeURL],
            notificationCenter: notificationCenter
        )
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
        try await ingestRemoteChange(storeURL: nil)
    }

    func ingestRemoteChange(forStoreURL storeURL: URL) async throws {
        try await ingestRemoteChange(storeURL: storeURL)
    }

    func fetchPersistentHistoryForTesting() async throws -> SlateRemoteChangeHistoryWindow {
        try await fetchPersistentHistory(storeURL: nil)
    }

    func fetchPersistentHistoryForTesting(storeURL: URL) async throws -> SlateRemoteChangeHistoryWindow {
        try await fetchPersistentHistory(storeURL: storeURL)
    }

    func setIngestionHookForTesting(_ hook: (@Sendable () -> Void)?) {
        lock.lock()
        ingestionHookForTesting = hook
        lock.unlock()
    }

    func setIngestionStoreURLHookForTesting(_ hook: (@Sendable (URL?) -> Void)?) {
        lock.lock()
        ingestionStoreURLHookForTesting = hook
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

    var slotStoreURLsForTesting: [URL] {
        configuredSlots.map(\.storeURL)
    }

    func resolvedSlotStoreURLsForTesting() async throws -> [URL] {
        let owner = try await requireLoadedOwner()
        return try resolvedSlots(in: owner).map(\.storeURL)
    }

    private func ingestRemoteChangeFromNotification() {
        Task { [weak self] in
            try? await self?.ingestRemoteChange(storeURL: nil)
        }
    }

    private func ingestRemoteChange(storeURL: URL?) async throws {
        let owner = try await requireLoadedOwner()
        let slots = try resolvedSlots(in: owner)
        let selectedSlots: [SlateResolvedRemoteChangeIngestionSlot]
        if let storeURL {
            let standardizedURL = storeURL.standardizedFileURL
            guard let slot = slots.first(where: { $0.storeURL == standardizedURL }) else {
                throw SlateError.coreData(
                    "No remote-change ingestion slot matches store URL \(standardizedURL.path)"
                )
            }
            selectedSlots = [slot]
        } else {
            selectedSlots = slots
        }

        try await owner.accessGate.write {
            do {
                for slot in selectedSlots {
                    let window = try await fetchPersistentHistory(for: owner, slot: slot)
                    guard !window.isEmpty else {
                        continue
                    }

                    do {
                        owner.setIsMerging(true)
                        defer {
                            owner.setIsMerging(false)
                        }

                        try await applyMerge(window, to: owner)
                        owner.cache.remove(window.changedObjectIDs)
                        owner.notifyStreamsRefresh()
                        if let nextToken = window.nextToken {
                            try slot.tokenStore.save(nextToken)
                        }
                    }
                }
            } catch {
                try? await owner.writerContext.slatePerform {
                    owner.writerContext.rollback()
                }
                throw error
            }
        }

        let hooks = currentIngestionHooksForTesting()
        hooks.count?()
        hooks.storeURL(storeURL?.standardizedFileURL)
    }

    private func fetchPersistentHistory(storeURL: URL?) async throws -> SlateRemoteChangeHistoryWindow {
        let owner = try await requireLoadedOwner()
        let slots = try resolvedSlots(in: owner)
        let selectedSlot: SlateResolvedRemoteChangeIngestionSlot
        if let storeURL {
            let standardizedURL = storeURL.standardizedFileURL
            guard let slot = slots.first(where: { $0.storeURL == standardizedURL }) else {
                throw SlateError.coreData(
                    "No remote-change ingestion slot matches store URL \(standardizedURL.path)"
                )
            }
            selectedSlot = slot
        } else {
            guard let slot = slots.first else {
                throw SlateError.coreData("No remote-change ingestion slots are configured")
            }
            selectedSlot = slot
        }
        return try await fetchPersistentHistory(for: owner, slot: selectedSlot)
    }

    private func fetchPersistentHistory(
        for owner: SlateStoreOwner<Schema>,
        slot: SlateResolvedRemoteChangeIngestionSlot
    ) async throws -> SlateRemoteChangeHistoryWindow {
        let token = SlateUncheckedPersistentHistoryToken(try slot.tokenStore.load())
        let targetStoreBox = SlateUncheckedPersistentStore(slot.store)

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

    private func resolvedSlots(
        in owner: SlateStoreOwner<Schema>
    ) throws -> [SlateResolvedRemoteChangeIngestionSlot] {
        try configuredSlots.map { slot in
            let matchingStore = owner.coordinator.persistentStores.first { store in
                store.url?.standardizedFileURL == slot.storeURL
            }
            guard let matchingStore else {
                throw SlateError.coreData(
                    "No loaded persistent store matches history token URL \(slot.storeURL.path)"
                )
            }
            return SlateResolvedRemoteChangeIngestionSlot(
                storeURL: slot.storeURL,
                store: matchingStore,
                tokenStore: slot.tokenStore
            )
        }
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

    private func currentIngestionHooksForTesting() -> (
        count: (@Sendable () -> Void)?,
        storeURL: @Sendable (URL?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        let countHook = ingestionHookForTesting
        let storeURLHook = ingestionStoreURLHookForTesting
        return (countHook, { storeURL in
            storeURLHook?(storeURL)
        })
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

            let loadState = owner.loadState
            switch loadState {
            case .loaded:
                return owner
            case .failed, .loading:
                if try await SlateOwnerReadiness.isLoadedOrWait(loadState) {
                    return owner
                }
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
