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
/// Performs an async query on the Slate Core Data context and returns immutable
/// Book objects representing CoreDataBook NSManagedObjects.
func fetchBooksWithAtLeast(pageCount: Int) async throws -> [Book] {
  try await slate.query { readContext in
    return try readContext[Book.self].filter("pageCount > \(pageCount)").fetch()
  }
}
```

Continue to use NSManagedObjectContext for writes, but operate in a safe single-write/multi-read queue:

```swift
/// Perform mutations on a barrier transaction using a standard NSManagedObjectContext
/// using your typical Core Data classes. Slate protects against mutations leaking
/// outside of this block.
func updateBookPageCount(bookId: UUID, newPageCount: Int) async throws {
  try await slate.mutate { writeContext in
    if let book = try writeContext[CoreDataBook.self].filter("id = %@", id).fetchOne() {
      book.pageCount = newPageCount
    }
  }
}
```

## Immutable Access Tradeoffs

*Why would you want an immutable data model access pattern for your Core Data object graph?*

### Thread safety

Slate immutable models guarantee Sendable conformance. They can be queried/created on a background thread, and used in any complex sorting/determination logic before sent to the main thread for UI updates. Immutable model properties do not have to be synchronized and can be directly accessed.
  
### Protected Snapshots

Immutable models act similar to snapshots. If you have multiple features using the same underlying object graph, your features are protected from other code mutating their snapshot without their strict knowledge.  This extends to relationships -- one feature's snapshot of object relationships will not change if another feature removes them.

### Unidirectional Flow of Information

Immutable models help enforce unidirectional flow of information.  You cannot write methods that "update" immutable models outside of a mutation context.  Rather, mutations to the object graph *must* occur in a manner that enforces transactional updates to the object graph.

*What are the downsides of immutable data models on top of Core Data?*

### No More Faulting

Core Data has the ability to lazy-load managed objects (faulting).  This is mutually exclusive from the
concept of immutable data models.  All of your queried immutable objects in Slate will be completely loaded.

This means that Slate will not be a good solution if your application constantly queries/updates tens of
thousands of managed objects and you require faulting to keep that efficient.

### No More Dynamic Relationships

In Core Data you can access a managed object's relationships to dynamically query related objects.  In Slate
you must pre-fetch those relationships as arrays of immutable objects since they are part of a snapshot.  The relationships cannot be fetched outside
of a Slate query context.

## Understanding this Repository

Slate is not a standalone Cocoapod/Carthage library.  It is a suite of a code that you can pick and choose how to integrate into your application.

#### [Slate](Slate/Slate.swift)

The main implementation of the Slate framework that is imported into your project.

#### [slategen](SlateGenerator)

This is a separate application for generating the immutable versions of your Core Data models.  It reads your xcdatamodel XML file and outputs the required class/structs.  Check the README in the SlateGenerator directory for details and usage.

