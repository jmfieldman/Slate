//
//  SlateTest2.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

public struct SlateTest2: Sendable {
    // -- Attribute Declarations --
    public let qnty: Int

    // -- Attribute Names --

    public enum Attributes {
        public static let qnty = "qnty"
    }

    public enum Relationships {
        public static let test = "test"
    }

    public static func keypathToAttribute(_ keypath: PartialKeyPath<SlateTest2>) -> String {
        switch keypath {
        case \SlateTest2.qnty: "qnty"

        default: fatalError("Unsupported SlateTest2 key path")
        }
    }

    /**
      Each immutable data model object should have an associated SlateID (in the
      core data case, the NSManagedObjectID. This is a cross-mutation identifier
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
        self.qnty = Int(managedObject.qnty)
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive). You should never create values with this
     constructor in normal code.
     */
    init(
        qnty: Int
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.qnty = qnty
    }

    // -- Substruct Definitions
}

public extension SlateTest2 {
    protocol ManagedPropertyProviding: NSManagedObject {
        var qnty: Int64 { get }
    }
}

extension SlateTest2: Equatable {
    public static func == (lhs: SlateTest2, rhs: SlateTest2) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.qnty == rhs.qnty)
    }
}
