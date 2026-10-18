import Foundation

/// A passage for the reading test: real prose at a known difficulty, read silently and timed in
/// the background, then a few comprehension questions.
public struct Passage: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var author: String
    public var text: String
    /// The ladder tier this passage reads at.
    public var tier: Int
    public var language: Language?

    public init(id: String, title: String, author: String, text: String, tier: Int, language: Language? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.text = text
        self.tier = tier
        self.language = language
    }

    public var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
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

    public init(id: UUID = UUID(), isbn: String? = nil, title: String, author: String, pages: Int? = nil, year: Int? = nil,
                subjects: [String] = [], coverURL: URL? = nil, source: String, tier: Double? = nil, tierConfidence: Double = 0,
                fetchedAt: Date = Date(), updatedAt: Date = Date()) {
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
