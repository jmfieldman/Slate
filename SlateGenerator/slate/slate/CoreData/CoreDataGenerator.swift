//
//  CoreDataGenerator.swift
//  slate
//
//  Created by Jason Fieldman on 5/29/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation

private let kStringArgVar: String = "%@"

class CoreDataSwiftGenerator {

    static var entityToSlateClass: [String: String] = [:]
    static var entityToCDClass: [String: String] = [:]
    
    /**
     Master entrance point to the file generation
     */
    static func generateCoreData(
        entities: [CoreDataEntity],
        useClass: Bool,
        classXform: String,
        fileXform: String,
        outputPath: String,
        importModule: String)
    {
        let filePerClass: Bool = fileXform.contains(kStringArgVar)
        var fileAccumulator = generateHeader(filename: fileXform, importModule: importModule)
        
        // First pass create lookup dictionaries
        for entity in entities {
            let className: String = classXform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)
            
            entityToSlateClass[entity.entityName] = className
            entityToCDClass[entity.entityName] = entity.codeClass
        }
        
        for entity in entities {
            let className: String = classXform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)
            let filename: String = fileXform.replacingOccurrences(of: kStringArgVar, with: entity.entityName)
            
            // Start a new file accumulator if uses per-class file
            if filePerClass {
                fileAccumulator = generateHeader(filename: filename, importModule: importModule)
            }
            
            fileAccumulator += entityCode(entity: entity, useClass: useClass, className: className)
            
            // Write to file if necessary
            if filePerClass {
                let filepath = (outputPath as NSString).appendingPathComponent("\(filename).swift")
                try! fileAccumulator.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
            }
        }
        
        // Output single file if necessary
        if !filePerClass {
            let filepath = (outputPath as NSString).appendingPathComponent("\(fileXform).swift")
            try! fileAccumulator.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
        }
    }

    static func generateHeader(filename: String, importModule: String) -> String {
        return template_CD_Swift_fileheader.replacingWithMap(
            ["FILENAME": filename,
             "COMMAND": commandline,
             "EXTRAIMPORT": (importModule != "") ? "\nimport \(importModule)" : "" ]
        )
    }
    
    static var commandline: String {
        return CommandLine.arguments.joined(separator: " ")
    }
    
    static func entityCode(
        entity: CoreDataEntity,
        useClass: Bool,
        className: String
    ) -> String {
        
        let convertible = template_CD_Swift_SlateObjectConvertible.replacingWithMap(
            ["COREDATACLASS": entity.codeClass,
             "SLATECLASS": className]
        )
        
        let moExtension = template_CD_Swift_ManagedObjectExtension.replacingWithMap(
            ["COREDATACLASS": entity.codeClass,
             "COREDATAENTITYNAME": entity.entityName]
        )
        
        let classImpl = generateClassImpl(entity: entity, useClass: useClass, className: className)
        let relations = generateRelationships(entity: entity, useClass: useClass, className: className)
        let equatable = generateEquatable(entity: entity, className: className)
        
        return "\(convertible)\(moExtension)\(classImpl)\(relations)\(equatable)"
    }

    static func generateClassImpl(entity: CoreDataEntity, useClass: Bool, className: String) -> String {
        var declarations: String = ""
        var assignments: String = ""
        
        for attr in entity.attributes {
            declarations += template_CD_Swift_AttrDeclaration.replacingWithMap(
                ["ATTR": attr.name,
                 "TYPE": attr.type.immType,
                 "OPTIONAL": attr.optional ? "?" : ""])
            
            let useForce = !attr.optional && attr.type.codeGenForceOptional
            let str = useForce ? template_CD_Swift_AttrForceAssignment : template_CD_Swift_AttrAssignment
            var conv = ""
            if let sconv = attr.type.swiftValueConversion, !attr.useScalar {
                conv = (attr.optional ? "?" : "") + sconv
            }
            assignments += str.replacingWithMap(
                ["ATTR": attr.name,
                 "TYPE": attr.type.immType,
                 "CONV": conv,
                ])
        }
        
        return template_CD_Swift_SlateClassImpl.replacingWithMap(
            ["OBJTYPE": useClass ? "class" : "struct",
             "SLATECLASS": className,
             "COREDATACLASS": entity.codeClass,
             "ATTRASSIGNMENT": assignments,
             "ATTRDECLARATIONS": declarations]
        )
    }
    
    static func generateRelationships(entity: CoreDataEntity, useClass: Bool, className: String) -> String {
        var relationships: String = ""
        for relationship in entity.relationships {
            if relationship.toMany {
                relationships += template_CD_Swift_SlateRelationshipToMany.replacingWithMap(
                    ["RELATIONSHIPNAME": relationship.name,
                     "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
                     "COREDATACLASS": entity.codeClass]
                )
            } else {
                relationships += template_CD_Swift_SlateRelationshipToOne.replacingWithMap(
                    ["RELATIONSHIPNAME": relationship.name,
                     "TARGETSLATECLASS": entityToSlateClass[relationship.destinationEntityName]!,
                     "COREDATACLASS": entity.codeClass,
                     "OPTIONAL": relationship.optional ? "?" : "",
                     "NONOPTIONAL": relationship.optional ? "" : "!"]
                )
            }
        }
        
        return template_CD_Swift_SlateRelationshipResolver.replacingWithMap(
            ["OBJQUAL": useClass ? ": " : " == ",
             "SLATECLASS": className,
             "RELATIONSHIPS": relationships]
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
            ["SLATECLASS": className,
             "ATTRS": attrs]
        )
    }
}
