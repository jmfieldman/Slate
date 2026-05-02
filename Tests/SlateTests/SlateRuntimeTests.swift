import CoreData
import Foundation
import Slate
import SlateFixturePatientModels
import SlateFixturePatientPersistence
import SlateSchema
import Testing

@SlateEntity
public struct TestAuthor {
    public let name: String
}

final class DatabaseTestAuthor: NSManagedObject, TestAuthor.ManagedPropertyProviding, SlateMutableObject {
    typealias ImmutableObject = TestAuthor

    static let slateEntityName = "TestAuthor"

    @NSManaged var name: String

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestAuthor> {
        NSFetchRequest<DatabaseTestAuthor>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestAuthor {
        DatabaseTestAuthor(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestAuthor {
        TestAuthor(managedObject: self)
    }
}

enum TestSchema: SlateSchema {
    static let schemaIdentifier = "TestSchema"
    static let schemaFingerprint = "test"
    static let entities: [SlateEntityMetadata] = [
        SlateEntityMetadata(
            immutableTypeName: "TestAuthor",
            mutableTypeName: "DatabaseTestAuthor",
            entityName: "TestAuthor",
            attributes: [
                SlateAttributeMetadata(
                    swiftName: "name",
                    storageName: "name",
                    swiftType: "String",
                    storageType: "string",
                    optional: false
                ),
            ]
        ),
    ]

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let attribute = NSAttributeDescription()
        attribute.name = "name"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false

        let entity = NSEntityDescription()
        entity.name = "TestAuthor"
        entity.managedObjectClassName = NSStringFromClass(DatabaseTestAuthor.self)
        entity.properties = [attribute]
        entity.uniquenessConstraints = [["name"]]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestAuthor.self,
            mutable: DatabaseTestAuthor.self,
            entityName: "TestAuthor",
            uniquenessConstraints: [["name"]]
        )
    }
}

// Schema variant whose `name` attribute is NOT declared as a uniqueness
// constraint. Used to verify that `upsert(...)` rejects keys outside the
// declared uniqueness set.
@SlateEntity
public struct TestUnconstrainedAuthor {
    public let name: String
}

final class DatabaseTestUnconstrainedAuthor: NSManagedObject, TestUnconstrainedAuthor.ManagedPropertyProviding, SlateMutableObject {
    typealias ImmutableObject = TestUnconstrainedAuthor

    static let slateEntityName = "TestUnconstrainedAuthor"

    @NSManaged var name: String

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestUnconstrainedAuthor> {
        NSFetchRequest<DatabaseTestUnconstrainedAuthor>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestUnconstrainedAuthor {
        DatabaseTestUnconstrainedAuthor(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestUnconstrainedAuthor {
        TestUnconstrainedAuthor(managedObject: self)
    }
}

enum TestUnconstrainedSchema: SlateSchema {
    static let schemaIdentifier = "TestUnconstrainedSchema"
    static let schemaFingerprint = "test-unconstrained"
    static let entities: [SlateEntityMetadata] = []

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let attribute = NSAttributeDescription()
        attribute.name = "name"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false

        let entity = NSEntityDescription()
        entity.name = "TestUnconstrainedAuthor"
        entity.managedObjectClassName = NSStringFromClass(DatabaseTestUnconstrainedAuthor.self)
        entity.properties = [attribute]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestUnconstrainedAuthor.self,
            mutable: DatabaseTestUnconstrainedAuthor.self,
            entityName: "TestUnconstrainedAuthor"
        )
    }
}

public struct TestPerson: SlateObject, SlateKeypathAttributeProviding, SlateKeypathRelationshipProviding, Sendable {
    public let slateID: SlateID
    public let name: String
    public let profile: TestProfile?
    public let profiles: [TestProfile]?
    public let orderedProfiles: [TestProfile]?

    init(
        slateID: SlateID = NSManagedObjectID(),
        name: String,
        profile: TestProfile? = nil,
        profiles: [TestProfile]? = nil,
        orderedProfiles: [TestProfile]? = nil
    ) {
        self.slateID = slateID
        self.name = name
        self.profile = profile
        self.profiles = profiles
        self.orderedProfiles = orderedProfiles
    }

    init(managedObject: some ManagedPropertyProviding) {
        self.slateID = managedObject.objectID
        self.name = managedObject.name
        self.profile = nil
        self.profiles = nil
        self.orderedProfiles = nil
    }

    protocol ManagedPropertyProviding: AnyObject {
        var objectID: SlateID { get }
        var name: String { get }
    }

