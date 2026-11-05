import MindEngine
import SwiftUI
import SystemCore

/// Reading: genres you enjoy, and recent reading only (now, and the last twelve months), each
/// marked print, ebook or audiobook. Books read years ago say what you did, not what you can do
/// now, so the first session's reading test does the placing.
struct ReadingOnboarding: View {
    @Binding var settings: MindSettings
    @Binding var books: [Book]
    @State private var adding: BookStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading").font(.title.bold())
                .accessibilityIdentifier("onboarding.readingTitle")
            Text(
                "Your level comes from a short reading test in its first block: a few passages, a few questions each. Here, only what you're reading now and what you've read in the last twelve months."
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Genres you enjoy").font(.headline)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Genre.allCases) { genre in
                        let on = settings.genres.contains(genre)
                        Button {
                            if on { settings.genres.removeAll { $0 == genre } } else { settings.genres.append(genre) }
                        } label: {
                            Text(genre.label).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: .capsule)
                                .foregroundStyle(on ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("onboarding.genre.\(genre.rawValue)")
                    }
                }
            }
            .card()
            BookList(
                title: "What are you reading now?", books: books.filter { $0.status == .reading },
                add: books.contains { $0.status == .reading } ? nil : "Add the book you're reading",
                remove: remove
            ) { adding = .reading }
            BookList(
                title: "What have you read in the last 12 months?", books: books.filter { $0.status == .readBefore },
                add: "Add a book", remove: remove
            ) { adding = .readBefore }
            Label(
                "Audiobooks count for understanding and taste, not reading stamina. Stamina is measured from your first reading blocks.",
                systemImage: "headphones"
            )
            .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $adding) { status in
            BookFinder(status: status, title: status == .reading ? "Reading now" : "Read in the last year") { book in books.append(book) }
        }
    }

    func remove(_ book: Book) { books.removeAll { $0.id == book.id } }

    static func firstSession(_ settings: MindSettings, books: [Book]) -> String? {
        let test = "Reading: a short test, a few passages with questions, to find your level"
        if let current = books.first(where: { $0.status == .reading }) { return "\(test), then carry on with \(current.title)" }
        return test
    }
}

private struct BookList: View {
    let title: String
    let books: [Book]
    let add: String?
    let remove: (Book) -> Void
    let adding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(books) { book in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(book.title).font(.body)
                        Text(
                            [book.author, (book.format ?? .print).label.lowercased(), book.feel?.label.lowercased()].compactMap { $0 }
                                .filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { remove(book) }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.removeBook.\(book.id)")
                }
            }
            if let add {
                Button(add, systemImage: "plus", action: adding).font(.subheadline)
                    .accessibilityIdentifier("onboarding.addBook")
            }
        }
        .card()
    }
}

extension BookStatus: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Genres for the ladder's suggestions, the shelf, and where the passages and book data come from.
struct ReadingSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings
    let dismiss: () -> Void

    var body: some View {
        Section {
            ForEach(Genre.allCases) { genre in
                Toggle(
                    genre.label,
                    isOn: Binding(
                        get: { settings.genres.contains(genre) },
                        set: { on in
                            var s = settings
                            s.genres = on ? s.genres + [genre] : s.genres.filter { $0 != genre }
                            model.save(settings: s)
                        })
                )
                .accessibilityIdentifier("settings.genre.\(genre.rawValue)")
            }
            Button("Your shelf", systemImage: "books.vertical") {
                dismiss()
                model.showShelf = true
            }
            .rowButton()
            .accessibilityIdentifier("settings.shelf")
        } header: {
            Text("Reading")
        } footer: {
            Text(
                "Reading-test passages are public-domain excerpts from Project Gutenberg, and a few written for Stadig Mind. Book details come from Open Library, with Google Books as a backup; covers are read on your \(Platform.deviceName)."
            )
        }
    }
}
