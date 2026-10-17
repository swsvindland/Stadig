import CryptoKit
import Foundation
import SystemCore

// Mind Track's records. Each is synced whole, newest wins, so anything two devices might both
// change at once (a card's memory, a book's page) is its own record.

/// What a card is about: "jp.word.1358280", "jp.kana.あ", "maths.fractions-add", "writing.commas".
public struct CardKey: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public var raw: String

    public init(_ raw: String) { self.raw = raw }

    public static func word(_ id: Int) -> CardKey { CardKey("jp.word.\(id)") }
    public static func kana(_ kana: String) -> CardKey { CardKey("jp.kana.\(kana)") }
    public static func topic(_ id: String) -> CardKey { CardKey("maths.\(id)") }
    public static func skill(_ id: String) -> CardKey { CardKey("writing.\(id)") }

    public var domain: Domain {
        if raw.hasPrefix("jp.") { return .japanese }
        if raw.hasPrefix("maths.") { return .maths }
        if raw.hasPrefix("writing.") { return .writing }
        return .reading
    }

    /// The id inside the domain: a word id, a kana, a topic or a skill.
    public var item: String { String(raw.split(separator: ".", maxSplits: 2).last ?? "") }
    public var wordID: Int? { raw.hasPrefix("jp.word.") ? Int(item) : nil }
    public var isKana: Bool { raw.hasPrefix("jp.kana.") }

    public var description: String { raw }

    public static func < (a: CardKey, b: CardKey) -> Bool { a.raw < b.raw }

    /// The same key always gets the same record id, so two devices learning the same word converge.
    public var recordID: UUID {
        let digest = Array(SHA256.hash(data: Data("mind.card.\(raw)".utf8)))
        var bytes = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9],
                     digest[10], digest[11], digest[12], digest[13], digest[14], digest[15])
        bytes.6 = (bytes.6 & 0x0F) | 0x50
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes)
    }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// One thing being remembered: a word, a kana, a maths topic or a writing skill.
public struct MemoryCard: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var key: CardKey
    /// Nil while it's still being learned (a topic not yet mastered).
    public var memory: Memory?
    /// Recent results while learning: a topic is mastered at 4 of the last 5.
    public var recent: [Bool]
    public var introduced: Date
    /// Shown to be known on a check rather than taught here.
    public var knownBefore: Bool
    public var updatedAt: Date

    public init(key: CardKey, memory: Memory? = nil, recent: [Bool] = [], introduced: Date, knownBefore: Bool = false,
                updatedAt: Date = Date()) {
        id = key.recordID
        self.key = key
        self.memory = memory
        self.recent = recent
        self.introduced = introduced
        self.knownBefore = knownBefore
        self.updatedAt = updatedAt
    }

    public var domain: Domain { key.domain }
    public var learning: Bool { memory == nil }

    public func isDue(on day: Day) -> Bool { memory.map { Day($0.due) <= day } ?? false }
}

/// What kind of question an attempt was.
public enum AttemptKind: String, Codable, Sendable {
    /// A spaced review of something learned.
    case review
    /// Learning something new: taught, then asked.
    case learn
    /// A quick check of something probably known already (below the placement level).
    case probe
    /// Placement and check-in tests: they measure, and never schedule.
    case test
}

/// One answered question.
public struct Attempt: Hashable, Codable, Sendable {
    public var key: CardKey
    public var kind: AttemptKind
    public var correct: Bool
    /// "Don't know" on a test: not a guess.
    public var skipped: Bool
    public var seconds: Double
    public var at: Date
    /// The test it belonged to and, for banded tests, the band.
    public var test: TestKind?
    public var band: Int?

    public init(key: CardKey, kind: AttemptKind, correct: Bool, skipped: Bool = false, seconds: Double, at: Date,
                test: TestKind? = nil, band: Int? = nil) {
        self.key = key
        self.kind = kind
        self.correct = correct
        self.skipped = skipped
        self.seconds = seconds
        self.at = at
        self.test = test
        self.band = band
    }

    public var domain: Domain { key.domain }
}

public enum StudyKind: String, Codable, Sendable {
    /// The first sessions: finding a level in each domain.
    case placement
    case regular
    /// A system deload week: review only, nothing new.
    case review
    /// Plain check-in tests at the end of a review week.
    case checkIn
    /// Optional extra: a few minutes of reviews on a rest or paused day.
    case extra

    public var label: String {
        switch self {
        case .placement: "Finding your level"
        case .regular: "Session"
        case .review: "Review session"
        case .checkIn: "Check-in"
        case .extra: "Quick review"
        }
    }
}

/// Pages read in a session.
public struct ReadingLog: Hashable, Codable, Sendable {
    public var bookID: UUID
    public var fromPage: Int
    public var toPage: Int
    public var minutes: Double

    public init(bookID: UUID, fromPage: Int, toPage: Int, minutes: Double) {
        self.bookID = bookID
        self.fromPage = fromPage
        self.toPage = toPage
        self.minutes = minutes
    }

    public var pages: Int { max(0, toPage - fromPage) }
}

