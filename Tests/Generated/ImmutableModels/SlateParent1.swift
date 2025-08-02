//
//  SlateParent1.swift
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

extension CoreDataParent1: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateParent1(managedObject: self)
    }
}

public extension CoreDataParent1 {
    /**
     Helper method that instantiates a CoreDataParent1 in the specified context.
     */
    static func create(in moc: NSManagedObjectContext) -> CoreDataParent1? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Parent1", in: moc) else {
            return nil
        }

        return CoreDataParent1(entity: entity, insertInto: moc)
    }
}

public final class SlateParent1: SlateObject {
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

    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataParent1.self

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
    fileprivate init(managedObject: CoreDataParent1) {
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

    public struct Child1: Equatable {
        // -- Attribute Declarations --
        public let optString: String?
        public let propInt64scalar: Int
        public let string: String

        /**
         Instantiation is private to this file; Substructs should only be instantiated
         by their parent Slate object.
         */
        fileprivate init(managedObject: CoreDataParent1) {
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

    public struct Child2: Equatable {
        // -- Attribute Declarations --
        public let bool: Bool
        public let int64scalar: Int
        public let optBool: Bool?
        public let optString: String?

        /**
         Instantiation is private to this file; Substructs should only be instantiated
         by their parent Slate object.
         */
        fileprivate init(managedObject: CoreDataParent1) {
            // Attribute assignment
            self.bool = { let t: Bool? = managedObject.child2_bool?.boolValue
                return t ?? true
            }()
            self.int64scalar = managedObject.child2_int64scalar.slate_asInt
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

extension SlateParent1: SlateManagedObjectRelating {
    public typealias ManagedObjectType = CoreDataParent1
}

public extension SlateRelationshipResolver where SO: SlateParent1 {}

extension SlateParent1: Equatable {
    public static func == (lhs: SlateParent1, rhs: SlateParent1) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.id == rhs.id) &&
            (lhs.child1 == rhs.child1) &&
            (lhs.child2 == rhs.child2)
    }
}
