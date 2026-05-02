import Foundation
import SwiftParser
import SwiftSyntax

public struct SchemaParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let issues: [SchemaParseIssue]

    public var description: String {
        issues.map(\.formatted).joined(separator: "\n")
    }
}

public struct SchemaSourceLocation: Sendable, Equatable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }

    public var description: String { "\(file):\(line):\(column)" }
}

public struct SchemaParseIssue: Sendable, Equatable {
    public let entity: String?
    public let property: String?
    public let message: String
    public let location: SchemaSourceLocation?

    public init(
        entity: String?,
        property: String?,
        message: String,
        location: SchemaSourceLocation? = nil
    ) {
        self.entity = entity
        self.property = property
        self.message = message
        self.location = location
    }

    /// Compiler-style "file:line:column: error: <message>" rendering.
    /// Falls back to bare message when no source location is available.
    public var formatted: String {
        if let location {
            return "\(location): error: \(message)"
        }
        return message
    }
}

public struct SwiftSchemaParser: Sendable {
    public init() {}

    public func parseFiles(
        at urls: [URL],
        schemaName: String,
        modelModule: String,
        runtimeModule: String
    ) throws -> NormalizedSchema {
        // First parse every file once - we'll walk each tree twice:
        //   pass 1) build a cross-file enum index so attributes can reference
        //           enums declared in sibling files (option A from the design
        //           review), and
        //   pass 2) extract entities, threading both the entity-local
        //           nested-enum table and the cross-file index into
        //           attribute normalization.
        var parsedFiles: [(url: URL, tree: SourceFileSyntax, converter: SourceLocationConverter)] = []
        for url in urls {
            let source = try String(contentsOf: url, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: url.path, tree: tree)
            parsedFiles.append((url: url, tree: tree, converter: converter))
        }

        let enumIndex = Self.buildCrossFileEnumIndex(from: parsedFiles)

        var allEntities: [NormalizedEntity] = []
        var allIssues: [SchemaParseIssue] = []
        for parsed in parsedFiles {
            let visitor = EntityVisitor(
                fileURL: parsed.url,
                sourceLocationConverter: parsed.converter,
                crossFileEnumIndex: enumIndex,
                viewMode: .sourceAccurate
            )
            visitor.walk(parsed.tree)
            allEntities.append(contentsOf: visitor.entities)
            allIssues.append(contentsOf: visitor.issues)
        }
        if !allIssues.isEmpty {
            throw SchemaParseError(issues: allIssues)
        }
        let entities = allEntities.sorted { $0.swiftName < $1.swiftName }

        let fingerprintInput = entities.map { entity in
            [
                entity.swiftName,
                entity.entityName,
                entity.mutableName,
                entity.attributes.map { "\($0.swiftName):\($0.storageName):\($0.swiftType)" }.joined(separator: ","),
                entity.embedded.map { embedded in
                    "\(embedded.swiftName):\(embedded.swiftType):\(embedded.attributes.map { "\($0.swiftName):\($0.storageName):\($0.swiftType)" }.joined(separator: ","))"
                }.joined(separator: ","),
                entity.relationships.map { "\($0.name):\($0.kind):\($0.destination):\($0.inverse)" }.joined(separator: ","),
                entity.indexes.map { "\($0.storageNames.joined(separator: "+")):\($0.order)" }.joined(separator: ","),
                entity.uniqueness.map { $0.storageNames.joined(separator: "+") }.joined(separator: ","),
            ].joined(separator: "|")
        }.joined(separator: ";")

        return NormalizedSchema(
            schemaName: schemaName,
            schemaFingerprint: "diagnostic:\(stableFingerprint(fingerprintInput))",
            modelModule: modelModule,
            runtimeModule: runtimeModule,
            entities: entities
        )
    }

