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
- A footer shows the live iCloud state from Slate's mirroring stack: "iCloud sync
  on", a spinner + "Syncing with iCloud…" while remote changes import, or "Sign in
  to iCloud to sync" when there's no account.

`Note` is a single Slate entity with `noteId`, `title`, `content`, `createdAt`,
and `modifiedAt`. The model satisfies CloudKit's required subset (every attribute
optional or defaulted, `#Index` instead of `#Unique`, no ordered relationships),
so mirroring is a configuration choice — not a rewrite.

### CloudKit status: enabled in code

The app is wired for CloudKit mirroring:

- `Note` is declared `@SlateEntity(cloudKit: true)`.
- `NotesStore.storageMode = .cloudKitMirrored(containerIdentifier:)`.
- `CloudKitMirrorDemo.entitlements` declares the iCloud/CloudKit container and
  `aps-environment`; `Info.plist` adds the `remote-notification` background mode.

No UI or query code knows about CloudKit — the same `slate.stream(...)`
republishes whenever CloudKit imports remote changes. The app still builds and
runs locally on an unprovisioned simulator (the local store loads; it just can't
sync without an account/container).

### What you still need to do: provision it

These steps happen in your Apple Developer account / Xcode signing, not in code:

1. **Signing team** — open `CloudKitMirrorDemo.xcodeproj`, select the
   `CloudKitMirrorDemo` target → **Signing & Capabilities**, and set your
   **Team**. Keep **Automatically manage signing** on.
2. **iCloud / CloudKit container** — the **iCloud** capability (CloudKit) is
   already declared via the entitlements file; confirm it shows up, and make sure
   the container **`iCloud.org.fieldman.CloudKitMirrorDemo`** exists and is
   checked. Create it with the **+** under iCloud Containers (or in the CloudKit
   Console). If you use a different identifier, update
   `NotesStore.cloudKitContainerIdentifier` and the entitlements file to match.
   With automatic signing, Xcode registers the App ID's iCloud + Push
   capabilities for you.
3. **Run on two destinations signed into the same iCloud account** — two physical
   devices, or a device plus a simulator, both signed into iCloud (Settings →
   sign in). Create/edit a note on one; it appears on the other. (CloudKit sync is
   most reliable on real devices; simulator delivery can lag.)
4. First launch initializes the CloudKit schema in the **development**
   environment automatically. Use the **CloudKit Console** to inspect records and,
   when ready, deploy the schema to production.

If signing reports a missing capability, open **Signing & Capabilities** and make
sure **iCloud → CloudKit** (with the container), **Background Modes → Remote
notifications**, and **Push Notifications** are present — they reconcile with the
entitlements/Info.plist already in the project.

### Project layout

- `CloudKitMirrorDemo.xcodeproj` — references the local Slate package at the
  repository root (`..`), which provides the CloudKit-capable runtime.
- `CloudKitMirrorDemo/Models/Note.swift` — the hand-written model.
- `CloudKitMirrorDemo/Generated/` — generator output (do not edit by hand; run
  `./generate_cloudkit_demo.sh`).
- `CloudKitMirrorDemo/App/NotesStore.swift` — owns the Slate store and the note
  operations; the single place the storage mode / container is configured.
- `CloudKitMirrorDemo/ContentView.swift` — the list, editor, and status footer.
- `CloudKitMirrorDemo/CloudKitMirrorDemo.entitlements` — iCloud/CloudKit
  container + `aps-environment`.
- `CloudKitMirrorDemo/Info.plist` — partial plist merged into the generated one;
  adds the `remote-notification` background mode.