/// A focused study block that happened.
public struct StudySession: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var purpose: StudyKind
    public var start: Date
    public var end: Date?
    public var plannedMinutes: Int
    /// The domains of the main block.
    public var domains: [Domain]
    /// Part of the plan (for Discipline), as opposed to extra.
    public var planned: Bool
    public var attempts: [Attempt]
    public var reading: ReadingLog?
    /// Seconds spent actively in the session, pauses left out.
    public var activeSeconds: Double
    /// Everything planned was done (the plan can run out before the clock does).
    public var ranToEnd: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), purpose: StudyKind, start: Date, end: Date? = nil, plannedMinutes: Int, domains: [Domain],
                planned: Bool, attempts: [Attempt] = [], reading: ReadingLog? = nil, activeSeconds: Double = 0,
                ranToEnd: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.purpose = purpose
        self.start = start
        self.end = end
        self.plannedMinutes = plannedMinutes
        self.domains = domains
        self.planned = planned
        self.attempts = attempts
        self.reading = reading
        self.activeSeconds = activeSeconds
        self.ranToEnd = ranToEnd
        self.updatedAt = updatedAt
    }

    public var day: Day { Day(start) }
    public var minutes: Double { activeSeconds / 60 }
    public var finished: Bool { end != nil }

    /// Counts toward the plan: everything planned done, or most of the planned time.
    public var counts: Bool {
        guard finished else { return false }
        return ranToEnd || purpose == .checkIn || purpose == .placement || minutes >= Double(plannedMinutes) * 0.6
    }
}

/// The honest measures. Tests measure and never schedule, and only these move a stat.
public enum TestKind: String, Codable, Sendable, CaseIterable {
    /// Words known, estimated from a sample of every frequency band.
    case vocabulary
    /// Sentences understood by ear, at several levels.
    case listening
    /// An episode watched without subtitles, rated after: a plain check-in, not a score.
    case episode
    /// Placement across the maths topics.
    case mathsPlacement
    /// A mixed, timed problem set over what's been learned.
    case maths
    /// A mixed set over every writing skill.
    case writing

    public var label: String {
        switch self {
        case .vocabulary: "Vocabulary"
        case .listening: "Listening"
        case .episode: "No-subtitles episode"
        case .mathsPlacement: "Maths placement"
        case .maths: "Maths check"
        case .writing: "Writing check"
        }
    }

    public var domain: Domain {
        switch self {
        case .vocabulary, .listening, .episode: .japanese
        case .mathsPlacement, .maths: .maths
        case .writing: .writing
        }
    }
}

/// A test's result. `score` is the test's own measure (words for vocabulary, a 0–1 share
/// otherwise); `detail` keeps the parts (per band, low and high, seconds per problem).
public struct TestResult: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var test: TestKind
    public var date: Date
    public var score: Double
    public var detail: [String: Double]
    public var placement: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), test: TestKind, date: Date, score: Double, detail: [String: Double] = [:],
                placement: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.test = test
        self.date = date
        self.score = score
        self.detail = detail
        self.placement = placement
        self.updatedAt = updatedAt
    }

    public var day: Day { Day(date) }
}

public enum Genre: String, CaseIterable, Codable, Sendable, Identifiable {
    case fantasy, sciFi, literary, classics, crime, nonfiction, philosophy

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fantasy: "Fantasy"
        case .sciFi: "Science fiction"
        case .literary: "Literary fiction"
        case .classics: "Classics"
        case .crime: "Crime and mystery"
        case .nonfiction: "Non-fiction"
        case .philosophy: "Philosophy"
        }
    }
}

public enum BookStatus: String, Codable, Sendable {
    case reading, finished, abandoned
    /// Read before Mind Track: places the ladder.
    case readBefore
}

/// How a finished book felt. Moves the ladder: easy or right steps up, hard holds.
public enum BookFeel: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy, right, hard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .easy: "Easy"
        case .right: "A stretch, but fine"
        case .hard: "Hard going"
        }
    }
}

/// A book on the person's shelf: from the ladder, or their own.
public struct Book: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// The ladder book, when it's one.
    public var ladderID: String?
    public var title: String
    public var author: String
    public var tier: Int
    public var pages: Int
    public var genres: [Genre]
    public var status: BookStatus
    public var started: Day?
    public var finished: Day?
    public var page: Int
    public var feel: BookFeel?
    public var updatedAt: Date

    public init(id: UUID = UUID(), ladderID: String? = nil, title: String, author: String, tier: Int, pages: Int, genres: [Genre],
                status: BookStatus, started: Day? = nil, finished: Day? = nil, page: Int = 0, feel: BookFeel? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.ladderID = ladderID
        self.title = title
        self.author = author
        self.tier = clamp(tier, 1, 10)
        self.pages = max(1, pages)
        self.genres = genres
        self.status = status
        self.started = started
        self.finished = finished
        self.page = page
        self.feel = feel
        self.updatedAt = updatedAt
    }

    public var progress: Double { min(1, Double(page) / Double(pages)) }
    public var done: Bool { status == .finished || status == .readBefore }
}

public enum ReflectionKind: String, Codable, Sendable {
    /// After a session's reading.
    case section
    /// After finishing a book.
    case book
}

/// A few sentences after reading: what happened, what struck you.
public struct Reflection: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var bookID: UUID?
    public var date: Date
    public var kind: ReflectionKind
    public var page: Int?
    public var text: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), bookID: UUID?, date: Date, kind: ReflectionKind, page: Int? = nil, text: String,
                updatedAt: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.date = date
        self.kind = kind
        self.page = page
        self.text = text
        self.updatedAt = updatedAt
    }
}
