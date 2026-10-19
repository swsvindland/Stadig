import MindEngine
import SwiftUI
import SystemCore

/// What's been learned, course by course, in a wide window: a language's words as a table (where
/// each memory stands, when it's next due, how sure it is), and the maths topics by level. On an
/// iPhone the topic map is on Plan.
struct CoursesDestination: View {
    @Environment(AppModel.self) private var model
    @State private var course: Domain?

    /// Languages whose catalog this build has, then maths.
    var courses: [Domain] {
        (model.settings?.domains ?? []).filter { domain in
            domain.isLanguage ? model.catalogs.deck(for: domain) != nil : domain == .maths
        }
    }

    var body: some View {
        let courses = self.courses
        let shown = course.flatMap { courses.contains($0) ? $0 : nil } ?? courses.first
        NavigationStack {
            Group {
                switch shown {
                case .some(let domain) where domain.isLanguage:
                    if let language = domain.language { LanguageWords(language: language).id(language) }
                case .some(.maths):
                    if let state = model.state { TopicMapList(state: state) }
                default:
                    ContentUnavailableView(
                        "No courses to browse", systemImage: "square.stack.3d.up",
                        description: Text("Turn on a language or maths in Settings to see what's been learned here."))
                }
            }
            .navigationTitle(shown.map { "\($0.label)" } ?? "Courses")
            .toolbar {
                if courses.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Picker("Course", selection: Binding(get: { shown }, set: { course = $0 })) {
                            ForEach(courses) { Text($0.label).tag(Domain?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("courses.picker")
                    }
                }
            }
            .background(.pageBackground)
        }
    }
}

/// A language's words: every one met here, sortable by any column, searchable, and filtered by
/// where its memory stands. The selected word opens in the inspector.
private struct LanguageWords: View {
    @Environment(AppModel.self) private var model
    let language: Language
    @State private var rows: [CourseWord] = []
    @State private var shown: [CourseWord] = []
    @State private var counts: [CourseWord.State: Int] = [:]
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\CourseWord.rank)]
    @State private var query = ""
    @State private var filter: CourseWord.State?
    @State private var selection: CourseWord.ID?
    @State private var inspecting = false
    /// The selected word's example sentences, looked up in the catalog when it's selected.
    @State private var sentences: [Sentence] = []

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            Table(shown, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Word", value: \.text) { row in
                    Text(row.text).font(.title3).environment(\.locale, Locale(identifier: language.pack.locale))
                }
                TableColumn("Reading", value: \.reading)
                TableColumn("Meaning", value: \.meaning)
                TableColumn("Memory", value: \.state) { row in WordState(state: row.state) }
                TableColumn("Next review", value: \.dueOrder) { row in
                    Text(row.due.map { Format.day(Day($0)) } ?? "—").foregroundStyle(.secondary)
                }
                TableColumn("Recall", value: \.recallOrder) { row in
                    Text(row.recall.map(Format.percent) ?? "—").monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("Frequency", value: \.rank) { row in
                    Text("#\(row.rank.formatted())").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: CourseWord.ID.self) { ids in
                if let id = ids.first, let word = word(id) {
                    Button("Hear It", systemImage: "speaker.wave.2") { model.speech.speak(word.reading, language: language) }
                    Button("Show Details", systemImage: "info.circle") {
                        selection = id
                        inspecting = true
                    }
                }
            } primaryAction: { ids in
                selection = ids.first
                inspecting = true
            }
            .overlay {
                if loaded, shown.isEmpty {
                    if rows.isEmpty {
                        ContentUnavailableView(
                            "No words yet", systemImage: language.domain.symbol,
                            description: Text("Words appear here as sessions teach them."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .accessibilityIdentifier("courses.words")
        }
        .searchable(text: $query, prompt: "Word, reading or meaning")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Details", systemImage: "info.circle") { inspecting.toggle() }
                    .help("Show the selected word's details")
                    .accessibilityIdentifier("courses.details")
            }
        }
        .detailsInspector(isPresented: $inspecting) {
            Group {
                if let id = selection, let word = word(id) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            WordCard(word: word, kanji: model.catalogs.deck(language)?.kanji(in: word) ?? [])
                            ForEach(sentences) { sentence in
                                SentenceLine(sentence: sentence, language: language).card()
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView("Choose a word", systemImage: "character.book.closed")
                }
            }
        }
        .task(id: model.cardsRevision) {
            let cards = model.state?.cards ?? [:]
            guard let deck = model.catalogs.deck(language) else { return }
            rows = await Self.rows(language, cards: cards, deck: deck, today: model.today, now: model.now())
            counts = CourseWord.counts(rows)
            refilter()
            loaded = true
        }
        .task(id: selection) {
            guard let id = selection, let deck = model.catalogs.deck(language) else { return }
            sentences = await Self.sentences(id, deck: deck)
        }
        .onChange(of: query) { refilter() }
        .onChange(of: filter) { refilter() }
        .onChange(of: sortOrder) { refilter() }
    }

    /// Counts by state, each a filter: click Due to see what's due.
    var summary: some View {
        HStack(spacing: 10) {
            Text("\(rows.count.formatted()) words").font(.headline)
            Spacer()
            ForEach(CourseWord.State.allCases, id: \.self) { state in
                Button {
                    filter = filter == state ? nil : state
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(WordState.color(state)).frame(width: 8, height: 8)
                        Text("\(state.label) \(counts[state] ?? 0)").font(.subheadline.monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(filter == state ? WordState.color(state).opacity(0.2) : Color.clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .hoverable(in: .capsule)
                .accessibilityAddTraits(filter == state ? .isSelected : [])
                .accessibilityIdentifier("courses.filter.\(state.label.lowercased())")
            }
        }
    }

    func word(_ id: Int) -> Word? { model.catalogs.deck(language)?.word(id) }

    func refilter() { shown = CourseWord.filter(rows, query: query, state: filter).sorted(using: sortOrder) }

    /// A catalog query: off the main actor.
    @concurrent nonisolated static func sentences(_ id: Int, deck: LanguageDeck) async -> [Sentence] {
        deck.sentences(with: id, maxLevel: .max, limit: 3)
    }

    /// Thousands of cards matched to their words: off the main actor.
    @concurrent nonisolated static func rows(_ language: Language, cards: [CardKey: MemoryCard], deck: LanguageDeck, today: Day, now: Date) async
        -> [CourseWord]
    {
        CourseWord.rows(language, cards: cards, deck: deck, today: today, now: now)
    }
}

/// Where a word's memory stands, in a colour.
private struct WordState: View {
    let state: CourseWord.State

    var body: some View {
        Label {
            Text(state.label)
        } icon: {
            Circle().fill(Self.color(state)).frame(width: 8, height: 8)
        }
    }

    static func color(_ state: CourseWord.State) -> Color {
        switch state {
        case .learning: .orange
        case .due: .pink
        case .known: .blue
        case .mastered: .green
        }
    }
}
