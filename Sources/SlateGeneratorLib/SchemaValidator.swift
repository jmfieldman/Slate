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

        // Uniform-or-error: every entity in a schema must agree on `@SlateEntity(cloudKit:)`.
        // The issue fires only when both groups are non-empty; an all-CloudKit, all-local,
        // or empty schema produces no issue.
        let cloudKitNames = schema.entities.filter(\.cloudKit).map(\.swiftName).sorted()
        let nonCloudKitNames = schema.entities.filter { !$0.cloudKit }.map(\.swiftName).sorted()
        if !cloudKitNames.isEmpty, !nonCloudKitNames.isEmpty {
            let cloudKitList = cloudKitNames.map { "'\($0)'" }.joined(separator: ", ")
            let nonCloudKitList = nonCloudKitNames.map { "'\($0)'" }.joined(separator: ", ")
            issues.append(SchemaValidationIssue(
                message: "All entities in a schema must agree on '@SlateEntity(cloudKit:)'. "
                    + "CloudKit entities: \(cloudKitList); non-CloudKit entities: \(nonCloudKitList). "
                    + "Set the same 'cloudKit:' value on every entity in this schema."
            ))
        }

        // CloudKit-subset model rules. The uniform-or-error check above guarantees
        // a CloudKit schema is uniform, so a single `schema.cloudKit` test gates the
        // whole block — no per-entity re-checking. Issues aggregate into the same
        // `issues` and throw together below; no early throw.
        if schema.cloudKit {
            validateCloudKitSubset(schema, issues: &issues)
        }

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
            // External binary storage is meaningful only for `Data` attributes
            // (storage type `binary`). This guard applies to every schema, not
            // just CloudKit ones.
            if attribute.externalStorage, attribute.storageType != "binary" {
                issues.append(SchemaValidationIssue(
                    message: "Entity '\(entity.swiftName)' attribute '\(attribute.swiftName)' sets 'externalStorage: true' but its storage type is '\(attribute.storageType)', not binary; external storage applies only to 'Data' attributes. Remove 'externalStorage: true' or change '\(attribute.swiftName)' to 'Data'."
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

    /// Enforces CloudKit's non-negotiable model subset for a CloudKit schema.
    /// Called only when `schema.cloudKit`. Every violation is appended to `issues`
    /// (no early throw), so a single generation run reports every offending
    /// construct at once. The four rules:
    ///   - every attribute must be optional or carry a default (no silent zero-fill);
    ///   - no relationship may be ordered (model an explicit sort-key attribute);
    ///   - no relationship may use the `deny` delete rule (NSPCKC-unsupported);
    ///   - no entity may declare a `#Unique` constraint.
    private func validateCloudKitSubset(
        _ schema: NormalizedSchema,
        issues: inout [SchemaValidationIssue]
    ) {
        for entity in schema.entities {
            // Optional-or-default, evaluated over `storageAttributes(for:)` so the
            // synthesized `*_has` presence boolean (which `storageAttributes(for:)`
            // defaults to `false` in CloudKit mode) and `optional: true` embedded value
            // fields pass; only top-level authored non-optional-no-default attributes
            // (enums included) are flagged.
            for attribute in storageAttributes(for: entity) where !attribute.optional && attribute.defaultExpression == nil {
                issues.append(SchemaValidationIssue(
                    message: "Entity '\(entity.swiftName)' attribute '\(attribute.swiftName)' is non-optional with no default; CloudKit requires every attribute to be optional or carry a default. Add '@SlateAttribute(default:)' or make '\(attribute.swiftName)' optional."
                ))
            }

            for relationship in entity.relationships {
                if relationship.ordered {
                    issues.append(SchemaValidationIssue(
                        message: "Entity '\(entity.swiftName)' relationship '\(relationship.name)' is ordered; CloudKit does not support ordered relationships. Remove 'ordered: true' and model an explicit sort-key attribute."
                    ))
                }
                if relationship.deleteRule == "deny" {
                    issues.append(SchemaValidationIssue(
                        message: "Entity '\(entity.swiftName)' relationship '\(relationship.name)' uses the 'deny' delete rule, which CloudKit does not support. Use 'nullify', 'cascade', or 'noAction', or model a soft-delete flag (e.g. 'isTrashed') instead."
                    ))
                }
            }

            if !entity.uniqueness.isEmpty {
                issues.append(SchemaValidationIssue(
                    message: "Entity '\(entity.swiftName)' declares a '#Unique' constraint, which CloudKit does not support. Remove it; 'upsert' then fails at runtime via the existing uniqueness check while 'firstOrCreate' still works."
                ))
            }
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
                    optional: false,
                    defaultExpression: entity.cloudKit ? "false" : nil
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
