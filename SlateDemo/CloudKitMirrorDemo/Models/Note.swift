import Foundation
import SlateSchema

/// A single note: a `title` and a `content` body.
///
/// `CloudKitMirrorDemo` exists to show Slate's CloudKit mirroring: with the same
/// iCloud account on two devices, notes sync automatically. This first pass runs
/// the app against a **local** store so the UI works immediately without any
/// CloudKit provisioning. The model below is already written to satisfy
/// CloudKit's required subset, so enabling sync (pass 2) is a mechanical flip:
///
///   1. Add the iCloud + CloudKit capability/entitlement and a container.
///   2. Change `@SlateEntity()` to `@SlateEntity(cloudKit: true)` below.
///   3. Re-run the generator (`./generate_cloudkit_demo.sh`).
///   4. Switch the store's `storageMode` from `.local` to
///      `.cloudKitMirrored(containerIdentifier:)` in `NotesStore`.
///
/// CloudKit-subset rules already honored here: every attribute is optional or
/// carries a default, there is no `#Unique` constraint (CloudKit forbids them —
/// `noteId` uses `#Index` instead), and there are no ordered relationships.
@SlateEntity()
public struct Note {
    #Index<Note>([\.noteId], [\.modifiedAt])

    /// Stable identifier assigned once at creation. Used to re-fetch a note for
    /// streaming, editing, and deletion. Indexed (not unique) so the model stays
    /// CloudKit-compatible.
    @SlateAttribute(default: "")
    public let noteId: String

    @SlateAttribute(default: "")
    public let title: String

    @SlateAttribute(default: "")
    public let content: String

    /// Optional because CloudKit requires every attribute to be optional or carry
    /// a literal default, and `Date()` is not a lowerable default. Always set in
    /// code, so they are effectively non-nil at runtime.
    public let createdAt: Date?
    public let modifiedAt: Date?
}
