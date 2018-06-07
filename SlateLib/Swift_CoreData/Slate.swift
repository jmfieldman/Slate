//
//  Slate.swift
//  Swift -- Core Data
//
//  Copyright (c) 2018-Present Jason Fieldman - https://github.com/jmfieldman/Slate
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import CoreData

// MARK: - Private Constants

/// The thread key for the current SlateQueryContext
private let kThreadKeySlateQueryContext = "kThreadKeySlateQueryContext"

// MARK: - SlateError

public enum SlateError: Error {
    case alreadyConfigured
    case storageURLRequired
    case storageURLAlreadyInUse
    case queryOutsideScope
    case queryInvalidCast
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

// MARK: - SlateListener

/**
 Any object may register itself as a SlateMutationListener.  It will receive
 the results of any call to a Slate mutation method.
 */
public protocol SlateMutationListener: AnyObject {
    
    /**
     When a Slate instance is mutated, it will call `slateMutationHandler` on
     all registed listeners.
     
     In order to guarantee that the listeners can read from the context before subsequent
     mutations can occur (for state consistency with the inserted/deleted/updated results),
     the Slate instance will issue these announcements synchronously inside its R/W access
     queue in the same block that the mutation occurred.  In essence, the listener
     implementations of `slateMutationHandler` are extensions of the sync mutation block
     with access to a query context into that transaction.  (All other reads are blocked until
     all `slateMutationHandler` calls return.)
     */
    func slateMutationHandler(result: SlateMutationResult)
}

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

// MARK: - SlateChangeDictionaries

/**
 Contains dictionaries of all changes for a single SlateObject type that occurred in
 a mutation block.
 */
public struct SlateChangeDictionaries<T: SlateObject> {
    public let inserted: [SlateID: T]
    public let deleted: [SlateID: T]
    public let updated: [SlateID: T]
}

// MARK: - __SlateAbort

/**
 This is a no-op class that can be used to signal a mutation block to abort
 (i.e. Slate will NOT run the `save` method on the MOC after the mutation
 block is complete.)  See `Slate.abort`
 */
public class __SlateAbort {
    
}

// MARK: - SlateMutationResult

/**
 Contains all metadata for the result of a single Slate mutation block.  This result
 is sent to all listeners of the Slate instance per mutation.
 */
public class SlateMutationResult {
    
    /**
     The Slate instance that was mutated
     */
    public let slate: Slate
    
    /**
     A query context that listeners can use to run follow-up queries before a
     subsequent write block is issued (in case there is additional data the listener
     must read out from a consistent view of the model.)  This context blocks other reads.
     */
    public let queryContext: SlateQueryContext
    
    /**
     Contains the return value of the mutation block.  This acts as a
     traditional void pointer that allows higher-level user code to pass
     an arbitrary value from the mutation block on to the listeners.
     */
    public let mutationBlockResult: Any?
    
    /**
     All update results from the block.  This is derived from the mutation MOC
     and converted into immutable SlateObject instances.  Accessed through the
     `changes` function that returns type-safe results
     */
    private let internalUpdateMap: [AnyHashable: [SlateID: Any]]
    
    /**
     All delete results from the block.  This is derived from the mutation MOC
     and converted into immutable SlateObject instances.  Accessed through the
     `changes` function that returns type-safe results
     */
    private let internalDeleteMap: [AnyHashable: [SlateID: Any]]
    
    /**
     All insert results from the block.  This is derived from the mutation MOC
     and converted into immutable SlateObject instances.  Accessed through the
     `changes` function that returns type-safe results
     */
    private let internalInsertMap: [AnyHashable: [SlateID: Any]]
    
    /**
     This is a cache of the generated internal change dictionaries that are
     created lazily as they are accessed (to prevent second instantiations).
     */
    private var internalChangeDictionaryCache: [AnyHashable: Any] = [:]
    
    /**
     Initializing the SlateMutationResult can only be done from this implementation.
     */
    fileprivate init(
        slate: Slate,
        blockResult: Any?,
        queryContext: SlateQueryContext,
        updateMap: [AnyHashable: [SlateID: Any]],
        deleteMap: [AnyHashable: [SlateID: Any]],
        insertMap: [AnyHashable: [SlateID: Any]])
    {
        self.slate = slate
        self.mutationBlockResult = blockResult
        self.queryContext = queryContext
        self.internalUpdateMap = updateMap
        self.internalDeleteMap = deleteMap
        self.internalInsertMap = insertMap
    }
    
