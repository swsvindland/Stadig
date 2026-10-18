import MindEngine
import SwiftUI
import SystemCore

/// The graded reader on the go in a language, and its own reading level.
struct ReadersSection: View {
    @Environment(AppModel.self) private var model
    let language: Language
    let state: StudyState
    @State private var showing = false

    var body: some View {
        let books = state.books
        let current = GradedReaders.current(language, books: books)
        let comfort = GradedReaders.comfortLevel(language, books: books)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Books in \(language.pack.name)", systemImage: "books.vertical").font(.subheadline.weight(.semibold))
                Spacer()
                Button(current == nil ? "Choose one" : "Update") { showing = true }.buttonStyle(.borderless)
                    .accessibilityIdentifier("progress.readers.\(language.domain.rawValue)")
            }
            if let current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.subheadline.weight(.medium))
                    Text("Level \(current.tier) · page \(current.page) of \(current.pages)").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: current.progress).tint(language.domain.color)
                }
            }
            Text(
                comfort.map { "Reading level \($0) of 6, \(GradedReaders.label($0).lowercased()). Its own level, beside English." }
                    ?? "Finish a reader to set your \(language.pack.name) reading level. It's separate from English."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showing) { ReaderSheet(language: language) }
    }
}

/// Choose a reader at your level, or log where you are in the one on the go.
struct ReaderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let language: Language
    @State private var page = 0
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            Form {
                if let current = GradedReaders.current(language, books: model.books) {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.title).font(.headline)
                            Text("\(current.author) · level \(current.tier)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Stepper("Page \(page) of \(current.pages)", value: $page, in: 0...current.pages, step: 5)
                            .accessibilityIdentifier("readers.page")
                        Button("Save the page") { save(current, page: page) }.disabled(page == current.page)
                            .accessibilityIdentifier("readers.savePage")
                        Button("I've finished it") { finishing = true }
                            .accessibilityIdentifier("readers.finished")
                        Button("Put it down", role: .destructive) {
                            var book = current
                            book.status = .abandoned
                            book.finished = model.today
                            model.save(book: book)
                        }
                        .accessibilityIdentifier("readers.putDown")
                    } header: {
                        Text("Reading now")
                    }
                    // Starting another reader from the list below keeps this section on screen.
                    .onChange(of: current.id, initial: true) { page = current.page }
                    .confirmationDialog("How did it feel?", isPresented: $finishing, titleVisibility: .visible) {
                        ForEach(BookFeel.allCases) { feel in
                            Button(feel.label) { finish(current, feel: feel) }
                                .accessibilityIdentifier("readers.feel.\(feel.rawValue)")
                        }
                    } message: {
                        Text("Easy or just right moves your \(language.pack.name) reading level up; a slog holds it.")
                    }
                }
                let words = model.state?.latest(.vocabulary, in: language.domain).map { Int($0.score) }
                let suggestions = GradedReaders.suggestions(language, books: model.books, words: words)
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { ReaderRow(reader: $0) }
                    } header: {
                        Text("At your level")
                    } footer: {
                        Text(
                            "Level \(GradedReaders.targetLevel(language, books: model.books, words: words)) next: one above the last that felt comfortable, or where your vocabulary says to start."
                        )
                    }
                }
                ForEach(Array(GradedReaders.levels), id: \.self) { level in
                    let readers = GradedReaders.readers(language).filter { $0.level == level && !suggestions.contains($0) }
                    if !readers.isEmpty {
                        Section("Level \(level): \(GradedReaders.label(level))") {
                            ForEach(readers) { ReaderRow(reader: $0) }
                        }
                    }
                }
            }
            .navigationTitle("\(language.pack.name) readers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("readers.done") } }
        }
    }

    func save(_ book: Book, page: Int) {
        var book = book
        book.page = page
        model.save(book: book)
    }

    func finish(_ book: Book, feel: BookFeel) {
        var book = book
        book.status = .finished
        book.finished = model.today
        book.page = book.pages
        book.feel = feel
        model.save(book: book)
    }
}

private struct ReaderRow: View {
    @Environment(AppModel.self) private var model
    let reader: GradedReader

    var body: some View {
        let shelf = model.books.first { $0.ladderID == reader.id }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(reader.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("Level \(reader.level)").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(reader.author) · about \(reader.pages) pages").font(.caption).foregroundStyle(.secondary)
            Text(reader.about).font(.caption)
            HStack(spacing: 16) {
                if let shelf {
                    Text(shelf.status == .reading ? "Reading now" : shelf.done ? "Finished" : "Put down").font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Start reading") { model.start(reader: reader) }.font(.caption.weight(.semibold))
                        .accessibilityIdentifier("readers.start.\(reader.id)")
                }
                if let free = reader.free { Link("Read it free", destination: free).font(.caption.weight(.semibold)) }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

extension AppModel {
    /// Starts a reader. Another reader in the same language on the go is put down; English books
    /// and other languages' readers carry on.
    func start(reader: GradedReader) {
        startReading(reader.book(status: .reading, started: today))
    }
}
