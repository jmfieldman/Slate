import Foundation

@attached(member, names: named(slateID), named(init), named(ManagedPropertyProviding), named(keypathToAttribute), named(keypathToRelationship), arbitrary)
@attached(extension, conformances: SlateObject, SlateKeypathAttributeProviding, SlateKeypathRelationshipProviding, Identifiable, Equatable, Hashable, names: named(id), named(==), named(hash(into:)))
public macro SlateEntity(
    name: String? = nil,
    storageName: String? = nil,
    relationships: [SlateRelationship] = []
) = #externalMacro(
    module: "SlateSchemaMacros",
    type: "SlateEntityMacro"
)

@attached(peer)
public macro SlateAttribute(
    storageName: String? = nil,
    default: Any? = nil,
    indexed: Bool = false,
    externalStorage: Bool = false,
    enumRawType: Any.Type? = nil
) = #externalMacro(
    module: "SlateSchemaMacros",
    type: "SlateAttributeMacro"
)

@attached(peer)
public macro SlateEmbedded() = #externalMacro(
    module: "SlateSchemaMacros",
    type: "SlateEmbeddedMacro"
)

/// Declares one or more fetch indexes for the enclosing `@SlateEntity` type.
///
/// Each `[\.foo, \.bar]` array argument is one index (composite when the
/// array has more than one key path). Use multiple `#Index` declarations to
/// vary the `order:` per index group. The macro itself expands to nothing —
/// the generator parses the source to harvest the metadata.
///
///     #Index<Author>([\.sortName], [\.nationality])
///     #Index<Library>([\.updatedAt], order: .descending)
@freestanding(declaration)
public macro Index<Root>(
    _ keyPaths: [PartialKeyPath<Root>]...,
    order: SlateIndexOrder = .ascending
) = #externalMacro(
    module: "SlateSchemaMacros",
    type: "SlateIndexMacro"
)

/// Declares one or more uniqueness constraints for the enclosing
/// `@SlateEntity` type. Composite constraints are expressed as a single
/// array with multiple key paths.
///
///     #Unique<Author>([\.authorId])
///     #Unique<Person>([\.givenName, \.familyName])
@freestanding(declaration)
public macro Unique<Root>(
    _ keyPaths: [PartialKeyPath<Root>]...
) = #externalMacro(
    module: "SlateSchemaMacros",
    type: "SlateUniqueMacro"
)

public enum SlateIndexOrder: Sendable {
    case ascending
    case descending
}

public struct SlateRelationship: Sendable {
    public let name: String
    public let destinationTypeName: String
    public let kind: SlateRelationshipKind
    public let inverse: String
    public let deleteRule: SlateDeleteRule
    public let ordered: Bool
    public let optional: Bool
    public let minCount: Int?
    public let maxCount: Int?

    public static func toOne(
        _ name: String,
        _ destination: Any.Type,
        inverse: String,
        deleteRule: SlateDeleteRule = .nullify,
        optional: Bool = true
    ) -> Self {
        Self(
            name: name,
            destinationTypeName: String(describing: destination),
            kind: .toOne,
            inverse: inverse,
            deleteRule: deleteRule,
            ordered: false,
            optional: optional,
            minCount: nil,
            maxCount: nil
        )
    }

    public static func toMany(
        _ name: String,
        _ destination: Any.Type,
        inverse: String,
        deleteRule: SlateDeleteRule = .nullify,
        ordered: Bool = false,
        minCount: Int? = nil,
        maxCount: Int? = nil
    ) -> Self {
        Self(
            name: name,
            destinationTypeName: String(describing: destination),
            kind: .toMany,
            inverse: inverse,
            deleteRule: deleteRule,
            ordered: ordered,
            optional: false,
            minCount: minCount,
            maxCount: maxCount
        )
    }

    /// String-typed destination overloads. The spec form uses
    /// `Destination.self`, but mutually-referenced `@SlateEntity` types
    /// trigger Swift's circular-macro-reference detector during
    /// expansion. Passing the destination as a string literal sidesteps
    /// the circular reference because Swift no longer needs to resolve
    /// the destination type when type-checking the macro arguments.
    public static func toOne(
        _ name: String,
        _ destinationTypeName: String,
        inverse: String,
        deleteRule: SlateDeleteRule = .nullify,
        optional: Bool = true
    ) -> Self {
        Self(
            name: name,
            destinationTypeName: destinationTypeName,
            kind: .toOne,
            inverse: inverse,
            deleteRule: deleteRule,
            ordered: false,
            optional: optional,
            minCount: nil,
            maxCount: nil
        )
    }

    public static func toMany(
        _ name: String,
        _ destinationTypeName: String,
        inverse: String,
        deleteRule: SlateDeleteRule = .nullify,
        ordered: Bool = false,
        minCount: Int? = nil,
        maxCount: Int? = nil
    ) -> Self {
        Self(
            name: name,
            destinationTypeName: destinationTypeName,
            kind: .toMany,
            inverse: inverse,
            deleteRule: deleteRule,
            ordered: ordered,
            optional: false,
            minCount: minCount,
            maxCount: maxCount
        )
    }
}