    private func stableFingerprint(_ input: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    public func parseFile(at url: URL) throws -> [NormalizedEntity] {
        let result = try parseFileResult(at: url)
        if !result.issues.isEmpty {
            throw SchemaParseError(issues: result.issues)
        }
        return result.entities
    }

    private func parseFileResult(at url: URL) throws -> (entities: [NormalizedEntity], issues: [SchemaParseIssue]) {
        let source = try String(contentsOf: url, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: url.path, tree: tree)
        let enumIndex = Self.buildCrossFileEnumIndex(from: [(url: url, tree: tree, converter: converter)])
        let visitor = EntityVisitor(
            fileURL: url,
            sourceLocationConverter: converter,
            crossFileEnumIndex: enumIndex,
            viewMode: .sourceAccurate
        )
        visitor.walk(tree)
        return (visitor.entities, visitor.issues)
    }

    /// Walks every input tree's top-level statements and records each
    /// raw-value enum (`String`/`Int16`/`Int32`/`Int64`) by name. Names
    /// declared more than once are flagged as collisions; lookups for
    /// colliding names emit a parse issue suggesting an explicit
    /// `@SlateAttribute(enumRawType:)` override.
    fileprivate static func buildCrossFileEnumIndex(
        from parsedFiles: [(url: URL, tree: SourceFileSyntax, converter: SourceLocationConverter)]
    ) -> CrossFileEnumIndex {
        var occurrences: [String: Int] = [:]
        var entries: [String: String] = [:]

        for parsed in parsedFiles {
            for statement in parsed.tree.statements {
                guard let enumDecl = statement.item.as(EnumDeclSyntax.self),
                      let rawType = supportedRawType(of: enumDecl)
                else {
                    continue
                }
                let name = enumDecl.name.text
                let count = (occurrences[name] ?? 0) + 1
                occurrences[name] = count
                if count == 1 {
                    entries[name] = rawType
                } else {
                    // Once we see a collision the entry is no longer safe to
                    // resolve without a user-supplied disambiguator.
                    entries.removeValue(forKey: name)
                }
            }
        }

        let collisions = Set(occurrences.compactMap { $0.value > 1 ? $0.key : nil })
        return CrossFileEnumIndex(entries: entries, collisions: collisions)
    }

    private static func supportedRawType(of enumDecl: EnumDeclSyntax) -> String? {
        guard let inheritance = enumDecl.inheritanceClause else { return nil }
        for inherited in inheritance.inheritedTypes {
            let typeName = inherited.type.trimmedDescription
            if Self.crossFileSupportedRawTypes.contains(typeName) {
                return typeName
            }
        }
        return nil
    }

    private static let crossFileSupportedRawTypes: Set<String> = [
        "String",
        "Int16",
        "Int32",
        "Int64",
    ]
}

struct CrossFileEnumIndex: Sendable {
    let entries: [String: String]
    let collisions: Set<String>

    static let empty = CrossFileEnumIndex(entries: [:], collisions: [])

    func resolve(_ name: String) -> Resolution {
        if let rawType = entries[name] { return .resolved(rawType) }
        if collisions.contains(name) { return .collision }
        return .unknown
    }

    enum Resolution: Sendable {
        case resolved(String)
        case collision
        case unknown
    }
}

private final class EntityVisitor: SyntaxVisitor {
    private(set) var entities: [NormalizedEntity] = []
    private(set) var issues: [SchemaParseIssue] = []
    private let fileURL: URL
    private let converter: SourceLocationConverter
    private let crossFileEnumIndex: CrossFileEnumIndex

    init(
        fileURL: URL,
        sourceLocationConverter: SourceLocationConverter,
        crossFileEnumIndex: CrossFileEnumIndex,
        viewMode: SyntaxTreeViewMode
    ) {
        self.fileURL = fileURL
        self.converter = sourceLocationConverter
        self.crossFileEnumIndex = crossFileEnumIndex
        super.init(viewMode: viewMode)
    }

    /// Resolve a `SchemaSourceLocation` for the start of the given syntax
    /// node so that `SchemaParseIssue`s carry actionable file/line/column
    /// info.
    private func location(of node: some SyntaxProtocol) -> SchemaSourceLocation {
        let sourceLocation = node.startLocation(converter: converter)
        return SchemaSourceLocation(
            file: fileURL.path,
            line: sourceLocation.line,
            column: sourceLocation.column
        )
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(node, sourceKind: "struct")
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(node, sourceKind: "class")
        return .skipChildren
    }

