import Foundation
import SystemCore

/// One measured metric over the pieces written, as a trend: a rolling average and which way it's
/// moving in plain words. No piece gets a number of its own.
public struct WritingTrend: Hashable, Sendable, Identifiable {
    public enum Metric: String, CaseIterable, Sendable {
        case slips, vocabulary, variety

        public var title: String {
            switch self {
            case .slips: "Slips per 100 words"
            case .vocabulary: "Range of vocabulary"
            case .variety: "Variety in sentence length"
            }
        }

        var key: String {
            switch self {
            case .slips: WritingMetrics.Key.errors
            case .vocabulary: WritingMetrics.Key.vocabulary
            case .variety: WritingMetrics.Key.sentenceSpread
            }
        }

        /// Fewer slips is the good direction; more range and more variety for the others.
        var lowerIsBetter: Bool { self == .slips }

        /// The smallest change worth calling a change.
        func moved(from earlier: Double, to recent: Double) -> Bool {
            switch self {
            case .slips: abs(recent - earlier) >= 0.4 && abs(recent - earlier) >= earlier * 0.15
            case .vocabulary: abs(recent - earlier) >= 0.02
            case .variety: abs(recent - earlier) >= max(0.5, earlier * 0.12)
            }
        }
    }

    public enum Direction: Hashable, Sendable { case better, worse, steady, notEnoughData }

    public struct Point: Hashable, Sendable {
        public var date: Date
        public var value: Double
    }

    public var metric: Metric
    /// The average of the last five pieces at each piece, oldest first.
    public var points: [Point]
    public var direction: Direction

    public var id: String { metric.rawValue }

    public var summary: String {
        switch (metric, direction) {
        case (_, .notEnoughData): "A trend shows once there are six pieces."
        case (.slips, .better): "Fewer slips than in your earlier pieces."
        case (.slips, .worse): "More slips than in your earlier pieces. A slower read before handing in catches most."
        case (.slips, .steady): "About as many as in your earlier pieces."
        case (.vocabulary, .better): "A wider range of words than in your earlier pieces."
        case (.vocabulary, .worse): "A narrower range of words than in your earlier pieces."
        case (.vocabulary, .steady): "About the same range as your earlier pieces."
        case (.variety, .better): "Sentence lengths vary more than they did."
        case (.variety, .worse): "Sentence lengths vary less than they did."
        case (.variety, .steady): "About as varied as your earlier pieces."
        }
    }
}

/// How the blind side-by-sides have gone.
public struct ComparisonRecord: Hashable, Sendable {
    public var judged: Int
    public var newerPicked: Int
    public var aiJudged: Int
    public var aiNewerPicked: Int
    /// Comparisons with both opinions where they agreed.
    public var agreed: Int
    public var bothJudged: Int
}

/// Writing's honest measures: the metrics as trends, the comparisons' record, and the score behind
/// Intelligence's writing share, which moves only on the grammar check and blind comparisons.
public enum WritingProgress {
    public static let rollingWindow = 5
    /// The direction compares this many recent pieces with as many from earlier.
    public static let trendWindow = 8
    public static let trendMinimum = 6

    /// Pieces the metrics are tracked on: the person's own prose, long enough to measure.
    public static func measured(_ pieces: [WritingPiece]) -> [WritingPiece] {
        pieces.filter { $0.exercise.composes && $0.words >= WritingSchedule.minimumWords }.sorted { $0.date < $1.date }
    }

