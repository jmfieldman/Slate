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

    let id: UUID
    let registry: SlateTableRegistry
    let coordinator: NSPersistentStoreCoordinator
    let cloudKitContainer: NSPersistentCloudKitContainer?
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

    init(
        id: UUID = UUID(),
        registry: SlateTableRegistry,
        coordinator: NSPersistentStoreCoordinator,
        cloudKitContainer: NSPersistentCloudKitContainer? = nil,
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
        mergeStateLock.unlock()
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

    private func notifyStreamSinks(_ event: SlateStreamRefreshEvent) {
        sinkLock.lock()
        let handlers = Array(batchDeleteSinks.values)
        sinkLock.unlock()
        for handler in handlers {
            handler(event)
        }
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