    private func inspect(_ node: some DeclGroupSyntax, sourceKind: String) {
        guard let slateEntityAttribute = slateEntityAttribute(node.attributes),
              let name = declarationName(node)
        else {
            return
        }

        if !isPublicDeclaration(node) {
            issues.append(SchemaParseIssue(
                entity: name,
                property: nil,
                message: "@SlateEntity '\(name)' must be declared 'public'.",
                location: location(of: node)
            ))
        }

        if hasGenericParameters(node) {
            issues.append(SchemaParseIssue(
                entity: name,
                property: nil,
                message: "@SlateEntity '\(name)' cannot be generic; remove generic parameters.",
                location: location(of: node)
            ))
        }

        if let inheritedClass = inheritedClassName(node) {
            issues.append(SchemaParseIssue(
                entity: name,
                property: nil,
                message: "@SlateEntity '\(name)' inherits from class '\(inheritedClass)'; entity inheritance is not supported. Move shared behavior into protocols or extensions.",
                location: location(of: node)
            ))
        }

        for member in node.memberBlock.members {
            if let ifConfig = member.decl.as(IfConfigDeclSyntax.self) {
                if conditionalContainsPersistedDeclaration(ifConfig) {
                    issues.append(SchemaParseIssue(
                        entity: name,
                        property: nil,
                        message: "@SlateEntity '\(name)' has persisted properties inside a conditional compilation (#if) block; conditional persisted properties are not supported.",
                        location: location(of: ifConfig)
                    ))
                }
                continue
            }

            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }

            let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
            let isVar = variable.bindingSpecifier.tokenKind == .keyword(.var)
            let firstBinding = variable.bindings.first
            let isComputed = firstBinding?.accessorBlock != nil
            let propertyName = (firstBinding?.pattern.as(IdentifierPatternSyntax.self))?.identifier.text
            let hasSlateAnnotation = hasAttribute("SlateAttribute", in: variable.attributes) || hasAttribute("SlateEmbedded", in: variable.attributes)

            if isVar && !isComputed {
                issues.append(SchemaParseIssue(
                    entity: name,
                    property: propertyName,
                    message: "@SlateEntity '\(name)' has stored 'var' property '\(propertyName ?? "?")'; use 'let' instead.",
                    location: location(of: variable)
                ))
            }

            if isComputed && hasSlateAnnotation {
                issues.append(SchemaParseIssue(
                    entity: name,
                    property: propertyName,
                    message: "@SlateEntity '\(name)' has computed property '\(propertyName ?? "?")' annotated with @SlateAttribute or @SlateEmbedded; computed persisted properties are not supported.",
                    location: location(of: variable)
                ))
            }

            _ = isLet
        }
        let entityName = stringArgument("name", in: slateEntityAttribute) ?? name
        let mutableName = stringArgument("storageName", in: slateEntityAttribute) ?? "Database\(name)"

        let nestedStructs = nestedStructDeclarations(in: node)
        let nestedEnums = nestedEnumRawTypes(in: node)
        let persistedMembers = persistedMembers(in: node)

        let attributes = persistedMembers.compactMap { variable -> NormalizedAttribute? in
            guard !hasAttribute("SlateEmbedded", in: variable.attributes),
                  let property = property(in: variable)
            else {
                return nil
            }

            let typeName = property.typeName
            let optional = isOptional(typeName)
            let unwrapped = unwrappedTypeName(typeName)
            let leaf = leafTypeName(unwrapped)
            // Resolution priority for the enum metadata:
            //   1. Explicit `@SlateAttribute(enumRawType: String.self)` — most
            //      authoritative; lets users disambiguate or reference enums
            //      whose declaration is invisible to the parser.
            //   2. Entity-local nested enum (e.g., `enum Sex: String { ... }`
            //      declared inside the entity).
            //   3. Cross-file index of top-level raw-value enums in the
            //      generator's input. Collisions emit a parse issue and
            //      fall through.
            let enumKind: NormalizedEnumKind?
            if let overrideRaw = enumRawTypeOverride(in: variable.attributes, entityName: name, propertyName: property.name) {
                enumKind = NormalizedEnumKind(typeName: leaf, rawType: overrideRaw)
            } else if let rawType = nestedEnums[unwrapped] {
                enumKind = NormalizedEnumKind(typeName: unwrapped, rawType: rawType)
            } else {
                switch crossFileEnumIndex.resolve(leaf) {
                case .resolved(let rawType):
                    enumKind = NormalizedEnumKind(typeName: leaf, rawType: rawType)
                case .collision:
                    issues.append(SchemaParseIssue(
                        entity: name,
                        property: property.name,
                        message: "@SlateEntity '\(name)' attribute '\(property.name)' refers to enum '\(leaf)' which is declared in multiple input files; disambiguate with `@SlateAttribute(enumRawType: <RawType>.self)`.",
                        location: location(of: variable)
                    ))
                    enumKind = nil
                case .unknown:
                    enumKind = nil
                }
            }
            return NormalizedAttribute(
                swiftName: property.name,
                storageName: storageName(for: variable.attributes) ?? property.name,
                swiftType: typeName,
                storageType: enumKind.map { storageTypeForEnumRawType($0.rawType) }
                    ?? storageType(for: typeName),
                optional: optional,
                indexed: isIndexed(variable.attributes),
                defaultExpression: defaultExpression(for: variable.attributes),
                enumKind: enumKind
            )
        }

