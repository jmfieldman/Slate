import Foundation
import Observation
import Slate

struct LibraryPayload: Sendable, Identifiable {
    let id: String
    let name: String
    let city: String
    let state: String
    let foundedYear: Int?
    let annualVisitors: Int
    let latitude: Double?
    let longitude: Double?
    let isOpenToday: Bool
    let kind: Library.Kind
    let address: Library.Address?
    let hours: Library.Hours
    let updatedAt: Date
}

struct BookAuthorPayload: Sendable, Identifiable {
    let id: String
    let book: BookPayload
    let author: AuthorPayload
}

struct BookPayload: Sendable {
    let bookId: String
    let libraryId: String
    let authorId: String
    let title: String
    let subtitle: String?
    let isbn: String?
    let publicationYear: Int?
    let pageCount: Int
    let rating: Double
    let isAvailable: Bool
    let format: Book.Format
    let catalog: Book.CatalogInfo
    let acquiredAt: Date
}

struct AuthorPayload: Sendable {
    let authorId: String
    let displayName: String
    let sortName: String
    let nationality: String?
    let birthYear: Int?
    let website: String?
    let isLiving: Bool
    let era: Author.Era
    let profile: Author.Profile
}

enum DemoNetwork {
    static func libraryPage(_ page: Int, pageSize: Int) async throws -> [LibraryPayload] {
        try await Task.sleep(for: .seconds(3))
        let names = [
            "Aster Reading Room", "Bay Laurel Library", "Civic Stacks", "Dovetail Archive",
            "Elm & Ink Branch", "Foundry Library", "Garden Court Collection", "Harbor University Library",
            "Iris Public Library", "Juniper Manuscripts", "Keystone Library", "Lantern Hall",
        ]
        let cities = [
            ("Portland", "OR"), ("Madison", "WI"), ("Savannah", "GA"), ("Santa Fe", "NM"),
            ("Burlington", "VT"), ("Pasadena", "CA"), ("Asheville", "NC"), ("Ann Arbor", "MI"),
        ]
        let kinds: [Library.Kind] = [.publicBranch, .university, .archive, .privateCollection]
        let start = page * pageSize

        return (0..<pageSize).map { offset in
            let index = start + offset
            let city = cities[index % cities.count]
            return LibraryPayload(
                id: "library-\(index)",
                name: "\(names[index % names.count]) \(index + 1)",
                city: city.0,
                state: city.1,
                foundedYear: 1880 + (index * 7) % 130,
                annualVisitors: 42_000 + index * 6_700,
                latitude: 32.0 + Double(index % 19) * 1.7,
                longitude: -122.0 + Double(index % 23) * 2.1,
                isOpenToday: index % 5 != 0,
                kind: kinds[index % kinds.count],
                address: Library.Address(
                    street: "\(100 + index) \(["Maple", "Cedar", "Pine", "Walnut"][index % 4]) Street",
                    city: city.0,
                    state: city.1,
                    postalCode: String(format: "%05d", 90000 + index)
                ),
                hours: Library.Hours(
                    opensAt: index % 3 == 0 ? "10:00 AM" : "9:00 AM",
                    closesAt: index % 4 == 0 ? "6:00 PM" : "8:00 PM",
                    weekendHours: index % 2 == 0 ? "10:00 AM - 5:00 PM" : nil
                ),
                updatedAt: Date().addingTimeInterval(Double(-index * 3600))
            )
        }
    }

