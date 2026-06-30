@preconcurrency import CloudKit
import CoreData
import Foundation
import Observation
import Slate

/// Owns the Slate store and exposes the note + sharing operations the UI needs.
///
/// ## CloudKit sharing
///
/// The store is opened in `.cloudKitShared` mode. Unlike `.cloudKitMirrored`
/// (one private database that follows a single iCloud account across that user's
/// own devices), shared mode provisions **two** stores backed by CloudKit:
///
/// - a **private** store — the notes you create and own, and
/// - a **shared** store — notes other people have shared *with* you and you have
///   accepted.
///
/// A single `slate.stream(Note.self, …)` fetches across both stores, so the list
/// shows owned and shared-with-me notes together — no per-store query code. When
/// either side edits a note, `NSPersistentCloudKitContainer` pushes the change to
/// the shared CloudKit zone and the other side's stream republishes.
///
/// Sharing itself is three Slate calls: `sharing.prepareShare(for:)` to mint a
/// `CKShare` to hand to `UICloudSharingController`, `sharing.acceptShare(_:)` when
/// an invitee opens a share link, and `sharing.stopSharing(_:)` to revoke. The
/// only remaining work is provisioning (signing team + the iCloud/CloudKit
/// container); the entitlements/Info.plist are already in the target. See
/// `SlateDemo/README.md`.
///
/// On an unprovisioned simulator the local stores still load and the app works
/// offline; it simply can't sync or share without an account/container.
@MainActor
@Observable
final class NotesStore {
    /// The CloudKit container this demo shares through once provisioned.
    static let cloudKitContainerIdentifier = "iCloud.org.fieldman.CloudKitShareDemo"

    /// CloudKit-shared: provisions a private store (owned notes) and a shared
    /// store (notes shared with you). Requires the target to be provisioned for
    /// the container below (signing team + iCloud capability).
    static let storageMode: SlateStorageMode =
        .cloudKitShared(containerIdentifier: cloudKitContainerIdentifier)

    /// Core Data configuration name Slate gives the shared store. Used to tell an
    /// owned note (private store) apart from one shared with you, without an async
    /// CloudKit round-trip. Mirrors `SlateCloudKitContainer.sharedStoreConfigurationName`.
    private static let sharedStoreConfigurationName = "SlateCloudKitSharedStore"

    private let slate: Slate<CloudKitShareSchema>

    /// Live, modification-time-descending stream of every note across the private
    /// and shared stores. Republishes on local writes and on remote imports.
    var notesStream: SlateStream<Note>?
    var isConfigured = false
    var errorMessage: String?

    /// `true` when the store is configured for CloudKit. Drives the sync footer.
    var isCloudKitEnabled: Bool {
        switch Self.storageMode {
        case .local: false
        case .cloudKitMirrored, .cloudKitShared: true
        }
    }

    /// Live iCloud account status reported by the CloudKit stack.
    var accountStatus: SlateAccountStatus { slate.accountStatus }

