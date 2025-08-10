//
//  CoreDataEnumUser.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataEnumUser)
public final class CoreDataEnumUser: NSManagedObject, SlateEnumUser.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataEnumUser> {
        NSFetchRequest<CoreDataEnumUser>(entityName: "EnumUser")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataEnumUser? {
        NSEntityDescription.entity(forEntityName: "EnumUser", in: moc).flatMap {
            CoreDataEnumUser(entity: $0, insertInto: moc)
        }
    }

    @NSManaged public var intEnumOptNSNumber: NSNumber?
}

extension CoreDataEnumUser: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateEnumUser(managedObject: self)
    }
}

extension SlateEnumUser: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataEnumUser.self
}

extension SlateEnumUser: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataEnumUser
}

public extension SlateRelationshipResolver where SO: SlateEnumUser {}
