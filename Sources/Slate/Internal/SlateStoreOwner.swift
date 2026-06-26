@preconcurrency import CloudKit
@preconcurrency import CoreData
import Foundation
import SlateSchema

enum SlateStoreLoadState {
    case loading
    case loaded
    case failed(Error)
}

enum SlateStreamRefreshEvent {
    case batchDelete(deletedIDs: [NSManagedObjectID])
    case remoteMerge
}

final class SlateStoreOwner<Schema: SlateSchema>: @unchecked Sendable {
    typealias BatchDeleteHandler = @Sendable (SlateStreamRefreshEvent) -> Void
    typealias AccountStatusSink = @MainActor @Sendable (SlateAccountStatus) -> Void
    typealias ImportEventSink = @MainActor @Sendable (Bool, (any Error)?) -> Void
    typealias MergeStateSink = @MainActor @Sendable (Bool) -> Void

    let id: UUID
    let registry: SlateTableRegistry
    let coordinator: NSPersistentStoreCoordinator
    let cloudKitContainer: NSPersistentCloudKitContainer?
    let cloudKitAccountContainer: CKContainer?
    let cloudKitAccountContainerIdentifier: String?
    let writerContext: NSManagedObjectContext
    let accessGate: SlateAccessGate
    let cache: SlateObjectCache
    let storageMode: SlateStorageMode

    private let loadStateLock = NSLock()
    private var storedLoadState: SlateStoreLoadState
    private var loadStarted = false
    private let sinkLock = NSLock()
    private var batchDeleteSinks: [UUID: BatchDeleteHandler] = [:]
    private let ingestorLock = NSLock()
    private var storedRemoteChangeIngestor: SlateRemoteChangeIngestor<Schema>?
    private let mergeStateLock = NSLock()
    private var storedIsMerging = false
    private var mergeStateSinks: [UUID: MergeStateSink] = [:]
    private var mergeStateRevision = 0
    private let accountStatusLock = NSLock()
    private var accountStatusSinks: [UUID: AccountStatusSink] = [:]
    private var accountStatusObserver: NSObjectProtocol?
    private var accountStatusRefreshGeneration = 0
    private let importEventLock = NSLock()
    private var importEventSinks: [UUID: ImportEventSink] = [:]
    private var importEventObserver: SlateCloudKitContainer.EventObserverToken?
    private var activeImportEventIDs = Set<UUID>()
    private var lastImportEventError: Error?
    private var importEventRevision = 0

    init(
        id: UUID = UUID(),
        registry: SlateTableRegistry,
        coordinator: NSPersistentStoreCoordinator,
        cloudKitContainer: NSPersistentCloudKitContainer? = nil,
        cloudKitAccountContainer: CKContainer? = nil,
        cloudKitAccountContainerIdentifier: String? = nil,
        writerContext: NSManagedObjectContext,
        accessGate: SlateAccessGate = SlateAccessGate(),
        cache: SlateObjectCache = SlateObjectCache(),
        storageMode: SlateStorageMode = .local,
        loadState: SlateStoreLoadState = .loaded
    ) {
        self.id = id
        self.registry = registry
        self.coordinator = coordinator
        self.cloudKitContainer = cloudKitContainer
        self.cloudKitAccountContainer = cloudKitAccountContainer
        self.cloudKitAccountContainerIdentifier = cloudKitAccountContainerIdentifier
        self.writerContext = writerContext
        self.accessGate = accessGate
        self.cache = cache
        self.storageMode = storageMode
        self.storedLoadState = loadState
    }

    var loadState: SlateStoreLoadState {
        loadStateLock.lock()
        defer { loadStateLock.unlock() }
        return storedLoadState
    }

    func markLoaded() {
        loadStateLock.lock()
        storedLoadState = .loaded
        loadStateLock.unlock()
        startRemoteChangeIngestorIfNeeded()
        refreshAccountStatusIfNeeded()
    }

    func markFailed(_ error: Error) {
        loadStateLock.lock()
        storedLoadState = .failed(error)
        loadStateLock.unlock()
    }