    /// `true` while CloudKit is importing remote changes or merging them in.
    var isSyncing: Bool { slate.isImporting || slate.isMerging }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudKitShareDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CloudKitShareDemo.sqlite")
        // `.strict` (not `.cacheStore`): CloudKit rejects `.cacheStore`.
        slate = Slate<CloudKitShareSchema>(
            storeURL: storeURL,
            storeKind: .strict,
            storageMode: Self.storageMode
        )
    }

    func configure() async {
        guard !isConfigured else { return }
        do {
            try slate.configure()
            notesStream = slate.stream(Note.self, sort: [.desc(\.modifiedAt)])
            isConfigured = true
            // The store is loaded; drain any share-acceptance metadata that
            // arrived (or arrives) from a tapped CloudKit share link.
            ShareAcceptanceBridge.shared.setHandler { [weak self] metadata in
                Task { await self?.acceptShare(metadata) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A live single-note stream so the detail screen reflects edits made on the
    /// other side of a share while it's open.
    func noteStream(noteId: String) -> SlateStream<Note> {
        slate.stream(Note.self, where: \.noteId == noteId)
    }

    // MARK: - Notes

    /// Creates an empty note (in the private store) and returns its identifier so
    /// the caller can navigate straight into it.
    @discardableResult
    func createNote() async -> String? {
        let id = UUID().uuidString
        let now = Date()
        do {
            try await slate.mutate { context in
                let note = context.create(DatabaseNote.self)
                note.noteId = id
                note.title = ""
                note.content = ""
                note.createdAt = now
                note.modifiedAt = now
            }
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Commits an edit. The title is derived from the first non-empty line of the
    /// content (Apple Notes style), and `modifiedAt` is bumped so the note floats
    /// to the top of the list. Works the same for an owned note and a note shared
    /// with you (given write permission) — Slate routes the write to whichever
    /// store holds the row.
    func updateNote(noteId: String, content: String) async {
        let now = Date()
        let title = Self.derivedTitle(from: content)
        do {
            try await slate.mutate { context in
                guard let row = try context[DatabaseNote.self].where(\.noteId == noteId).one() else { return }
                row.title = title
                row.content = content
                row.modifiedAt = now
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNote(noteId: String) async {
        do {
            try await slate.mutate { context in
                _ = try context[DatabaseNote.self].delete(where: \.noteId == noteId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sharing

    /// `true` if this note was shared with you by someone else (it lives in the
    /// shared store). You can read/edit it, but only its owner can manage sharing.
    func isSharedWithMe(_ note: Note) -> Bool {
        note.slateID.persistentStore?.configurationName == Self.sharedStoreConfigurationName
    }

    /// Mints (or fetches the existing) `CKShare` for an owned note and returns
    /// everything `UICloudSharingController` needs to present the share sheet.
    /// Returns `nil` (and surfaces a message) if the note can't be shared — e.g.
    /// it was shared with you, so you don't own it.
    func prepareShare(for note: Note) async -> ShareInvitation? {
        let title = Self.shareTitle(for: note)
        do {
            let sharing = try slate.sharing
            let (share, container) = try await sharing.prepareShare(for: note, title: title)
            // A fresh CKShare defaults to `publicPermission == .none`: only people
            // you explicitly invite can open the link. The collaboration UI that
            // would invite participants / enable a public link ("Invite with Link")
            // is unreliable on the Simulator, so make the share open to anyone with
            // the link here. With this, a copied link works for any iCloud account —
            // no invites needed. (The note still lives in the owner's *private*
            // database; only the share link is public.)
            if share.publicPermission != .readWrite {
                share.publicPermission = .readWrite
                try await Self.saveShare(share, in: container)
            }
            return ShareInvitation(share: share, container: container, title: title)
        } catch {
            errorMessage = Self.shareErrorMessage(for: error)
            return nil
        }
    }

    /// Persists changes to a `CKShare` (here, its `publicPermission`) to the
    /// owner's private CloudKit database. Mirrors how Slate's own live sharing
    /// test saves a share.
    private static func saveShare(_ share: CKShare, in container: CKContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    /// Accepts an incoming share invitation. The shared note lands in the shared
    /// store and shows up in `notesStream`.
    func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            try await slate.sharing.acceptShare(metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Title CloudKit shows in the share sheet / invitation.
    static func shareTitle(for note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Shared Note" : trimmed
    }

    /// First non-empty line of `content`, trimmed — used as the note's title.
    static func derivedTitle(from content: String) -> String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func shareErrorMessage(for error: Error) -> String {
        if case SlateError.sharingObjectWrongStore = error {
            return "This note was shared with you, so only its owner can manage sharing."
        }
        return error.localizedDescription
    }
}

/// Everything `UICloudSharingController` needs to present a note's share sheet.
/// Identifiable so it can drive a SwiftUI `.sheet(item:)`.
struct ShareInvitation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
    let title: String
}
