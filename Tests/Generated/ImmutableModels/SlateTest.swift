//
//  SlateTest.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

public final class SlateTest: Sendable {
    // -- Attribute Declarations --
    public let binAttr: Data
    public let boolAttr: Bool
    public let dateAttr: Date
    public let decAttr: Decimal?
    public let doubleAttr: Double
    public let floatAttr: Float
    public let int16attr: Int
    public let int32attr: Int
    public let int64atttr: Int
    public let stringAttr: String
    public let uriAttr: URL
    public let uuidAttr: UUID

    // -- Attribute Names --

    public enum Attributes {
        public static let binAttr = "binAttr"
        public static let boolAttr = "boolAttr"
        public static let dateAttr = "dateAttr"
        public static let decAttr = "decAttr"
        public static let doubleAttr = "doubleAttr"
        public static let floatAttr = "floatAttr"
        public static let int16attr = "int16attr"
        public static let int32attr = "int32attr"
        public static let int64atttr = "int64atttr"
        public static let stringAttr = "stringAttr"
        public static let uriAttr = "uriAttr"
        public static let uuidAttr = "uuidAttr"
    }

    public enum Relationships {
        public static let test2s = "test2s"
    }

    public static func keypathToAttribute(_ keypath: PartialKeyPath<SlateTest>) -> String {
        switch keypath {
        case \SlateTest.binAttr: "binAttr"
        case \SlateTest.boolAttr: "boolAttr"
        case \SlateTest.dateAttr: "dateAttr"
        case \SlateTest.decAttr: "decAttr"
        case \SlateTest.doubleAttr: "doubleAttr"
        case \SlateTest.floatAttr: "floatAttr"
        case \SlateTest.int16attr: "int16attr"
        case \SlateTest.int32attr: "int32attr"
        case \SlateTest.int64atttr: "int64atttr"
        case \SlateTest.stringAttr: "stringAttr"
        case \SlateTest.uriAttr: "uriAttr"
        case \SlateTest.uuidAttr: "uuidAttr"
        default: fatalError("Unsupported SlateTest key path")
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
        self.binAttr = { let t: Data? = managedObject.binAttr
            return t!
        }()
        self.boolAttr = managedObject.boolAttr
        self.dateAttr = { let t: Date? = managedObject.dateAttr
            return t!
        }()
        self.decAttr = managedObject.decAttr?.decimalValue
        self.doubleAttr = managedObject.doubleAttr
        self.floatAttr = managedObject.floatAttr
        self.int16attr = Int(managedObject.int16attr)
        self.int32attr = managedObject.int32attr.intValue
        self.int64atttr = Int(managedObject.int64atttr)
        self.stringAttr = { let t: String? = managedObject.stringAttr
            return t!
        }()
        self.uriAttr = { let t: URL? = managedObject.uriAttr
            return t!
        }()
        self.uuidAttr = { let t: UUID? = managedObject.uuidAttr
            return t!
        }()
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive). You should never create values with this
     constructor in normal code.
     */
    init(
        binAttr: Data,
        boolAttr: Bool,
        dateAttr: Date,
        decAttr: Decimal?,
        doubleAttr: Double,
        floatAttr: Float,
        int16attr: Int,
        int32attr: Int,
        int64atttr: Int,
        stringAttr: String,
        uriAttr: URL,
        uuidAttr: UUID
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.binAttr = binAttr
        self.boolAttr = boolAttr
        self.dateAttr = dateAttr
        self.decAttr = decAttr
        self.doubleAttr = doubleAttr
        self.floatAttr = floatAttr
        self.int16attr = int16attr
        self.int32attr = int32attr
        self.int64atttr = int64atttr
        self.stringAttr = stringAttr
        self.uriAttr = uriAttr
        self.uuidAttr = uuidAttr
    }

    // -- Substruct Definitions
}

public extension SlateTest {
    protocol ManagedPropertyProviding: NSManagedObject {
        var binAttr: Data? { get }
        var boolAttr: Bool { get }
        var dateAttr: Date? { get }
        var decAttr: NSDecimalNumber? { get }
        var doubleAttr: Double { get }
        var floatAttr: Float { get }
        var int16attr: Int16 { get }
        var int32attr: NSNumber { get }
        var int64atttr: Int64 { get }
        var stringAttr: String? { get }
        var uriAttr: URL? { get }
        var uuidAttr: UUID? { get }
    }
}

extension SlateTest: Equatable {
    public static func == (lhs: SlateTest, rhs: SlateTest) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.binAttr == rhs.binAttr) &&
            (lhs.boolAttr == rhs.boolAttr) &&
            (lhs.dateAttr == rhs.dateAttr) &&
            (lhs.decAttr == rhs.decAttr) &&
            (lhs.doubleAttr == rhs.doubleAttr) &&
            (lhs.floatAttr == rhs.floatAttr) &&
            (lhs.int16attr == rhs.int16attr) &&
            (lhs.int32attr == rhs.int32attr) &&
            (lhs.int64atttr == rhs.int64atttr) &&
            (lhs.stringAttr == rhs.stringAttr) &&
            (lhs.uriAttr == rhs.uriAttr) &&
            (lhs.uuidAttr == rhs.uuidAttr)
    }
}
