import Foundation

/// A fixed, repeatable conditioning test, taken about every four weeks at the end of a deload.
public enum EnduranceBenchmark: String, CaseIterable, Codable, Sendable, Identifiable {
    case row2k, bike12min, stairs10min, run2_4k

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .row2k: "2 km row"
        case .bike12min: "12-minute bike"
        case .stairs10min: "10-minute StairMaster"
        case .run2_4k: "2.4 km run"
        }
    }

    public var instructions: String {
        switch self {
        case .row2k: "Row 2,000 m as fast as you can hold. Same damper every time."
        case .bike12min: "Ride as far as you can in 12 minutes. Same bike and resistance every time."
        case .stairs10min: "Climb as many floors as you can in 10 minutes at a level you choose once and keep."
        case .run2_4k: "Run 2.4 km as fast as you can hold, on the same route or treadmill incline."
        }
    }

    public enum Measure: String, Codable, Sendable { case timeSeconds, distanceMeters, floors }

    public var measure: Measure {
        switch self {
        case .row2k, .run2_4k: .timeSeconds
        case .bike12min: .distanceMeters
        case .stairs10min: .floors
        }
    }

    /// Lower times are better; higher distances and floors are better.
    public var lowerIsBetter: Bool { measure == .timeSeconds }

    public var equipment: Equipment {
        switch self {
        case .row2k: .rower
        case .bike12min: .bike
        case .stairs10min: .stairClimber
        case .run2_4k: .treadmill
        }
    }

    /// Relative improvement from one result to the next, positive when better.
    public func improvement(from old: Double, to new: Double) -> Double {
        guard old > 0, new > 0 else { return 0 }
        return lowerIsBetter ? (old - new) / old : (new - old) / old
    }
}

public struct BenchmarkResult: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var benchmark: EnduranceBenchmark
    public var day: Day
    public var value: Double
    public var averageHeartRate: Double?

    public init(id: UUID = UUID(), benchmark: EnduranceBenchmark, day: Day, value: Double, averageHeartRate: Double? = nil) {
        self.id = id
        self.benchmark = benchmark
        self.day = day
        self.value = value
        self.averageHeartRate = averageHeartRate
    }
}

/// Heart-rate zones from heart-rate reserve (Karvonen).
public struct HeartRateZones: Hashable, Codable, Sendable {
    public var resting: Double
    public var maximum: Double

    public init(resting: Double, maximum: Double) {
        self.resting = resting
        self.maximum = max(maximum, resting + 40)
    }

    /// Tanaka's age-predicted maximum.
    public static func estimated(age: Int?, resting: Double?) -> HeartRateZones {
        let max = 208 - 0.7 * Double(age ?? 35)
        return HeartRateZones(resting: resting ?? 62, maximum: max)
    }

    public func bpm(atReserve fraction: Double) -> Double { resting + (maximum - resting) * fraction }

