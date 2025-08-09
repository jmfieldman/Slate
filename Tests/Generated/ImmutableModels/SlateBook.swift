//
//  SlateBook.swift
//  Copyright © 2025 Jason Fieldman.
//

import CoreData
import Foundation

public final class SlateBook: Sendable {
    // -- Attribute Declarations --
    public let likeCount: Int
    public let loading: Bool
    public let subtitle: String?
    public let title: String

    // -- Attribute Names --

    public enum Attributes {
        public static let likeCount = "likeCount"
        public static let loading = "loading"
        public static let subtitle = "subtitle"
        public static let title = "title"
    }

    public enum Relationships {
        public static let author = "author"
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
        self.likeCount = Int(managedObject.likeCount)
        self.loading = managedObject.loading
        self.subtitle = managedObject.subtitle
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
        likeCount: Int,
        loading: Bool,
        subtitle: String?,
        title: String
    ) {
        // Internally created objects have no real managed object ID
        self.slateID = NSManagedObjectID()

        self.likeCount = likeCount
        self.loading = loading
        self.subtitle = subtitle
        self.title = title
    }

    // -- Substruct Definitions
}

public extension SlateBook {
    protocol ManagedPropertyProviding: NSManagedObject {
        var likeCount: Int64 { get }
        var loading: Bool { get }
        var subtitle: String? { get }
        var title: String? { get }
    }
}

extension SlateBook: Equatable {
    public static func == (lhs: SlateBook, rhs: SlateBook) -> Bool {
        (lhs.slateID == rhs.slateID) &&
            (lhs.likeCount == rhs.likeCount) &&
            (lhs.loading == rhs.loading) &&
            (lhs.subtitle == rhs.subtitle) &&
            (lhs.title == rhs.title)
    }
}
