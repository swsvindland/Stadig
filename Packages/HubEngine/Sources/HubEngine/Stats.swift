import Foundation
import SystemCore

/// One of the eight stats, put together from every app that publishes it. There's no overall level:
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
}

public enum StatsBoard {
    /// The app that speaks for a stat before any has published it.
    static func owner(_ stat: StatKind) -> AppID {
        switch stat {
        case .strength, .physique, .endurance, .agility, .discipline: .liftTrack
        case .vitality: .macroTrack
        case .intelligence, .wisdom: .knowledge
        }
    }

    static func summaries(_ inputs: HubInputs) -> [AppSummary] {
        [inputs.lift, inputs.macro, inputs.mind].compactMap(\.self).filter { HubPlanner.fresh($0.updated, inputs) }
    }

    /// Every stat, in the same order every time, including the ones nothing has published yet.
    public static func lines(_ inputs: HubInputs) -> [StatLine] {
        let summaries = summaries(inputs)
        return StatKind.allCases.map { stat in
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
