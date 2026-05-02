import Slate
import SwiftUI

struct ContentView: View {
    @Environment(DemoStore.self) private var store
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let stream = store.libraryStream {
                    LibraryList(stream: stream)
                } else {
                    ProgressView("Opening Slate store")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                }
            }
            .background(Theme.background)
            .navigationTitle("Libraries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!store.isConfigured)
                    .accessibilityLabel("Delete database")
                }
            }
            .confirmationDialog(
                "Delete all libraries, books, and authors?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Database", role: .destructive) {
                    Task { await store.deleteDatabase() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Slate Demo Error", isPresented: Binding(
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
        .tint(Theme.ink)
    }
}

private struct LibraryList: View {
    @Environment(DemoStore.self) private var store
    let stream: SlateStream<Library>

    var body: some View {
        List {
            ForEach(stream.values, id: \.slateID) { library in
                NavigationLink(value: library) {
                    LibraryRow(library: library)
                        .onAppear {
                            if library.slateID == stream.values.last?.slateID {
                                Task { await store.loadMoreLibraries() }
                            }
                        }
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.separator)
            }

            if store.isLoadingLibraries {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading another page")
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Library.self) { library in
            LibraryDetailView(library: library)
        }
        .overlay {
            if stream.state == .loading {
                ProgressView()
            } else if stream.values.isEmpty && !store.isLoadingLibraries {
                ContentUnavailableView("No Libraries", systemImage: "books.vertical", description: Text("The next fake page will repopulate the cache."))
            }
        }
    }
}

private struct LibraryRow: View {
    let library: Library

