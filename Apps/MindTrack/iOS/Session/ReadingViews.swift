import SwiftUI
import MindEngine
import SystemCore

/// No book on the go: the ladder's three suggestions, or your own.
struct PickBookView: View {
    @Environment(AppModel.self) private var model
    let options: [LadderBook]
    @State private var addingOwn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your next book").font(.title.bold())
                Text("One step up from where you're comfortable, in the genres you like.").foregroundStyle(.secondary)
                ForEach(options) { book in
                    Button {
                        model.act { $0.pickBook(book, now: Date()) }
                    } label: {
                        LadderBookRow(book: book)
                    }
                    .buttonStyle(.plain)
                }
                Button("Add a book of your own", systemImage: "plus") { addingOwn = true }
                    .padding(.top, 4)
                Button("Not today") { model.act { $0.skipPart(now: Date()) } }
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .readableWidth(640)
        }
        .sheet(isPresented: $addingOwn) {
            BookEditor(book: nil) { book in model.act { $0.addBook(book, now: Date()) } }
        }
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

/// The reading block: a quiet timer, then where the bookmark is.
struct ReadingTimerView: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let minutes: Int
    @State private var started = Date()
    @State private var logging = false

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
                            Text(left > 0 ? "Read. The phone can go face down." : "That's the block. Finish the page.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
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
                    Text("Done reading").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $logging) {
            PageSheet(book: book) { page, finished, feel in
                let minutes = Date().timeIntervalSince(started) / 60
                model.act { $0.finishReading(page: page, finished: finished, feel: feel, minutes: minutes, now: Date()) }
            }
        }
    }
}

/// Where the bookmark is now, and how the book felt if it's finished.
struct PageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let save: (Int, Bool, BookFeel?) -> Void
    @State private var page: Int
    @State private var finished = false
    @State private var feel: BookFeel = .right

    init(book: Book, finished: Bool = false, save: @escaping (Int, Bool, BookFeel?) -> Void) {
        self.book = book
        self.save = save
        _page = State(initialValue: min(book.pages, book.page + 20))
        _finished = State(initialValue: finished)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("I finished it", isOn: $finished)
                    if !finished {
                        Stepper(value: $page, in: book.page...book.pages, step: 1) {
                            LabeledContent("Now on page", value: "\(page)")
                        }
                        TextField("Page", value: $page, format: .number).keyboardType(.numberPad)
                    }
                } footer: {
                    if !finished { Text("\(max(0, page - book.page)) pages this time.") }
                }
                if finished {
                    Section {
                        Picker("How did it feel?", selection: $feel) {
                            ForEach(BookFeel.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("How did it feel?")
                    } footer: {
                        Text("Easy or a stretch moves the ladder up a tier; hard going holds it here for one more.")
                    }
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(min(page, book.pages), finished, finished ? feel : nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                    Text(finished ? "A few sentences about \(book.title) as a whole." : "Two or three sentences are plenty. Next time starts with them.")
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
                    Button {
                        let note = text
                        model.act { $0.reflect(note, now: Date()) }
                    } label: {
                        Text("Save").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .controlSize(.large)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }
}

/// A book of your own: title, author, length, and how hard, by comparison with the ladder.
struct BookEditor: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book?
    let save: (Book) -> Void
    @State private var title = ""
    @State private var author = ""
    @State private var pages = 300
    @State private var tier = 3
    @State private var genre: Genre = .literary

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    Stepper(value: $pages, in: 40...2000, step: 10) { LabeledContent("Pages", value: "\(pages)") }
                    Picker("Genre", selection: $genre) { ForEach(Genre.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    Stepper(value: $tier, in: 1...10) { LabeledContent("Tier", value: "\(tier) of 10") }
                    let examples = ReadingLadder.standard.books.filter { $0.tier == tier }.prefix(3).map(\.title)
                    if !examples.isEmpty {
                        Text("About as hard as \(ListFormatter.localizedString(byJoining: examples)).").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How hard to read")
                } footer: {
                    Text(ReadingLadder.standard.tier(tier)?.description ?? "")
                }
            }
            .navigationTitle(book == nil ? "Add a book" : "Edit book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var edited = book ?? Book(title: title, author: author, tier: tier, pages: pages, genres: [genre], status: .reading)
                        edited.title = title
                        edited.author = author
                        edited.tier = tier
                        edited.pages = pages
                        edited.genres = [genre]
                        save(edited)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let book else { return }
                title = book.title
                author = book.author
                pages = book.pages
                tier = book.tier
                genre = book.genres.first ?? .literary
            }
        }
    }
}
