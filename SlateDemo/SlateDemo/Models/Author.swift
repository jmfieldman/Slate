import CoreData
import Foundation
import SlateSchema

@SlateEntity(
    relationships: [
        .toMany("books", "Book", inverse: "author", deleteRule: .nullify, ordered: true),
    ]
)
public struct Author {
    #Index<Author>([\.sortName], [\.nationality])
    #Unique<Author>([\.authorId])

    public enum Era: String, Sendable {
        case classical
        case modern
        case contemporary
        case emerging
    }

    public let authorId: String
    public let displayName: String
    public let sortName: String
    public let nationality: String?
    public let birthYear: Int?
    public let website: String?
    public let isLiving: Bool

    @SlateAttribute(default: Author.Era.contemporary)
    public let era: Era

    @SlateEmbedded
    public let profile: Profile

    @SlateEmbedded
    public struct Profile: Sendable, Hashable {
        public let shortBio: String
        public let notableAward: String?
        public let favoriteShelf: String?

        public init(shortBio: String, notableAward: String?, favoriteShelf: String?) {
            self.shortBio = shortBio
            self.notableAward = notableAward
            self.favoriteShelf = favoriteShelf
        }
    }
}
