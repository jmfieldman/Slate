@preconcurrency import CoreData
import Foundation
import SlateSchema

public final class SlateQueryContext<Schema: SlateSchema>: @unchecked Sendable {
    let ownerID: UUID
    let scopeID: UUID
    let managedObjectContext: NSManagedObjectContext
    let registry: SlateTableRegistry
    let cache: SlateObjectCache

    init(
        ownerID: UUID,
        scopeID: UUID,
        managedObjectContext: NSManagedObjectContext,
        registry: SlateTableRegistry,
        cache: SlateObjectCache
    ) {
        self.ownerID = ownerID
        self.scopeID = scopeID
        self.managedObjectContext = managedObjectContext
        self.registry = registry
        self.cache = cache
    }

    public subscript<I: SlateObject & SlateKeypathAttributeProviding>(_ immutable: I.Type) -> SlateQueryTable<I> {
        SlateQueryTable(context: self, predicate: nil, sorts: [])
    }
}

public struct SlateQueryTable<I: SlateObject & SlateKeypathAttributeProviding>: Sendable {
    private let context: AnySlateQueryContext
    private let predicate: SlatePredicate<I>?
    private let sorts: [SlateSort<I>]
    private let relationships: Set<String>

    init<Schema: SlateSchema>(
        context: SlateQueryContext<Schema>,
        predicate: SlatePredicate<I>?,
        sorts: [SlateSort<I>],
        relationships: Set<String> = []
    ) {
        self.context = AnySlateQueryContext(context)
        self.predicate = predicate
        self.sorts = sorts
        self.relationships = relationships
    }

    private init(context: AnySlateQueryContext, predicate: SlatePredicate<I>?, sorts: [SlateSort<I>], relationships: Set<String>) {
        self.context = context
        self.predicate = predicate
        self.sorts = sorts
        self.relationships = relationships
    }

    public func `where`(_ predicate: SlatePredicate<I>) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts, relationships: relationships)
    }

    public func sort(_ keyPath: PartialKeyPath<I>, ascending: Bool = true) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts + [SlateSort(keyPath, ascending: ascending)], relationships: relationships)
    }

    public func sort(_ attribute: String, ascending: Bool = true) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts + [SlateSort(attribute: attribute, ascending: ascending)], relationships: relationships)
    }

    public func sort(_ sorts: [SlateSort<I>]) -> Self {
        Self(context: context, predicate: predicate, sorts: self.sorts + sorts, relationships: relationships)
    }

    /// Ascending-only key-path overload of `sort(_:)`. Lets callers chain
    /// `.sort([\.lastName, \.firstName])` instead of wrapping each path
    /// in `SlateSort(...)`.
    public func sort(_ keyPaths: [PartialKeyPath<I>]) -> Self {
        Self(context: context, predicate: predicate, sorts: self.sorts + keyPaths.map { SlateSort($0) }, relationships: relationships)
    }

    public func relationships(_ keyPaths: [PartialKeyPath<I>]) -> Self where I: SlateKeypathRelationshipProviding {
        let names = Set(keyPaths.map { I.keypathToRelationship($0) })
        return Self(context: context, predicate: predicate, sorts: sorts, relationships: relationships.union(names))
    }

    public func relationships(names: Set<String>) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts, relationships: relationships.union(names))
    }

    public func many(limit: Int? = nil, offset: Int? = nil) throws -> [I] {
        try context.fetch(
            I.self,
            predicate: predicate,
            sorts: sorts,
            relationships: relationships,
            fetchLimit: limit ?? 0,
            fetchOffset: offset ?? 0
        )
    }

    public func one() throws -> I? {
        try context.fetch(
            I.self,
            predicate: predicate,
            sorts: sorts,
            relationships: relationships,
            fetchLimit: 1,
            fetchOffset: 0
        ).first
    }

    public func count() throws -> Int {
        try context.count(I.self, predicate: predicate)
    }

    public func one(where predicate: SlatePredicate<I>) throws -> I? {
        try `where`(predicate).one()
    }

    public func many(where predicate: SlatePredicate<I>, limit: Int? = nil, offset: Int? = nil) throws -> [I] {
        try `where`(predicate).many(limit: limit, offset: offset)
    }

    public func count(where predicate: SlatePredicate<I>) throws -> Int {
        try `where`(predicate).count()
    }
}

private struct AnySlateQueryContext: @unchecked Sendable {
    let managedObjectContext: NSManagedObjectContext
    let registry: SlateTableRegistry
    let cache: SlateObjectCache

    init<Schema: SlateSchema>(_ context: SlateQueryContext<Schema>) {
        self.managedObjectContext = context.managedObjectContext
        self.registry = context.registry
        self.cache = context.cache
    }

    func fetch<I: SlateObject>(
        _ immutable: I.Type,
        predicate: SlatePredicate<I>?,
        sorts: [SlateSort<I>],
        relationships: Set<String>,
        fetchLimit: Int = 0,
        fetchOffset: Int = 0
    ) throws -> [I] {
        guard let table = registry.table(for: immutable) else {
            throw SlateError.missingTable(String(describing: immutable))
        }

        let request = table.makeFetchRequest()
        request.entity = NSEntityDescription.entity(forEntityName: table.entityName, in: managedObjectContext)
        request.predicate = predicate?.expression.nsPredicate
        request.sortDescriptors = sorts.map(\.descriptor)
        request.fetchLimit = fetchLimit
        request.fetchOffset = fetchOffset
        request.relationshipKeyPathsForPrefetching = relationships.sorted()

        let objects = try managedObjectContext.fetch(request)
        return try objects.map { object in
            guard let managedObject = object as? NSManagedObject else {
                throw SlateError.coreData("Fetch returned a non-managed object")
            }
            if relationships.isEmpty,
               let cached = cache.get(managedObject.objectID) as? I
            {
                return cached
            }
            guard let immutableObject = try table.convert(managedObject, relationships) as? I else {
                throw SlateError.coreData("Could not convert \(managedObject) to \(I.self)")
            }
            if relationships.isEmpty {
                cache.set(managedObject.objectID, immutableObject)
            }
            return immutableObject
        }
    }

    func count<I: SlateObject>(_ immutable: I.Type, predicate: SlatePredicate<I>?) throws -> Int {
        guard let table = registry.table(for: immutable) else {
            throw SlateError.missingTable(String(describing: immutable))
        }
        let request = table.makeFetchRequest()
        request.entity = NSEntityDescription.entity(forEntityName: table.entityName, in: managedObjectContext)
        request.predicate = predicate?.expression.nsPredicate
        return try managedObjectContext.count(for: request)
    }
}
