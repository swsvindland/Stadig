import Foundation
import SystemCore

public struct LadderTier: Hashable, Codable, Sendable {
    public var tier: Int
    public var label: String
    public var description: String
}

/// A book on the ladder. `year` is negative before the common era (The Republic is -375).
public struct LadderBook: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var author: String
    public var year: Int
    public var pages: Int
    public var tier: Int
    public var genres: [Genre]
    public var note: String

    public func book(status: BookStatus, started: Day? = nil) -> Book {
        Book(ladderID: id, title: title, author: author, tier: tier, pages: pages, genres: genres, status: status, started: started)
    }
}

/// Ten tiers of real reading difficulty (prose, vocabulary, structure, what the book asks of the
/// reader), with stepping-stone books between them: Sanderson towards Woolf.
public struct ReadingLadder: Sendable {
    public var tiers: [LadderTier]
    public var books: [LadderBook]

    public init(tiers: [LadderTier], books: [LadderBook]) {
        self.tiers = tiers.sorted { $0.tier < $1.tier }
        self.books = books
    }

    private struct File: Decodable {
        var tiers: [LadderTier]
        var books: [LadderBook]
    }

    public static let standard: ReadingLadder = {
        guard let url = Bundle.module.url(forResource: "ladder", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
            mindLog.error("The reading ladder is missing or unreadable")
            return ReadingLadder(tiers: [], books: [])
        }
        return ReadingLadder(tiers: file.tiers, books: file.books)
    }()

    public func tier(_ n: Int) -> LadderTier? { tiers.first { $0.tier == n } }
    public func book(_ id: String) -> LadderBook? { books.first { $0.id == id } }
}

/// Where someone is on the ladder and what to read next.
public enum ReadingPlan {
    /// Without any books read, the ladder starts here.
    public static let startingTier = 2

    /// The highest tier finished without it feeling hard. Books read before the app count, unless
    /// marked hard going.
    public static func comfortTier(_ shelf: [Book]) -> Int? {
        shelf.filter { $0.done && $0.feel != .hard }.map(\.tier).max()
    }

    /// One tier above comfort, out of the comfort zone; the same tier again after a hard one or a
    /// book given up on, so the step isn't missed twice.
    public static func targetTier(_ shelf: [Book]) -> Int {
        let comfort = comfortTier(shelf) ?? (startingTier - 1)
        let recent = shelf.filter { $0.status == .finished || $0.status == .abandoned }
            .max { ($0.finished ?? .init(ordinal: 0)) < ($1.finished ?? .init(ordinal: 0)) }
        if let recent, recent.status == .abandoned || recent.feel == .hard { return max(1, min(comfort, recent.tier)) }
        return min(10, comfort + 1)
    }

    /// Up to `count` ladder books at the target tier (then next to it), liked genres first, none
    /// already on the shelf.
    public static func suggestions(shelf: [Book], genres: [Genre], ladder: ReadingLadder = .standard, count: Int = 3) -> [LadderBook] {
        let target = targetTier(shelf)
        let owned = Set(shelf.compactMap(\.ladderID))
        let liked = Set(genres)
        func score(_ book: LadderBook) -> Double {
            let distance = Double(abs(book.tier - target)) + (book.tier > target ? 0.5 : 0)
            let genre = liked.isEmpty || !liked.isDisjoint(with: book.genres) ? 0 : 1.5
            return distance + genre
        }
        return ladder.books.filter { !owned.contains($0.id) && abs($0.tier - target) <= 1 }
            .sorted { (score($0), $0.pages, $0.id) < (score($1), $1.pages, $1.id) }
            .prefix(count).map { $0 }
    }

    /// 0–100 for the hub: the comfort tier, ten points a tier.
    public static func score(_ shelf: [Book]) -> Double? { comfortTier(shelf).map { Double($0) * 10 } }

    /// Pages a minute at a tier, from logged reading. Nil without enough.
    public static func pace(_ sessions: [StudySession]) -> Double? {
        let logs = sessions.compactMap(\.reading).filter { $0.minutes >= 5 && $0.pages > 0 }
        let minutes = logs.map(\.minutes).reduce(0, +)
        guard minutes >= 20 else { return nil }
        return Double(logs.map(\.pages).reduce(0, +)) / minutes
    }
}
