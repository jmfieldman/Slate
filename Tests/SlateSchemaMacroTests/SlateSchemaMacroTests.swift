import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import SlateSchemaMacros

@Suite
struct SlateSchemaMacroTests {
    @Test
    func slateEntityExpandsImmutableScaffolding() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient {
                public let patientId: String
                @SlateAttribute(storageName: "yearsOld")
                public let age: Int?
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public let patientId: String
                public let age: Int?

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String,
                    age: Int?
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                    self.age = age
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                    self.age = managedObject.age
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                    var age: Int? { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    case \\Patient.age: "yearsOld"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                        && lhs.age == rhs.age
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                    hasher.combine(age)
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func slateEmbeddedIsPeerOnlyOnStruct() {
        // `@SlateEmbedded` is peer-only — it does not synthesize a
        // memberwise initializer. Authors must declare a public init
        // for nested embedded structs so that generated bridge code
        // can construct them across modules.
        assertMacroExpansion(
            """
            @SlateEmbedded
            public struct Address {
                public let city: String?
                public let postalCode: String?

                public init(city: String?, postalCode: String?) {
                    self.city = city
                    self.postalCode = postalCode
                }
            }
            """,
            expandedSource:
            """
            public struct Address {
                public let city: String?
                public let postalCode: String?

                public init(city: String?, postalCode: String?) {
                    self.city = city
                    self.postalCode = postalCode
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func slateEntityExpandsRelationshipAccessors() {
        assertMacroExpansion(
            """
            @SlateEntity(
                relationships: [
                    .toOne("primaryDoctor", Doctor.self, inverse: "patients"),
                    .toMany("notes", PatientNote.self, inverse: "patient", ordered: true)
                ]
            )
            public struct Patient {
                public let patientId: String
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public let patientId: String

                public let slateID: SlateID

                public let primaryDoctor: Doctor?

                public let notes: [PatientNote]?

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String,
                    primaryDoctor: Doctor? = nil,
                    notes: [PatientNote]? = nil
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                    self.primaryDoctor = primaryDoctor
                    self.notes = notes
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                    self.primaryDoctor = nil
                    self.notes = nil
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.primaryDoctor: "primaryDoctor"
                    case \\Patient.notes: "notes"
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func slateEntityEmbeddedKeypathsMapToFlattenedStorageNames() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient {
                public let patientId: String

                @SlateEmbedded
                public let address: Address?

                @SlateEmbedded
                public let name: Name

                @SlateEmbedded
                public struct Address {
                    public let city: String?
                    @SlateAttribute(storageName: "addr_zip")
                    public let postalCode: String?
                }

                @SlateEmbedded
                public struct Name {
                    public let first: String?
                    public let last: String?
                }
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public let patientId: String

                @SlateEmbedded
                public let address: Address?

                @SlateEmbedded
                public let name: Name

                @SlateEmbedded
                public struct Address {
                    public let city: String?
                    @SlateAttribute(storageName: "addr_zip")
                    public let postalCode: String?
                }

                @SlateEmbedded
                public struct Name {
                    public let first: String?
                    public let last: String?
                }

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String,
                    address: Address?,
                    name: Name
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                    self.address = address
                    self.name = name
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                    self.address = managedObject.address
                    self.name = managedObject.name
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                    var address: Address? { get }
                    var name: Name { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    case \\Patient.address?.city: "address_city"
                    case \\Patient.address?.postalCode: "addr_zip"
                    case \\Patient.name.first: "name_first"
                    case \\Patient.name.last: "name_last"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                        && lhs.address == rhs.address
                        && lhs.name == rhs.name
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                    hasher.combine(address)
                    hasher.combine(name)
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesNonPublicEntity() {
        assertMacroExpansion(
            """
            @SlateEntity
            struct Patient {
                let patientId: String
            }
            """,
            expandedSource:
            """
            struct Patient {
                let patientId: String

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity types must be declared 'public'",
                    line: 2,
                    column: 8,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesGenericEntity() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient<T> {
                public let patientId: String
            }
            """,
            expandedSource:
            """
            public struct Patient<T> {
                public let patientId: String

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity does not support generic types",
                    line: 2,
                    column: 22,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesInheritedClassEntity() {
        assertMacroExpansion(
            """
            @SlateEntity
            public final class Patient: Person, Sendable {
                public let patientId: String
            }
            """,
            expandedSource:
            """
            public final class Patient: Person, Sendable {
                public let patientId: String

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity classes may conform to protocols but must not inherit from a base class",
                    line: 2,
                    column: 29,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesAnnotatedComputedProperty() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient {
                public let patientId: String
                @SlateAttribute
                public var derived: Int { 7 }
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public let patientId: String
                @SlateAttribute
                public var derived: Int { 7 }

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity persisted properties must be stored ('let'); computed properties cannot be persisted",
                    line: 4,
                    column: 5,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesConditionalPersistedProperty() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient {
                public let patientId: String
                #if DEBUG
                @SlateAttribute
                public let debugFlag: Bool
                #endif
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public let patientId: String
                #if DEBUG
                @SlateAttribute
                public let debugFlag: Bool
                #endif

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID(),
                    patientId: String
                ) {
                    self.slateID = slateID
                    self.patientId = patientId
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                    self.patientId = managedObject.patientId
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                    var patientId: String { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    case \\Patient.patientId: "patientId"
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                        && lhs.patientId == rhs.patientId
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                    hasher.combine(patientId)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity persisted properties cannot be wrapped in conditional compilation (#if) blocks",
                    line: 4,
                    column: 5,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    @Test
    func slateEntityDiagnosesMutableStoredProperties() {
        assertMacroExpansion(
            """
            @SlateEntity
            public struct Patient {
                public var patientId: String
            }
            """,
            expandedSource:
            """
            public struct Patient {
                public var patientId: String

                public let slateID: SlateID

                public init(
                    slateID: SlateID = NSManagedObjectID()
                ) {
                    self.slateID = slateID
                }

                public init(managedObject: some ManagedPropertyProviding) {
                    self.slateID = managedObject.objectID
                }

                public protocol ManagedPropertyProviding: AnyObject {
                    var objectID: SlateID { get }
                }

                public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate key path")
                    }
                }

                public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
                    switch keyPath {
                    default:
                        fatalError("Unsupported Slate relationship key path")
                    }
                }
            }

            extension Patient: SlateObject {
            }

            extension Patient: SlateKeypathAttributeProviding {
            }

            extension Patient: SlateKeypathRelationshipProviding {
            }

            extension Patient: Identifiable {
                public var id: SlateID {
                    slateID
                }
            }

            extension Patient: Equatable {
                public static func == (lhs: Patient, rhs: Patient) -> Bool {
                    lhs.slateID == rhs.slateID
                }
            }

            extension Patient: Hashable {
                public func hash(into hasher: inout Hasher) {
                    hasher.combine(slateID)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SlateEntity persisted properties must be declared with 'let'",
                    line: 3,
                    column: 5,
                    severity: .error
                ),
            ],
            macros: testMacros
        )
    }
}

private let testMacros: [String: Macro.Type] = [
    "SlateEntity": SlateEntityMacro.self,
    "SlateEmbedded": SlateEmbeddedMacro.self,
]
