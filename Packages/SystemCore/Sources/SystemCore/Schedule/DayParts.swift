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
