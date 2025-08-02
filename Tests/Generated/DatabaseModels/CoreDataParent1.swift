//
//  CoreDataParent1.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataParent1)
public final class CoreDataParent1: NSManagedObject, SlateParent1.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataParent1> {
        NSFetchRequest<CoreDataParent1>(entityName: "Parent1")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataParent1? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Parent1", in: moc) else {
            return nil
        }

        return CoreDataParent1(entity: entity, insertInto: moc)
    }

    @NSManaged public var id: String?

    @NSManaged public var child1_has: Bool
    @NSManaged public var child1_optString: String?
    @NSManaged public var child1_propInt64scalar: NSNumber?
    @NSManaged public var child1_string: String?

    @NSManaged public var child2_bool: NSNumber?
    @NSManaged public var child2_int64scalar: Int64
    @NSManaged public var child2_optBool: NSNumber?
    @NSManaged public var child2_optString: String?
}

public extension CoreDataParent1: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    var slateObject: SlateObject {
        SlateParent1(managedObject: self)
    }
}

extension SlateParent1: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataParent1.self
}
