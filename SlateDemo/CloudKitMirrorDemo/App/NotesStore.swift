import Foundation
import Observation
import Slate

/// Owns the Slate store and exposes the note operations the UI needs.
///
/// ## CloudKit mirroring
///
/// The store is opened in `.cloudKitMirrored` mode, so Slate mirrors the same
/// Core Data stack to the private CloudKit database. No UI or query code knows
/// about CloudKit — `notesStream` republishes whenever CloudKit imports remote
/// changes, so two devices signed into the same iCloud account see each other's
/// notes automatically. The only remaining work is provisioning (signing team +
/// the iCloud/CloudKit container); the entitlements/Info.plist are already in the
/// target. See `SlateDemo/README.md`.
///
/// On an unprovisioned simulator the local store still loads and the app works
/// offline; it simply can't sync without an account/container.
@MainActor
@Observable
final class NotesStore {
    /// The CloudKit container this demo will mirror to once provisioned (pass 2).
    static let cloudKitContainerIdentifier = "iCloud.org.fieldman.CloudKitMirrorDemo"

    /// CloudKit-mirrored: every write is mirrored to the private CloudKit
    /// database, and remote changes import back into `notesStream`. Requires the
    /// target to be provisioned for the container below (signing team + iCloud
    /// capability). To run purely locally again, set this to `.local` and revert
    /// `Note` to `@SlateEntity()` (regenerate) — the schema's `cloudKitEnabled`
    /// flag must match the storage mode.
    static let storageMode: SlateStorageMode =
        .cloudKitMirrored(containerIdentifier: cloudKitContainerIdentifier)

    private let slate: Slate<CloudKitMirrorSchema>

    /// Live, modification-time-descending stream of every note. Republishes on
    /// local writes and, once CloudKit is enabled, on remote imports too.
    var notesStream: SlateStream<Note>?
    var isConfigured = false
    var errorMessage: String?

    /// `true` when the store is configured for CloudKit mirroring. Drives the sync
    /// status footer. Derived from the storage mode so it stays honest.
    var isCloudKitEnabled: Bool {
        switch Self.storageMode {
        case .local: false
        case .cloudKitMirrored, .cloudKitShared: true
        }
    }

    /// Live iCloud account status reported by the CloudKit mirroring stack.
    var accountStatus: SlateAccountStatus { slate.accountStatus }

    /// `true` while CloudKit is importing remote changes or merging them in.
    var isSyncing: Bool { slate.isImporting || slate.isMerging }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudKitMirrorDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CloudKitMirrorDemo.sqlite")
        // `.strict` (not `.cacheStore`) so the same store kind works in pass 2:
        // CloudKit mirroring rejects `.cacheStore`.
        slate = Slate<CloudKitMirrorSchema>(
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A live single-note stream so the detail screen reflects edits made on
    /// other devices while it's open.
    func noteStream(noteId: String) -> SlateStream<Note> {
        slate.stream(Note.self, where: \.noteId == noteId)
    }

    /// Creates an empty note and returns its identifier so the caller can
    /// navigate straight into it.
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
    /// to the top of the list.
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

    /// First non-empty line of `content`, trimmed — used as the note's title.
    static func derivedTitle(from content: String) -> String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
