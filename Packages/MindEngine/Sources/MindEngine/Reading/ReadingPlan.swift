import Foundation
import SystemCore

/// Reading as two dimensions and a prescription.
///
/// - **Level** is how hard a book can be, 1–10 on the ladder. It comes from the reading test and
///   from finished books (easy, just right or a slog), never from time read.
/// - **Stamina** is how long focus holds in one sitting, measured from reading blocks on print and
///   ebooks. Audiobooks count for level and taste, not stamina.
/// - **The next book** starts just below the tested level and climbs as books feel easy or just
///   right; a slog holds it, and one given up on as too hard steps it back.
public enum ReadingPlan {
    /// Without a test or a finished book, the ladder starts here.
    public static let startingTier = 2
    /// The first reading block, before any focus has been measured.
    public static let firstBlock = 15
    static let blockRange = 5...90

    // MARK: Level

    /// One piece of evidence about the level: it should lie between `low` and `high`.
    struct Evidence: Hashable {
        var low: Double
        var high: Double
        var weight: Double
    }

    /// The reader's level as of a day: the value that best fits every test and finished book,
    /// recent ones counting most. Nil with neither. Only English books count here; a language's
    /// graded readers level that language.
    public static func level(books: [Book], tests: [TestResult], on day: Day) -> Double? {
        let evidence = self.evidence(books: books, tests: tests, on: day)
        guard !evidence.isEmpty else { return nil }
        // A convex, piecewise quadratic loss over 1–10: a fine grid finds its minimum exactly
        // enough, and the lowest point of a flat stretch keeps a lower bound honest.
        var best = (level: 1.0, loss: Double.infinity)
        for step in 0...900 {
            let candidate = 1 + Double(step) / 100
            let loss = evidence.map { e -> Double in
                if candidate < e.low { return e.weight * (e.low - candidate) * (e.low - candidate) }
                if candidate > e.high { return e.weight * (candidate - e.high) * (candidate - e.high) }
                return 0
            }.reduce(0, +)
            if loss < best.loss - 1e-9 { best = (candidate, loss) }
        }
        return (best.level * 10).rounded() / 10
    }

    static func evidence(books: [Book], tests: [TestResult], on day: Day) -> [Evidence] {
        var out: [Evidence] = []
        for test in tests where test.test == .readingTest && test.domain == .reading && test.day <= day {
            guard let tier = test.detail["tier"] else { continue }
            out.append(Evidence(low: tier, high: tier, weight: 3 * decay(days: test.day.days(until: day), halfLife: 180)))
        }
        for book in books where book.language == nil && book.done {
            let finished = finishDay(book)
            guard finished <= day else { continue }
            let tier = Double(book.tier)
            var weight = confidence(book) * decay(days: finished.days(until: day), halfLife: 365)
            if book.format == .audiobook { weight *= 0.5 }
            // Read before Mind Track: the last year's books, said rather than seen.
            if book.status == .readBefore { weight *= 0.5 }
            switch book.feel {
            case .easy: out.append(Evidence(low: tier + 0.5, high: .infinity, weight: weight))
            case .hard: out.append(Evidence(low: tier - 1.25, high: tier - 0.5, weight: weight))
            case .right, nil: out.append(Evidence(low: tier, high: tier, weight: weight))
            }
        }
        return out
    }

    /// How sure a book's tier is: a ladder book is certain (or nearly, levelled from its text);
    /// one's own book is an estimate, so it moves the level less.
    static func confidence(_ book: Book) -> Double {
        book.tierConfidence ?? (book.ladderID != nil ? 1 : BookLevel.guessConfidence)
    }

    static func finishDay(_ book: Book) -> Day { book.finished ?? Day(book.updatedAt) }

    static func decay(days: Int, halfLife: Double) -> Double { pow(0.5, Double(max(0, days)) / halfLife) }

    /// The tier the latest reading test placed at, by a day.
    public static func tested(_ tests: [TestResult], on day: Day) -> TestResult? {
        tests.last { $0.test == .readingTest && $0.domain == .reading && $0.day <= day && $0.detail["tier"] != nil }
    }

    // MARK: The next book

