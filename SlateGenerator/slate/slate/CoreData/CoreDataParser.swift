//
//  main.swift
//  slate
//
//  Created by Jason Fieldman on 5/28/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation

func ParseCoreData(contentsPath: String) -> [CoreDataEntity] {
    let contents = try! String.init(contentsOfFile: contentsPath)
    let xml = try! XML.parse(contents)
    
    let model = xml["model", "entity"]
    
    guard let entities = model.all else {
        print("Could not find model>entities in xcdatamodel")
        exit(1)
    }
    
    var coreDataEntities: [CoreDataEntity] = []
    for entity in entities {
        guard let entityName = entity.attributes["name"] else {
            print("Error getting name attribute of entity")
            exit(2)
        }
        
        guard let representedClass = entity.attributes["representedClassName"] else {
            print("Error getting name attribute of entity")
            exit(2)
        }
        
        var attributes: [CoreDataAttribute] = []
        for attribute in entity.childElements {
            guard attribute.name == "attribute" else {
                continue
            }
            
            guard let name = attribute.attributes["name"] else {
                print("attribute does not have name")
                continue
            }
            
            guard let attrTypeStr = attribute.attributes["attributeType"] else {
                print("attribute does not attributeType")
                continue
            }
            
            guard let attrType = CoreDataAttrType(rawValue: attrTypeStr) else {
                print("Unrecognized attributeType \(attrTypeStr)")
                continue
            }
            
            let optional = (attribute.attributes["optional"] ?? "NO") == "YES"
            
            let useScalar = (attribute.attributes["usesScalarValueType"] ?? "NO") == "YES"
            
            
            
            attributes.append(
                CoreDataAttribute(name: name,
                                  optional: optional,
                                  useScalar: useScalar,
                                  type: attrType)
            )
        }
        
        var relationships: [CoreDataRelationship] = []
        for relationship in entity.childElements {
            guard relationship.name == "relationship" else {
                continue
            }
            
            guard let name = relationship.attributes["name"] else {
                print("attribute does not have name")
                continue
            }
            
            guard let destEntName = relationship.attributes["inverseEntity"] else {
                print("relationship has no inverse entity name")
                continue
            }
            
            let optional = (relationship.attributes["optional"] ?? "NO") == "YES"
            let toMany: Bool = (relationship.attributes["toMany"] ?? "NO") == "YES"
            let ordered: Bool = (relationship.attributes["ordered"] ?? "NO") == "YES"
            
            relationships.append(
                CoreDataRelationship(name: name,
                                     optional: optional,
                                     destinationEntityName: destEntName,
                                     toMany: toMany,
                                     ordered: ordered)
            )
        }
        
        coreDataEntities.append(
            CoreDataEntity(entityName: entityName,
                           codeClass: representedClass,
                           attributes: attributes,
                           relationships: relationships)
        )
    }
    
    return coreDataEntities
}

