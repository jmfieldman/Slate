//
//  CoreDataAuthor.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation
import ImmutableModels
import Slate

@objc(CoreDataAuthor)
public final class CoreDataAuthor: NSManagedObject, SlateAuthor.ManagedPropertyProviding {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataAuthor> {
        NSFetchRequest<CoreDataAuthor>(entityName: "Author")
    }

    @nonobjc static func create(in moc: NSManagedObjectContext) -> CoreDataAuthor? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Author", in: moc) else {
            return nil
        }

        return CoreDataAuthor(entity: entity, insertInto: moc)
    }

    @NSManaged public var name: String?

    @NSManaged public var books: NSSet?
}

public extension CoreDataAuthor: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    var slateObject: SlateObject {
        SlateAuthor(managedObject: self)
    }
}

extension SlateAuthor: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataAuthor.self
}