    @discardableResult
    func loadCloudKitStoresIfNeeded(
        completion: @escaping (SlateStoreLoadState) -> Void
    ) -> Bool {
        guard let cloudKitContainer else {
            return false
        }

        loadStateLock.lock()
        guard !loadStarted else {
            loadStateLock.unlock()
            return false
        }
        loadStarted = true
        storedLoadState = .loading
        loadStateLock.unlock()

        SlateCloudKitContainer.loadPersistentStores(for: cloudKitContainer) { [weak self] error in
            let newState: SlateStoreLoadState
            if let error {
                newState = .failed(error)
            } else {
                newState = .loaded
            }

            switch newState {
            case .loaded:
                self?.markLoaded()
            case .failed(let error):
                self?.markFailed(error)
            case .loading:
                break
            }

            completion(newState)
        }

        return true
    }

    var remoteChangeIngestor: SlateRemoteChangeIngestor<Schema>? {
        ingestorLock.lock()
        defer { ingestorLock.unlock() }
        return storedRemoteChangeIngestor
    }

    var isMerging: Bool {
        mergeStateLock.lock()
        defer { mergeStateLock.unlock() }
        return storedIsMerging
    }

    func setIsMerging(_ isMerging: Bool) {
        mergeStateLock.lock()
        storedIsMerging = isMerging
        mergeStateRevision += 1
        let revision = mergeStateRevision
        let sinkIDs = Set(mergeStateSinks.keys)
        mergeStateLock.unlock()

        guard !sinkIDs.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            guard let sinks = self?.mergeStateSinks(for: revision, sinkIDs: sinkIDs) else {
                return
            }
            for sink in sinks {
                sink(isMerging)
            }
        }
    }

    func installRemoteChangeIngestor(_ ingestor: SlateRemoteChangeIngestor<Schema>) {
        ingestorLock.lock()
        storedRemoteChangeIngestor = ingestor
        let shouldStart = {
            loadStateLock.lock()
            defer { loadStateLock.unlock() }
            if case .loaded = storedLoadState {
                return true
            }
            return false
        }()
        ingestorLock.unlock()

        if shouldStart {
            ingestor.start()
        }
    }

    func startRemoteChangeIngestorIfNeeded() {
        let ingestor = remoteChangeIngestor
        ingestor?.start()
    }

    func stopRemoteChangeIngestor() {
        let ingestor = remoteChangeIngestor
        ingestor?.stop()
    }

    func makeReaderContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    func makeStreamContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    /// Register a sink that wants to receive batch-delete or remote-merge
    /// refresh events after store-level changes that bypass the writer
    /// context's normal save notification.
    @discardableResult
    func registerBatchDeleteSink(_ handler: @escaping BatchDeleteHandler) -> UUID {
        let id = UUID()
        sinkLock.lock()
        batchDeleteSinks[id] = handler
        sinkLock.unlock()
        return id
    }

    func unregisterBatchDeleteSink(_ id: UUID) {
        sinkLock.lock()
        batchDeleteSinks.removeValue(forKey: id)
        sinkLock.unlock()
    }

    func notifyBatchDelete(deletedIDs: [NSManagedObjectID]) {
        notifyStreamSinks(.batchDelete(deletedIDs: deletedIDs))
    }

    func notifyStreamsRefresh() {
        notifyStreamSinks(.remoteMerge)
    }

    @discardableResult
    func registerAccountStatusSink(_ sink: @escaping AccountStatusSink) -> UUID? {
        guard cloudKitAccountContainerIdentifier != nil else {
            return nil
        }

        let id = UUID()
        accountStatusLock.lock()
        accountStatusSinks[id] = sink
        let shouldStartObserving = accountStatusObserver == nil
        accountStatusLock.unlock()

        if shouldStartObserving {
            startAccountStatusObservationIfNeeded()
        }
        if isLoaded {
            refreshAccountStatusIfNeeded()
        }

        return id
    }

    func unregisterAccountStatusSink(_ id: UUID) {
        var observerToRemove: NSObjectProtocol?
        accountStatusLock.lock()
        accountStatusSinks.removeValue(forKey: id)
        if accountStatusSinks.isEmpty {
            observerToRemove = accountStatusObserver
            accountStatusObserver = nil
        }
        accountStatusLock.unlock()

        if let observerToRemove {
            NotificationCenter.default.removeObserver(observerToRemove)
        }
    }

    @discardableResult
    func registerImportEventSink(_ sink: @escaping ImportEventSink) -> UUID? {
        guard cloudKitContainer != nil else {
            return nil
        }

        let id = UUID()
        importEventLock.lock()
        importEventSinks[id] = sink
        let shouldStartObserving = importEventObserver == nil
        importEventLock.unlock()

        if shouldStartObserving {
            startImportEventObservationIfNeeded()
        }

        return id
    }

    func unregisterImportEventSink(_ id: UUID) {
        let observerToInvalidate: SlateCloudKitContainer.EventObserverToken?
        importEventLock.lock()
        importEventSinks.removeValue(forKey: id)
        if importEventSinks.isEmpty {
            observerToInvalidate = importEventObserver
            importEventObserver = nil
            activeImportEventIDs.removeAll()
        } else {
            observerToInvalidate = nil
        }
        importEventLock.unlock()

        observerToInvalidate?.invalidate()
    }

    @discardableResult
    func registerMergeStateSink(_ sink: @escaping MergeStateSink) -> UUID? {
        guard remoteChangeIngestor != nil else {
            return nil
        }

        let id = UUID()
        let currentValue: Bool
        let revision: Int
        mergeStateLock.lock()
        mergeStateSinks[id] = sink
        currentValue = storedIsMerging
        revision = mergeStateRevision
        mergeStateLock.unlock()

        Task { @MainActor [weak self] in
            guard let sinks = self?.mergeStateSinks(for: revision, sinkIDs: [id]) else {
                return
            }
            for sink in sinks {
                sink(currentValue)
            }
        }

        return id
    }

    func unregisterMergeStateSink(_ id: UUID) {
        mergeStateLock.lock()
        mergeStateSinks.removeValue(forKey: id)
        mergeStateLock.unlock()
    }

    private func notifyStreamSinks(_ event: SlateStreamRefreshEvent) {
        sinkLock.lock()
        let handlers = Array(batchDeleteSinks.values)
        sinkLock.unlock()
        for handler in handlers {
            handler(event)
        }
    }

    private var isLoaded: Bool {
        loadStateLock.lock()
        defer { loadStateLock.unlock() }
        if case .loaded = storedLoadState {
            return true
        }
        return false
    }

    private func startAccountStatusObservationIfNeeded() {
        guard cloudKitAccountContainerIdentifier != nil else {
            return
        }

        accountStatusLock.lock()
        guard accountStatusObserver == nil else {
            accountStatusLock.unlock()
            return
        }
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refreshAccountStatusIfNeeded()
        }
        accountStatusObserver = observer
        accountStatusLock.unlock()
    }

    private func startImportEventObservationIfNeeded() {
        guard let cloudKitContainer else {
            return
        }

        importEventLock.lock()
        guard importEventObserver == nil else {
            importEventLock.unlock()
            return
        }
        let observer = SlateCloudKitContainer.observeEvents(for: cloudKitContainer) { [weak self] event in
            self?.recordCloudKitEvent(event)
        }
        importEventObserver = observer
        importEventLock.unlock()
    }

    func recordCloudKitEvent(_ event: SlateCloudKitContainer.EventSnapshot) {
        guard event.type == .import else {
            return
        }

        importEventLock.lock()
        if event.endDate == nil, event.error == nil {
            activeImportEventIDs.insert(event.identifier)
        } else {
            activeImportEventIDs.remove(event.identifier)
        }
        if let error = event.error {
            lastImportEventError = error
        }
        let isImporting = !activeImportEventIDs.isEmpty
        importEventRevision += 1
        let revision = importEventRevision
        let sinkIDs = Set(importEventSinks.keys)
        let error = lastImportEventError
        importEventLock.unlock()

        guard !sinkIDs.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            guard let sinks = self?.importEventSinks(for: revision, sinkIDs: sinkIDs) else {
                return
            }
            for sink in sinks {
                sink(isImporting, error)
            }
        }
    }

    private func refreshAccountStatusIfNeeded() {
        guard let cloudKitAccountContainerIdentifier else {
            return
        }

        accountStatusLock.lock()
        let hasSinks = !accountStatusSinks.isEmpty
        accountStatusRefreshGeneration += 1
        let generation = accountStatusRefreshGeneration
        accountStatusLock.unlock()
        guard hasSinks else {
            return
        }

        SlateCloudKitContainer.accountStatus(
            for: cloudKitAccountContainer,
            forContainerIdentifier: cloudKitAccountContainerIdentifier
        ) { [weak self] result in
            let status: SlateAccountStatus
            if let cloudKitStatus = result.status {
                status = SlateAccountStatus(cloudKitStatus: cloudKitStatus)
            } else {
                status = .couldNotDetermine
            }
            self?.notifyAccountStatusSinks(status, generation: generation)
        }
    }

    private func notifyAccountStatusSinks(_ status: SlateAccountStatus, generation: Int) {
        accountStatusLock.lock()
        guard generation == accountStatusRefreshGeneration else {
            accountStatusLock.unlock()
            return
        }
        let sinkIDs = Set(accountStatusSinks.keys)
        accountStatusLock.unlock()

        guard !sinkIDs.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            guard let sinks = self?.accountStatusSinks(for: generation, sinkIDs: sinkIDs) else {
                return
            }
            for sink in sinks {
                sink(status)
            }
        }
    }

    private func mergeStateSinks(for revision: Int, sinkIDs: Set<UUID>) -> [MergeStateSink]? {
        mergeStateLock.lock()
        defer { mergeStateLock.unlock() }
        guard revision == mergeStateRevision else {
            return nil
        }
        return sinkIDs.compactMap { mergeStateSinks[$0] }
    }

    private func importEventSinks(for revision: Int, sinkIDs: Set<UUID>) -> [ImportEventSink]? {
        importEventLock.lock()
        defer { importEventLock.unlock() }
        guard revision == importEventRevision else {
            return nil
        }
        return sinkIDs.compactMap { importEventSinks[$0] }
    }

    private func accountStatusSinks(for generation: Int, sinkIDs: Set<UUID>) -> [AccountStatusSink]? {
        accountStatusLock.lock()
        defer { accountStatusLock.unlock() }
        guard generation == accountStatusRefreshGeneration else {
            return nil
        }
        return sinkIDs.compactMap { accountStatusSinks[$0] }
    }

    func setLoadStateForTesting(_ loadState: SlateStoreLoadState) {
        loadStateLock.lock()
        storedLoadState = loadState
        loadStateLock.unlock()
        if case .loaded = loadState {
            startRemoteChangeIngestorIfNeeded()
        }
    }

    deinit {
        stopRemoteChangeIngestor()
        if let accountStatusObserver {
            NotificationCenter.default.removeObserver(accountStatusObserver)
        }
        importEventObserver?.invalidate()
    }
}

