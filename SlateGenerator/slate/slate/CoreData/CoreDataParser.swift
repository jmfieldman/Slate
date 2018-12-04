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

        // Attributes

        var attributes: [CoreDataAttribute] = []
        var prestructAttrs: [CoreDataAttribute] = []
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
            
            var userdata: [String: String] = [:]
            for userdataElement in attribute.childElements {
                guard userdataElement.name == "userInfo" else {
                    continue
                }
                for entry in userdataElement.childElements {
                    guard entry.name == "entry" else {
                        continue
                    }
                    if let key = entry.attributes["key"], let value = entry.attributes["value"] {
                        userdata[key] = value
                    }
                }
            }

            let newAttr = CoreDataAttribute(name: name,
                                            optional: optional,
                                            useScalar: useScalar,
                                            type: attrType,
                                            userdata: userdata)

            if name.contains("_") {
                prestructAttrs.append(newAttr)
            } else {
                attributes.append(newAttr)
            }
        }

        // Substructs

        var subAttrs: [String: [CoreDataAttribute]] = [:]
        for attr in prestructAttrs {
            let breakdown = attr.name.components(separatedBy: "_")
            if breakdown.count != 2 {
                print("cannot parse substruct attribute \(attr.name) with more than 2 components")
                continue
            }

            let structname = breakdown[0]
            let attrname = breakdown[1]

            let newAttr = CoreDataAttribute(name: attrname,
                                            optional: attr.optional,
                                            useScalar: attr.useScalar,
                                            type: attr.type,
                                            userdata: attr.userdata)
            if subAttrs[structname] == nil {
                subAttrs[structname] = [newAttr]
            } else {
                subAttrs[structname]!.append(newAttr)
            }
        }

        var substructs: [CoreDataSubstruct] = []
        for (varname, attrArr) in subAttrs {

            let hasAttr = attrArr.first(where: { $0.name == "has" })
            if let hasAttr = hasAttr {
                if hasAttr.type != .boolean || hasAttr.optional == true || hasAttr.useScalar == false {
                    print("a substruct _has property must be a non-optional scalar boolean")
                    continue
                }
            }

            let isOptional = hasAttr != nil
            let attrs = attrArr.filter({ $0.name != "has" })

            // Make sure optional structs have all-optional properties
            if isOptional {
                var bad = false
                for attr in attrs {
                    if !attr.optional {
                        print("in entity \(entityName) substruct \(varname) is optional (_has exists) -- all substruct attributes must be labeled optional in core data but [\(varname + "_" + attr.name)] is not")
                        bad = true
                    }
                }
                if bad { continue }
            }

            let substruct = CoreDataSubstruct(structName: varname.capitalized,
                                              varName: varname,
                                              optional: isOptional,
                                              attributes: attrs.sorted { $0.name < $1.name })
            substructs.append(substruct)
        }

        // Relationships
        
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
                           attributes: attributes.sorted { $0.name < $1.name },
                           relationships: relationships.sorted { $0.name < $1.name },
                           substructs: substructs.sorted { $0.structName < $1.structName })
        )
    }
    
    return coreDataEntities
}

