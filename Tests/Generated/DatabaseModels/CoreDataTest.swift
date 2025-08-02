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
    @NSManaged public var transAttr: NSObject?
    @NSManaged public var uriAttr: URL?
    @NSManaged public var uuidAttr: UUID?

    @NSManaged public var test2s: NSOrderedSet?
}

extension CoreDataTest: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateTest(managedObject: self)
    }
}

extension SlateTest: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataTest.self
}
