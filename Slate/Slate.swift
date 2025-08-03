//
//  Slate.swift
//  Copyright © 2018 Jason Fieldman.
//

import Combine
import CoreData
import Foundation

// MARK: - Private Constants

/// The thread key for the current SlateQueryContext
private let kThreadKeySlateQueryContext = "kThreadKeySlateQueryContext"

// MARK: - SlateConfigError

public enum SlateConfigError: Error {
    case alreadyConfigured
    case storageURLRequired
    case storageURLAlreadyInUse
    case coreDataError(Error)
}

// MARK: - SlateError

public enum SlateTransactionError: Error {
    /// A slate context is being used outside of query/mutate blocks.
    case queryOutsideScope

    /// Some internal inconsistency occurred while casting
    /// Core Data <-> Immutable objects. This should never occur,
    /// but is coded to catch unexpected problems.
    case queryInvalidCast

    /// Contains non-Slate Core Data errors (e.g. if a mutation
    /// fails due to insufficient disk storage.)
    ///
    /// May also contain any specific errors thrown by the user
    /// that need to bubble up. If you want to abort quietly
    /// without rethrowing further errors, throw `aborted`.
    case underlying(Error)

    /// Throw this error from inside a mutation/query block to
    /// terminate the block, without the error bubbling up to
    /// any error publisher/handler (`aborted` is eaten internally
    /// and resets the context/transaction.)
    ///
    /// If you would like to catch a specific error along with
    /// the abort, use `underlying`.
    case aborted

    /// Quick accessor to check if this is aborted
    fileprivate var isAborted: Bool {
        switch self {
        case .queryOutsideScope, .queryInvalidCast, .underlying:
            false
        case .aborted:
            true
        }
    }
}

// MARK: - SlateID

/**
 This implementation of Slate is based on Core Data, but it should be feasible to
 refactor code to use an alternate version of Slate (e.g. backed by Realm?) without
 too much hassle in higher level code.  Higher level code can use the SlateID
 as a constant identifier of an object as it undergoes mutations and new immutable versions
 of its model are generated.
 */
public typealias SlateID = NSManagedObjectID

// MARK: - SlateObject

/**
 Any immutable Slate data model implementation must implement SlateObject.
 */
public protocol SlateObject {
    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    static var __slate_managedObjectType: NSManagedObject.Type { get }

    /**
     Each immutable data model object should have an associated SlateID (in the
     core data case, the NSManagedObjectID.  This is a cross-mutation identifier
     for the object.
     */
    var slateID: SlateID { get }
}

/**
 Conformance to this protocol allows a SlateManagedObjectRelating to be used as a generic
 and pass the managed object type down to ivars that need a related ManagedObject type.
 */
public protocol SlateManagedObjectRelating: SlateObject {
    associatedtype ManagedObjectType: SlateObjectConvertible, NSManagedObject
}

// MARK: - Slate

/**
 A Slate instance is the central management context for all operations (mutation
 and query) on a NSPersistentStore. You should only have one active
 instantiation of a Slate per NSPersistentStore.  Think of a Slate as an
 implementation replacement of a NSPersistentStoreCoordinator.

 It is considered a fatalError to instantiate multiple concurrent Slate instances
 on the same NSPersistentStore data.  Slate will attempt to validate this by checking
 against a global cache of used NSPersistentStore.URL locations.

 A Slate provides a single-write/multiple-read I/O system.  All mutations occur
 as a barrier operation, waiting for all reads to complete and blocking all reads
 during.  Mutations occur on the top-level Managed Object Context and are
 immediately persisted to the store.

 Reads/queries are executed inside of a SlateQueryContext.  A SlateQueryContext
 is generated for each read transaction.  Queries inside of this context return
 immutable value objects representing the snapshot of the data model at the time
 of the query.

 Because of the barrier nature of the single-write, during the SlateQueryContext
 lifecycle you are guaranteed that all queries are operating on an internally
 consistent representation of the object graph that will not be modified in the
 middle of multiple query operations.
 */
public final class Slate {
    // MARK: Private Properties

    /// The NSManagedObjectModel associated with this Slate
    private var managedObjectModel: NSManagedObjectModel?

    /// The NSPersistentStoreDescription associated with this Slate
    private var persistentStoreDescription: NSPersistentStoreDescription?

    /// The master NSPersistentStoreCoordinator associated with this Slate, assigned
    /// during initialization
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator?

    /// The master context associated with the Slate.  This is the context that handles
    /// mutations, and is also the parent for read contexts.
    private var masterContext: _SlateManagedObjectContext?

    /// The read/write dispatch queue to execute context access
    private let accessQueue: DispatchQueue

    /// The configuration dispatch queue
    private let configQueue: DispatchQueue

    /// Indicates that we have been configured
    private var configured: Bool = false

    /// A passthrough subject to publish uncaught transaction errors.
    /// This only emits transaction errors that are not otherwise
    /// caught by an explicit catch block. This does not emit .aborted
    /// errors.
    fileprivate let uncaughtTransactionErrorSubject: PassthroughSubject<SlateTransactionError, Never> = .init()

    /// Publishes uncaught transaction errors.
    /// This only emits transaction errors that are not otherwise
    /// caught by an explicit catch block. This does not emit .aborted
    /// errors.
    public let uncaughtTransactionErrors: AnyPublisher<SlateTransactionError, Never>

