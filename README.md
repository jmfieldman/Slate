![Slate](/Misc/Banner/banner.png)

![Swift 4.1](https://img.shields.io/badge/Swift-4.1-orange.svg?style=flat)

# Immutable Data Models for Core Data

Slate is middleware that sits on top of your Core Data object graph and provides:

* Single-writer/multi-reader transactional access to the object graph.
* **Immutable data models** with clean query DSL.

Let's take a quick look at what this means.

```swift
/* Typical Core Data NSManagedObject */
class CDBook: NSManagedObject {
    @NSManaged public var pageCount: Int64
}

/* An immutable version */
struct ImmBook {
    let pageCount: Int
}

slate.queryAsync { context in
    // Run queries on a Core Data object graph that return immutable, non-managed objects.
    // Slate is responsible for the conversion between Core Data and the immutable types.
    let books: [ImmBook] = try context[ImmBook.self].filter("pageCount > 100").fetch()

}.catch { error in
    // The optional trailing catch method allows you to batch all try-based calls inside
    // of the transaction (similar to PromiseKit)
    print(error)
}

slate.mutateAsync { moc in
    // Mutate managed objects in a single-writer MOC.  
    // Insert/delete/updates are announced to all registered listeners on completion. 
    if let cdBook = moc.object(with: someId) as? CDBook {
        cdBook.pageCount = 200
    }

    // The Any? return value is passed to listeners to help implement more intelligent
    // dispatch logic.
    return MutationType.changedPageCount
}
```

*Why would you want an immutable data model access pattern for your Core Data object graph?*

#### Thread safety

Immutable models cannot mutate.  They can be queried/created on a background thread, and used in any
complex sorting/determination logic before sent to the main thread for UI updates (so the main thread stays smooth.)  Immutable
model properties do not have to be synchronized and can be directly accessed.
  
#### Protected Snapshots

Immutable models act similar to snapshots. If you have multiple features using the same underlying object graph, 
Your features are protected from other code mutating their snapshot without their strict knowledge.  This extends
to relationships -- a feature's snapshot of object relationships will not change if another feature removes them.
Instead of will be notified of changes and can refresh/query the relationships when ready.

#### Unidirectional Flow of Information

Immutable models help enforce unidirectional flow of information.  You cannot write methods that "update" immutable
models in situ.  Rather, mutations to the object graph must occur in a manner that enforces transactional
updates to the object graph first, which in turn announce changes to listeners that can re-fetch their snapshot in a
controlled manner.

*What are the downsides of immutable data models on top of Core Data?*

#### No More Faulting

Core Data has the ability to lazy-load managed objects (faulting).  This is mutually exclusive from the
concept of immutable data models.  All of your queried immutable objects in Slate will be loaded completely
and stored in memory.

This means that Slate will not be a good solution if your application constantly queries/updates tens of
thousands of managed objects and you require faulting to keep that efficient.

#### No More Dynamic Relationships

In Core Data you can access a managed object's relationships to dynamically query related objects.  In Slate
you must pre-fetch those relationships as arrays of immutable objects since they are part of a snapshot.  The relationships cannot be fetched outside
of a Slate query context.

## Understanding this Repository

Slate is not a standalone Cocoapod/Carthage library.  It is a suite of a code that you can pick and choose how to integrate
into your application.

#### [SlateLib](SlateLib/Swift_CoreData)

In the current repo, this only contains a Swift + Core Data implementation of Slate.  Other languages and underlying stores may
be supported in the future.

The entire implementation sits inside one swift file.  Aside from being faster to compile, this allows Slate to
use fileprivate to enforce cross-class protection even if you place the code in your top-level application.

You can simply drop ```Slate.swift``` in your app, or make a separate framework and import it.

#### [SlateGenerator](SlateGenerator)

This is a separate application for generating the immutable versions of your Core Data models.  It reads your xcdatamodel XML file
and outputs the required class/structs.  Check the README in the SlateGenerator directory for details and usage.


#### [UpdatableListNode](UpdatableListNode)

This is a simple protocol that can help generate the update/delete/move/reload indexes to update one list into another.
This is used primarily in the UITableView/UICollectionView ```performBatchUpdates``` method, and is provided since
```NSFetchedResultsController``` cannot be used in conjunction with Slate.

