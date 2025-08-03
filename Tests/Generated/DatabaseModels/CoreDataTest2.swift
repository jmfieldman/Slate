//
//  CoreDataTest2.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataTest2)
public final class CoreDataTest2: NSManagedObject, SlateTest2.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataTest2> {
        NSFetchRequest<CoreDataTest2>(entityName: "Test2")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataTest2? {
        NSEntityDescription.entity(forEntityName: "Test2", in: moc).flatMap {
            CoreDataTest2(entity: $0, insertInto: moc)
        }
    }

    @NSManaged public var qnty: Int64

    @NSManaged public var test: CoreDataTest?
}

extension CoreDataTest2: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateTest2(managedObject: self)
    }
}

extension SlateTest2: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataTest2.self
}

extension SlateTest2: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataTest2
}

public extension SlateRelationshipResolver where SO == SlateTest2 {
    var test: SlateTest? {
        guard let mo = managedObject as? CoreDataTest2 else {
            fatalError("Fatal casting error")
        }

        return convert(mo.test) as? SlateTest
    }
}
