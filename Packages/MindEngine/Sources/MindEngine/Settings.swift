import Foundation
import SystemCore

/// Mind Track's own settings. One record. Decoding fills anything missing with its default, so a
/// field added later never breaks a record saved before it.
public struct MindSettings: Hashable, Codable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000317D")!
    /// Heavy Focus courses (languages and maths) past this spread the week too thin.
    public static let focusCap = 3

    public var id: UUID
    /// Every active course and how hard it's pushed. Courses not here are off.
    public var courses: [Domain: CourseMode]
    public var schedule: StudySchedule
    public var onboardedAt: Date?
    /// Nil until asked. False starts Japanese with hiragana and katakana.
    public var readsKana: Bool?
    /// The classic ladder's placement start, until the adaptive per-strand placement replaces it.
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

    public init(courses: [Domain: CourseMode] = [.japanese: .focus, .maths: .focus, .writing: .focus, .reading: .focus],
                schedule: StudySchedule = StudySchedule(), onboardedAt: Date? = nil, readsKana: Bool? = nil,
                mathsBackground: MathsBackground = .algebra, mathsStrands: [MathsStrand] = MathsStrand.allCases,
                writingKinds: [WritingKind] = [.creative], genres: [Genre] = [], speaking: Bool = true, allowCloudAI: Bool = true,
                autoPrioritise: Bool = true, reminders: Bool = false, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.courses = courses
        self.schedule = schedule
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
    public var focus: [Domain] { domains.filter { courses[$0] == .focus } }
    public var maintenance: [Domain] { domains.filter { courses[$0] == .maintenance } }
    public var languages: [Domain] { domains.filter(\.isLanguage) }

    public func has(_ domain: Domain) -> Bool { courses[domain] != nil }
    public func mode(_ domain: Domain) -> CourseMode? { courses[domain] }

    enum CodingKeys: String, CodingKey {
        case id, courses, domains, schedule, onboardedAt, readsKana, mathsBackground, mathsStrands, writingKinds, genres, speaking,
             allowCloudAI, autoPrioritise, reminders, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? Self.singletonID
        if let courses = try c.decodeIfPresent([Domain: CourseMode].self, forKey: .courses) {
            self.courses = courses
        } else {
            // Version 1 kept a plain list of subjects: every one was a full course.
            let old = try c.decodeIfPresent([Domain].self, forKey: .domains) ?? [.japanese, .maths, .writing, .reading]
            courses = Dictionary(uniqueKeysWithValues: old.map { ($0, .focus) })
        }
        schedule = try c.decodeIfPresent(StudySchedule.self, forKey: .schedule) ?? StudySchedule()
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
        readsKana = try c.decodeIfPresent(Bool.self, forKey: .readsKana)
        mathsBackground = try c.decodeIfPresent(MathsBackground.self, forKey: .mathsBackground) ?? .algebra
        mathsStrands = try c.decodeIfPresent([MathsStrand].self, forKey: .mathsStrands) ?? MathsStrand.allCases
        writingKinds = try c.decodeIfPresent([WritingKind].self, forKey: .writingKinds) ?? [.creative]
        genres = try c.decodeIfPresent([Genre].self, forKey: .genres) ?? []
        speaking = try c.decodeIfPresent(Bool.self, forKey: .speaking) ?? true
        allowCloudAI = try c.decodeIfPresent(Bool.self, forKey: .allowCloudAI) ?? true
        autoPrioritise = try c.decodeIfPresent(Bool.self, forKey: .autoPrioritise) ?? true
        reminders = try c.decodeIfPresent(Bool.self, forKey: .reminders) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(courses, forKey: .courses)
        try c.encode(schedule, forKey: .schedule)
        try c.encodeIfPresent(onboardedAt, forKey: .onboardedAt)
        try c.encodeIfPresent(readsKana, forKey: .readsKana)
        try c.encode(mathsBackground, forKey: .mathsBackground)
        try c.encode(mathsStrands, forKey: .mathsStrands)
        try c.encode(writingKinds, forKey: .writingKinds)
        try c.encode(genres, forKey: .genres)
        try c.encode(speaking, forKey: .speaking)
        try c.encode(allowCloudAI, forKey: .allowCloudAI)
        try c.encode(autoPrioritise, forKey: .autoPrioritise)
        try c.encode(reminders, forKey: .reminders)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// How much the chosen courses ask of the week, against the time there is. Languages need
/// near-daily exposure, so each extra Focus course dilutes the others.
public enum CourseLoad {
    /// Sessions a week a Focus course needs to move: two for a language (its reviews come up in
    /// every warm-up as well), one for the rest. Writing rides along in a maths session when both
    /// are Focus.
    public static func sessionsNeeded(_ domain: Domain) -> Int { domain.isLanguage ? 2 : 1 }

    /// The heavy courses the cap counts: languages and maths. Writing pairs with maths and reading
    /// happens off the clock too.
    public static func heavy(_ domain: Domain) -> Bool { domain.isLanguage || domain == .maths }

    /// Minutes of reviews a Maintenance course takes in each session's warm-up.
    public static let maintenanceMinutes = 4

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
        let reviewShare = settings.maintenance.count * maintenanceMinutes
        var warning: String?
        if heavyCount > MindSettings.focusCap {
            warning = "\(heavyCount) heavy Focus courses is more than three. Each one dilutes the others: move one to Maintenance."
        } else if needed > available {
            warning = "These Focus courses want about \(needed) sessions a week and there are \(available). Add a day, or move one to Maintenance."
        } else if reviewShare > settings.schedule.minutes / 2 {
            warning = "Maintenance reviews would take most of each session. Keep fewer courses on Maintenance, or make sessions longer."
        }
        return Check(sessionsNeeded: needed, sessionsAvailable: available, focusCount: focus.count, warning: warning)
    }
}
