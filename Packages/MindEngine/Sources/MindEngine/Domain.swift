import Foundation
import SystemCore

/// What Mind Track trains. Japanese, maths and writing are Intelligence (active skill learning);
/// reading is Wisdom. Piano comes later.
public enum Domain: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case japanese, maths, writing, reading

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .japanese: "Japanese"
        case .maths: "Maths"
        case .writing: "Writing"
        case .reading: "Reading"
        }
    }

    public var symbol: String {
        switch self {
        case .japanese: "character.book.closed.ja"
        case .maths: "function"
        case .writing: "pencil.and.scribble"
        case .reading: "book.fill"
        }
    }

    public var pitch: String {
        switch self {
        case .japanese: "Words and kanji on spaced repetition, and listening until you can follow a show without subtitles."
        case .maths: "From fractions to calculus: find where you are, then master one topic at a time."
        case .writing: "Grammar, punctuation and usage, sharpened with short objective sets."
        case .reading: "A ladder of books that climbs out of your comfort zone, with a short reflection as you go."
        }
    }

    public var stat: StatKind { self == .reading ? .wisdom : .intelligence }

    public static func < (a: Domain, b: Domain) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

/// When the person studies: focused 25-minute blocks, five days a week by default.
public struct StudySchedule: Hashable, Codable, Sendable {
    public static let sessionOptions = [15, 25, 50]

    public var daysPerWeek: Int
    public var minutes: Int
    /// Days the person would rather study. Empty means any.
    public var preferredDays: [Weekday]

    public init(daysPerWeek: Int = 5, minutes: Int = 25, preferredDays: [Weekday] = []) {
        self.daysPerWeek = clamp(daysPerWeek, 1, 7)
        self.minutes = clamp(minutes, 10, 90)
        self.preferredDays = preferredDays
    }

    /// The study days of a week: the preferred ones, else spread evenly from Monday.
    public var studyDays: [Weekday] {
        TrainingSchedule(daysPerWeek: daysPerWeek, preferredDays: preferredDays).trainingDays
    }
}

/// How far someone got with maths, asked once so the diagnostic starts near the right place.
public enum MathsBackground: String, CaseIterable, Codable, Sendable, Identifiable {
    case basics, algebra, precalculus, calculus

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .basics: "Arithmetic and fractions"
        case .algebra: "Algebra"
        case .precalculus: "Functions, trig and logs"
        case .calculus: "Calculus"
        }
    }

    /// The topic level the diagnostic opens at.
    public var startLevel: Int {
        switch self {
        case .basics: 2
        case .algebra: 4
        case .precalculus: 6
        case .calculus: 8
        }
    }
}

/// Mind Track's own settings. One record.
public struct MindSettings: Hashable, Codable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000317D")!

    public var id: UUID
    public var domains: [Domain]
    public var schedule: StudySchedule
    public var onboardedAt: Date?
    /// Nil until asked. False starts Japanese with hiragana and katakana.
    public var readsKana: Bool?
    public var mathsBackground: MathsBackground
    public var genres: [Genre]
    /// Lagging domains get more sessions. Off keeps the split even.
    public var autoPrioritise: Bool
    /// Reminders at the usual study time when the day's session hasn't happened.
    public var reminders: Bool
    public var updatedAt: Date

    public init(domains: [Domain] = [.japanese, .maths, .writing, .reading], schedule: StudySchedule = StudySchedule(),
                onboardedAt: Date? = nil, readsKana: Bool? = nil, mathsBackground: MathsBackground = .algebra,
                genres: [Genre] = [], autoPrioritise: Bool = true, reminders: Bool = false, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.domains = domains.sorted()
        self.schedule = schedule
        self.onboardedAt = onboardedAt
        self.readsKana = readsKana
        self.mathsBackground = mathsBackground
        self.genres = genres
        self.autoPrioritise = autoPrioritise
        self.reminders = reminders
        self.updatedAt = updatedAt
    }

    public func has(_ domain: Domain) -> Bool { domains.contains(domain) }
}
