//
//  SlateFetchTests.swift
//  Copyright © 2025 Jason Fieldman.
//

import DatabaseModels
import Foundation
import ImmutableModels
import Slate
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SlateFetchTests {
    let slate = Slate()

    @Test func InstantiateInsertQuery() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestName3"

            let newAuthor3 = CoreDataAuthor(context: moc)
            newAuthor3.name = "TestName2"
        }

        var authors: [SlateAuthor] = []
        slate.querySync { context in
            authors = try context[SlateAuthor.self].sort(\.name).fetch()
        }

        #expect(authors.map(\.name) == ["TestName1", "TestName2", "TestName3"])
    }
}