    public static func trends(_ pieces: [WritingPiece]) -> [WritingTrend] {
        let measured = measured(pieces)
        return WritingTrend.Metric.allCases.map { metric in
            let values = measured.compactMap { piece in piece.metrics[metric.key].map { (piece.date, $0) } }
            var points: [WritingTrend.Point] = []
            for i in values.indices {
                let window = values[max(0, i - rollingWindow + 1)...i].map(\.1)
                points.append(WritingTrend.Point(date: values[i].0, value: window.reduce(0, +) / Double(window.count)))
            }
            var direction = WritingTrend.Direction.notEnoughData
            if values.count >= trendMinimum {
                // The last few pieces against those from about six weeks before them (or, early
                // on, the ones just before), so a week's ups and downs don't read as a trend.
                let size = min(trendWindow, values.count / 2)
                let recent = values.suffix(size)
                let cutoff = recent.first!.0.addingTimeInterval(-Double(WritingSchedule.pairGap) * 86_400)
                let before = values.filter { $0.0 <= cutoff }
                let earlier = before.count >= 3 ? Array(before.suffix(size)) : Array(values.dropLast(size).suffix(size))
                let (r, rSpread) = meanAndSpread(recent.map(\.1)), (e, eSpread) = meanAndSpread(earlier.map(\.1))
                // A change only counts past two standard errors: more than pieces vary on their own.
                let noise = 2 * (rSpread * rSpread / Double(recent.count) + eSpread * eSpread / Double(earlier.count)).squareRoot()
                if !metric.moved(from: e, to: r) || abs(r - e) < noise { direction = .steady }
                else { direction = (r < e) == metric.lowerIsBetter ? .better : .worse }
            }
            return WritingTrend(metric: metric, points: points, direction: direction)
        }
    }

    static func meanAndSpread(_ values: [Double]) -> (Double, Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, values.count - 1))
        return (mean, variance.squareRoot())
    }

    public static func record(_ comparisons: [BlindComparison]) -> ComparisonRecord {
        let judged = comparisons.compactMap(\.pickedNewer)
        let ai = comparisons.compactMap(\.aiPickedNewer)
        let both = comparisons.filter { $0.pickedNewer != nil && $0.aiPickedNewer != nil }
        return ComparisonRecord(judged: judged.count, newerPicked: judged.filter { $0 }.count, aiJudged: ai.count,
                                aiNewerPicked: ai.filter { $0 }.count, agreed: both.filter { $0.pickedNewer == $0.aiPickedNewer }.count,
                                bothJudged: both.count)
    }

    // MARK: The score

    /// Craft starts level, since nothing is known yet, and moves five points with each blind
    /// comparison: up when the newer piece was judged stronger, down when the older one was.
    public static let craftStart = 50.0
    public static let craftStep = 5.0

    /// A comparison's outcome: the share of its opinions (the person's, and the AI's when it gave
    /// one) that picked the newer piece. The AI is the truly blind one, since people can
    /// recognise what they wrote last week, so it counts the same as the person.
    public static func outcome(_ comparison: BlindComparison) -> Double? {
        let opinions = [comparison.pickedNewer, comparison.aiPickedNewer].compactMap { $0 }
        guard !opinions.isEmpty else { return nil }
        return Double(opinions.filter { $0 }.count) / Double(opinions.count)
    }

    public static func craft(_ comparisons: [BlindComparison]) -> Double {
        comparisons.sorted { $0.date < $1.date }.compactMap(outcome).reduce(craftStart) { clamp($0 + craftStep * (2 * $1 - 1), 0, 100) }
    }

    /// Writing's 0–100 reading, one point per day it changed: half the grammar check's accuracy,
    /// half craft from the blind comparisons. Time spent and pieces written never move it.
    public static func series(tests: [TestResult], comparisons: [BlindComparison]) -> [(day: Day, score: Double)] {
        enum Event { case grammar(Double), comparison(Double) }
        var events: [(date: Date, event: Event)] = tests.filter { $0.test == .writing }.map { ($0.date, .grammar($0.score)) }
        events += comparisons.compactMap { c in outcome(c).map { (c.date, .comparison($0)) } }
        var grammar: Double?
        var craft = craftStart
        var out: [(day: Day, score: Double)] = []
        for (date, event) in events.sorted(by: { $0.date < $1.date }) {
            switch event {
            case .grammar(let score): grammar = score
            case .comparison(let outcome): craft = clamp(craft + craftStep * (2 * outcome - 1), 0, 100)
            }
            guard let grammar else { continue }
            let point = (day: Day(date), score: 50 * grammar + 0.5 * craft)
            if out.last?.day == point.day { out[out.count - 1] = point } else { out.append(point) }
        }
        return out
    }
}
