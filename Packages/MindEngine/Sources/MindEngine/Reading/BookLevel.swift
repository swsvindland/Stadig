import Foundation
import SystemCore

/// A book's tier when it isn't one of the hand-levelled ones. Lexile and ATOS are licensed and
/// mostly cover school books, so: the ladder when it's on it, the author's other books when they
/// are, otherwise genre, length and age. The reader's feedback then refines it.
public enum BookLevel {
    /// How sure each source is, 0–1. Levels from a classic's text are about two tiers out on
    /// average against the hand-levelled books, so they count for half. A tier chosen by hand
    /// counts as a guess.
    public static let textConfidence = 0.5
    public static let authorConfidence = 0.6
    public static let guessConfidence = 0.3

    public struct Estimate: Hashable, Sendable {
        public enum Basis: Hashable, Sendable {
            case ladder(LadderBook)
            /// The author's other books: on the ladder, or finished here.
            case author(count: Int)
            case genre
        }

        public var tier: Double
        public var confidence: Double
        public var basis: Basis
        public var genres: [Genre]

        public init(tier: Double, confidence: Double, basis: Basis, genres: [Genre]) {
            self.tier = tier
            self.confidence = confidence
            self.basis = basis
            self.genres = genres
        }

        public var roundedTier: Int { clamp(Int(tier.rounded()), 1, 10) }

        /// Where the tier comes from, in a few words.
        public var explanation: String {
            switch basis {
            case .ladder(let book) where book.levelledFromText: "Levelled from its text at tier \(book.tier)"
            case .ladder(let book): "On the ladder at tier \(book.tier)"
            case .author(let count): "From the author's other \(count == 1 ? "book" : "books")"
            case .genre: "Estimated from its genre, length and age. How it feels will refine it."
            }
        }
    }

    /// Typical tiers for a book of each genre (not the ladder's spread, which climbs to the summit).
    static let genreTiers: [Genre: Double] = [
        .fantasy: 2.5, .sciFi: 3, .crime: 2, .literary: 4, .classics: 5, .nonfiction: 3, .philosophy: 6,
    ]

    public static func estimate(title: String, author: String, pages: Int? = nil, year: Int? = nil, subjects: [String] = [],
                                ladder: ReadingLadder = .standard, shelf: [Book] = [], readerLevel: Double? = nil) -> Estimate {
        let key = matchKey(title: title, author: author)
        let genres = self.genres(subjects: subjects)
        if let book = ladder.books.first(where: { matchKey(title: $0.title, author: $0.author) == key }) {
            return Estimate(tier: Double(book.tier), confidence: book.levelledFromText ? textConfidence : 1, basis: .ladder(book),
                            genres: book.genres)
        }
        // Known-similar titles: the same author on the ladder, and their books finished here with
        // the reader's feedback folded in.
        let surname = self.surname(author)
        var similar: [(tier: Double, weight: Double)] = ladder.books(in: nil).filter { self.surname($0.author) == surname && !surname.isEmpty }
            .map { (Double($0.tier), 1) }
        for book in shelf where book.language == nil && self.surname(book.author) == surname && !surname.isEmpty && book.done
            && matchKey(title: book.title, author: book.author) != key {
            similar.append((refined(book, readerLevel: readerLevel), ReadingPlan.confidence(book)))
        }
        if !similar.isEmpty {
            let weight = similar.map(\.weight).reduce(0, +)
            let tier = similar.map { $0.tier * $0.weight }.reduce(0, +) / weight
            let ladderGenres = ladder.books.first { self.surname($0.author) == surname }?.genres
            return Estimate(tier: clamp(tier, 1, 10), confidence: authorConfidence, basis: .author(count: similar.count),
                            genres: genres.isEmpty ? ladderGenres ?? [] : genres)
        }
        var tier = genres.compactMap { genreTiers[$0] }.max() ?? 3.5
        let words = subjects.joined(separator: " ").lowercased()
        if ["juvenile", "young adult", "children", "picture book"].contains(where: words.contains) { tier = min(tier, 1.5) }
        if let year {
            if year < 1700 { tier += 2.5 } else if year < 1800 { tier += 2 } else if year < 1900 { tier += 1 } else if year < 1940 { tier += 0.5 }
        }
        if let pages {
            if pages > 900 { tier += 1 } else if pages > 600 { tier += 0.5 } else if pages < 180 { tier -= 0.5 }
        }
        return Estimate(tier: clamp(tier, 1, 10), confidence: guessConfidence, basis: .genre, genres: genres)
    }

    /// Genres from a catalogue's subject headings ("Fiction, fantasy, epic", "genre:fantasy").
    public static func genres(subjects: [String]) -> [Genre] {
        let text = subjects.joined(separator: " | ").lowercased()
        var out: [Genre] = []
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["fantasy", "magic", "dragons", "wizards"]) { out.append(.fantasy) }
        if has(["science fiction", "sci-fi", "dystopia", "space opera", "time travel"]) { out.append(.sciFi) }
        if has(["detective", "mystery", "crime", "thriller", "suspense", "murder"]) { out.append(.crime) }
        if has(["philosophy", "ethics", "metaphysics", "epistemology", "stoic"]) { out.append(.philosophy) }
        if has(["classic"]) { out.append(.classics) }
        if has(["biography", "autobiography", "memoir", "history", "science", "self-help", "business", "economics", "psychology",
                "politics", "essays", "nonfiction", "non-fiction", "true crime"]) && !out.contains(.sciFi) {
            out.append(.nonfiction)
        }
        if out.isEmpty && has(["fiction", "novel", "literary", "literature"]) { out.append(.literary) }
        return out
    }

    /// A book's tier with the reader's feedback folded in: an easy book reads about a tier below
    /// the reader, a just-right one at it, a slog about a tier above, and one given up on as too
    /// hard further still. The feedback counts as half a ladder placing.
    public static func refined(_ book: Book, readerLevel: Double?) -> Double {
        let prior = Double(book.tier)
        guard let level = readerLevel, let feel = book.feel, book.status == .finished || book.status == .abandoned else { return prior }
        let implied: Double = switch (book.status, feel) {
        case (.abandoned, .hard): level + 1.5
        case (_, .easy): level - 1
        case (_, .right): level
        case (_, .hard): level + 1
        }
        let confidence = ReadingPlan.confidence(book)
        return clamp((confidence * prior + 0.5 * implied) / (confidence + 0.5), 1, 10)
    }

    // MARK: Matching

    /// The same book however a catalogue writes it: title without its subtitle or leading article,
    /// accents and punctuation gone, and the author's surname.
    public static func matchKey(title: String, author: String) -> String {
        var main = fold(title)
        if let colon = main.firstIndex(where: { $0 == ":" || $0 == "(" }) { main = String(main[..<colon]) }
        var words = main.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if let first = words.first, ["the", "a", "an"].contains(first), words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ") + "|" + surname(author)
    }

    /// "jane austen", "Austen, Jane" and "J. Austen" all give "austen".
    static func surname(_ author: String) -> String {
        let folded = fold(author)
        let name = folded.contains(",") ? String(folded.prefix { $0 != "," }) : folded
        let words = name.split { !$0.isLetter }.map(String.init).filter { !["jr", "sr", "ii", "iii", "iv"].contains($0) }
        return words.last ?? ""
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "&", with: "and")
    }
}