    /**
     Returns type-safe changes for the specified SlateObject type.
     */
    public func changes<T: SlateObject>(_ objectClass: T.Type) -> SlateChangeDictionaries<T>? {
        
        let hashKey = "\(objectClass)"
        
        // Return cached value
        if let cached = self.internalChangeDictionaryCache[hashKey] as? SlateChangeDictionaries<T> {
            return cached
        }
        
        // Otherwise generate and cache
        let changeDic = SlateChangeDictionaries<T>(
            inserted: (internalInsertMap[hashKey] as? [SlateID: T]) ?? [:],
            deleted: (internalDeleteMap[hashKey] as? [SlateID: T]) ?? [:],
            updated: (internalUpdateMap[hashKey] as? [SlateID: T]) ?? [:])
        
        self.internalChangeDictionaryCache[hashKey] = changeDic
        return changeDic
    }
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
public class Slate {
 
    // MARK: Private Properties
    
    /// The NSManagedObjectModel associated with this Slate
    private var managedObjectModel: NSManagedObjectModel? = nil
    
    /// The NSPersistentStoreDescription associated with this Slate
    private var persistentStoreDescription: NSPersistentStoreDescription? = nil
    
    /// The master NSPersistentStoreCoordinator associated with this Slate, assigned
    /// during initialization
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator? = nil
    
    /// The master context associated with the Slate.  This is the context that handles
    /// mutations, and is also the parent for read contexts.
    private var masterContext: _SlateManagedObjectContext? = nil
    
    /// The read/write dispatch queue to execute context access
    private let accessQueue: DispatchQueue
    
    /// The configuration dispatch queue
    private let configQueue: DispatchQueue
    
    /// Indicates that we have been configured
    private var configured: Bool = false
    
    /// The access lock for the global unique store URL check
    private static let storeUrlCheckLock: NSLock = NSLock()
    
    /// The set of on-disk persistent store URLs used by all instantiated Slates.
    /// It is considered a fatalError to instantiate multiple Slates that use the
    /// same storeUrl.
    private static var storeUrlSet: Set<URL> = Set<URL>()
    
    // MARK: Initialization
    
    /**
     Initialize the Slate with a given NSManagedObjectModel and NSPersistentStoreDescription.
     The completion handler is passed directly into the associated addPersistentStore method when
     configuring the internal NSPersistentStoreCoordinator.
     This is the main designated initializer.
    */
    public init() {
        
        // Config Queue
        self.configQueue = DispatchQueue(label: "Slate.configQueue",
                                         qos: .default,
                                         attributes: [],
                                         autoreleaseFrequency: .workItem,
                                         target: nil)
        
        // Access Queue
        self.accessQueue = DispatchQueue(label: "Slate.accessQueue",
                                         qos: .default,
                                         attributes: [.concurrent, .initiallyInactive],
                                         autoreleaseFrequency: .workItem,
                                         target: nil)
    }
    
    // MARK: Deinit
    
    deinit {
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
        completionHandler: @escaping (NSPersistentStoreDescription, Error?) -> Void)
    {
        self.configQueue.async {
            guard !self.configured else {
                completionHandler(persistentStoreDescription, SlateError.alreadyConfigured)
                return
            }
            
            // Validate and insert the storeURL for disk-based persistent stores.
            if (persistentStoreDescription.type != NSInMemoryStoreType) {
                guard let storeURL = persistentStoreDescription.url else {
                    completionHandler(persistentStoreDescription, SlateError.storageURLRequired)
                    return
                }
                
                Slate.storeUrlCheckLock.lock()
                if Slate.storeUrlSet.contains(storeURL) {
                    Slate.storeUrlCheckLock.unlock()
                    completionHandler(persistentStoreDescription, SlateError.storageURLAlreadyInUse)
                    return
                }
                Slate.storeUrlSet.insert(storeURL)
                Slate.storeUrlCheckLock.unlock()
            }
            
            // Assign properties
            self.managedObjectModel = managedObjectModel
            self.persistentStoreDescription = persistentStoreDescription
            
            // The configuration will wait on the persistent store addition
            let semaphore = DispatchSemaphore(value: 0)
            
            // The PSC is created and attached to the store
            self.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
            self.persistentStoreCoordinator?.addPersistentStore(with: persistentStoreDescription) { desc, error in
                // If the PSC is configured properly we can spin up the access queue
                if error == nil {
                    self.configured = true
                    self.accessQueue.activate()
                }
                
                // Call our parent completion handler
                completionHandler(desc, error)
                
                // Done
                semaphore.signal()
            }
            
            let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
            
            // The master MOC is created and attached to the PSC
            self.masterContext = _SlateManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            self.masterContext?.persistentStoreCoordinator = self.persistentStoreCoordinator
            self.masterContext?.undoManager = nil
        }
    }
    
