//
//  BasicSlateTests.swift
//  Copyright © 2020 Jason Fieldman.
//

import DatabaseModels
import Foundation
import ImmutableModels
import Slate
import Testing

@Suite(.timeLimit(.minutes(1)))
struct BasicSlateTests {
    let slate = Slate()

    @Test func InstantiateInsertQuery() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        let inserted: Bool = await withCheckedContinuation { continuation in
            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestName"

                continuation.resume(returning: true)
            }
        }

        #expect(inserted)

        let authors: [SlateAuthor] = await withCheckedContinuation { continuation in
            slate.queryAsync { context in
                let authors = try context[SlateAuthor.self].fetch()
                continuation.resume(returning: authors)
            }
        }

        #expect(authors.first!.name == "TestName")
    }

    @Test func InstantiateInsertSyncQuery() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName"
        }

        let authors: [SlateAuthor] = await withCheckedContinuation { continuation in
            slate.queryAsync { context in
                let authors = try context[SlateAuthor.self].fetch()
                continuation.resume(returning: authors)
            }
        }

        #expect(authors.first!.name == "TestName")
    }

    @Test func InstantiateInsertSyncQuerySync() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName"
        }

        let authors: [SlateAuthor] = await withCheckedContinuation { continuation in
            slate.querySync { context in
                let authors = try context[SlateAuthor.self].fetch()
                continuation.resume(returning: authors)
            }
        }

        #expect(authors.first!.name == "TestName")
    }

    @Test func InstantiateInsertAsyncQuery() async throws {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        let inserted: Bool = await withCheckedContinuation { continuation in
            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestName"

                continuation.resume(returning: true)
            }
        }

        #expect(inserted)

        let authors: [SlateAuthor] = try await slate.query { context in
            try context[SlateAuthor.self].fetch()
        }

        #expect(authors.first!.name == "TestName")
    }

    @Test func InstantiateAsyncInsertAsyncQuery() async throws {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        try await slate.mutate { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName"
        }

        let checkResult = try await slate.mutate { moc in
            let author = try moc[CoreDataAuthor.self].fetchOne()!

            let newBook = CoreDataBook(context: moc)
            newBook.title = "BookName"
            newBook.author = author
            return 42
        }

        #expect(checkResult == 42)

        let authors: [SlateAuthor] = try await slate.query { context in
            try context[SlateAuthor.self].fetch()
        }

        let books: [SlateBook] = try await slate.query { context in
            try context[SlateBook.self].fetch()
        }

        #expect(authors.first!.name == "TestName")
        #expect(books.first!.title == "BookName")
    }

    @Test func InstantiateInsertAbortQuery() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        let inserted: Bool = await withCheckedContinuation { continuation in
            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestName"

                continuation.resume(returning: true)
                throw SlateTransactionError.aborted
            }
        }

        #expect(inserted)

        let authors: [SlateAuthor] = await withCheckedContinuation { continuation in
            slate.queryAsync { context in
                let authors = try context[SlateAuthor.self].fetch()
                continuation.resume(returning: authors)
            }
        }

        #expect(authors.count == 0)
    }
}
