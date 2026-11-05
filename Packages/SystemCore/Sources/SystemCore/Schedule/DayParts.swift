import Foundation

/// The six parts of a day. Plans go by part rather than by the clock: a plan that says "this
/// evening" survives a day running late, and leisure with a clock time on it starts to feel like
/// work (Tonietto and Malkoc, 2016), which "sometime this evening" doesn't.
public enum DayPart: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case early, morning, midday, afternoon, evening, night

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .early: "Early"
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    /// The part an hour on the clock falls in. The small hours are the night before's, as a study
    /// day's are.
    public init(hour: Int) {
        switch hour {
        case 4..<8: self = .early
        case 8..<11: self = .morning
        case 11..<14: self = .midday
        case 14..<17: self = .afternoon
        case 17..<20: self = .evening
        default: self = .night
        }
    }

    /// Where the part falls on a day's timeline, in minutes from that day's midnight. A day runs 4 a.m.
    /// to 4 a.m., so the night goes past 1440, as a span running into the next day does.
    public var minutes: Range<Int> {
        switch self {
        case .early: 240..<480
        case .morning: 480..<660
        case .midday: 660..<840
        case .afternoon: 840..<1020
        case .evening: 1020..<1200
        case .night: 1200..<1680
        }
    }

    public init(_ time: TimeOfDay) {
        switch time {
        case .morning: self = .morning
        case .midday: self = .midday
        case .evening: self = .evening
        }
    }

    /// The rougher word published payloads use.
    public var timeOfDay: TimeOfDay {
        switch self {
        case .early, .morning: .morning
        case .midday, .afternoon: .midday
        case .evening, .night: .evening
        }
    }

    public static func < (a: DayPart, b: DayPart) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

/// Something a day already holds: a lift, a class.
public struct Commitment: Hashable, Sendable {
    public var title: String
    public var part: DayPart
    public var minutes: Int
    /// An SF Symbol for it.
    public var symbol: String

    public init(title: String, part: DayPart, minutes: Int, symbol: String = "figure.strengthtraining.traditional") {
        self.title = title
        self.part = part
        self.minutes = minutes
        self.symbol = symbol
    }
}

/// What the person's week already holds, by weekday: the training days and classes they set up in
/// Stadig Lift.
public struct WeekCommitments: Hashable, Sendable {
    public static let none = WeekCommitments()
    /// A lift, as a commitment's title.
    public static let liftTitle = "Lift"
    /// How many recent lifts say when this person trains.
    static let recentLifts = 8

    private var days: [Weekday: [Commitment]]

    public init(days: [Weekday: [Commitment]] = [:]) { self.days = days }

    /// From the shared profile and what Stadig Lift published. Lifts count only once Stadig Lift has
    /// published: Stadig Macro can write the profile first, with the default three training days,
    /// and nobody set those. Classes are the person's own either way.
    ///
    /// A lift's part comes from when they've actually been trained, using days before `today` so
    /// tonight's session can't move the plan under the person mid-day. With no history a lift is
    /// taken to be in the evening, where classes default to.
    public init(profile: SharedProfile?, lift: AppSummary?, before today: Day, timeZone: TimeZone = .current) {
        var days: [Weekday: [Commitment]] = [:]
        guard let profile else {
            self.days = days
            return
        }
        if let lift {
            let part = Self.liftingPart(lift.sessions, before: today, timeZone: timeZone) ?? .evening
            for weekday in profile.schedule.trainingDays {
                days[weekday, default: []].append(Commitment(title: Self.liftTitle, part: part, minutes: profile.schedule.minutesPerSession))
            }
        }
        for activity in profile.recurring {
            for weekday in activity.weekdays {
                days[weekday, default: []].append(
                    Commitment(
                        title: activity.activity.label, part: DayPart(activity.timeOfDay), minutes: activity.minutes, symbol: activity.activity.symbol
                    ))
            }
        }
        self.days = days.mapValues { list in list.sorted { ($0.part, $0.title) < ($1.part, $1.title) } }
    }

    public func on(_ weekday: Weekday) -> [Commitment] { days[weekday] ?? [] }

    /// A date's commitments, with anything moved for just that day where it went.
    public func on(_ day: Day, changes: [DayChange]) -> [Commitment] {
        on(day.weekday).map { commitment in
            var commitment = commitment
            commitment.part = changes.movedPart(of: commitment.title, on: day) ?? commitment.part
            return commitment
        }
    }

    /// The same week with whatever the rhythm moved for good where it went. A placement for a class
    /// that's gone from that day simply finds nothing.
    public func placed(by rhythm: Rhythm?) -> WeekCommitments {
        guard let rhythm, !rhythm.placements.isEmpty else { return self }
        var moved = self
        for (weekday, list) in days {
            moved.days[weekday] = list.map { commitment in
                var commitment = commitment
                commitment.part = rhythm.placedPart(of: commitment.title, on: weekday) ?? commitment.part
                return commitment
            }.sorted { ($0.part, $0.title) < ($1.part, $1.title) }
        }
        return moved
    }

    /// The part of the day lifts usually start in: the median of the last few, by the clock.
    static func liftingPart(_ sessions: [SessionSummary], before today: Day, timeZone: TimeZone) -> DayPart? {
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = timeZone
        let recent = sessions.filter { $0.kind == .strength && Day($0.start, timeZone: timeZone) < today }.sorted { $0.start < $1.start }
        let minutes = recent.suffix(recentLifts).map { session -> Int in
            let parts = clock.dateComponents([.hour, .minute], from: session.start)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        return DayPart(hour: minutes[minutes.count / 2] / 60)
    }
}

extension SharedProfile {
    /// What Stadig Lift should leave in the shared file: the file as it stands, with Stadig Lift's
    /// training days and classes. Stadig Lift owns those two and edits them nowhere else, and other
    /// apps plan around them, so a copy another app or a freshly set-up device wrote mustn't stand.
    /// Nil when the file already has them, or when it's newer and came from Stadig Lift itself: an
    /// edit on another device, whose profile record is still on its way here.
    public func sharing(over file: SharedProfile?, writtenBy: @autoclosure () -> AppID?, now: Date) -> SharedProfile? {
        guard var file else { return self }
        guard file.schedule != schedule || file.recurring != recurring else { return nil }
        if file.updatedAt > updatedAt, writtenBy() == .liftTrack { return nil }
        file.schedule = schedule
        file.recurring = recurring
        file.updatedAt = now
        return file
    }
}