    /// The access lock for the global unique store URL check
    private static let storeUrlCheckLock = NSLock()

    /// The set of on-disk persistent store URLs used by all instantiated Slates.
    /// It is considered a fatalError to instantiate multiple Slates that use the
    /// same storeUrl.
    private static var storeUrlSet: Set<URL> = .init()

    // MARK: Initialization

    /**
     Initialize the Slate with a given NSManagedObjectModel and NSPersistentStoreDescription.
     The completion handler is passed directly into the associated addPersistentStore method when
     configuring the internal NSPersistentStoreCoordinator.
     This is the main designated initializer.
     */
    public init() {
        // Config Queue
        self.configQueue = DispatchQueue(
            label: "Slate.configQueue",
            qos: .default,
            attributes: [],
            autoreleaseFrequency: .workItem,
            target: nil
        )

        // Access Queue
        self.accessQueue = DispatchQueue(
            label: "Slate.accessQueue",
            qos: .default,
            attributes: [.concurrent, .initiallyInactive],
            autoreleaseFrequency: .workItem,
            target: nil
        )

        self.uncaughtTransactionErrors = uncaughtTransactionErrorSubject.eraseToAnyPublisher()
    }

    // MARK: Deinit

    deinit {
        if !configured {
            accessQueue.activate()
        }

        // Remove the storeURL from the set of active disk stores.
        if let storeURL = self.persistentStoreDescription?.url {
            Slate.storeUrlCheckLock.lock()
            Slate.storeUrlSet.remove(storeURL)
            Slate.storeUrlCheckLock.unlock()
        }
    }

    // MARK: Configuration

    public func configure(
        managedObjectModel: NSManagedObjectModel,
        persistentStoreDescription: NSPersistentStoreDescription,
        completionHandler: @escaping (NSPersistentStoreDescription, SlateConfigError?) -> Void
    ) {
        configQueue.async {
            guard !self.configured else {
                completionHandler(persistentStoreDescription, .alreadyConfigured)
                return
            }

            // Validate the storeURL for disk-based persistent stores.
            if persistentStoreDescription.type != NSInMemoryStoreType {
                guard let storeURL = persistentStoreDescription.url else {
                    completionHandler(persistentStoreDescription, .storageURLRequired)
                    return
                }

                Slate.storeUrlCheckLock.lock()
                if Slate.storeUrlSet.contains(storeURL) {
                    Slate.storeUrlCheckLock.unlock()
                    completionHandler(persistentStoreDescription, .storageURLAlreadyInUse)
                    return
                }
                Slate.storeUrlCheckLock.unlock()
            }

            // Assign properties
            self.managedObjectModel = managedObjectModel
            self.persistentStoreDescription = persistentStoreDescription

            // The PSC is created and attached to the store
            self.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
            self.persistentStoreCoordinator?.addPersistentStore(with: persistentStoreDescription) { desc, error in
                // If the PSC is configured properly we can spin up the access queue
                if error == nil {
                    // insert the storeURL for disk-based persistent stores.
                    if persistentStoreDescription.type != NSInMemoryStoreType {
                        guard let storeURL = persistentStoreDescription.url else {
                            return
                        }

                        Slate.storeUrlCheckLock.lock()
                        Slate.storeUrlSet.insert(storeURL)
                        Slate.storeUrlCheckLock.unlock()
                    }

                    // The master MOC is created and attached to the PSC
                    self.masterContext = _SlateManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    self.masterContext?.persistentStoreCoordinator = self.persistentStoreCoordinator
                    self.masterContext?.undoManager = nil

                    // When an NSBatchDelete executes and removes an entity that was previously fetched and updated
                    // inside a single transaction, we expect the deletion to take precedence in the merge conflict.
                    // Note that since transactions against the master context are synchronized, this type of
                    // "merge conflict" is the only one that can occur as a peculiarity of batched deletes executing
                    // directly against the persistent store.
                    self.masterContext?.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

                    self.masterContext?.performAndWait {
                        // Guarantees that the master context is setup before activating
                        // the access queue.
                    }

                    self.configured = true
                    self.accessQueue.activate()
                }

                // Call our parent completion handler
                completionHandler(desc, error.flatMap { .coreDataError($0) })
            }
        }
    }

    // MARK: Immutable Object Cache

    /// The immutable object cache -- Cannot use NSCache because it does not support
    /// Swift structs as values
    private var immutableObjectCache: [SlateID: Any] = [:]

    /// Fast locking mechanism for immObjectCache
    private var immutableObjectCacheLock = os_unfair_lock_s()

    /**
     Run bulk immutable object cache updates inside lock
     */
    private func updateImmutableObjectCache(
        updates: [SlateID: Any],
        inserts: [SlateID: Any],
        deletes: [SlateID]
    ) {
        os_unfair_lock_lock(&immutableObjectCacheLock)
        defer {
            os_unfair_lock_unlock(&immutableObjectCacheLock)
        }

        for (objId, obj) in updates {
            if immutableObjectCache[objId] != nil {
                immutableObjectCache[objId] = obj
            }
        }

        for (objId, obj) in inserts {
            immutableObjectCache[objId] = obj
        }

        for objId in deletes {
            immutableObjectCache[objId] = nil
        }
    }

