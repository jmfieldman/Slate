@preconcurrency import CoreData
import Foundation
import SlateSchema

final class SlateStoreOwner<Schema: SlateSchema>: @unchecked Sendable {
    typealias BatchDeleteHandler = @Sendable ([NSManagedObjectID]) -> Void

    let id: UUID
    let registry: SlateTableRegistry
    let coordinator: NSPersistentStoreCoordinator
    let writerContext: NSManagedObjectContext
    let accessGate: SlateAccessGate
    let cache: SlateObjectCache

    private let sinkLock = NSLock()
    private var batchDeleteSinks: [UUID: BatchDeleteHandler] = [:]

    init(
        id: UUID = UUID(),
        registry: SlateTableRegistry,
        coordinator: NSPersistentStoreCoordinator,
        writerContext: NSManagedObjectContext,
        accessGate: SlateAccessGate = SlateAccessGate(),
        cache: SlateObjectCache = SlateObjectCache()
    ) {
        self.id = id
        self.registry = registry
        self.coordinator = coordinator
        self.writerContext = writerContext
        self.accessGate = accessGate
        self.cache = cache
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

    /// Register a sink that wants to receive batch-delete object IDs after a
    /// `Slate.batchDelete(...)` call commits to the persistent store. Stream
    /// cores use this because `NSBatchDeleteRequest` bypasses
    /// `NSManagedObjectContextDidSave`, so the writer-context save observer
    /// they normally rely on never fires.
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
        sinkLock.lock()
        let handlers = Array(batchDeleteSinks.values)
        sinkLock.unlock()
        for handler in handlers {
            handler(deletedIDs)
        }
    }
}

struct SlateStoreIdentity: Hashable, Sendable {
    let canonicalURL: URL?
    let inMemoryToken: UUID?
    let schemaIdentifier: String
}

actor SlateStoreRegistryActor {
    static let shared = SlateStoreRegistryActor()

    private var owners: [SlateStoreIdentity: Any] = [:]
    private var diskSchemas: [URL: String] = [:]

    func owner<Schema: SlateSchema>(
        identity: SlateStoreIdentity,
        create: () throws -> SlateStoreOwner<Schema>
    ) throws -> SlateStoreOwner<Schema> {
        if let url = identity.canonicalURL {
            if let existingSchema = diskSchemas[url], existingSchema != identity.schemaIdentifier {
                throw SlateError.incompatibleStore(url)
            }
        }

        if let existing = owners[identity] {
            guard let typed = existing as? SlateStoreOwner<Schema> else {
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