    static func books(for library: Library) async throws -> [BookAuthorPayload] {
        try await Task.sleep(for: .seconds(3))
        let authors = authorPool(for: library)
        let titles = [
            "The Quiet Index", "Margins of the City", "Borrowed Light", "A Catalog of Rain",
            "The Orchard Map", "Notes from the Upper Room", "A History of Small Fires", "The Last Folio",
        ]
        let formats: [Book.Format] = [.hardcover, .paperback, .ebook, .audiobook, .manuscript]

        return titles.enumerated().map { index, title in
            let author = authors[index % authors.count]
            let bookId = "\(library.libraryId)-book-\(index)"
            return BookAuthorPayload(
                id: bookId,
                book: BookPayload(
                    bookId: bookId,
                    libraryId: library.libraryId,
                    authorId: author.authorId,
                    title: title,
                    subtitle: index % 3 == 0 ? "Collected notes from \(library.city)" : nil,
                    isbn: "978-\(1000000000 + abs(bookId.hashValue % 899999999))",
                    publicationYear: 1978 + (index * 6 + library.libraryId.count) % 45,
                    pageCount: 160 + index * 47,
                    rating: 3.7 + Double(index % 4) * 0.3,
                    isAvailable: index % 4 != 1,
                    format: formats[index % formats.count],
                    catalog: Book.CatalogInfo(
                        callNumber: "\(String(library.city.prefix(2)).uppercased()) \(800 + index).\(index)",
                        shelf: ["Oak", "Brass", "North", "Reading"][index % 4],
                        room: index % 2 == 0 ? "Main Hall" : "Annex"
                    ),
                    acquiredAt: Date().addingTimeInterval(Double(-index * 86_400))
                ),
                author: author
            )
        }
    }

    private static func authorPool(for library: Library) -> [AuthorPayload] {
        let shared = [
            author("ada-lim", "Ada Lim", "Lim, Ada", "Singaporean", 1978, .contemporary, "Writes compact essays about civic memory.", "Penfield Prize"),
            author("mara-vale", "Mara Vale", "Vale, Mara", "Canadian", 1962, .modern, "Known for lyrical urban histories.", nil),
            author("elio-rivera", "Elio Rivera", "Rivera, Elio", "Mexican", 1984, .contemporary, "Blends archival research with fiction.", "Northstar Medal"),
        ]
        let local = author(
            "local-\(library.libraryId)",
            "\(library.city) Fielding",
            "Fielding, \(library.city)",
            "American",
            1991,
            .emerging,
            "A local voice collected by \(library.name).",
            nil
        )
        return shared + [local]
    }

    private static func author(
        _ id: String,
        _ displayName: String,
        _ sortName: String,
        _ nationality: String?,
        _ birthYear: Int?,
        _ era: Author.Era,
        _ bio: String,
        _ award: String?
    ) -> AuthorPayload {
        AuthorPayload(
            authorId: id,
            displayName: displayName,
            sortName: sortName,
            nationality: nationality,
            birthYear: birthYear,
            website: "https://example.com/\(id)",
            isLiving: true,
            era: era,
            profile: Author.Profile(shortBio: bio, notableAward: award, favoriteShelf: "Literary essays")
        )
    }
}

@MainActor
@Observable
final class DemoStore {
    private let slate: Slate<DemoSlateSchema>
    private var nextLibraryPage = 0
    private let pageSize = 8