    /**
     Returns the cached object for the given SlateID if it exists.  Otherwise it uses
     the make block to create the SlateObject, cache it, and return it.
     */
    fileprivate func cachedObjectOrCreate(id: SlateID, make: () -> SlateObject) -> SlateObject {
        os_unfair_lock_lock(&immutableObjectCacheLock)
        defer {
            os_unfair_lock_unlock(&immutableObjectCacheLock)
        }

        if let slateObj = immutableObjectCache[id] as? SlateObject {
            return slateObj
        }

        let slateObj = make()
        immutableObjectCache[id] = slateObj
        return slateObj
    }

    // MARK: Query

    /**
     The `querySync` function grants a synchronous read scope into the
     core data graph.  The user-submitted block is run synchronously on the
     multi-reader queue.  The scope only permits reading immutable
     data model representations of the core data graph objects.
     */
    @discardableResult public func querySync(block: (SlateQueryContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock(slate: self)

        // Run immediately if the thread is being called synchronously inside of
        // an exisitng query context
        if let currentContext = Thread.current.containingQueryContext() {
            do {
                try block(currentContext)
            } catch {
                catchBlock.error = error
            }
            return catchBlock
        }

        accessQueue.sync {
            // Create a new read MOC
            let queryMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            queryMOC.parent = self.masterContext
            queryMOC.undoManager = nil

            // Run the remaining operations synchronously in the context's perform queue
            queryMOC.performAndWait {
                // Create query context
                let slateQueryContext = SlateQueryContext(slate: self, managedObjectContext: queryMOC)

                // Set the Thread's query context key
                let oldQueryContext = Thread.current.setInsideQueryContext(slateQueryContext)

                // Issue user query block
                do {
                    try block(slateQueryContext)
                } catch {
                    catchBlock.error = error
                }

                // Reset query context
                Thread.current.setInsideQueryContext(oldQueryContext)
            }
        }

        return catchBlock
    }

    /**
     The `queryAsync` function grants an asynchronous read scope into the
     core data graph.  The user-submitted block is run synchronously on the
     multi-reader queue.  The scope only permits reading immutable
     data model representations of the core data graph objects.
     */
    @discardableResult public func queryAsync(block: @escaping (SlateQueryContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock(slate: self)

        accessQueue.async {
            // Create a new read MOC
            let queryMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            queryMOC.parent = self.masterContext
            queryMOC.undoManager = nil

            // Run the remaining operations synchronously in the context's perform queue
            queryMOC.performAndWait {
                // Create query context
                let slateQueryContext = SlateQueryContext(slate: self, managedObjectContext: queryMOC)

                // Set the Thread's query context key
                let oldQueryContext = Thread.current.setInsideQueryContext(slateQueryContext)

                // Issue user query block
                do {
                    try block(slateQueryContext)
                } catch {
                    catchBlock.error = error
                }

                // Reset query context
                Thread.current.setInsideQueryContext(oldQueryContext)
            }
        }

        return catchBlock
    }

    // MARK: Async Query

    /**
     The `query` function wraps `queryAsync` in structured concurrency semantics. You can use:

        do {
            let result = try await slate.query { context in
                return try context[Author.self].fetchOne()
            }
        } catch { .. SlateTransactionError .. }

     Note that since the inner block that exposes the context is running inside a ManagedObjectContext
     queue, that it cannot be async itself.
     */
    @discardableResult public func query<Output: Sendable>(
        block: @escaping (SlateQueryContext) throws -> Output
    ) async throws(SlateTransactionError) -> Output {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                // Create a new read MOC
                let queryMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                queryMOC.parent = self.masterContext
                queryMOC.undoManager = nil

                accessQueue.asyncUnsafe {
                    // Run the remaining operations synchronously in the context's perform queue
                    queryMOC.performAndWait {
                        // Create query context
                        let slateQueryContext = SlateQueryContext(slate: self, managedObjectContext: queryMOC)

                        // Set the Thread's query context key
                        let oldQueryContext = Thread.current.setInsideQueryContext(slateQueryContext)

                        // Issue user query block
                        let result: Result<Output, Error>
                        do {
                            result = try Result<Output, Error>.success(block(slateQueryContext))
                        } catch {
                            result = Result<Output, Error>.failure(error)
                        }

                        // Reset query context
                        Thread.current.setInsideQueryContext(oldQueryContext)

                        continuation.resume(with: result)
                    }
                }
            }
        } catch {
            if let err = error as? SlateTransactionError {
                throw err
            } else {
                throw SlateTransactionError.underlying(error)
            }
        }
    }

    // MARK: Mutation

