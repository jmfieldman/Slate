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
func fetchBooksWithMoreThan(pageCount: Int) async throws -> [Book] {
    try await slate.query { readContext in
        return try readContext[Book.self]
            .filter(where: \.pageCount, .greaterThan(pageCount))
            .fetch()
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
        if let book = try writeContext[CoreDataBook.self]
            .filter(where: \.id, .equals(bookId))
            .fetchOne() 
        {
            book.pageCount = newPageCount
        }
    }
}
```

You can also stream NSFetchedResultsController updates through a Combine publisher to reactively observe a collection represented by a filter/sort query:

```swift
/// Creates an AnyPublisher<Slate.StreamUpdate, SlateTransactionError>.
/// The StreamUpdate struct contains information such as the current sorted
/// array of values, and the inserted/updated/deleted/moved indexes since
/// the last update.
let streamPublisher = slate.stream { request -> SlateQueryRequest<Book> in
    // Return the request modified by filter/sort instructions
    return request.sort(\.pageCount)
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

## How to Setup Slate

### `xcdatamodel`

The first step to using Slate is to create a new Data Model file. You can use `New > File from Template > Core Data > Data Model`. There is basic documentation for creating the Data Model [here](https://developer.apple.com/documentation/coredata/creating-a-core-data-model). Ultimately, you will create one or more Core Data Entities in this Data Model.  

It is important to consider module abstraction at this point. If you are going to have a lot of entities in your entire app, consider creating separate Data Model files for each logical group of Entities that will be used inside of its own implementation module. The correct architecture pattern is to contain each data model and its Core Data NSManagedObject classes completely inside the single implementation module that will perform query/mutations on the Core Data context.

Make sure that you set the Codegen property of each Entity to `Manual/None`, since compiler-generated classes will conflict with those created by `slategen`.

#### `class` vs. `struct`

Slate will derive the immutable types using `class` by default. Core Data objects are typically larger, stable objects that benefit from reference semantics when passed around your code.

In a scenario where an Entity type is going to have its values constantly mutated, it may be more appropriate to use `struct` to avoid thrashing the heap each time new instantiations of the immutable type are required. You can do this per-Entity by adding the key/value pair `struct`: `true` to the Entity's User Info dictionary in the data model.

### `slategen` - The Model code generator

This is a Swift application used to generate both the Core Data NSManagedObject classes, and the Immutable types derived from them.

You can execute `slategen` using your preferred method of running Swift package executables. We recommend [Mint](https://github.com/yonaskolb/Mint):

```bash
$ brew install mint

$ cat Mintfile
jmfieldman/Slate

# Example arguments
$ mint run slategen gen-core-data \
  --input-model <path-to-implementation-module>/SlateTests.xcdatamodel \
  --output-core-data-entity-path <path-to-implementation-module>/DatabaseModels \
  --output-slate-object-path <path-to-api-module>/ImmutableModels \		
  --cast-int \
  --core-data-file-imports "Slate, ImmutableModels"
```

There is a practical example in the [Makefile](Makefile) for `setuptests` to generate unit test types.

#### `--input-model`

This is the path to the Data Model. On disk this path is a directory that contains a `contents` XML file. `slategen` will parse that XML file for code generation.

#### `--output-core-data-entity-path`

The path to emit the generated Core Data NSManagedObject classes. These should be put into an implementation module where they will be used by a `Slate` instance to modify the data model owned by that implementation.

#### `--output-slate-object-path`

The path to emit the slate/immutable objects derived from your Core Data entity definitions. These should be put in a broadly-accessible API module, and can be used throughout your application stack.

#### `--no-int-cast`

Core Data defines its integer types with specific byte counts, and uses `Int16`, `Int32` and `Int64` in its managed objects when you choose to use scalar types.

Slate will automatically cast these to `Int` when converting to the immutable versions of your objects. If you do not want this automatic conversion you can pass `--no-int-cast` to keep the more strictly-sized primitives.

#### `-f`

Forces the creation of intermediate directories during file generation, if they are not already created.

#### `--core-data-file-imports`

Pass a comma-separated list of modules to import in the generated Core Data files. At the very least you must import where Slate is provided (usually `Slate`), and you must import the API module that the immutable types are generated into.

#### `--name-transform`, `--file-transform`

In your Core Data model, you can choose both an Entity name and a Core Data class name. The best practice is to keep the Entity name as semantically-correct as possible, e.g. "Author", "Book", etc. 

Your Core Data class name can have a prefix so that you know it is the managed version, e.g. "ManagedAuthor", or "CoreDataAuthor". The Core Data classes typically do not get exposed outside of one implementation module.

These generator parameters allow you to add a custom mutation of the Entity name when generating the immutable types. The string you pass in must contain "%@" which is replaced by the Entity name.

For example, if you use "Slate%@" then the entity Book would become SlateBook. These parameters affect the type name, and the filename it is created in.

You can ignore these parameters if you want the immutable types to have the same names as your Entities.

## How to Use the Slate Library 

Once your models are generated and the files are compiling properly in your application, all you need to do is instantiate a `Slate` instance in your implementation module:

```swift
// Can be an ivar of your manager class
let slate = Slate()

// Inside your manager's init/begin; first get your data model
guard 
  let momPath = Bundle.main.path(forResource: "YourDataModel", ofType: "mom"),
  let managedObjectModel = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: basePath))
else {
    throw // no data model! -- note that it may have a .mom or .momd extension
}

// Create and configure the NSPersistentStoreDescription
let persistentStoreDescription = NSPersistentStoreDescription()
persistentStoreDescription.type = // Choose the type and set additional parameters

// Configure slate. Note that it is perfectly safe for other code to call 
// query/mutation functions on slate before configuration is complete. Those
// functions are queued up on an inactive queue that will only activate once
// configuration completes.
slate.configure(
    managedObjectModel: managedObjectModel,
    persistentStoreDescription: persistentStoreDescription
) { desc, error in
    if let error {
        // Error -- you can see what's wrong; if the issue is unrecoverable you can
        // re-configure slate with new options. If a lightweight migration is failing
        // you may need to delete the existing .sqlite file on disk before re-config.
    } else {
        // Success -- slate is ready to be accessed.
    }
}
```

