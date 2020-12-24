//
//  CoreDataGenerator.swift
//  slate
//
//  Created by Jason Fieldman on 5/29/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation

class CoreDataSwiftGenerator {
  static var entityToSlateClass: [String: String] = [:]
  static var entityToCDClass: [String: String] = [:]

  /**
   Master entrance point to the file generation
   */
  static func generateCoreData(
    entities: [CoreDataEntity],
    useStruct: Bool,
    nameTransform: String,
    fileTransform: String,
    castInt: Bool,
    outputPath: String,
    entityPath: String,
    imports: String
  ) {
    let filePerClass: Bool = fileTransform.contains(kStringArgVar)
    var fileAccumulator = generateHeader(filename: fileTransform, imports: imports)

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
      if filePerClass {
        fileAccumulator = generateHeader(filename: filename, imports: imports)
      }

      fileAccumulator += entityCode(entity: entity, useStruct: useStruct, castInt: castInt, className: className)

      // Write to file if necessary
      if filePerClass {
        let filepath = (outputPath as NSString).appendingPathComponent("\(filename).swift")
        try! fileAccumulator.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
      }
    }

    // Output Core Data entity files if necessary
    if entityPath.count > 0 {
      for entity in entities {
        let filename = "\(entity.codeClass).swift"
        let properties = generateCoreDataEntityProperties(entity: entity)
        let file = template_CD_Entity.replacingWithMap(
          [
            "FILENAME": filename,
            "CDENTITYCLASS": entity.codeClass,
            "CDENTITYNAME": entity.entityName,
            "PROPERTIES": properties,
          ]
        )

        let filepath = (entityPath as NSString).appendingPathComponent(filename)
        try! file.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
      }
    }

