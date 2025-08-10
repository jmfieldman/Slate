//
//  CoreDataTypes.swift
//  Copyright © 2020 Jason Fieldman.
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

    func immType(castInt: Bool) -> String {
        switch self {
        case .integer16: castInt ? "Int" : "Int16"
        case .integer32: castInt ? "Int" : "Int32"
        case .integer64: castInt ? "Int" : "Int64"
        case .decimal: "Decimal"
        case .double: "Double"
        case .float: "Float"
        case .string: "String"
        case .boolean: "Bool"
        case .date: "Date"
        case .binaryData: "Data"
        case .uuid: "UUID"
        case .uri: "URL"
        case .transformable: "AnyObject"
        }
    }

    // When using CD codegen tools, selecting not-optional will force
    // optional properties
    var codeGenForceOptional: Bool {
        switch self {
        case .integer16: false
        case .integer32: false
        case .integer64: false
        case .decimal: true
        case .double: false
        case .float: false
        case .string: true
        case .boolean: false
        case .date: true
        case .binaryData: true
        case .uuid: true
        case .uri: true
        case .transformable: true
        }
    }

    // If the CD value is not scalar, we'll need to convert it to the
    // native scalar
    var needsOptConvIfNotScalar: Bool {
        switch self {
        case .integer16: true
        case .integer32: true
        case .integer64: true
        case .decimal: true
        case .double: true
        case .float: true
        case .string: false
        case .boolean: true
        case .date: false
        case .binaryData: false
        case .uuid: false
        case .uri: false
        case .transformable: false
        }
    }

    // true if this is an integer type
    var isInt: Bool {
        switch self {
        case .integer16: true
        case .integer32: true
        case .integer64: true
        default: false
        }
    }

    // Converts something like NSNumber to Double
    func swiftValueConversion(castInt: Bool) -> String? {
        switch self {
        case .integer16: castInt ? ".intValue" : ".int16Value"
        case .integer32: castInt ? ".intValue" : ".int32Value"
        case .integer64: castInt ? ".intValue" : ".int64Value"
        case .decimal: ".decimalValue"
        case .double: ".doubleValue"
        case .float: ".floatValue"
        case .string: nil
        case .boolean: ".boolValue"
        case .date: nil
        case .binaryData: nil
        case .uuid: nil
        case .uri: nil
        case .transformable: nil
        }
    }

    // Returns the type of the property in an NSManagedObject property
    func swiftManagedType(scalar: Bool) -> String {
        switch self {
        case .integer16: scalar ? "Int16" : "NSNumber"
        case .integer32: scalar ? "Int32" : "NSNumber"
        case .integer64: scalar ? "Int64" : "NSNumber"
        case .decimal: "NSDecimalNumber"
        case .double: scalar ? "Double" : "NSNumber"
        case .float: scalar ? "Float" : "NSNumber"
        case .string: "String"
        case .boolean: scalar ? "Bool" : "NSNumber"
        case .date: scalar ? "TimeInterval" : "Date"
        case .binaryData: "Data"
        case .uuid: "UUID"
        case .uri: "URL"
        case .transformable: "NSObject"
        }
    }

    var supported: Bool {
        switch self {
        case .integer16: true
        case .integer32: true
        case .integer64: true
        case .decimal: true
        case .double: true
        case .float: true
        case .string: true
        case .boolean: true
        case .date: true
        case .binaryData: true
        case .uuid: true
        case .uri: true
        case .transformable: false
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

    var access: String {
        userdata["access"] ?? "public"
    }

    var enumType: String? { userdata["enum"] }
    var enumDefault: String? { userdata["enumDefault"] }
}

struct CoreDataSubstruct {
    let structName: String
    let varName: String
    let optional: Bool
    let attributes: [CoreDataAttribute]

    var access: String {
        "public"
    }
}

struct CoreDataEntity {
    let entityName: String
    let codeClass: String
    let useStruct: Bool
    let imports: [String]
    let attributes: [CoreDataAttribute]
    let relationships: [CoreDataRelationship]
    let substructs: [CoreDataSubstruct]
}
