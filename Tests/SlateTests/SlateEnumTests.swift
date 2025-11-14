//
//  SlateEnumTests.swift
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
struct SlateEnumTests {
    let slate = Slate()

    @Test func BasicEnumTest() async throws {
        await ConfigureTest(
            slate: slate,
            mom: kMomSlateTests
        )

        slate.mutateSync { context in
            // Test normal assignment
            let newEnumUser = context.create(CoreDataEnumUser.self)
            newEnumUser.id = 1
            newEnumUser.intEnumNonOptIntNoDef = 1
            newEnumUser.intEnumNonOptIntYesDef = 1
            newEnumUser.intEnumNonOptNSNumberNoDef = 1
            newEnumUser.intEnumNonOptNSNumberYesDef = 1
            newEnumUser.intEnumOptNSNumberNoDef = .init(1)
            newEnumUser.intEnumOptNSNumberYesDef = .init(1)
            newEnumUser.stringEnumNonOptStringNoDef = "world"
            newEnumUser.stringEnumNonOptStringYesDef = "world"
            newEnumUser.stringEnumOptStringNoDef = "world"
            newEnumUser.stringEnumOptStringYesDef = "world"

            // Test what happens when there are zero values assigned
            let newEnumUser2 = context.create(CoreDataEnumUser.self)
            newEnumUser2.id = 2

            // Test what happens when there are completely incorrect assignments
            let newEnumUser3 = context.create(CoreDataEnumUser.self)
            newEnumUser3.id = 3
            newEnumUser3.intEnumNonOptIntNoDef = 10
            newEnumUser3.intEnumNonOptIntYesDef = 10
            newEnumUser3.intEnumNonOptNSNumberNoDef = 10
            newEnumUser3.intEnumNonOptNSNumberYesDef = 10
            newEnumUser3.intEnumOptNSNumberNoDef = .init(10)
            newEnumUser3.intEnumOptNSNumberYesDef = .init(10)
            newEnumUser3.stringEnumNonOptStringNoDef = "world10"
            newEnumUser3.stringEnumNonOptStringYesDef = "world10"
            newEnumUser3.stringEnumOptStringNoDef = "world10"
            newEnumUser3.stringEnumOptStringYesDef = "world10"
        }

        let result = try await slate.query { context in
            try context[SlateEnumUser.self].sort(\.id).fetch()
        }

        #expect(result.count == 3)

        #expect(result[0].intEnumNonOptIntNoDef == .one)
        #expect(result[0].intEnumNonOptIntYesDef == .one)
        #expect(result[0].intEnumNonOptNSNumberNoDef == .one)
        #expect(result[0].intEnumNonOptNSNumberYesDef == .one)
        #expect(result[0].intEnumOptNSNumberNoDef == .one)
        #expect(result[0].intEnumOptNSNumberYesDef == .one)
        #expect(result[0].stringEnumNonOptStringNoDef == .world)
        #expect(result[0].stringEnumNonOptStringYesDef == .world)
        #expect(result[0].stringEnumOptStringNoDef == .world)
        #expect(result[0].stringEnumOptStringYesDef == .world)

        #expect(result[1].intEnumNonOptIntNoDef == .zero)
        #expect(result[1].intEnumNonOptIntYesDef == .zero)
        #expect(result[1].intEnumNonOptNSNumberNoDef == .zero)
        #expect(result[1].intEnumNonOptNSNumberYesDef == .zero)
        #expect(result[1].intEnumOptNSNumberNoDef == nil)
        #expect(result[1].intEnumOptNSNumberYesDef == .zero)
        #expect(result[1].stringEnumNonOptStringNoDef == nil)
        #expect(result[1].stringEnumNonOptStringYesDef == .hello)
        #expect(result[1].stringEnumOptStringNoDef == nil)
        #expect(result[1].stringEnumOptStringYesDef == .hello)

        #expect(result[2].intEnumNonOptIntNoDef == nil)
        #expect(result[2].intEnumNonOptIntYesDef == .two)
        #expect(result[2].intEnumNonOptNSNumberNoDef == nil)
        #expect(result[2].intEnumNonOptNSNumberYesDef == .two)
        #expect(result[2].intEnumOptNSNumberNoDef == nil)
        #expect(result[2].intEnumOptNSNumberYesDef == .two)
        #expect(result[2].stringEnumNonOptStringNoDef == nil)
        #expect(result[2].stringEnumNonOptStringYesDef == .hello)
        #expect(result[2].stringEnumOptStringNoDef == nil)
        #expect(result[2].stringEnumOptStringYesDef == .hello)
    }
}