    /**
     The `mutateSync` function gives direct access to the underlying master write context
     in a synchronous scope.  The block is run on the context's private queue, so
     the user's block code can immediately fetch and modify NSManagedObjects within
     the MOC argument (you do not need an additional perform/performAndWait.)  The
     entire operation is a barrier on the Slate accessQueue, no other read/writes can
     occur while the mutation block is executing.

     Call sites should NOT keep a reference to the MOC, and they should NOT issue
     the `save` command on the MOC.  The save will occur when the mutation block completes.
     Saving inside the block will prevent Slate from properly detecting changes.

     Upon completion of the mutation block, the Slate listeners will be notified of
     the mutation results WITHIN THE MOC'S `performAndWait` context.  This means that
     listener blocks are called synchronously after the call to `mutateSync` and
     will also act as barriers to futher read/write operations.
     */
    @discardableResult public func mutateSync(block: (NSManagedObjectContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock(slate: self)

        accessQueue.sync(flags: .barrier) {
            guard let masterContext = self.masterContext else {
                return
            }

            // Issue the mutation block inside of the context's
            // performAndWait; capture the response
            // TODO: Protect against saving or other invalid MOC operations?
            masterContext.performAndWait {
                do {
                    try block(masterContext)
                } catch {
                    catchBlock.error = error
                    masterContext.reset()
                    return
                }

                // Attempt to save the context
                do {
                    try masterContext.obtainPermanentIDs(for: [NSManagedObject](masterContext.insertedObjects))

                    let queryContext = SlateQueryContext(slate: self, managedObjectContext: masterContext)
                    let oldQueryContext = Thread.current.setInsideQueryContext(queryContext)

                    // Update cache (after getting objects but before saving
                    // so that we are cached for any fetched results controllers
                    self.updateImmutableObjectCache(
                        updates: Slate.toSlateMap(masterContext.updatedObjects),
                        inserts: Slate.toSlateMap(masterContext.insertedObjects),
                        deletes: masterContext.deletedObjects.map(\.objectID),
                    )

                    Thread.current.setInsideQueryContext(oldQueryContext)

                    try masterContext.safeSave()
                } catch {
                    catchBlock.error = error
                    return
                }
            }
        }

        return catchBlock
    }

    /**
     The `mutateAsync` function gives direct access to the underlying master write context
     in an asynchronous scope.  The block is run on the context's private queue, so
     the user's block code can immediately fetch and modify NSManagedObjects within
     the MOC argument (you do not need an additional perform/performAndWait.)  The
     entire operation is a barrier on the Slate accessQueue, no other read/writes can
     occur while the mutation block is executing.

     Call sites should NOT keep a reference to the MOC, and they should NOT issue
     the `save` command on the MOC.  The save will occur when the mutation block completes.
     Saving inside the block will prevent Slate from properly detecting changes.

     Upon completion of the mutation block, the Slate listeners will be notified of
     the mutation results WITHIN THE MOC'S `performAndWait` context.  This means that
     listener blocks will also act as barriers to futher read/write operations.
     */
    @discardableResult public func mutateAsync(block: @escaping (NSManagedObjectContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock(slate: self)

        accessQueue.async(flags: .barrier) {
            guard let masterContext = self.masterContext else {
                return
            }

            // Issue the mutation block inside of the context's
            // performAndWait; capture the response
            // TODO: Protect against saving or other invalid MOC operations?
            masterContext.performAndWait {
                do {
                    try block(masterContext)
                } catch {
                    catchBlock.error = error
                    masterContext.reset()
                    return
                }

                // Attempt to save the context
                do {
                    try masterContext.obtainPermanentIDs(for: [NSManagedObject](masterContext.insertedObjects))

                    let queryContext = SlateQueryContext(slate: self, managedObjectContext: masterContext)
                    let oldQueryContext = Thread.current.setInsideQueryContext(queryContext)

                    // Update cache (after getting objects but before saving
                    // so that we are cached for any fetched results controllers
                    self.updateImmutableObjectCache(
                        updates: Slate.toSlateMap(masterContext.updatedObjects),
                        inserts: Slate.toSlateMap(masterContext.insertedObjects),
                        deletes: masterContext.deletedObjects.map(\.objectID)
                    )

                    Thread.current.setInsideQueryContext(oldQueryContext)

                    try masterContext.safeSave()
                } catch {
                    catchBlock.error = error
                    return
                }
            }
        }

        return catchBlock
    }
}

// MARK: - _SlateCatchBlock

/**
 Provides a mechanism to attach a catch statement to a mutation/query scope.  Should
 not be used directly by callers.
 */
public final class _SlateCatchBlock {
    /// Lock providing synchronous access to internal properties
    private let errorLock = NSLock()

    /// The internal error
    private var internalError: SlateTransactionError?

    /// Handle to the owning slate objects
    private weak var slate: Slate?

    /// thread safe access to the internal error
    fileprivate var error: Error? {
        get {
            errorLock.withLock { internalError }
        }
        set {
            errorLock.withLock {
                if let slateError = newValue as? SlateTransactionError {
                    internalError = slateError
                } else if let error = newValue {
                    internalError = .underlying(error)
                } else {
                    internalError = nil
                }
                self.resolveErrorBlock()
            }
        }
    }

    /// The queue to run the catch block on (sync if nil)
    private var queue: DispatchQueue?

    /// The catch block to run.
    private var catchBlock: ((Error) -> Void)?

    /// Was the catchBlock executed?
    private var executed: Bool = false

    /// Prevent public init
    fileprivate init(slate: Slate) {
        self.slate = slate
    }

    /// Prevent uncaught errors
    deinit {
        errorLock.withLock {
            if let err = internalError {
                if !executed, !err.isAborted {
                    slate?.uncaughtTransactionErrorSubject.send(err)
                }
            }
        }
    }

    /**
     Register a catch block to run if there is an error assigned
     */
    public func `catch`(on queue: DispatchQueue? = nil, _ catchBlock: @escaping (Error) -> Void) {
        errorLock.withLock {
            self.queue = queue
            self.catchBlock = catchBlock
            self.resolveErrorBlock()
        }
    }

    /**
     Calls the catch block if there is a block+error.  Run inside lock.
     */
    private func resolveErrorBlock() {
        guard !executed else {
            return
        }

        let _error = internalError
        let _queue = queue
        let _catchBlock = catchBlock

        guard let err = _error, let block = _catchBlock else {
            return
        }

        executed = true

        if let q = _queue {
            q.async {
                block(err)
            }
        } else {
            block(err)
        }
    }
}

// MARK: - _SlateManagedObjectContext

/**
 Despite being a publicly-exposed class, this is not meant to be instantiated.
 Instead, it provides a tap into the `save` method to make sure that higher-
 level code is not calling `save` on the MOC.  Only the Slate should call
 `save` on the MOC internally when the mutation block completes.
 */
public final class _SlateManagedObjectContext: NSManagedObjectContext {
    /// Are we in an internal save call?
    fileprivate var inSafeSave: Bool = false

    /// Run a safe save operation inside of Slate.  Don't need lock
    /// protections since this only run in the MOC perform queue
    fileprivate func safeSave() throws {
        inSafeSave = true
        try save()
        inSafeSave = false
    }

    /// Override save to make sure we are inside a safe save.
    override public func save() throws {
        guard inSafeSave else {
            fatalError("You cannot explicitly call save on a Slate MOC")
        }
        try super.save()
    }
}

// MARK: - SlateObjectConvertible

/**
 Objects that conform to `SlateObjectConvertible` can be converted
 into immutable SlateObjects.

 This should be implemented by any NSManagedObject that can be
 transformed into a corresponding SlateObject
 */
public protocol SlateObjectConvertible: NSFetchRequestResult {
    /// Converts the NSManagedObject into an immutable SlateObject
    var slateObject: SlateObject { get }

    /// Get the objectID of the NSManagedObject that implements this protocol
    var objectID: NSManagedObjectID { get }
}

// MARK: - Thread Keys

private extension Thread {
    /**
     Sets the current SlateQueryContext for thread.  Returns the existing one.
     */
    @discardableResult func setInsideQueryContext(_ queryContext: SlateQueryContext?) -> SlateQueryContext? {
        let result = threadDictionary[kThreadKeySlateQueryContext]
        threadDictionary[kThreadKeySlateQueryContext] = queryContext
        return result as? SlateQueryContext
    }

    /**
     Returns the current SlateQueryContext for thread.
     */
    func containingQueryContext() -> SlateQueryContext? {
        threadDictionary[kThreadKeySlateQueryContext] as? SlateQueryContext
    }
}

public extension Slate {
    static var isThreadInsideQuery: Bool {
        Thread.current.containingQueryContext() != nil
    }
}

// MARK: - SlateQueryContext

/**
 Reads/queries are executed inside of a SlateQueryContext.  A SlateQueryContext
 is generated for each read transaction.  Queries inside of this context return
 immutable value objects representing the snapshot of the data model at the time
 of the query.

 Because of the barrier nature of the single-write, during the SlateQueryContext
 lifecycle you are guaranteed that all queries are operating on an internally
 consistent representation of the object graph that will not be modified in the
 middle of multiple query operations.
 */
public final class SlateQueryContext {
    /// The parent Slate
    fileprivate let slate: Slate

    /// The internal MOC associated with this query context
    fileprivate let managedObjectContext: NSManagedObjectContext

    fileprivate init(slate: Slate, managedObjectContext: NSManagedObjectContext) {
        self.slate = slate
        self.managedObjectContext = managedObjectContext
    }

    /**
     Get an NSManagedObject from its slateID/managedObjectID.  The object is tied to
     the managedObjectContext of this query context.  This is used primarily for
     the SlateRelationshipResolver.
     */
    fileprivate func managedObject(slateID: SlateID) -> NSManagedObject {
        managedObjectContext.object(with: slateID)
    }

    /**
     Begin an object query, e.g. to query for ImmObject:

         context.query(ImmObject.self).filter(...).fetch()
     */
    public func query<SO: SlateObject>(_ objectClass: SO.Type) -> SlateQueryRequest<SO> {
        SlateQueryRequest<SO>(slateQueryContext: self)
    }

    /**
     A subscript shortcut to begin an object query, e.g. to query for ImmObject:

         context[ImmObject.self].filter(...).fetch()
     */
    public subscript<SO: SlateObject>(_ objectClass: SO.Type) -> SlateQueryRequest<SO> {
        SlateQueryRequest<SO>(slateQueryContext: self)
    }

    /**
     Begin a relationship resolver.  e.g. to query for `immObject` instance's relationship `other`:

     context.resolve(immObject).other
     */
    public func resolve<SO: SlateObject>(_ slateObject: SO) -> SlateRelationshipResolver<SO> {
        SlateRelationshipResolver<SO>(context: self, object: slateObject)
    }

    /**
     A subscript shortcut to begin a relationship resolver,
     e.g. to query for `immObject` instance's relationship `other`:

     context[immObject].other
     */
    public subscript<SO: SlateObject>(_ slateObject: SO) -> SlateRelationshipResolver<SO> {
        SlateRelationshipResolver<SO>(context: self, object: slateObject)
    }
}

// MARK: - SlateRelationshipResolver

/**
 The SlateRelationshipResolver is a mechanism to grant a compile-time syntax for querying
 relationships between immutable objects.

 Because of the nature of a changing object graph, it is unwise to attach relationships
 directly to an immutable object.  Instead, relationships must be resolved in the same
 way that object queries are: as a snapshot inside of the query context they are queried
 in.
 */
public final class SlateRelationshipResolver<SO: SlateObject> {
    let context: SlateQueryContext
    let slateObject: SO

    fileprivate init(context: SlateQueryContext, object: SO) {
        self.context = context
        self.slateObject = object
    }

    /**
     The class-specific extensions of SlateRelationshipResolver need access to the
     NSManagedObject representation of their target SlateObject within the context
     of the current query.
     */
    public var managedObject: NSManagedObject {
        context.managedObject(slateID: slateObject.slateID)
    }

    /**
     Converts a set of managed objects into an array of corresponding SlateObjects
     */
    public func convert(_ moSet: Set<AnyHashable>) -> [SlateObject] {
        moSet.map {
            let converible = $0 as! SlateObjectConvertible
            return context.slate.cachedObjectOrCreate(id: converible.objectID, make: { converible.slateObject })
        }
    }

    /**
     Converts a managed objects into the corresponding SlateObject
     */
    public func convert(_ mo: SlateObjectConvertible?) -> SlateObject? {
        guard let obj = mo else {
            return nil
        }
        return context.slate.cachedObjectOrCreate(id: obj.objectID, make: { obj.slateObject })
    }
}

// MARK: - Private Slate Helpers

private extension Slate {
    /**
     This method takes a set of NSManangedObject and
     maps them to a dictionary structure.

     This method only operates on NSManagedObjects that implement the
     SlateObjectConvertible protocol.
     */
    static func toSlateMap(_ managedObjects: Set<NSManagedObject>) -> [SlateID: Any] {
        var response = [SlateID: Any](minimumCapacity: managedObjects.count)

        for mo in managedObjects {
            guard let slateObj = (mo as? SlateObjectConvertible)?.slateObject else {
                continue
            }

            response[slateObj.slateID] = slateObj
        }

        return response
    }
}

/**
 The SlateQueryRequest provides a wrapping around the standard NSFetchRequest in order to
 directly pipe immutable representations of the data model from the query context.

 The chained configuration style helps make the fetch statements a bit more cohesive.

 The SlateQueryRequest fetch methods can ONLY be called from inside a query context block.
 It is a fatalError to attempt to fetch outside of a block.  The fetch will know which
 context it is being called from.
 */
public final class SlateQueryRequest<SO: SlateObject> {
    /// The backing NSFetchRequest that will power this fetch
    private let nsFetchRequest: NSFetchRequest<NSFetchRequestResult>

    /// The backing SlateQueryContext
    private let slateQueryContext: SlateQueryContext

    /**
     Initializes the SlateFetchRequest with the backing NSFetchRequest returned based
     on the generic SlateObject type.
     */
    fileprivate init(slateQueryContext: SlateQueryContext) {
        self.slateQueryContext = slateQueryContext
        self.nsFetchRequest = SO.__slate_managedObjectType.fetchRequest()
    }

    // -------------------------- Filtering ------------------------------

    /**
     Filter the query by a specified predicate.  Will create a compound AND predicate with any
     existing predicates.
     */
    public func filter(_ predicate: NSPredicate) -> SlateQueryRequest<SO> {
        if let currentPredicate = nsFetchRequest.predicate {
            nsFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [currentPredicate, predicate])
        } else {
            nsFetchRequest.predicate = predicate
        }
        return self
    }

    /**
     Filter the query by a specified predicate.  Will create a compound AND predicate with any
     existing predicates.
     */
    public func filter(_ predicateString: String, _ predicateArgs: Any...) -> SlateQueryRequest<SO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return filter(newPredicate)
    }

