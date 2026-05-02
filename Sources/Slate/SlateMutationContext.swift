@preconcurrency import CoreData
import Foundation
import SlateSchema

public final class SlateMutationContext<Schema: SlateSchema>: @unchecked Sendable {
    let ownerID: UUID
    let scopeID: UUID
    let managedObjectContext: NSManagedObjectContext
    let registry: SlateTableRegistry

    init(ownerID: UUID, scopeID: UUID, managedObjectContext: NSManagedObjectContext, registry: SlateTableRegistry) {
        self.ownerID = ownerID
        self.scopeID = scopeID
        self.managedObjectContext = managedObjectContext
        self.registry = registry
    }

    public func create<M: SlateMutableObject>(_ mutable: M.Type) -> M {
        M.create(in: managedObjectContext)
    }

    public subscript<M: SlateMutableObject>(_ mutable: M.Type) -> SlateMutationTable<M> where M.ImmutableObject: SlateKeypathAttributeProviding {
        SlateMutationTable(context: self, predicate: nil, sorts: [])
    }

    public func immutable<M: SlateMutableObject>(_ mutable: M) -> M.ImmutableObject {
        mutable.slateObject
    }
}

public struct SlateMutationTable<M: SlateMutableObject>: Sendable where M.ImmutableObject: SlateKeypathAttributeProviding {
    private let context: AnySlateMutationContext
    private let predicate: SlatePredicate<M.ImmutableObject>?
    private let sorts: [SlateSort<M.ImmutableObject>]

    init<Schema: SlateSchema>(
        context: SlateMutationContext<Schema>,
        predicate: SlatePredicate<M.ImmutableObject>?,
        sorts: [SlateSort<M.ImmutableObject>]
    ) {
        self.context = AnySlateMutationContext(context)
        self.predicate = predicate
        self.sorts = sorts
    }

    private init(context: AnySlateMutationContext, predicate: SlatePredicate<M.ImmutableObject>?, sorts: [SlateSort<M.ImmutableObject>]) {
        self.context = context
        self.predicate = predicate
        self.sorts = sorts
    }

