//
//  CloudKitMirrorDemoApp.swift
//  CloudKitMirrorDemo
//
//  A minimal notes app that demonstrates Slate's CloudKit mirroring.
//

import SwiftUI

@main
struct CloudKitMirrorDemoApp: App {
    @State private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
