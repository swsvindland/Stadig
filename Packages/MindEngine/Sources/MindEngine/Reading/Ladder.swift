import Foundation
import SystemCore

public struct LadderTier: Hashable, Codable, Sendable {
    public var tier: Int
    public var label: String
    public var description: String
}

/// A book on the ladder. `year` is negative before the common era (The Republic is -375).
public struct LadderBook: Hashable, Codable, Sendable, Identifiable {
    /// How a book's tier was set: by hand against the rest of the ladder, or computed from its
    /// public-domain text.
    public enum Levelling: String, Hashable, Codable, Sendable { case hand, text }

    public var id: String
    public var title: String
    public var author: String
    public var year: Int
    public var pages: Int
    public var tier: Int
    public var genres: [Genre]
    public var note: String
    /// Nil for English. Graded readers in a language being learned carry it, and level apart.
    public var language: Language?
    /// Nil means by hand.
    public var levelled: Levelling?

    public init(id: String, title: String, author: String, year: Int, pages: Int, tier: Int, genres: [Genre], note: String,
                language: Language? = nil, levelled: Levelling? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.year = year
        self.pages = pages
        self.tier = tier
        self.genres = genres
        self.note = note
        self.language = language
        self.levelled = levelled
    }

    public var levelledFromText: Bool { levelled == .text }

    public func book(status: BookStatus, started: Day? = nil) -> Book {
        Book(ladderID: id, title: title, author: author, tier: tier, pages: pages, genres: genres, status: status, started: started,
             language: language, tierConfidence: levelledFromText ? BookLevel.textConfidence : 1)
    }
}

/// A public-domain classic levelled from its Project Gutenberg text by `Scripts/level-gutenberg.py`:
/// readability, vocabulary rarity and sentence complexity, fitted to the hand-levelled books.
public struct LevelledClassic: Hashable, Codable, Sendable {
    public var gutenberg: Int
    public var id: String
    public var title: String
    public var author: String
    public var year: Int
    public var pages: Int
    public var genres: [Genre]
    public var words: Int
    /// Words a sentence, on average.
    public var sentenceWords: Double
    /// Syllables a word, on average.
    public var syllables: Double
    /// Share of words outside everyday vocabulary (proper names left out).
    public var rareWords: Double
    /// Commas, semicolons, colons and dashes a sentence: how many parts a sentence holds.
    public var clauses: Double
    /// The computed tier, 1–10.
    public var tier: Double
    /// The hand tier, for books on the ladder too: what the fit was checked against.
    public var handTier: Int?
}

/// Ten tiers of real reading difficulty (prose, vocabulary, structure, what the book asks of the
/// reader), with stepping-stone books between them: Sanderson towards Woolf. A few hundred are
/// levelled by hand; public-domain classics beyond those are levelled from their text.
public struct ReadingLadder: Sendable {
    public var tiers: [LadderTier]
    public var books: [LadderBook]
    /// Every classic levelled from its text, including those also levelled by hand.
    public var classics: [LevelledClassic]

    public init(tiers: [LadderTier], books: [LadderBook], classics: [LevelledClassic] = []) {
        self.tiers = tiers.sorted { $0.tier < $1.tier }
        self.classics = classics
        let hand = Set(books.map { BookLevel.matchKey(title: $0.title, author: $0.author) })
        let computed = classics.filter { $0.handTier == nil && !hand.contains(BookLevel.matchKey(title: $0.title, author: $0.author)) }
            .map(Self.ladderBook)
        self.books = books + computed
    }

    private struct File: Decodable {
        var tiers: [LadderTier]
        var books: [LadderBook]
    }

    private struct Classics: Decodable {
        var books: [LevelledClassic]
    }

    public static let standard: ReadingLadder = {
        guard let url = Bundle.module.url(forResource: "ladder", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
            mindLog.error("The reading ladder is missing or unreadable")
            return ReadingLadder(tiers: [], books: [])
        }
        var classics: [LevelledClassic] = []
        if let url = Bundle.module.url(forResource: "gutenberg-levels", withExtension: "json"), let data = try? Data(contentsOf: url) {
            classics = (try? JSONDecoder().decode(Classics.self, from: data))?.books ?? []
        }
        return ReadingLadder(tiers: file.tiers, books: file.books, classics: classics)
    }()

    public func tier(_ n: Int) -> LadderTier? { tiers.first { $0.tier == n } }
    public func book(_ id: String) -> LadderBook? { books.first { $0.id == id } }

    /// The books for reading in a language: nil is English.
    public func books(in language: Language?) -> [LadderBook] { books.filter { $0.language == language } }

    /// The hand-levelled books only.
    public var handLevelled: [LadderBook] { books.filter { !$0.levelledFromText } }

    /// A classic as a ladder book, with a note that says what its text is like.
    static func ladderBook(_ classic: LevelledClassic) -> LadderBook {
        let sentences = switch classic.sentenceWords {
        case ..<16: "short sentences"
        case ..<23: "sentences of middling length"
        case ..<31: "long sentences"
        default: "very long sentences"
        }
        let vocabulary = switch classic.rareWords {
        case ..<0.02: "an everyday vocabulary"
        case ..<0.035: "a fairly plain vocabulary"
        case ..<0.05: "a rich vocabulary"
        default: "a rare and demanding vocabulary"
        }
        return LadderBook(id: classic.id, title: classic.title, author: classic.author, year: classic.year, pages: classic.pages,
                          tier: clamp(Int(classic.tier.rounded()), 1, 10), genres: classic.genres,
                          note: "Levelled from its text: \(sentences) and \(vocabulary). In the public domain, so the ebook is free.",
                          levelled: .text)
    }
}
