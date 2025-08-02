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
        guard let entity = NSEntityDescription.entity(forEntityName: "Book", in: moc) else {
            return nil
        }

        return CoreDataBook(entity: entity, insertInto: moc)
    }

    @NSManaged public var likeCount: Int64
    @NSManaged public var loading: Bool
    @NSManaged public var title: String?

    @NSManaged public var author: CoreDataAuthor
}

public extension CoreDataBook: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    var slateObject: SlateObject {
        SlateBook(managedObject: self)
    }
}

extension SlateBook: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataBook.self
}
