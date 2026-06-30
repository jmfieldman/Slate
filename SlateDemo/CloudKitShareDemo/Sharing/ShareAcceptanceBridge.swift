@preconcurrency import CloudKit
import Foundation

/// Bridges CloudKit share-acceptance callbacks (delivered to the `AppDelegate`)
/// into the `NotesStore`.
///
/// When someone taps a share link, the system launches the app and hands the
/// `AppDelegate` a `CKShare.Metadata`. That can arrive *before* the store has
/// finished configuring, so this bridge buffers metadata until `NotesStore`
/// registers its handler, then flushes. Everything runs on the main actor, where
/// both the delegate callback and the store live.
@MainActor
final class ShareAcceptanceBridge {
    static let shared = ShareAcceptanceBridge()

    private var handler: ((CKShare.Metadata) -> Void)?
    private var buffered: [CKShare.Metadata] = []

    private init() {}

    /// Registers the consumer (the store) and flushes anything received early.
    func setHandler(_ handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler
        let pending = buffered
        buffered.removeAll()
        for metadata in pending {
            handler(metadata)
        }
    }

    /// Called from the `AppDelegate` when a share link is opened.
    func accept(_ metadata: CKShare.Metadata) {
        if let handler {
            handler(metadata)
        } else {
            buffered.append(metadata)
        }
    }
}
