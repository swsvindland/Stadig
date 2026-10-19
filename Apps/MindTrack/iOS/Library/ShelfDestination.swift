import MindEngine
import SwiftUI
import SystemCore

/// What's selected on the shelf: a book of yours, or one the ladder suggests.
enum ShelfSelection: Hashable {
    case book(UUID)
    case suggestion(String)
}

/// The shelf as a destination of its own in a wide window (iPad, the Mac, Vision Pro): every book
/// in a list beside the one selected, with what can be done with it and what you noted while
/// reading it. An iPhone opens `ShelfView` as a sheet instead.
struct ShelfDestination: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ShelfSelection?
    @State private var query = ""
    @State private var editing: Book?
    @State private var finishing: Book?
    @State private var settingAside: Book?

    var body: some View {
        let shelf = ShelfSections(books: model.books, query: query)
        let suggestions = query.isEmpty ? Shelf.suggestions(model) : []
        let reading = model.analysis?.reading
        NavigationStack {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    if let reading, query.isEmpty {
                        Section("Your reading") { LevelRows(reading: reading) }
                    }
                    if let current = shelf.current {
                        Section("Reading now") {
                            ShelfRow(book: current, detail: Shelf.detail(current))
                                .tag(ShelfSelection.book(current.id))
                                .contextMenu { actions(for: current) }
                                .accessibilityIdentifier("shelfList.current")
                        }
                    }
                    if !suggestions.isEmpty {
                        Section("Suggested next") {
                            ForEach(suggestions) { book in
                                ShelfRow(title: book.title, detail: "\(book.author) · tier \(book.tier)")
                                    .tag(ShelfSelection.suggestion(book.id))
                                    .contextMenu {
                                        Button("Start Reading", systemImage: "book") { start(book) }
                                    }
                                    .accessibilityIdentifier("shelfList.suggestion.\(book.id)")
                            }
                        }
                    }
                    section("Finished", shelf.finished, level: reading?.level)
                    section("Set aside", shelf.setAside, level: nil)
                    section("Read in the year before Mind Track", shelf.readBefore, level: nil)
                }
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
                .overlay {
                    if !query.isEmpty, shelf.isEmpty { ContentUnavailableView.search(text: query) }
                }
                Divider()
                detail(shelf: shelf, suggestions: suggestions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Shelf")
            .searchable(text: $query, prompt: "Title or author")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add a Book", systemImage: "plus") { model.addingBook = true }
                        .help("Add a book you're reading now (⇧⌘B)")
                        .accessibilityIdentifier("shelfList.addBook")
                }
            }
            .background(.pageBackground)
        }
        .modifier(BookSheets(editing: $editing, finishing: $finishing, settingAside: $settingAside))
        .modifier(AddBookSheet(isPresented: Binding(get: { model.addingBook && model.tab == .shelf }, set: { model.addingBook = $0 })))
        .onAppear {
            if selection == nil, let current = ShelfSections(books: model.books).current { selection = .book(current.id) }
        }
    }

    @ViewBuilder func section(_ title: String, _ books: [Book], level: Double?) -> some View {
        if !books.isEmpty {
            Section(title) {
                ForEach(books) { book in
                    FinishedRow(book: book, level: level)
                        .tag(ShelfSelection.book(book.id))
                        .contextMenu { actions(for: book) }
                }
            }
        }
    }

    /// What can be done with a book, in its context menu and its detail.
    @ViewBuilder func actions(for book: Book) -> some View {
        if book.status == .reading {
            Button("Finished It…", systemImage: "checkmark") { finishing = book }
            Button("Edit…", systemImage: "pencil") { editing = book }
            Button("Set It Aside…", systemImage: "xmark.bin", role: .destructive) { settingAside = book }
        } else {
            Button("Edit…", systemImage: "pencil") { editing = book }
        }
    }

    func start(_ book: LadderBook) {
        model.start(book: book)
        // The book started is the one on the go now: select it.
        if let current = ShelfSections(books: model.books).current { selection = .book(current.id) }
    }

    @ViewBuilder func detail(shelf: ShelfSections, suggestions: [LadderBook]) -> some View {
        switch selection {
        case .book(let id):
            if let book = model.books.first(where: { $0.id == id }) {
                BookDetail(
                    book: book, reflections: model.reflections.filter { $0.bookID == id }.reversed(), level: model.analysis?.reading.level,
                    finish: { finishing = book }, edit: { editing = book }, setAside: { settingAside = book })
            } else {
                noSelection
            }
        case .suggestion(let id):
            if let book = model.catalogs.ladder.books(in: nil).first(where: { $0.id == id }) {
                SuggestionDetail(book: book, current: shelf.current) { start(book) }
            } else {
                noSelection
            }
        case nil:
            noSelection
        }
    }

    var noSelection: some View {
        ContentUnavailableView(
            "Choose a book", systemImage: "books.vertical", description: Text("Its level, where you are in it and what you noted."))
    }
}

