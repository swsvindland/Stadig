import Foundation

/// A stat's score on one day: the last the app published that day.
public struct ScorePoint: Hashable, Codable, Sendable {
    public var day: Day
    /// 0 to 100, to a tenth.
    public var score: Double

    public init(day: Day, score: Double) {
        self.day = day
        self.score = score
    }
}

/// The scores one app has published, day by day, so both apps can say how each has moved: "+2 this
/// month", "+3 since August". Each app keeps its own in the shared container beside its summary (in
/// SystemStore, `SharedKey.scores` and `SharedContainer.recordScores`) and adds the day's readings
/// whenever it publishes its stats, so the other app and the person's other devices have it too.
///
/// One reading a day for each stat, the day's last. Every reading of the last nine weeks is kept;
/// older ones only as each week's and each month's last, which is all a change is ever measured
/// from back there, and the first, which one is measured from when the readings began inside its
/// window; after two years, none.
public struct ScoreHistory: Hashable, Codable, Sendable {
    /// A file of its own rather than a field of the summary: an older copy of either app rewrites the
    /// summary without it, but never touches this.
    public static let schemaVersion = 1
    /// Every reading this many days old or newer is kept: two months, so "this month" and the month
    /// before are measured from the day itself.
    public static let dailyDays = 62
    /// Older readings are kept this long, as each week's and each month's last.
    public static let horizonDays = 731

    public var app: AppID
    /// Each stat's readings, oldest first, one a day.
    public var stats: [StatKind: [ScorePoint]]

    public init(app: AppID, stats: [StatKind: [ScorePoint]] = [:]) {
        self.app = app
        self.stats = stats
    }

    public func points(_ stat: StatKind) -> [ScorePoint] { stats[stat] ?? [] }

    public var isEmpty: Bool { stats.values.allSatisfy(\.isEmpty) }

    // MARK: Recording

    /// The day's readings added, each replacing that stat's earlier reading the same day, with the
    /// scores to a tenth (finer than that is noise, and would rewrite the file for nothing), then the
    /// old thinned. A reading with no score adds nothing.
    public func recording(_ readings: [StatReading], on day: Day) -> ScoreHistory {
        var history = self
        for reading in readings {
            guard let score = reading.score, score.isFinite else { continue }
            let point = ScorePoint(day: day, score: (min(100, max(0, score)) * 10).rounded() / 10)
            history.stats[reading.stat] = Self.inserting(point, into: history.points(reading.stat))
        }
        return history.thinned(today: day)
    }

    /// `recording(_:on:)` on the day `now` falls on in the calendar's time zone: a phone carried
    /// across time zones records each reading on the day its clock showed.
    public func recording(_ readings: [StatReading], at now: Date, calendar: Calendar) -> ScoreHistory {
        recording(readings, on: Day(now, calendar: calendar))
    }

    /// This copy and another (the same app's, from another device): every day either has, and on a
    /// day both have, the other's. Days a device recorded while its copy lost the race to iCloud
    /// come back this way.
    public func merged(with other: ScoreHistory) -> ScoreHistory {
        var history = self
        for (stat, theirs) in other.stats where !theirs.isEmpty {
            var byDay = Dictionary(points(stat).map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
            for point in theirs { byDay[point.day] = point }
            history.stats[stat] = byDay.values.sorted { $0.day < $1.day }
        }
        return history
    }

    /// Readings older than `dailyDays` kept only as the first, or the last of their week or of their
    /// month, and none older than `horizonDays`. Thinning again changes nothing.
    public func thinned(today: Day) -> ScoreHistory {
        var history = self
        for (stat, points) in stats {
            let kept = points.indices.filter { index in
                let day = points[index].day
                let age = day.days(until: today)
                if age <= Self.dailyDays { return true }
                guard age <= Self.horizonDays else { return false }
                guard index > 0, index + 1 < points.count else { return true }
                let next = points[index + 1].day
                return next.startOfWeek != day.startOfWeek || next.firstOfMonth != day.firstOfMonth
            }
            history.stats[stat] = kept.isEmpty ? nil : kept.map { points[$0] }
        }
        return history
    }

    static func inserting(_ point: ScorePoint, into points: [ScorePoint]) -> [ScorePoint] {
        var points = points.filter { $0.day != point.day }
        points.insert(point, at: points.firstIndex { $0.day > point.day } ?? points.endIndex)
        return points
    }

    // MARK: Reading

    /// A reading further back than this from the start of a window says nothing about then: the app
    /// went unused between, and the score may have moved without being recorded.
    public static let gapDays = 35

    /// The score as it stood before `day` began: the last reading before it, if it's recent enough to
    /// speak for then (`gapDays`). Nil when nothing was recorded before, or not for too long.
    public static func standing(_ points: [ScorePoint], before day: Day) -> ScorePoint? {
        guard let last = points.last(where: { $0.day < day }), last.day.days(until: day) <= gapDays else { return nil }
        return last
    }
}

/// What a change in a score is measured over.
public enum ScoreWindow: Hashable, Sendable {
    /// The last month: since this date a month ago, by the calendar (from 31 March, since the end of
    /// February). "+2 this month".
    case month
    /// Since a calendar month began: "+3 since August". Any day in the month names it.
    case since(month: Day)
    /// Since a check-in, what the check-in itself changed included: "+1 since the last check-in".
    case sinceCheckIn(Day)

    /// The window's first day: the change is measured from the score as it stood before it.
    public func start(today: Day) -> Day {
        switch self {
        case .month: today.adding(months: -1).adding(days: 1)
        case .since(let month): month.firstOfMonth
        case .sinceCheckIn(let day): day
        }
    }

