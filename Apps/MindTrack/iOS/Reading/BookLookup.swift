import Foundation
import OSLog
import MindEngine

/// A book found by search, scan or cover, ready to confirm: from the ladder (levelled by hand or
/// from its text) or from a catalogue lookup with an estimated level.
struct BookDraft: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var author: String
    var pages: Int?
    var year: Int?
    var genres: [Genre]
    var isbn: String?
    var ladderID: String?
    var coverURL: URL?
    var estimate: BookLevel.Estimate
    /// The catalogue lookup it came from, kept once the book is saved.
    var lookup: BookMeta?

    init(ladder book: LadderBook) {
        title = book.title
        author = book.author
        pages = book.pages
        year = book.year
        genres = book.genres
        ladderID = book.id
        estimate = BookLevel.Estimate(tier: Double(book.tier), confidence: book.levelledFromText ? BookLevel.textConfidence : 1,
                                      basis: .ladder(book), genres: book.genres)
    }

    init(meta: BookMeta, estimate: BookLevel.Estimate) {
        title = meta.title
        author = meta.author
        pages = meta.pages
        year = meta.year
        genres = estimate.genres
        isbn = meta.isbn
        coverURL = meta.coverURL
        if case .ladder(let book) = estimate.basis { ladderID = book.id }
        self.estimate = estimate
        lookup = meta
    }

    /// A blank one, for a book typed in by hand.
    init(title: String = "", author: String = "") {
        self.title = title
        self.author = author
        genres = []
        estimate = BookLevel.estimate(title: title, author: author)
    }
}

/// Looks books up: the ladder and earlier lookups first (both work offline), then Open Library,
/// then Google Books. A lookup that's used is kept as a BookMeta record, so it happens once.
@MainActor
enum BookLookup {
    /// What the search shows: ladder books, then catalogue results.
    struct Results {
        var ladder: [LadderBook] = []
        var found: [BookMeta] = []
        /// Neither catalogue answered (offline, or both failed).
        var unreachable = false
    }

    static let agent = "MindTrack/1.0 (iOS; dev.svindland.stadig.mind)"

    /// A book by its ISBN: from the cache, or Open Library, or Google Books. Nil when no one knows it.
    static func isbn(_ isbn: String, model: AppModel) async -> BookMeta? {
        if let cached = model.bookMeta.first(where: { $0.isbn == isbn }) { return cached }
        if let data = await fetch(OpenLibrary.isbnURL(isbn)), let meta = OpenLibrary.parseISBN(data, isbn: isbn) { return meta }
        if let data = await fetch(GoogleBooks.isbnURL(isbn)), let meta = GoogleBooks.parse(data).first { return meta }
        return nil
    }

    /// The ladder and cached lookups match at once; the catalogues follow.
    static func local(_ query: String, model: AppModel) -> Results {
        let words = fold(query).split(separator: " ").map(String.init)
        guard query.trimmingCharacters(in: .whitespaces).count >= 2, !words.isEmpty else { return Results() }
        func matches(_ title: String, _ author: String) -> Bool {
            let haystack = fold(title + " " + author)
            return words.allSatisfy { haystack.contains($0) }
        }
        let ladder = model.catalogs.ladder.books(in: nil).filter { matches($0.title, $0.author) }.prefix(8)
        let cached = model.bookMeta.filter { matches($0.title, $0.author) }.prefix(8)
        return Results(ladder: Array(ladder), found: Array(cached))
    }

    static func search(_ query: String, model: AppModel) async -> Results {
        var results = local(query, model: model)
        if let isbn = ISBN.normalize(query) {
            if let meta = await self.isbn(isbn, model: model) { results.found.insert(meta, at: 0) } else { results.unreachable = true }
            return results
        }
        var online: [BookMeta] = []
        if let data = await fetch(OpenLibrary.searchURL(query)) { online = OpenLibrary.parseSearch(data) }
        if online.isEmpty, let data = await fetch(GoogleBooks.searchURL(query)) { online = GoogleBooks.parse(data) }
        if online.isEmpty && results.found.isEmpty && results.ladder.isEmpty { results.unreachable = !(await reachable()) }
        // Ladder books found online are shown once, as ladder books.
        let ladderKeys = Set(results.ladder.map { BookLevel.matchKey(title: $0.title, author: $0.author) })
        var seen = Set(results.found.map { BookLevel.matchKey(title: $0.title, author: $0.author) })
        for meta in online {
            let key = BookLevel.matchKey(title: meta.title, author: meta.author)
            guard !ladderKeys.contains(key), seen.insert(key).inserted else { continue }
            results.found.append(meta)
        }
        return results
    }

    /// The level estimate for a looked-up book, from the ladder, the author's other books, or its
    /// genre, length and age, with this reader's shelf and feedback folded in.
    static func estimate(_ meta: BookMeta, model: AppModel) -> BookLevel.Estimate {
        let level = model.analysis?.reading.level
        return BookLevel.estimate(title: meta.title, author: meta.author, pages: meta.pages, year: meta.year, subjects: meta.subjects,
                                  ladder: model.catalogs.ladder, shelf: model.books, readerLevel: level)
    }

    /// Keeps a lookup that's been used, with its estimate: one record per book.
    static func keep(_ meta: BookMeta, estimate: BookLevel.Estimate, model: AppModel) {
        var meta = meta
        if let existing = model.bookMeta.first(where: { ($0.isbn != nil && $0.isbn == meta.isbn)
            || BookLevel.matchKey(title: $0.title, author: $0.author) == BookLevel.matchKey(title: meta.title, author: meta.author) }) {
            meta.id = existing.id
        }
        meta.tier = estimate.tier
        meta.tierConfidence = estimate.confidence
        model.save(meta: meta)
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            appLog.info("Book lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func reachable() async -> Bool {
        var request = URLRequest(url: URL(string: "https://openlibrary.org")!, timeoutInterval: 6)
        request.httpMethod = "HEAD"
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
