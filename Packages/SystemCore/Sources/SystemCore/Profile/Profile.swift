import Foundation

/// The apps in the System. Each owns its own data and publishes summaries for the others.
public enum AppID: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case liftTrack, macroTrack, knowledge, hub

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .liftTrack: "Lift Track"
        case .macroTrack: "Macro Track"
        // The design doc's "Knowledge" app; people know it as Mind Track.
        case .knowledge: "Mind Track"
        case .hub: "The System"
        }
    }
}

/// What the person wants, stated as outcomes. They never pick a cut or a bulk, or a program; the
/// apps choose from the data.
public enum OutcomeGoal: String, CaseIterable, Codable, Sendable, Identifiable {
    case leaner, biggerAndStronger, stronger, fitter, moreMobile, healthier

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .leaner: "Leaner"
        case .biggerAndStronger: "Bigger and stronger"
        case .stronger: "Stronger"
        case .fitter: "Fitter"
        case .moreMobile: "More mobile"
        case .healthier: "Healthier overall"
        }
    }

    public var detail: String {
        switch self {
        case .leaner: "Lose fat, keep the muscle. Visible abs."
        case .biggerAndStronger: "Build muscle and strength together."
        case .stronger: "Lift more on the big lifts."
        case .fitter: "Better engine for sport, class and life."
        case .moreMobile: "Move freely; fix what's tight."
        case .healthier: "Feel good, sleep well, keep it sustainable."
        }
    }

    public var symbol: String {
        switch self {
        case .leaner: "figure.core.training"
        case .biggerAndStronger: "figure.strengthtraining.traditional"
        case .stronger: "scalemass.fill"
        case .fitter: "heart.circle.fill"
        case .moreMobile: "figure.flexibility"
        case .healthier: "leaf.fill"
        }
    }

    /// How much each goal pulls a session's time toward each kind of work.
    public var emphasis: GoalEmphasis {
        switch self {
        case .leaner: GoalEmphasis(strength: 0.8, hypertrophy: 1, conditioning: 0.9, mobility: 0.4)
        case .biggerAndStronger: GoalEmphasis(strength: 1, hypertrophy: 1, conditioning: 0.3, mobility: 0.3)
        case .stronger: GoalEmphasis(strength: 1.2, hypertrophy: 0.6, conditioning: 0.2, mobility: 0.3)
        case .fitter: GoalEmphasis(strength: 0.6, hypertrophy: 0.4, conditioning: 1.2, mobility: 0.5)
        case .moreMobile: GoalEmphasis(strength: 0.5, hypertrophy: 0.4, conditioning: 0.4, mobility: 1.2)
        case .healthier: GoalEmphasis(strength: 0.7, hypertrophy: 0.6, conditioning: 0.8, mobility: 0.7)
        }
    }
}

public struct GoalEmphasis: Hashable, Codable, Sendable {
    public var strength: Double
    public var hypertrophy: Double
    public var conditioning: Double
    public var mobility: Double

    public init(strength: Double, hypertrophy: Double, conditioning: Double, mobility: Double) {
        self.strength = strength
        self.hypertrophy = hypertrophy
        self.conditioning = conditioning
        self.mobility = mobility
    }

    public static func combined(_ goals: [OutcomeGoal]) -> GoalEmphasis {
        let list = goals.isEmpty ? [.healthier] : goals
        let n = Double(list.count)
        return GoalEmphasis(
            strength: list.map(\.emphasis.strength).reduce(0, +) / n,
            hypertrophy: list.map(\.emphasis.hypertrophy).reduce(0, +) / n,
            conditioning: list.map(\.emphasis.conditioning).reduce(0, +) / n,
            mobility: list.map(\.emphasis.mobility).reduce(0, +) / n)
    }
}

public enum TrainingExperience: String, CaseIterable, Codable, Sendable, Identifiable {
    case novice, intermediate, experienced

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .novice: "Under a year"
        case .intermediate: "1–3 years"
        case .experienced: "3+ years"
        }
    }

    /// How far self-reported effort is believed before any evidence. Beginners tend to
    /// underestimate how many reps they have left.
    public var startingTrust: Double {
        switch self {
        case .novice: 0.3
        case .intermediate: 0.5
        case .experienced: 0.7
        }
    }

    /// Lift Track's solo assessment, in weeks. Experienced lifters can stop early once their
    /// ratings have proven accurate.
    public var assessmentWeeks: Int {
        switch self {
        case .novice, .intermediate: 4
        case .experienced: 3
        }
    }
}

