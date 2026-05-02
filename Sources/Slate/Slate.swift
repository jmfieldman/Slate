@preconcurrency import CoreData
import Foundation
import SlateSchema

public final class Slate<Schema: SlateSchema>: @unchecked Sendable {
    private let persistentStoreDescription: NSPersistentStoreDescription
    private let storeKind: SlateStoreKind
    private let stateLock = NSLock()
    private var owner: SlateStoreOwner<Schema>?
    private var closed = false

    public init(
        persistentStoreDescription: NSPersistentStoreDescription,
        storeKind: SlateStoreKind = .strict
    ) {
        self.persistentStoreDescription = persistentStoreDescription
        self.storeKind = storeKind
    }

    public convenience init(
        storeURL: URL?,
        storeType: String = NSSQLiteStoreType,
        storeKind: SlateStoreKind = .strict
    ) {
        let description = NSPersistentStoreDescription()
        description.type = storeType
        description.url = storeURL
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        self.init(persistentStoreDescription: description, storeKind: storeKind)
    }

    public func configure() throws {
        try checkOpen()
        guard isUnconfigured() else {
            throw SlateError.alreadyConfigured
        }

        var registry = SlateTableRegistry()
        Schema.registerTables(&registry)

        let identity = try storeIdentity()
        let newOwner = try SlateStoreRegistry.shared.owner(identity: identity) {
            try Self.openOwner(
                description: persistentStoreDescription,
                storeKind: storeKind,
                registry: registry
            )
        }
        if !installOwner(newOwner) {
            throw SlateError.closed
        }
    }

    public func close() async {
        let activeOwner = markClosed()
        if let activeOwner {
            try? await activeOwner.accessGate.write { /* drain in-flight */ }
        }
    }

    private func checkOpen() throws {
        if isClosed() { throw SlateError.closed }
    }