    public static func keypathToAttribute(_ keyPath: PartialKeyPath<TestPerson>) -> String {
        switch keyPath {
        case \TestPerson.name: "name"
        default: fatalError("Unsupported key path")
        }
    }

    public static func keypathToRelationship(_ keyPath: PartialKeyPath<TestPerson>) -> String {
        switch keyPath {
        case \TestPerson.profile: "profile"
        case \TestPerson.profiles: "profiles"
        case \TestPerson.orderedProfiles: "orderedProfiles"
        default: fatalError("Unsupported relationship key path")
        }
    }
}

public struct TestProfile: SlateObject, SlateKeypathAttributeProviding, SlateKeypathRelationshipProviding, Sendable {
    public let slateID: SlateID
    public let biography: String

    init(slateID: SlateID = NSManagedObjectID(), biography: String) {
        self.slateID = slateID
        self.biography = biography
    }

    init(managedObject: some ManagedPropertyProviding) {
        self.slateID = managedObject.objectID
        self.biography = managedObject.biography
    }

    protocol ManagedPropertyProviding: AnyObject {
        var objectID: SlateID { get }
        var biography: String { get }
    }

    public static func keypathToAttribute(_ keyPath: PartialKeyPath<TestProfile>) -> String {
        switch keyPath {
        case \TestProfile.biography: "biography"
        default: fatalError("Unsupported key path")
        }
    }

    public static func keypathToRelationship(_ keyPath: PartialKeyPath<TestProfile>) -> String {
        switch keyPath {
        default: fatalError("Unsupported relationship key path")
        }
    }
}

final class DatabaseTestPerson: NSManagedObject, TestPerson.ManagedPropertyProviding, SlateMutableObject, SlateRelationshipHydratingMutableObject {
    typealias ImmutableObject = TestPerson

    static let slateEntityName = "TestPerson"

