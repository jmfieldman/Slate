//
//  CoreDataTypes.swift
//  slate
//
//  Created by Jason Fieldman on 5/29/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation


enum CoreDataAttrType: String {
    case integer16 = "Integer 16"
    case integer32 = "Integer 32"
    case integer64 = "Integer 64"
    case decimal = "Decimal"
    case double = "Double"
    case float = "Float"
    case string = "String"
    case boolean = "Boolean"
    case date = "Date"
    case binaryData = "Binary"
    case uuid = "UUID"
    case uri = "URI"
    case transformable = "Transformable"
    
    var immType: String {
        switch self {
        case .integer16: return _useInt ? "Int" : "Int16"
        case .integer32: return _useInt ? "Int" : "Int32"
        case .integer64: return _useInt ? "Int" : "Int64"
        case .decimal: return "Decimal"
        case .double: return "Double"
        case .float: return "Float"
        case .string: return "String"
        case .boolean: return "Bool"
        case .date: return "Date"
        case .binaryData: return "Data"
        case .uuid: return "UUID"
        case .uri: return "URL"
        case .transformable: return "AnyObject"
        }
    }
    
    // When using CD codegen tools, selecting not-optional will force
    // optional properties
    var codeGenForceOptional: Bool {
        switch self {
        case .integer16: return false
        case .integer32: return false
        case .integer64: return false
        case .decimal: return true
        case .double: return false
        case .float: return false
        case .string: return true
        case .boolean: return false
        case .date: return true
        case .binaryData: return true
        case .uuid: return true
        case .uri: return true
        case .transformable: return true
        }
    }

    // If the CD value is not scalar, we'll need to convert it to the
    // native scalar
    var needsOptConvIfNotScalar: Bool {
        switch self {
        case .integer16: return true
        case .integer32: return true
        case .integer64: return true
        case .decimal: return true
        case .double: return true
        case .float: return true
        case .string: return false
        case .boolean: return true
        case .date: return false
        case .binaryData: return false
        case .uuid: return false
        case .uri: return false
        case .transformable: return false
        }
    }

    // true if this is an integer type
    var isInt: Bool {
        switch self {
        case .integer16: return true
        case .integer32: return true
        case .integer64: return true
        default: return false
        }
    }

    // Converts something like NSNumber to Double
    var swiftValueConversion: String? {
        switch self {
        case .integer16: return _useInt ? ".intValue" : ".int16Value"
        case .integer32: return _useInt ? ".intValue" : ".int32Value"
        case .integer64: return _useInt ? ".intValue" : ".int64Value"
        case .decimal: return ".decimalValue"
        case .double: return ".doubleValue"
        case .float: return ".floatValue"
        case .string: return nil
        case .boolean: return ".boolValue"
        case .date: return nil
        case .binaryData: return nil
        case .uuid: return nil
        case .uri: return nil
        case .transformable: return nil
        }
    }

    // Returns the type of the property in an NSManagedObject property
    func swiftManagedType(scalar: Bool) -> String {
        switch self {
        case .integer16: return scalar ? "Int16" : "NSNumber"
        case .integer32: return scalar ? "Int32" : "NSNumber"
        case .integer64: return scalar ? "Int64" : "NSNumber"
        case .decimal: return "NSDecimalNumber"
        case .double: return scalar ? "Double" : "NSNumber"
        case .float: return scalar ? "Float" : "NSNumber"
        case .string: return "String"
        case .boolean: return scalar ? "Bool" : "NSNumber"
        case .date: return scalar ? "TimeInterval" : "Date"
        case .binaryData: return "Data"
        case .uuid: return "UUID"
        case .uri: return "URL"
        case .transformable: return "NSObject"
        }
    }
}

struct CoreDataRelationship {
    let name: String
    let optional: Bool
    let destinationEntityName: String
    let toMany: Bool
    let ordered: Bool
}

struct CoreDataAttribute {
    let name: String
    let optional: Bool
    let useScalar: Bool
    let type: CoreDataAttrType
    let userdata: [String: String]
}

struct CoreDataSubstruct {
    let structName: String
    let varName: String
    let optional: Bool
    let attributes: [CoreDataAttribute]
}

struct CoreDataEntity {
    let entityName: String
    let codeClass: String
    let attributes: [CoreDataAttribute]
    let relationships: [CoreDataRelationship]
    let substructs: [CoreDataSubstruct]
}
