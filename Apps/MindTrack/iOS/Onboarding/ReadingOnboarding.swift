import SwiftUI
import MindEngine
import SystemCore

/// Reading: genres you enjoy, and only recent reading (now, and the last twelve months). Older
/// books say little about where you are today; the reading test does the placing.
struct ReadingOnboarding: View {
    @Binding var settings: MindSettings
    @Binding var books: [Book]
    @State private var adding: BookStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading").font(.title.bold())
            Text("What you're reading now and what you've read in the last year. Audiobooks count for taste and understanding, not stamina.")
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
                    }
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent reading").font(.headline)
                ForEach(books) { book in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book.title).font(.body)
                            Text([book.author, book.status == .reading ? "reading now" : "finished", book.format?.label.lowercased()]
                                .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { books.removeAll { $0.id == book.id } }
                            .labelStyle(.iconOnly).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if !books.contains(where: { $0.status == .reading }) {
                        Button("Reading now", systemImage: "plus") { adding = .reading }
                    }
                    Spacer()
                    Button("Finished this year", systemImage: "plus") { adding = .readBefore }
                }
                .font(.subheadline)
            }
            .card()
        }
        .sheet(item: $adding) { status in
            BookEditor(book: nil, status: status) { book in books.append(book) }
        }
    }

    static func firstSession(_ settings: MindSettings, books: [Book]) -> String? {
        if let current = books.first(where: { $0.status == .reading }) { return "Reading: carry on with \(current.title)" }
        return "Reading: your ladder starts at tier \(ReadingPlan.targetTier(books))"
    }
}

extension BookStatus: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Genres for the ladder's suggestions, and the shelf.
struct ReadingSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings
    let dismiss: () -> Void

    var body: some View {
        Section("Reading") {
            ForEach(Genre.allCases) { genre in
                Toggle(genre.label, isOn: Binding(get: { settings.genres.contains(genre) }, set: { on in
                    var s = settings
                    s.genres = on ? s.genres + [genre] : s.genres.filter { $0 != genre }
                    model.save(settings: s)
                }))
            }
            Button("Your shelf", systemImage: "books.vertical") {
                dismiss()
                model.showShelf = true
            }
        }
    }
}
