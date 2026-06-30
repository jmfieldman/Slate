# Slate Demos

Three sample apps, each focused on one slice of Slate:

| Demo | Shows | Storage mode |
| --- | --- | --- |
| **SlateDemo** | The core API surface — entities, relationships-by-id, constraints, nested value types, queries, and live streams. | `.cacheStore` (local) |
| **CloudKitMirrorDemo** | **CloudKit mirroring** — the same iCloud account on two devices syncs automatically, no extra app code. | `.cloudKitMirrored` |
| **CloudKitShareDemo** | **CloudKit sharing** — share a note with another iCloud user; either side's edits sync to both. | `.cloudKitShared` |

The two CloudKit demos are the same minimal notes app; sharing is mirroring plus a
sharing layer on top. If you're wiring up CloudKit for the first time, read
[CloudKit gotchas (both demos)](#cloudkit-gotchas-both-demos) at the bottom — it
collects the non-obvious things that cost the most time.

## SlateDemo

A read-only catalog browser over three related entities — **Library → Book →
Author** — that exercises most of Slate's core API without any CloudKit:

- **Related entities linked by id** (`libraryId`, `authorId`) with `#Unique` and
  multi-column `#Index` constraints, and **nested `Sendable` value types**
  (`Library.Address`/`Hours`, `Book.CatalogInfo`, `Author.Profile`).
- **Live streams** driving a master-detail UI: a list of libraries, a library's
  books, and a book's author, each from `slate.stream(...)` with predicates and
  sorts (`slate.stream(Book.self, where: \.libraryId == …)`).
- Seeded sample data on first launch, stored locally in a `.cacheStore` (fast,
  disposable) — so there's nothing to provision; it just runs.

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
  `./generate_demo.sh` from the repository root).
- `CloudKitMirrorDemo/App/NotesStore.swift` — owns the Slate store and the note
  operations; the single place the storage mode / container is configured.
- `CloudKitMirrorDemo/ContentView.swift` — the list, editor, and status footer.
- `CloudKitMirrorDemo/CloudKitMirrorDemo.entitlements` — iCloud/CloudKit
  container + `aps-environment`.
- `CloudKitMirrorDemo/Info.plist` — partial plist merged into the generated one;
  adds the `remote-notification` background mode.

## CloudKitShareDemo

A minimal notes app whose purpose is to demonstrate Slate's **CloudKit
sharing**: share a note you own with another iCloud user, and once they accept,
edits made by either side sync to both apps. It is the same notes app as
`CloudKitMirrorDemo` with sharing layered on top.

### What it does

- **Notes list** — every note, most-recently-modified at the top, including both
  notes you own and notes others have **shared with you** (those get a
  person badge). Swipe a row to delete it. Tap **+** (top right) to create a new
  note.
