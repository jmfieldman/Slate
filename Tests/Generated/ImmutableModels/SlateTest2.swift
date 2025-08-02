//
//  SlateTest2.swift
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

public final class SlateTest2 {
    // -- Attribute Declarations --

    // -- Attribute Names --

    public struct Attributes {}

    public enum Relationships {
        public static let test = "test"
    }

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
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive).  You should never create values with this
     constructor in normal code.
     */
    init(
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()
    }

    // -- Substruct Definitions
}

extension SlateTest2: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataTest2
}

public extension SlateRelationshipResolver where SO: SlateTest2 {
    var test: SlateTest? {
        guard let mo = managedObject as? CoreDataTest2 else {
            fatalError("Fatal casting error")
        }

        return convert(mo.test) as? SlateTest
    }
}

public extension SlateTest2 {
    protocol ManagedPropertyProviding: NSManagedObject {}
}

extension SlateTest2: Equatable {
    public static func == (lhs: SlateTest2, rhs: SlateTest2) -> Bool {
        lhs.slateID == rhs.slateID
    }
}