    /// How the change is said when it's measured from a reading on `from`. A month named is the one
    /// asked for, or a later one when nothing was recorded before it: four weeks of readings can't
    /// say what moved since August, only since they began.
    func period(from: Day, today: Day) -> ScoreChange.Period {
        switch self {
        case .month: return .thisMonth
        case .sinceCheckIn: return .sinceCheckIn
        case .since(let month):
            let start = month.firstOfMonth
            let named = from < start ? start : from.firstOfMonth
            guard named < today.firstOfMonth else { return .thisMonth }
            let monthsBack = (today.year - named.year) * 12 + today.month - named.month
            // "Since November" a year on would read as this November.
            return .since(month: named, withYear: monthsBack >= 12)
        }
    }
}

/// How far a score has moved over a window: the score now against the score as it stood before the
/// window began. Under a point either way is steady.
public struct ScoreChange: Hashable, Sendable {
    public enum Direction: Sendable { case up, steady, down }

    /// What the change is over, as it's said.
    public enum Period: Hashable, Sendable {
        /// "this month"
        case thisMonth
        /// "since August", or "since August 2025" a year or more back. The day is the month's first.
        case since(month: Day, withYear: Bool)
        /// "since the last check-in"
        case sinceCheckIn
    }

    /// Less than this, either way, is steady.
    public static let steadyBelow = 1.0
    /// Readings that begin inside a window say how it moved once the first is this many days old:
    /// a new person's second day isn't "steady this month".
    public static let minimumDays = 7

    /// Now less then, unrounded.
    public var points: Double
    /// The score it's measured from.
    public var then: Double
    /// The day of the reading it's measured from.
    public var from: Day
    public var period: Period

    public init(points: Double, then: Double, from: Day, period: Period) {
        self.points = points
        self.then = then
        self.from = from
        self.period = period
    }

    public var isSteady: Bool { abs(points) < Self.steadyBelow }

    public var direction: Direction { isSteady ? .steady : (points > 0 ? .up : .down) }

    /// Whole points, signed, rounded half away from zero; 0 when steady.
    public var whole: Int { isSteady ? 0 : Int(points.rounded()) }

    /// "+2", "−1" or "steady": a score's change beside it, as the boards have it.
    public var short: String {
        switch direction {
        case .steady: "steady"
        case .up: "+\(whole)"
        case .down: "\u{2212}\(-whole)"
        }
    }

    /// "+2 this month", "−1 since August", "Steady this month": the chip beside a score.
    public func text(calendar: Calendar) -> String {
        let period = period.words(calendar: calendar)
        return isSteady ? "Steady \(period)" : "\(short) \(period)"
    }

    /// "up 2 this month", "down 1 since August", "steady this month": for VoiceOver.
    public func spoken(calendar: Calendar) -> String {
        let period = period.words(calendar: calendar)
        switch direction {
        case .steady: return "steady \(period)"
        case .up: return "up \(whole) \(period)"
        case .down: return "down \(-whole) \(period)"
        }
    }

    // MARK: Measuring

    /// How far a score has moved over a window, from one app's dated readings (oldest first, one a
    /// day) and its score now. Measured from the score as it stood before the window began (the last
    /// reading before it, within `ScoreHistory.gapDays`); when the readings begin inside the window,
    /// from the first of them once it's `minimumDays` old. Nil with nothing to measure from: no
    /// readings, only today's, or a first a few days old.
    public static func measure(_ points: [ScorePoint], now: Double?, over window: ScoreWindow, today: Day) -> ScoreChange? {
        measure([(points, now)], over: window, today: today)
    }

    /// The same for a stat several apps publish (Discipline), whose score is their average: the
    /// average of the changes of those that have something to measure from, so an app set up this
    /// week doesn't count as the score moving.
    public static func measure(_ sources: [(points: [ScorePoint], now: Double?)], over window: ScoreWindow, today: Day) -> ScoreChange? {
        let start = window.start(today: today)
        let moves = sources.compactMap { source -> (now: Double, then: ScorePoint)? in
            guard let now = source.now, now.isFinite, let then = baseline(source.points, start: start, today: today) else { return nil }
            return (now, then)
        }
        guard let from = moves.map(\.then.day).min() else { return nil }
        let count = Double(moves.count)
        let then = moves.map(\.then.score).reduce(0, +) / count
        let now = moves.map(\.now).reduce(0, +) / count
        return ScoreChange(points: now - then, then: then, from: from, period: window.period(from: from, today: today))
    }

    /// The reading a change is measured from.
    static func baseline(_ points: [ScorePoint], start: Day, today: Day) -> ScorePoint? {
        let point =
            ScoreHistory.standing(points, before: start)
            ?? points.first { $0.day >= start && $0.day < today && $0.day.days(until: today) >= minimumDays }
        return point.flatMap { $0.day < today ? $0 : nil }
    }
}

extension ScoreChange.Period {
    /// "this month", "since August", "since the last check-in".
    public func words(calendar: Calendar) -> String {
        switch self {
        case .thisMonth: "this month"
        case .sinceCheckIn: "since the last check-in"
        case .since: "since \(monthName(calendar: calendar) ?? "")"
        }
    }

    /// "August", or "August 2025" a year or more back; nil for a period that isn't a month. In the
    /// calendar's locale (English where it has none), for the Gregorian month a `Day` always is.
    public func monthName(calendar: Calendar) -> String? {
        guard case .since(let month, let withYear) = self else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        let names = gregorian.standaloneMonthSymbols
        let name = names.indices.contains(month.month - 1) ? names[month.month - 1] : month.iso
        return withYear ? "\(name) \(month.year)" : name
    }
}
