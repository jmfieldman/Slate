//
//  SlateEnumUser.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import ExampleEnums
import Foundation

public final class SlateEnumUser: Sendable {
    // -- Attribute Declarations --
    public let intEnumOptNSNumber: IntegerEnumExample?

    // -- Attribute Names --

    public enum Attributes {
        public static let intEnumOptNSNumber = "intEnumOptNSNumber"
    }

    public struct Relationships {}

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
        self.intEnumOptNSNumber = managedObject.intEnumOptNSNumber?.intValue
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive).  You should never create values with this
     constructor in normal code.
     */
    init(
        intEnumOptNSNumber: Int?
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.intEnumOptNSNumber = intEnumOptNSNumber
    }

    // -- Substruct Definitions
}

public extension SlateEnumUser {
    protocol ManagedPropertyProviding: NSManagedObject {
        var intEnumOptNSNumber: NSNumber? { get }
    }
}

extension SlateEnumUser: Equatable {
    public static func == (lhs: SlateEnumUser, rhs: SlateEnumUser) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.intEnumOptNSNumber == rhs.intEnumOptNSNumber)
    }
}
