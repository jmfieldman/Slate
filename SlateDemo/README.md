# Slate Demos

## SlateDemo

This demo shows most functionality of Slate.

## CloudKitMirrorDemo

A minimal notes app whose purpose is to demonstrate Slate's **CloudKit
mirroring**: with the same iCloud account on two devices, notes sync
automatically with no extra app code.

### What it does

- **Notes list** — every note, most-recently-modified at the top. Swipe a row to
  delete it. Tap **+** (top right) to create a new note.
- **Note detail / editor** — tap a note to open it. Tap the content to edit (an
  inline editable text view); tap **Done** to commit the change to the store.
  Editing bumps the modification time, so the note floats back to the top of the
  list. The title is the first non-empty line of the content (Apple Notes style).
- A footer shows where data lives (local now; iCloud once CloudKit is enabled).

`Note` is a single Slate entity with `noteId`, `title`, `content`, `createdAt`,
and `modifiedAt`. The model already satisfies CloudKit's required subset (every
attribute optional or defaulted, `#Index` instead of `#Unique`, no ordered
relationships), so turning on sync is a configuration change — not a rewrite.

### Pass 1 vs pass 2

This is **pass 1**: the app runs against a **local** store
(`NotesStore.storageMode = .local`) so it works immediately without any iCloud
provisioning. CloudKit entitlements/provisioning are intentionally deferred to
**pass 2**.

To enable real CloudKit sync (pass 2):

1. In Xcode, add the **iCloud** capability with **CloudKit** to the
   `CloudKitMirrorDemo` target, and create/select the container
   `iCloud.org.fieldman.CloudKitMirrorDemo` (or update
   `NotesStore.cloudKitContainerIdentifier` to match). Add the **Background
   Modes → Remote notifications** capability so imports arrive in the background.
2. Change `@SlateEntity()` to `@SlateEntity(cloudKit: true)` in
   `CloudKitMirrorDemo/Models/Note.swift`.
3. Regenerate the persistence code: `./generate_cloudkit_demo.sh` (from the repo
   root).
4. Change `NotesStore.storageMode` from `.local` to
   `.cloudKitMirrored(containerIdentifier: cloudKitContainerIdentifier)`.

No UI or query code changes are needed — the same `slate.stream(...)`
republishes whenever CloudKit imports remote changes.

### Project layout

- `CloudKitMirrorDemo.xcodeproj` — references the local Slate package at the
  repository root (`..`), which provides the CloudKit-capable runtime.
- `CloudKitMirrorDemo/Models/Note.swift` — the hand-written model.
- `CloudKitMirrorDemo/Generated/` — generator output (do not edit by hand; run
  `./generate_cloudkit_demo.sh`).
- `CloudKitMirrorDemo/App/NotesStore.swift` — owns the Slate store and the note
  operations; the single place CloudKit is switched on.
- `CloudKitMirrorDemo/ContentView.swift` — the list, editor, and status footer.