    var libraryStream: SlateStream<Library>?
    var isConfigured = false
    var isLoadingLibraries = false
    var errorMessage: String?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlateDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("SlateDemo.sqlite")
        slate = Slate<DemoSlateSchema>(storeURL: storeURL, storeKind: .cacheStore)
    }

    func configure() async {
        guard !isConfigured else { return }
        do {
            try slate.configure()
            libraryStream = slate.stream(Library.self, sort: [\.name])
            isConfigured = true
            if try await slate.count(Library.self) == 0 {
                await loadMoreLibraries()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreLibraries() async {
        guard isConfigured, !isLoadingLibraries else { return }
        isLoadingLibraries = true
        defer { isLoadingLibraries = false }

        do {
            let page = nextLibraryPage
            let payloads = try await DemoNetwork.libraryPage(page, pageSize: pageSize)
            try await ingestLibraries(payloads)
            nextLibraryPage = page + 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bookStream(for library: Library) -> SlateStream<Book> {
        slate.stream(
            Book.self,
            where: \.libraryId == library.libraryId,
            sort: [\.title],
            relationships: [\.author]
        )
    }

    func authorBookStream(for author: Author) -> SlateStream<Book> {
        slate.stream(
            Book.self,
            where: \.authorId == author.authorId,
            sort: [\.title],
            relationships: [\.library, \.author]
        )
    }

    func bookStream(bookId: String) -> SlateStream<Book> {
        slate.stream(Book.self, where: \.bookId == bookId)
    }

    func toggleLike(bookId: String) async {
        do {
            try await slate.mutate { context in
                guard let row = try context[DatabaseBook.self]
                    .where(\.bookId == bookId)
                    .one()
                else { return }
                row.like.toggle()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshBooks(for library: Library) async {
        do {
            let payloads = try await DemoNetwork.books(for: library)
            try await ingestBooks(payloads, libraryId: library.libraryId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteDatabase() async {
        do {
            _ = try await slate.batchDelete(Book.self)
            _ = try await slate.batchDelete(Author.self)
            _ = try await slate.batchDelete(Library.self)
            nextLibraryPage = 0
            await loadMoreLibraries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ingestLibraries(_ payloads: [LibraryPayload]) async throws {
        try await slate.mutate { context in
            for payload in payloads {
                let row = try context[DatabaseLibrary.self].upsert(\.libraryId, payload.id)
                row.libraryId = payload.id
                row.name = payload.name
                row.city = payload.city
                row.state = payload.state
                row.foundedYear = payload.foundedYear
                row.annualVisitors = payload.annualVisitors
                row.latitude = payload.latitude
                row.longitude = payload.longitude
                row.isOpenToday = payload.isOpenToday
                row.kind = payload.kind
                row.updatedAt = payload.updatedAt
                row.address_has = payload.address != nil
                row.address_street = payload.address?.street
                row.address_city = payload.address?.city
                row.address_state = payload.address?.state
                row.zip = payload.address?.postalCode
                row.hours_opensAt = payload.hours.opensAt
                row.hours_closesAt = payload.hours.closesAt
                row.hours_weekendHours = payload.hours.weekendHours
            }
        }
    }

    private func ingestBooks(_ payloads: [BookAuthorPayload], libraryId: String) async throws {
        try await slate.mutate { context in
            guard let library = try context[DatabaseLibrary.self]
                .where(\.libraryId == libraryId)
                .one()
            else { return }

            let incomingBookIds = Set(payloads.map(\.book.bookId))
            _ = try context[DatabaseBook.self]
                .where(\.libraryId == libraryId)
                .deleteMissing(key: \.bookId, keeping: incomingBookIds, emptySetDeletesAll: true)

            for payload in payloads {
                let author = try context[DatabaseAuthor.self].upsert(\.authorId, payload.author.authorId)
                author.authorId = payload.author.authorId
                author.displayName = payload.author.displayName
                author.sortName = payload.author.sortName
                author.nationality = payload.author.nationality
                author.birthYear = payload.author.birthYear
                author.website = payload.author.website
                author.isLiving = payload.author.isLiving
                author.era = payload.author.era
                author.profile_shortBio = payload.author.profile.shortBio
                author.profile_notableAward = payload.author.profile.notableAward
                author.profile_favoriteShelf = payload.author.profile.favoriteShelf

                let book = try context[DatabaseBook.self].upsert(\.bookId, payload.book.bookId)
                book.bookId = payload.book.bookId
                book.libraryId = payload.book.libraryId
                book.authorId = payload.book.authorId
                book.title = payload.book.title
                book.subtitle = payload.book.subtitle
                book.isbn = payload.book.isbn
                book.publicationYear = payload.book.publicationYear
                book.pageCount = payload.book.pageCount
                book.rating = payload.book.rating
                book.isAvailable = payload.book.isAvailable
                book.format = payload.book.format
                book.acquiredAt = payload.book.acquiredAt
                book.catalog_callNumber = payload.book.catalog.callNumber
                book.catalog_shelf = payload.book.catalog.shelf
                book.catalog_room = payload.book.catalog.room
                book.library = library
                book.author = author
            }
        }
    }
}