    /**
     An alias for `filter`.  Semantically, it should come after an initial filter call.
     */
    public func and(_ predicate: NSPredicate) -> SlateQueryRequest<SO> {
        filter(predicate)
    }

    /**
     An alias for `filter`.  Semantically, it should come after an initial filter call.
     */
    public func and(_ predicateString: String, _ predicateArgs: AnyObject...) -> SlateQueryRequest<SO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return and(newPredicate)
    }

    /**
     Creates an OR compound predicate with an existing predicate.
     */
    public func or(_ predicate: NSPredicate) -> SlateQueryRequest<SO> {
        if let currentPredicate = nsFetchRequest.predicate {
            nsFetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [currentPredicate, predicate])
        } else {
            nsFetchRequest.predicate = predicate
        }
        return self
    }

    /**
     Creates an OR compound predicate with an existing predicate.
     */
    public func or(_ predicateString: String, _ predicateArgs: AnyObject...) -> SlateQueryRequest<SO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return or(newPredicate)
    }

    // -------------------------- Sorting ------------------------------

    /**
     Attach a sort descriptor to the fetch using key and ascending.
     */
    public func sort(_ property: String, ascending: Bool = true) -> SlateQueryRequest<SO> {
        let descriptor = NSSortDescriptor(key: property, ascending: ascending)
        return sort(descriptor)
    }

    /**
     Attach a sort descriptor to the fetch using an NSSortDescriptor
     */
    public func sort(_ descriptor: NSSortDescriptor) -> SlateQueryRequest<SO> {
        if nsFetchRequest.sortDescriptors == nil {
            nsFetchRequest.sortDescriptors = [descriptor]
        } else {
            nsFetchRequest.sortDescriptors?.append(descriptor)
        }
        return self
    }

    // ------------------------ Misc Operations --------------------------

    /**
     Specify the limit of objects to query for. This modifies fetchLimit.
     */
    public func limit(_ limit: Int) -> SlateQueryRequest<SO> {
        nsFetchRequest.fetchLimit = limit
        return self
    }

    /**
     Specify the offset to begin the fetch. This modifies fetchOffset.
     */
    public func offset(_ offset: Int) -> SlateQueryRequest<SO> {
        nsFetchRequest.fetchOffset = offset
        return self
    }

    // -------------------------- Fetching ------------------------------

    /**
     Executes the fetch on the current context.  You cannot execute a fetch from
     any scope other than the query scope it was created in.
     */
    public func fetch() throws(SlateTransactionError) -> [SO] {
        guard let currentContext = Thread.current.containingQueryContext() else {
            throw .queryOutsideScope
        }

        guard currentContext === slateQueryContext else {
            throw .queryOutsideScope
        }

        // The slate we are in
        let slate = currentContext.slate

        // The fetch result is now an array of our NSManagedObjects for the SO type
        let fetchResult: [NSFetchRequestResult]
        do {
            fetchResult = try currentContext.managedObjectContext.fetch(nsFetchRequest)
        } catch {
            throw .underlying(error)
        }

        guard let slatableResult = fetchResult as? [SlateObjectConvertible] else {
            throw .queryInvalidCast
        }

        let immResults: [SO] = try slatableResult.map { slatableObject throws(SlateTransactionError) in
            let slateObject = slate.cachedObjectOrCreate(id: slatableObject.objectID, make: { slatableObject.slateObject })
            guard let immObj = slateObject as? SO else {
                throw .queryInvalidCast
            }

            return immObj
        }

        return immResults
    }

    /**
     Executes the fetch on the current context.  You cannot execute a fetch from
     any scope other than the query scope it was created in.
     */
    public func fetchOne() throws(SlateTransactionError) -> SO? {
        let prevLimit = nsFetchRequest.fetchLimit
        nsFetchRequest.fetchLimit = 1
        let result: SO? = try fetch().first
        nsFetchRequest.fetchLimit = prevLimit
        return result
    }

    /**
     Returns the number of objects that match the fetch parameters.  If you are only interested in
     counting objects, this method is much faster than performing a normal fetch and counting
     the objects in the full response array.
     */
    public func count() throws(SlateTransactionError) -> Int {
        guard let currentContext = Thread.current.containingQueryContext() else {
            throw .queryOutsideScope
        }

        guard currentContext === slateQueryContext else {
            throw .queryOutsideScope
        }

        do {
            return try currentContext.managedObjectContext.count(for: nsFetchRequest)
        } catch {
            throw .underlying(error)
        }
    }
}

