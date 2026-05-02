import Foundation

public struct NormalizedSchema: Sendable, Codable, Equatable {
    public let schemaName: String
    public let schemaFingerprint: String
    public let modelModule: String
    public let runtimeModule: String
    public let entities: [NormalizedEntity]

    public init(
        schemaName: String,
        schemaFingerprint: String,
        modelModule: String,
        runtimeModule: String,
        entities: [NormalizedEntity]
    ) {
        self.schemaName = schemaName
        self.schemaFingerprint = schemaFingerprint
        self.modelModule = modelModule
        self.runtimeModule = runtimeModule
        self.entities = entities
    }
}

public struct GeneratedFile: Sendable, Codable, Equatable {
    public let path: String
    public let contents: String
    public let kind: GeneratedFileKind

    public init(path: String, contents: String, kind: GeneratedFileKind = .schema) {
        self.path = path
        self.contents = contents
        self.kind = kind
    }
}

/// Logical category for a generated artifact. The CLI uses these to route
/// each file to the appropriate output directory (`--output-mutable`,
/// `--output-bridge`, `--output-schema`, `--output-manifest`). When all
/// directories collapse to a single output (the legacy `--output` flag),
/// every kind lands in the same place.
public enum GeneratedFileKind: String, Sendable, Codable, Equatable {
    case mutable
    case bridge
    case schema
    case manifest
}

public struct GenerationManifest: Sendable, Codable, Equatable {
    public let generatorVersion: Int
    public let schemaFingerprint: String
    public let files: [String]

    public init(generatorVersion: Int = 1, schemaFingerprint: String, files: [String]) {
        self.generatorVersion = generatorVersion
        self.schemaFingerprint = schemaFingerprint
        self.files = files
    }
}

public struct NormalizedEntity: Sendable, Codable, Equatable {
    public let swiftName: String
    public let entityName: String
    public let mutableName: String
    public let sourceKind: String
    public let attributes: [NormalizedAttribute]
    public let embedded: [NormalizedEmbedded]
    public let relationships: [NormalizedRelationship]
    public let indexes: [NormalizedIndex]
    public let uniqueness: [NormalizedUniqueness]

    public init(
        swiftName: String,
        entityName: String,
        mutableName: String,
        sourceKind: String,
        attributes: [NormalizedAttribute],
        embedded: [NormalizedEmbedded] = [],
        relationships: [NormalizedRelationship] = [],
        indexes: [NormalizedIndex] = [],
        uniqueness: [NormalizedUniqueness] = []
    ) {
        self.swiftName = swiftName
        self.entityName = entityName
        self.mutableName = mutableName
        self.sourceKind = sourceKind
        self.attributes = attributes
        self.embedded = embedded
        self.relationships = relationships
        self.indexes = indexes
        self.uniqueness = uniqueness
    }
}

public struct NormalizedIndex: Sendable, Codable, Equatable {
    public let storageNames: [String]
    public let order: String

    public init(storageNames: [String], order: String = "ascending") {
        self.storageNames = storageNames
        self.order = order
    }
}

public struct NormalizedUniqueness: Sendable, Codable, Equatable {
    public let storageNames: [String]

    public init(storageNames: [String]) {
        self.storageNames = storageNames
    }
}

public struct NormalizedAttribute: Sendable, Codable, Equatable {
    public let swiftName: String
    public let storageName: String
    public let swiftType: String
    public let storageType: String
    public let optional: Bool
    public let indexed: Bool
    public let defaultExpression: String?
    public let enumKind: NormalizedEnumKind?

    public init(
        swiftName: String,
        storageName: String,
        swiftType: String,
        storageType: String,
        optional: Bool,
        indexed: Bool = false,
        defaultExpression: String? = nil,
        enumKind: NormalizedEnumKind? = nil
    ) {
        self.swiftName = swiftName
        self.storageName = storageName
        self.swiftType = swiftType
        self.storageType = storageType
        self.optional = optional
        self.indexed = indexed
        self.defaultExpression = defaultExpression
        self.enumKind = enumKind
    }
}

/// Description of an attribute backed by a `RawRepresentable` enum nested
/// inside the entity declaration.
///
/// `typeName` is the unqualified Swift name of the enum (e.g., `Sex`), so
/// renderers must qualify it with the entity name (e.g., `Patient.Sex`).
/// `rawType` is the storage Swift type the runtime persists (e.g.,
/// `String`, `Int16`, `Int32`, `Int64`).
public struct NormalizedEnumKind: Sendable, Codable, Equatable {
    public let typeName: String
    public let rawType: String

    public init(typeName: String, rawType: String) {
        self.typeName = typeName
        self.rawType = rawType
    }
}

public struct NormalizedEmbedded: Sendable, Codable, Equatable {
    public let swiftName: String
    public let swiftType: String
    public let optional: Bool
    public let presenceStorageName: String?
    public let attributes: [NormalizedAttribute]

    public init(
        swiftName: String,
        swiftType: String,
        optional: Bool,
        presenceStorageName: String?,
        attributes: [NormalizedAttribute]
    ) {
        self.swiftName = swiftName
        self.swiftType = swiftType
        self.optional = optional
        self.presenceStorageName = presenceStorageName
        self.attributes = attributes
    }
}

public struct NormalizedRelationship: Sendable, Codable, Equatable {
    public let name: String
    public let kind: String
    public let destination: String
    public let inverse: String
    public let deleteRule: String
    public let ordered: Bool
    public let optional: Bool
    public let minCount: Int?
    public let maxCount: Int?

    public init(
        name: String,
        kind: String,
        destination: String,
        inverse: String,
        deleteRule: String,
        ordered: Bool = false,
        optional: Bool = true,
        minCount: Int? = nil,
        maxCount: Int? = nil
    ) {
        self.name = name
        self.kind = kind
        self.destination = destination
        self.inverse = inverse
        self.deleteRule = deleteRule
        self.ordered = ordered
        self.optional = optional
        self.minCount = minCount
        self.maxCount = maxCount
    }
}