    @NSManaged var name: String
    @NSManaged var profile: DatabaseTestProfile?
    @NSManaged var profiles: Set<DatabaseTestProfile>?
    @NSManaged var orderedProfiles: NSOrderedSet?

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestPerson> {
        NSFetchRequest<DatabaseTestPerson>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestPerson {
        DatabaseTestPerson(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestPerson {
        TestPerson(managedObject: self)
    }

    // This body intentionally mirrors `GeneratedSchemaRenderer.relationshipHydrationExpression`
    // byte-for-byte so the runtime tests exercise the exact code shape the
    // generator emits for to-one, unordered to-many, and ordered to-many
    // relationships. If the renderer changes its output, this body should
    // change with it (and `rendersAllRelationshipKindHydrationExpressions`
    // pins the renderer's contract).
    func slateObject(hydrating relationships: Set<String>) throws -> TestPerson {
        TestPerson(
            slateID: objectID,
            name: name,
            profile: relationships.contains("profile") ? profile?.slateObject : nil,
            profiles: relationships.contains("profiles") ? profiles?.map { $0.slateObject } : nil,
            orderedProfiles: relationships.contains("orderedProfiles") ? (orderedProfiles?.array as? [DatabaseTestProfile])?.map(\.slateObject) : nil
        )
    }
}

final class DatabaseTestProfile: NSManagedObject, TestProfile.ManagedPropertyProviding, SlateMutableObject, SlateRelationshipHydratingMutableObject {
    typealias ImmutableObject = TestProfile

    static let slateEntityName = "TestProfile"

    @NSManaged var biography: String
    @NSManaged var person: DatabaseTestPerson?

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestProfile> {
        NSFetchRequest<DatabaseTestProfile>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestProfile {
        DatabaseTestProfile(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestProfile {
        TestProfile(managedObject: self)
    }

    func slateObject(hydrating relationships: Set<String>) throws -> TestProfile {
        TestProfile(
            slateID: objectID,
            biography: biography
        )
    }
}

enum TestRelationshipSchema: SlateSchema {
    static let schemaIdentifier = "TestRelationshipSchema"
    static let schemaFingerprint = "test-relationships"
    static let entities: [SlateEntityMetadata] = []

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let personName = NSAttributeDescription()
        personName.name = "name"
        personName.attributeType = .stringAttributeType
        personName.isOptional = false

        let profileBiography = NSAttributeDescription()
        profileBiography.name = "biography"
        profileBiography.attributeType = .stringAttributeType
        profileBiography.isOptional = false

        let personEntity = NSEntityDescription()
        personEntity.name = "TestPerson"
        personEntity.managedObjectClassName = NSStringFromClass(DatabaseTestPerson.self)

        let profileEntity = NSEntityDescription()
        profileEntity.name = "TestProfile"
        profileEntity.managedObjectClassName = NSStringFromClass(DatabaseTestProfile.self)

        let personProfile = NSRelationshipDescription()
        personProfile.name = "profile"
        personProfile.destinationEntity = profileEntity
        personProfile.minCount = 0
        personProfile.maxCount = 1
        personProfile.deleteRule = .nullifyDeleteRule

        let personProfiles = NSRelationshipDescription()
        personProfiles.name = "profiles"
        personProfiles.destinationEntity = profileEntity
        personProfiles.minCount = 0
        personProfiles.maxCount = 0
        personProfiles.deleteRule = .nullifyDeleteRule

        let personOrderedProfiles = NSRelationshipDescription()
        personOrderedProfiles.name = "orderedProfiles"
        personOrderedProfiles.destinationEntity = profileEntity
        personOrderedProfiles.minCount = 0
        personOrderedProfiles.maxCount = 0
        personOrderedProfiles.deleteRule = .nullifyDeleteRule
        personOrderedProfiles.isOrdered = true

        let profilePerson = NSRelationshipDescription()
        profilePerson.name = "person"
        profilePerson.destinationEntity = personEntity
        profilePerson.minCount = 0
        profilePerson.maxCount = 1
        profilePerson.deleteRule = .nullifyDeleteRule

        personProfile.inverseRelationship = profilePerson
        profilePerson.inverseRelationship = personProfile

        personEntity.properties = [personName, personProfile, personProfiles, personOrderedProfiles]
        profileEntity.properties = [profileBiography, profilePerson]

        let model = NSManagedObjectModel()
        model.entities = [personEntity, profileEntity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestPerson.self,
            mutable: DatabaseTestPerson.self,
            entityName: "TestPerson"
        )
        registry.register(
            immutable: TestProfile.self,
            mutable: DatabaseTestProfile.self,
            entityName: "TestProfile"
        )
    }
}

// Test entity used to verify the throwing enum-hydration code path.
// `TestInvalid.color` HAS a default expression, so invalid stored values
// silently fall back to `.unknown`. `TestInvalid.shape` has NO default, so
// invalid stored values must throw `SlateError.invalidStoredValue`.
public struct TestInvalid: SlateObject, SlateKeypathAttributeProviding, SlateKeypathRelationshipProviding, Sendable {
    public let slateID: SlateID
    public let name: String
    public let color: Color
    public let shape: Shape

    public enum Color: String, Sendable {
        case unknown, red, blue
    }
    public enum Shape: String, Sendable {
        case circle, square
    }

    public init(slateID: SlateID = NSManagedObjectID(), name: String, color: Color, shape: Shape) {
        self.slateID = slateID
        self.name = name
        self.color = color
        self.shape = shape
    }

    public static func keypathToAttribute(_ keyPath: PartialKeyPath<TestInvalid>) -> String {
        switch keyPath {
        case \TestInvalid.name: "name"
        case \TestInvalid.color: "color"
        case \TestInvalid.shape: "shape"
        default: fatalError("Unsupported key path")
        }
    }

    public static func keypathToRelationship(_ keyPath: PartialKeyPath<TestInvalid>) -> String {
        switch keyPath {
        default: fatalError("Unsupported relationship key path")
        }
    }
}

final class DatabaseTestInvalid: NSManagedObject, SlateMutableObject, SlateRelationshipHydratingMutableObject {
    typealias ImmutableObject = TestInvalid

    static let slateEntityName = "TestInvalid"

    @NSManaged var name: String

    var color: TestInvalid.Color {
        get {
            willAccessValue(forKey: "color")
            defer { didAccessValue(forKey: "color") }
            let raw = primitiveValue(forKey: "color") as? String
            return raw.flatMap { TestInvalid.Color(rawValue: $0) } ?? TestInvalid.Color.unknown
        }
        set {
            willChangeValue(forKey: "color")
            defer { didChangeValue(forKey: "color") }
            setPrimitiveValue(newValue.rawValue, forKey: "color")
        }
    }

    var shape: TestInvalid.Shape {
        get {
            willAccessValue(forKey: "shape")
            defer { didAccessValue(forKey: "shape") }
            let raw = primitiveValue(forKey: "shape") as? String
            return raw.flatMap { TestInvalid.Shape(rawValue: $0) } ?? TestInvalid.Shape.circle
        }
        set {
            willChangeValue(forKey: "shape")
            defer { didChangeValue(forKey: "shape") }
            setPrimitiveValue(newValue.rawValue, forKey: "shape")
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<DatabaseTestInvalid> {
        NSFetchRequest<DatabaseTestInvalid>(entityName: slateEntityName)
    }

    static func create(in context: NSManagedObjectContext) -> DatabaseTestInvalid {
        DatabaseTestInvalid(entity: NSEntityDescription.entity(forEntityName: slateEntityName, in: context)!, insertInto: context)
    }

    var slateObject: TestInvalid {
        TestInvalid(slateID: objectID, name: name, color: color, shape: shape)
    }

    // Mirrors what the generator emits: pre-flight resolves enums with
    // default-fallback for `color` (has default) and throw-on-invalid for
    // `shape` (no default).
    func slateObject(hydrating relationships: Set<String>) throws -> TestInvalid {
        let resolvedColor: TestInvalid.Color = (primitiveValue(forKey: "color") as? String).flatMap {
            TestInvalid.Color(rawValue: $0)
        } ?? TestInvalid.Color.unknown

        guard let rawShape = primitiveValue(forKey: "shape") as? String else {
            throw SlateError.invalidStoredValue(entity: "TestInvalid", property: "shape", valueDescription: "nil")
        }
        guard let resolvedShape = TestInvalid.Shape(rawValue: rawShape) else {
            throw SlateError.invalidStoredValue(entity: "TestInvalid", property: "shape", valueDescription: String(describing: rawShape))
        }

        return TestInvalid(
            slateID: objectID,
            name: name,
            color: resolvedColor,
            shape: resolvedShape
        )
    }
}

enum TestInvalidSchema: SlateSchema {
    static let schemaIdentifier = "TestInvalidSchema"
    static let schemaFingerprint = "test-invalid"
    static let entities: [SlateEntityMetadata] = []

    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false

        let color = NSAttributeDescription()
        color.name = "color"
        color.attributeType = .stringAttributeType
        color.isOptional = false
        color.defaultValue = TestInvalid.Color.unknown.rawValue

        let shape = NSAttributeDescription()
        shape.name = "shape"
        shape.attributeType = .stringAttributeType
        shape.isOptional = false
        shape.defaultValue = TestInvalid.Shape.circle.rawValue

        let entity = NSEntityDescription()
        entity.name = "TestInvalid"
        entity.managedObjectClassName = NSStringFromClass(DatabaseTestInvalid.self)
        entity.properties = [name, color, shape]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    static func registerTables(_ registry: inout SlateTableRegistry) {
        registry.register(
            immutable: TestInvalid.self,
            mutable: DatabaseTestInvalid.self,
            entityName: "TestInvalid"
        )
    }
}

@Suite
struct SlateRuntimeTests {
    @Test
    func queryAndMutateInMemory() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        let authors = try await slate.query { context in
            try context[TestAuthor.self]
                .where(\.name == "Ada")
                .many()
        }

        #expect(authors.map(\.name) == ["Ada"])
    }

    @Test
    func queryHydratesRequestedToOneRelationship() async throws {
        let slate = Slate<TestRelationshipSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let person = context.create(DatabaseTestPerson.self)
            person.name = "Ada"

            let profile = context.create(DatabaseTestProfile.self)
            profile.biography = "Mathematician"
            profile.person = person
            person.profile = profile
        }

        let unresolved = try await slate.query { context in
            try context[TestPerson.self].one()
        }
        #expect(unresolved?.profile == nil)

        let resolved = try await slate.query { context in
            try context[TestPerson.self]
                .relationships([\.profile])
                .one()
        }
        #expect(resolved?.profile?.biography == "Mathematician")
    }

    @Test
    func directQueryConveniences() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let one = try await slate.one(TestAuthor.self, where: \.name == "Bea")
        #expect(one?.name == "Bea")

        let many = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        )
        #expect(many.map(\.name) == ["Ada", "Bea", "Cyd"])

        let firstTwo = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)],
            limit: 2
        )
        #expect(firstTwo.map(\.name) == ["Ada", "Bea"])

        let offsetOne = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)],
            offset: 1
        )
        #expect(offsetOne.map(\.name) == ["Bea", "Cyd"])

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 3)

        let filteredCount = try await slate.count(TestAuthor.self, where: \.name == "Bea")
        #expect(filteredCount == 1)
    }

    @Test
    func directQueryHydratesRelationships() async throws {
        let slate = Slate<TestRelationshipSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let person = context.create(DatabaseTestPerson.self)
            person.name = "Ada"

            let profile = context.create(DatabaseTestProfile.self)
            profile.biography = "Mathematician"
            profile.person = person
            person.profile = profile
        }

        let resolved = try await slate.one(
            TestPerson.self,
            relationships: [\TestPerson.profile]
        )
        #expect(resolved?.profile?.biography == "Mathematician")

        let unresolved = try await slate.one(TestPerson.self)
        #expect(unresolved?.profile == nil)
    }

    @Test
    func queryHydratesRequestedToManyRelationships() async throws {
        let slate = Slate<TestRelationshipSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let person = context.create(DatabaseTestPerson.self)
            person.name = "Ada"

            let firstProfile = context.create(DatabaseTestProfile.self)
            firstProfile.biography = "Analyst"

            let secondProfile = context.create(DatabaseTestProfile.self)
            secondProfile.biography = "Programmer"

            person.profiles = [firstProfile, secondProfile]
            person.orderedProfiles = NSOrderedSet(array: [secondProfile, firstProfile])
        }

        let unresolved = try await slate.query { context in
            try context[TestPerson.self].one()
        }
        #expect(unresolved?.profiles == nil)
        #expect(unresolved?.orderedProfiles == nil)

        let resolved = try await slate.query { context in
            try context[TestPerson.self]
                .relationships([\.profiles, \.orderedProfiles])
                .one()
        }

        #expect(resolved?.profiles?.map(\.biography).sorted() == ["Analyst", "Programmer"])
        #expect(resolved?.orderedProfiles?.map(\.biography) == ["Programmer", "Analyst"])
        #expect(resolved?.profile == nil)
    }

    @Test
    func mutationFirstOrCreate() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            _ = try context[DatabaseTestAuthor.self].firstOrCreate(\.name, "Ada")
            _ = try context[DatabaseTestAuthor.self].firstOrCreate(\.name, "Ada")
            _ = try context[DatabaseTestAuthor.self].firstOrCreate(\.name, "Bea")
        }

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 2)
    }

    @Test
    func mutationFirstOrCreateMany() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        try await slate.mutate { context in
            let result = try context[DatabaseTestAuthor.self]
                .firstOrCreateMany(\.name, ["Ada", "Bea", "Cyd", "Ada"])
            #expect(result.count == 3)
            #expect(result.keys.sorted() == ["Ada", "Bea", "Cyd"])
        }

        let names = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        ).map(\.name)
        #expect(names == ["Ada", "Bea", "Cyd"])

        try await slate.mutate { context in
            let empty = try context[DatabaseTestAuthor.self]
                .firstOrCreateMany(\.name, [String]())
            #expect(empty.isEmpty)
        }
    }

    @Test
    func mutationDictionary() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        try await slate.mutate { context in
            let dict = try context[DatabaseTestAuthor.self].dictionary(by: \.name)
            #expect(dict.count == 3)
            #expect(dict["Ada"]?.name == "Ada")
            #expect(dict["Bea"]?.name == "Bea")
        }
    }

    @Test
    func mutationDeleteMissing() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd", "Dru"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        try await slate.mutate { context in
            let removed = try context[DatabaseTestAuthor.self]
                .deleteMissing(key: \.name, keeping: ["Bea", "Dru"], emptySetDeletesAll: false)
            #expect(removed == 2)
        }

        let names = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        ).map(\.name)
        #expect(names == ["Bea", "Dru"])
    }

    @Test
    func mutationDeleteMissingEmptyRequiresFlag() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        await #expect(throws: SlateError.emptyDeleteMissingSet) {
            try await slate.mutate { context in
                _ = try context[DatabaseTestAuthor.self]
                    .deleteMissing(key: \.name, keeping: [String](), emptySetDeletesAll: false)
            }
        }

        try await slate.mutate { context in
            let removed = try context[DatabaseTestAuthor.self]
                .deleteMissing(key: \.name, keeping: [String](), emptySetDeletesAll: true)
            #expect(removed == 1)
        }

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 0)
    }

    @Test
    func upsertReturnsExistingRowForUniqueAttribute() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let row = try context[DatabaseTestAuthor.self].upsert(\.name, "Ada")
            #expect(row.name == "Ada")
        }

        try await slate.mutate { context in
            // Second upsert with same key returns the existing row, no new
            // row is created.
            let row = try context[DatabaseTestAuthor.self].upsert(\.name, "Ada")
            #expect(row.name == "Ada")
        }

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 1)
    }

    @Test
    func upsertManyMatchesOrCreatesRowsForUniqueAttribute() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let row = context.create(DatabaseTestAuthor.self)
            row.name = "Ada"
        }

        try await slate.mutate { context in
            let result = try context[DatabaseTestAuthor.self]
                .upsertMany(\.name, ["Ada", "Bea", "Cyd"])
            #expect(result.count == 3)
            #expect(Set(result.keys) == ["Ada", "Bea", "Cyd"])
        }

        let names = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        ).map(\.name)
        #expect(names == ["Ada", "Bea", "Cyd"])
    }

    @Test
    func upsertRejectsKeyOutsideDeclaredUniquenessConstraints() async throws {
        let slate = Slate<TestUnconstrainedSchema>(
            storeURL: nil,
            storeType: NSInMemoryStoreType
        )
        try await slate.configure()

        await #expect(throws: SlateError.upsertKeyNotUnique(
            entity: "TestUnconstrainedAuthor",
            attribute: "name"
        )) {
            try await slate.mutate { context in
                _ = try context[DatabaseTestUnconstrainedAuthor.self]
                    .upsert(\.name, "Ada")
            }
        }
    }

    @Test
    func upsertManyRejectsKeyOutsideDeclaredUniquenessConstraints() async throws {
        let slate = Slate<TestUnconstrainedSchema>(
            storeURL: nil,
            storeType: NSInMemoryStoreType
        )
        try await slate.configure()

        await #expect(throws: SlateError.upsertKeyNotUnique(
            entity: "TestUnconstrainedAuthor",
            attribute: "name"
        )) {
            try await slate.mutate { context in
                _ = try context[DatabaseTestUnconstrainedAuthor.self]
                    .upsertMany(\.name, ["Ada", "Bea"])
            }
        }
    }

    @Test
    func mutationDeleteWhere() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        try await slate.mutate { context in
            let removed = try context[DatabaseTestAuthor.self].delete(where: \.name == "Bea")
            #expect(removed == 1)
        }

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 2)
    }

    // In-memory stores do not support `NSBatchDeleteRequest`, so this exercises
    // the fetch + per-row delete + save fallback path. The test confirms (a)
    // matching rows are deleted, (b) `count(...)` reflects the deletion, and
    // (c) the cache no longer holds the deleted IDs (a subsequent query
    // returns the surviving rows only).
    @Test
    func batchDeleteFallbackInMemoryStore() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd", "Dru"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        // Warm the cache with all rows so we can verify deleted IDs are
        // evicted and only surviving rows remain reachable through cache hits.
        let warmed = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])
        #expect(warmed.map(\.name) == ["Ada", "Bea", "Cyd", "Dru"])

        let removed = try await slate.batchDelete(
            TestAuthor.self,
            where: .in(\.name, ["Bea", "Dru"])
        )
        #expect(removed == 2)

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 2)

        let names = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        ).map(\.name)
        #expect(names == ["Ada", "Cyd"])
    }

    @Test
    func batchDeleteWithoutPredicateClearsAll() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        let removed = try await slate.batchDelete(TestAuthor.self)
        #expect(removed == 3)
        #expect(try await slate.count(TestAuthor.self) == 0)
    }

    @Test
    func batchDeleteRejectedWhenClosed() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()
        await slate.close()

        await #expect(throws: SlateError.closed) {
            _ = try await slate.batchDelete(TestAuthor.self)
        }
    }

    // SQLite stores do support `NSBatchDeleteRequest`. This test goes through
    // the real batch path: it provisions a temporary on-disk store, runs a
    // batch delete, and verifies the writer-context's cache and on-disk row
    // count are both updated.
    @Test
    func batchDeleteOnSQLiteStorePath() async throws {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("SlateBatchDeleteTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appendingPathComponent("Test.sqlite")
        let slate = Slate<TestSchema>(
            storeURL: storeURL,
            storeType: NSSQLiteStoreType
        )
        try await slate.configure()

        try await slate.mutate { context in
            for name in ["Ada", "Bea", "Cyd", "Dru"] {
                let author = context.create(DatabaseTestAuthor.self)
                author.name = name
            }
        }

        // Warm the cache.
        _ = try await slate.many(TestAuthor.self, sort: [SlateSort(\TestAuthor.name)])

        let removed = try await slate.batchDelete(
            TestAuthor.self,
            where: .in(\.name, ["Bea", "Dru"])
        )
        #expect(removed == 2)

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 2)

        let names = try await slate.many(
            TestAuthor.self,
            sort: [SlateSort(\TestAuthor.name)]
        ).map(\.name)
        #expect(names == ["Ada", "Cyd"])

        await slate.close()
    }

    @Test
    func closedSlateRejectsOperations() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let author = context.create(DatabaseTestAuthor.self)
            author.name = "Ada"
        }

        await slate.close()

        await #expect(throws: SlateError.closed) {
            try await slate.query { _ in }
        }

        await #expect(throws: SlateError.closed) {
            try await slate.mutate { _ in }
        }

        await #expect(throws: SlateError.closed) {
            _ = try await slate.count(TestAuthor.self)
        }

        await #expect(throws: SlateError.closed) {
            try await slate.configure()
        }
    }

    @Test
    func closeIsIdempotent() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()
        await slate.close()
        await slate.close()
    }

    @Test
    func closeBeforeConfigureBlocksConfigure() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        await slate.close()
        await #expect(throws: SlateError.closed) {
            try await slate.configure()
        }
    }

    @Test
    func mutationRollbackOnUserThrow() async throws {
        let slate = Slate<TestSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        struct UserError: Error {}

        await #expect(throws: UserError.self) {
            try await slate.mutate { context in
                let author = context.create(DatabaseTestAuthor.self)
                author.name = "Ada"
                throw UserError()
            }
        }

        let count = try await slate.count(TestAuthor.self)
        #expect(count == 0)
    }

    @Test
    func enumWithDefaultFallsBackOnInvalidStoredValue() async throws {
        let slate = Slate<TestInvalidSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let row = context.create(DatabaseTestInvalid.self)
            row.name = "A"
            row.color = .red
            row.shape = .square
        }

        // Plant a stored raw value that no longer maps to any enum case.
        try await slate.mutate { context in
            guard let row = try context[DatabaseTestInvalid.self].one() else {
                Issue.record("expected a row")
                return
            }
            row.willChangeValue(forKey: "color")
            row.setPrimitiveValue("legacy_color", forKey: "color")
            row.didChangeValue(forKey: "color")
        }

        // `color` has a default — the throwing hydration path silently
        // resolves the unmappable raw value to `.unknown` rather than
        // throwing.
        let row = try await slate.one(TestInvalid.self)
        #expect(row?.color == .unknown)
        #expect(row?.shape == .square)
    }

    @Test
    func enumWithoutDefaultThrowsOnInvalidStoredValue() async throws {
        let slate = Slate<TestInvalidSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let row = context.create(DatabaseTestInvalid.self)
            row.name = "A"
            row.color = .red
            row.shape = .square
        }

        // Plant an unmappable raw value on the no-default attribute.
        try await slate.mutate { context in
            guard let row = try context[DatabaseTestInvalid.self].one() else {
                Issue.record("expected a row")
                return
            }
            row.willChangeValue(forKey: "shape")
            row.setPrimitiveValue("hexagon", forKey: "shape")
            row.didChangeValue(forKey: "shape")
        }

        // `shape` has no declared default — the hydration path must throw
        // SlateError.invalidStoredValue with the entity, property, and the
        // unmappable raw value.
        await #expect(throws: SlateError.invalidStoredValue(
            entity: "TestInvalid",
            property: "shape",
            valueDescription: "hexagon"
        )) {
            _ = try await slate.one(TestInvalid.self)
        }
    }

    // The sort: parameter accepts three shapes:
    //   - [SlateSort<Value>]                       — full control
    //   - [.asc(\.x), .desc(\.y)]                  — leading-dot shorthand
    //   - [\.x, \.y]                               — ascending-only keypaths
    // This test exercises all three against the same data to make sure
    // the overload set resolves correctly and produces identical
    // ascending-direction sorts.
    @Test
    func sortAcceptsKeyPathShorthandAndAscDescFactories() async throws {
        let slate = SlateFixtures.PatientSlate(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            for (id, first, last) in [
                ("1", "Ada", "Lovelace"),
                ("2", "Grace", "Hopper"),
                ("3", "Margaret", "Hamilton"),
                ("4", "Ada", "Hamilton"),
            ] {
                let row = context.create(DatabasePatient.self)
                row.patientId = id
                row.firstName = first
                row.lastName = last
                row.status = .active
                row.address_has = false
            }
        }

        // Form 1: explicit [SlateSort] (legacy form, still supported).
        let viaSlateSort = try await slate.many(
            Patient.self,
            sort: [SlateSort(\Patient.lastName), SlateSort(\Patient.firstName)]
        ).map { "\($0.lastName) \($0.firstName)" }

        // Form 2: leading-dot factories with mixed direction.
        let viaFactories = try await slate.many(
            Patient.self,
            sort: [.asc(\.lastName), .desc(\.firstName)]
        ).map { "\($0.lastName) \($0.firstName)" }

        // Form 3: bare keypath array (ascending only).
        let viaKeyPaths = try await slate.many(
            Patient.self,
            sort: [\.lastName, \.firstName]
        ).map { "\($0.lastName) \($0.firstName)" }

        // Forms 1 and 3 are equivalent (both ascending on lastName, firstName).
        #expect(viaSlateSort == viaKeyPaths)
        #expect(viaKeyPaths == [
            "Hamilton Ada",
            "Hamilton Margaret",
            "Hopper Grace",
            "Lovelace Ada",
        ])

        // Form 2 sorts firstName descending within each lastName.
        #expect(viaFactories == [
            "Hamilton Margaret",
            "Hamilton Ada",
            "Hopper Grace",
            "Lovelace Ada",
        ])
    }

    // End-to-end embedded keypath alignment: insert two Patients with
    // different embedded `address.city` values, then query by an
    // immutable keypath predicate (`\Patient.address?.city == "Boston"`).
    // The runtime translates the keypath through Patient.keypathToAttribute
    // (macro-emitted) into the Core Data column (`address_city`,
    // generator-emitted) — if they disagree, Core Data raises an
    // unknown-key fetch error. A passing test means macro and generator
    // both emit the same flattened storage names.
    @Test
    func embeddedKeypathPredicateRoutesToFlattenedStorageColumn() async throws {
        let slate = SlateFixtures.PatientSlate(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()

        try await slate.mutate { context in
            let bostonPatient = context.create(DatabasePatient.self)
            bostonPatient.patientId = "P1"
            bostonPatient.firstName = "Ada"
            bostonPatient.lastName = "Lovelace"
            bostonPatient.status = .active
            bostonPatient.address_has = true
            bostonPatient.address_line1 = "1 Main St"
            bostonPatient.address_city = "Boston"
            bostonPatient.zip = "02101"

            let nycPatient = context.create(DatabasePatient.self)
            nycPatient.patientId = "P2"
            nycPatient.firstName = "Grace"
            nycPatient.lastName = "Hopper"
            nycPatient.status = .active
            nycPatient.address_has = true
            nycPatient.address_line1 = "200 Broadway"
            nycPatient.address_city = "New York"
            nycPatient.zip = "10007"
        }

        // Predicate uses the immutable keypath into the embedded struct;
        // the runtime resolves it to "address_city" via keypathToAttribute.
        let bostonOnly = try await slate.many(
            Patient.self,
            where: \.address?.city == "Boston"
        )
        #expect(bostonOnly.map(\.firstName) == ["Ada"])

        // Honors a `@SlateAttribute(storageName:)` override too: zip is
        // the Core Data column for `address?.postalCode`.
        let zipMatch = try await slate.many(
            Patient.self,
            where: \.address?.postalCode == "10007"
        )
        #expect(zipMatch.map(\.firstName) == ["Grace"])
    }

    @Test
    func entityEqualityIsContentBasedAndIdentityIsSlateID() async throws {
        // Persist one Patient so we have a stable, real `slateID`.
        let slate = SlateFixtures.PatientSlate(storeURL: nil, storeType: NSInMemoryStoreType)
        try await slate.configure()
        try await slate.mutate { context in
            let p = context.create(DatabasePatient.self)
            p.patientId = "p1"
            p.firstName = "Ada"
            p.lastName = "Lovelace"
            p.age = 30
            p.status = .active
            p.address_has = false
        }
        let original = try await slate.one(Patient.self, where: \Patient.patientId == "p1")!

        // Same slateID + same content → equal, same hash.
        let copy = Patient(
            slateID: original.slateID,
            patientId: original.patientId,
            firstName: original.firstName,
            lastName: original.lastName,
            age: original.age,
            status: original.status,
            address: original.address
        )
        #expect(original == copy)
        #expect(original.hashValue == copy.hashValue)

        // Same slateID + mutated content → NOT equal (the regression case
        // that motivated content-based equality — UI must redraw on edit).
        let edited = Patient(
            slateID: original.slateID,
            patientId: original.patientId,
            firstName: "Augusta",
            lastName: original.lastName,
            age: original.age,
            status: original.status,
            address: original.address
        )
        #expect(original != edited)

        // Identifiable's id is the slateID — stable across content edits so
        // SwiftUI ForEach keeps the same row identity through a mutation.
        #expect(original.id == edited.id)
        #expect(original.id == original.slateID)
    }
}

/// Test helpers for the in-tree fixture targets. Hidden behind a namespace
/// so the runtime test file doesn't pollute its public symbols.
private enum SlateFixtures {
    typealias PatientSlate = Slate<PatientSlateSchema>
}
