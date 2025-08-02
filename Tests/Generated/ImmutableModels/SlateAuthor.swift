//
//  SlateAuthor.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

public final class SlateAuthor {
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
      Each immutable data model object should have an associated SlateID (in the
      core data case, the NSManagedObjectID.  This is a cross-mutation identifier
      for the object.
     */
    public let slateID: NSManagedObjectID

    /**
     Instantiation is public so that Slate instances can create immutable objects
     from corresponding managed objects. You should never manually construct this in code.
     */
    public init(managedObject: ManagedPropertyProviding) {
        // Immutable objects should only be created inside Slate contexts
        // (by the Slate engine)
        guard Thread.current.threadDictionary["kThreadKeySlateQueryContext"] != nil else {
            fatalError("It is a programming error to instantiate an immutable Slate object from outside of a Slate query context.")
        }

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

public extension SlateAuthor {
    protocol ManagedPropertyProviding: NSManagedObject {
        var name: String? { get }
    }
}

extension SlateAuthor: Equatable {
    public static func == (lhs: SlateAuthor, rhs: SlateAuthor) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.name == rhs.name)
    }
}
