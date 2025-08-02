//
//  CoreDataAuthor.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import Slate

@objc(CoreDataAuthor)
public final class CoreDataAuthor: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataAuthor> {
        NSFetchRequest<CoreDataAuthor>(entityName: "Author")
    }

    @NSManaged public var name: String?

    @NSManaged public var books: NSSet?
}
