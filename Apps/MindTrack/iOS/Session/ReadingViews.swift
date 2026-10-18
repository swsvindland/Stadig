import MindEngine
import SwiftUI
import SystemCore

/// No book on the go: the ladder's three suggestions at the next tier, or a book of your own.
struct PickBookView: View {
    @Environment(AppModel.self) private var model
    let options: [LadderBook]
    @State private var addingOwn = false

    var body: some View {
        let reading = model.analysis?.reading
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your next book").font(.title.bold())
                Text(reading.map(intro) ?? "Near your level, in the genres you like.").foregroundStyle(.secondary)
                ForEach(options) { book in
                    Button {
                        model.act { $0.pickBook(book, now: Date()) }
                    } label: {
                        LadderBookRow(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pickBook.book.\(book.id)")
                }
                Button("Add a book of your own", systemImage: "plus") { addingOwn = true }
                    .accessibilityIdentifier("pickBook.addOwn")
                    .padding(.top, 4)
                Button("Not today") { model.act { $0.skipPart(now: Date()) } }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pickBook.notToday")
            }
            .padding(20)
            .readableWidth(640)
        }
        .sheet(isPresented: $addingOwn) {
            BookFinder { book in model.act { $0.addBook(book, now: Date()) } }
        }
    }

    func intro(_ reading: ReadingSummary) -> String {
        guard let tested = reading.testedLevel else { return "Tier \(reading.targetTier), in the genres you like." }
        if reading.finished.isEmpty {
            return
                "Tier \(reading.targetTier): just below the tier \(ReadingPlan.format(tested)) your reading test found, so it starts comfortably and climbs."
        }
        return "Tier \(reading.targetTier), from your test and how your last books felt, in the genres you like."
    }
}

struct LadderBookRow: View {
    let book: LadderBook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(book.title).font(.headline)
                Spacer()
                Pill(text: "Tier \(book.tier)", color: .teal)
            }
            Text("\(book.author) · \(book.pages) pages").font(.subheadline).foregroundStyle(.secondary)
            Text(book.note).font(.footnote)
        }
        .card()
        .contentShape(.rect)
    }
}

/// The reading block: a quiet timer as long as focus has held so far, then where the bookmark is.
struct ReadingTimerView: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let minutes: Int
    @State private var started = Date()
    @State private var logging = false

    var listening: Bool { book.format == .audiobook }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text(book.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(book.author) · page \(book.page) of \(book.pages)").font(.subheadline).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(started)
                        let left = max(0, Double(minutes) * 60 - elapsed)
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().stroke(Color.teal.opacity(0.18), lineWidth: 12)
                                Circle().trim(from: 0, to: min(1, elapsed / max(1, Double(minutes) * 60)))
                                    .stroke(Color.teal.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text(left > 0 ? Duration.seconds(left).formatted(.time(pattern: .minuteSecond)) : "Time")
                                    .font(.system(size: 44, weight: .light).monospacedDigit())
                            }
                            .frame(width: 220, height: 220)
                            Text(
                                left > 0
                                    ? (listening ? "Listen. The phone can go face down." : "Read. The phone can go face down.")
                                    : "That's the block. Finish the page, or keep going if focus holds."
                            )
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    if !listening {
                        Text("A \(minutes)-minute block: as long as your focus has held so far. It grows while it keeps holding.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let last = model.reflections.last(where: { $0.bookID == book.id }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last time you noted").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(last.text).font(.subheadline)
                        }
                        .card()
                    }
                }
                .padding(24)
                .readableWidth(560)
            }
            BottomBar {
                Button {
                    logging = true
                } label: {
                    Text(listening ? "Done listening" : "Done reading").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .accessibilityIdentifier("reading.done")
            }
        }
        .sheet(isPresented: $logging) {
            PageSheet(book: book, asksFocus: (book.format ?? .print).countsForStamina) { page, finished, feel, focus in
                let minutes = Date().timeIntervalSince(started) / 60
                model.act { $0.finishReading(page: page, finished: finished, feel: feel, minutes: minutes, focus: focus, now: Date()) }
            }
        }
    }
}

/// The three-tap colour rating, as after a set in Lift Track: green, orange or red.
struct ColourRating<Value: Hashable>: View {
    struct Option {
        var value: Value
        var label: String
        var detail: String
        var color: Color
    }

