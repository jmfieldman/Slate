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

    @NSManaged public var id: Int64
    @NSManaged public var intEnumNonOptIntNoDef: Int64
    @NSManaged public var intEnumNonOptIntYesDef: Int64
    @NSManaged public var intEnumNonOptNSNumberNoDef: NSNumber
    @NSManaged public var intEnumNonOptNSNumberYesDef: NSNumber
    @NSManaged public var intEnumOptNSNumberNoDef: NSNumber?
    @NSManaged public var intEnumOptNSNumberYesDef: NSNumber?
    @NSManaged public var stringEnumNonOptStringNoDef: String?
    @NSManaged public var stringEnumNonOptStringYesDef: String?
    @NSManaged public var stringEnumOptStringNoDef: String?
    @NSManaged public var stringEnumOptStringYesDef: String?
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
