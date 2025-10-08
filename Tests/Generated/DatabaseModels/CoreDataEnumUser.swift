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

    public static func keypathToAttribute(_ keypath: PartialKeyPath<CoreDataEnumUser>) -> String {
        switch keypath {
        case \CoreDataEnumUser.id: "id"
        case \CoreDataEnumUser.intEnumNonOptIntNoDef: "intEnumNonOptIntNoDef"
        case \CoreDataEnumUser.intEnumNonOptIntYesDef: "intEnumNonOptIntYesDef"
        case \CoreDataEnumUser.intEnumNonOptNSNumberNoDef: "intEnumNonOptNSNumberNoDef"
        case \CoreDataEnumUser.intEnumNonOptNSNumberYesDef: "intEnumNonOptNSNumberYesDef"
        case \CoreDataEnumUser.intEnumOptNSNumberNoDef: "intEnumOptNSNumberNoDef"
        case \CoreDataEnumUser.intEnumOptNSNumberYesDef: "intEnumOptNSNumberYesDef"
        case \CoreDataEnumUser.stringEnumNonOptStringNoDef: "stringEnumNonOptStringNoDef"
        case \CoreDataEnumUser.stringEnumNonOptStringYesDef: "stringEnumNonOptStringYesDef"
        case \CoreDataEnumUser.stringEnumOptStringNoDef: "stringEnumOptStringNoDef"
        case \CoreDataEnumUser.stringEnumOptStringYesDef: "stringEnumOptStringYesDef"
        default: fatalError("Unsupported CoreDataEnumUser key path")
        }
    }
}

extension CoreDataEnumUser: SlateKeypathAttributeProviding {}

extension SlateEnumUser: SlateKeypathAttributeProviding {}

extension CoreDataEnumUser: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateEnumUser(managedObject: self)
    }
}

extension SlateEnumUser: @retroactive SlateObject {
    public static let __slate_managedObjectType: NSManagedObject.Type = CoreDataEnumUser.self
}

extension SlateEnumUser: @retroactive SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataEnumUser
}

public extension SlateRelationshipResolver where SO: SlateEnumUser {}
