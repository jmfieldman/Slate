//
//  SlateParent1.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

public final class SlateParent1: Sendable {
    // -- Attribute Declarations --
    public let id: String
    public let child1: SlateParent1.Child1?
    public let child2: SlateParent1.Child2

    // -- Attribute Names --

    public enum Attributes {
        public static let child1_optString = "child1_optString"
        public static let child1_propInt64scalar = "child1_propInt64scalar"
        public static let child1_string = "child1_string"
        public static let child2_bool = "child2_bool"
        public static let child2_int64scalar = "child2_int64scalar"
        public static let child2_optBool = "child2_optBool"
        public static let child2_optString = "child2_optString"
        public static let id = "id"
    }

    public struct Relationships {}

    public static func keypathToAttribute(_ keypath: PartialKeyPath<SlateParent1>) -> String {
        switch keypath {
        case \SlateParent1.id: "id"
        case \SlateParent1.child1?.optString: "child1_optString"
        case \SlateParent1.child1?.propInt64scalar: "child1_propInt64scalar"
        case \SlateParent1.child1?.string: "child1_string"
        case \SlateParent1.child2.bool: "child2_bool"
        case \SlateParent1.child2.int64scalar: "child2_int64scalar"
        case \SlateParent1.child2.optBool: "child2_optBool"
        case \SlateParent1.child2.optString: "child2_optString"
        default: fatalError("Unsupported SlateParent1 key path")
        }
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
        self.id = { let t: String? = managedObject.id
            return t!
        }()
        self.child1 = managedObject.child1_has ? SlateParent1.Child1(managedObject: managedObject) : nil
        self.child2 = SlateParent1.Child2(managedObject: managedObject)
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive).  You should never create values with this
     constructor in normal code.
     */
    init(
        child1: SlateParent1.Child1?,
        child2: SlateParent1.Child2,
        id: String
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.child1 = child1
        self.child2 = child2
        self.id = id
    }

    // -- Substruct Definitions

    public struct Child1: Equatable, Sendable {
        // -- Attribute Declarations --
        public let optString: String?
        public let propInt64scalar: Int
        public let string: String

        /**
         Instantiation is private to this file; Substructs should only be instantiated
         by their parent Slate object.
         */
        fileprivate init(managedObject: ManagedPropertyProviding) {
            // Attribute assignment
            self.optString = managedObject.child1_optString
            self.propInt64scalar = { let t: Int? = managedObject.child1_propInt64scalar?.intValue
                return t ?? 0
            }()
            self.string = { let t: String? = managedObject.child1_string
                return t ?? "Test"
            }()
        }

        /**
          Allow the creation of a Slate-exposed class/struct with all of its parameters.
          Note that this is internal -- this is for use only in unit tests (using the
          @testable import directive).  You should never create values with this
          constructor in normal code.
         */
        init(
            optString: String?,
            propInt64scalar: Int,
            string: String
        ) {
            self.optString = optString
            self.propInt64scalar = propInt64scalar
            self.string = string
        }
    }

    public struct Child2: Equatable, Sendable {
        // -- Attribute Declarations --
        public let bool: Bool
        public let int64scalar: Int
        public let optBool: Bool?
        public let optString: String?

        /**
         Instantiation is private to this file; Substructs should only be instantiated
         by their parent Slate object.
         */
        fileprivate init(managedObject: ManagedPropertyProviding) {
            // Attribute assignment
            self.bool = { let t: Bool? = managedObject.child2_bool?.boolValue
                return t ?? true
            }()
            self.int64scalar = Int(managedObject.child2_int64scalar)
            self.optBool = managedObject.child2_optBool?.boolValue
            self.optString = managedObject.child2_optString
        }

        /**
          Allow the creation of a Slate-exposed class/struct with all of its parameters.
          Note that this is internal -- this is for use only in unit tests (using the
          @testable import directive).  You should never create values with this
          constructor in normal code.
         */
        init(
            bool: Bool,
            int64scalar: Int,
            optBool: Bool?,
            optString: String?
        ) {
            self.bool = bool
            self.int64scalar = int64scalar
            self.optBool = optBool
            self.optString = optString
        }
    }
}

public extension SlateParent1 {
    protocol ManagedPropertyProviding: NSManagedObject {
        var id: String? { get }

        var child1_has: Bool { get }
        var child1_optString: String? { get }
        var child1_propInt64scalar: NSNumber? { get }
        var child1_string: String? { get }

        var child2_bool: NSNumber? { get }
        var child2_int64scalar: Int64 { get }
        var child2_optBool: NSNumber? { get }
        var child2_optString: String? { get }
    }
}

extension SlateParent1: Equatable {
    public static func == (lhs: SlateParent1, rhs: SlateParent1) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.id == rhs.id) &&
            (lhs.child1 == rhs.child1) &&
            (lhs.child2 == rhs.child2)
    }
}
