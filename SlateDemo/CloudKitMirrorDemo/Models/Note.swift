import Foundation
import SlateSchema

/// A single note: a `title` and a `content` body.
///
/// `CloudKitMirrorDemo` exists to show Slate's CloudKit mirroring: with the same
/// iCloud account on two devices, notes sync automatically. The entity is marked
/// `cloudKit: true`, and `NotesStore` opens the store in
/// `.cloudKitMirrored` mode, so once the target is provisioned (signing team +
/// the iCloud/CloudKit container) writes mirror to CloudKit and remote changes
/// import back into the same `slate.stream(...)` with no UI changes.
///
/// CloudKit-subset rules honored here: every attribute is optional or
/// carries a default, there is no `#Unique` constraint (CloudKit forbids them —
/// `noteId` uses `#Index` instead), and there are no ordered relationships.
@SlateEntity(cloudKit: true)
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
