//
//  CoreDataGenerator.swift
//  Copyright © 2020 Jason Fieldman.
//

import Foundation

public let kStringArgVar: String = "%@"

public enum CoreDataSwiftGenerator {
    static var entityToSlateClass: [String: String] = [:]
    static var entityToCDClass: [String: String] = [:]

    /**
     Master entrance point to the file generation
     */
    public static func generateCoreData(
        contentsPath: String,
        nameTransform: String,
        fileTransform: String,
        castInt: Bool,
        internalModels: Bool,
        noRetroactive: Bool,
        publicParamInit: Bool,
        outputPath: String,
        entityPath: String,
        coreDataFileImports: String
    ) {
        let entities = ParseCoreData(contentsPath: contentsPath)
        var fileAccumulator = generateHeader(
            filename: fileTransform,
            imports: entities.map(\.imports)
        )

        // First pass create lookup dictionaries
        for entity in entities {
            let className: String = nameTransform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)

            entityToSlateClass[entity.entityName] = className
            entityToCDClass[entity.entityName] = entity.codeClass
        }

        for entity in entities {
            let className: String = nameTransform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)
            let filename: String = fileTransform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)

            // Start a new file accumulator if uses per-class file
            fileAccumulator = generateHeader(filename: filename, imports: [entity.imports])
            fileAccumulator += entityCode(entity: entity, castInt: castInt, internalModels: internalModels, publicParamInit: publicParamInit, className: className)

            // Write to file if necessary
            let filepath = (outputPath as NSString).appendingPathComponent("\(filename).swift")
            try! fileAccumulator.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
        }

        // Output Core Data entity files if necessary
        for entity in entities {
            let filename = "\(entity.codeClass).swift"
            let coreDataImportString = importHeaderString(entity: entity, imports: coreDataFileImports)
            let slateClassName: String = nameTransform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)
            let properties = generateCoreDataEntityProperties(entity: entity)
            let keypathCases = generateCoreDataKeypathCases(entity: entity)
            let relations = generateRelationships(entity: entity, className: slateClassName, internalModels: internalModels)
            let file = template_CD_Entity.replacingWithMap([
                "FILENAME": filename,
                "CDIMPORTS": coreDataImportString,
                "CDENTITYCLASS": entity.codeClass,
                "CDENTITYNAME": entity.entityName,
                "SLATECLASS": slateClassName,
                "PROPERTIES": properties,
                "RELATIONS": relations,
                "KEYPATHCASES": keypathCases,
                "CDPUBLICMODELS": internalModels ? "" : "public ",
                "RETROACTIVE": (noRetroactive || internalModels) ? "" : "@retroactive ",
            ])

            let filepath = (entityPath as NSString).appendingPathComponent(filename)
            try! file.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
        }
    }

    static func generateHeader(filename: String, imports: [[String]]) -> String {
        let importList = imports.reduce(Set<String>()) { partialResult, imports in
            partialResult.union(imports)
        }.sorted().map { "import \($0)" }.joined(separator: "\n")

        return template_CD_Swift_fileheader.replacingWithMap([
            "FILENAME": filename,
            "IMPORTS": importList.count == 0 ? "" : importList + "\n",
        ])
    }

    static func importHeaderString(entity: CoreDataEntity, imports: String) -> String {
        let importArray: [String] = imports.count > 0 ? imports.components(separatedBy: ",") : []
        let finalArray = Array(Set(importArray)).sorted().map { "import \($0.trimmingCharacters(in: .whitespaces))" }
        return (finalArray.count > 0) ? "\n\(finalArray.joined(separator: "\n"))" : ""
    }

    static var commandline: String {
        CommandLine.arguments.joined(separator: " ")
    }

    static func entityCode(
        entity: CoreDataEntity,
        castInt: Bool,
        internalModels: Bool,
        publicParamInit: Bool,
        className: String
    ) -> String {
        let classImpl = generateClassImpl(entity: entity, castInt: castInt, internalModels: internalModels, publicParamInit: publicParamInit, className: className)
        let provider = generatePropertyProviderProtocol(entity: entity, className: className, internalModels: internalModels)
        let equatable = generateEquatable(entity: entity, className: className)

        return "\(classImpl)\(provider)\(equatable)"
    }

    static func generateClassImpl(
        entity: CoreDataEntity,
        castInt: Bool,
        internalModels: Bool,
        publicParamInit: Bool,
        className: String
    ) -> String {
        var declarations = ""
        var assignments = ""
        var keypathAttrs = ""
        var attributeNames: [String] = []
        var relationshipNames: [String] = []
        var initParams: [String] = []
        var initParamAssignments: [String] = []

        var hasIntEnum = false
        var hasNSNumberEnum = false
        var hasStringEnum = false

        for attr in entity.attributes {
            attributeNames.append(attr.name)

            if !attr.type.supported {
                vprint(.error, "Unsupported attribute type [\(attr.type.rawValue)] in [\(entity.entityName)]")
                exit(12)
            }

            if let enumType = attr.enumType, let enumSource = attr.enumSource {
                // Handle special enum case
                declarations += template_CD_Swift_AttrDeclaration.replacingWithMap([
                    "ATTR": attr.name,
                    "TYPE": enumType,
                    "ACCESS": attr.access,
                    "OPTIONAL": attr.enumDefault == nil ? "?" : "",
                ])

                switch enumSource {
                case .Int: hasIntEnum = true
                case .NSNumber: hasNSNumberEnum = true
                case .String: hasStringEnum = true
                }
            } else {
                declarations += template_CD_Swift_AttrDeclaration.replacingWithMap([
                    "ATTR": attr.name,
                    "TYPE": attr.type.immType(castInt: castInt),
                    "ACCESS": attr.access,
                    "OPTIONAL": attr.optional ? "?" : "",
                ])
            }

            let useForce = !attr.optional && attr.type.codeGenForceOptional
            var str = useForce ? template_CD_Swift_AttrForceAssignment : template_CD_Swift_AttrAssignment
            var conv = ""
            var enumSrcStr = ""
            var defaultExp = ""
            if let enumSource = attr.enumSource {
                str = template_CD_Swift_AttrEnumAssignment
                enumSrcStr = enumSource.rawValue
                defaultExp = attr.enumDefault.map { " ?? .\($0)" } ?? ""
            } else if let sconv = attr.type.swiftValueConversion(castInt: castInt), !attr.useScalar {
                conv = ((attr.optional || useForce) ? "?" : "") + sconv
            } else if castInt, attr.type.isInt {
                str = (attr.optional && !attr.useScalar) ? template_CD_Swift_AttrIntOptAssignment : template_CD_Swift_AttrIntAssignment
            }
            assignments += str.replacingWithMap([
                "ATTR": attr.name,
                "TYPE": attr.type.immType(castInt: castInt),
                "CONV": conv,
                "ENUMSRC": enumSrcStr,
                "DEFAULT": defaultExp,
            ])

            // Slightly different rules for normal types vs. enums
            var initType = attr.type.immType(castInt: castInt)
            var initTypeOptional = attr.optional
            if let enumType = attr.enumType {
                initType = enumType
                initTypeOptional = attr.enumDefault == nil
            }

            initParams += ["\(attr.name): \(initType)\(initTypeOptional ? "?" : "")"]
            initParamAssignments += ["self.\(attr.name) = \(attr.name)"]
            keypathAttrs += template_CD_Swift_Keypath.replacingWithMap([
                "SLATECLASS": className,
                "ATTRPATH": attr.name,
                "ATTRSTR": attr.name,
            ])
        }

        for relationship in entity.relationships {
            relationshipNames.append(relationship.name)
        }

        let substruct = entity.substructs.reduce("") {
            $0 + generateSubstructImpl(substruct: $1, baseEntityClass: entity.codeClass, castInt: castInt)
        }

        for substruct in entity.substructs {
            let substructType = className + "." + substruct.structName
            declarations += template_CD_Swift_AttrDeclaration.replacingWithMap([
                "ATTR": substruct.varName,
                "TYPE": substructType,
                "ACCESS": substruct.access,
                "OPTIONAL": substruct.optional ? "?" : "",
            ])

            let str = substruct.optional ? template_CD_Swift_AttrAssignmentForOptSubstruct : template_CD_Swift_AttrAssignmentForSubstruct
            assignments += str.replacingWithMap([
                "ATTR": substruct.varName,
                "TYPE": substructType,
            ])

            for attr in substruct.attributes {
                attributeNames.append(substruct.varName + "_" + attr.name)
            }

            initParams += ["\(substruct.varName): \(substructType)\(substruct.optional ? "?" : "")"]
            initParamAssignments += ["self.\(substruct.varName) = \(substruct.varName)"]

            for subattr in substruct.attributes {
                keypathAttrs += template_CD_Swift_Keypath.replacingWithMap([
                    "SLATECLASS": className + "." + substruct.varName + (substruct.optional ? "?" : ""),
                    "ATTRPATH": subattr.name,
                    "ATTRSTR": "\(substruct.varName)_\(subattr.name)",
                ])
            }
        }

        let privateFunctionsConvertInt: String = hasIntEnum ? template_Conversion_Int : ""
        let privateFunctionsConvertNSNumber: String = hasNSNumberEnum ? template_Conversion_NSNumber : ""
        let privateFunctionsConvertString: String = hasStringEnum ? template_Conversion_String : ""
        let privateFunctions = privateFunctionsConvertInt + privateFunctionsConvertNSNumber + privateFunctionsConvertString

        return template_CD_Swift_SlateClassImpl.replacingWithMap([
            "OBJTYPE": entity.useStruct ? "struct" : "final class",
            "SLATECLASS": className,
            "COREDATACLASS": entity.codeClass,
            "ATTRASSIGNMENT": assignments,
            "ATTRDECLARATIONS": declarations,
            "ATTRNAMES": attributeNames.sorted(by: <).reduce("") { $0 + template_CD_Swift_AttrName.replacingWithMap(["ATTR": $1]) },
            "RELNAMES": relationshipNames.sorted(by: <).reduce("") { $0 + template_CD_Swift_RelName.replacingWithMap(["REL": $1]) },
            "KEYPATHCASES": keypathAttrs,
            "INITPARAMS": initParams.sorted(by: <).joined(separator: ",\n        "),
            "INITPARAMASSIGNMENTS": initParamAssignments.sorted(by: <).joined(separator: "\n        "),
            "SUBSTRUCTS": substruct,
            "PRIVATE": privateFunctions,
            "PUBLICMODEL": internalModels ? "" : "public ",
            "PUBLICPARAMINIT": publicParamInit ? template_CD_Swift_SlateClassImpl_ExplicitInitPublic : template_CD_Swift_SlateClassImpl_ExplicitInitInternal,
        ])
    }

    static func generateSubstructImpl(
        substruct: CoreDataSubstruct,
        baseEntityClass: String,
        castInt: Bool
    ) -> String {
        var declarations = ""
        var assignments = ""
        var initParams: [String] = []
        var initParamAssignments: [String] = []

        for attr in substruct.attributes {
            if !attr.type.supported {
                vprint(.error, "Unsupported attribute type [\(attr.type.rawValue)] in substruct [\(baseEntityClass) -> \(substruct.structName)_\(attr.name)]")
                exit(12)
            }

            let isOptionalForStruct: Bool = {
                if let optInStruct = attr.userdata["optInStruct"] {
                    return optInStruct == "true"
                }
                return attr.optional
            }()

            declarations += template_CD_Swift_SubstructAttrDeclaration.replacingWithMap([
                "ATTR": attr.name,
                "TYPE": attr.type.immType(castInt: castInt),
                "ACCESS": attr.access,
                "OPTIONAL": isOptionalForStruct ? "?" : "",
            ])

            let useForce = !isOptionalForStruct && (attr.type.codeGenForceOptional || attr.optional)
            var str = useForce ? template_CD_Swift_SubstructAttrForceAssignment : template_CD_Swift_SubstructAttrAssignment
            var conv = ""
            if let sconv = attr.type.swiftValueConversion(castInt: castInt), !attr.useScalar {
                conv = (attr.optional ? "?" : "") + sconv
            } else if castInt, attr.type.isInt {
                str = (attr.optional && !attr.useScalar) ? template_CD_Swift_SubstructAttrIntOptAssignment : template_CD_Swift_SubstructAttrIntAssignment
            }

            let def: String = attr.userdata["default"] ?? ""
            if useForce, def.isEmpty {
                print("substruct property \(baseEntityClass).\(substruct.varName + "_" + attr.name) is forced non-optional but does not have a default userInfo key")
            }

            assignments += str.replacingWithMap([
                "ATTR": attr.name,
                "STRNAME": substruct.varName,
                "TYPE": attr.type.immType(castInt: castInt),
                "CONV": conv,
                "DEF": def,
            ])

            initParams += ["\(attr.name): \(attr.type.immType(castInt: castInt))\(isOptionalForStruct ? "?" : "")"]
            initParamAssignments += ["self.\(attr.name) = \(attr.name)"]
        }

        return template_CD_Swift_SlateSubstructImpl.replacingWithMap([
            "SLATESUBSTRUCT": substruct.structName,
            "COREDATACLASS": baseEntityClass,
            "ATTRASSIGNMENT": assignments,
            "ATTRDECLARATIONS": declarations,
            "INITPARAMS": initParams.sorted(by: <).joined(separator: ",\n            "),
            "INITPARAMASSIGNMENTS": initParamAssignments.sorted(by: <).joined(separator: "\n            "),
        ])
    }

    static func generateRelationships(entity: CoreDataEntity, className: String, internalModels: Bool) -> String {
        var relationships = ""
        for relationship in entity.relationships {
            if relationship.toMany {
                relationships += template_CD_Swift_SlateRelationshipToMany.replacingWithMap([
                    "RELATIONSHIPNAME": relationship.name,
                    "SET": relationship.ordered ? "?.set" : " as? Set<AnyHashable>",
                    "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
                    "COREDATACLASS": entity.codeClass,
                ])
            } else {
                relationships += template_CD_Swift_SlateRelationshipToOne.replacingWithMap([
                    "RELATIONSHIPNAME": relationship.name,
                    "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
                    "COREDATACLASS": entity.codeClass,
                    "OPTIONAL": relationship.optional ? "?" : "",
                    "NONOPTIONAL": relationship.optional ? "" : "!",
                ])
            }
        }

        return template_CD_Swift_SlateRelationshipResolver.replacingWithMap([
            "OBJQUAL": entity.useStruct ? " == " : ": ",
            "SLATECLASS": className,
            "RELATIONSHIPS": relationships,
            "PUBLIC": internalModels ? "" : "public ",
        ])
    }

    static func generateEquatable(entity: CoreDataEntity, className: String) -> String {
        var attrs = ""
        for attr in entity.attributes {
            // No support for transformable right now?
            if attr.type == .transformable {
                return ""
            }

            attrs += " &&\n               (lhs.\(attr.name) == rhs.\(attr.name))"
        }

        for substruct in entity.substructs {
            attrs += " &&\n               (lhs.\(substruct.varName) == rhs.\(substruct.varName))"
        }

        return template_CD_Swift_SlateEquatable.replacingWithMap([
            "SLATECLASS": className,
            "ATTRS": attrs,
        ])
    }

    static func generatePropertyProviderProtocol(entity: CoreDataEntity, className: String, internalModels: Bool) -> String {
        template_CD_Property_Provider_Protocol.replacingWithMap([
            "SLATECLASS": className,
            "PROPERTIES": generateCoreDataPropertyProviderAttributes(entity: entity),
            "PUBLIC": internalModels ? "" : "public ",
        ])
    }

    // ----- Core Data Entities -----

    static func generateCoreDataKeypathCases(entity: CoreDataEntity) -> String {
        var keypathCases = ""

        for attribute in entity.attributes {
            keypathCases += template_CD_Entity_Keypath.replacingWithMap([
                "COREDATACLASS": entity.codeClass,
                "ATTRNAME": attribute.name,
            ])
        }

        for substruct in entity.substructs {
            for attribute in substruct.attributes {
                keypathCases += template_CD_Entity_Keypath.replacingWithMap([
                    "COREDATACLASS": entity.codeClass,
                    "ATTRNAME": substruct.varName + "_" + attribute.name,
                ])
            }
        }

        return keypathCases
    }

    static func generateCoreDataEntityProperties(entity: CoreDataEntity) -> String {
        var properties = ""
        for attribute in entity.attributes {
            properties += template_CD_Entity_Property.replacingWithMap([
                "VARNAME": attribute.name,
                "OPTIONAL": ((attribute.optional || attribute.type.codeGenForceOptional) && !attribute.useScalar) ? "?" : "",
                "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
            ])
        }
        for substruct in entity.substructs {
            properties += "\n"

            if substruct.optional {
                properties += template_CD_Entity_Property.replacingWithMap([
                    "VARNAME": substruct.varName + "_has",
                    "OPTIONAL": "",
                    "TYPE": "Bool",
                ])
            }

            for attribute in substruct.attributes {
                properties += template_CD_Entity_Property.replacingWithMap([
                    "VARNAME": substruct.varName + "_" + attribute.name,
                    "OPTIONAL": (attribute.optional && !attribute.useScalar) ? "?" : "",
                    "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
                ])
            }
        }
        for relationship in entity.relationships {
            properties += "\n"

            var type = "NSSet"
            if relationship.ordered { type = "NSOrderedSet" }
            if !relationship.toMany {
                type = entityToCDClass[relationship.destinationEntityName] ?? "---"
            }

            properties += template_CD_Entity_Property.replacingWithMap([
                "VARNAME": relationship.name,
                "OPTIONAL": (relationship.optional || relationship.toMany) ? "?" : "",
                "TYPE": type,
            ])
        }
        return properties
    }

    static func generateCoreDataPropertyProviderAttributes(entity: CoreDataEntity) -> String {
        var properties = ""
        for attribute in entity.attributes {
            properties += template_CD_Property_Provider_Attr.replacingWithMap([
                "VARNAME": attribute.name,
                "OPTIONAL": ((attribute.optional || attribute.type.codeGenForceOptional) && !attribute.useScalar) ? "?" : "",
                "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
            ])
        }
        for substruct in entity.substructs {
            properties += "\n"

            if substruct.optional {
                properties += template_CD_Property_Provider_Attr.replacingWithMap([
                    "VARNAME": substruct.varName + "_has",
                    "OPTIONAL": "",
                    "TYPE": "Bool",
                ])
            }

            for attribute in substruct.attributes {
                properties += template_CD_Property_Provider_Attr.replacingWithMap([
                    "VARNAME": substruct.varName + "_" + attribute.name,
                    "OPTIONAL": (attribute.optional && !attribute.useScalar) ? "?" : "",
                    "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
                ])
            }
        }
        return properties
    }
}