/**
 The SlateMOCFetchRequest provides a wrapping around the standard NSFetchRequest in order to
 buildable query interface.
 */
public final class SlateMOCFetchRequest<MO: NSManagedObject> {
    /// The backing NSFetchRequest that will power this fetch
    fileprivate let nsFetchRequest: NSFetchRequest<MO>

    /// The backing MOC
    fileprivate let moc: NSManagedObjectContext

    /// Generate a fetched results controller for this query
    public var fetchedResultsController: NSFetchedResultsController<MO> {
        NSFetchedResultsController<MO>(
            fetchRequest: nsFetchRequest,
            managedObjectContext: moc,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }

    /**
     Initializes the SlateFetchRequest with the backing NSFetchRequest returned based
     on the generic SlateObject type.
     */
    fileprivate init(moc: NSManagedObjectContext) {
        self.moc = moc
        self.nsFetchRequest = MO.fetchRequest() as! NSFetchRequest<MO>
    }

    // -------------------------- Filtering ------------------------------

    /**
     Filter the query by a specified predicate.  Will create a compound AND predicate with any
     existing predicates.
     */
    public func filter(_ predicate: NSPredicate) -> SlateMOCFetchRequest<MO> {
        if let currentPredicate = nsFetchRequest.predicate {
            nsFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [currentPredicate, predicate])
        } else {
            nsFetchRequest.predicate = predicate
        }
        return self
    }

