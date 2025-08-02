//
//  CoreDataTest2.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

@objc(CoreDataTest2)
public class CoreDataTest2: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataTest2> {
        NSFetchRequest<CoreDataTest2>(entityName: "Test2")
    }

    @NSManaged public var test: CoreDataTest?
}
