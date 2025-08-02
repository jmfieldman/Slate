//
//  CoreDataBook.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataBook)
public final class CoreDataBook: NSManagedObject, SlateBook.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataBook> {
        NSFetchRequest<CoreDataBook>(entityName: "Book")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataBook? {
        NSEntityDescription.entity(forEntityName: "Book", in: moc).flatMap {
            CoreDataBook(entity: $0, insertInto: moc)
        }
    }

    @NSManaged public var likeCount: Int64
    @NSManaged public var loading: Bool
    @NSManaged public var title: String?

    @NSManaged public var author: CoreDataAuthor
}

extension CoreDataBook: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateBook(managedObject: self)
    }
}

extension SlateBook: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataBook.self
}

extension SlateBook: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataBook
}
