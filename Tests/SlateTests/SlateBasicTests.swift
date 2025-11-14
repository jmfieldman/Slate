//
//  SlateBasicTests.swift
//  Copyright © 2020 Jason Fieldman.
//

import DatabaseModels
import Foundation
import ImmutableModels
import Slate
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SlateBasicTests {
    let slate = Slate()

    @Test func InstantiateInsertQuery() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        let inserted: Bool = await withCheckedContinuation { continuation in
            slate.mutateAsync { context in
                let newAuthor = context.create(CoreDataAuthor.self)
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

        slate.mutateSync { context in
            let newAuthor = context.create(CoreDataAuthor.self)
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

        slate.mutateSync { context in
            let newAuthor = context.create(CoreDataAuthor.self)
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
            slate.mutateAsync { context in
                let newAuthor = context.create(CoreDataAuthor.self)
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

        try await slate.mutate { context in
            let newAuthor = context.create(CoreDataAuthor.self)
            newAuthor.name = "TestName"
        }

        let checkResult = try await slate.mutate { context in
            let author = try context[CoreDataAuthor.self].fetchOne()!

            let newBook = context.create(CoreDataBook.self)
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
            slate.mutateAsync { context in
                let newAuthor = context.create(CoreDataAuthor.self)
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
