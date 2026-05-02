import CoreData
import Foundation
import Slate
import SlateSchema
import Testing

public struct TestNote: SlateObject, SlateKeypathAttributeProviding, Sendable {
    public let slateID: SlateID
    public let title: String
    public let body: String?
    public let pageCount: Int

    init(slateID: SlateID = NSManagedObjectID(), title: String, body: String?, pageCount: Int) {
        self.slateID = slateID
        self.title = title
        self.body = body
        self.pageCount = pageCount
    }

    init(managedObject: some ManagedPropertyProviding) {
        self.slateID = managedObject.objectID
        self.title = managedObject.title
        self.body = managedObject.body
        self.pageCount = managedObject.pageCount
    }

    protocol ManagedPropertyProviding: AnyObject {
        var objectID: SlateID { get }
        var title: String { get }
        var body: String? { get }
        var pageCount: Int { get }
    }

    public static func keypathToAttribute(_ keyPath: PartialKeyPath<TestNote>) -> String {
        switch keyPath {
        case \TestNote.title: "title"
        case \TestNote.body: "body"
        case \TestNote.pageCount: "pageCount"
        default: fatalError("Unsupported key path")
        }
    }
}

final class DatabaseTestNote: NSManagedObject, TestNote.ManagedPropertyProviding, SlateMutableObject {
    typealias ImmutableObject = TestNote

    static let slateEntityName = "TestNote"

    @NSManaged var title: String
    @NSManaged var body: String?
    @NSManaged var pageCount: Int

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestNote> {
        NSFetchRequest<DatabaseTestNote>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestNote {
        DatabaseTestNote(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestNote {
        TestNote(managedObject: self)
    }
}

enum TestNoteSchema: SlateSchema {
    static let schemaIdentifier = "TestNoteSchema"
    static let schemaFingerprint = "test-note"
    static let entities: [SlateEntityMetadata] = []

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = false

        let body = NSAttributeDescription()
        body.name = "body"
        body.attributeType = .stringAttributeType
        body.isOptional = true

        let pageCount = NSAttributeDescription()
        pageCount.name = "pageCount"
        pageCount.attributeType = .integer64AttributeType
        pageCount.isOptional = false
        pageCount.defaultValue = 0

        let entity = NSEntityDescription()
        entity.name = "TestNote"
        entity.managedObjectClassName = NSStringFromClass(DatabaseTestNote.self)
        entity.properties = [title, body, pageCount]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestNote.self,
            mutable: DatabaseTestNote.self,
            entityName: "TestNote"
        )
    }
}

// Entity with a String-backed enum attribute used by enum predicate tests.
public struct TestRoleNote: SlateObject, SlateKeypathAttributeProviding, Sendable {
    public let slateID: SlateID
    public let title: String
    public let role: Role

    public enum Role: String, Sendable {
        case patient
        case caregiver
    }

    init(slateID: SlateID = NSManagedObjectID(), title: String, role: Role) {
        self.slateID = slateID
        self.title = title
        self.role = role
    }

    init(managedObject: DatabaseTestRoleNote) {
        self.slateID = managedObject.objectID
        self.title = managedObject.title
        self.role = TestRoleNote.Role(rawValue: managedObject.role) ?? .patient
    }

    public static func keypathToAttribute(_ keyPath: PartialKeyPath<TestRoleNote>) -> String {
        switch keyPath {
        case \TestRoleNote.title: "title"
        case \TestRoleNote.role: "role"
        default: fatalError("Unsupported key path")
        }
    }
}

final class DatabaseTestRoleNote: NSManagedObject, SlateMutableObject {
    typealias ImmutableObject = TestRoleNote

    static let slateEntityName = "TestRoleNote"

    @NSManaged var title: String
    @NSManaged var role: String

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestRoleNote> {
        NSFetchRequest<DatabaseTestRoleNote>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestRoleNote {
        DatabaseTestRoleNote(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestRoleNote {
        TestRoleNote(managedObject: self)
    }
}

enum TestEnumSchema: SlateSchema {
    static let schemaIdentifier = "TestEnumSchema"
    static let schemaFingerprint = "test-enum"
    static let entities: [SlateEntityMetadata] = []

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = false

        let role = NSAttributeDescription()
        role.name = "role"
        role.attributeType = .stringAttributeType
        role.isOptional = false
        role.defaultValue = TestRoleNote.Role.patient.rawValue

        let entity = NSEntityDescription()
        entity.name = "TestRoleNote"
        entity.managedObjectClassName = NSStringFromClass(DatabaseTestRoleNote.self)
        entity.properties = [title, role]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestRoleNote.self,
            mutable: DatabaseTestRoleNote.self,
            entityName: "TestRoleNote"
        )
    }
}

@Suite
struct SlatePredicateTests {
    @Test
    func filtersByOptionalEqualNil() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let withBody = context.create(DatabaseTestNote.self)
            withBody.title = "A"
            withBody.body = "Has body"
            withBody.pageCount = 10

            let withoutBody = context.create(DatabaseTestNote.self)
            withoutBody.title = "B"
            withoutBody.body = nil
            withoutBody.pageCount = 20
        }

        let nilNotes = try await slate.query { context in
            try context[TestNote.self].where(\.body == nil).many()
        }
        #expect(nilNotes.map(\.title) == ["B"])

        let nonNilNotes = try await slate.query { context in
            try context[TestNote.self].where(\.body != nil).many()
        }
        #expect(nonNilNotes.map(\.title) == ["A"])
    }

    @Test
    func filtersByIsNilStaticHelper() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let one = context.create(DatabaseTestNote.self)
            one.title = "First"
            one.body = "B"
            one.pageCount = 1

