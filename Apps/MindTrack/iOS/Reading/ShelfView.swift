import SwiftUI
import MindEngine
import SystemCore

/// Books: where you are, the one on the go, what the ladder suggests next, and what's been read.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Book?
    @State private var adding = false
    @State private var finishing: Book?
    @State private var settingAside: Book?

    var body: some View {
        let shelf = model.books.filter { $0.language == nil }
        let reading = model.analysis?.reading
        List {
            if let reading {
                Section {
                    LevelRows(reading: reading)
                } footer: {
                    Text("Level comes from the reading test and how finished books felt. Focus comes from reading blocks on print and ebooks. Neither moves on time alone.")
                }
            }
            if let current = shelf.first(where: { $0.status == .reading }) {
                Section("Reading now") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title).font(.headline)
                        Text([current.author, tierText(current), "page \(current.page) of \(current.pages)", current.format?.label.lowercased()]
                            .compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("Finished it", systemImage: "checkmark") { finishing = current }
                    Button("Edit", systemImage: "pencil") { editing = current }
                    Button("Set it aside", systemImage: "xmark.bin", role: .destructive) { settingAside = current }
                }
            }
            Section {
                ForEach(ReadingPlan.suggestions(shelf: model.books, tests: model.tests, genres: model.settings?.genres ?? [], on: model.today,
                                                ladder: model.catalogs.ladder)) { book in
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
                }
                Button("Add a book", systemImage: "plus") { adding = true }
            } header: {
                Text("Suggested next")
            } footer: {
                Text("At the tier your reading is ready for. Starting one sets aside the book you're on.")
            }
            let finished = shelf.filter { $0.status == .finished }.sorted { ($0.finished ?? .today) > ($1.finished ?? .today) }
            if !finished.isEmpty {
                Section("Finished") {
                    ForEach(finished) { book in FinishedRow(book: book, level: reading?.level) }
                }
            }
            let aside = shelf.filter { $0.status == .abandoned }.sorted { ($0.finished ?? .today) > ($1.finished ?? .today) }
            if !aside.isEmpty {
                Section("Set aside") {
                    ForEach(aside) { book in LabeledContent(book.title, value: tierText(book)) }
                }
            }
            let before = shelf.filter { $0.status == .readBefore }
            if !before.isEmpty {
                Section("Read in the year before Mind Track") {
                    ForEach(before) { book in FinishedRow(book: book, level: nil) }
                }
            }
        }
        .navigationTitle("Your shelf")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editing) { book in BookEditor(book: book) { model.save(book: $0) } }
        .sheet(isPresented: $adding) {
            BookFinder(initialQuery: debugQuery) { book in
                for var current in model.books where current.status == .reading && current.language == book.language {
                    current.status = .abandoned
                    current.finished = model.today
                    model.save(book: current)
                }
                var book = book
                book.started = model.today
                model.save(book: book)
            }
        }
        .sheet(item: $finishing) { book in
            PageSheet(book: book, finished: true) { _, _, feel, _ in
                var done = book
                done.status = .finished
                done.page = book.pages
                done.finished = model.today
                done.feel = feel ?? .right
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
        #if DEBUG
        // -findBook <title, author or ISBN> opens the finder searching for it.
        .onAppear { if !debugQuery.isEmpty { adding = true } }
        #endif
    }

    func tierText(_ book: Book) -> String {
        let estimated = book.ladderID == nil || (book.tierConfidence ?? 1) < 1
        return "tier \(book.tier)\(estimated ? " (estimated)" : "")"
    }

    var debugQuery: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-findBook"), arguments.indices.contains(i + 1) { return arguments[i + 1] }
        #endif
        return ""
    }
}

/// Level and focus side by side: two separate measures, and the next tier and block they set.
struct LevelRows: View {
    let reading: ReadingSummary

    var body: some View {
        LabeledContent("Level") {
            Text(reading.level.map { "Tier \(ReadingPlan.format($0)) of 10" } ?? "From the reading test")
        }
        if let test = reading.test, let tested = reading.testedLevel {
            LabeledContent("Reading test") {
                Text("Tier \(ReadingPlan.format(tested)) · \(Format.day(test.day, style: .dateTime.month(.abbreviated).day()))")
            }
        }
        LabeledContent("Next book", value: "Tier \(reading.targetTier)")
        LabeledContent("Focus") {
            Text(reading.stamina.map { "About \(Int($0)) min" } ?? "Measured as you read")
        }
        LabeledContent("Next reading block", value: "\(reading.nextBlock) min")
    }
}

private struct FinishedRow: View {
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
                    Text("Set aside as a slog, the next book steps back a tier. Easy or just right, it's taste, not difficulty, and nothing changes. Either way it's fine to stop.")
                }
            }
            .navigationTitle("Set it aside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set aside") {
                        save(feel)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
