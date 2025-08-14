//
//  SlateEnumUser.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import ExampleEnums
import Foundation

public final class SlateEnumUser: Sendable {
    // -- Attribute Declarations --
    public let id: Int
    public let intEnumNonOptIntNoDef: IntegerEnumExample?
    public let intEnumNonOptIntYesDef: IntegerEnumExample
    public let intEnumNonOptNSNumberNoDef: IntegerEnumExample?
    public let intEnumNonOptNSNumberYesDef: IntegerEnumExample
    public let intEnumOptNSNumberNoDef: IntegerEnumExample?
    public let intEnumOptNSNumberYesDef: IntegerEnumExample
    public let stringEnumNonOptStringNoDef: StringEnumExample?
    public let stringEnumNonOptStringYesDef: StringEnumExample
    public let stringEnumOptStringNoDef: StringEnumExample?
    public let stringEnumOptStringYesDef: StringEnumExample

    // -- Attribute Names --

    public enum Attributes {
        public static let id = "id"
        public static let intEnumNonOptIntNoDef = "intEnumNonOptIntNoDef"
        public static let intEnumNonOptIntYesDef = "intEnumNonOptIntYesDef"
        public static let intEnumNonOptNSNumberNoDef = "intEnumNonOptNSNumberNoDef"
        public static let intEnumNonOptNSNumberYesDef = "intEnumNonOptNSNumberYesDef"
        public static let intEnumOptNSNumberNoDef = "intEnumOptNSNumberNoDef"
        public static let intEnumOptNSNumberYesDef = "intEnumOptNSNumberYesDef"
        public static let stringEnumNonOptStringNoDef = "stringEnumNonOptStringNoDef"
        public static let stringEnumNonOptStringYesDef = "stringEnumNonOptStringYesDef"
        public static let stringEnumOptStringNoDef = "stringEnumOptStringNoDef"
        public static let stringEnumOptStringYesDef = "stringEnumOptStringYesDef"
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
        self.id = Int(managedObject.id)
        self.intEnumNonOptIntNoDef = __convertIntToEnum(managedObject.intEnumNonOptIntNoDef)
        self.intEnumNonOptIntYesDef = __convertIntToEnum(managedObject.intEnumNonOptIntYesDef) ?? .two
        self.intEnumNonOptNSNumberNoDef = __convertNSNumberToEnum(managedObject.intEnumNonOptNSNumberNoDef)
        self.intEnumNonOptNSNumberYesDef = __convertNSNumberToEnum(managedObject.intEnumNonOptNSNumberYesDef) ?? .two
        self.intEnumOptNSNumberNoDef = __convertNSNumberToEnum(managedObject.intEnumOptNSNumberNoDef)
        self.intEnumOptNSNumberYesDef = __convertNSNumberToEnum(managedObject.intEnumOptNSNumberYesDef) ?? .two
        self.stringEnumNonOptStringNoDef = __convertStringToEnum(managedObject.stringEnumNonOptStringNoDef)
        self.stringEnumNonOptStringYesDef = __convertStringToEnum(managedObject.stringEnumNonOptStringYesDef) ?? .hello
        self.stringEnumOptStringNoDef = __convertStringToEnum(managedObject.stringEnumOptStringNoDef)
        self.stringEnumOptStringYesDef = __convertStringToEnum(managedObject.stringEnumOptStringYesDef) ?? .hello
    }