    /**
     Filter the query by a specified predicate.  Will create a compound AND predicate with any
     existing predicates.
     */
    public func filter(_ predicateString: String, _ predicateArgs: Any...) -> SlateMOCFetchRequest<MO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return filter(newPredicate)
    }

    /**
     An alias for `filter`.  Semantically, it should come after an initial filter call.
     */
    public func and(_ predicate: NSPredicate) -> SlateMOCFetchRequest<MO> {
        filter(predicate)
    }

    /**
     An alias for `filter`.  Semantically, it should come after an initial filter call.
     */
    public func and(_ predicateString: String, _ predicateArgs: AnyObject...) -> SlateMOCFetchRequest<MO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return and(newPredicate)
    }

    /**
     Creates an OR compound predicate with an existing predicate.
     */
    public func or(_ predicate: NSPredicate) -> SlateMOCFetchRequest<MO> {
        if let currentPredicate = nsFetchRequest.predicate {
            nsFetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [currentPredicate, predicate])
        } else {
            nsFetchRequest.predicate = predicate
        }
        return self
    }

    /**
     Creates an OR compound predicate with an existing predicate.
     */
    public func or(_ predicateString: String, _ predicateArgs: AnyObject...) -> SlateMOCFetchRequest<MO> {
        let newPredicate = NSPredicate(format: predicateString, argumentArray: predicateArgs)
        return or(newPredicate)
    }

    // -------------------------- Sorting ------------------------------

    /**
     Attach a sort descriptor to the fetch using key and ascending.
     */
    public func sort(_ property: String, ascending: Bool = true) -> SlateMOCFetchRequest<MO> {
        let descriptor = NSSortDescriptor(key: property, ascending: ascending)
        return sort(descriptor)
    }

    /**
     Attach a sort descriptor to the fetch using an NSSortDescriptor
     */
    public func sort(_ descriptor: NSSortDescriptor) -> SlateMOCFetchRequest<MO> {
        if nsFetchRequest.sortDescriptors == nil {
            nsFetchRequest.sortDescriptors = [descriptor]
        } else {
            nsFetchRequest.sortDescriptors!.append(descriptor)
        }
        return self
    }

    // ------------------------ Misc Operations --------------------------

    /**
     Specify the limit of objects to query for. This modifies fetchLimit.
     */
    public func limit(_ limit: Int) -> SlateMOCFetchRequest<MO> {
        nsFetchRequest.fetchLimit = limit
        return self
    }

    /**
     Specify the offset to begin the fetch. This modifies fetchOffset.
     */
    public func offset(_ offset: Int) -> SlateMOCFetchRequest<MO> {
        nsFetchRequest.fetchOffset = offset
        return self
    }

    // -------------------------- Fetching ------------------------------

    /**
     Executes the fetch on the current context.  You cannot execute a fetch from
     any scope other than the query scope it was created in.
     */
    public func fetch() throws -> [MO] {
        try moc.fetch(nsFetchRequest)
    }

    /**
     Executes the fetch on the current context.  You cannot execute a fetch from
     any scope other than the query scope it was created in.
     */
    public func fetchOne() throws -> MO? {
        let prevLimit = nsFetchRequest.fetchLimit
        nsFetchRequest.fetchLimit = 1
        let result: MO? = try fetch().first
        nsFetchRequest.fetchLimit = prevLimit
        return result
    }

    /**
     Returns the number of objects that match the fetch parameters.  If you are only interested in
     counting objects, this method is much faster than performing a normal fetch and counting
     the objects in the full response array.
     */
    public func count() throws -> Int {
        try moc.count(for: nsFetchRequest)
    }

    /**
     Performs a NSBatchDeleteRequest against the receiving query, and returns the number
     of items deleted.
     */
    @discardableResult
    public func delete() throws -> Int {
        // This cast is guaranteed to succeed:
        // nsFetchRequest is a NSFetchRequest<MO>, where MO: NSManagedObject, and NSManagedObject: NSFetchRequestResult
        guard let request = nsFetchRequest as? NSFetchRequest<NSFetchRequestResult> else {
            fatalError("NSFetchRequest cast failed -- should never happen")
        }
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        batchDeleteRequest.resultType = NSBatchDeleteRequestResultType.resultTypeObjectIDs
        let result = try moc.execute(batchDeleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID]
        if let objectIDArray {
            let changes = [NSDeletedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [moc])
        }
        return objectIDArray?.count ?? 0
    }
}

