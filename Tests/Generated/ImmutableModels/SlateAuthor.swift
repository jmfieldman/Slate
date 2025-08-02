//
//  SlateAuthor.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import DatabaseModels
import Foundation
import Slate

/** These extensions are available if conversion to basic integer is required */
private extension Int16 {
    var slate_asInt: Int { Int(self) }
}

private extension Int32 {
    var slate_asInt: Int { Int(self) }
}

private extension Int64 {
    var slate_asInt: Int { Int(self) }
}

extension CoreDataAuthor: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateAuthor(managedObject: self)
    }
}

public extension CoreDataAuthor {
    /**
     Helper method that instantiates a CoreDataAuthor in the specified context.
     */
    static func create(in moc: NSManagedObjectContext) -> CoreDataAuthor? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Author", in: moc) else {
            return nil
        }

        return CoreDataAuthor(entity: entity, insertInto: moc)
    }
}

public final class SlateAuthor: SlateObject {
    // -- Attribute Declarations --
    public let name: String

    // -- Attribute Names --

    public enum Attributes {
        public static let name = "name"
    }

    public enum Relationships {
        public static let books = "books"
    }

    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataAuthor.self

    /**
      Each immutable data model object should have an associated SlateID (in the
      core data case, the NSManagedObjectID.  This is a cross-mutation identifier
      for the object.
     */
    public let slateID: SlateID

    /**
     Instantiation is private to this file; Slate objects should only be instantiated
     by accessing the `slateObject` property of the corresponding managed object.
     */
    fileprivate init(managedObject: CoreDataAuthor) {
        // All objects inherit the objectID
        self.slateID = managedObject.objectID

        // Attribute assignment
        self.name = { let t: String? = managedObject.name
            return t!
        }()
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive).  You should never create values with this
     constructor in normal code.
     */
    init(
        name: String
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.name = name
    }

    // -- Substruct Definitions
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

extension SlateAuthor: Equatable {
    public static func == (lhs: SlateAuthor, rhs: SlateAuthor) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.name == rhs.name)
    }
}
