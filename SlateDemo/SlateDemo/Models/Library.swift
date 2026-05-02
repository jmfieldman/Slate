import CoreData
import Foundation
import SlateSchema

@SlateEntity(
    relationships: [
        .toMany("books", "Book", inverse: "library", deleteRule: .cascade, ordered: true),
    ]
)
public struct Library {
    #Index<Library>([\.name], [\.city])
    #Index<Library>([\.updatedAt], order: .descending)
    #Unique<Library>([\.libraryId])

    public enum Kind: String, Sendable {
        case publicBranch
        case university
        case archive
        case privateCollection
    }

    public let libraryId: String
    public let name: String
    public let city: String
    public let state: String
    public let foundedYear: Int?
    public let annualVisitors: Int
    public let latitude: Double?
    public let longitude: Double?
    public let isOpenToday: Bool
    public let updatedAt: Date

    @SlateAttribute(default: Library.Kind.publicBranch)
    public let kind: Kind

    @SlateEmbedded
    public let address: Address?

    @SlateEmbedded
    public let hours: Hours

    @SlateEmbedded
    public struct Address: Sendable, Hashable {
        public let street: String?
        public let city: String?
        public let state: String?
        @SlateAttribute(storageName: "zip")
        public let postalCode: String?

        public init(street: String?, city: String?, state: String?, postalCode: String?) {
            self.street = street
            self.city = city
            self.state = state
            self.postalCode = postalCode
        }
    }

    @SlateEmbedded
    public struct Hours: Sendable, Hashable {
        public let opensAt: String
        public let closesAt: String
        public let weekendHours: String?

        public init(opensAt: String, closesAt: String, weekendHours: String?) {
            self.opensAt = opensAt
            self.closesAt = closesAt
            self.weekendHours = weekendHours
        }
    }
}
