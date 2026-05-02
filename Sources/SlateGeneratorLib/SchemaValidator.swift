import Foundation

public struct SchemaValidator: Sendable {
    public init() {}

    public func validate(_ schema: NormalizedSchema) throws {
        var issues: [SchemaValidationIssue] = []

        issues += duplicateIssues(
            values: schema.entities.map(\.swiftName),
            message: { "Duplicate Swift entity name '\($0)'." }
        )
        issues += duplicateIssues(
            values: schema.entities.map(\.entityName),
            message: { "Duplicate Core Data entity name '\($0)'." }
        )
        issues += duplicateIssues(
            values: schema.entities.map(\.mutableName),
            message: { "Duplicate mutable object name '\($0)'." }
        )

        let entitiesBySwiftName = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.swiftName, $0) })

        for entity in schema.entities {
            validateEntity(entity, entitiesBySwiftName: entitiesBySwiftName, issues: &issues)
        }

        guard issues.isEmpty else {
            throw SchemaValidationError(issues: issues)
        }
    }

    private func validateEntity(
        _ entity: NormalizedEntity,
        entitiesBySwiftName: [String: NormalizedEntity],
        issues: inout [SchemaValidationIssue]
    ) {
        let storageAttributes = storageAttributes(for: entity)

        issues += duplicateIssues(
            values: storageAttributes.map(\.storageName),
            message: { "Entity '\(entity.swiftName)' has duplicate storage name '\($0)'." }
        )
        issues += duplicateIssues(
            values: entity.relationships.map(\.name),
            message: { "Entity '\(entity.swiftName)' has duplicate relationship name '\($0)'." }
        )

        for attribute in storageAttributes {
            if !Self.supportedStorageTypes.contains(attribute.storageType) {
                issues.append(SchemaValidationIssue(
                    message: "Entity '\(entity.swiftName)' attribute '\(attribute.swiftName)' uses unsupported storage type '\(attribute.storageType)' from Swift type '\(attribute.swiftType)'."
                ))
            }
        }

        let validStorageNames = Set(storageAttributes.map(\.storageName))
        for index in entity.indexes {
            validateStorageReferences(
                index.storageNames,
                validStorageNames: validStorageNames,
                entityName: entity.swiftName,
                purpose: "index",
                issues: &issues
            )
        }
        for uniqueness in entity.uniqueness {
            validateStorageReferences(
                uniqueness.storageNames,
                validStorageNames: validStorageNames,
                entityName: entity.swiftName,
                purpose: "uniqueness constraint",
                issues: &issues
            )
        }

        for relationship in entity.relationships {
            validateRelationship(
                relationship,
                sourceEntity: entity,
                entitiesBySwiftName: entitiesBySwiftName,
                issues: &issues
            )
        }
    }

    private func validateStorageReferences(
        _ storageNames: [String],
        validStorageNames: Set<String>,
        entityName: String,
        purpose: String,
        issues: inout [SchemaValidationIssue]
    ) {
        if storageNames.isEmpty {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(entityName)' has an empty \(purpose)."
            ))
        }

        for storageName in storageNames where !validStorageNames.contains(storageName) {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(entityName)' \(purpose) references unknown storage name '\(storageName)'."
            ))
        }
    }

    private func validateRelationship(
        _ relationship: NormalizedRelationship,
        sourceEntity: NormalizedEntity,
        entitiesBySwiftName: [String: NormalizedEntity],
        issues: inout [SchemaValidationIssue]
    ) {
        if !["toOne", "toMany"].contains(relationship.kind) {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(sourceEntity.swiftName)' relationship '\(relationship.name)' has unsupported kind '\(relationship.kind)'."
            ))
        }

        if !Self.supportedDeleteRules.contains(relationship.deleteRule) {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(sourceEntity.swiftName)' relationship '\(relationship.name)' has unsupported delete rule '\(relationship.deleteRule)'."
            ))
        }

        guard let destination = entitiesBySwiftName[relationship.destination] else {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(sourceEntity.swiftName)' relationship '\(relationship.name)' references missing destination '\(relationship.destination)'."
            ))
            return
        }

        guard let inverse = destination.relationships.first(where: { $0.name == relationship.inverse }) else {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(sourceEntity.swiftName)' relationship '\(relationship.name)' references missing inverse '\(relationship.inverse)' on '\(destination.swiftName)'."
            ))
            return
        }

        if inverse.destination != sourceEntity.swiftName {
            issues.append(SchemaValidationIssue(
                message: "Entity '\(sourceEntity.swiftName)' relationship '\(relationship.name)' inverse '\(destination.swiftName).\(inverse.name)' points to '\(inverse.destination)' instead of '\(sourceEntity.swiftName)'."
            ))
        }
    }

    private func duplicateIssues(
        values: [String],
        message: (String) -> String
    ) -> [SchemaValidationIssue] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts
            .filter { $0.value > 1 }
            .keys
            .sorted()
            .map { SchemaValidationIssue(message: message($0)) }
    }

    private func storageAttributes(for entity: NormalizedEntity) -> [NormalizedAttribute] {
        entity.attributes + entity.embedded.flatMap { embedded in
            let presence = embedded.presenceStorageName.map { storageName in
                NormalizedAttribute(
                    swiftName: storageName,
                    storageName: storageName,
                    swiftType: "Bool",
                    storageType: "boolean",
                    optional: false
                )
            }
            return [presence].compactMap { $0 } + embedded.attributes
        }
    }

    private static let supportedStorageTypes: Set<String> = [
        "binary",
        "boolean",
        "date",
        "decimal",
        "double",
        "float",
        "integer16",
        "integer32",
        "integer64",
        "rawRepresentable",
        "string",
        "uri",
        "uuid",
    ]

    private static let supportedDeleteRules: Set<String> = [
        "cascade",
        "deny",
        "noAction",
        "nullify",
    ]
}

public struct SchemaValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    public let issues: [SchemaValidationIssue]

    public init(issues: [SchemaValidationIssue]) {
        self.issues = issues
    }

    public var description: String {
        issues.map(\.message).joined(separator: "\n")
    }
}

public struct SchemaValidationIssue: Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
