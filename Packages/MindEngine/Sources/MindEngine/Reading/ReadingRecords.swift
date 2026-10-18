import Foundation

/// A passage for the reading test: real prose at a known difficulty, read silently and timed in
/// the background, then a few comprehension questions. Public domain (from Project Gutenberg) or
/// written for Mind Track.
public struct Passage: Hashable, Sendable, Identifiable, Decodable {
    public var id: String
    public var title: String
    public var author: String
    public var text: String
    /// The ladder tier this passage reads at.
    public var tier: Int
    public var language: Language?
    /// Where it's from: "Project Gutenberg #1342", or "Written for Mind Track".
    public var source: String
    public var questions: [PassageQuestion]

    public init(
        id: String, title: String, author: String, text: String, tier: Int, language: Language? = nil,
        source: String = "Written for Mind Track", questions: [PassageQuestion] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.text = text
        self.tier = tier
        self.language = language
        self.source = source
        self.questions = questions
    }

    public var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// One comprehension question: the gist, a detail, an inference, or a word in context. Asked
/// after the passage, without it on screen.
public struct PassageQuestion: Hashable, Sendable, Decodable {
    public enum Kind: String, Hashable, Sendable, Decodable { case gist, detail, inference, vocabulary }

    public var kind: Kind
    public var prompt: String
    public var answer: String
    public var wrong: [String]

    public init(kind: Kind, prompt: String, answer: String, wrong: [String]) {
        self.kind = kind
        self.prompt = prompt
        self.answer = answer
        self.wrong = wrong
    }
}

/// How focus held through a reading block: the same three-tap pattern as a set's effort. It's
/// what stamina is measured from, apart from how hard the book is.
public enum ReadingFocus: String, CaseIterable, Codable, Sendable, Identifiable {
    case held, drifted, lost

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .held: "Held"
        case .drifted: "Drifted"
        case .lost: "Lost it"
        }
    }

    /// The share of the block that counts as focused reading.
    var share: Double {
        switch self {
        case .held: 1
        case .drifted: 0.9
        case .lost: 0.5
        }
    }
}

/// What's known about a book from outside: Open Library first, Google Books as backup, cached
/// so it works offline after the first lookup. The level estimate starts from genre, length and
/// known-similar titles and is refined by feedback.
public struct BookMeta: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var isbn: String?
    public var title: String
    public var author: String
    public var pages: Int?
    public var year: Int?
    public var subjects: [String]
    public var coverURL: URL?
    /// "openlibrary" or "googlebooks".
    public var source: String
    /// The estimated ladder tier, and how sure it is (0–1).
    public var tier: Double?
    public var tierConfidence: Double
    public var fetchedAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), isbn: String? = nil, title: String, author: String, pages: Int? = nil, year: Int? = nil,
        subjects: [String] = [], coverURL: URL? = nil, source: String, tier: Double? = nil, tierConfidence: Double = 0,
        fetchedAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.isbn = isbn
        self.title = title
        self.author = author
        self.pages = pages
        self.year = year
        self.subjects = subjects
        self.coverURL = coverURL
        self.source = source
        self.tier = tier
        self.tierConfidence = tierConfidence
        self.fetchedAt = fetchedAt
        self.updatedAt = updatedAt
    }
}