struct SlateStoreIdentity: Hashable, Sendable {
    let canonicalURL: URL?
    let inMemoryToken: UUID?
    let schemaIdentifier: String
}

final class SlateStoreRegistry: @unchecked Sendable {
    static let shared = SlateStoreRegistry()

    private let lock = NSLock()
    private var owners: [SlateStoreIdentity: Any] = [:]
    private var diskSchemas: [URL: String] = [:]

    func owner<Schema: SlateSchema>(
        identity: SlateStoreIdentity,
        storageMode: SlateStorageMode,
        create: () throws -> SlateStoreOwner<Schema>
    ) throws -> SlateStoreOwner<Schema> {
        lock.lock()
        defer { lock.unlock() }

        if let url = identity.canonicalURL {
            if let existingSchema = diskSchemas[url], existingSchema != identity.schemaIdentifier {
                throw SlateError.incompatibleStore(url)
            }
        }

        if let existing = owners[identity] {
            guard let typed = existing as? SlateStoreOwner<Schema> else {
                throw SlateError.incompatibleStore(identity.canonicalURL)
            }
            guard typed.storageMode == storageMode else {
                throw SlateError.incompatibleStore(identity.canonicalURL)
            }
            return typed
        }

        let owner = try create()
        owners[identity] = owner
        if let url = identity.canonicalURL {
            diskSchemas[url] = identity.schemaIdentifier
        }
        return owner
    }
}
