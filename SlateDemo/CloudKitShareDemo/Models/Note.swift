import Foundation
import SlateSchema

/// A single note: a `title` and a `content` body.
///
/// `CloudKitShareDemo` exists to show Slate's CloudKit **sharing**: a note you
/// own can be shared with another iCloud user, and once they accept, edits made
/// by either side sync to both apps. The entity is marked `cloudKit: true`, and
/// `NotesStore` opens the store in `.cloudKitShared` mode — which provisions both
/// a private store (notes you own) and a shared store (notes shared *with* you).
/// A single `slate.stream(...)` surfaces both, so the list shows owned and
/// shared-with-me notes together with no per-store query code.
///
/// CloudKit-subset rules honored here: every attribute is optional or carries a
/// default, there is no `#Unique` constraint (CloudKit forbids them — `noteId`
/// uses `#Index` instead), and there are no ordered relationships.
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
