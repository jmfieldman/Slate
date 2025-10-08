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

    @Test func QuerySort() async {
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

        slate.querySync { context in
            authors = try context[SlateAuthor.self].sort(SlateAuthor.Attributes.name).fetch()
        }

        #expect(authors.map(\.name) == ["TestName1", "TestName2", "TestName3"])
    }

    @Test func MutateSort() async {
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

            // Sorting inside of a mutable block should know about all
            // objects instantiated inside of this block already.
            let authors = try! moc[CoreDataAuthor.self].sort(\.name).fetch()
            #expect(authors.map(\.name) == ["TestName1", "TestName2", "TestName3"])
        }

        slate.mutateSync { moc in
            let authors = try! moc[CoreDataAuthor.self].sort(SlateAuthor.Attributes.name).fetch()
            #expect(authors.map(\.name) == ["TestName1", "TestName2", "TestName3"])
        }
    }

    @Test func QueryFilterPredicate() async {
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
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .equals("TestName1"))
                .sort(\.name)
                .fetch()
        }

        #expect(authors.map(\.name) == ["TestName1"])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .notEquals("TestName1"))
                .sort(\.name)
                .fetch()
        }

        #expect(authors.map(\.name) == ["TestName2", "TestName3"])
    }

    @Test func QueryWherePredicate() async {
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
            authors = try context[SlateAuthor.self]
                .where(\.name, .equals("TestName1"))
                .sort(\.name)
                .fetch()
        }

        #expect(authors.map(\.name) == ["TestName1"])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .where(\.name, .notEquals("TestName1"))
                .sort(\.name)
                .fetch()
        }

        #expect(authors.map(\.name) == ["TestName2", "TestName3"])
    }

    @Test func QueryWhereMultilevelPredicate() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newParent = CoreDataParent1(context: moc)
            newParent.id = "1"
            newParent.child1_has = false
            newParent.child2_bool = true
            newParent.child2_int64scalar = 3

            let newParent2 = CoreDataParent1(context: moc)
            newParent2.id = "2"
            newParent2.child1_has = false
            newParent2.child2_bool = false
            newParent2.child2_int64scalar = 2

            let newParent3 = CoreDataParent1(context: moc)
            newParent3.id = "3"
            newParent3.child1_has = false
            newParent3.child2_bool = true
            newParent3.child2_int64scalar = 1
        }

        var parents: [SlateParent1] = []

        slate.querySync { context in
            parents = try context[SlateParent1.self]
                .where(\.child2.bool, .equals(true))
                .sort(\.child2.int64scalar, ascending: true)
                .fetch()
        }

        #expect(parents.map(\.child2.int64scalar) == [1, 3])
    }

    @Test func QueryFilterPredicateNullability() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"

            let newBook = CoreDataBook(context: moc)
            newBook.author = newAuthor
            newBook.title = "TestBook1"

            let newBook2 = CoreDataBook(context: moc)
            newBook2.author = newAuthor
            newBook2.title = "TestBook2"

            let newBook3 = CoreDataBook(context: moc)
            newBook3.author = newAuthor
            newBook3.title = "TestBook3"
            newBook3.subtitle = "Subtitle3"
        }

        var books: [SlateBook] = []

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .equals("Subtitle3"))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook3"])

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .equals(nil))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook1", "TestBook2"])

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .notEquals("Subtitle3"))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook1", "TestBook2"])

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .notEquals(nil))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook3"])
    }

    @Test func QueryFilterPredicateAndOrLogic() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"
            newAuthor.age = 10

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestName2"
            newAuthor2.age = 20

            let newAuthor3 = CoreDataAuthor(context: moc)
            newAuthor3.name = "TestName3"
            newAuthor3.age = 30

            let newAuthor4 = CoreDataAuthor(context: moc)
            newAuthor4.name = "TestName4"
            newAuthor4.age = 40
        }

        var authors: [SlateAuthor] = []

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .equals("TestName1"))
                .and(where: \.name, .equals("TestName2"))
                .sort(\.name)
                .fetch()
        }

        // Cannot have both name clauses be true
        #expect(authors.map(\.name) == [])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .equals("TestName1"))
                .or(where: \.name, .equals("TestName2"))
                .sort(\.name)
                .fetch()
        }

        // -or- allows either name to appear
        #expect(authors.map(\.name) == ["TestName1", "TestName2"])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.age, .greaterThan(25))
                .or(where: \.name, .equals("TestName2"))
                .sort(\.name)
                .fetch()
        }

        // age -> 3 and 4
        // name -> 2
        #expect(authors.map(\.name) == ["TestName2", "TestName3", "TestName4"])
    }

    @Test func QueryFilterPredicateContains() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"
            newAuthor.age = 10

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestName2"
            newAuthor2.age = 20

            let newAuthor3 = CoreDataAuthor(context: moc)
            newAuthor3.name = "TestName3"
            newAuthor3.age = 30

            let newAuthor4 = CoreDataAuthor(context: moc)
            newAuthor4.name = "TestName4"
            newAuthor4.age = 40
        }

        var authors: [SlateAuthor] = []

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .in(["TestName1", "TestName2"]))
                .sort(\.name)
                .fetch()
        }

        // Cannot have both name clauses be true
        #expect(authors.map(\.name) == ["TestName1", "TestName2"])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.name, .notIn(["TestName1", "TestName2"]))
                .sort(\.name)
                .fetch()
        }

        // -or- allows either name to appear
        #expect(authors.map(\.name) == ["TestName3", "TestName4"])
    }

    @Test func QueryFilterPredicateBetween() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"
            newAuthor.age = 10

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestName2"
            newAuthor2.age = 20

            let newAuthor3 = CoreDataAuthor(context: moc)
            newAuthor3.name = "TestName3"
            newAuthor3.age = 30

            let newAuthor4 = CoreDataAuthor(context: moc)
            newAuthor4.name = "TestName4"
            newAuthor4.age = 40
        }

        var authors: [SlateAuthor] = []

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.age, .between(20, 30))
                .sort(\.name)
                .fetch()
        }

        // Cannot have both name clauses be true
        #expect(authors.map(\.name) == ["TestName2", "TestName3"])

        slate.querySync { context in
            authors = try context[SlateAuthor.self]
                .filter(where: \.age, .notBetween(20, 30))
                .sort(\.name)
                .fetch()
        }

        // -or- allows either name to appear
        #expect(authors.map(\.name) == ["TestName1", "TestName4"])
    }

    @Test func QueryFilterPredicateLike() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"

            let newBook = CoreDataBook(context: moc)
            newBook.author = newAuthor
            newBook.title = "TestBook1"

            let newBook2 = CoreDataBook(context: moc)
            newBook2.author = newAuthor
            newBook2.title = "TestBook2"

            let newBook3 = CoreDataBook(context: moc)
            newBook3.author = newAuthor
            newBook3.title = "TestBook3"
            newBook3.subtitle = "Subtitle3"
        }

        var books: [SlateBook] = []

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .like("Subt*"))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook3"])

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .like("subt*", "cd"))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook3"])

        slate.querySync { context in
            books = try context[SlateBook.self]
                .filter(where: \.subtitle, .notLike("Subt*"))
                .sort(\.title)
                .fetch()
        }

        #expect(books.map(\.title) == ["TestBook1", "TestBook2"])
    }

    @Test func MutateFilterPredicate() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        var executed = false

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestName1"

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestName3"

            let newAuthor3 = CoreDataAuthor(context: moc)
            newAuthor3.name = "TestName2"

            let authors = try! moc[CoreDataAuthor.self]
                .filter(where: \.name, .equals("TestName1"))
                .sort(\.name)
                .fetch()

            #expect(authors.map(\.name) == ["TestName1"])
            executed = true
        }

        #expect(executed)
    }
}