    /// Zone 1–5 for a heart rate.
    public func zone(for bpm: Double) -> Int {
        let fraction = (bpm - resting) / (maximum - resting)
        switch fraction {
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    public func range(zone: Int) -> ClosedRange<Double> {
        let bounds: [Int: (Double, Double)] = [1: (0.5, 0.6), 2: (0.6, 0.7), 3: (0.7, 0.8), 4: (0.8, 0.9), 5: (0.9, 1)]
        let b = bounds[clamp(zone, 1, 5)]!
        return bpm(atReserve: b.0)...bpm(atReserve: b.1)
    }
}

/// How long to rest, and whether heart rate may end the rest early.
public struct RestPlan: Hashable, Codable, Sendable {
    /// The rest prescribed for this set.
    public var target: Int
    /// The rest can never end before this, whatever the heart rate says.
    public var minimum: Int
    /// Whether a recovered heart rate may end the rest early.
    public var heartRateGuided: Bool

    public init(target: Int, minimum: Int, heartRateGuided: Bool) {
        self.target = target
        self.minimum = min(minimum, target)
        self.heartRateGuided = heartRateGuided
    }
}

public enum RestRole: String, Codable, Sendable {
    /// Heavy compounds: recovery is mostly local and neural, so a minimum rest always holds.
    case heavyCompound
    case compound
    case accessory
}

public enum Rest {
    /// Rest for a set. Accessories and hypertrophy work may end early on a recovered heart rate;
    /// heavy compounds keep their minimum. Low endurance earns slightly longer rests.
    public static func plan(role: RestRole, reps: Int, defaultSeconds: Int, enduranceScore: Double?, hrGuidance: Bool) -> RestPlan {
        var target = Double(defaultSeconds)
        if let score = enduranceScore, score < 40 { target *= 1.15 }
        let target_ = Int((target / 15).rounded() * 15)
        switch role {
        case .heavyCompound:
            return RestPlan(target: max(target_, 150), minimum: 150, heartRateGuided: false)
        case .compound:
            return RestPlan(target: target_, minimum: reps <= 6 ? 120 : 75, heartRateGuided: hrGuidance && reps > 6)
        case .accessory:
            return RestPlan(target: target_, minimum: 45, heartRateGuided: hrGuidance)
        }
    }

    /// Whether rest may end now: past the minimum and heart rate back to the recovered threshold.
    /// The threshold is about 55% of heart-rate reserve, or within 12 bpm of where the set began.
    public static func recovered(heartRate: Double, preSet: Double?, zones: HeartRateZones, elapsed: Int, plan: RestPlan) -> Bool {
        guard plan.heartRateGuided, elapsed >= plan.minimum else { return false }
        let threshold = max(zones.bpm(atReserve: 0.55), (preSet ?? 0) + 12)
        return heartRate <= threshold
    }
}

public enum HeartRateRecovery {
    /// The drop in the minute after a set: peak within ten seconds of the set's end, minus the
    /// heart rate at sixty seconds. Faster recovery means a better engine.
    public static func drop(samples: [(date: Date, bpm: Double)], setEnd: Date) -> (peak: Double, drop: Double)? {
        let peakWindow = samples.filter { abs($0.date.timeIntervalSince(setEnd)) <= 10 }
        guard let peak = peakWindow.map(\.bpm).max() else { return nil }
        let later = samples.filter { (50...75).contains($0.date.timeIntervalSince(setEnd)) }
        guard let after = later.min(by: { abs($0.date.timeIntervalSince(setEnd) - 60) < abs($1.date.timeIntervalSince(setEnd) - 60) }) else {
            return nil
        }
        return (peak, peak - after.bpm)
    }

    /// The trend in recovery for comparable sets, bpm per week; positive is improving.
    public static func trend(_ points: [(day: Day, drop: Double)]) -> Double? {
        guard points.count >= 4, let first = points.first?.day else { return nil }
        return leastSquaresSlope(x: points.map { Double(first.days(until: $0.day)) / 7 }, y: points.map(\.drop))
    }
}

/// The Endurance stat from the passive engine (VO2 max, resting heart rate) and benchmark trends.
public struct EnduranceAnalysis: Hashable, Sendable {
    public var vo2Max: Double?
    public var restingHeartRate: Double?
    public var latestBenchmark: BenchmarkResult?
    /// Change since the previous benchmark of the same kind, positive when better.
    public var benchmarkChange: Double?
    public var heartRateRecoveryTrend: Double?
    /// Weekly minutes of conditioning and declared cardio over the last four weeks.
    public var weeklyConditioningMinutes: Double
    public var score: Double?
    /// A lagging engine: Zone 2 belongs in a free block.
    public var engineLagging: Bool
    /// A lagging benchmark: intervals belong in the post-lift conditioning block.
    public var benchmarkLagging: Bool
}

public enum Endurance {
    /// VO2 max standards (ml/kg/min) for "fair" and "excellent", roughly by sex.
    static func vo2Range(_ sex: BiologicalSex, age: Int?) -> ClosedRange<Double> {
        let ageAdjust = Double(max(0, (age ?? 35) - 30)) * 0.25
        switch sex {
        case .female: return (31 - ageAdjust)...(45 - ageAdjust)
        case .male: return (37 - ageAdjust)...(52 - ageAdjust)
        case .unspecified: return (34 - ageAdjust)...(48 - ageAdjust)
        }
    }

    public static func analyse(vo2Max: Double?, restingHeartRate: Double?, benchmarks: [BenchmarkResult],
                               hrrTrend: Double?, weeklyConditioningMinutes: Double, sex: BiologicalSex, age: Int?) -> EnduranceAnalysis {
        let sorted = benchmarks.sorted { $0.day < $1.day }
        let latest = sorted.last
        var change: Double?
        if let latest, let previous = sorted.dropLast().last(where: { $0.benchmark == latest.benchmark }) {
            change = latest.benchmark.improvement(from: previous.value, to: latest.value)
        }
        var parts: [Double] = []
        if let vo2Max {
            let range = vo2Range(sex, age: age)
            parts.append(clamp((vo2Max - range.lowerBound + 10) / (range.upperBound - range.lowerBound + 10), 0, 1.1) * 100)
        }
        if let rhr = restingHeartRate { parts.append(clamp((85 - rhr) / 35, 0, 1) * 100) }
        // Zone 2 guidance: ~150 minutes a week is a solid base.
        parts.append(clamp(weeklyConditioningMinutes / 150, 0, 1) * 100)
        let score = parts.reduce(0, +) / Double(parts.count)
        let engineLagging = weeklyConditioningMinutes < 60 || (vo2Max.map { $0 < vo2Range(sex, age: age).lowerBound } ?? false)
        let benchmarkLagging = (change.map { $0 < 0.005 } ?? false)
        return EnduranceAnalysis(vo2Max: vo2Max, restingHeartRate: restingHeartRate, latestBenchmark: latest, benchmarkChange: change,
                                 heartRateRecoveryTrend: hrrTrend, weeklyConditioningMinutes: weeklyConditioningMinutes,
                                 score: score, engineLagging: engineLagging, benchmarkLagging: benchmarkLagging)
    }
}
