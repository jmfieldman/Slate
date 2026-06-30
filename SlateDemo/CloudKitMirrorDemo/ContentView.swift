import Slate
import SwiftUI

struct ContentView: View {
    @Environment(NotesStore.self) private var store
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let stream = store.notesStream {
                    NotesList(stream: stream)
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
            .task {
                await store.configure()
            }
        }
    }
}

// MARK: - List

private struct NotesList: View {
    @Environment(NotesStore.self) private var store
    let stream: SlateStream<Note>

    var body: some View {
        List {
            ForEach(stream.values, id: \.slateID) { note in
                NavigationLink(value: note.noteId) {
                    NoteRow(note: note)
                }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
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
    @FocusState private var editorFocused: Bool

    private var note: Note? { stream?.value }
    private var displayContent: String { note?.content ?? "" }

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
            }
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
            // Reflect external/remote updates while reading, but never clobber an
            // in-progress edit.
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
