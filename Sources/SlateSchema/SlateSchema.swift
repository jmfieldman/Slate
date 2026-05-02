@preconcurrency import CoreData
import Foundation

public typealias SlateID = NSManagedObjectID

public protocol SlateObject: Sendable {
    var slateID: SlateID { get }
}

public protocol SlateKeypathAttributeProviding {
    static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String
}

public protocol SlateKeypathRelationshipProviding {
    static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String
}

public protocol SlateManagedPropertyProviding: AnyObject {
    var objectID: SlateID { get }
}

public protocol SlateSchema: Sendable {
    static var schemaIdentifier: String { get }
    static var schemaFingerprint: String { get }
    static var entities: [SlateEntityMetadata] { get }
    static func makeManagedObjectModel() throws -> NSManagedObjectModel
    static func registerTables(_ registry: inout SlateTableRegistry)
}

public protocol SlateMutableObject: NSManagedObject {
    associatedtype ImmutableObject: SlateObject

    static var slateEntityName: String { get }
    static func fetchRequest() -> NSFetchRequest<Self>
    static func create(in context: NSManagedObjectContext) -> Self

    var slateObject: ImmutableObject { get }
}

public protocol SlateRelationshipHydratingMutableObject: SlateMutableObject {
    func slateObject(hydrating relationships: Set<String>) throws -> ImmutableObject
}

public struct SlateTableRegistry: Sendable {
    public private(set) var tables: [ObjectIdentifier: AnySlateTable]

    public init() {
        self.tables = [:]
    }

    public mutating func register<I: SlateObject, M: SlateMutableObject>(
        immutable: I.Type,
        mutable: M.Type,
        entityName: String,
        uniquenessConstraints: [[String]] = []
    ) where M.ImmutableObject == I {
        tables[ObjectIdentifier(I.self)] = AnySlateTable(
            immutableType: I.self,
            mutableType: M.self,
            entityName: entityName,
            uniquenessConstraints: uniquenessConstraints,
            makeFetchRequest: { M.fetchRequest() as NSFetchRequest<NSFetchRequestResult> },
            create: { M.create(in: $0) },
            convert: { managedObject, relationships in
                guard let typed = managedObject as? M else {
                    throw SlateSchemaError.invalidMutableObjectCast(
                        expected: String(describing: M.self),
                        actual: String(describing: type(of: managedObject))
                    )
                }
                if let hydrating = typed as? any SlateRelationshipHydratingMutableObject,
                   let hydrated = try hydrating.slateObject(hydrating: relationships) as? I
                {
                    return hydrated
                }
                return typed.slateObject
            }
        )
    }

    public func table<I: SlateObject>(for immutable: I.Type) -> AnySlateTable? {
        tables[ObjectIdentifier(I.self)]
    }

    public func table(forEntityName entityName: String) -> AnySlateTable? {
        tables.values.first { $0.entityName == entityName }
    }

    public func table(forManagedObject managedObject: NSManagedObject) -> AnySlateTable? {
        guard let entityName = managedObject.entity.name else { return nil }
        return table(forEntityName: entityName)
    }
}

public struct AnySlateTable: Sendable {
    public let immutableType: Any.Type
    public let mutableType: NSManagedObject.Type
    public let entityName: String
    /// Each inner array is a single uniqueness constraint defined for this
    /// entity, expressed as the storage names participating in that
    /// constraint. A single-attribute constraint is a one-element inner
    /// array; a composite constraint contains multiple storage names.
    /// Used at runtime by `upsert`/`upsertMany` to validate that the user's
    /// upsert key corresponds to a declared uniqueness constraint.
    public let uniquenessConstraints: [[String]]
    public let makeFetchRequest: @Sendable () -> NSFetchRequest<NSFetchRequestResult>
    public let create: @Sendable (NSManagedObjectContext) throws -> NSManagedObject
    public let convert: @Sendable (NSManagedObject, Set<String>) throws -> any SlateObject
}

public enum SlateSchemaError: Error, Sendable, Equatable {
    case invalidMutableObjectCast(expected: String, actual: String)
    case missingTable(String)
}

public struct SlateEntityMetadata: Sendable, Codable, Equatable {
    public let immutableTypeName: String
    public let mutableTypeName: String
    public let entityName: String
    public let attributes: [SlateAttributeMetadata]
    public let relationships: [SlateRelationshipMetadata]

    public init(
        immutableTypeName: String,
        mutableTypeName: String,
        entityName: String,
        attributes: [SlateAttributeMetadata] = [],
        relationships: [SlateRelationshipMetadata] = []
    ) {
        self.immutableTypeName = immutableTypeName
        self.mutableTypeName = mutableTypeName
        self.entityName = entityName
        self.attributes = attributes
        self.relationships = relationships
    }
}

public struct SlateAttributeMetadata: Sendable, Codable, Equatable {
    public let swiftName: String
    public let storageName: String
    public let swiftType: String
    public let storageType: String
    public let optional: Bool
    public let indexed: Bool

    public init(
        swiftName: String,
        storageName: String,
        swiftType: String,
        storageType: String,
        optional: Bool,
        indexed: Bool = false
    ) {
        self.swiftName = swiftName
        self.storageName = storageName
        self.swiftType = swiftType
        self.storageType = storageType
        self.optional = optional
        self.indexed = indexed
    }
}

public struct SlateRelationshipMetadata: Sendable, Codable, Equatable {
    public let name: String
    public let kind: SlateRelationshipKind
    public let destination: String
    public let inverse: String
    public let deleteRule: SlateDeleteRule
    public let ordered: Bool

    public init(
        name: String,
        kind: SlateRelationshipKind,
        destination: String,
        inverse: String,
        deleteRule: SlateDeleteRule,
        ordered: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.destination = destination
        self.inverse = inverse
        self.deleteRule = deleteRule
        self.ordered = ordered
    }
}

public enum SlateRelationshipKind: String, Sendable, Codable {
    case toOne
    case toMany
}

public enum SlateDeleteRule: String, Sendable, Codable {
    case noAction
    case nullify
    case cascade
    case deny

    public var coreDataDeleteRule: NSDeleteRule {
        switch self {
        case .noAction: .noActionDeleteRule
        case .nullify: .nullifyDeleteRule
        case .cascade: .cascadeDeleteRule
        case .deny: .denyDeleteRule
        }
    }
}