    let options: [Option]
    @Binding var selection: Value?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                let chosen = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    VStack(spacing: 4) {
                        Text(option.label).font(.subheadline.weight(.semibold))
                        Text(option.detail).font(.caption2).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(option.color.gradient, in: .rect(cornerRadius: 16))
                    .overlay {
                        if chosen { RoundedRectangle(cornerRadius: 16).stroke(.primary, lineWidth: 3) }
                    }
                    .opacity(selection == nil || chosen ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label): \(option.detail)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .animation(.snappy, value: selection)
    }
}

extension ColourRating where Value == BookFeel {
    init(selection: Binding<BookFeel?>) {
        self.init(
            options: [
                .init(value: .easy, label: BookFeel.easy.label, detail: "Breezed through it", color: .green),
                .init(value: .right, label: BookFeel.right.label, detail: "A stretch, in a good way", color: .orange),
                .init(value: .hard, label: BookFeel.hard.label, detail: "Hard going", color: .red),
            ], selection: selection)
    }
}

extension ColourRating where Value == ReadingFocus {
    init(selection: Binding<ReadingFocus?>) {
        self.init(
            options: [
                .init(value: .held, label: ReadingFocus.held.label, detail: "All the way through", color: .green),
                .init(value: .drifted, label: ReadingFocus.drifted.label, detail: "Wandered near the end", color: .orange),
                .init(value: .lost, label: ReadingFocus.lost.label, detail: "Couldn't settle", color: .red),
            ], selection: selection)
    }
}

/// Where the bookmark is now, how focus held, and how the book felt if it's finished.
struct PageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    var asksFocus = false
    let save: (Int, Bool, BookFeel?, ReadingFocus?) -> Void
    @State private var page: Int
    @State private var finished = false
    @State private var feel: BookFeel?
    @State private var focus: ReadingFocus?

    /// Where the bookmark was.
    var from: Int { book.page }

    /// The page given, kept within the book.
    var bookmark: Int {
        var read = book
        read.page = page
        return read.normalized().page
    }

    init(book: Book, finished: Bool = false, asksFocus: Bool = false, save: @escaping (Int, Bool, BookFeel?, ReadingFocus?) -> Void) {
        // Kept within its bounds: a page count corrected below the bookmark (another edition)
        // mustn't make the range run backwards.
        let book = book.normalized()
        self.book = book
        self.asksFocus = asksFocus
        self.save = save
        _page = State(initialValue: min(book.pages, book.page + 20))
        _finished = State(initialValue: finished)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("I finished it", isOn: $finished)
                        .accessibilityIdentifier("pageSheet.finished")
                    if !finished {
                        Stepper(value: $page, in: from...book.pages, step: 1) {
                            LabeledContent("Now on page", value: "\(page)")
                        }
                        .accessibilityIdentifier("pageSheet.stepper")
                        TextField("Page", value: $page, format: .number).keyboardType(.numberPad)
                            .accessibilityIdentifier("pageSheet.page")
                    }
                } footer: {
                    if !finished { Text("\(max(0, page - from)) pages this time.") }
                }
                if asksFocus {
                    Section {
                        ColourRating(selection: $focus)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    } header: {
                        Text("How did your focus hold?")
                    } footer: {
                        Text(
                            "This sets the next block: longer while focus holds, the same when it drifts, shorter when it's lost. It's apart from how hard the book is."
                        )
                    }
                }
                if finished {
                    Section {
                        ColourRating(selection: $feel)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    } header: {
                        Text("How did it feel?")
                    } footer: {
                        Text(
                            "Easy moves the next book up a tier and just right half a tier; a slog holds it. It also refines this book's level and yours."
                        )
                    }
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(bookmark, finished, finished ? (feel ?? .right) : nil, asksFocus ? focus : nil)
                        dismiss()
                    }
                    .disabled(finished && feel == nil)
                    .accessibilityIdentifier("pageSheet.save")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("pageSheet.cancel") }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A few sentences after reading.
struct ReflectView: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let finished: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(finished ? "What will you keep from it?" : "What happened, and what struck you?").font(.title2.bold())
                    Text(
                        finished
                            ? "A few sentences about \(book.title) as a whole." : "Two or three sentences are plenty. Next time starts with them."
                    )
                    .foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(.cardBackground, in: .rect(cornerRadius: 16))
                        .focused($focused)
                }
                .padding(20)
                .readableWidth(640)
            }
            BottomBar {
                HStack(spacing: 12) {
                    Button {
                        model.act { $0.reflect(nil, now: Date()) }
                    } label: {
                        Text("Skip").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .controlSize(.large)
                    .accessibilityIdentifier("reflect.skip")
                    Button {
                        let note = text
                        model.act { $0.reflect(note, now: Date()) }
                    } label: {
                        Text("Save").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.large)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("reflect.save")
                }
            }
        }
        .onAppear { focused = true }
    }
}

