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
        NSEntityDescription.entity(forEntityName: "Parent1", in: moc).flatMap {
            CoreDataParent1(entity: $0, insertInto: moc)
        }
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

    public static func keypathToAttribute(_ keypath: PartialKeyPath<CoreDataParent1>) -> String {
        switch keypath {
        case \CoreDataParent1.id: "id"
        case \CoreDataParent1.child1_optString: "child1_optString"
        case \CoreDataParent1.child1_propInt64scalar: "child1_propInt64scalar"
        case \CoreDataParent1.child1_string: "child1_string"
        case \CoreDataParent1.child2_bool: "child2_bool"
        case \CoreDataParent1.child2_int64scalar: "child2_int64scalar"
        case \CoreDataParent1.child2_optBool: "child2_optBool"
        case \CoreDataParent1.child2_optString: "child2_optString"
        default: fatalError("Unsupported CoreDataParent1 key path")
        }
    }
}

extension CoreDataParent1: SlateKeypathAttributeProviding {}

extension SlateParent1: SlateKeypathAttributeProviding {}

extension CoreDataParent1: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateParent1(managedObject: self)
    }
}

extension SlateParent1: @retroactive SlateObject {
    public static let __slate_managedObjectType: NSManagedObject.Type = CoreDataParent1.self
}

extension SlateParent1: @retroactive SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataParent1
}

public extension SlateRelationshipResolver where SO: SlateParent1 {}