    // MARK: Immutable Object Cache
    
    /// The immutable object cache -- Cannot use NSCache because it does not support
    /// Swift structs as values
    private var immObjectCache: [SlateID: Any] = [:]
    
    /// Fast locking mechanism for immObjectCache
    private var immObjectCacheLock: os_unfair_lock_s = os_unfair_lock_s()
    
    /**
     Run bulk immutable object cache updates inside lock
     */
    fileprivate func updateImmObjectCache(with updates: [[SlateID: Any]], deletes: [[SlateID: Any]]) {
        os_unfair_lock_lock(&immObjectCacheLock)
        for dictionary in updates {
            for (objId, obj) in dictionary {
                if self.immObjectCache[objId] != nil {
                    self.immObjectCache[objId] = obj
                }
            }
        }
        
        for dictionary in deletes {
            for objId in dictionary.keys {
                self.immObjectCache[objId] = nil
            }
        }
        os_unfair_lock_unlock(&immObjectCacheLock)
    }
    
    /**
     Returns the cached object for the given SlateID if it exists.  Otherwise it uses
     the make block to create the SlateObject, cache it, and return it.
     */
    fileprivate func cachedObjectOrCreate(id: SlateID, make: () -> SlateObject) -> SlateObject {
        os_unfair_lock_lock(&immObjectCacheLock)
        if let slateObj = self.immObjectCache[id] as? SlateObject {
            os_unfair_lock_unlock(&immObjectCacheLock)
            return slateObj
        }
        
        let slateObj = make()
        self.immObjectCache[id] = slateObj
        os_unfair_lock_unlock(&immObjectCacheLock)
        return slateObj
    }
    
    // MARK: Listeners
    
    /// The array of listeners
    private var listeners: [ObjectIdentifier: SlateAnnounceNode] = [:]
    
    /// The listener array lock
    private let listenersLock: NSLock = NSLock()
    
    /**
     Attach an object as a listener to the slate
     */
    public func addListener(_ listener: SlateMutationListener) {
        listenersLock.lock()
        listeners[ObjectIdentifier(listener)] = SlateAnnounceNode(listener: listener)
        listenersLock.unlock()
    }
    
    /**
     Remove an object as a listener to the slate
     */
    public func removeListener(_ listener: SlateMutationListener) {
        listenersLock.lock()
        listeners[ObjectIdentifier(listener)] = nil
        listenersLock.unlock()
    }
    
    /**
     This private announce function is called to announce mutation results to
     all listeners.  Any listener node whose weak reference is nil will be removed
     automatically (listeners do not have to explicitly remove themselves during deinit).
     */
    private func announce(_ mutationResult: SlateMutationResult) {
        listenersLock.lock()
        var toRemove: [ObjectIdentifier] = []
        for (objId, node) in listeners {
            if let listener = node.listener {
                listener.slateMutationHandler(result: mutationResult)
            } else {
                toRemove.append(objId)
            }
        }
        for objId in toRemove {
            listeners.removeValue(forKey: objId)
        }
        listenersLock.unlock()
    }
    
    // MARK: Query
    
