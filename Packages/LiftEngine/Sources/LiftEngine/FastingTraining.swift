import Foundation
import SystemCore

// Lifting on a long fast. Macro Track publishes a fast while one runs. A strength session a day or
// more into one starts with the liver's glycogen spent and muscle's low, so heavy sets feel harder,
// and there's no protein around it to recover with. Today says so before the session, while
// there's time to eat or go lighter. A deload's lighter sessions are left alone.

public enum FastingTraining {
    /// Hours into a fast from which a heavy session gets a word.
    public static let hours = 24.0
    /// How many recent sessions say when this person usually starts.
    static let recentSessions = 8

    /// When this person usually starts a session on `day`: the median time of day of their last
    /// few, by the clock where they were; nil before the first.
    public static func usualStart(on day: Day, sessions: [SessionRecord], calendar: Calendar = .current) -> Date? {
        let recent = sessions.sorted { $0.start < $1.start }.suffix(recentSessions)
        let minutes = recent.map { session -> Int in
            var clock = Calendar(identifier: .gregorian)
            clock.timeZone = session.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
            let parts = clock.dateComponents([.hour, .minute], from: session.start)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        return day.at(minutes: minutes[minutes.count / 2], calendar: calendar)
    }

    /// The word for today, when a strength session is planned and not done yet, outside a deload, and
    /// the person is a day or more into a fast now, or will be by their usual start with the fast's
    /// goal still running then.
    public static func note(
        fast: PublishedFast?, next: NextSession?, deload: Bool, trainedToday: Bool, usualStart: Date?, now: Date
    ) -> NextAction? {
        guard let fast, let next, next.scheduledToday, !next.day.strengthSlots.isEmpty, !deload, !trainedToday else { return nil }
        let nowHours = fast.hours(at: now)
        let session = max(now, usualStart ?? now)
        let sessionHours = fast.hours(at: session)
        let byThen = session > now && session < fast.goalEnd && sessionHours >= hours
        guard nowHours >= hours || byThen else { return nil }
        let into =
            nowHours >= hours
            ? "You're \(Int(nowHours)) hours into a fast" : "You'll be about \(Int(sessionHours)) hours into a fast by your usual start"
        return NextAction(
            id: "fasting-\(Int(fast.start.timeIntervalSince1970))", kind: .fasting, stat: .vitality, title: "Lifting on a long fast",
            detail:
                "\(into) (Macro Track). Glycogen is low by now, so heavy sets feel harder, and there's no protein around the session to recover with.",
            action: "Eat a meal with protein an hour or two before, or keep today light: the same lifts, fewer sets.", priority: 8)
    }
}
