import SwiftCompilerPlugin
import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct SlateSchemaPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SlateEntityMacro.self,
        SlateAttributeMacro.self,
        SlateEmbeddedMacro.self,
        SlateIndexMacro.self,
        SlateUniqueMacro.self,
    ]
}

public struct SlateAttributeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

public struct SlateEmbeddedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// `#Index<Root>([\.foo], [\.bar, \.baz])` — pure marker. Index metadata is
/// harvested by the offline generator from the source text; the macro
/// expands to nothing so the declaration leaves no runtime trace.
public struct SlateIndexMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// `#Unique<Root>([\.foo, \.bar])` — pure marker. See `SlateIndexMacro`.
public struct SlateUniqueMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

public struct SlateEntityMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        diagnoseMutableStoredProperties(in: declaration, context: context)
        diagnoseInvalidEntityShape(declaration: declaration, context: context)
        diagnoseInvalidPersistedDeclarations(in: declaration, context: context)
        // Re-order properties so direct attributes come first, then
        // embedded properties. This matches the order the generator
        // emits arguments to `Patient(...)` in the bridge file, so the
        // hand-rolled initializer call signature aligns with the
        // generator's hydration call.
        let allProperties = storedLetProperties(in: declaration)
        let embeddedNames = embeddedPropertyNames(in: declaration)
        let directAttributes = allProperties.filter { !embeddedNames.contains($0.name) }
        let embeddedProperties = allProperties.filter { embeddedNames.contains($0.name) }
        let properties = directAttributes + embeddedProperties
        let relationships = relationships(in: node)
        let embeddedPaths = embeddedPaths(in: declaration)
        var members: [DeclSyntax] = [
            "public let slateID: SlateID"
        ]

        members.append(contentsOf: relationships.map(makeRelationshipProperty))
        members.append(makeMemberwiseInitializer(properties: properties, relationships: relationships))
        members.append(makeProviderInitializer(properties: properties, relationships: relationships))
        members.append(makeProviderProtocol(properties: properties))
        members.append(makeKeypathMapping(
            typeName: declarationName(declaration),
            properties: properties,
            embeddedPaths: embeddedPaths
        ))
        members.append(makeRelationshipKeypathMapping(typeName: declarationName(declaration), relationships: relationships))

        return members
    }

    /// Names of stored properties annotated with `@SlateEmbedded`.
    private static func embeddedPropertyNames(in declaration: some DeclGroupSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  hasAttribute("SlateEmbedded", in: variable.attributes),
                  let binding = variable.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                continue
            }
            names.insert(pattern.identifier.text)
        }
        return names
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let allProperties = storedLetProperties(in: declaration)
        let embeddedNames = embeddedPropertyNames(in: declaration)
        let directAttributes = allProperties.filter { !embeddedNames.contains($0.name) }
        let embeddedProperties = allProperties.filter { embeddedNames.contains($0.name) }
        let valueProperties = directAttributes + embeddedProperties

        let equalityTerms = (["lhs.slateID == rhs.slateID"]
            + valueProperties.map { "lhs.\($0.name) == rhs.\($0.name)" })
            .joined(separator: "\n            && ")
        let hashCombines = (["hasher.combine(slateID)"]
            + valueProperties.map { "hasher.combine(\($0.name))" })
            .joined(separator: "\n        ")

        return [
            try ExtensionDeclSyntax("extension \(type.trimmed): SlateObject {}"),
            try ExtensionDeclSyntax("extension \(type.trimmed): SlateKeypathAttributeProviding {}"),
            try ExtensionDeclSyntax("extension \(type.trimmed): SlateKeypathRelationshipProviding {}"),
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): Identifiable {
                    public var id: SlateID {
                        slateID
                    }
                }
                """
            ),
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): Equatable {
                    public static func == (lhs: \(type.trimmed), rhs: \(type.trimmed)) -> Bool {
                        \(raw: equalityTerms)
                    }
                }
                """
            ),
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): Hashable {
                    public func hash(into hasher: inout Hasher) {
                        \(raw: hashCombines)
                    }
                }
                """
            ),
        ]
    }

    struct Property {
        let name: String
        let type: String
        let storageName: String
    }

    struct Relationship {
        let name: String
        let type: String
    }

    struct EmbeddedPath {
        let embeddedName: String
        let embeddedOptional: Bool
        let propertyName: String
        let storageName: String
    }

    static func embeddedPaths(in declaration: some DeclGroupSyntax) -> [EmbeddedPath] {
        let nestedStructs = nestedStructDeclarations(in: declaration)
        var paths: [EmbeddedPath] = []

        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  hasAttribute("SlateEmbedded", in: variable.attributes),
                  variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type
            else {
                continue
            }

            let typeName = type.trimmedDescription
            let isOptional = typeName.hasSuffix("?")
            let unwrapped = typeName.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
            let embeddedName = pattern.identifier.text

            guard let nestedDecl = nestedStructs[unwrapped],
                  hasAttribute("SlateEmbedded", in: nestedDecl.attributes)
            else {
                continue
            }

            for nestedMember in nestedDecl.memberBlock.members {
                guard let nestedVariable = nestedMember.decl.as(VariableDeclSyntax.self),
                      nestedVariable.bindingSpecifier.tokenKind == .keyword(.let),
                      nestedVariable.bindings.count == 1,
                      let nestedBinding = nestedVariable.bindings.first,
                      nestedBinding.accessorBlock == nil,
                      let nestedPattern = nestedBinding.pattern.as(IdentifierPatternSyntax.self),
                      nestedBinding.typeAnnotation?.type != nil
                else {
                    continue
                }

                let propertyName = nestedPattern.identifier.text
                let storage = storageName(for: nestedVariable.attributes) ?? "\(embeddedName)_\(propertyName)"

                paths.append(EmbeddedPath(
                    embeddedName: embeddedName,
                    embeddedOptional: isOptional,
                    propertyName: propertyName,
                    storageName: storage
                ))
            }
        }

        return paths
    }

    private static func nestedStructDeclarations(in declaration: some DeclGroupSyntax) -> [String: StructDeclSyntax] {
        Dictionary(uniqueKeysWithValues: declaration.memberBlock.members.compactMap { member in
            guard let nested = member.decl.as(StructDeclSyntax.self) else {
                return nil
            }
            return (nested.name.text, nested)
        })
    }

    private static func hasAttribute(_ name: String, in attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
        }
    }

    static func storedLetProperties(in declaration: some DeclGroupSyntax) -> [Property] {
        declaration.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  pattern.identifier.text != "slateID",
                  let type = binding.typeAnnotation?.type
            else {
                return nil
            }

            return Property(
                name: pattern.identifier.text,
                type: type.trimmedDescription,
                storageName: storageName(for: variable.attributes) ?? pattern.identifier.text
            )
        }
    }

    private static func storageName(for attributes: AttributeListSyntax) -> String? {
        attributes.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "SlateAttribute",
                  let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)
            else {
                return nil
            }

            for argument in arguments where argument.label?.text == "storageName" {
                return argument.expression.trimmedDescription
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            return nil
        }.first
    }

    private static func relationships(in attribute: AttributeSyntax) -> [Relationship] {
        guard let expression = expressionArgument("relationships", in: attribute) else {
            return []
        }

        return relationshipCalls(in: expression).compactMap { call in
            let kind: String
            if call.hasPrefix(".toOne") || call.hasPrefix("SlateRelationship.toOne") {
                kind = "toOne"
            } else if call.hasPrefix(".toMany") || call.hasPrefix("SlateRelationship.toMany") {
                kind = "toMany"
            } else {
                return nil
            }

            guard let name = firstQuotedString(in: call),
                  let destination = destinationType(in: call)
            else {
                return nil
            }

            let type = kind == "toOne" ? "\(destination)?" : "[\(destination)]?"
            return Relationship(name: name, type: type)
        }
    }

    private static func expressionArgument(_ label: String, in attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        for argument in arguments where argument.label?.text == label {
            return argument.expression.trimmedDescription
        }
        return nil
    }

    private static func relationshipCalls(in expression: String) -> [String] {
        var calls: [String] = []
        var searchStart = expression.startIndex

        while let range = expression[searchStart...].range(of: ".to") {
            var index = range.lowerBound
            var depth = 0
            var foundOpening = false

            while index < expression.endIndex {
                let character = expression[index]
                if character == "(" {
                    depth += 1
                    foundOpening = true
                } else if character == ")" {
                    depth -= 1
                    if foundOpening && depth == 0 {
                        let end = expression.index(after: index)
                        calls.append(String(expression[range.lowerBound..<end]))
                        searchStart = end
                        break
                    }
                }
                index = expression.index(after: index)
            }

            if index >= expression.endIndex {
                break
            }
        }

        return calls
    }

    private static func firstQuotedString(in text: String) -> String? {
        guard let first = text.firstIndex(of: "\""),
              let second = text[text.index(after: first)...].firstIndex(of: "\"")
        else {
            return nil
        }
        return String(text[text.index(after: first)..<second])
    }

    private static func destinationType(in text: String) -> String? {
        // Spec form: `.toOne("name", Destination.self, inverse: ...)`.
        if let selfRange = text.range(of: ".self") {
            let prefix = text[..<selfRange.lowerBound]
            if let comma = prefix.lastIndex(of: ",") {
                return prefix[text.index(after: comma)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Escape-hatch form (avoids Swift macro circular references):
        // `.toOne("name", "Destination", inverse: ...)`. Locate the
        // SECOND quoted string in the call.
        var searchStart = text.startIndex
        var quoted: [String] = []
        while let openQuote = text[searchStart...].firstIndex(of: "\"") {
            let afterOpen = text.index(after: openQuote)
            guard let closeQuote = text[afterOpen...].firstIndex(of: "\"") else {
                break
            }
            quoted.append(String(text[afterOpen..<closeQuote]))
            searchStart = text.index(after: closeQuote)
        }
        return quoted.count >= 2 ? quoted[1] : nil
    }

    private static func declarationName(_ declaration: some DeclGroupSyntax) -> String {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.name.text
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        }
        return "Self"
    }

    /// Diagnose entity-shape problems: a non-public declaration, a generic
    /// parameter list, or an inherited base class. The parser surfaces
    /// these too, but emitting them here gives users immediate compile-time
    /// feedback in the IDE without running the generator.
    private static func diagnoseInvalidEntityShape(
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) {
        // Visibility: every @SlateEntity must be public so the generated
        // persistence module (a separate target) can reference it.
        let modifiers = declarationModifiers(declaration)
        let isPublic = modifiers.contains(where: {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
        })
        if !isPublic {
            context.diagnose(Diagnostic(
                node: Syntax(declarationNameToken(declaration) ?? Syntax(declaration)),
                message: SlateMacroDiagnostic(
                    message: "@SlateEntity types must be declared 'public'",
                    diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "nonPublicEntity"),
                    severity: .error
                )
            ))
        }

        // Generics: the generator parses concrete schema types only; a
        // generic entity has no resolvable storage type for its fields.
        if let structDecl = declaration.as(StructDeclSyntax.self),
           structDecl.genericParameterClause != nil
        {
            context.diagnose(Diagnostic(
                node: Syntax(structDecl.genericParameterClause!),
                message: SlateMacroDiagnostic(
                    message: "@SlateEntity does not support generic types",
                    diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "genericEntity"),
                    severity: .error
                )
            ))
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self),
           classDecl.genericParameterClause != nil
        {
            context.diagnose(Diagnostic(
                node: Syntax(classDecl.genericParameterClause!),
                message: SlateMacroDiagnostic(
                    message: "@SlateEntity does not support generic types",
                    diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "genericEntity"),
                    severity: .error
                )
            ))
        }

        // Inheritance: classes may conform to protocols (Sendable, etc.)
        // but must not inherit from a non-protocol base class. We can't
        // resolve protocol vs class without type info, so we use a small
        // allowlist of well-known protocol names; any other inherited
        // type is flagged. Structs cannot inherit so they're skipped.
        if let classDecl = declaration.as(ClassDeclSyntax.self),
           let inheritance = classDecl.inheritanceClause
        {
            for entry in inheritance.inheritedTypes {
                let name = entry.type.trimmedDescription
                if Self.allowedClassConformances.contains(name) {
                    continue
                }
                context.diagnose(Diagnostic(
                    node: Syntax(entry.type),
                    message: SlateMacroDiagnostic(
                        message: "@SlateEntity classes may conform to protocols but must not inherit from a base class",
                        diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "inheritedClass"),
                        severity: .error
                    )
                ))
            }
        }
    }

    /// Diagnose persisted-declaration problems: a `@SlateAttribute` /
    /// `@SlateEmbedded` annotated computed property, or a persisted
    /// declaration nested under `#if`/`#elseif`/`#else`. The macro can
    /// see these locally even if the parser hasn't run yet.
    private static func diagnoseInvalidPersistedDeclarations(
        in declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) {
        for member in declaration.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self),
               isAnnotatedAsPersisted(attributes: variable.attributes),
               variable.bindings.contains(where: { $0.accessorBlock != nil })
            {
                context.diagnose(Diagnostic(
                    node: Syntax(variable),
                    message: SlateMacroDiagnostic(
                        message: "@SlateEntity persisted properties must be stored ('let'); computed properties cannot be persisted",
                        diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "computedPersistedProperty"),
                        severity: .error
                    )
                ))
            }

            if let ifConfig = member.decl.as(IfConfigDeclSyntax.self),
               ifConfigContainsPersistedDeclaration(ifConfig)
            {
                context.diagnose(Diagnostic(
                    node: Syntax(ifConfig),
                    message: SlateMacroDiagnostic(
                        message: "@SlateEntity persisted properties cannot be wrapped in conditional compilation (#if) blocks",
                        diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "conditionalPersistedProperty"),
                        severity: .error
                    )
                ))
            }
        }
    }

    private static func isAnnotatedAsPersisted(attributes: AttributeListSyntax) -> Bool {
        hasAttribute("SlateAttribute", in: attributes) || hasAttribute("SlateEmbedded", in: attributes)
    }

    private static func ifConfigContainsPersistedDeclaration(_ ifConfig: IfConfigDeclSyntax) -> Bool {
        for clause in ifConfig.clauses {
            guard let elements = clause.elements?.as(MemberBlockItemListSyntax.self) else {
                continue
            }
            for element in elements {
                if let variable = element.decl.as(VariableDeclSyntax.self),
                   variable.bindingSpecifier.tokenKind == .keyword(.let),
                   isAnnotatedAsPersisted(attributes: variable.attributes)
                {
                    return true
                }
                if let nested = element.decl.as(IfConfigDeclSyntax.self),
                   ifConfigContainsPersistedDeclaration(nested)
                {
                    return true
                }
            }
        }
        return false
    }

    private static func declarationModifiers(_ declaration: some DeclGroupSyntax) -> DeclModifierListSyntax {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.modifiers
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.modifiers
        }
        return DeclModifierListSyntax([])
    }

    private static func declarationNameToken(_ declaration: some DeclGroupSyntax) -> Syntax? {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return Syntax(structDecl.name)
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return Syntax(classDecl.name)
        }
        return nil
    }

    /// Allowlist of well-known protocols an `@SlateEntity` class may
    /// conform to. Any other inherited type is flagged as a class base.
    /// (Structs cannot have a base class so this only matters for
    /// `final class` entities.)
    private static let allowedClassConformances: Set<String> = [
        "Sendable",
        "Codable",
        "Decodable",
        "Encodable",
        "CustomStringConvertible",
        "CustomDebugStringConvertible",
    ]

    private static func diagnoseMutableStoredProperties(
        in declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) {
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.var),
                  variable.bindings.contains(where: { $0.accessorBlock == nil })
            else {
                continue
            }

            context.diagnose(Diagnostic(
                node: Syntax(variable),
                message: SlateMacroDiagnostic(
                    message: "@SlateEntity persisted properties must be declared with 'let'",
                    diagnosticID: MessageID(domain: "SlateSchemaMacros", id: "mutableStoredProperty"),
                    severity: .error
                )
            ))
        }
    }

    static func makeMemberwiseInitializer(
        properties: [Property],
        relationships: [Relationship] = [],
        includeSlateID: Bool = true
    ) -> DeclSyntax {
        let slateIDParameter = includeSlateID ? ["slateID: SlateID = NSManagedObjectID()"] : []
        let slateIDAssignment = includeSlateID ? ["self.slateID = slateID"] : []
        let relationshipParameters = relationships.map { "\($0.name): \($0.type) = nil" }
        let parameters = (slateIDParameter + properties.map { "\($0.name): \($0.type)" } + relationshipParameters).joined(separator: ",\n        ")
        let assignments = (slateIDAssignment + properties.map { "self.\($0.name) = \($0.name)" } + relationships.map { "self.\($0.name) = \($0.name)" }).joined(separator: "\n        ")
        return """
        public init(
            \(raw: parameters)
        ) {
            \(raw: assignments)
        }
        """
    }

    private static func makeRelationshipProperty(_ relationship: Relationship) -> DeclSyntax {
        """
        public let \(raw: relationship.name): \(raw: relationship.type)
        """
    }

    private static func makeProviderInitializer(properties: [Property], relationships: [Relationship]) -> DeclSyntax {
        let assignments = (
            ["self.slateID = managedObject.objectID"] +
            properties.map { "self.\($0.name) = managedObject.\($0.name)" } +
            relationships.map { "self.\($0.name) = nil" }
        ).joined(separator: "\n        ")
        return """
        public init(managedObject: some ManagedPropertyProviding) {
            \(raw: assignments)
        }
        """
    }

    private static func makeProviderProtocol(properties: [Property]) -> DeclSyntax {
        let requirements = (["var objectID: SlateID { get }"] + properties.map { "var \($0.name): \($0.type) { get }" }).joined(separator: "\n        ")
        return """
        public protocol ManagedPropertyProviding: AnyObject {
            \(raw: requirements)
        }
        """
    }

    private static func makeKeypathMapping(
        typeName: String,
        properties: [Property],
        embeddedPaths: [EmbeddedPath] = []
    ) -> DeclSyntax {
        let directCases = properties.map { #"case \\#(typeName).\#($0.name): "\#($0.storageName)""# }
        let embeddedCases = embeddedPaths.map { path -> String in
            let separator = path.embeddedOptional ? "?." : "."
            return #"case \\#(typeName).\#(path.embeddedName)\#(separator)\#(path.propertyName): "\#(path.storageName)""#
        }
        let cases = (directCases + embeddedCases).joined(separator: "\n        ")
        return """
        public static func keypathToAttribute(_ keyPath: PartialKeyPath<Self>) -> String {
            switch keyPath {
            \(raw: cases)
            default:
                fatalError("Unsupported Slate key path")
            }
        }
        """
    }

    private static func makeRelationshipKeypathMapping(typeName: String, relationships: [Relationship]) -> DeclSyntax {
        let cases = relationships.map { #"case \\#(typeName).\#($0.name): "\#($0.name)""# }.joined(separator: "\n        ")
        return """
        public static func keypathToRelationship(_ keyPath: PartialKeyPath<Self>) -> String {
            switch keyPath {
            \(raw: cases)
            default:
                fatalError("Unsupported Slate relationship key path")
            }
        }
        """
    }
}

private struct SlateMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity
}
