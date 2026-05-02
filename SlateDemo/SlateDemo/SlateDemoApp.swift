//
//  SlateDemoApp.swift
//  SlateDemo
//
//  Created by Jason Fieldman on 5/1/26.
//

import SwiftUI

@main
struct SlateDemoApp: App {
    @State private var store = DemoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
