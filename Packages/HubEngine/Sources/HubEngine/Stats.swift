import Foundation
import SystemCore
import SystemStore

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

public enum StatsBoard {
    /// The stats the hub shows: the ones Stadig Lift and Stadig Macro score. `StatKind` still has
    /// Intelligence and Wisdom, so what Stadig Mind published goes on decoding, but they aren't shown.
    public static let shown: [StatKind] = [.strength, .physique, .endurance, .vitality, .agility, .discipline]

    /// The app that speaks for a stat before any has published it.
    static func owner(_ stat: StatKind) -> AppID { stat == .vitality ? .macroTrack : .liftTrack }

    static func summaries(_ inputs: HubInputs) -> [AppSummary] {
        fresh(lift: inputs.lift, macro: inputs.macro, today: inputs.today, timeZone: inputs.timeZone)
    }

    /// Published data older than `HubPlanner.staleDays` says nothing about now: the app may be gone.
    /// Only the two fitness apps count, whatever is handed in.
    static func fresh(lift: AppSummary?, macro: AppSummary?, today: Day, timeZone: TimeZone) -> [AppSummary] {
        [lift, macro].compactMap(\.self)
            .filter {
                ($0.app == .liftTrack || $0.app == .macroTrack) && Day($0.updated, timeZone: timeZone).days(until: today) <= HubPlanner.staleDays
            }
    }

    /// Every stat shown, in the same order every time, including the ones nothing has published yet.
    public static func lines(_ inputs: HubInputs) -> [StatLine] {
        lines(lift: inputs.lift, macro: inputs.macro, today: inputs.today, timeZone: inputs.timeZone)
    }

    /// The fitness stats as either app shows them: its own, and the other app's once that one is set
    /// up too, each saying which app it comes from (`StatLine.apps`, with each app's own number in
    /// `sources`). Read from what both publish to the shared container, so Stadig Lift and Stadig
    /// Macro give the same answer on every device.
    public static func lines(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> [StatLine] {
        lines(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), today: today, timeZone: timeZone)
    }

    /// The same from summaries in hand: an app passes its own, fresh, and what it read of the other's.
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

    /// "Training 84%, nutrition 92%".
    static func joined(_ labels: [String]) -> String {
        labels.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).lowercased() + $0.element.dropFirst() }.joined(separator: ", ")
    }

    /// The trend of a stat two apps share: the one that needs attention, among those that know.
    static func worst(_ trends: [Trajectory]) -> Trajectory {
        [Trajectory.regressing, .stalled, .onPace, .ahead].first(where: trends.contains) ?? .notEnoughData
    }

    /// When any app last published.
    public static func updated(_ inputs: HubInputs) -> Date? { summaries(inputs).map(\.updated).max() }

    /// Whether both apps are publishing: the point at which each shows all the stats, not only its own.
    public static func bothApps(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> Bool {
        fresh(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), today: today, timeZone: timeZone).count == 2
    }
}

extension HubText {
    /// "Updated today", "Updated yesterday", "Updated 3 days ago".
    public static func updated(_ date: Date?, today: Day) -> String {
        guard let date else { return "Nothing from your apps yet" }
        let days = Day(date).days(until: today)
        switch days {
        case ...0: return "Updated today"
        case 1: return "Updated yesterday"
        default: return "Updated \(days) days ago"
        }
    }
}
