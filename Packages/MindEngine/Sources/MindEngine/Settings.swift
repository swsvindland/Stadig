import Foundation
import SystemCore

/// Stadig Mind's own settings. One record. Decoding fills anything missing with its default, so a
/// field added later never breaks a record saved before it, and keeps values it doesn't know (a
/// course or genre from a newer version on another device) aside and writes them back unchanged.
public struct MindSettings: Hashable, Codable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000317D")!
    /// Days start at 4 a.m. unless changed, as Anki's do: late enough for a late night, early
    /// enough for an early morning.
    public static let standardDayStart = 4
    /// The hours a day can start at: midnight, or a little after it.
    public static let dayStarts = 0...6

    public var id: UUID
    /// Every active course. Courses not here are off. How much of each there is lives in
    /// `WeekSettings`, which keeps these values in step for older builds.
    public var courses: [Domain: CourseMode]
    public var schedule: StudySchedule
    /// Schedules replaced in the last few weeks, so Discipline judges each day by the one in force
    /// then: a change of days doesn't rewrite the weeks before it. See `recordScheduleChange`.
    public var earlierSchedules: [EarlierSchedule]
    public var onboardedAt: Date?
    /// Nil until asked. False starts Japanese with hiragana and katakana.
    public var readsKana: Bool?
    /// What the first version asked about school maths. Kept so old records decode; placement is
    /// a test of each strand now, and nothing reads this.
    public var mathsBackground: MathsBackground
    /// Maths strands in the order that matters to this person; numeracy is always kept up.
    public var mathsStrands: [MathsStrand]
    /// The kinds of writing to improve. Creative by default.
    public var writingKinds: [WritingKind]
    public var genres: [Genre]
    /// Speaking exercises use the microphone; off skips them (on a train, say) without a gap in the plan.
    public var speaking: Bool
    /// Private Cloud Compute for heavier AI jobs (writing feedback) when the device model isn't enough.
    public var allowCloudAI: Bool
    /// A lagging course gets one more block a week.
    public var autoPrioritise: Bool
    /// Not built yet: nothing reads this.
    public var reminders: Bool
    /// The hour on the clock a study day begins. A session between midnight and then counts for
    /// the evening before, so a lesson done late on Friday night is Friday's.
    public var dayStart: Int
    public var updatedAt: Date
    /// Values a newer version wrote that this one can't read.
    private var unrecognised = Unrecognised()

    /// A schedule that was in force until a day, not including it.
    public struct EarlierSchedule: Hashable, Codable, Sendable {
        public var until: Day
        public var schedule: StudySchedule

        public init(until: Day, schedule: StudySchedule) {
            self.until = until
            self.schedule = schedule
        }
    }

    struct Unrecognised: Hashable, Sendable {
        var courses: [String: String] = [:]
        var mathsStrands: [String] = []
        var writingKinds: [String] = []
        var genres: [String] = []
    }

    public init(
        courses: [Domain: CourseMode] = [.japanese: .focus, .maths: .focus, .writing: .focus, .reading: .focus],
        schedule: StudySchedule = StudySchedule(), onboardedAt: Date? = nil, readsKana: Bool? = nil,
        mathsBackground: MathsBackground = .algebra, mathsStrands: [MathsStrand] = MathsStrand.allCases,
        writingKinds: [WritingKind] = [.creative], genres: [Genre] = [], speaking: Bool = true, allowCloudAI: Bool = true,
        autoPrioritise: Bool = true, reminders: Bool = false, dayStart: Int = standardDayStart, updatedAt: Date = Date(),
        earlierSchedules: [EarlierSchedule] = []
    ) {
        id = Self.singletonID
        self.courses = courses
        self.schedule = schedule
        self.earlierSchedules = earlierSchedules
        self.onboardedAt = onboardedAt
        self.readsKana = readsKana
        self.mathsBackground = mathsBackground
        self.mathsStrands = mathsStrands
        self.writingKinds = writingKinds
        self.genres = genres
        self.speaking = speaking
        self.allowCloudAI = allowCloudAI
        self.autoPrioritise = autoPrioritise
        self.reminders = reminders
        self.dayStart = Self.clampedDayStart(dayStart)
        self.updatedAt = updatedAt
    }

    /// Every active course, in order.
    public var domains: [Domain] { courses.keys.sorted() }
    /// Courses on reviews only.
    public var maintenance: [Domain] { domains.filter { courses[$0] == .maintenance } }
    /// The courses that learn new material.
    public var studied: [Domain] { domains.filter { courses[$0]?.learns == true } }
    public var languages: [Domain] { domains.filter(\.isLanguage) }

    public func has(_ domain: Domain) -> Bool { courses[domain] != nil }
    public func mode(_ domain: Domain) -> CourseMode? { courses[domain] }

    /// The schedule in force on a day.
    public func schedule(on day: Day) -> StudySchedule {
        earlierSchedules.sorted { $0.until < $1.until }.first { day < $0.until }?.schedule ?? schedule
    }

    /// Call after `schedule` changes, with the one it replaced: days before `day` keep being
    /// judged by it. A second change on the same day keeps the schedule from before the first.
    public mutating func recordScheduleChange(from previous: StudySchedule, on day: Day) {
        guard previous != schedule else { return }
        if earlierSchedules.last?.until != day { earlierSchedules.append(EarlierSchedule(until: day, schedule: previous)) }
        // Discipline looks back four weeks and the week view one; older changes never matter.
        earlierSchedules.removeAll { $0.until.days(until: day) > Discipline.windowDays + 7 }
    }

    enum CodingKeys: String, CodingKey {
        case id, courses, domains, schedule, earlierSchedules, onboardedAt, readsKana, mathsBackground, mathsStrands, writingKinds, genres,
            speaking, allowCloudAI, autoPrioritise, reminders, dayStart, updatedAt
    }

    private static func clampedDayStart(_ hour: Int) -> Int { min(max(hour, dayStarts.lowerBound), dayStarts.upperBound) }

    /// The values that parse, in order, and the raw ones that don't.
    private static func split<T: RawRepresentable>(_ raw: [String]) -> (known: [T], unknown: [String]) where T.RawValue == String {
        (raw.compactMap(T.init(rawValue:)), raw.filter { T(rawValue: $0) == nil })
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? Self.singletonID
        if let raw = try c.decodeIfPresent([String: String].self, forKey: .courses) {
            var courses: [Domain: CourseMode] = [:]
            for (key, value) in raw {
                if let domain = Domain(rawValue: key), let mode = CourseMode(rawValue: value) {
                    courses[domain] = mode
                } else {
                    unrecognised.courses[key] = value
                }
            }
            self.courses = courses
        } else {
            // Version 1 kept a plain list of subjects: every one was a full course. A repeat (from
            // a hand-edited backup) counts once.
            let old =
                try c.decodeIfPresent([String].self, forKey: .domains)?.compactMap(Domain.init(rawValue:))
                ?? [.japanese, .maths, .writing, .reading]
            courses = Dictionary(old.map { ($0, CourseMode.focus) }, uniquingKeysWith: { first, _ in first })
        }
        schedule = try c.decodeIfPresent(StudySchedule.self, forKey: .schedule) ?? StudySchedule()
        earlierSchedules = try c.decodeIfPresent([EarlierSchedule].self, forKey: .earlierSchedules) ?? []
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
        readsKana = try c.decodeIfPresent(Bool.self, forKey: .readsKana)
        mathsBackground = try c.decodeIfPresent(MathsBackground.self, forKey: .mathsBackground) ?? .algebra
        mathsStrands = MathsStrand.allCases
        if let raw = try c.decodeIfPresent([String].self, forKey: .mathsStrands) {
            (mathsStrands, unrecognised.mathsStrands) = Self.split(raw)
        }
        writingKinds = [.creative]
        if let raw = try c.decodeIfPresent([String].self, forKey: .writingKinds) {
            (writingKinds, unrecognised.writingKinds) = Self.split(raw)
        }
        genres = []
        if let raw = try c.decodeIfPresent([String].self, forKey: .genres) {
            (genres, unrecognised.genres) = Self.split(raw)
        }
        speaking = try c.decodeIfPresent(Bool.self, forKey: .speaking) ?? true
        allowCloudAI = try c.decodeIfPresent(Bool.self, forKey: .allowCloudAI) ?? true
        autoPrioritise = try c.decodeIfPresent(Bool.self, forKey: .autoPrioritise) ?? true
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? false
        // Saved before there was a choice: 4 a.m., which files the late nights already studied
        // under the evenings they belong to.
        dayStart = Self.clampedDayStart(try c.decodeIfPresent(Int.self, forKey: .dayStart) ?? Self.standardDayStart)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        let courses = Dictionary(uniqueKeysWithValues: courses.map { ($0.key.rawValue, $0.value.rawValue) })
        try c.encode(courses.merging(unrecognised.courses) { known, _ in known }, forKey: .courses)
        try c.encode(schedule, forKey: .schedule)
        if !earlierSchedules.isEmpty { try c.encode(earlierSchedules, forKey: .earlierSchedules) }
        try c.encodeIfPresent(onboardedAt, forKey: .onboardedAt)
        try c.encodeIfPresent(readsKana, forKey: .readsKana)
        try c.encode(mathsBackground, forKey: .mathsBackground)
        try c.encode(mathsStrands.map(\.rawValue) + unrecognised.mathsStrands, forKey: .mathsStrands)
        try c.encode(writingKinds.map(\.rawValue) + unrecognised.writingKinds, forKey: .writingKinds)
        try c.encode(genres.map(\.rawValue) + unrecognised.genres, forKey: .genres)
        try c.encode(speaking, forKey: .speaking)
        try c.encode(allowCloudAI, forKey: .allowCloudAI)
        try c.encode(autoPrioritise, forKey: .autoPrioritise)
        try c.encode(reminders, forKey: .reminders)
        try c.encode(dayStart, forKey: .dayStart)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// How much the chosen courses ask of the week, against the time there is.
public enum CourseLoad {
    /// Blocks a week below which a language barely moves: it wants near-daily exposure.
    public static let languageBlocksNeeded = 2

    /// What to change when the blocks won't fit the week, or nil when they do.
    /// `open` is the week's open parts when something else knows them: the hub's rhythm, which the
    /// settings and commitments alone can't see.
    public static func warning(_ settings: MindSettings, week: WeekSettings, commitments: WeekCommitments, open known: Int? = nil) -> String? {
        let blocks = week.total(settings.domains)
        let open = known ?? WeekPlanner.openPartCount(settings: week, commitments: commitments)
        if blocks > open {
            return "\(blocks) blocks and \(open) open parts of the week. Open a part, or drop a block."
        }
        let thin = settings.languages.filter { (1..<languageBlocksNeeded).contains(week.blocks($0)) }
        if let language = thin.first {
            return "\(language.label) on one block a week will move slowly. Two or more keeps it going."
        }
        return nil
    }
}