        let embedded = persistedMembers.compactMap { variable -> NormalizedEmbedded? in
            guard hasAttribute("SlateEmbedded", in: variable.attributes),
                  let rootProperty = property(in: variable)
            else {
                return nil
            }

            let embeddedType = unwrappedTypeName(rootProperty.typeName)
            guard let declaration = nestedStructs[embeddedType] else {
                issues.append(SchemaParseIssue(
                    entity: name,
                    property: rootProperty.name,
                    message: "@SlateEntity '\(name)' embedded property '\(rootProperty.name)' references external type '\(embeddedType)'; embedded structs must be nested inside the entity.",
                    location: location(of: variable)
                ))
                return nil
            }
            guard hasAttribute("SlateEmbedded", in: declaration.attributes) else {
                return nil
            }

            let flattenedAttributes = self.persistedMembers(in: declaration).compactMap { embeddedVariable -> NormalizedAttribute? in
                guard let embeddedProperty = self.property(in: embeddedVariable) else {
                    return nil
                }
                if hasAttribute("SlateEmbedded", in: embeddedVariable.attributes) {
                    issues.append(SchemaParseIssue(
                        entity: name,
                        property: "\(rootProperty.name).\(embeddedProperty.name)",
                        message: "@SlateEntity '\(name)' embedded struct '\(embeddedType)' field '\(embeddedProperty.name)' cannot be marked @SlateEmbedded; @SlateEmbedded is only supported on entity-level properties.",
                        location: location(of: embeddedVariable)
                    ))
                    return nil
                }
                let embeddedPropertyType = embeddedProperty.typeName
                let storage = storageName(for: embeddedVariable.attributes) ?? "\(rootProperty.name)_\(embeddedProperty.name)"
                return NormalizedAttribute(
                    swiftName: embeddedProperty.name,
                    storageName: storage,
                    swiftType: embeddedPropertyType,
                    storageType: storageType(for: embeddedPropertyType),
                    optional: true,
                    indexed: isIndexed(embeddedVariable.attributes)
                )
            }

            return NormalizedEmbedded(
                swiftName: rootProperty.name,
                swiftType: embeddedType,
                optional: isOptional(rootProperty.typeName),
                presenceStorageName: isOptional(rootProperty.typeName) ? "\(rootProperty.name)_has" : nil,
                attributes: flattenedAttributes
            )
        }
        let storageNameMap = storageNameMap(attributes: attributes, embedded: embedded)

        entities.append(
            NormalizedEntity(
                swiftName: name,
                entityName: entityName,
                mutableName: mutableName,
                sourceKind: sourceKind,
                attributes: attributes,
                embedded: embedded,
                relationships: relationships(in: slateEntityAttribute),
                indexes: indexes(in: node, storageNameMap: storageNameMap),
                uniqueness: uniqueness(in: node, storageNameMap: storageNameMap)
            )
        )
    }

    private struct Property {
        let name: String
        let typeName: String
    }

    private func conditionalContainsPersistedDeclaration(_ ifConfig: IfConfigDeclSyntax) -> Bool {
        for clause in ifConfig.clauses {
            guard let elements = clause.elements?.as(MemberBlockItemListSyntax.self) else {
                continue
            }
            for member in elements {
                if let nestedIfConfig = member.decl.as(IfConfigDeclSyntax.self) {
                    if conditionalContainsPersistedDeclaration(nestedIfConfig) {
                        return true
                    }
                    continue
                }
                guard let variable = member.decl.as(VariableDeclSyntax.self),
                      variable.bindingSpecifier.tokenKind == .keyword(.let),
                      variable.bindings.first?.accessorBlock == nil
                else {
                    continue
                }
                // Any stored let inside a conditional is treated as a persisted
                // property candidate - even without an explicit annotation,
                // because conditionally-present persisted properties cannot
                // be safely flattened into a single Core Data schema.
                return true
            }
        }
        return false
    }