/// A book's details before it goes on the shelf: from a search, scan or cover (with its estimated
/// level and where the estimate comes from), or typed in, or an existing book being edited.
struct BookEditor: View {
    @Environment(\.dismiss) private var dismiss
    var book: Book?
    var draft: BookDraft?
    /// For a new book: reading now, or finished in the last year.
    var status: BookStatus = .reading
    let save: (Book) -> Void
    @State private var title = ""
    @State private var author = ""
    @State private var pages = 300
    @State private var tier = 3
    @State private var estimatedTier: Int?
    @State private var genre: Genre = .literary
    @State private var format: BookFormat = .print
    @State private var feel: BookFeel?

    init(book: Book? = nil, draft: BookDraft? = nil, status: BookStatus = .reading, save: @escaping (Book) -> Void) {
        self.book = book
        self.draft = draft
        self.status = status
        self.save = save
    }

    var finishedBefore: Bool { (book?.status ?? status) == .readBefore }
    var setByHand: Bool { estimatedTier.map { $0 != tier } ?? (book == nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("bookEditor.title")
                    TextField("Author", text: $author)
                        .accessibilityIdentifier("bookEditor.author")
                    Stepper(value: $pages, in: 40...2000, step: 10) { LabeledContent("Pages", value: "\(pages)") }
                        .accessibilityIdentifier("bookEditor.pages")
                    Picker("Genre", selection: $genre) { ForEach(Genre.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    Picker("Format", selection: $format) { ForEach(BookFormat.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                } footer: {
                    Text(
                        format == .audiobook
                            ? "Audiobooks count for understanding and taste, not reading stamina."
                            : "Print and ebooks build reading stamina as well as level.")
                }
                if finishedBefore {
                    Section("How did it feel?") {
                        ColourRating(selection: $feel)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
                Section {
                    Stepper(value: $tier, in: 1...10) { LabeledContent("Tier", value: "\(tier) of 10") }
                    let examples = ReadingLadder.standard.handLevelled.filter { $0.tier == tier && $0.title != title }.prefix(3).map(\.title)
                    if !examples.isEmpty {
                        Text("About as hard as \(ListFormatter.localizedString(byJoining: examples)).").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How hard to read")
                } footer: {
                    Text(levelNote)
                }
            }
            .navigationTitle(book == nil ? "Add a book" : "Edit book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("bookEditor.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(edited)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (finishedBefore && feel == nil))
                    .accessibilityIdentifier("bookEditor.save")
                }
            }
            .onAppear(perform: fill)
        }
    }

    /// Where the tier comes from, and how much it counts.
    var levelNote: String {
        if setByHand { return "Set by you. A tier chosen by hand counts for less towards your level than one from the ladder." }
        if let draft { return draft.estimate.explanation + "." }
        return ReadingLadder.standard.tier(tier)?.description ?? ""
    }

    var edited: Book {
        var edited =
            book
            ?? Book(
                ladderID: draft?.ladderID, title: title, author: author, tier: tier, pages: pages, genres: [genre],
                status: status, isbn: draft?.isbn)
        edited.title = title
        edited.author = author
        edited.tier = tier
        edited.pages = pages
        edited.genres = [genre]
        edited.format = format
        if setByHand {
            edited.tierConfidence = BookLevel.guessConfidence
        } else if let draft, book == nil {
            edited.tierConfidence = draft.estimate.confidence
        }
        if edited.status == .readBefore {
            edited.feel = feel
            edited.page = edited.pages
            edited.finished = edited.finished ?? Day.today
        }
        // Fewer pages than the bookmark (another edition): the bookmark moves to the end.
        return edited.normalized()
    }

    func fill() {
        if let book {
            title = book.title
            author = book.author
            pages = book.pages
            tier = book.tier
            estimatedTier = book.tierConfidence == BookLevel.guessConfidence ? nil : book.tier
            genre = book.genres.first ?? .literary
            format = book.format ?? .print
            feel = book.feel
        } else if let draft {
            title = draft.title
            author = draft.author
            pages = draft.pages ?? 300
            tier = draft.estimate.roundedTier
            estimatedTier = draft.title.isEmpty ? nil : draft.estimate.roundedTier
            genre = draft.genres.first ?? draft.estimate.genres.first ?? .literary
        }
    }
}