    public func `where`(_ predicate: SlatePredicate<M.ImmutableObject>) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts)
    }

    public func sort(_ keyPath: PartialKeyPath<M.ImmutableObject>, ascending: Bool = true) -> Self {
        Self(context: context, predicate: predicate, sorts: sorts + [SlateSort(keyPath, ascending: ascending)])
    }

    public func sort(_ sorts: [SlateSort<M.ImmutableObject>]) -> Self {
        Self(context: context, predicate: predicate, sorts: self.sorts + sorts)
    }

    /// Ascending-only key-path overload of `sort(_:)`.
    public func sort(_ keyPaths: [PartialKeyPath<M.ImmutableObject>]) -> Self {
        Self(context: context, predicate: predicate, sorts: self.sorts + keyPaths.map { SlateSort($0) })
    }

    public func create() -> M {
        M.create(in: context.managedObjectContext)
    }

    public func many() throws -> [M] {
        try context.fetch(M.self, predicate: predicate, sorts: sorts)
    }

    public func one() throws -> M? {
        try context.fetch(M.self, predicate: predicate, sorts: sorts, fetchLimit: 1).first
    }

    public func count() throws -> Int {
        try context.count(M.self, predicate: predicate)
    }

    public func one(where predicate: SlatePredicate<M.ImmutableObject>) throws -> M? {
        try `where`(predicate).one()
    }

    public func many(where predicate: SlatePredicate<M.ImmutableObject>) throws -> [M] {
        try `where`(predicate).many()
    }

    public func count(where predicate: SlatePredicate<M.ImmutableObject>) throws -> Int {
        try `where`(predicate).count()
    }

    @discardableResult
    public func delete(where predicate: SlatePredicate<M.ImmutableObject>) throws -> Int {
        let rows = try context.fetch(M.self, predicate: predicate, sorts: [])
        rows.forEach(context.managedObjectContext.delete)
        return rows.count
    }

    public func dictionary<Value: Hashable>(by keyPath: KeyPath<M.ImmutableObject, Value>) throws -> [Value: M] {
        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        let rows = try context.fetch(M.self, predicate: predicate, sorts: sorts)
        var result: [Value: M] = [:]
        for row in rows {
            if let key = row.value(forKey: attributeName) as? Value {
                result[key] = row
            }
        }
        return result
    }

    public func firstOrCreate<Value: Sendable>(
        _ keyPath: KeyPath<M.ImmutableObject, Value>,
        _ value: Value,
        sort additional: [SlateSort<M.ImmutableObject>] = []
    ) throws -> M {
        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        let matchPredicate = SlatePredicate<M.ImmutableObject>(
            .comparison(attribute: attributeName, op: .equal, value: SendableValue(value))
        )
        let mergedSorts = sorts + additional
        if let existing = try context.fetch(
            M.self,
            predicate: combine(predicate, matchPredicate),
            sorts: mergedSorts,
            fetchLimit: 1
        ).first {
            return existing
        }
        let created = M.create(in: context.managedObjectContext)
        created.setValue(value, forKey: attributeName)
        return created
    }

    public func firstOrCreateMany<Value: Hashable & Sendable>(
        _ keyPath: KeyPath<M.ImmutableObject, Value>,
        _ values: some Collection<Value>,
        sort additional: [SlateSort<M.ImmutableObject>] = []
    ) throws -> [Value: M] {
        let unique = Set(values)
        guard !unique.isEmpty else { return [:] }

        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        let inPredicate = SlatePredicate<M.ImmutableObject>(
            .comparison(attribute: attributeName, op: .in, value: SendableValue(Array(unique)))
        )
        let mergedSorts = sorts + additional
        let existingRows = try context.fetch(
            M.self,
            predicate: combine(predicate, inPredicate),
            sorts: mergedSorts
        )

        var result: [Value: M] = [:]
        for row in existingRows {
            if let key = row.value(forKey: attributeName) as? Value, result[key] == nil {
                result[key] = row
            }
        }
        for value in unique where result[value] == nil {
            let created = M.create(in: context.managedObjectContext)
            created.setValue(value, forKey: attributeName)
            result[value] = created
        }
        return result
    }

    /// Insert a new row for `value` if no existing row matches the supplied
    /// uniqueness key, otherwise return the existing row. Unlike
    /// `firstOrCreate`, `upsert` requires that `keyPath` resolves to an
    /// attribute participating in a declared single-attribute uniqueness
    /// constraint on this entity. Without that guarantee multiple rows
    /// could match a single key and the operation's semantics would be
    /// ambiguous.
    public func upsert<Value: Sendable>(
        _ keyPath: KeyPath<M.ImmutableObject, Value>,
        _ value: Value
    ) throws -> M {
        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        try requireSingleKeyUniqueness(attribute: attributeName)
        return try firstOrCreate(keyPath, value)
    }

    /// Bulk variant of `upsert(_:_:)`: validates that `keyPath` corresponds
    /// to a single-attribute uniqueness constraint and then either fetches
    /// existing rows or creates new ones for every value in `values`.
    public func upsertMany<Value: Hashable & Sendable>(
        _ keyPath: KeyPath<M.ImmutableObject, Value>,
        _ values: some Collection<Value>
    ) throws -> [Value: M] {
        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        try requireSingleKeyUniqueness(attribute: attributeName)
        return try firstOrCreateMany(keyPath, values)
    }

    private func requireSingleKeyUniqueness(attribute: String) throws {
        let entityName = M.slateEntityName
        guard let table = context.registry.table(forEntityName: entityName) else {
            throw SlateError.missingTable(entityName)
        }
        let isUnique = table.uniquenessConstraints.contains { $0 == [attribute] }
        guard isUnique else {
            throw SlateError.upsertKeyNotUnique(entity: entityName, attribute: attribute)
        }
    }

    @discardableResult
    public func deleteMissing<Value: Hashable & Sendable>(
        key keyPath: KeyPath<M.ImmutableObject, Value>,
        keeping values: some Collection<Value>,
        emptySetDeletesAll: Bool
    ) throws -> Int {
        let unique = Set(values)
        if unique.isEmpty && !emptySetDeletesAll {
            throw SlateError.emptyDeleteMissingSet
        }
        let attributeName = M.ImmutableObject.keypathToAttribute(keyPath)
        let combined: SlatePredicate<M.ImmutableObject>?
        if unique.isEmpty {
            combined = predicate
        } else {
            let notInPredicate = SlatePredicate<M.ImmutableObject>(
                .comparison(attribute: attributeName, op: .notIn, value: SendableValue(Array(unique)))
            )
            combined = combine(predicate, notInPredicate)
        }
        let rows = try context.fetch(M.self, predicate: combined, sorts: [])
        rows.forEach(context.managedObjectContext.delete)
        return rows.count
    }

    private func combine(
        _ lhs: SlatePredicate<M.ImmutableObject>?,
        _ rhs: SlatePredicate<M.ImmutableObject>
    ) -> SlatePredicate<M.ImmutableObject> {
        guard let lhs else { return rhs }
        return SlatePredicate(.and(lhs.expression, rhs.expression))
    }
}

private struct AnySlateMutationContext: @unchecked Sendable {
    let managedObjectContext: NSManagedObjectContext
    let registry: SlateTableRegistry

    init<Schema: SlateSchema>(_ context: SlateMutationContext<Schema>) {
        self.managedObjectContext = context.managedObjectContext
        self.registry = context.registry
    }

    func fetch<M: SlateMutableObject>(
        _ mutable: M.Type,
        predicate: SlatePredicate<M.ImmutableObject>?,
        sorts: [SlateSort<M.ImmutableObject>],
        fetchLimit: Int = 0
    ) throws -> [M] {
        let request = M.fetchRequest()
        request.predicate = predicate?.expression.nsPredicate
        request.sortDescriptors = sorts.map(\.descriptor)
        request.fetchLimit = fetchLimit
        return try managedObjectContext.fetch(request)
    }

    func count<M: SlateMutableObject>(_ mutable: M.Type, predicate: SlatePredicate<M.ImmutableObject>?) throws -> Int {
        let request = M.fetchRequest()
        request.predicate = predicate?.expression.nsPredicate
        return try managedObjectContext.count(for: request)
    }
}