- **Share a note** — each note you own has a **Share** button on the right of its
  row (and one in the editor's toolbar). Tapping it presents the standard system
  share sheet, where you add people (Messages, Mail, copy link), choose read-only
  vs read/write, or share via link.
- **Accept a share** — when the invitee taps the share link, the app launches and
  accepts the invitation; the note appears in their list as "shared with you".
- **Two-way edits** — open a note, tap the content to edit, tap **Done** to
  commit. Either participant's edit bumps the modification time and syncs to the
  other side's open editor and list. The title is the first non-empty line of the
  content (Apple Notes style).
- A footer shows the live iCloud state from Slate's CloudKit stack: "iCloud sync
  on", a spinner + "Syncing with iCloud…" while changes import, or "Sign in to
  iCloud to sync" when there's no account.

### How sharing works in Slate

The store is opened in `.cloudKitShared` mode, which provisions **two** CloudKit
backed stores: a **private** store (notes you own) and a **shared** store (notes
shared *with* you and accepted). A single `slate.stream(Note.self, …)` fetches
across both, so the list shows owned and shared-with-me notes together — no
per-store query code. Telling them apart for the UI is just the row's
persistent-store configuration name, so `NotesStore.isSharedWithMe(_:)` needs no
async CloudKit round-trip.

Sharing itself is three Slate calls, wired in `NotesStore`:

- `slate.sharing.prepareShare(for:title:)` returns the `(CKShare, CKContainer)`
  pair, which the app registers on an `NSItemProvider`
  (`registerCKShare(_:container:allowedSharingOptions: .standard)`) and presents
  through `UIActivityViewController` (the `CKShare` is already created and saved
  server-side, so no preparation handler is needed). This is the supported path on
  iOS 17+; `UICloudSharingController` can't supply the `CKAllowedSharingOptions`
  the "Invite with Link" flow needs, so it errors with "No optionsGroups provided
  to addToCloudKitSharing".
  - The app then sets the share's `publicPermission = .readWrite` and re-saves it,
    so **anyone with the link** can open it. A new `CKShare` defaults to
    `publicPermission == .none` (invited participants only); without this, a copied
    link returns "the owner stopped sharing, or your account doesn't have
    permission to open it" on any account you didn't explicitly invite.
- `slate.sharing.acceptShare(_:)` accepts an incoming invitation. A SwiftUI
  `WindowGroup` app receives the `CKShare.Metadata` on the **scene** delegate's
  `windowScene(_:userDidAcceptCloudKitShareWith:)` (the `UIApplicationDelegate`
  variant is never called for this lifecycle), so the app registers a
  `SceneDelegate` and forwards the metadata through `ShareAcceptanceBridge` (which
  buffers it until the store has configured).
- `slate.sharing.stopSharing(_:)` / `slate.sharing.share(for:)` revoke and inspect
  a share. The share sheet also exposes manage/stop-sharing for the owner.

`Note` is the same single Slate entity as the mirror demo (`noteId`, `title`,
`content`, `createdAt`, `modifiedAt`) and satisfies CloudKit's required subset, so
sharing is a configuration choice — not a rewrite.

### CloudKit status: enabled in code

The app is wired for CloudKit sharing:

- `Note` is declared `@SlateEntity(cloudKit: true)`.
- `NotesStore.storageMode = .cloudKitShared(containerIdentifier:)`.
- `CloudKitShareDemo.entitlements` declares the iCloud/CloudKit container and
  `aps-environment`; `Info.plist` adds the `remote-notification` background mode
  and **`CKSharingSupported = true`** (required for the system to route share
  links to the app).

It still builds and runs locally on an unprovisioned simulator (the stores load;
it just can't sync or share without an account/container).

### What you still need to do: provision it

These steps happen in your Apple Developer account / Xcode signing, not in code —
the same as the mirror demo, but with this demo's own container:

1. **Signing team** — open `CloudKitShareDemo.xcodeproj`, select the
   `CloudKitShareDemo` target → **Signing & Capabilities**, and set your **Team**.
   Keep **Automatically manage signing** on.
2. **iCloud / CloudKit container** — the **iCloud** capability (CloudKit) is
   already declared via the entitlements file; confirm the container
   **`iCloud.org.fieldman.CloudKitShareDemo`** exists and is checked. Create it
   with the **+** under iCloud Containers (or in the CloudKit Console). If you use
   a different identifier, update `NotesStore.cloudKitContainerIdentifier` and the
   entitlements file to match.
3. **Run on two destinations signed into *different* iCloud accounts** — sharing
   is between two *people*, so unlike the mirror demo you want two accounts (two
   devices, or a device + a simulator). Create a note on account A, tap Share, and
   share the link with account B. On B, open the link; the note appears in B's
   list. Edit on either side and watch it update on the other. (CloudKit sharing is
   most reliable on real devices; on the Simulator use the `simctl` recipe in
   "Testing the share flow on two simulators" below.)
4. First launch initializes the CloudKit schema in the **development**
   environment automatically. Use the **CloudKit Console** to inspect records and
   shares and, when ready, deploy the schema to production.

If signing reports a missing capability, open **Signing & Capabilities** and make
sure **iCloud → CloudKit** (with the container), **Background Modes → Remote
notifications**, and **Push Notifications** are present.

### Testing the share flow on two simulators

Sharing needs two *people*, so the two simulators must be signed into **different
iCloud accounts** (Settings → sign in), both with the app installed. The live
"Invite with Link" / collaboration UI is unreliable on the Simulator, so use
**Copy Link** plus `simctl` to move the link between them:

```bash
# Owner sim: create a note, tap Share, tap "Copy Link".
xcrun simctl pbpaste <OWNER-UDID>                       # prints the iCloud share URL
# Hand the link to the invitee sim (routes to the app, not Safari):
xcrun simctl openurl <INVITEE-UDID> "https://www.icloud.com/share/…"
```

The invitee app launches, accepts the share, and the note appears in its list;
edit on either side to see it sync. Because the app marks shares "anyone with the
link can edit", you don't need to invite the second account first. Pasting the
link into Safari won't work — only `simctl openurl` (or tapping it in Messages/Mail
on a real device) hands it to the app. On real devices the in-app "Invite with
Link" button also works.

### Project layout

- `CloudKitShareDemo.xcodeproj` — references the local Slate package at the
  repository root (`..`).
- `CloudKitShareDemo/Models/Note.swift` — the hand-written model.
- `CloudKitShareDemo/Generated/` — generator output (do not edit by hand; run
  `./generate_demo.sh`).
- `CloudKitShareDemo/App/NotesStore.swift` — owns the Slate store and the note +
  sharing operations; the single place the storage mode / container is configured.
- `CloudKitShareDemo/ContentView.swift` — the list (with per-row Share buttons),
  editor, and status footer.
- `CloudKitShareDemo/Sharing/CloudSharingView.swift` — the system share sheet
  (`UIActivityViewController` + `NSItemProvider.registerCKShare`) wrapped for
  SwiftUI.
- `CloudKitShareDemo/Sharing/ShareAcceptanceBridge.swift` — buffers the
  share-acceptance metadata from the scene delegate and hands it to the store once
  it's configured.
- `CloudKitShareDemo/CloudKitShareDemoApp.swift` — app entry, plus the `AppDelegate`
  that installs a `SceneDelegate` whose `windowScene(_:userDidAcceptCloudKitShareWith:)`
  receives accepted shares.
- `CloudKitShareDemo/CloudKitShareDemo.entitlements` — iCloud/CloudKit container +
  `aps-environment`.
- `CloudKitShareDemo/Info.plist` — partial plist merged into the generated one;
  adds the `remote-notification` background mode and `CKSharingSupported`.

## CloudKit gotchas (both demos)

The non-obvious things that cost the most time getting the CloudKit demos running.

### Building & running

- **You must build *signed*.** Running unsigned (e.g. `xcodebuild … CODE_SIGNING_ALLOWED=NO`)
  strips the iCloud entitlement, and the app then **traps on launch** inside
  `CKContainer(identifier:)` (an `EXC_BREAKPOINT`, deep in
  `SlateCloudKitContainer.build`). It is not a code bug — give the target a signing
  **Team** so the entitlements get embedded. (On the Simulator a signed *ad-hoc*
  build is enough; entitlements still embed.)
- **Match the Simulator runtime to the deployment target.** The demos target a
  recent iOS; installing onto an older Simulator/device fails with "Requires a
  Newer Version of iOS". Use a Simulator whose runtime ≥ the deployment target.
- **Unprovisioned still runs.** With no container/account the local store(s) load
  and the app works offline — it just can't sync or share. The footer reports the
  live account state ("Sign in to iCloud to sync").
- **CloudKit subset rules.** Every attribute must be optional or defaulted, use
  `#Index` not `#Unique`, and no ordered relationships. The generated schema's
  `cloudKitEnabled` flag must match the storage mode (`.cloudKit*` ⇒ `true`).

### Accounts & reliability

- **Mirroring wants the *same* account; sharing wants *different* accounts.**
  Mirroring syncs one user's own devices, so both destinations sign into the same
  Apple ID. Sharing is person-to-person — the owner and the invitee must be
  **different** Apple IDs, or the "shared with you" note never appears (the second
  device is just another of the owner's devices).
- **Real devices are the reliable path.** Simulator CloudKit delivery lags and the
  collaboration UI is incomplete (see below). If something doesn't show up,
  background/foreground the app and give push a few seconds.

### Sharing-specific (CloudKitShareDemo)

- **The accept callback lands on the *scene* delegate.** A SwiftUI `WindowGroup`
  app gets `windowScene(_:userDidAcceptCloudKitShareWith:)` on a
  `UIWindowSceneDelegate` — the `UIApplicationDelegate` variant is **never called**.
  You must register a `SceneDelegate` (here via the app delegate's
  `configurationForConnecting`); otherwise tapping a share link does nothing.
- **`UICloudSharingController` can't enable link sharing on iOS 17+.** It has no way
  to supply `CKAllowedSharingOptions`, and its `availablePermissions` is deprecated
  and ignored by the modern collaboration sheet — so "Invite with Link" fails with
  `CKErrorDomain Code=1 "No optionsGroups provided to addToCloudKitSharing"`. The
  supported path (used here) is `UIActivityViewController` + a `CKShare` registered
  on an `NSItemProvider` with `allowedSharingOptions: .standard`.
- **A new `CKShare` is invite-only by default.** It ships with
  `publicPermission == .none`, so a *copied link* opens only for accounts you
  explicitly invited — everyone else gets "the owner stopped sharing, or your
  account doesn't have permission to open it" (even though nothing was stopped).
  The demo sets `publicPermission = .readWrite` so anyone with the link can open it.
- **`CKSharingSupported = true` in `Info.plist`** is required for the system to
  route a share link back to the app.
- **Don't paste share links into Safari.** Safari shows the iCloud web page and
  never hands off. Use `xcrun simctl openurl <udid> "<link>"` on the Simulator (or
  tap the link in Messages/Mail on a device). See "Testing the share flow on two
  simulators" above.
- **The live "Invite with Link"/collaboration UI is unreliable on the Simulator**
  regardless of the above — use "Copy Link". On real devices the in-app button
  works.
