import MindEngine
import SwiftUI
import SystemCore

/// Books: where you are, the one on the go, what the ladder suggests next, and what's been read. A
/// sheet over the tabs on an iPhone; in a wide window the shelf is a destination of its own
/// (`ShelfDestination`).
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Book?
    @State private var finishing: Book?
    @State private var settingAside: Book?

    var body: some View {
        let shelf = ShelfSections(books: model.books, today: model.today)
        let reading = model.analysis?.reading
        List {
            if let reading {
                Section {
                    LevelRows(reading: reading)
                } footer: {
                    Text(
                        "Level comes from the reading test and how finished books felt. Focus comes from reading blocks on print and ebooks. Neither moves on time alone."
                    )
                }
            }
            if let current = shelf.current {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title).font(.headline)
                            .accessibilityIdentifier("shelf.current")
                        Text(Shelf.detail(current)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Group {
                        Button("Finished it", systemImage: "checkmark") { finishing = current }
                            .accessibilityIdentifier("shelf.finished")
                        Button("Edit", systemImage: "pencil") { editing = current }
                            .accessibilityIdentifier("shelf.edit")
                        Button("Set it aside", systemImage: "xmark.bin", role: .destructive) { settingAside = current }
                            .accessibilityIdentifier("shelf.setAside")
                    }
                    .disabled(model.booksLocked)
                } header: {
                    Text("Reading now")
                } footer: {
                    BooksLockedNote()
                }
            }
            Section {
                ForEach(Shelf.suggestions(model)) { book in
                    Button {
                        model.start(book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(book.title).font(.headline)
                                Spacer()
                                Text("Tier \(book.tier)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                            Text(book.note).font(.footnote)
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(model.booksLocked)
                    .accessibilityIdentifier("shelf.suggestion.\(book.id)")
                }
                Button("Add a book", systemImage: "plus") { model.addingBook = true }
                    .disabled(model.booksLocked)
                    .accessibilityIdentifier("shelf.addBook")
            } header: {
                Text("Suggested next")
            } footer: {
                Text("At the tier your reading is ready for. Starting one sets aside the book you're on.")
            }
            if !shelf.finished.isEmpty {
                Section("Finished") {
                    ForEach(shelf.finished) { book in FinishedRow(book: book, level: reading?.level) }
                }
            }
            if !shelf.setAside.isEmpty {
                Section("Set aside") {
                    ForEach(shelf.setAside) { book in LabeledContent(book.title, value: Shelf.tierText(book)) }
                }
            }
            if !shelf.readBefore.isEmpty {
                Section("Read in the year before Stadig Mind") {
                    ForEach(shelf.readBefore) { book in FinishedRow(book: book, level: nil) }
                }
            }
        }
        .navigationTitle("Your shelf")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("shelf.done") } }
        .modifier(BookSheets(editing: $editing, finishing: $finishing, settingAside: $settingAside))
        .modifier(AddBookSheet(isPresented: Binding(get: { model.addingBook }, set: { model.addingBook = $0 })))
    }
}

/// What the shelf says about a book, and what it suggests next: shared by the iPhone's sheet and
/// the wide destination.
enum Shelf {
    static func tierText(_ book: Book) -> String {
        let estimated = book.ladderID == nil || (book.tierConfidence ?? 1) < 1
        return "tier \(book.tier)\(estimated ? " (estimated)" : "")"
    }

    /// "Frank Herbert · tier 4 · page 120 of 600 · print"
    static func detail(_ book: Book) -> String {
        [book.author, tierText(book), "page \(book.page) of \(book.pages)", book.format?.label.lowercased()]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @MainActor
    static func suggestions(_ model: AppModel) -> [LadderBook] {
        ReadingPlan.suggestions(
            shelf: model.books, tests: model.tests, genres: model.settings?.genres ?? [], on: model.today, dayStart: model.dayStart,
            ladder: model.catalogs.ladder)
    }

    /// `-findBook <title, author or ISBN>` opens the finder already searching for it.
    static var debugQuery: String {
        #if DEBUG
        if let query = LaunchOptions.current.value(after: "-findBook") { return query }
        #endif
        return ""
    }
}

/// Why the shelf's buttons wait while a session is open: on the Mac the shelf stays in reach beside
/// the session's window.
struct BooksLockedNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.booksLocked {
            Label("A session is open. Books can be changed once it ends, so its reading block doesn't save over the change.", systemImage: "lock")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("shelf.booksLocked")
        }
    }
}

