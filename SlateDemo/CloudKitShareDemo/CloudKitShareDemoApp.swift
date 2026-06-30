//
//  CloudKitShareDemoApp.swift
//  CloudKitShareDemo
//
//  A minimal notes app that demonstrates Slate's CloudKit sharing: share a note
//  you own with another iCloud user, and edits sync to both apps.
//

@preconcurrency import CloudKit
import SwiftUI
import UIKit

@main
struct CloudKitShareDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

/// Wires up a custom scene delegate.
///
/// A SwiftUI `WindowGroup` app is *scene*-based, so CloudKit delivers an accepted
/// share to the **scene** delegate's `windowScene(_:userDidAcceptCloudKitShareWith:)`
/// — `application(_:userDidAcceptCloudKitShareWith:)` is never called for this app
/// lifecycle. We point the connecting scene at `SceneDelegate` so the callback
/// actually lands. SwiftUI keeps managing the window; this only adds the hook.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Receives the CloudKit share-acceptance callback when the invitee opens a share
/// link, and forwards the metadata to `NotesStore` through `ShareAcceptanceBridge`
/// (which buffers it until the store has configured). It deliberately does not
/// implement `scene(_:willConnectTo:)`, so SwiftUI still owns the window.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        // Scene-delegate callbacks run on the main thread, where the bridge lives.
        MainActor.assumeIsolated {
            ShareAcceptanceBridge.shared.accept(cloudKitShareMetadata)
        }
    }
}
