//
//  CoreDataParent1.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import Slate

@objc(CoreDataParent1)
public final class CoreDataParent1: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataParent1> {
        NSFetchRequest<CoreDataParent1>(entityName: "Parent1")
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