    /// The next book's tier, as a fraction: just below the tested level to begin with, then up a
    /// tier after an easy book and half a tier after a just-right one, held after a slog, back a
    /// tier after one given up on as too hard. Kept within two tiers below and one above the level.
    public static func target(books: [Book], tests: [TestResult], on day: Day) -> Double {
        let level = self.level(books: books, tests: tests, on: day)
        let firstTest = tests.first { $0.test == .readingTest && $0.domain == .reading && $0.detail["tier"] != nil }
        guard let anchor = firstTest?.detail["tier"] ?? level else { return Double(startingTier) }
        var target = anchor - 1
        let since = firstTest?.day ?? .init(ordinal: 0)
        let read = books.filter { $0.language == nil && ($0.status == .finished || $0.status == .abandoned) }
            .filter { finishDay($0) >= since && finishDay($0) <= day }
            .sorted { (finishDay($0), $0.updatedAt) < (finishDay($1), $1.updatedAt) }
        for book in read {
            let tier = Double(book.tier)
            switch (book.status, book.feel) {
            case (.finished, .easy): target = max(target, tier + 1)
            case (.finished, .right), (.finished, nil): target = max(target, tier + 0.5)
            case (.finished, .hard): target = min(target, tier)
            case (.abandoned, .hard): target = min(target, tier - 1)
            default: break // Given up on for other reasons: taste, not difficulty.
            }
        }
        if let level { target = clamp(target, level - 2, level + 1) }
        return clamp(target, 1, 10)
    }

    public static func targetTier(books: [Book], tests: [TestResult], on day: Day) -> Int {
        clamp(Int(target(books: books, tests: tests, on: day).rounded()), 1, 10)
    }

    /// Up to `count` ladder books near the next tier, liked genres first, none already on the
    /// shelf and no two by the same author.
    public static func suggestions(shelf: [Book], tests: [TestResult], genres: [Genre], on day: Day,
                                   ladder: ReadingLadder = .standard, count: Int = 3) -> [LadderBook] {
        let target = self.target(books: shelf, tests: tests, on: day)
        let owned = Set(shelf.compactMap(\.ladderID))
        let ownedTitles = Set(shelf.map { BookLevel.matchKey(title: $0.title, author: $0.author) })
        let liked = Set(genres)
        func score(_ book: LadderBook) -> Double {
            let tier = Double(book.tier)
            let distance = abs(tier - target) + (tier > target ? 0.25 : 0)
            let genre = liked.isEmpty || !liked.isDisjoint(with: book.genres) ? 0 : 1.5
            return distance + genre + (book.levelledFromText ? 0.3 : 0)
        }
        let candidates = ladder.books(in: nil).filter {
            !owned.contains($0.id) && !ownedTitles.contains(BookLevel.matchKey(title: $0.title, author: $0.author))
                && abs(Double($0.tier) - target) <= 1.5
        }.sorted { (score($0), $0.pages, $0.id) < (score($1), $1.pages, $1.id) }
        var picks: [LadderBook] = []
        for book in candidates where !picks.contains(where: { $0.author == book.author }) {
            picks.append(book)
            if picks.count == count { break }
        }
        return picks
    }

    // MARK: Stamina

    /// A reading block that counts for stamina: on a print book or an ebook.
    public struct Block: Hashable, Sendable {
        public var day: Day
        public var minutes: Double
        /// The block asked for, from stamina; nil before v2 (the timer's length was the plan).
        public var planned: Int?
        public var focus: ReadingFocus?

        public init(day: Day, minutes: Double, planned: Int? = nil, focus: ReadingFocus? = nil) {
            self.day = day
            self.minutes = minutes
            self.planned = planned
            self.focus = focus
        }

        /// Minutes of it read with focus.
        var focused: Double { minutes * (focus?.share ?? 0.9) }
    }

    /// Reading blocks on print and ebooks, oldest first. Audiobooks and very short blocks are left out.
    public static func blocks(_ sessions: [StudySession], books: [Book]) -> [Block] {
        let formats = Dictionary(books.map { ($0.id, $0.format ?? .print) }, uniquingKeysWith: { a, _ in a })
        return sessions.sorted { $0.start < $1.start }.compactMap { session in
            guard let log = session.reading, log.minutes >= 2, formats[log.bookID]?.countsForStamina ?? true else { return nil }
            return Block(day: session.day, minutes: log.minutes, planned: log.planned, focus: log.focus)
        }
    }

    /// Focused minutes in one sitting: the best of the recent blocks, read with focus. Nil until a
    /// block on print or an ebook.
    public static func stamina(_ blocks: [Block]) -> Double? {
        let recent = blocks.suffix(8).map(\.focused).sorted(by: >)
        guard !recent.isEmpty else { return nil }
        let best = recent.prefix(3)
        return (best.reduce(0, +) / Double(best.count)).rounded()
    }

