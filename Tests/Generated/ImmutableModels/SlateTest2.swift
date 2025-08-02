//
//  SlateTest2.swift
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

extension CoreDataTest2: SlateObjectConvertible {
    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        SlateTest2(managedObject: self)
    }
}

public extension CoreDataTest2 {
    /**
     Helper method that instantiates a CoreDataTest2 in the specified context.
     */
    static func create(in moc: NSManagedObjectContext) -> CoreDataTest2? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Test2", in: moc) else {
            return nil
        }

        return CoreDataTest2(entity: entity, insertInto: moc)
    }
}

public final class SlateTest2: SlateObject {
    // -- Attribute Declarations --

    // -- Attribute Names --

    public struct Attributes {}

    public enum Relationships {
        public static let test = "test"
    }

    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    public static var __slate_managedObjectType: NSManagedObject.Type = CoreDataTest2.self

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
    fileprivate init(managedObject: CoreDataTest2) {
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

extension SlateTest2: Equatable {
    public static func == (lhs: SlateTest2, rhs: SlateTest2) -> Bool {
        lhs.slateID == rhs.slateID
    }
}