    // Output single file if necessary
    if !filePerClass {
      let filepath = (outputPath as NSString).appendingPathComponent("\(fileTransform).swift")
      try! fileAccumulator.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
    }
  }

  static func generateHeader(filename: String, imports: String) -> String {
    template_CD_Swift_fileheader.replacingWithMap(
      [
        "FILENAME": filename,
        "EXTRAIMPORT": (imports != "") ? "\n\(imports)" : "",
      ]
    )
  }

  static var commandline: String {
    CommandLine.arguments.joined(separator: " ")
  }

  static func entityCode(
    entity: CoreDataEntity,
    useStruct: Bool,
    castInt: Bool,
    className: String
  ) -> String {
    let convertible = template_CD_Swift_SlateObjectConvertible.replacingWithMap(
      [
        "COREDATACLASS": entity.codeClass,
        "SLATECLASS": className,
      ]
    )

    let moExtension = template_CD_Swift_ManagedObjectExtension.replacingWithMap(
      [
        "COREDATACLASS": entity.codeClass,
        "COREDATAENTITYNAME": entity.entityName,
      ]
    )

    let classImpl = generateClassImpl(entity: entity, useStruct: useStruct, castInt: castInt, className: className)
    let relations = generateRelationships(entity: entity, useStruct: useStruct, className: className)
    let equatable = generateEquatable(entity: entity, className: className)

    return "\(convertible)\(moExtension)\(classImpl)\(relations)\(equatable)"
  }

  static func generateClassImpl(
    entity: CoreDataEntity,
    useStruct: Bool,
    castInt: Bool,
    className: String
  ) -> String {
    var declarations: String = ""
    var assignments: String = ""
    var attributeNames: [String] = []
    var relationshipNames: [String] = []
    var initParams: [String] = []
    var initParamAssignments: [String] = []

    for attr in entity.attributes {
      attributeNames.append(attr.name)

      declarations += template_CD_Swift_AttrDeclaration.replacingWithMap(
        [
          "ATTR": attr.name,
          "TYPE": attr.type.immType(castInt: castInt),
          "ACCESS": attr.access,
          "OPTIONAL": attr.optional ? "?" : "",
        ])

      let amConvertingOptToScalar = !attr.optional && !attr.useScalar && attr.type.needsOptConvIfNotScalar
      let useForce = (!attr.optional && attr.type.codeGenForceOptional) || amConvertingOptToScalar
      let str = useForce ? template_CD_Swift_AttrForceAssignment : template_CD_Swift_AttrAssignment
      var conv = ""
      if let sconv = attr.type.swiftValueConversion(castInt: castInt), !attr.useScalar {
        conv = ((attr.optional || useForce) ? "?" : "") + sconv
      } else if castInt, attr.type.isInt {
        conv = ((attr.optional && !attr.useScalar) ? "?" : "") + ".slate_asInt"
      }
      assignments += str.replacingWithMap(
        [
          "ATTR": attr.name,
          "TYPE": attr.type.immType(castInt: castInt),
          "CONV": conv,
        ])

      initParams += ["\(attr.name): \(attr.type.immType(castInt: castInt))\(attr.optional ? "?" : "")"]
      initParamAssignments += ["self.\(attr.name) = \(attr.name)"]
    }

    for relationship in entity.relationships {
      relationshipNames.append(relationship.name)
    }

    let substruct = entity.substructs.reduce("") {
      $0 + generateSubstructImpl(substruct: $1, baseEntityClass: entity.codeClass, castInt: castInt)
    }

    for substruct in entity.substructs {
      let substructType = className + "." + substruct.structName
      declarations += template_CD_Swift_AttrDeclaration.replacingWithMap(
        [
          "ATTR": substruct.varName,
          "TYPE": substructType,
          "ACCESS": substruct.access,
          "OPTIONAL": substruct.optional ? "?" : "",
        ])

      let str = substruct.optional ? template_CD_Swift_AttrAssignmentForOptSubstruct : template_CD_Swift_AttrAssignmentForSubstruct
      assignments += str.replacingWithMap(
        [
          "ATTR": substruct.varName,
          "TYPE": substructType,
        ]
      )

      for attr in substruct.attributes {
        attributeNames.append(substruct.varName + "_" + attr.name)
      }

      initParams += ["\(substruct.varName): \(substructType)\(substruct.optional ? "?" : "")"]
      initParamAssignments += ["self.\(substruct.varName) = \(substruct.varName)"]
    }

    return template_CD_Swift_SlateClassImpl.replacingWithMap(
      [
        "OBJTYPE": useStruct ? "struct" : "final class",
        "SLATECLASS": className,
        "COREDATACLASS": entity.codeClass,
        "ATTRASSIGNMENT": assignments,
        "ATTRDECLARATIONS": declarations,
        "ATTRNAMES": attributeNames.sorted(by: <).reduce("") { $0 + template_CD_Swift_AttrName.replacingWithMap(["ATTR": $1]) },
        "RELNAMES": relationshipNames.sorted(by: <).reduce("") { $0 + template_CD_Swift_RelName.replacingWithMap(["REL": $1]) },
        "INITPARAMS": initParams.sorted(by: <).joined(separator: ",\n        "),
        "INITPARAMASSIGNMENTS": initParamAssignments.sorted(by: <).joined(separator: "\n        "),
        "SUBSTRUCTS": substruct,
      ]
    )
  }

  static func generateSubstructImpl(
    substruct: CoreDataSubstruct,
    baseEntityClass: String,
    castInt: Bool
  ) -> String {
    var declarations: String = ""
    var assignments: String = ""
    var initParams: [String] = []
    var initParamAssignments: [String] = []

    for attr in substruct.attributes {
      let isOptionalForStruct: Bool = {
        if let optInStruct = attr.userdata["optInStruct"] {
          return optInStruct == "true"
        }
        return attr.optional
      }()

      declarations += template_CD_Swift_SubstructAttrDeclaration.replacingWithMap(
        [
          "ATTR": attr.name,
          "TYPE": attr.type.immType(castInt: castInt),
          "ACCESS": attr.access,
          "OPTIONAL": isOptionalForStruct ? "?" : "",
        ])

      let useForce = !isOptionalForStruct && (attr.type.codeGenForceOptional || attr.optional)
      let str = useForce ? template_CD_Swift_SubstructAttrForceAssignment : template_CD_Swift_SubstructAttrAssignment
      var conv = ""
      if let sconv = attr.type.swiftValueConversion(castInt: castInt), !attr.useScalar {
        conv = (attr.optional ? "?" : "") + sconv
      } else if castInt, attr.type.isInt {
        conv = ((attr.optional && !attr.useScalar) ? "?" : "") + ".slate_asInt"
      }

      let def: String = attr.userdata["default"] ?? ""
      if useForce, def.isEmpty {
        print("substruct property \(baseEntityClass).\(substruct.varName + "_" + attr.name) is forced non-optional but does not have a default userInfo key")
      }

      assignments += str.replacingWithMap(
        [
          "ATTR": attr.name,
          "STRNAME": substruct.varName,
          "TYPE": attr.type.immType(castInt: castInt),
          "CONV": conv,
          "DEF": def,
        ])

      initParams += ["\(attr.name): \(attr.type.immType(castInt: castInt))\(attr.optional ? "?" : "")"]
      initParamAssignments += ["self.\(attr.name) = \(attr.name)"]
    }

    return template_CD_Swift_SlateSubstructImpl.replacingWithMap(
      [
        "SLATESUBSTRUCT": substruct.structName,
        "COREDATACLASS": baseEntityClass,
        "ATTRASSIGNMENT": assignments,
        "ATTRDECLARATIONS": declarations,
        "INITPARAMS": initParams.sorted(by: <).joined(separator: ",\n            "),
        "INITPARAMASSIGNMENTS": initParamAssignments.sorted(by: <).joined(separator: "\n            "),
      ]
    )
  }

  static func generateRelationships(entity: CoreDataEntity, useStruct: Bool, className: String) -> String {
    var relationships: String = ""
    for relationship in entity.relationships {
      if relationship.toMany {
        relationships += template_CD_Swift_SlateRelationshipToMany.replacingWithMap(
          [
            "RELATIONSHIPNAME": relationship.name,
            "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
            "COREDATACLASS": entity.codeClass,
          ]
        )
      } else {
        relationships += template_CD_Swift_SlateRelationshipToOne.replacingWithMap(
          [
            "RELATIONSHIPNAME": relationship.name,
            "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
            "COREDATACLASS": entity.codeClass,
            "OPTIONAL": relationship.optional ? "?" : "",
            "NONOPTIONAL": relationship.optional ? "" : "!",
          ]
        )
      }
    }

    return template_CD_Swift_SlateRelationshipResolver.replacingWithMap(
      [
        "OBJQUAL": useStruct ? " == " : ": ",
        "SLATECLASS": className,
        "RELATIONSHIPS": relationships,
      ]
    )
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

    return template_CD_Swift_SlateEquatable.replacingWithMap(
      [
        "SLATECLASS": className,
        "ATTRS": attrs,
      ]
    )
  }

  // ----- Core Data Entities -----

  static func generateCoreDataEntityProperties(entity: CoreDataEntity) -> String {
    var properties = ""
    for attribute in entity.attributes {
      properties += template_CD_Entity_Property.replacingWithMap(
        [
          "VARNAME": attribute.name,
          "OPTIONAL": ((attribute.optional || attribute.type.codeGenForceOptional) && !attribute.useScalar) ? "?" : "",
          "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
        ]
      )
    }
    for substruct in entity.substructs {
      properties += "\n"

      if substruct.optional {
        properties += template_CD_Entity_Property.replacingWithMap(
          [
            "VARNAME": substruct.varName + "_has",
            "OPTIONAL": "",
            "TYPE": "Bool",
          ]
        )
      }

      for attribute in substruct.attributes {
        properties += template_CD_Entity_Property.replacingWithMap(
          [
            "VARNAME": substruct.varName + "_" + attribute.name,
            "OPTIONAL": (attribute.optional && !attribute.useScalar) ? "?" : "",
            "TYPE": attribute.type.swiftManagedType(scalar: attribute.useScalar),
          ]
        )
      }
    }
    for relationship in entity.relationships {
      properties += "\n"

      var type = "NSSet"
      if relationship.ordered { type = "NSOrderedSet" }
      if !relationship.toMany {
        type = entityToCDClass[relationship.destinationEntityName] ?? "---"
      }

      properties += template_CD_Entity_Property.replacingWithMap(
        [
          "VARNAME": relationship.name,
          "OPTIONAL": (relationship.optional || relationship.toMany) ? "?" : "",
          "TYPE": type,
        ]
      )
    }
    return properties
  }
}