    /// The next block's length. It climbs a little (two minutes, or a tenth) after a block where
    /// focus held all the way, and straight to what was read when the reading went past the timer;
    /// holds after focus drifted; drops a quarter below what was read after focus was lost. A block
    /// cut short by the session's length says nothing against a longer one.
    public static func nextBlock(_ blocks: [Block]) -> Int {
        var next = Double(firstBlock)
        for block in blocks {
            let asked = Double(block.planned ?? Int(block.minutes.rounded()))
            let step = max(2, asked * 0.1)
            let fullBlock = block.minutes >= asked * 0.9
            switch block.focus {
            case .held, nil:
                if fullBlock { next = max(next, asked + step, block.minutes.rounded()) }
            case .drifted:
                next = min(next, fullBlock ? asked : max(block.minutes, asked - step))
            case .lost:
                next = min(next, min(block.minutes, asked) * 0.75)
            }
        }
        return clamp(Int(next.rounded()), blockRange.lowerBound, blockRange.upperBound)
    }

    // MARK: Measures

    /// 0–100 for the hub: the level, ten points a tier.
    public static func score(_ level: Double?) -> Double? { level.map { $0 * 10 } }

    /// Pages a minute, from logged reading. Nil without enough.
    public static func pace(_ sessions: [StudySession]) -> Double? {
        let logs = sessions.compactMap(\.reading).filter { $0.minutes >= 5 && $0.pages > 0 }
        let minutes = logs.map(\.minutes).reduce(0, +)
        guard minutes >= 20 else { return nil }
        return Double(logs.map(\.pages).reduce(0, +)) / minutes
    }

    /// Wisdom: the level from the reading test and finished books. Time read never moves it.
    public static func wisdom(_ state: StudyState) -> StatReading {
        let level = self.level(books: state.books, tests: state.tests, on: state.today)
        let finished = state.books.filter { $0.status == .finished && $0.language == nil && finishDay($0).days(until: state.today) <= 84 }.count
        let label = level.map { "Reads at tier \(Self.format($0)) of 10 · \(finished) finished in 12 weeks" } ?? "Measured by the reading test"
        return StatReading(stat: .wisdom, score: score(level), label: label, trend: Analyst.trajectory(.reading, state: state),
                           updated: state.now)
    }

    /// The level after each test and each finished book, oldest first.
    static func series(_ state: StudyState) -> [(day: Day, score: Double)] {
        let tests = state.tests.filter { $0.test == .readingTest && $0.domain == .reading && $0.detail["tier"] != nil }.map(\.day)
        let books = state.books.filter { $0.language == nil && $0.done }.map(finishDay)
        return Set(tests + books).sorted().compactMap { day in
            level(books: state.books, tests: state.tests, on: day).map { (day, $0 * 10) }
        }
    }

    public static func summary(_ state: StudyState) -> ReadingSummary {
        let blocks = self.blocks(state.sessions, books: state.books)
        let target = self.target(books: state.books, tests: state.tests, on: state.today)
        return ReadingSummary(current: state.currentBook, level: level(books: state.books, tests: state.tests, on: state.today),
                              test: tested(state.tests, on: state.today), target: target, targetTier: clamp(Int(target.rounded()), 1, 10),
                              stamina: stamina(blocks), nextBlock: nextBlock(blocks),
                              finished: state.books.filter { $0.status == .finished }.sorted { ($0.finished ?? state.today) > ($1.finished ?? state.today) },
                              pagesPerMinute: pace(state.sessions))
    }

    /// "5.5", or "5" for a whole tier.
    public static func format(_ level: Double) -> String {
        let rounded = (level * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}

/// Where the reader is: level and stamina apart, and what comes next.
public struct ReadingSummary: Hashable, Sendable {
    public var current: Book?
    /// 1–10, from the reading test and finished books. Nil until either.
    public var level: Double?
    /// The latest reading test.
    public var test: TestResult?
    /// The next book's tier, as a fraction and rounded.
    public var target: Double
    public var targetTier: Int
    /// Focused minutes in one sitting, from print and ebooks. Nil until measured.
    public var stamina: Double?
    /// The next reading block's length, in minutes.
    public var nextBlock: Int
    public var finished: [Book]
    public var pagesPerMinute: Double?

    /// The tested level's own number.
    public var testedLevel: Double? { test?.detail["tier"] }
}
