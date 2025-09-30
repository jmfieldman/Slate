# Slate

![Slate](/Misc/Banner/banner.png)

## Overview

**Slate** is a Swift framework that provides immutable data models for Core Data, enabling safe and efficient access to your application's data with thread safety guarantees. It sits on top of Core Data's object graph and provides a clean, type-safe interface for querying and mutating data.

Slate addresses common Core Data challenges by offering:
- **Single-writer/multi-reader transactional access** to the object graph
- **Immutable data models** with a clean query DSL that ensures thread safety and prevents accidental mutations

## Key Features

### Immutable Data Models
Slate automatically generates immutable representations of your Core Data entities, providing:
- Thread-safe access to data models
- Protection against accidental mutations outside of mutation contexts  
- Clean separation between read and write operations

### Thread Safety
All immutable models in Slate conform to `Sendable`, making them safe for concurrent access across different threads. This eliminates the need for manual synchronization when passing data between background and main threads.

### Transactional Access
Slate implements a single-writer/multi-reader pattern that ensures:
- Mutations occur in isolated barriers, preventing race conditions
- Queries always operate on consistent snapshots of the data model
- Safe concurrent access to read operations

### Reactive Streaming
Slate provides Combine publisher support for streaming NSFetchedResultsController updates, enabling reactive UI updates that respond to data changes in real-time.

## Architecture

### Core Components

1. **Slate Instance**: The central management context for all operations on a NSPersistentStore
2. **Core Data Integration**: Works directly with Core Data's object graph and managed objects  
3. **Immutable Model Generation**: Automatically generates immutable representations of your Core Data entities
4. **Query Contexts**: Thread-local contexts for safe read operations with snapshot consistency
5. **Mutation Contexts**: Single-writer barrier operations that ensure data integrity

### How It Works

1. **Data Model Definition**: Define your Core Data entities in `.xcdatamodel` files
2. **Code Generation**: Use `slategen` to generate both Core Data managed objects and immutable Slate models
3. **Runtime Usage**: 
   - Use `slate.query()` for read operations that return immutable models
   - Use `slate.mutate()` for write operations that modify the Core Data store
4. **Thread Safety**: Immutable models can be safely shared across threads without synchronization

## Core Concepts

### Immutable Models
Slate generates immutable representations of your Core Data entities that:
- Cannot be modified after creation
- Provide thread-safe access patterns  
- Are automatically cached for performance
- Support the `Sendable` protocol

### Query DSL
Slate provides a fluent API for querying data:
```swift
let books = try await slate.query { context in
    return try context[Book.self]
        .where(\.pageCount, .greaterThan(100))
        .sort(\.title)
        .fetch()
}
```

### Mutation Contexts
Mutations are performed in barrier operations:
```swift
try await slate.mutate { writeContext in
    if let book = try writeContext[CoreDataBook.self]
        .where(\.id, .equals(bookId))
        .fetchOne() 
    {
        book.pageCount = newPageCount
    }
}
```

## Setup and Usage

### Prerequisites

- Swift 5.9 or later
- iOS 17+, macOS 14+, tvOS 17+, watchOS 6+ 
- Xcode 15 or later

### Dependencies

Slate depends on:
- Swift Argument Parser (v1.6.1+) - for the code generation tool
- Foundation framework (built-in)
- Core Data framework (built-in)

### Installation

Slate is distributed as a Swift Package. Add it to your project using Xcode's package manager or by adding the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jmfieldman/Slate", from: "<latest version>")
]
```

### Data Model Setup

1. Create a new Core Data model file (`New > File from Template > Core Data > Data Model`)
2. Set the Codegen property of each Entity to `Manual/None` 
3. Configure module abstraction for logical separation of entities
4. For each entity, you can specify `struct: true` in the User Info dictionary to generate structs instead of classes

### Code Generation with `slategen`

Use the `slategen` command-line tool to generate both Core Data managed objects and immutable Slate models:

```bash
$ swift run slategen gen-core-data \
  --input-model <path-to-implementation-module>/SlateTests.xcdatamodel \
  --output-core-data-entity-path <path-to-implementation-module>/DatabaseModels \
  --output-slate-object-path <path-to-api-module>/ImmutableModels \
  --cast-int \
  --core-data-file-imports "Slate, ImmutableModels"
```

### Runtime Usage

1. Create a `Slate` instance in your implementation module:
```swift
let slate = Slate()
```

2. Configure the persistent store:
```swift
guard 
    let momPath = Bundle.main.path(forResource: "YourDataModel", ofType: "mom"),
    let managedObjectModel = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: basePath))
else {
    throw // no data model!
}

let persistentStoreDescription = NSPersistentStoreDescription()
persistentStoreDescription.type = // Choose the type and set additional parameters

slate.configure(
    managedObjectModel: managedObjectModel,
    persistentStoreDescription: persistentStoreDescription
) { desc, error in
    if let error {
        // Handle configuration errors
    } else {
        // Success - slate is ready to be accessed.
    }
}
```

3. Query data using immutable models:
```swift
let books = try await slate.query { context in
    return try context[Book.self]
        .where(\.pageCount, .greaterThan(100))
        .fetch()
}
```

4. Mutate data safely:
```swift
try await slate.mutate { writeContext in
    if let book = try writeContext[CoreDataBook.self]
        .where(\.id, .equals(bookId))
        .fetchOne() 
    {
        book.pageCount = newPageCount
    }
}
```

## Streaming Data

Slate supports reactive streaming of data changes using Combine publishers:

```swift
let streamPublisher = slate.stream { request -> SlateQueryRequest<Book> in
    return request.sort(\.pageCount)
}
```

## Tradeoffs and Considerations

### Advantages
- **Thread Safety**: Immutable models guarantee Sendable conformance, making them safe for concurrent access
- **Snapshot Isolation**: Queries operate on consistent snapshots of the data model 
- **Unidirectional Flow**: Enforces clear separation between read and write operations
- **Performance**: Caching of immutable objects improves performance for repeated queries

### Limitations  
- **No Faulting**: All queried objects are fully loaded, which may impact performance for large datasets
- **No Dynamic Relationships**: Relationships must be pre-fetched as arrays of immutable objects

## API Reference

### Core Types
- `Slate`: Main entry point for all operations
- `SlateObject`: Protocol that immutable models must conform to  
- `SlateQueryContext`: Context for read operations
- `SlateTransactionError`: Errors that can occur during transactions

### Key Methods
- `slate.query()`: Asynchronous read operations returning immutable models
- `slate.mutate()`: Asynchronous write operations modifying Core Data  
- `slate.stream()`: Reactive streaming of data changes

## Example Usage Patterns

### Basic Query
```swift
let authors = try await slate.query { context in
    return try context[Author.self].fetch()
}
```

### Filtered Query with Sorting
```swift
let books = try await slate.query { context in
    return try context[Book.self]
        .where(\.pageCount, .greaterThan(100))
        .sort(\.title)
        .fetch()
}
```

### Mutation with Error Handling
```swift
do {
    try await slate.mutate { context in
        let author = try context[CoreDataAuthor.self].fetchOne()
        author.name = "New Name"
    }
} catch {
    // Handle mutation errors
}
```

### Reactive Data Streaming
```swift
let publisher = slate.stream { request in
    return request.sort(\.title)
}

publisher.sink(
    receiveCompletion: { completion in
        // Handle stream completion
    },
    receiveValue: { update in
        // Update UI with new data and change indices
    }
)
```

## Contributing

Contributions to Slate are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch  
3. Make your changes with tests
4. Submit a pull request

## License

Slate is released under the MIT license. See [LICENSE.txt](LICENSE.txt) for details.