public extension NSManagedObjectContext {
    /**
     Begin an object query, e.g. to query for ImmObject:

     context.query(ImmObject.self).filter(...).fetch()
     */
    func query<MO: NSManagedObject>(_ objectClass: MO.Type) -> SlateMOCFetchRequest<MO> {
        SlateMOCFetchRequest<MO>(moc: self)
    }

    /**
     A subscript shortcut to begin an object query, e.g. to query for ImmObject:

     context[ImmObject.self].filter(...).fetch()
     */
    subscript<MO: NSManagedObject>(_ objectClass: MO.Type) -> SlateMOCFetchRequest<MO> {
        SlateMOCFetchRequest<MO>(moc: self)
    }
}

public extension Slate {
    func convert<SO: SlateObject>(managedObjects: [some NSManagedObject]) throws(SlateTransactionError) -> [SO] {
        guard let slatableResult = managedObjects as? [SlateObjectConvertible] else {
            throw .queryInvalidCast
        }

        let immResults: [SO] = try slatableResult.map { slatableObject throws(SlateTransactionError) in
            let slateObject = self.cachedObjectOrCreate(id: slatableObject.objectID, make: { slatableObject.slateObject })
            guard let immObj = slateObject as? SO else {
                throw .queryInvalidCast
            }

            return immObj
        }

        return immResults
    }
}
