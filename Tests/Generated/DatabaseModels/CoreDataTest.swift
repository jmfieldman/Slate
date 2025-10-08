//
//  CoreDataTest.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataTest)
public final class CoreDataTest: NSManagedObject, SlateTest.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataTest> {
        NSFetchRequest<CoreDataTest>(entityName: "Test")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataTest? {
        NSEntityDescription.entity(forEntityName: "Test", in: moc).flatMap {
            CoreDataTest(entity: $0, insertInto: moc)
        }
    }

    @NSManaged public var binAttr: Data?
    @NSManaged public var boolAttr: Bool
    @NSManaged public var dateAttr: Date?
    @NSManaged public var decAttr: NSDecimalNumber?
    @NSManaged public var doubleAttr: Double
    @NSManaged public var floatAttr: Float
    @NSManaged public var int16attr: Int16
    @NSManaged public var int32attr: NSNumber
    @NSManaged public var int64atttr: Int64
    @NSManaged public var stringAttr: String?
    @NSManaged public var uriAttr: URL?
    @NSManaged public var uuidAttr: UUID?

    @NSManaged public var test2s: NSOrderedSet?

    public static func keypathToAttribute(_ keypath: PartialKeyPath<CoreDataTest>) -> String {
        switch keypath {
        case \CoreDataTest.binAttr: "binAttr"
        case \CoreDataTest.boolAttr: "boolAttr"
        case \CoreDataTest.dateAttr: "dateAttr"
        case \CoreDataTest.decAttr: "decAttr"
        case \CoreDataTest.doubleAttr: "doubleAttr"
        case \CoreDataTest.floatAttr: "floatAttr"
        case \CoreDataTest.int16attr: "int16attr"
        case \CoreDataTest.int32attr: "int32attr"
        case \CoreDataTest.int64atttr: "int64atttr"
        case \CoreDataTest.stringAttr: "stringAttr"
        case \CoreDataTest.uriAttr: "uriAttr"
        case \CoreDataTest.uuidAttr: "uuidAttr"
        default: fatalError("Unsupported CoreDataTest key path")
        }
    }
}

extension CoreDataTest: SlateKeypathAttributeProviding {}

extension SlateTest: SlateKeypathAttributeProviding {}

extension CoreDataTest: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateTest(managedObject: self)
    }
}

extension SlateTest: @retroactive SlateObject {
    public static let __slate_managedObjectType: NSManagedObject.Type = CoreDataTest.self
}

extension SlateTest: @retroactive SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataTest
}

public extension SlateRelationshipResolver where SO: SlateTest {
    var test2s: [SlateTest2] {
        guard let mo = managedObject as? CoreDataTest else {
            fatalError("Fatal casting error")
        }

        guard let set = mo.test2s?.set else {
            return []
        }

        return convert(set) as! [SlateTest2]
    }
}
