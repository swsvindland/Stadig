import Foundation

/// Simple, repeatable mobility tests, taken about every four weeks at the end of a deload.
public enum MobilityTest: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case hip9090, deepSquatHold, kneeToWall, sitAndReach, overheadReach

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hip9090: "90/90 hip switch"
        case .deepSquatHold: "Deep squat hold"
        case .kneeToWall: "Knee-to-wall"
        case .sitAndReach: "Sit-and-reach"
        case .overheadReach: "Overhead reach"
        }
    }

    public var instructions: String {
        switch self {
        case .hip9090: "Sit in 90/90. Switch sides without hands, ten times. Rate how it went."
        case .deepSquatHold:
            "Heels down, feet about shoulder width. Hold the bottom of a bodyweight squat as long as you comfortably can, up to 60 seconds."
        case .kneeToWall: "Facing a wall, keep the heel down and touch the knee to the wall. Measure the toe-to-wall distance; take the worse side."
        case .sitAndReach: "Legs straight, reach toward the toes. Measure fingertips past the toes (negative if short)."
        case .overheadReach:
            "Back flat against a wall, arms straight, raise them overhead. Rate how close the thumbs get to the wall without the ribs flaring."
        }
    }

    public var target: MobilityTarget {
        switch self {
        case .hip9090: .hips
        case .deepSquatHold: .hips
        case .kneeToWall: .ankles
        case .sitAndReach: .hamstrings
        case .overheadReach: .shoulders
        }
    }

    public enum Measure: String, Codable, Sendable {
        /// 0–3: can't, with effort, mostly clean, clean.
        case quality
        case seconds
        case centimetres
    }

    public var measure: Measure {
        switch self {
        case .hip9090, .overheadReach: .quality
        case .deepSquatHold: .seconds
        case .kneeToWall, .sitAndReach: .centimetres
        }
    }

    public var unit: String {
        switch measure {
        case .quality: ""
        case .seconds: "s"
        case .centimetres: "cm"
        }
    }

    /// The raw value mapped to 0–100, where 100 meets a healthy standard and beyond counts no more.
    public func score(_ value: Double) -> Double {
        switch self {
        case .hip9090, .overheadReach: clamp(value / 3, 0, 1) * 100
        case .deepSquatHold: clamp(value / 60, 0, 1) * 100
        // 10 cm toe-to-wall is a common healthy ankle standard.
        case .kneeToWall: clamp(value / 10, 0, 1) * 100
        // From 20 cm short (0) to 5 cm past the toes (100).
        case .sitAndReach: clamp((value + 20) / 25, 0, 1) * 100
        }
    }

    public static let qualityLabels = ["Can't", "With effort", "Mostly clean", "Clean"]
}

public struct MobilityResult: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var test: MobilityTest
    public var day: Day
    public var value: Double
    /// Pain during the test: the answer is a physio, not more stretching.
    public var painful: Bool

    public init(id: UUID = UUID(), test: MobilityTest, day: Day, value: Double, painful: Bool = false) {
        self.id = id
        self.test = test
        self.day = day
        self.value = value
        self.painful = painful
    }

    public var score: Double { test.score(value) }
}

public struct AgilityAnalysis: Hashable, Sendable {
    /// Latest result per test.
    public var latest: [MobilityTest: MobilityResult]
    /// The weakest area: every session's limiter slot works on it.
    public var limiter: MobilityTarget?
    public var limiterTest: MobilityTest?
    /// 0–100 average of the latest tests.
    public var score: Double?
    /// Tests that hurt or got worse twice running: see a physio, don't stretch harder.
    public var seePhysio: [MobilityTest]
}

public enum Agility {
    public static func analyse(_ results: [MobilityResult]) -> AgilityAnalysis {
        var latest: [MobilityTest: MobilityResult] = [:]
        var history: [MobilityTest: [MobilityResult]] = [:]
        for result in results.sorted(by: { $0.day < $1.day }) {
            latest[result.test] = result
            history[result.test, default: []].append(result)
        }
        // In the tests' fixed order, never the dictionary's (which changes from launch to launch), so
        // a tie always goes to the first test and the plan doesn't change on its own.
        let inOrder = MobilityTest.allCases.compactMap { latest[$0] }
        let weakest = inOrder.filter { !$0.painful }.min { $0.score < $1.score }
        let limiter = weakest.flatMap { $0.score < 90 ? $0.test.target : nil }
        let scores = inOrder.map(\.score)
        let seePhysio = history.compactMap { test, list -> MobilityTest? in
            if list.last?.painful == true { return test }
            let recent = list.suffix(3).map(\.score)
            if recent.count == 3, recent[2] < recent[1], recent[1] < recent[0] { return test }
            return nil
        }
        return AgilityAnalysis(
            latest: latest, limiter: limiter, limiterTest: limiter == nil ? nil : weakest?.test,
            score: scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count),
            seePhysio: seePhysio.sorted { $0.rawValue < $1.rawValue })
    }
}