    /**
     The `querySync` function grants a synchronous read scope into the
     core data graph.  The user-submitted block is run synchronously on the
     multi-reader queue.  The scope only permits reading immutable
     data model representations of the core data graph objects.
     */
    @discardableResult public func querySync (block: (SlateQueryContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock()
        
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
        
        self.accessQueue.sync {
            
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
    @discardableResult public func queryAsync (block: @escaping (SlateQueryContext) throws -> Void) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock()
        
        self.accessQueue.async {
            
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
    @discardableResult public func mutateSync (block: (NSManagedObjectContext) throws -> Any?) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock()
        
        self.accessQueue.sync(flags: .barrier) {
            guard let masterContext = self.masterContext else {
                return
            }
            
            // Issue the mutation block inside of the context's
            // performAndWait; capture the response
            // TODO: Protect against saving or other invalid MOC operations?
            masterContext.performAndWait {
                
                var userBlockResponse: Any? = nil
                do {
                    userBlockResponse = try block(masterContext)
                } catch {
                    catchBlock.error = error
                    return
                }
                
                // Bail on abort
                guard (userBlockResponse as? __SlateAbort) !== Slate.abort else {
                    return masterContext.reset()
                }
                
                // Construct the state change maps (MUST DO BEFORE SAVING)
                var updateMap: [AnyHashable: [SlateID: Any]]!
                var deleteMap: [AnyHashable: [SlateID: Any]]!
                var insertMap: [AnyHashable: [SlateID: Any]]!
                
                // Attempt to save the context
                do {
                    try masterContext.obtainPermanentIDs(for: Array<NSManagedObject>(masterContext.insertedObjects))
                    updateMap = Slate.toSlateChangeMap(masterContext.updatedObjects)
                    deleteMap = Slate.toSlateChangeMap(masterContext.deletedObjects)
                    insertMap = Slate.toSlateChangeMap(masterContext.insertedObjects)
                    try masterContext.safeSave()
                } catch {
                    catchBlock.error = error
                    return
                }
                
                // Create a query context for the handler
                let queryContext = SlateQueryContext(slate: self, managedObjectContext: masterContext)
                let oldQueryContext = Thread.current.setInsideQueryContext(queryContext)
                
                // Generate the mutation result
                let mutationResult = SlateMutationResult(slate: self,
                                                         blockResult: userBlockResponse,
                                                         queryContext: queryContext,
                                                         updateMap: updateMap,
                                                         deleteMap: deleteMap,
                                                         insertMap: insertMap)
                
                // Update cache
                self.updateImmObjectCache(with: Array(updateMap.values), deletes: Array(deleteMap.values))
                
                // The announcement is made within the perform queue of the
                // masterContext (since it is being used for reads in the query context)
                self.announce(mutationResult)
                
                // Reset query context
                Thread.current.setInsideQueryContext(oldQueryContext)
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
    @discardableResult public func mutateAsync (block: @escaping (NSManagedObjectContext) throws -> Any?) -> _SlateCatchBlock {
        let catchBlock = _SlateCatchBlock()
        
        self.accessQueue.async(flags: .barrier) {
            guard let masterContext = self.masterContext else {
                return
            }
            
            // Issue the mutation block inside of the context's
            // performAndWait; capture the response
            // TODO: Protect against saving or other invalid MOC operations?
            masterContext.performAndWait {
                
                var userBlockResponse: Any? = nil
                do {
                    userBlockResponse = try block(masterContext)
                } catch {
                    catchBlock.error = error
                    return
                }
                
                // Bail on abort
                guard (userBlockResponse as? __SlateAbort) !== Slate.abort else {
                    return masterContext.reset()
                }
                
                // Construct the state change maps (MUST DO BEFORE SAVING)
                var updateMap: [AnyHashable: [SlateID: Any]]!
                var deleteMap: [AnyHashable: [SlateID: Any]]!
                var insertMap: [AnyHashable: [SlateID: Any]]!
                
                // Attempt to save the context
                do {
                    try masterContext.obtainPermanentIDs(for: Array<NSManagedObject>(masterContext.insertedObjects))
                    updateMap = Slate.toSlateChangeMap(masterContext.updatedObjects)
                    deleteMap = Slate.toSlateChangeMap(masterContext.deletedObjects)
                    insertMap = Slate.toSlateChangeMap(masterContext.insertedObjects)
                    try masterContext.safeSave()
                } catch {
                    catchBlock.error = error
                    return
                }
                
                // Create a query context for the handler
                let queryContext = SlateQueryContext(slate: self, managedObjectContext: masterContext)
                let oldQueryContext = Thread.current.setInsideQueryContext(queryContext)
                
                // Generate the mutation result
                let mutationResult = SlateMutationResult(slate: self,
                                                         blockResult: userBlockResponse,
                                                         queryContext: queryContext,
                                                         updateMap: updateMap,
                                                         deleteMap: deleteMap,
                                                         insertMap: insertMap)
                
                // Update cache
                self.updateImmObjectCache(with: Array(updateMap.values), deletes: Array(deleteMap.values))
                
                // The announcement is made within the perform queue of the
                // masterContext (since it is being used for reads in the query context)
                self.announce(mutationResult)
                
                // Reset query context
                Thread.current.setInsideQueryContext(oldQueryContext)
            }
        }
        
        return catchBlock
    }
    
    /// Return `Slate.abort` from a mutation block and Slate will `reset` the master MOC
    /// rather than saving it.  A mutation result will NOT be broadcast to
    /// listeners (there will have been no mutation).
    public static let abort: __SlateAbort = __SlateAbort()
}

// MARK: - _SlateCatchBlock

/**
 Provides a mechanism to attach a catch statement to a mutation/query scope.  Should
 not be used directly by callers.
 */
public class _SlateCatchBlock {
    
    /// Lock providing synchronous access to internal properties
    private let errorLock: NSLock = NSLock()
    
    /// The internal error
    private var internalError: Error?
    
    /// thread safe access to the internal error
    fileprivate var error: Error? {
        get {
            return errorLock.get { internalError }
        }
        set {
            errorLock.do {
                internalError = newValue
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
    
    private static let defaultCatchBlock: ((Error) -> Void) = { error in
        fatalError("Uncaught try resulted in error: \(error)")
    }
    
    /// Prevent public init
    fileprivate init() { }
    
    /// Prevent uncaught errors
    deinit {
        errorLock.do {
            if let err = internalError {
                if !executed {
                    _SlateCatchBlock.defaultCatchBlock(err)
                }
            }
        }
    }
    
    /**
     Register a catch block to run if there is an error assigned
     */
    public func `catch`(on queue: DispatchQueue? = nil, _ catchBlock: @escaping (Error) -> Void) {
        errorLock.do {
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
        
        let _error = self.internalError
        let _queue = self.queue
        let _catchBlock = self.catchBlock
        
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
public class _SlateManagedObjectContext: NSManagedObjectContext {
    
    /// Are we in an internal save call?
    fileprivate var inSafeSave: Bool = false
    
    /// Run a safe save operation inside of Slate.  Don't need lock
    /// protections since this only run in the MOC perform queue
    fileprivate func safeSave() throws {
        inSafeSave = true
        try self.save()
        inSafeSave = false
    }
    
    /// Override save to make sure we are inside a safe save.
    public override func save() throws {
        guard inSafeSave else {
            fatalError("You cannot explicitly call save on a Slate MOC")
        }
        try super.save()
    }
}

// MARK: - SlateAnnounceNode

/**
 This is a node that captures a weak reference to a SlateListener
 */
fileprivate struct SlateAnnounceNode {
    fileprivate weak var listener: SlateMutationListener?;
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

// MARK: - Private Lock Helper

private extension NSLock {
    func `do`(_ block: () -> Void) {
        self.lock()
        block()
        self.unlock()
    }
    
    func `get`<T>(_ block: () -> T) -> T {
        self.lock()
        let t = block()
        self.unlock()
        return t
    }
}

// MARK: - Thread Keys

fileprivate extension Thread {
    /**
     Sets the current SlateQueryContext for thread.  Returns the existing one.
     */
    @discardableResult fileprivate func setInsideQueryContext(_ queryContext: SlateQueryContext?) -> SlateQueryContext? {
        let result = self.threadDictionary[kThreadKeySlateQueryContext]
        self.threadDictionary[kThreadKeySlateQueryContext] = queryContext
        return result as? SlateQueryContext
    }
    
    /**
     Returns the current SlateQueryContext for thread.
     */
    fileprivate func containingQueryContext() -> SlateQueryContext? {
        return self.threadDictionary[kThreadKeySlateQueryContext] as? SlateQueryContext
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
public class SlateQueryContext {
    
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
        return self.managedObjectContext.object(with: slateID)
    }
    
    /**
     Begin an object query, e.g. to query for ImmObject:
     
         context.query(ImmObject.self).filter(...).fetch()
     */
    public func query<SO: SlateObject>(_ objectClass: SO.Type) -> SlateQueryRequest<SO> {
        return SlateQueryRequest<SO>(slateQueryContext: self)
    }
    
    /**
     A subscript shortcut to begin an object query, e.g. to query for ImmObject:
     
         context[ImmObject.self].filter(...).fetch()
     */
    public subscript<SO: SlateObject>(_ objectClass: SO.Type) -> SlateQueryRequest<SO> {
        return SlateQueryRequest<SO>(slateQueryContext: self)
    }
    
    /**
     Begin a relationship resolver.  e.g. to query for `immObject` instance's relationship `other`:
     
     context.resolve(immObject).other
     */
    public func resolve<SO: SlateObject>(_ slateObject: SO) -> SlateRelationshipResolver<SO> {
        return SlateRelationshipResolver<SO>(context: self, object: slateObject)
    }
    
    /**
     A subscript shortcut to begin a relationship resolver,
     e.g. to query for `immObject` instance's relationship `other`:
     
     context[immObject].other
     */
    public subscript<SO: SlateObject>(_ slateObject: SO) -> SlateRelationshipResolver<SO> {
        return SlateRelationshipResolver<SO>(context: self, object: slateObject)
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
public class SlateRelationshipResolver<SO: SlateObject> {
    
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
        return context.managedObject(slateID: self.slateObject.slateID)
    }
    
    /**
     Converts a set of managed objects into an array of corresponding SlateObjects
     */
    public func convert(_ moSet: Set<AnyHashable>) -> [SlateObject] {
        return moSet.map {
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

fileprivate extension Slate {
    
    /**
     This method takes a sets of NSManangedObject and
     maps them to a dictionary structure that can be imported into
     the mutation results as change maps.
     
     This method only operates on NSManagedObjects that implement the
     SlateObjectConvertible protocol.
     */
    fileprivate static func toSlateChangeMap(_ managedObjects: Set<NSManagedObject>) -> [AnyHashable: [SlateID: Any]] {
        var response: [AnyHashable: [SlateID: Any]] = [:]
        let defaultDic: [SlateID: Any] = Dictionary<SlateID, Any>.init(minimumCapacity: managedObjects.count)
        
        for mo in managedObjects {
            guard let slateObj = (mo as? SlateObjectConvertible)?.slateObject else {
                continue
            }
            
            let hashKey = "\(type(of: slateObj))"
            response[hashKey, default: defaultDic][slateObj.slateID] = slateObj
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
public class SlateQueryRequest<SO: SlateObject> {
    
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
        return filter(predicate)
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
            nsFetchRequest.sortDescriptors!.append(descriptor)
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
    public func fetch() throws -> [SO] {
        guard let currentContext = Thread.current.containingQueryContext() else {
            throw SlateError.queryOutsideScope
        }
        
        guard currentContext === self.slateQueryContext else {
            throw SlateError.queryOutsideScope
        }
        
        // The slate we are in
        let slate = currentContext.slate
        
        // The fetch result is now an array of our NSManagedObjects for the SO type
        let fetchResult = try currentContext.managedObjectContext.fetch(nsFetchRequest)
        guard let slatableResult = fetchResult as? [SlateObjectConvertible] else {
            throw SlateError.queryInvalidCast
        }
        
        let immResults: [SO] = try slatableResult.map { slatableObject in
            let slateObject = slate.cachedObjectOrCreate(id: slatableObject.objectID, make: { slatableObject.slateObject })
            guard let immObj = slateObject as? SO else {
                throw SlateError.queryInvalidCast
            }
            
            return immObj
        }
        
        return immResults
    }
    
    /**
     Executes the fetch on the current context.  You cannot execute a fetch from
     any scope other than the query scope it was created in.
     */
    public func fetchOne() throws -> SO? {
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
    public func count() throws -> Int {
        guard let currentContext = Thread.current.containingQueryContext() else {
            throw SlateError.queryOutsideScope
        }
        
        guard currentContext === self.slateQueryContext else {
            throw SlateError.queryOutsideScope
        }
        
        return try currentContext.managedObjectContext.count(for: nsFetchRequest)
    }
}
