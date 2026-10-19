import MindEngine
import SwiftUI
import SystemCore

/// What's selected in Writing: a piece, a draft waiting for its task, or a reflection.
enum WritingSelection: Hashable {
    case piece(UUID)
    case draft(String)
    case reflection(UUID)
}

/// Your writing as a destination of its own in a wide window: drafts in progress, every piece
/// handed in (with its slips and notes beside it) and what you noted after reading. On an iPhone
/// the same pieces and reflections are reached from Progress.
struct WritingDestination: View {
    @Environment(AppModel.self) private var model
    @State private var selection: WritingSelection?
    @State private var query = ""
    @State private var drafts: [WritingDrafts.Entry] = []
    /// What the list shows, searched and sorted when the search or the records change rather than
    /// on every redraw: years of pieces add up.
    @State private var pieces: [WritingPiece] = []
    @State private var reflections: [Reflection] = []

    var body: some View {
        let shownDrafts = drafts.filter { LibrarySearch.matches(query, $0.draft.text, $0.draft.ownPage ?? "") }
        NavigationStack {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    if !shownDrafts.isEmpty {
                        Section {
                            ForEach(shownDrafts) { entry in
                                WritingRow(
                                    symbol: entry.exercise?.symbol ?? "pencil", title: entry.exercise?.label ?? "Writing",
                                    date: entry.saved, text: entry.draft.text.isEmpty ? "A page written with Apple Pencil" : entry.draft.text,
                                    handwritten: entry.draft.handwritten
                                )
                                .tag(WritingSelection.draft(entry.key))
                            }
                        } header: {
                            Text("In progress")
                        }
                    }
                    Section("Pieces") {
                        ForEach(pieces) { piece in
                            WritingRow(
                                symbol: piece.exercise.symbol, title: piece.exercise.label, date: piece.date,
                                text: piece.text.isEmpty ? piece.notes ?? "" : piece.text, handwritten: piece.source == .handwritten
                            )
                            .tag(WritingSelection.piece(piece.id))
                            .accessibilityIdentifier("writingList.piece")
                        }
                    }
                    if !reflections.isEmpty {
                        Section("After reading") {
                            ForEach(reflections) { reflection in
                                WritingRow(
                                    symbol: "text.quote", title: title(of: reflection), date: reflection.date, text: reflection.text,
                                    handwritten: false, color: Domain.reading.color
                                )
                                .tag(WritingSelection.reflection(reflection.id))
                            }
                        }
                    }
                }
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
                .overlay {
                    if pieces.isEmpty, shownDrafts.isEmpty, reflections.isEmpty {
                        if query.isEmpty {
                            ContentUnavailableView(
                                "Nothing written yet", systemImage: "doc.richtext",
                                description: Text("Pieces from writing sessions, and what you note after reading, collect here."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Writing")
            .searchable(text: $query, prompt: "Prompts, pieces and notes")
            .toolbar {
                if model.settings?.has(.writing) == true {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Write Now", systemImage: "square.and.pencil") { model.startSession([.writing]) }
                            .disabled(model.run != nil)
                            .help("Start a writing session")
                            .accessibilityIdentifier("writingList.writeNow")
                    }
                }
            }
            .background(.pageBackground)
        }
        // Again after a session, which may have handed one in or left one.
        .task(id: model.run == nil) { drafts = await model.drafts.all() }
        .onChange(of: query, initial: true) { refilter() }
        .onChange(of: model.pieces) { refilter() }
        .onChange(of: model.reflections) { refilter() }
        .onAppear {
            if selection == nil, let newest = PieceSearch.matching(model.pieces, query: "").first { selection = .piece(newest.id) }
        }
    }

    func refilter() {
        pieces = PieceSearch.matching(model.pieces, query: query)
        reflections = model.reflections.reversed().filter { LibrarySearch.matches(query, $0.text, title(of: $0)) }
    }

    func title(of reflection: Reflection) -> String { model.books.first { $0.id == reflection.bookID }?.title ?? "Reading" }

    @ViewBuilder var detail: some View {
        switch selection {
        case .piece(let id):
            PieceView(id: id)
        case .draft(let key):
            if let entry = drafts.first(where: { $0.key == key }) {
                DraftView(entry: entry)
            } else {
                ContentUnavailableView("Handed in", systemImage: "checkmark.circle", description: Text("That draft is a piece now."))
            }
        case .reflection(let id):
            if let reflection = model.reflections.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(title(of: reflection), systemImage: Domain.reading.symbol).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Domain.reading.color)
                        Text(reflection.text).font(.writing).lineSpacing(LineSpacing.writing).textSelection(.enabled)
                        Text(reflection.date.formatted(date: .complete, time: .omitted) + (reflection.page.map { " · page \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .card()
                    .padding(24)
                    .readableWidth(680)
                }
            }
        case nil:
            ContentUnavailableView(
                "Choose a piece", systemImage: "doc.richtext", description: Text("Its slips, the notes on it and what it worked from."))
        }
    }
}

/// A piece, draft or reflection in Writing's list.
private struct WritingRow: View {
    let symbol: String
    let title: String
    let date: Date
    let text: String
    let handwritten: Bool
    var color: Color = Domain.writing.color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Text(text).font(.subheadline).lineLimit(2)
            if handwritten {
                Label("Handwritten", systemImage: "pencil.and.scribble").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A draft kept on this device: what's written so far. It comes back with its task.
private struct DraftView: View {
    let entry: WritingDrafts.Entry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(entry.exercise?.label ?? "Writing", systemImage: entry.exercise?.symbol ?? "pencil")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Domain.writing.color)
                Label(
                    "In progress on this \(Platform.deviceName). It comes back with its task in your next writing session, to finish and hand in.",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.subheadline).foregroundStyle(.secondary)
                if let ownPage = entry.draft.ownPage {
                    TextCard(title: "Your page", detail: nil, text: Text(ownPage))
                }
                if !entry.draft.text.isEmpty {
                    let words = entry.draft.text.split { $0.isWhitespace || $0.isNewline }.count
                    TextCard(
                        title: entry.draft.handwritten ? "Read from your handwriting" : "So far", detail: "\(words) words",
                        text: Text(entry.draft.text))
                } else if entry.draft.drawing != nil {
                    Text("Written with Apple Pencil, not read into text yet.").foregroundStyle(.secondary)
                }
                Text("Saved \(entry.saved.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .readableWidth(680)
        }
    }
}
