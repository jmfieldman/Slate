//
//  SlateTests.swift
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
