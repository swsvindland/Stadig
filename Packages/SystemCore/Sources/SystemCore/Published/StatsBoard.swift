import Foundation

/// One of the fitness stats, put together from every app that publishes it. There's no overall level:
/// they sit side by side.
public struct StatLine: Hashable, Sendable, Identifiable {
    /// What one app says about it.
    public struct Source: Hashable, Sendable, Identifiable {
        public var app: AppID
        public var label: String
        public var score: Int?

        public var id: AppID { app }
    }

    public var stat: StatKind
    /// 0 to 100, or nil with nothing to go on.
    public var score: Int?
    public var label: String
    public var trend: Trajectory
    public var sources: [Source]
    /// The app it's coloured by: the first that publishes it, or the one that would.
    public var app: AppID

    public var id: StatKind { stat }
    public var isKnown: Bool { !sources.isEmpty }
    /// The apps it comes from: Stadig Lift, Stadig Macro or both, in that order. Empty until one has
    /// published it, when `app` says which would.
    public var apps: [AppID] { sources.map(\.app) }
}

/// The stats as both apps show them: each app's own, and the other's once that one is set up too,
/// merged the same way in both so they give the same numbers. Reading them from the shared container
/// is `SystemStore`'s `StatsBoard.lines(shared:today:timeZone:)`.
public enum StatsBoard {
    /// The stats shown: the ones Stadig Lift and Stadig Macro score. `StatKind` still has Intelligence
    /// and Wisdom, so what Stadig Mind published goes on decoding, but they aren't shown.
    public static let shown: [StatKind] = [.strength, .physique, .endurance, .vitality, .agility, .discipline]
    /// A summary older than this says nothing about now: the app may be gone.
    public static let staleDays = 28

    /// The app that speaks for a stat before any has published it.
    static func owner(_ stat: StatKind) -> AppID { stat == .vitality ? .macroTrack : .liftTrack }

    /// The summaries that count: Stadig Lift's and Stadig Macro's, whatever is handed in, and only
    /// while they're fresh.
    static func fresh(lift: AppSummary?, macro: AppSummary?, today: Day, timeZone: TimeZone) -> [AppSummary] {
        [lift, macro].compactMap(\.self)
            .filter {
                ($0.app == .liftTrack || $0.app == .macroTrack) && Day($0.updated, timeZone: timeZone).days(until: today) <= staleDays
            }
    }

    /// Every stat shown, in the same order every time, including the ones nothing has published yet,
    /// from summaries in hand: an app passes its own, fresh, and what it read of the other's.
    public static func lines(lift: AppSummary?, macro: AppSummary?, today: Day, timeZone: TimeZone = .current) -> [StatLine] {
        let summaries = fresh(lift: lift, macro: macro, today: today, timeZone: timeZone)
        return shown.map { stat in
            let readings = summaries.flatMap { summary in summary.stats.filter { $0.stat == stat }.map { (app: summary.app, reading: $0) } }
            guard let first = readings.first else {
                let owner = owner(stat)
                return StatLine(
                    stat: stat, score: nil, label: "Nothing from \(owner.displayName) yet", trend: .notEnoughData, sources: [], app: owner)
            }
            let scores = readings.compactMap(\.reading.score)
            let score = scores.isEmpty ? nil : Int((scores.reduce(0, +) / Double(scores.count)).rounded())
            return StatLine(
                stat: stat, score: score.map { min(100, max(0, $0)) }, label: joined(readings.map(\.reading.label)),
                trend: worst(readings.map(\.reading.trend)),
                sources: readings.map { StatLine.Source(app: $0.app, label: $0.reading.label, score: $0.reading.score.map { Int($0.rounded()) }) },
                app: first.app)
        }
    }

    /// Whether both apps are publishing: the point at which each shows all the stats, not only its own.
    public static func bothApps(lift: AppSummary?, macro: AppSummary?, today: Day, timeZone: TimeZone = .current) -> Bool {
        fresh(lift: lift, macro: macro, today: today, timeZone: timeZone).count == 2
    }

    /// "Training 84%, nutrition 92%".
    static func joined(_ labels: [String]) -> String {
        labels.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).lowercased() + $0.element.dropFirst() }.joined(separator: ", ")
    }

    /// The trend of a stat two apps share: the one that needs attention, among those that know.
    static func worst(_ trends: [Trajectory]) -> Trajectory {
        [Trajectory.regressing, .stalled, .onPace, .ahead].first(where: trends.contains) ?? .notEnoughData
    }
}
