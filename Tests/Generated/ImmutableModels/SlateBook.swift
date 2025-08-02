//
//  SlateBook.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
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

extension CoreDataBook: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateBook(managedObject: self)
    }
}

public extension CoreDataBook {
    /**
     Helper method that instantiates a CoreDataBook in the specified context.
     */
    static func create(in moc: NSManagedObjectContext) -> CoreDataBook? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Book", in: moc) else {
            return nil
        }

        return CoreDataBook(entity: entity, insertInto: moc)
    }
}

public final class SlateBook: SlateObject {
    // -- Attribute Declarations --
    public let likeCount: Int?
    public let loading: Bool?
    public let title: String

    // -- Attribute Names --

    public enum Attributes {
        public static let likeCount = "likeCount"
        public static let loading = "loading"
        public static let title = "title"
    }

    public enum Relationships {
        public static let author = "author"
    }

    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataBook.self

    /**
      Each immutable data model object should have an associated SlateID (in the
      core data case, the NSManagedObjectID.  This is a cross-mutation identifier
      for the object.
     */
    public let slateID: SlateID

    /**
     Instantiation is public so that Slate instances can create immutable objects
     from corresponding managed objects. You should never manually construct this in code.
     */
    public init(managedObject: ManagedPropertyProviding) {
        // Immutable objects should only be created inside Slate contexts
        // (by the Slate engine)
        guard Slate.isThreadInsideQuery else {
            fatalError("It is a programming error to instantiate an immutable Slate object from outside of a Slate query context.")
        }

        // All objects inherit the objectID
        self.slateID = managedObject.objectID

        // Attribute assignment
        self.likeCount = managedObject.likeCount.slate_asInt
        self.loading = managedObject.loading
        self.title = { let t: String? = managedObject.title
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
        likeCount: Int?,
        loading: Bool?,
        title: String
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.likeCount = likeCount
        self.loading = loading
        self.title = title
    }

    // -- Substruct Definitions
}

extension SlateBook: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataBook
}

public extension SlateRelationshipResolver where SO: SlateBook {
    var author: SlateAuthor {
        guard let mo = managedObject as? CoreDataBook else {
            fatalError("Fatal casting error")
        }

        return convert(mo.author) as! SlateAuthor
    }
}

public extension SlateBook {
    protocol ManagedPropertyProviding: NSManagedObject {
        var likeCount: Int64 { get }
        var loading: Bool { get }
        var title: String? { get }
    }
}

extension SlateBook: Equatable {
    public static func == (lhs: SlateBook, rhs: SlateBook) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.likeCount == rhs.likeCount) &&
            (lhs.loading == rhs.loading) &&
            (lhs.title == rhs.title)
    }
}
