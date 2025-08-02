//
//  CoreDataTest.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

@objc(CoreDataTest)
public final class CoreDataTest: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataTest> {
        NSFetchRequest<CoreDataTest>(entityName: "Test")
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