    private func persistedMembers(in node: some DeclGroupSyntax) -> [VariableDeclSyntax] {
        node.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  identifier.identifier.text != "slateID",
                  binding.typeAnnotation?.type != nil
            else {
                return nil
            }
            return variable
        }
    }

    private func property(in variable: VariableDeclSyntax) -> Property? {
        guard variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type
        else {
            return nil
        }
        return Property(name: identifier.identifier.text, typeName: type.trimmedDescription)
    }

    private func nestedStructDeclarations(in node: some DeclGroupSyntax) -> [String: StructDeclSyntax] {
        Dictionary(uniqueKeysWithValues: node.memberBlock.members.compactMap { member in
            guard let declaration = member.decl.as(StructDeclSyntax.self) else {
                return nil
            }
            return (declaration.name.text, declaration)
        })
    }

    /// Returns a map of nested enum name → raw type for raw-value enums
    /// declared inline in the entity. Only enums whose first inherited
    /// type is one of the supported raw types (`String`, `Int16`,
    /// `Int32`, `Int64`) are surfaced; other enums are ignored.
    private func nestedEnumRawTypes(in node: some DeclGroupSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for member in node.memberBlock.members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  let inheritance = enumDecl.inheritanceClause
            else {
                continue
            }
            for inherited in inheritance.inheritedTypes {
                let typeName = inherited.type.trimmedDescription
                if Self.supportedEnumRawTypes.contains(typeName) {
                    map[enumDecl.name.text] = typeName
                    break
                }
            }
        }
        return map
    }

    private static let supportedEnumRawTypes: Set<String> = [
        "String",
        "Int16",
        "Int32",
        "Int64",
    ]

    private func storageTypeForEnumRawType(_ rawType: String) -> String {
        switch rawType {
        case "String": "string"
        case "Int16": "integer16"
        case "Int32": "integer32"
        case "Int64": "integer64"
        default: "string"
        }
    }

    private func slateEntityAttribute(_ attributes: AttributeListSyntax) -> AttributeSyntax? {
        attributes.compactMap { element in
            element.as(AttributeSyntax.self)
        }.first { attribute in
            attribute.attributeName.trimmedDescription == "SlateEntity"
        }
    }

    private func declarationName(_ node: some DeclGroupSyntax) -> String? {
        if let structDecl = node.as(StructDeclSyntax.self) {
            return structDecl.name.text
        }
        if let classDecl = node.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        }
        return nil
    }

    private func isPublicDeclaration(_ node: some DeclGroupSyntax) -> Bool {
        node.modifiers.contains { modifier in
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open):
                return true
            default:
                return false
            }
        }
    }

    private func hasGenericParameters(_ node: some DeclGroupSyntax) -> Bool {
        if let structDecl = node.as(StructDeclSyntax.self) {
            return structDecl.genericParameterClause != nil
        }
        if let classDecl = node.as(ClassDeclSyntax.self) {
            return classDecl.genericParameterClause != nil
        }
        return false
    }

    /// Returns the name of an apparent base class in the class entity's
    /// inheritance clause, or nil if all inherited types are recognised
    /// protocols. Heuristic: the first inherited type is a base class
    /// candidate. We allow well-known protocols like `Sendable`, `Equatable`,
    /// etc. Anything else flagged as a likely base class so users see a
    /// clear diagnostic instead of a confusing macro/Core Data failure.
    private func inheritedClassName(_ node: some DeclGroupSyntax) -> String? {
        guard let classDecl = node.as(ClassDeclSyntax.self),
              let inheritance = classDecl.inheritanceClause
        else {
            return nil
        }

        for inherited in inheritance.inheritedTypes {
            let typeName = inherited.type.trimmedDescription
            let bareName = typeName.split(separator: ".").last.map(String.init) ?? typeName
            if !Self.knownProtocolNames.contains(bareName) {
                return typeName
            }
        }
        return nil
    }

    private static let knownProtocolNames: Set<String> = [
        "Sendable",
        "Equatable",
        "Hashable",
        "Comparable",
        "Codable",
        "Encodable",
        "Decodable",
        "Identifiable",
        "CustomStringConvertible",
        "CustomDebugStringConvertible",
        "AnyObject",
        "NSObjectProtocol",
        "NSCopying",
        "Error",
        "LocalizedError",
        "AdditiveArithmetic",
        "Numeric",
    ]

    private func storageName(for attributes: AttributeListSyntax) -> String? {
        attributes.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "SlateAttribute"
            else {
                return nil
            }
            return stringArgument("storageName", in: attribute)
        }.first
    }

    /// Reduce a possibly-qualified Swift type name (`SharedTypes.Status`)
    /// to its leaf identifier (`Status`) so we can look it up in the
    /// cross-file enum index.
    private func leafTypeName(_ swiftType: String) -> String {
        swiftType.split(separator: ".").last.map(String.init) ?? swiftType
    }

    /// Read `@SlateAttribute(enumRawType: <T>.self)` if present and validate
    /// `<T>` is a supported raw type. Other expressions emit a parse issue
    /// so users get a clear message instead of silently degrading to a
    /// non-enum attribute.
    private func enumRawTypeOverride(
        in attributes: AttributeListSyntax,
        entityName: String,
        propertyName: String
    ) -> String? {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "SlateAttribute",
                  let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)
            else {
                continue
            }
            for argument in arguments where argument.label?.text == "enumRawType" {
                // Expecting `String.self` / `Int16.self` / ... — a member
                // access expression with `.self` as the leaf and the raw
                // type as the base.
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self",
                   let base = memberAccess.base
                {
                    let typeName = base.trimmedDescription
                    if Self.parserSupportedEnumRawTypes.contains(typeName) {
                        return typeName
                    }
                    issues.append(SchemaParseIssue(
                        entity: entityName,
                        property: propertyName,
                        message: "@SlateEntity '\(entityName)' attribute '\(propertyName)' has unsupported `enumRawType: \(typeName).self`; use one of String.self, Int16.self, Int32.self, or Int64.self.",
                        location: location(of: attribute)
                    ))
                    return nil
                }
                issues.append(SchemaParseIssue(
                    entity: entityName,
                    property: propertyName,
                    message: "@SlateEntity '\(entityName)' attribute '\(propertyName)' has invalid `enumRawType:` argument; use a metatype literal such as `String.self`.",
                    location: location(of: attribute)
                ))
                return nil
            }
        }
        return nil
    }

    private static let parserSupportedEnumRawTypes: Set<String> = [
        "String",
        "Int16",
        "Int32",
        "Int64",
    ]

    private func defaultExpression(for attributes: AttributeListSyntax) -> String? {
        attributes.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "SlateAttribute"
            else {
                return nil
            }
            return expressionArgument("default", in: attribute)
        }.first
    }

    private func hasAttribute(_ name: String, in attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
        }
    }

    private func stringArgument(_ label: String, in attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        for argument in arguments where argument.label?.text == label {
            return argument.expression.trimmedDescription
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private func expressionArgument(_ label: String, in attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        for argument in arguments where argument.label?.text == label {
            return argument.expression.trimmedDescription
        }
        return nil
    }

    private func relationships(in attribute: AttributeSyntax) -> [NormalizedRelationship] {
        guard let arrayExpr = arrayArgumentExpression("relationships", in: attribute) else {
            return []
        }

        return arrayExpr.elements.compactMap { element -> NormalizedRelationship? in
            guard let call = functionCall(element.expression),
                  call.name == "toOne" || call.name == "toMany",
                  let name = stringLiteralValue(positional(call.arguments, at: 0)),
                  let destination = typeReferenceValue(positional(call.arguments, at: 1)),
                  let inverse = stringLiteralValue(labeledArgument(call.arguments, label: "inverse"))
            else {
                return nil
            }

            return NormalizedRelationship(
                name: name,
                kind: call.name,
                destination: destination,
                inverse: inverse,
                deleteRule: memberAccessLeafName(labeledArgument(call.arguments, label: "deleteRule")) ?? "nullify",
                ordered: boolLiteralValue(labeledArgument(call.arguments, label: "ordered")) ?? false,
                optional: boolLiteralValue(labeledArgument(call.arguments, label: "optional")) ?? true,
                minCount: integerLiteralValue(labeledArgument(call.arguments, label: "minCount")),
                maxCount: integerLiteralValue(labeledArgument(call.arguments, label: "maxCount"))
            )
        }
    }

    /// Harvest `#Index<Root>([\.foo], [\.bar, \.baz], order: .descending)`
    /// declarations from inside the entity body. Each unlabeled array
    /// argument becomes one index; the `order:` label applies to every
    /// index in the call. The macro itself expands to nothing — this walk
    /// is the only place index metadata is captured.
    private func indexes(in node: some DeclGroupSyntax, storageNameMap: [String: String]) -> [NormalizedIndex] {
        var result: [NormalizedIndex] = []
        for invocation in macroInvocations(named: "Index", in: node) {
            let order = memberAccessLeafName(labeledArgument(invocation.arguments, label: "order")) ?? "ascending"
            for arrayExpr in keyPathArrayArguments(in: invocation.arguments) {
                let storageNames = keyPathStorageNames(in: arrayExpr, storageNameMap: storageNameMap)
                guard !storageNames.isEmpty else { continue }
                result.append(NormalizedIndex(storageNames: storageNames, order: order))
            }
        }
        return result
    }

    /// Harvest `#Unique<Root>([\.foo, \.bar])` declarations from inside
    /// the entity body. Composite uniqueness lives in a single array.
    private func uniqueness(in node: some DeclGroupSyntax, storageNameMap: [String: String]) -> [NormalizedUniqueness] {
        var result: [NormalizedUniqueness] = []
        for invocation in macroInvocations(named: "Unique", in: node) {
            for arrayExpr in keyPathArrayArguments(in: invocation.arguments) {
                let storageNames = keyPathStorageNames(in: arrayExpr, storageNameMap: storageNameMap)
                guard !storageNames.isEmpty else { continue }
                result.append(NormalizedUniqueness(storageNames: storageNames))
            }
        }
        return result
    }

    private struct MacroInvocation {
        let arguments: LabeledExprListSyntax
    }

    /// Walk the entity body for `#Name<...>(...)` freestanding macro
    /// expansions whose macro name matches.
    private func macroInvocations(named name: String, in node: some DeclGroupSyntax) -> [MacroInvocation] {
        node.memberBlock.members.compactMap { member in
            guard let macro = member.decl.as(MacroExpansionDeclSyntax.self),
                  macro.macroName.text == name
            else {
                return nil
            }
            return MacroInvocation(arguments: macro.arguments)
        }
    }

    /// Extract the unlabeled array-literal arguments of a macro call. Each
    /// `[\.foo]` / `[\.foo, \.bar]` group corresponds to one index or
    /// uniqueness constraint.
    private func keyPathArrayArguments(in args: LabeledExprListSyntax) -> [ArrayExprSyntax] {
        args.compactMap { argument in
            guard argument.label == nil,
                  let arrayExpr = argument.expression.as(ArrayExprSyntax.self)
            else {
                return nil
            }
            return arrayExpr
        }
    }

    // MARK: - Typed AST helpers

    private struct CallInfo {
        let name: String
        let arguments: LabeledExprListSyntax
    }

    /// Extract the array-literal expression for a labeled argument on the
    /// given attribute (e.g., `relationships: [ ... ]`).
    private func arrayArgumentExpression(_ label: String, in attribute: AttributeSyntax) -> ArrayExprSyntax? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        for argument in arguments where argument.label?.text == label {
            return argument.expression.as(ArrayExprSyntax.self)
        }
        return nil
    }

    /// Returns name + arguments for a function-call expression whose
    /// callee is a member-access (handles both `.toOne(...)` implicit-base
    /// and `SlateRelationship.toOne(...)` qualified forms).
    private func functionCall(_ expr: ExprSyntax) -> CallInfo? {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self)
        else {
            return nil
        }
        return CallInfo(
            name: memberAccess.declName.baseName.text,
            arguments: call.arguments
        )
    }

    private func positional(_ args: LabeledExprListSyntax, at index: Int) -> ExprSyntax? {
        let unlabeled = args.filter { $0.label == nil }
        guard index < unlabeled.count else { return nil }
        return unlabeled[unlabeled.index(unlabeled.startIndex, offsetBy: index)].expression
    }

    private func labeledArgument(_ args: LabeledExprListSyntax, label: String) -> ExprSyntax? {
        args.first { $0.label?.text == label }?.expression
    }

    /// Extract the body of a single-segment string literal (`"foo"`).
    /// Returns nil for interpolated or empty literals so callers can fall
    /// through to the next argument source.
    private func stringLiteralValue(_ expr: ExprSyntax?) -> String? {
        guard let expr,
              let stringLiteral = expr.as(StringLiteralExprSyntax.self),
              stringLiteral.segments.count == 1,
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self)
        else {
            return nil
        }
        return segment.content.text
    }

    /// Extract the type reference from either a `Foo.self` expression
    /// (the spec form) or a string literal (the macro-circular-reference
    /// escape hatch — see the relationship overload that accepts a
    /// `String` destination type name).
    private func typeReferenceValue(_ expr: ExprSyntax?) -> String? {
        guard let expr else { return nil }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "self",
           let base = memberAccess.base
        {
            return base.trimmedDescription
        }
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            return stringLiteralText(stringLiteral)
        }
        return nil
    }

    private func stringLiteralText(_ literal: StringLiteralExprSyntax) -> String? {
        var result = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else {
                return nil
            }
            result += plain.content.text
        }
        return result
    }

    private func boolLiteralValue(_ expr: ExprSyntax?) -> Bool? {
        guard let expr,
              let booleanLiteral = expr.as(BooleanLiteralExprSyntax.self)
        else {
            return nil
        }
        switch booleanLiteral.literal.tokenKind {
        case .keyword(.true): return true
        case .keyword(.false): return false
        default: return nil
        }
    }

    private func integerLiteralValue(_ expr: ExprSyntax?) -> Int? {
        guard let expr,
              let int = expr.as(IntegerLiteralExprSyntax.self)
        else {
            return nil
        }
        return Int(int.literal.text)
    }

    /// Returns the leaf member name of an expression like `.cascade` or
    /// `SlateDeleteRule.cascade`.
    private func memberAccessLeafName(_ expr: ExprSyntax?) -> String? {
        guard let expr,
              let memberAccess = expr.as(MemberAccessExprSyntax.self)
        else {
            return nil
        }
        return memberAccess.declName.baseName.text
    }

    /// Walk a key-path array literal (e.g., `[\.foo, \.bar]`) and resolve
    /// each element to its Core Data storage name via the supplied lookup
    /// map. Composite indexes/uniqueness constraints live in a single
    /// array and emit multiple storage names in declaration order.
    private func keyPathStorageNames(
        in arrayExpr: ArrayExprSyntax,
        storageNameMap: [String: String]
    ) -> [String] {
        var result: [String] = []
        for element in arrayExpr.elements {
            if let storage = keyPathStorageName(element.expression, storageNameMap: storageNameMap) {
                result.append(storage)
            }
        }
        return result
    }

    private func keyPathStorageName(
        _ expr: ExprSyntax,
        storageNameMap: [String: String]
    ) -> String? {
        guard let keyPath = expr.as(KeyPathExprSyntax.self) else { return nil }

        var segments: [String] = []
        for component in keyPath.components {
            if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                segments.append(property.declName.baseName.text)
            }
            // Skip optional-chain (?), subscript, and other component kinds
            // — only property segments are meaningful for storage lookup.
        }

        guard !segments.isEmpty else { return nil }
        let dotted = segments.joined(separator: ".")
        let underscored = segments.joined(separator: "_")
        return storageNameMap[dotted] ?? storageNameMap[underscored] ?? underscored
    }

    private func storageNameMap(attributes: [NormalizedAttribute], embedded: [NormalizedEmbedded]) -> [String: String] {
        var map: [String: String] = [:]
        for attribute in attributes {
            map[attribute.swiftName] = attribute.storageName
        }
        for embeddedValue in embedded {
            if let presenceStorageName = embeddedValue.presenceStorageName {
                map["\(embeddedValue.swiftName)_has"] = presenceStorageName
            }
            for attribute in embeddedValue.attributes {
                map["\(embeddedValue.swiftName).\(attribute.swiftName)"] = attribute.storageName
                map["\(embeddedValue.swiftName)_\(attribute.swiftName)"] = attribute.storageName
            }
        }
        return map
    }

    private func isIndexed(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "SlateAttribute",
                  let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)
            else {
                return false
            }
            return arguments.contains { argument in
                argument.label?.text == "indexed" && argument.expression.trimmedDescription == "true"
            }
        }
    }

    private func storageType(for swiftType: String) -> String {
        let unwrapped = unwrappedTypeName(swiftType)
        return switch unwrapped {
        case "String": "string"
        case "Bool": "boolean"
        case "Int", "Int64": "integer64"
        case "Int16": "integer16"
        case "Int32": "integer32"
        case "Float": "float"
        case "Double": "double"
        case "Decimal": "decimal"
        case "Date": "date"
        case "Data": "binary"
        case "UUID": "uuid"
        case "URL": "uri"
        default: "rawRepresentable"
        }
    }

    private func isOptional(_ swiftType: String) -> Bool {
        swiftType.hasSuffix("?")
    }

    private func unwrappedTypeName(_ swiftType: String) -> String {
        swiftType.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
    }
}
