import Foundation
import SystemCore

/// Mind Track's own settings. One record. Decoding fills anything missing with its default, so a
/// field added later never breaks a record saved before it, and keeps values it doesn't know (a
/// course or genre from a newer version on another device) aside and writes them back unchanged.
public struct MindSettings: Hashable, Codable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000317D")!
    /// Heavy Main courses (languages and maths) past this spread the week too thin.
    public static let focusCap = 3

    public var id: UUID
    /// Every active course and how hard it's pushed. Courses not here are off.
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
    /// Lagging courses get more sessions. Off keeps the split even.
    public var autoPrioritise: Bool
    /// Reminders at the usual study time when the day's session hasn't happened.
    public var reminders: Bool
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
        autoPrioritise: Bool = true, reminders: Bool = false, updatedAt: Date = Date(), earlierSchedules: [EarlierSchedule] = []
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
        self.updatedAt = updatedAt
    }

    /// Every active course, in order.
    public var domains: [Domain] { courses.keys.sorted() }
    /// Main courses: the ones with days of their own.
    public var focus: [Domain] { domains.filter { courses[$0] == .focus } }
    public var secondary: [Domain] { domains.filter { courses[$0] == .secondary } }
    public var maintenance: [Domain] { domains.filter { courses[$0] == .maintenance } }
    /// Main and Secondary: the courses that learn new material.
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
            speaking, allowCloudAI, autoPrioritise, reminders, updatedAt
    }

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
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// How much the chosen courses ask of the week, against the time there is. Languages need
/// near-daily exposure, so each extra Main course dilutes the others.
public enum CourseLoad {
    /// Sessions a week a Main course needs to move: two for a language (its reviews come up in
    /// every warm-up as well), one for the rest. Writing rides along in a maths session when both
    /// are Main.
    public static func sessionsNeeded(_ domain: Domain) -> Int { domain.isLanguage ? 2 : 1 }

    /// The heavy courses the cap counts: languages and maths. Writing pairs with maths and reading
    /// happens off the clock too.
    public static func heavy(_ domain: Domain) -> Bool { domain.isLanguage || domain == .maths }

    /// Minutes of reviews a Maintenance course takes in each session's warm-up.
    public static let maintenanceMinutes = 4

    /// A Secondary block's share of the time a session has after its warm-up, and its least: about
    /// seven minutes of a 25-minute session.
    public static let secondaryShare = 0.3
    public static let secondaryMinimum = 5

    /// A Secondary block's minutes, from the minutes a session has once its warm-up is done.
    public static func secondaryMinutes(_ remaining: Int) -> Int {
        max(secondaryMinimum, Int((Double(remaining) * secondaryShare).rounded()))
    }
    /// Blocks a week a Secondary course needs to keep moving. Every study day has one block, and
    /// the Secondary courses take turns at it.
    public static let secondaryBlocksNeeded = 2

    public struct Check: Hashable, Sendable {
        public var sessionsNeeded: Int
        public var sessionsAvailable: Int
        public var focusCount: Int
        /// What to change, when the load doesn't fit. Nil when it does.
        public var warning: String?
    }

    public static func check(_ settings: MindSettings) -> Check {
        let focus = settings.focus
        var needed = focus.map(sessionsNeeded).reduce(0, +)
        if focus.contains(.maths) && focus.contains(.writing) { needed -= 1 }
        let heavyCount = focus.filter(heavy).count
        let available = settings.schedule.daysPerWeek
        let secondary = settings.secondary.count
        let reviewShare = settings.maintenance.count * maintenanceMinutes
        var warning: String?
        if heavyCount > MindSettings.focusCap {
            warning = "\(heavyCount) heavy Main courses is more than three. Each one dilutes the others: make one Secondary."
        } else if needed > available {
            warning = "These Main courses want about \(needed) sessions a week and there are \(available). Add a day, or make one Secondary."
        } else if secondary > 0 && available < secondaryBlocksNeeded * secondary {
            let each = (Double(available) / Double(secondary)).formatted(.number.precision(.fractionLength(0...1)))
            warning =
                "\(secondary) Secondary courses take turns at one short block a session, so each comes up about \(each) times a week. Add a day, or move one to Maintenance."
        } else if reviewShare > settings.schedule.minutes / 2 {
            warning = "Maintenance reviews would take most of each session. Keep fewer courses on Maintenance, or make sessions longer."
        }
        return Check(sessionsNeeded: needed, sessionsAvailable: available, focusCount: focus.count, warning: warning)
    }
}
