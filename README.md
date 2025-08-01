![Slate](/Misc/Banner/banner.png)

# Immutable Data Models for Core Data

Slate is middleware that sits on top of your Core Data object graph and provides:

* Single-writer/multi-reader transactional access to the object graph.
* **Immutable data models** with a clean query DSL.

> Note: If you're looking for an earlier version of Slate pre-2025, check out the `0.0.2` tag.

## By Example

Take your typical Core Data NSManagedObjects:

```swift
class CoreDataBook: NSManagedObject {
  @NSManaged public var id: UUID
  @NSManaged public var pageCount: Int64
}
```

Slate automatically generates immutable representations:

```swift
/* Auto-generated */
final class Book {
  let id: UUID
  let pageCount: Int
}
```

Query from a read-only context that provides these immutable versions of your Core Data model:

```swift
func fetchBooksWithAtLeast(pageCount: Int, completion: ([Book]) -> Void) {
  slate.queryAsync { readContext in
    // Run queries on a Core Data object graph proxy that returns immutable objects.
    // Slate handles the conversion behind the scenes.
    let books = try readContext[Book.self].filter("pageCount > \(pageCount)").fetch()
    
    // You can now pass `books` around wherever you want in a thread-safe manner.
    // They are fully immutable and thread-safe.    
    completion(books)

  }.catch { error in
    // The optional trailing catch method allows you to batch all try-based calls inside
    // of the transaction (similar to PromiseKit)
    print(error)
  }
}
```

Continue to use NSManagedObjectContext for writes, but operate in a safe single-write/multi-read queue:

```swift
func updateBookPageCount(id: UUID, newPageCount: Int) {
  slate.mutateAsync { moc in
    // Mutate NSManagedObjects in a single-writer MOC. Insert/delete/updates are 
    // announced to all registered listeners on completion of the mutation block. 
    if let book = try moc[CoreDataBook.self].filter("id = %@", id).fetchOne() {
      book.pageCount = newPageCount
    }

    // An optional Any? return value is passed along to transaction listeners
    // to help indicate the context of the transaction.
    return ExampleEnum.updatePageCount(id: id)
  }
}
```

Listen to transactions:

```swift
class SomeClass: SlateMutationListener {
  func slateMutationHandler(result: SlateMutationResult) {
    // Handle Slate Mutation
  }
}

...
let myClass = SomeClass()
slate.addListener(myClass)
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

