import Foundation

/// A book's barcode is its ISBN: an EAN-13 starting 978 or 979. Older books print a ten-digit
/// ISBN, which converts.
public enum ISBN {
    /// Thirteen digits for a scanned or typed ISBN with a valid check digit, or nil. Digits typed
    /// on another keyboard (full-width ９７８) come back as plain ones; anything else that counts as
    /// a number (½, ①) isn't a digit of an ISBN.
    public static func normalize(_ raw: String) -> String? {
        let characters = String(
            raw.uppercased().compactMap { character -> Character? in
                if character == "X" { return "X" }
                guard character.unicodeScalars.count == 1, character.unicodeScalars.first?.properties.numericType == .decimal,
                    let value = character.wholeNumberValue
                else { return nil }
                return Character(String(value))
            })
        if characters.count == 13, characters.allSatisfy(\.isNumber), characters.hasPrefix("978") || characters.hasPrefix("979"),
            checkDigit13(String(characters.prefix(12))) == characters.last?.wholeNumberValue
        {
            return characters
        }
        if characters.count == 10, characters.dropLast().allSatisfy(\.isNumber), valid10(characters) {
            let stem = "978" + characters.prefix(9)
            return stem + String(checkDigit13(stem))
        }
        return nil
    }

    static func checkDigit13(_ twelve: String) -> Int {
        let sum = twelve.compactMap(\.wholeNumberValue).enumerated().map { $0.offset % 2 == 0 ? $0.element : $0.element * 3 }.reduce(0, +)
        return (10 - sum % 10) % 10
    }

    static func valid10(_ ten: String) -> Bool {
        let values = ten.map { $0 == "X" ? 10 : ($0.wholeNumberValue ?? 0) }
        guard !ten.dropLast().contains("X") else { return false }
        return values.enumerated().map { (10 - $0.offset) * $0.element }.reduce(0, +) % 11 == 0
    }
}

/// Open Library: free, no key. One call for an ISBN (title, authors, pages, subjects, cover);
/// search for everything else.
public enum OpenLibrary {
    public static func isbnURL(_ isbn: String) -> URL {
        URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!
    }

    public static func searchURL(_ query: String, limit: Int = 12) -> URL {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,number_of_pages_median,isbn,subject,cover_i"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return components.url!
    }

    public static func coverURL(id: Int) -> URL { URL(string: "https://covers.openlibrary.org/b/id/\(id)-M.jpg")! }

    private struct Named: Decodable { var name: String }
    private struct Edition: Decodable {
        var title: String
        var subtitle: String?
        var authors: [Named]?
        var numberOfPages: Int?
        var publishDate: String?
        var subjects: [Named]?
        var cover: [String: String]?

        enum CodingKeys: String, CodingKey {
            case title, subtitle, authors, subjects, cover
            case numberOfPages = "number_of_pages", publishDate = "publish_date"
        }
    }

    public static func parseISBN(_ data: Data, isbn: String, now: Date = Date()) -> BookMeta? {
        guard let editions = try? JSONDecoder().decode([String: Edition].self, from: data),
            let edition = editions["ISBN:\(isbn)"] ?? editions.values.first
        else { return nil }
        return BookMeta(
            isbn: isbn, title: edition.title, author: edition.authors?.map(\.name).joined(separator: ", ") ?? "",
            pages: edition.numberOfPages, year: edition.publishDate.flatMap(year), subjects: (edition.subjects ?? []).prefix(20).map(\.name),
            coverURL: (edition.cover?["medium"] ?? edition.cover?["small"]).flatMap(URL.init(string:)), source: "openlibrary",
            fetchedAt: now, updatedAt: now)
    }

    /// One entry of a list that reads as nil when it doesn't parse, so one odd record in a reply
    /// doesn't lose the rest.
    struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private struct Search: Decodable {
        struct Doc: Decodable {
            var title: String?
            var authorName: [String]?
            var firstPublishYear: Int?
            var numberOfPagesMedian: Int?
            var isbn: [String]?
            var subject: [String]?
            var coverID: Int?

            enum CodingKeys: String, CodingKey {
                case title, isbn, subject
                case authorName = "author_name", firstPublishYear = "first_publish_year"
                case numberOfPagesMedian = "number_of_pages_median", coverID = "cover_i"
            }
        }
        var docs: [Lenient<Doc>]
    }

    public static func parseSearch(_ data: Data, now: Date = Date()) -> [BookMeta] {
        guard let search = try? JSONDecoder().decode(Search.self, from: data) else { return [] }
        return search.docs.compactMap { doc in
            guard let doc = doc.value, let title = doc.title, !title.isEmpty else { return nil }
            let isbns = (doc.isbn ?? []).compactMap(ISBN.normalize)
            return BookMeta(
                isbn: isbns.first { $0.hasPrefix("978") } ?? isbns.first, title: title,
                author: doc.authorName?.first ?? "", pages: doc.numberOfPagesMedian, year: doc.firstPublishYear,
                subjects: Array((doc.subject ?? []).prefix(20)), coverURL: doc.coverID.map(coverURL), source: "openlibrary",
                fetchedAt: now, updatedAt: now)
        }
    }

    /// The first plausible year in a date as catalogues write it: "2003", "March 2003", "2003-05-01".
    static func year(_ text: String) -> Int? {
        var digits = ""
        for character in text + " " {
            if character.isNumber {
                digits.append(character)
                continue
            }
            if digits.count == 4, let year = Int(digits), (1000...2100).contains(year) { return year }
            digits = ""
        }
        return nil
    }
}