/// A book in the shelf's list.
private struct ShelfRow: View {
    let title: String
    let detail: String

    init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    init(book: Book, detail: String) {
        title = book.title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One of your books: its level and where that comes from, where you are in it, how it felt, and
/// what you noted while reading it.
private struct BookDetail: View {
    let book: Book
    let reflections: [Reflection]
    let level: Double?
    let finish: () -> Void
    let edit: () -> Void
    let setAside: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(.largeTitle.bold())
                        .accessibilityIdentifier("bookDetail.title")
                    Text(book.author).font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Pill(text: "Tier \(book.tier)", color: .teal)
                        Pill(text: status, color: .secondary)
                        if let format = book.format { Pill(text: format.label, color: .secondary) }
                    }
                }
                if book.status == .reading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(book.page), total: Double(max(1, book.pages))).tint(.teal)
                        Text("Page \(book.page) of \(book.pages)").font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Finished It…", systemImage: "checkmark", action: finish).primaryAction()
                                .accessibilityIdentifier("bookDetail.finished")
                            Button("Edit…", systemImage: "pencil", action: edit).secondaryAction()
                                .accessibilityIdentifier("bookDetail.edit")
                            Button("Set It Aside…", systemImage: "xmark.bin", role: .destructive, action: setAside).secondaryAction()
                                .accessibilityIdentifier("bookDetail.setAside")
                        }
                        .padding(.top, 4)
                    }
                    .card()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if let feel = book.feel { LabeledContent("How it felt", value: feel.label) }
                        if let finished = book.finished {
                            LabeledContent(book.status == .abandoned ? "Set aside" : "Finished", value: Format.day(finished))
                        }
                        let refined = BookLevel.refined(book, readerLevel: level)
                        if abs(refined - Double(book.tier)) >= 0.5 {
                            LabeledContent("Your feedback puts it near", value: "tier \(ReadingPlan.format(refined))")
                        }
                        Button("Edit…", systemImage: "pencil", action: edit).secondaryAction().padding(.top, 4)
                            .accessibilityIdentifier("bookDetail.edit")
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("How hard to read").font(.subheadline.weight(.semibold))
                    Text(levelNote).font(.subheadline).foregroundStyle(.secondary)
                }
                if !reflections.isEmpty {
                    SectionHeader(title: "What you noted", detail: "\(reflections.count)")
                    ForEach(reflections) { reflection in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reflection.text).font(.writing).lineSpacing(LineSpacing.writing).textSelection(.enabled)
                            Text(reflection.date.formatted(date: .abbreviated, time: .omitted) + (reflection.page.map { " · page \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .card()
                    }
                }
            }
            .padding(24)
            .readableWidth(720)
        }
    }

    var status: String {
        switch book.status {
        case .reading: "Reading now"
        case .finished: "Finished"
        case .abandoned: "Set aside"
        case .readBefore: "Read before Mind Track"
        }
    }

    var levelNote: String {
        if book.ladderID != nil, (book.tierConfidence ?? 1) >= 1 { return ReadingLadder.standard.tier(book.tier)?.description ?? "" }
        if book.ladderID != nil { return "Levelled from its text, so it counts half towards your level." }
        return "Estimated from the author's other books, its genre, length and age, and refined by how it felt."
    }
}

/// A book the ladder suggests next, and starting it.
private struct SuggestionDetail: View {
    let book: LadderBook
    let current: Book?
    let start: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(.largeTitle.bold())
                    Text(book.author).font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Pill(text: "Tier \(book.tier)", color: .teal)
                        Pill(text: "\(book.pages) pages", color: .secondary)
                        ForEach(book.genres.prefix(2), id: \.self) { Pill(text: $0.label, color: .secondary) }
                    }
                }
                Text(book.note).font(.body)
                if let tier = ReadingLadder.standard.tier(book.tier) {
                    Text("\(tier.label): \(tier.description)").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("Start Reading", systemImage: "book", action: start).primaryAction().controlSize(.large)
                        .accessibilityIdentifier("suggestion.start")
                    if let current {
                        Text("\(current.title) is set aside: one English book at a time.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .readableWidth(720)
        }
    }
}
