//
//  CoreDataBook.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

@objc(CoreDataBook)
public final class CoreDataBook: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataBook> {
        NSFetchRequest<CoreDataBook>(entityName: "Book")
    }

    @NSManaged public var likeCount: Int64
    @NSManaged public var loading: Bool
    @NSManaged public var title: String?

    @NSManaged public var author: CoreDataAuthor
}