/// Finishing, editing or setting aside a book.
struct BookSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var editing: Book?
    @Binding var finishing: Book?
    @Binding var settingAside: Book?

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { book in BookEditor(book: book) { model.save(book: $0) } }
            .sheet(item: $finishing) { book in
                // Switching "I finished it" off logs the page instead: the book carries on.
                PageSheet(book: book, finished: true) { page, finished, feel, _ in
                    var done = book
                    if finished {
                        done.status = .finished
                        done.page = book.pages
                        done.finished = model.today
                        done.feel = feel ?? .right
                    } else {
                        done.page = page
                    }
                    model.save(book: done)
                }
            }
            .sheet(item: $settingAside) { book in
                SetAsideSheet(book: book) { feel in
                    var aside = book
                    aside.status = .abandoned
                    aside.finished = model.today
                    aside.feel = feel
                    model.save(book: aside)
                }
            }
    }
}

/// The book finder, for a book to read now: it goes on the shelf as the one on the go.
struct AddBookSheet: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            BookFinder(initialQuery: Shelf.debugQuery) { book in
                var book = book
                book.started = model.today
                model.startReading(book)
            }
        }
    }
}

/// Level and focus side by side: two separate measures, and the next tier and block they set.
struct LevelRows: View {
    @Environment(AppModel.self) private var model
    let reading: ReadingSummary

    var body: some View {
        LabeledContent("Level") {
            Text(reading.level.map { "Tier \(ReadingPlan.format($0)) of 10" } ?? "From the reading test")
        }
        if let test = reading.test, let tested = reading.testedLevel {
            LabeledContent("Reading test") {
                Text(
                    "Tier \(ReadingPlan.format(tested)) · \(Format.day(test.day(startingAt: model.dayStart), style: .dateTime.month(.abbreviated).day()))"
                )
            }
        }
        LabeledContent("Next book", value: "Tier \(reading.targetTier)")
        LabeledContent("Focus") {
            Text(reading.stamina.map { "About \(Int($0)) min" } ?? "Measured as you read")
        }
        LabeledContent("Next reading block", value: "\(reading.nextBlock) min")
    }
}

struct FinishedRow: View {
    let book: Book
    let level: Double?

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let feel = book.feel { Text(feel.label).font(.subheadline).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    var color: Color {
        switch book.feel {
        case .easy: .green
        case .right: .orange
        case .hard: .red
        case nil: .secondary
        }
    }

    /// The book's tier, with where the reader's feedback puts it when that differs.
    var detail: String {
        var parts = ["Tier \(book.tier)"]
        let refined = BookLevel.refined(book, readerLevel: level)
        if abs(refined - Double(book.tier)) >= 0.5 { parts[0] += ", felt nearer \(ReadingPlan.format(refined))" }
        if book.format == .audiobook { parts.append("audiobook") }
        if let finished = book.finished, book.status == .finished { parts.append(Format.day(finished)) }
        return parts.joined(separator: " · ")
    }
}

/// Setting a book aside: whether it was too hard says something about level; boredom doesn't.
struct SetAsideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let save: (BookFeel?) -> Void
    @State private var feel: BookFeel?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColourRating(selection: $feel)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("How was it going?")
                } footer: {
                    Text(
                        "Set aside as a slog, the next book steps back a tier. Easy or just right, it's taste, not difficulty, and nothing changes. Either way it's fine to stop."
                    )
                }
            }
            .navigationTitle("Set it aside")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("setAside.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set aside") {
                        save(feel)
                        dismiss()
                    }
                    .accessibilityIdentifier("setAside.save")
                }
            }
        }
        .presentationDetents([.medium])
        .sheetForm(height: 320)
    }
}
