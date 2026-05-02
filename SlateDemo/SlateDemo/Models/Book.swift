import CoreData
import Foundation
import SlateSchema

@SlateEntity(
    relationships: [
        .toOne("library", "Library", inverse: "books", deleteRule: .nullify, optional: false),
        .toOne("author", "Author", inverse: "books", deleteRule: .nullify, optional: false),
    ]
)
public struct Book {
    #Unique<Book>([\.bookId])
    #Index<Book>([\.libraryId], [\.authorId], [\.title], [\.acquiredAt])
    
    public enum Format: String, Sendable {
        case hardcover
        case paperback
        case ebook
        case audiobook
        case manuscript
    }

    public let bookId: String
    public let libraryId: String
    public let authorId: String
    public let title: String
    public let subtitle: String?
    public let isbn: String?
    public let publicationYear: Int?
    public let pageCount: Int
    public let rating: Double
    public let isAvailable: Bool
    public let acquiredAt: Date

    @SlateAttribute(default: Book.Format.hardcover)
    public let format: Format

    @SlateEmbedded
    public let catalog: CatalogInfo

    @SlateEmbedded
    public struct CatalogInfo: Sendable, Hashable {
        public let callNumber: String
        public let shelf: String
        public let room: String?

        public init(callNumber: String, shelf: String, room: String?) {
            self.callNumber = callNumber
            self.shelf = shelf
            self.room = room
        }
    }
}