/// Google Books, the backup: works without a key at low volume (and fails when its shared quota
/// runs out, which is why it's the backup).
public enum GoogleBooks {
    public static func isbnURL(_ isbn: String) -> URL {
        URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)&maxResults=5")!
    }

    public static func searchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "12"),
            URLQueryItem(name: "printType", value: "books"),
        ]
        return components.url!
    }

    private struct Volumes: Decodable {
        struct Item: Decodable {
            struct Info: Decodable {
                struct Identifier: Decodable {
                    var type: String
                    var identifier: String
                }
                var title: String?
                var authors: [String]?
                var publishedDate: String?
                var pageCount: Int?
                var categories: [String]?
                var imageLinks: [String: String]?
                /// One without a value loses only itself, not the book.
                var industryIdentifiers: [OpenLibrary.Lenient<Identifier>]?
            }
            var volumeInfo: Info
        }
        var items: [OpenLibrary.Lenient<Item>]?
    }

    public static func parse(_ data: Data, now: Date = Date()) -> [BookMeta] {
        guard let volumes = try? JSONDecoder().decode(Volumes.self, from: data) else { return [] }
        return (volumes.items ?? []).compactMap { item in
            guard let info = item.value?.volumeInfo else { return nil }
            guard let title = info.title, !title.isEmpty else { return nil }
            let isbn = (info.industryIdentifiers ?? []).compactMap(\.value).sorted { $0.type == "ISBN_13" && $1.type != "ISBN_13" }
                .lazy.compactMap { ISBN.normalize($0.identifier) }.first
            // Covers come over http; the https address is the same image.
            let cover = (info.imageLinks?["thumbnail"] ?? info.imageLinks?["smallThumbnail"])?.replacingOccurrences(of: "http://", with: "https://")
            return BookMeta(
                isbn: isbn, title: title, author: info.authors?.joined(separator: ", ") ?? "", pages: info.pageCount,
                year: info.publishedDate.flatMap(OpenLibrary.year), subjects: info.categories ?? [],
                coverURL: cover.flatMap(URL.init(string:)), source: "googlebooks", fetchedAt: now, updatedAt: now)
        }
    }
}

/// A book's title and author from the text read off its cover. Apple's model does this best; this
/// is the plain fallback: the largest words are the title, and a name-shaped line the author.
public enum CoverText {
    public struct Line: Hashable, Sendable {
        public var text: String
        /// The text's height, as a share of the photo's.
        public var height: Double

        public init(text: String, height: Double) {
            self.text = text
            self.height = height
        }
    }

    public struct Guess: Hashable, Sendable {
        public var title: String
        public var author: String?

        public var query: String { [title, author].compactMap { $0 }.joined(separator: " ") }
    }

    /// For SystemAI: a light job, on the device.
    public static let instructions = """
        You read the text recognised on a photo of a book's cover and name the book. Answer in exactly two lines: \
        "Title: <title>" and "Author: <author>". Leave out taglines, quotes, prizes, series names and publishers. \
        If there is no author on the cover, write "Author: unknown".
        """

    public static func prompt(_ lines: [Line]) -> String {
        "Text on the cover, largest first:\n" + lines.sorted { $0.height > $1.height }.map(\.text).joined(separator: "\n")
    }

    /// The model's two lines, or nil when it didn't answer in that shape.
    public static func parseReply(_ reply: String) -> Guess? {
        var title: String?
        var author: String?
        for line in reply.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"*"))) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            switch parts[0].lowercased() {
            case "title": title = parts[1]
            case "author": author = parts[1].lowercased() == "unknown" ? nil : parts[1]
            default: break
            }
        }
        return title.map { Guess(title: $0, author: author) }
    }

    static let noise = [
        "bestsell", "new york times", "a novel", "winner", "author of", "prize", "praise", "edition", "copyright",
        "now a major", "the guardian", "the times", "magnificent", "brilliant", "extraordinary", "★", "translated",
    ]

    /// The tallest lines are the title (a title over two lines joined), and the tallest remaining
    /// line shaped like a name is the author.
    public static func guess(_ lines: [Line]) -> Guess? {
        let clean = lines.map { Line(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), height: $0.height) }
            .filter { line in
                line.text.filter(\.isLetter).count >= 2 && !noise.contains { line.text.lowercased().contains($0) }
            }
        guard let tallest = clean.map(\.height).max() else { return nil }
        let titleLines = clean.filter { $0.height >= tallest * 0.8 }
        let title = titleLines.map(\.text).joined(separator: " ")
        let author = clean.filter { $0.height < tallest * 0.8 && looksLikeName($0.text) }.max { $0.height < $1.height }?.text
        return Guess(title: titleCase(title), author: author.map(titleCase))
    }

    static func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (2...4).contains(words.count) else { return false }
        return words.allSatisfy { word in
            word.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "'" || $0 == "’" } && (word.first?.isUppercase ?? false)
        }
    }

    /// Covers shout: "THE NAME OF THE WIND" reads better as "The Name of the Wind".
    static func titleCase(_ text: String) -> String {
        guard text == text.uppercased(), text.contains(where: \.isLetter) else { return text }
        let small: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "with"]
        return text.lowercased().split(separator: " ").enumerated().map { index, word in
            index > 0 && small.contains(String(word)) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