    /**
     Allow the creation of a Slate-exposed class/struct with all of its parameters.
     Note that this is internal -- this is for use only in unit tests (using the
     @testable import directive).  You should never create values with this
     constructor in normal code.
     */
    init(
        id: Int,
        intEnumNonOptIntNoDef: IntegerEnumExample?,
        intEnumNonOptIntYesDef: IntegerEnumExample,
        intEnumNonOptNSNumberNoDef: IntegerEnumExample?,
        intEnumNonOptNSNumberYesDef: IntegerEnumExample,
        intEnumOptNSNumberNoDef: IntegerEnumExample?,
        intEnumOptNSNumberYesDef: IntegerEnumExample,
        stringEnumNonOptStringNoDef: StringEnumExample?,
        stringEnumNonOptStringYesDef: StringEnumExample,
        stringEnumOptStringNoDef: StringEnumExample?,
        stringEnumOptStringYesDef: StringEnumExample
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.id = id
        self.intEnumNonOptIntNoDef = intEnumNonOptIntNoDef
        self.intEnumNonOptIntYesDef = intEnumNonOptIntYesDef
        self.intEnumNonOptNSNumberNoDef = intEnumNonOptNSNumberNoDef
        self.intEnumNonOptNSNumberYesDef = intEnumNonOptNSNumberYesDef
        self.intEnumOptNSNumberNoDef = intEnumOptNSNumberNoDef
        self.intEnumOptNSNumberYesDef = intEnumOptNSNumberYesDef
        self.stringEnumNonOptStringNoDef = stringEnumNonOptStringNoDef
        self.stringEnumNonOptStringYesDef = stringEnumNonOptStringYesDef
        self.stringEnumOptStringNoDef = stringEnumOptStringNoDef
        self.stringEnumOptStringYesDef = stringEnumOptStringYesDef
    }

    // -- Substruct Definitions
}

private func __convertIntToEnum<E: RawRepresentable>(
    _ int: (any BinaryInteger)?
) -> E? where E.RawValue == Int {
    int.flatMap { E(rawValue: Int($0)) }
}

private func __convertNSNumberToEnum<E: RawRepresentable>(
    _ int: NSNumber?
) -> E? where E.RawValue == Int {
    int.flatMap { E(rawValue: $0.intValue) }
}

private let kEnumStringLocale: Locale = .init(identifier: "en_US")

private func __convertStringToEnum<E: RawRepresentable>(
    _ string: String?
) -> E? where E.RawValue == String {
    guard let enumString = string else { return nil }
    if let initial = E(rawValue: enumString) { return initial }
    if let lowercase = E(rawValue: enumString.lowercased(with: kEnumStringLocale)) { return lowercase }
    if let uppercase = E(rawValue: enumString.uppercased(with: kEnumStringLocale)) { return uppercase }
    return nil
}

public extension SlateEnumUser {
    protocol ManagedPropertyProviding: NSManagedObject {
        var id: Int64 { get }
        var intEnumNonOptIntNoDef: Int64 { get }
        var intEnumNonOptIntYesDef: Int64 { get }
        var intEnumNonOptNSNumberNoDef: NSNumber { get }
        var intEnumNonOptNSNumberYesDef: NSNumber { get }
        var intEnumOptNSNumberNoDef: NSNumber? { get }
        var intEnumOptNSNumberYesDef: NSNumber? { get }
        var stringEnumNonOptStringNoDef: String? { get }
        var stringEnumNonOptStringYesDef: String? { get }
        var stringEnumOptStringNoDef: String? { get }
        var stringEnumOptStringYesDef: String? { get }
    }
}

extension SlateEnumUser: Equatable {
    public static func == (lhs: SlateEnumUser, rhs: SlateEnumUser) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.id == rhs.id) &&
            (lhs.intEnumNonOptIntNoDef == rhs.intEnumNonOptIntNoDef) &&
            (lhs.intEnumNonOptIntYesDef == rhs.intEnumNonOptIntYesDef) &&
            (lhs.intEnumNonOptNSNumberNoDef == rhs.intEnumNonOptNSNumberNoDef) &&
            (lhs.intEnumNonOptNSNumberYesDef == rhs.intEnumNonOptNSNumberYesDef) &&
            (lhs.intEnumOptNSNumberNoDef == rhs.intEnumOptNSNumberNoDef) &&
            (lhs.intEnumOptNSNumberYesDef == rhs.intEnumOptNSNumberYesDef) &&
            (lhs.stringEnumNonOptStringNoDef == rhs.stringEnumNonOptStringNoDef) &&
            (lhs.stringEnumNonOptStringYesDef == rhs.stringEnumNonOptStringYesDef) &&
            (lhs.stringEnumOptStringNoDef == rhs.stringEnumOptStringNoDef) &&
            (lhs.stringEnumOptStringYesDef == rhs.stringEnumOptStringYesDef)
    }
}