            let two = context.create(DatabaseTestNote.self)
            two.title = "Second"
            two.body = nil
            two.pageCount = 2
        }

        let isNilTitles = try await slate.query { context in
            try context[TestNote.self]
                .where(.isNil(\.body))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(isNilTitles == ["Second"])

        let notNilTitles = try await slate.query { context in
            try context[TestNote.self]
                .where(.isNotNil(\.body))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(notNilTitles == ["First"])
    }

    @Test
    func composesPredicates() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (title, body, pageCount) in [
                ("A", "x", 1),
                ("B", "y", 5),
                ("C", nil, 5),
                ("D", "z", 10),
            ] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = body
                note.pageCount = pageCount
            }
        }

        let andTitles = try await slate.query { context in
            try context[TestNote.self]
                .where(\.pageCount == 5 && .isNotNil(\.body))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(andTitles == ["B"])

        let orTitles = try await slate.query { context in
            try context[TestNote.self]
                .where(\.pageCount == 1 || \.pageCount == 10)
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(orTitles == ["A", "D"])

        let notTitles = try await slate.query { context in
            try context[TestNote.self]
                .where(!(\.pageCount == 5))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(notTitles == ["A", "D"])
    }

    @Test
    func inAndNotInHelpers() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for title in ["A", "B", "C", "D"] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = nil
                note.pageCount = 0
            }
        }

        let inSet = try await slate.query { context in
            try context[TestNote.self]
                .where(.in(\.title, ["A", "C"]))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(inSet == ["A", "C"])

        let notInSet = try await slate.query { context in
            try context[TestNote.self]
                .where(.notIn(\.title, ["A", "C"]))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(notInSet == ["B", "D"])
    }

    @Test
    func stringContainsBeginsEndsHelpers() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for title in ["Apple Pie", "Banana Bread", "Apple Cobbler", "Pumpkin Pie"] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = nil
                note.pageCount = 0
            }
        }

        let pies = try await slate.query { context in
            try context[TestNote.self]
                .where(.endsWith(\.title, "Pie"))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(pies == ["Apple Pie", "Pumpkin Pie"])

        let appleStartsWith = try await slate.query { context in
            try context[TestNote.self]
                .where(.beginsWith(\.title, "apple", options: [.caseInsensitive]))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(appleStartsWith == ["Apple Cobbler", "Apple Pie"])

        let containsBread = try await slate.query { context in
            try context[TestNote.self]
                .where(.contains(\.title, "Bread"))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(containsBread == ["Banana Bread"])
    }

    @Test
    func matchesRegexHelper() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for title in ["AAA-001", "BBB-002", "AAA-X99", "QUERY-77"] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = nil
                note.pageCount = 0
            }
        }

        let matches = try await slate.query { context in
            try context[TestNote.self]
                .where(.matches(\.title, "^AAA-[0-9]+$"))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(matches == ["AAA-001"])
    }

    @Test
    func betweenHelper() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (title, pageCount) in [("A", 1), ("B", 5), ("C", 10), ("D", 15), ("E", 20)] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = nil
                note.pageCount = pageCount
            }
        }

        let inRange = try await slate.query { context in
            try context[TestNote.self]
                .where(.between(\.pageCount, 5...15))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(inRange == ["B", "C", "D"])
    }

    @Test
    func filtersByEnumRawValueExtraction() async throws {
        let slate = Slate<TestEnumSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (title, role) in [("A", "patient"), ("B", "caregiver"), ("C", "patient")] {
                let row = context.create(DatabaseTestRoleNote.self)
                row.title = title
                row.role = role
            }
        }

        // The predicate is built with a RawRepresentable enum case;
        // SlatePredicate must extract `.rawValue` so the underlying
        // Core Data string column matches `"caregiver"`, not `"caregiver"`'s
        // enum object representation.
        let caregivers = try await slate.query { context in
            try context[TestRoleNote.self]
                .where(\.role == .caregiver)
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(caregivers == ["B"])

        let patients = try await slate.query { context in
            try context[TestRoleNote.self]
                .where(.in(\.role, [TestRoleNote.Role.patient]))
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(patients == ["A", "C"])
    }

    @Test
    func comparisonOperators() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (title, pageCount) in [("A", 1), ("B", 5), ("C", 10)] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = nil
                note.pageCount = pageCount
            }
        }

        let greater = try await slate.query { context in
            try context[TestNote.self]
                .where(\.pageCount > 4)
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(greater == ["B", "C"])

        let lessOrEq = try await slate.query { context in
            try context[TestNote.self]
                .where(\.pageCount <= 5)
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(lessOrEq == ["A", "B"])
    }

    // SlatePredicate now requires `Value: Sendable` on its public operators
    // and helpers. Both the predicate value (now stored as `(any Sendable)?`)
    // and the predicate itself must cross queue boundaries safely. This test
    // builds a predicate, tasks it through detached actors, and applies it
    // from inside the writer queue's `slate.query` block — so any
    // unchecked-Sendable misuse would surface as a strict-concurrency error
    // at compile time or a runtime crossing failure.
    @Test
    func predicateCrossesActorBoundariesSafely() async throws {
        let slate = Slate<TestNoteSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (title, body, pageCount) in [
                ("A", "alpha", 1),
                ("B", "beta", 5),
                ("C", "gamma", 10),
            ] {
                let note = context.create(DatabaseTestNote.self)
                note.title = title
                note.body = body
                note.pageCount = pageCount
            }
        }

        let predicate: SlatePredicate<TestNote> = \.pageCount > 1 && .in(\.title, ["A", "B", "C"])
        let detachedPredicate = await Task.detached { predicate }.value
        let titles = try await slate.query { context in
            try context[TestNote.self]
                .where(detachedPredicate)
                .sort(\.title)
                .many()
                .map(\.title)
        }
        #expect(titles == ["B", "C"])
    }
}