    var body: some View {
        HStack(spacing: 14) {
            SymbolBadge(symbol: library.kind.symbol, color: library.kind.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(library.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(library.city), \(library.state)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: library.kind.title)
                    Pill(text: library.isOpenToday ? "Open today" : "Closed today")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct LibraryDetailView: View {
    @Environment(DemoStore.self) private var store
    let library: Library
    @State private var bookStream: SlateStream<Book>?
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section {
                LibraryHeader(library: library, isRefreshing: isRefreshing) {
                    Task { await refresh() }
                }
            }
            .listRowBackground(Theme.card)

            Section("Books") {
                if let bookStream {
                    ForEach(bookStream.values, id: \.slateID) { book in
                        NavigationLink(value: book) {
                            BookRow(book: book)
                        }
                    }
                }

                if isRefreshing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Refreshing books")
                            .font(.system(.callout, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Book.self) { book in
            BookDetailView(book: book)
        }
        .task {
            if bookStream == nil {
                bookStream = store.bookStream(for: library)
            }
            await refresh()
        }
        .refreshable {
            await refresh()
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await store.refreshBooks(for: library)
    }
}

private struct LibraryHeader: View {
    let library: Library
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                SymbolBadge(symbol: library.kind.symbol, color: library.kind.color, size: 54)
                VStack(alignment: .leading, spacing: 7) {
                    Text(library.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(library.kind.color)
                    Text(library.name)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                    Text("\(library.address?.street ?? "Main desk") · \(library.city), \(library.state)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                StatTile(title: "Founded", value: library.foundedYear.map(String.init) ?? "Unknown")
                StatTile(title: "Visitors", value: library.annualVisitors.formatted())
                StatTile(title: "Hours", value: "\(library.hours.opensAt) - \(library.hours.closesAt)")
                StatTile(title: "Weekend", value: library.hours.weekendHours ?? "By request")
            }

            Button(action: refresh) {
                Label(isRefreshing ? "Refreshing" : "Refresh Books", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .padding(.vertical, 10)
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: book.format.symbol, color: book.format.color, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(book.author?.displayName ?? "Author not hydrated")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: book.format.title)
                    Pill(text: book.isAvailable ? "Available" : "Checked out")
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct BookDetailView: View {
    let book: Book

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    SymbolBadge(symbol: book.format.symbol, color: book.format.color, size: 64)
                    Text(book.title)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let subtitle = book.subtitle {
                        Text(subtitle)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Pill(text: book.format.title)
                        Pill(text: "\(book.pageCount) pages")
                        Pill(text: String(format: "%.1f stars", book.rating))
                    }
                }
                .padding(.vertical, 10)
            }
            .listRowBackground(Theme.card)

            Section("Catalog") {
                DetailLine("Call number", book.catalog.callNumber)
                DetailLine("Shelf", book.catalog.shelf)
                DetailLine("Room", book.catalog.room ?? "Unassigned")
                DetailLine("ISBN", book.isbn ?? "None")
                DetailLine("Published", book.publicationYear.map(String.init) ?? "Unknown")
            }
            .listRowBackground(Theme.card)

            if let author = book.author {
                Section("Author") {
                    NavigationLink(value: author) {
                        HStack(spacing: 12) {
                            SymbolBadge(symbol: "person.text.rectangle", color: Theme.sage, size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(author.displayName)
                                    .font(.system(.headline, design: .serif))
                                Text(author.profile.shortBio)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Book")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Author.self) { author in
            AuthorDetailView(author: author)
        }
    }
}

private struct AuthorDetailView: View {
    @Environment(DemoStore.self) private var store
    let author: Author
    @State private var bookStream: SlateStream<Book>?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    SymbolBadge(symbol: "person.fill.viewfinder", color: Theme.sage, size: 58)
                    Text(author.displayName)
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(author.profile.shortBio)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Pill(text: author.era.title)
                        if let nationality = author.nationality {
                            Pill(text: nationality)
                        }
                        if let birthYear = author.birthYear {
                            Pill(text: "Born \(birthYear)")
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .listRowBackground(Theme.card)

            Section("Books in this database") {
                if let bookStream {
                    ForEach(bookStream.values, id: \.slateID) { book in
                        BookRow(book: book)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(author.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if bookStream == nil {
                bookStream = store.authorBookStream(for: author)
            }
        }
    }
}

private struct SymbolBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.16))
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

private struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.ink.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.mist, in: Capsule())
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.mist, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailLine: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

private enum Theme {
    static let background = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let card = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let mist = Color(red: 0.90, green: 0.93, blue: 0.90)
    static let separator = Color(red: 0.83, green: 0.82, blue: 0.76)
    static let ink = Color(red: 0.20, green: 0.23, blue: 0.22)
    static let sage = Color(red: 0.38, green: 0.52, blue: 0.45)
    static let clay = Color(red: 0.68, green: 0.38, blue: 0.30)
    static let brass = Color(red: 0.64, green: 0.50, blue: 0.24)
    static let slate = Color(red: 0.34, green: 0.43, blue: 0.52)
}

private extension Library.Kind {
    var title: String {
        switch self {
        case .publicBranch: "Public branch"
        case .university: "University"
        case .archive: "Archive"
        case .privateCollection: "Private collection"
        }
    }

    var symbol: String {
        switch self {
        case .publicBranch: "books.vertical.fill"
        case .university: "graduationcap.fill"
        case .archive: "archivebox.fill"
        case .privateCollection: "lock.doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .publicBranch: Theme.sage
        case .university: Theme.slate
        case .archive: Theme.brass
        case .privateCollection: Theme.clay
        }
    }
}

private extension Book.Format {
    var title: String {
        switch self {
        case .hardcover: "Hardcover"
        case .paperback: "Paperback"
        case .ebook: "E-book"
        case .audiobook: "Audiobook"
        case .manuscript: "Manuscript"
        }
    }

    var symbol: String {
        switch self {
        case .hardcover: "book.closed.fill"
        case .paperback: "book.pages.fill"
        case .ebook: "ipad"
        case .audiobook: "headphones"
        case .manuscript: "scroll.fill"
        }
    }

    var color: Color {
        switch self {
        case .hardcover: Theme.sage
        case .paperback: Theme.clay
        case .ebook: Theme.slate
        case .audiobook: Theme.brass
        case .manuscript: Theme.ink
        }
    }
}

private extension Author.Era {
    var title: String {
        switch self {
        case .classical: "Classical"
        case .modern: "Modern"
        case .contemporary: "Contemporary"
        case .emerging: "Emerging"
        }
    }
}

#Preview {
    ContentView()
        .environment(DemoStore())
}
