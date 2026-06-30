import Slate
import SwiftUI

struct ContentView: View {
    @Environment(NotesStore.self) private var store
    @State private var path: [String] = []
    @State private var shareInvitation: ShareInvitation?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let stream = store.notesStream {
                    NotesList(stream: stream, onShare: share)
                } else {
                    ProgressView("Opening store")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let id = await store.createNote() {
                                path.append(id)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!store.isConfigured)
                    .accessibilityLabel("New note")
                }
            }
            .navigationDestination(for: String.self) { noteId in
                NoteDetailView(noteId: noteId)
            }
            .safeAreaInset(edge: .bottom) {
                SyncStatusBar()
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .sheet(item: $shareInvitation) { invitation in
                CloudSharingView(invitation: invitation)
                    .ignoresSafeArea()
            }
            .task {
                await store.configure()
            }
        }
    }

    private func share(_ note: Note) {
        Task {
            if let invitation = await store.prepareShare(for: note) {
                shareInvitation = invitation
            }
        }
    }
}

// MARK: - List

private struct NotesList: View {
    @Environment(NotesStore.self) private var store
    let stream: SlateStream<Note>
    let onShare: (Note) -> Void

    var body: some View {
        List {
            ForEach(stream.values, id: \.slateID) { note in
                NoteRow(
                    note: note,
                    isSharedWithMe: store.isSharedWithMe(note),
                    onShare: { onShare(note) }
                )
            }
            .onDelete { offsets in
                let ids = offsets.map { stream.values[$0].noteId }
                Task {
                    for id in ids {
                        await store.deleteNote(noteId: id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if stream.state == .loading, stream.values.isEmpty {
                ProgressView()
            } else if stream.values.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "note.text",
                    description: Text("Tap + to write your first note.")
                )
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let isSharedWithMe: Bool
    let onShare: () -> Void

    private var title: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    private var preview: String {
        let lines = note.content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let titleIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return "" }
        return lines[(titleIndex + 1)...]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            // The note content navigates to the editor.
            NavigationLink(value: note.noteId) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        if isSharedWithMe {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .accessibilityLabel("Shared with you")
                        }
                    }
                    HStack(spacing: 6) {
                        if let modifiedAt = note.modifiedAt {
                            Text(modifiedAt, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                        Text(preview.isEmpty ? "No additional text" : preview)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                }
                // Fill the row left of the Share button so the whole area taps
                // through to the editor.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            // Trailing affordance: owners get a Share button; notes shared with
            // you can only be managed by their owner.
            if !isSharedWithMe {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .imageScale(.large)
                        .padding(.vertical, 6)
                        .padding(.leading, 6)
                        .contentShape(Rectangle())
                }
                // `.borderless` so the button captures its own taps instead of the
                // surrounding NavigationLink swallowing them.
                .buttonStyle(.borderless)
                .accessibilityLabel("Share note")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail / editor

private struct NoteDetailView: View {
    @Environment(NotesStore.self) private var store
    let noteId: String

    @State private var stream: SlateStream<Note>?
    @State private var draft = ""
    @State private var isEditing = false
    @State private var didLoadInitialDraft = false
    @State private var shareInvitation: ShareInvitation?
    @FocusState private var editorFocused: Bool

    private var note: Note? { stream?.value }
    private var displayContent: String { note?.content ?? "" }
    private var isSharedWithMe: Bool { note.map(store.isSharedWithMe) ?? false }

    private var displayTitle: String {
        let base = isEditing ? NotesStore.derivedTitle(from: draft) : (note?.title ?? "")
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .focused($editorFocused)
                    .onAppear { editorFocused = true }
            } else {
                ScrollView {
                    Group {
                        if displayContent.isEmpty {
                            Text("Tap to edit")
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(displayContent)
                        }
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    // Fill at least the visible height so a tap anywhere on the
                    // page begins editing, not just on the text itself.
                    .containerRelativeFrame(.vertical, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                }
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Task { await commit() }
                    }
                    .fontWeight(.semibold)
                }
            } else if let note, !isSharedWithMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        share(note)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share note")
                }
            }
        }
        .sheet(item: $shareInvitation) { invitation in
            CloudSharingView(invitation: invitation)
                .ignoresSafeArea()
        }
        .task {
            if stream == nil {
                stream = store.noteStream(noteId: noteId)
            }
        }
        .onChange(of: note) { _, newValue in
            guard let newValue else { return }
            // Seed the draft once the note first loads; auto-open the editor for a
            // brand-new (empty) note so the user can start typing immediately.
            if !didLoadInitialDraft {
                didLoadInitialDraft = true
                draft = newValue.content
                if newValue.content.isEmpty {
                    beginEditing()
                }
                return
            }
            // Reflect external/remote updates (incl. edits from the other side of a
            // share) while reading, but never clobber an in-progress edit.
            if !isEditing {
                draft = newValue.content
            }
        }
    }

    private func beginEditing() {
        draft = note?.content ?? draft
        isEditing = true
    }

    private func commit() async {
        editorFocused = false
        isEditing = false
        await store.updateNote(noteId: noteId, content: draft)
    }

    private func share(_ note: Note) {
        Task {
            if let invitation = await store.prepareShare(for: note) {
                shareInvitation = invitation
            }
        }
    }
}

// MARK: - Sync status

private struct SyncStatusBar: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private var icon: some View {
        if !store.isCloudKitEnabled {
            Image(systemName: "internaldrive").foregroundStyle(.secondary)
        } else if store.isSyncing {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: iconName).foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch store.accountStatus {
        case .available: "icloud"
        case .unavailable: "icloud.slash"
        case .restricted: "lock.icloud"
        case .couldNotDetermine: "icloud"
        }
    }

    private var iconColor: Color {
        store.accountStatus == .available ? .blue : .secondary
    }

    private var text: String {
        guard store.isCloudKitEnabled else { return "Stored on this device" }
        if store.isSyncing { return "Syncing with iCloud…" }
        switch store.accountStatus {
        case .available: return "iCloud sync on"
        case .unavailable: return "Sign in to iCloud to sync"
        case .restricted: return "iCloud access is restricted"
        case .couldNotDetermine: return "Checking iCloud…"
        }
    }
}

#Preview {
    ContentView()
        .environment(NotesStore())
}
