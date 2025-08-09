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
        NSEntityDescription.entity(forEntityName: "Author", in: moc).flatMap {
            CoreDataAuthor(entity: $0, insertInto: moc)
        }
    }

    @NSManaged public var age: Int64
    @NSManaged public var name: String?

    @NSManaged public var books: NSSet?
}

extension CoreDataAuthor: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateAuthor(managedObject: self)
    }
}

extension SlateAuthor: SlateObject {
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataAuthor.self
}

extension SlateAuthor: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataAuthor
}

public extension SlateRelationshipResolver where SO: SlateAuthor {
    var books: [SlateBook] {
        guard let mo = managedObject as? CoreDataAuthor else {
            fatalError("Fatal casting error")
        }

        guard let set = mo.books as? Set<AnyHashable> else {
            return []
        }

        return convert(set) as! [SlateBook]
    }
}