    private func isClosed() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return closed
    }

    private func isUnconfigured() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return owner == nil
    }

    private func installOwner(_ newOwner: SlateStoreOwner<Schema>) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if closed { return false }
        owner = newOwner
        return true
    }

    private func markClosed() -> SlateStoreOwner<Schema>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let active = owner
        closed = true
        return active
    }

    @discardableResult
    public func query<Output: Sendable>(
        _ block: @Sendable @escaping (SlateQueryContext<Schema>) throws -> Output
    ) async throws -> Output {
        try checkOpen()
        guard SlateTransactionScopeKey.current == nil else {
            throw SlateError.nestedTransaction
        }
        let owner = try requireOwner()

        return try await owner.accessGate.read {
            let context = owner.makeReaderContext()
            let scope = SlateTransactionScope(ownerID: owner.id, scopeID: UUID(), kind: .query)

            return try await context.slatePerform {
                try SlateTransactionScopeKey.$current.withValue(scope) {
                    let queryContext = SlateQueryContext<Schema>(
                        ownerID: owner.id,
                        scopeID: scope.scopeID,
                        managedObjectContext: context,
                        registry: owner.registry,
                        cache: owner.cache
                    )
                    return try block(queryContext)
                }
            }
        }
    }

    @discardableResult
    public func mutate<Output: Sendable>(
        _ block: @Sendable @escaping (SlateMutationContext<Schema>) throws -> Output
    ) async throws -> Output {
        try checkOpen()
        guard SlateTransactionScopeKey.current == nil else {
            throw SlateError.nestedTransaction
        }
        let owner = try requireOwner()

        return try await owner.accessGate.write {
            let scope = SlateTransactionScope(ownerID: owner.id, scopeID: UUID(), kind: .mutation)

            return try await owner.writerContext.slatePerform {
                let output: Output
                do {
                    output = try SlateTransactionScopeKey.$current.withValue(scope) {
                        let mutationContext = SlateMutationContext<Schema>(
                            ownerID: owner.id,
                            scopeID: scope.scopeID,
                            managedObjectContext: owner.writerContext,
                            registry: owner.registry
                        )
                        return try block(mutationContext)
                    }
                } catch {
                    owner.writerContext.rollback()
                    throw error
                }

                guard owner.writerContext.hasChanges else {
                    return output
                }

                let inserted = owner.writerContext.insertedObjects
                if !inserted.isEmpty {
                    do {
                        try owner.writerContext.obtainPermanentIDs(for: Array(inserted))
                    } catch {
                        owner.writerContext.rollback()
                        throw error
                    }
                }

                let updated = owner.writerContext.updatedObjects
                let deleted = owner.writerContext.deletedObjects

                let mutatedIDs = inserted.union(updated).map(\.objectID)
                var updates: [NSManagedObjectID: any SlateObject] = [:]
                for object in inserted.union(updated) {
                    guard let table = owner.registry.table(forManagedObject: object) else {
                        continue
                    }
                    // Conversion can throw (e.g. an enum attribute lacking a
                    // default whose stored raw value no longer maps to a
                    // valid case). When that happens we don't try to cache
                    // the new immutable value here — it's still mutated, so
                    // we treat it like a delete from the cache so the next
                    // read forces a fresh convert and surfaces the error.
                    if let immutable = try? table.convert(object, []) {
                        updates[object.objectID] = immutable
                    }
                }
                let deletedIDs = deleted.map(\.objectID)
                let invalidatedIDs = mutatedIDs.filter { updates[$0] == nil } + deletedIDs
                let affectedIDs: Set<NSManagedObjectID> = Set(updates.keys).union(invalidatedIDs)
                let undo = owner.cache.snapshot(affectedIDs)

                owner.cache.apply(setting: updates, removing: invalidatedIDs)

                do {
                    try owner.writerContext.save()
                } catch {
                    owner.cache.restore(undo)
                    owner.writerContext.rollback()
                    throw error
                }

                return output
            }
        }
    }

    public func one<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [SlateSort<Value>] = [],
        relationships: [PartialKeyPath<Value>] = []
    ) async throws -> Value? where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        let relationshipNames = Set(relationships.map { Value.keypathToRelationship($0) })
        return try await query { context in
            var table = context[Value.self]
            if let predicate { table = table.where(predicate) }
            if !sort.isEmpty { table = table.sort(sort) }
            if !relationshipNames.isEmpty { table = table.relationships(names: relationshipNames) }
            return try table.one()
        }
    }

    /// Ascending-only key-path overload of `one(_:where:sort:relationships:)`.
    /// Lets callers skip the `SlateSort` wrapper for the common case:
    /// `slate.one(Patient.self, sort: [\.lastName])`.
    public func one<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [PartialKeyPath<Value>],
        relationships: [PartialKeyPath<Value>] = []
    ) async throws -> Value? where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        try await one(
            type,
            where: predicate,
            sort: sort.map { SlateSort($0) },
            relationships: relationships
        )
    }

    public func many<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [SlateSort<Value>] = [],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) async throws -> [Value] where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        let relationshipNames = Set(relationships.map { Value.keypathToRelationship($0) })
        return try await query { context in
            var table = context[Value.self]
            if let predicate { table = table.where(predicate) }
            if !sort.isEmpty { table = table.sort(sort) }
            if !relationshipNames.isEmpty { table = table.relationships(names: relationshipNames) }
            return try table.many(limit: limit, offset: offset)
        }
    }

    /// Ascending-only key-path overload of
    /// `many(_:where:sort:limit:offset:relationships:)`. See `one(...)`'s
    /// keypath overload for the rationale.
    public func many<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [PartialKeyPath<Value>],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) async throws -> [Value] where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        try await many(
            type,
            where: predicate,
            sort: sort.map { SlateSort($0) },
            limit: limit,
            offset: offset,
            relationships: relationships
        )
    }

    public func count<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil
    ) async throws -> Int where Value: SlateObject & SlateKeypathAttributeProviding {
        try await query { context in
            var table = context[Value.self]
            if let predicate { table = table.where(predicate) }
            return try table.count()
        }
    }

    /// Delete every row matching `predicate` using `NSBatchDeleteRequest`
    /// when the underlying store supports it (SQLite). The batch request
    /// runs as a SQL `DELETE` on the store and bypasses validation, delete
    /// rules, and any pending changes inside an active mutation context — it
    /// is intended for bulk maintenance work, not for cascading object-graph
    /// edits inside a `mutate` block.
    ///
    /// On non-SQLite stores (`NSInMemoryStoreType`, etc.) `NSBatchDeleteRequest`
    /// is unsupported, so this falls back to a fetch + per-row
    /// `context.delete(_:)` + `save()` inside the writer queue. The fallback
    /// path emits a normal `NSManagedObjectContextDidSave`, which streams
    /// already observe.
    ///
    /// In both paths, deleted object IDs are evicted from the immutable
    /// cache so the next read reflects the deletion. SQLite-path callers
    /// also receive a synthesized batch-delete event delivered to live
    /// streams so they re-fetch.
    @discardableResult
    public func batchDelete<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil
    ) async throws -> Int where Value: SlateObject & SlateKeypathAttributeProviding {
        try checkOpen()
        guard SlateTransactionScopeKey.current == nil else {
            throw SlateError.nestedTransaction
        }
        let owner = try requireOwner()
        guard let table = owner.registry.table(for: type) else {
            throw SlateError.missingTable(String(describing: type))
        }

        let supportsBatch = owner.coordinator.persistentStores.contains { $0.type == NSSQLiteStoreType }

        return try await owner.accessGate.write {
            try await owner.writerContext.slatePerform {
                let fetch = table.makeFetchRequest()
                fetch.entity = NSEntityDescription.entity(forEntityName: table.entityName, in: owner.writerContext)
                fetch.predicate = predicate?.expression.nsPredicate

                if supportsBatch {
                    let request = NSBatchDeleteRequest(fetchRequest: fetch)
                    request.resultType = .resultTypeObjectIDs

                    let result = try owner.writerContext.execute(request) as? NSBatchDeleteResult
                    let ids = (result?.result as? [NSManagedObjectID]) ?? []
                    guard !ids.isEmpty else { return 0 }

                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: ids]
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: changes,
                        into: [owner.writerContext]
                    )

                    owner.cache.remove(ids)
                    owner.notifyBatchDelete(deletedIDs: ids)

                    return ids.count
                }

                let objects = (try owner.writerContext.fetch(fetch)) as? [NSManagedObject] ?? []
                guard !objects.isEmpty else { return 0 }
                let ids = objects.map(\.objectID)
                for object in objects {
                    owner.writerContext.delete(object)
                }
                if owner.writerContext.hasChanges {
                    do {
                        try owner.writerContext.save()
                    } catch {
                        owner.writerContext.rollback()
                        throw error
                    }
                }
                owner.cache.remove(ids)
                return ids.count
            }
        }
    }

    @MainActor
    public func stream<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [SlateSort<Value>] = [],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) -> SlateStream<Value> where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        let core = makeStreamCore(
            type: type,
            predicate: predicate,
            sort: sort,
            limit: limit,
            offset: offset,
            relationships: relationships
        )
        return SlateStream(core: core)
    }

    /// Ascending-only key-path overload of `stream(...)`.
    @MainActor
    public func stream<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [PartialKeyPath<Value>],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) -> SlateStream<Value> where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        stream(
            type,
            where: predicate,
            sort: sort.map { SlateSort($0) },
            limit: limit,
            offset: offset,
            relationships: relationships
        )
    }

    public func streamBackground<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [SlateSort<Value>] = [],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) -> SlateBackgroundStream<Value> where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        let core = makeStreamCore(
            type: type,
            predicate: predicate,
            sort: sort,
            limit: limit,
            offset: offset,
            relationships: relationships
        )
        return SlateBackgroundStream(core: core)
    }

    /// Ascending-only key-path overload of `streamBackground(...)`.
    public func streamBackground<Value>(
        _ type: Value.Type,
        where predicate: SlatePredicate<Value>? = nil,
        sort: [PartialKeyPath<Value>],
        limit: Int? = nil,
        offset: Int? = nil,
        relationships: [PartialKeyPath<Value>] = []
    ) -> SlateBackgroundStream<Value> where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        streamBackground(
            type,
            where: predicate,
            sort: sort.map { SlateSort($0) },
            limit: limit,
            offset: offset,
            relationships: relationships
        )
    }

    private func makeStreamCore<Value>(
        type: Value.Type,
        predicate: SlatePredicate<Value>?,
        sort: [SlateSort<Value>],
        limit: Int?,
        offset: Int?,
        relationships: [PartialKeyPath<Value>]
    ) -> SlateStreamCore<Value> where
        Value: SlateObject & SlateKeypathAttributeProviding & SlateKeypathRelationshipProviding
    {
        guard let owner else {
            preconditionFailure("Slate.stream(...) requires configure() to have completed before stream creation.")
        }
        guard let table = owner.registry.table(for: type) else {
            preconditionFailure("Slate.stream(...): no table registered for \(type).")
        }

        let relationshipNames = Set(relationships.map { Value.keypathToRelationship($0) })
        let context = owner.makeStreamContext()

        let request = table.makeFetchRequest()
        request.predicate = predicate?.expression.nsPredicate
        let resolvedSorts = sort.isEmpty
            ? [NSSortDescriptor(key: "objectID", ascending: true)]
            : sort.map(\.descriptor)
        request.sortDescriptors = resolvedSorts
        if let limit { request.fetchLimit = limit }
        if let offset { request.fetchOffset = offset }
        request.relationshipKeyPathsForPrefetching = Array(relationshipNames).sorted()

        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        let convert: @Sendable (NSManagedObject) throws -> Value = { object in
            guard let result = try table.convert(object, relationshipNames) as? Value else {
                throw SlateError.coreData("Could not convert managed object to \(Value.self)")
            }
            return result
        }

        // The diffed-emission path relies on `mergeChanges` reliably producing
        // `NSManagedObjectContextObjectsDidChange` for inserts on a sibling
        // context. That holds for SQLite-backed coordinators but not for
        // `NSInMemoryStoreType`. It also assumes every emission can be served
        // from the FRC's already-fetched objects, which breaks down when the
        // request prefetches relationships (refaulted rows lose prefetched
        // data) or windows results via `fetchLimit`/`fetchOffset` (FRC change
        // tracking doesn't reliably evict at the boundary).
        let allStoresAreSQLite = owner.coordinator.persistentStores
            .allSatisfy { $0.type == NSSQLiteStoreType }
        let useDiffPath = allStoresAreSQLite
            && relationshipNames.isEmpty
            && limit == nil
            && offset == nil

        let storeOwner = owner
        return SlateStreamCore(
            context: context,
            frc: frc,
            convert: convert,
            writerContext: owner.writerContext,
            useDiffPath: useDiffPath,
            registerBatchDeleteSink: { handler in
                storeOwner.registerBatchDeleteSink(handler)
            },
            unregisterBatchDeleteSink: { id in
                storeOwner.unregisterBatchDeleteSink(id)
            }
        )
    }

    private func requireOwner() throws -> SlateStoreOwner<Schema> {
        stateLock.lock()
        defer { stateLock.unlock() }
        if closed { throw SlateError.closed }
        guard let owner else {
            throw SlateError.notConfigured
        }
        return owner
    }

    private func storeIdentity() throws -> SlateStoreIdentity {
        if persistentStoreDescription.type == NSInMemoryStoreType {
            return SlateStoreIdentity(
                canonicalURL: nil,
                inMemoryToken: UUID(),
                schemaIdentifier: Schema.schemaIdentifier
            )
        }

        guard let url = persistentStoreDescription.url else {
            throw SlateError.incompatibleStore(nil)
        }

        return SlateStoreIdentity(
            canonicalURL: url.standardizedFileURL,
            inMemoryToken: nil,
            schemaIdentifier: Schema.schemaIdentifier
        )
    }

    private static func openOwner(
        description: NSPersistentStoreDescription,
        storeKind: SlateStoreKind,
        registry: SlateTableRegistry
    ) throws -> SlateStoreOwner<Schema> {
        let model = try Schema.makeManagedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        do {
            try addStore(description: description, coordinator: coordinator)
        } catch {
            guard storeKind == .cacheStore,
                  description.type == NSSQLiteStoreType,
                  let url = description.url,
                  isLikelyIncompatibleStore(error)
            else {
                throw SlateError.coreData(String(describing: error))
            }

            try wipeSQLiteStore(at: url)
            try addStore(description: description, coordinator: coordinator)
        }

        let writerContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        writerContext.persistentStoreCoordinator = coordinator
        writerContext.undoManager = nil
        writerContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        return SlateStoreOwner(
            registry: registry,
            coordinator: coordinator,
            writerContext: writerContext
        )
    }

    private static func addStore(
        description: NSPersistentStoreDescription,
        coordinator: NSPersistentStoreCoordinator
    ) throws {
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
    }

    private static func isLikelyIncompatibleStore(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            [
                NSPersistentStoreIncompatibleVersionHashError,
                NSMigrationMissingSourceModelError,
                NSMigrationError,
                NSMigrationConstraintViolationError,
            ].contains(nsError.code)
    }

    private static func wipeSQLiteStore(at url: URL) throws {
        let fileManager = FileManager.default
        for candidate in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ] {
            guard fileManager.fileExists(atPath: candidate.path) else {
                continue
            }
            do {
                try fileManager.removeItem(at: candidate)
            } catch {
                throw SlateError.wipeFailed(candidate, String(describing: error))
            }
        }
    }
}