public enum BiologicalSex: String, CaseIterable, Codable, Sendable, Identifiable {
    case male, female, unspecified

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .unspecified: "Prefer not to say"
        }
    }
}

public struct TrainingSchedule: Hashable, Codable, Sendable {
    public var daysPerWeek: Int
    public var minutesPerSession: Int
    /// Days the person would rather train. Empty means any.
    public var preferredDays: [Weekday]

    public init(daysPerWeek: Int = 3, minutesPerSession: Int = 60, preferredDays: [Weekday] = []) {
        self.daysPerWeek = clamp(daysPerWeek, 1, 7)
        self.minutesPerSession = clamp(minutesPerSession, 20, 150)
        self.preferredDays = preferredDays
    }

    /// The training days of a week: the preferred ones, else spread evenly from Monday.
    public var trainingDays: [Weekday] {
        if preferredDays.count == daysPerWeek { return preferredDays.sorted() }
        let spreads: [Int: [Weekday]] = [
            1: [.wednesday], 2: [.monday, .thursday], 3: [.monday, .wednesday, .friday],
            4: [.monday, .tuesday, .thursday, .friday], 5: [.monday, .tuesday, .wednesday, .friday, .saturday],
            6: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday], 7: Weekday.allCases,
        ]
        return spreads[daysPerWeek] ?? [.monday, .wednesday, .friday]
    }
}

public enum TimeOfDay: String, CaseIterable, Codable, Sendable {
    case morning, midday, evening

    public var label: String {
        switch self {
        case .morning: "Morning"
        case .midday: "Midday"
        case .evening: "Evening"
        }
    }
}

/// Training the person does outside the app on a schedule: "BJJ Tue/Thu evenings".
public struct RecurringActivity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var activity: ActivityType
    public var weekdays: [Weekday]
    public var minutes: Int
    /// 1–10.
    public var intensity: Int
    public var timeOfDay: TimeOfDay

    public init(
        id: UUID = UUID(), activity: ActivityType, weekdays: [Weekday], minutes: Int = 60,
        intensity: Int? = nil, timeOfDay: TimeOfDay = .evening
    ) {
        self.id = id
        self.activity = activity
        self.weekdays = weekdays.sorted()
        self.minutes = minutes
        self.intensity = clamp(intensity ?? activity.typicalIntensity, 1, 10)
        self.timeOfDay = timeOfDay
    }

    public var summary: String {
        "\(activity.label) · \(weekdays.map(\.short).joined(separator: "/")) \(timeOfDay.label.lowercased())s"
    }
}

/// Setup answers, asked once and shared through the core. A second app reads these instead of
/// asking again.
public struct SharedProfile: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var goals: [OutcomeGoal]
    public var schedule: TrainingSchedule
    public var equipment: EquipmentAccess
    public var experience: TrainingExperience
    public var recurring: [RecurringActivity]
    public var sex: BiologicalSex
    public var birthYear: Int?
    public var heightCm: Double?
    public var units: UnitPreference
    public var createdBy: AppID
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        goals: [OutcomeGoal] = [], schedule: TrainingSchedule = TrainingSchedule(), equipment: EquipmentAccess = .fullGym,
        experience: TrainingExperience = .novice, recurring: [RecurringActivity] = [], sex: BiologicalSex = .unspecified,
        birthYear: Int? = nil, heightCm: Double? = nil, units: UnitPreference = .regional, createdBy: AppID,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.goals = goals
        self.schedule = schedule
        self.equipment = equipment
        self.experience = experience
        self.recurring = recurring
        self.sex = sex
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.units = units
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Birth years that make someone 10 to 100 on the day. Anything else is a typo or bad stored
    /// data (0, 19990, next year), and an age made from it would set heart-rate zones, the step
    /// floor and the energy formula from nonsense.
    public static func plausibleBirthYears(on day: Day) -> ClosedRange<Int> { (day.year - 100)...(day.year - 10) }

    /// Nil without a birth year, or with one outside `plausibleBirthYears`, so every use falls back
    /// to its default age.
    public func age(on day: Day = .today) -> Int? {
        guard let birthYear, Self.plausibleBirthYears(on: day).contains(birthYear) else { return nil }
        return day.year - birthYear
    }

    /// Declared outside training on a day.
    public func declared(on day: Day) -> [RecurringActivity] { recurring.filter { $0.weekdays.contains(day.weekday) } }
}
