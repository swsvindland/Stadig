import Foundation
import SystemCore

/// A course Stadig Mind runs: one per language, plus maths, writing and reading. Languages, maths
/// and writing are Intelligence (active skill learning); reading is Wisdom. Piano comes later.
public enum Domain: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable, Comparable {
    case japanese, spanish, maths, writing, reading

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .japanese: "Japanese"
        case .spanish: "Spanish"
        case .maths: "Maths"
        case .writing: "Writing"
        case .reading: "Reading"
        }
    }

    public var symbol: String {
        switch self {
        case .japanese: "character.book.closed.ja"
        case .spanish: "character.bubble"
        case .maths: "function"
        case .writing: "pencil.and.scribble"
        case .reading: "book.fill"
        }
    }

    public var pitch: String {
        switch self {
        case .japanese: "Listening, speaking, reading and writing, with kana and kanji scaffolds that fade as each one sticks."
        case .spanish: "Understand and be understood: listening and speaking first, with words on spaced repetition."
        case .maths: "Everyday numeracy every session, plus algebra to calculus and the statistics that matter in real life."
        case .writing: "Creative, practical or persuasive: write, get a few specific notes, and see the difference term by term."
        case .reading: "A ladder of books just above where you read now, with stamina built separately from difficulty."
        }
    }

    public var stat: StatKind { self == .reading ? .wisdom : .intelligence }

    /// The language a course teaches, for language courses.
    public var language: Language? {
        switch self {
        case .japanese: .japanese
        case .spanish: .spanish
        default: nil
        }
    }

    public var isLanguage: Bool { language != nil }

    public static var languages: [Domain] { allCases.filter(\.isLanguage) }

    public static func < (a: Domain, b: Domain) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

/// How hard a course is pushed. Main courses have days of their own in the weekly split: full
/// sessions and new material. Secondary courses take turns at a short block in sessions, so they
/// keep moving, more slowly. Maintenance courses keep what's learned with a few minutes of
/// reviews in each session's warm-up. `focus` is Main's stored name, from before there were three.
public enum CourseMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case focus, secondary, maintenance

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .focus: "Main"
        case .secondary: "Secondary"
        case .maintenance: "Maintenance"
        }
    }

    public var detail: String {
        switch self {
        case .focus: "Days of its own: full sessions and new material."
        case .secondary: "A short block in most sessions: new material, more slowly."
        case .maintenance: "Reviews only, a few minutes a day, so nothing slips."
        }
    }

    /// Main and Secondary courses learn new material; Maintenance only reviews.
    public var learns: Bool { self != .maintenance }
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

    public var weeklyMinutes: Int { daysPerWeek * minutes }
}

/// How far someone got with maths at school, as the first version asked. Kept so old settings
/// decode; nothing reads it now that placement is a short test of each strand.
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
