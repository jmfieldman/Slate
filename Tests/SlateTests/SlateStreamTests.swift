//
//  SlateStreamTests.swift
//  Copyright © 2025 Jason Fieldman.
//

import Combine
import DatabaseModels
import Foundation
import ImmutableModels
import Slate
import Testing

#if os(iOS) || os(tvOS)
import UIKit
#else
import AppKit
#endif

@Suite(.timeLimit(.minutes(1)))
struct SlateStreamTests {
    let slate = Slate()

    @Test func BasicStreamTest() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestNameAAA"

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestNameCCC"
        }

        let stream = slate.stream { request -> SlateQueryRequest<SlateAuthor> in
            request.sort(SlateAuthor.Attributes.name)
        }

        var cancellables: Set<AnyCancellable> = []
        var results: [Slate.StreamUpdate<SlateAuthor>] = []

        await withCheckedContinuation { continuation in
            let cancellable = stream.sink { _ in
            } receiveValue: { value in
                results.append(value)
                if results.count == 2 {
                    continuation.resume(returning: ())
                }
            }

            cancellables.insert(cancellable)

            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestNameBBB"
            }
        }

        #expect(results.count == 2)

        #expect(results[0].initialUpdate == true)
        #expect(results[0].values.count == 2)
        #expect(results[0].values[0].name == "TestNameAAA")
        #expect(results[0].values[1].name == "TestNameCCC")
        #expect(results[0].insertedIndexes.count == 2)
        #expect(results[0].insertedIndexes[0] == IndexPath(item: 0, section: 0))
        #expect(results[0].insertedIndexes[1] == IndexPath(item: 1, section: 0))
        #expect(results[0].updatedIndexes.count == 0)
        #expect(results[0].deletedIndexes.count == 0)
        #expect(results[0].movedIndexes.count == 0)

        #expect(results[1].initialUpdate == false)
        #expect(results[1].values.count == 3)
        #expect(results[1].values[0].name == "TestNameAAA")
        #expect(results[1].values[1].name == "TestNameBBB")
        #expect(results[1].values[2].name == "TestNameCCC")
        #expect(results[1].insertedIndexes.count == 1)
        #expect(results[1].insertedIndexes[0] == IndexPath(item: 1, section: 0))
        #expect(results[1].updatedIndexes.count == 0)
        #expect(results[1].deletedIndexes.count == 0)
        #expect(results[1].movedIndexes.count == 0)
    }

    @Test func StreamCancellationTest() async {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { moc in
            let newAuthor = CoreDataAuthor(context: moc)
            newAuthor.name = "TestNameAAA"

            let newAuthor2 = CoreDataAuthor(context: moc)
            newAuthor2.name = "TestNameCCC"
        }

        let stream = slate.stream { request -> SlateQueryRequest<SlateAuthor> in
            request.sort(\.name)
        }

        var cancellables: Set<AnyCancellable> = []
        var results: [Slate.StreamUpdate<SlateAuthor>] = []

        await withCheckedContinuation { continuation in
            autoreleasepool {
                let cancellable = stream.sink { _ in
                } receiveValue: { value in
                    results.append(value)
                    if results.count == 2 {
                        continuation.resume(returning: ())
                    }
                }

                cancellables.insert(cancellable)
            }

            Thread.sleep(forTimeInterval: 0.1)

            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestNameBBB"
            }
        }

        cancellables = []

        await withCheckedContinuation { continuation in
            slate.mutateAsync { moc in
                let newAuthor = CoreDataAuthor(context: moc)
                newAuthor.name = "TestNameDDD"
            }

            slate.mutateAsync { _ in
                continuation.resume(returning: ())
            }
        }

        #expect(results.count == 2)

        #expect(results[0].initialUpdate == true)
        #expect(results[0].values.count == 2)
        #expect(results[0].values[0].name == "TestNameAAA")
        #expect(results[0].values[1].name == "TestNameCCC")
        #expect(results[0].insertedIndexes.count == 2)
        #expect(results[0].insertedIndexes[0] == IndexPath(item: 0, section: 0))
        #expect(results[0].insertedIndexes[1] == IndexPath(item: 1, section: 0))
        #expect(results[0].updatedIndexes.count == 0)
        #expect(results[0].deletedIndexes.count == 0)
        #expect(results[0].movedIndexes.count == 0)

        #expect(results[1].initialUpdate == false)
        #expect(results[1].values.count == 3)
        #expect(results[1].values[0].name == "TestNameAAA")
        #expect(results[1].values[1].name == "TestNameBBB")
        #expect(results[1].values[2].name == "TestNameCCC")
        #expect(results[1].insertedIndexes.count == 1)
        #expect(results[1].insertedIndexes[0] == IndexPath(item: 1, section: 0))
        #expect(results[1].updatedIndexes.count == 0)
        #expect(results[1].deletedIndexes.count == 0)
        #expect(results[1].movedIndexes.count == 0)
    }
}
