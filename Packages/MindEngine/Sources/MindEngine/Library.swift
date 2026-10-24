import Foundation
import SystemCore

// What the desktop destinations list: the shelf, your writing and each course's words, grouped,
// searched and sorted here so the screens only show them.

/// Text matching for the destinations' search fields: every word typed is in the text somewhere,
/// ignoring case and accents ("cafe" finds "Café").
public enum LibrarySearch {
    public static func matches(_ query: String, _ fields: String...) -> Bool {
        let words = fold(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = fold(fields.joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The English shelf by where each book stands: the one on the go, finished (newest first; a book
/// with no date counts as today's), set aside the same way, and read in the year before Mind Track
/// (in the order they were entered). Graded readers in other languages live with their language.
public struct ShelfSections: Equatable, Sendable {
    public var current: Book?
    public var finished: [Book]
    public var setAside: [Book]
    public var readBefore: [Book]

    public init(books: [Book], query: String = "", today: Day) {
        let shelf = books.filter { $0.language == nil && LibrarySearch.matches(query, $0.title, $0.author) }
        current = shelf.first { $0.status == .reading }
        func newestFirst(_ status: BookStatus) -> [Book] {
            shelf.filter { $0.status == status }.sorted { ($0.finished ?? today, $1.title) > ($1.finished ?? today, $0.title) }
        }
        finished = newestFirst(.finished)
        setAside = newestFirst(.abandoned)
        readBefore = shelf.filter { $0.status == .readBefore }
    }

    public var isEmpty: Bool { current == nil && finished.isEmpty && setAside.isEmpty && readBefore.isEmpty }
}

/// Your writing, newest first, narrowed by a search over the prompt, the text and the notes.
public enum PieceSearch {
    public static func matching(_ pieces: [WritingPiece], query: String) -> [WritingPiece] {
        pieces.filter { LibrarySearch.matches(query, $0.prompt, $0.text, $0.notes ?? "", $0.exercise.label) }
            .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
    }
}

/// A language course's words as a table: each word met so far, where its memory stands, when it's
/// next due and how sure it is.
public struct CourseWord: Hashable, Sendable, Identifiable {
    public enum State: Int, Hashable, Sendable, Comparable, CaseIterable {
        /// Taught, not yet remembered from one day to the next.
        case learning
        /// Due for review today (or overdue).
        case due
        /// Remembered, and coming back on its schedule.
        case known
        /// Remembered for three weeks or more, or known before and never forgotten: its help has gone.
        case mastered

        public static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .learning: "Learning"
            case .due: "Due"
            case .known: "Known"
            case .mastered: "Mastered"
            }
        }
    }

    public var id: Int
    public var text: String
    /// How it's read: the kana, or a Spanish word's stress guide.
    public var reading: String
    public var meaning: String
    /// How common it is: 1 is the most common word.
    public var rank: Int
    public var state: State
    /// When it's next due; nil while it's still being learned.
    public var due: Date?
    /// The chance of recalling it now, by the memory model.
    public var recall: Double?
    public var reviews: Int
    public var lapses: Int

    /// For sorting a table by these columns: a word still being learned has neither, and sorts last
    /// by when it's due and lowest by recall.
    public var dueOrder: Date { due ?? .distantFuture }
    public var recallOrder: Double { recall ?? -1 }

    /// Every word with a card in the language, kana left out, most common first. A card whose
    /// word isn't in this build's deck is skipped.
    public static func rows(
        _ language: Language, cards: [CardKey: MemoryCard], deck: LanguageDeck, today: Day, dayStart: Int, now: Date
    ) -> [CourseWord] {
        cards.values.compactMap { card -> CourseWord? in
            guard card.key.language == language, let id = card.key.wordID, let word = deck.word(id) else { return nil }
            let state: State
            if let memory = card.memory {
                if card.isDue(on: today, dayStart: dayStart) {
                    state = .due
                } else if memory.stability >= Scaffolds.masteredStability || (card.knownBefore && memory.lapses == 0) {
                    state = .mastered
                } else {
                    state = .known
                }
            } else {
                state = .learning
            }
            return CourseWord(
                id: word.id, text: word.text, reading: reading(word), meaning: word.meaning, rank: word.rank,
                state: state, due: card.memory?.due, recall: card.memory.map { Scheduler.retrievability($0, at: now) },
                reviews: card.memory?.reps ?? 0, lapses: card.memory?.lapses ?? 0)
        }
        .sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
    }

    /// The kana for a Japanese word written with kanji, the stress guide for a Spanish one
    /// (co·ra·ZÓN), nothing for a word written as it's read.
    static func reading(_ word: Word) -> String {
        if word.language.pack.pronunciation == .spanish { return SpanishSounds.guide(word.text) ?? "" }
        return word.kana == word.text ? "" : word.kana
    }

    /// How many of each state, for the course's summary.
    public static func counts(_ rows: [CourseWord]) -> [State: Int] {
        Dictionary(grouping: rows, by: \.state).mapValues(\.count)
    }

    /// Rows narrowed by a search over the word, its reading and meaning, and by state.
    public static func filter(_ rows: [CourseWord], query: String, state: State?) -> [CourseWord] {
        rows.filter { ($0.state == state || state == nil) && LibrarySearch.matches(query, $0.text, $0.reading, $0.meaning) }
    }
}
