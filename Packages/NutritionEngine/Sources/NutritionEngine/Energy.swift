import Foundation
import SystemCore

/// Body weight as a trend: daily weigh-ins are mostly water, so only the smoothed line means much.
public struct WeightTrend: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public var day: Day
        public var trend: Double
        /// The day's own weigh-in, when there was one.
        public var scale: Double?
        /// Whether that weigh-in counts (not a day just back from a trip or ill).
        public var counted: Bool
    }

    /// One point per day from the first weigh-in to the last day asked for.
    public var points: [Point]
    /// Scatter of weigh-ins around the trend, kg.
    public var noise: Double
    /// Readings far from the days on both sides: likely misreads, left out of the trend.
    public var outliers: [WeighIn]

    public subscript(day: Day) -> Double? { points.first { $0.day == day }?.trend }
    public var latest: Point? { points.last }

    /// Change per week over the last `days`, from a least-squares line through the trend.
    public func weeklyChange(days: Int = 14, ending: Day? = nil) -> Double? {
        let end = ending ?? points.last?.day
        guard let end else { return nil }
        let window = points.filter { $0.day > end.adding(days: -days) && $0.day <= end }
        guard window.count >= max(5, days / 3), let first = window.first else { return nil }
        let xs = window.map { Double(first.day.days(until: $0.day)) }
        let ys = window.map(\.trend)
        let n = Double(window.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den == 0 ? 0 : num / den * 7
    }

    public static let empty = WeightTrend(points: [], noise: 0.6, outliers: [])
}

public enum Weight {
    /// How quickly the trend's level follows the scale: half of a reading's surprise is absorbed
    /// after this many days.
    public static let levelHalfLife = 4.0
    /// How quickly the trend's rate of change follows: slower, so a few water days don't tilt it.
    public static let slopeHalfLife = 14.0
    /// Past this many days without a reading the trend stops extrapolating and holds.
    public static let projectionDays = 7

    /// The trend through `through`: same-day weigh-ins averaged, then smoothed for both level and
    /// rate (Holt's method), so a steady loss or gain is followed without the lag a plain average
    /// has. Readings marked excluded, days in `ignored` (just back from a trip, or ill: that's
    /// water) and lone misreads don't move it.
    public static func trend(_ weighIns: [WeighIn], through: Day, ignored: Set<Day> = []) -> WeightTrend {
        let usable = weighIns.filter { !$0.excluded && $0.kg > 20 && $0.kg < 400 }
        var byDay: [Day: Double] = [:]
        for (day, list) in Dictionary(grouping: usable, by: \.day) { byDay[day] = list.map(\.kg).reduce(0, +) / Double(list.count) }
        // A reading more than 3% away from both neighbours is a likely misread.
        let days = byDay.keys.sorted()
        var outliers: [WeighIn] = []
        for (i, day) in days.enumerated() {
            guard let kg = byDay[day] else { continue }
            let neighbours = [i > 0 ? byDay[days[i - 1]] : nil, i + 1 < days.count ? byDay[days[i + 1]] : nil].compactMap { $0 }
            if neighbours.count == 2, neighbours.allSatisfy({ abs($0 - kg) > kg * 0.03 }) {
                outliers += usable.filter { $0.day == day }
                byDay[day] = nil
            }
        }
        guard let start = byDay.keys.min(), start <= through else { return WeightTrend(points: [], noise: 0.6, outliers: outliers) }
        // Start from the median of the first week so one odd first reading doesn't skew it.
        let opening = byDay.filter { $0.key < start.adding(days: 7) }.values.sorted()
        var level = opening[opening.count / 2]
        var slope = 0.0
        var points: [WeightTrend.Point] = []
        var residuals: [Double] = []
        var last = start
        for day in stride(from: start, through: through, by: 1) {
            let scale = byDay[day]
            if let scale, !ignored.contains(day) {
                let gap = Double(max(1, last.days(until: day)))
                let projected = level + slope * min(gap, Double(projectionDays))
                let alpha = 1 - pow(0.5, gap / levelHalfLife)
                let beta = 1 - pow(0.5, gap / slopeHalfLife)
                residuals.append(scale - projected)
                let next = projected + alpha * (scale - projected)
                slope += beta * ((next - level) / gap - slope)
                level = next
                last = day
            }
            let ahead = Double(min(last.days(until: day), projectionDays))
            points.append(WeightTrend.Point(day: day, trend: level + slope * ahead, scale: scale,
                                            counted: scale != nil && !ignored.contains(day)))
        }
        let noise = residuals.count >= 5 ? sqrt(residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count)) : 0.6
        return WeightTrend(points: points, noise: max(0.2, noise), outliers: outliers)
    }
}

/// Maintenance calories: a formula guess first, then what intake and the weight trend reveal.
public struct MaintenanceEstimate: Hashable, Codable, Sendable {
    public enum Basis: String, Codable, Sendable {
        /// Only the formula: no data yet.
        case formula
        /// Formula and data blended.
        case blended
        /// The data dominates.
        case data
    }

    public var kcal: Double
    public var low: Double
    public var high: Double
    public var basis: Basis
    /// Usable days of intake behind it.
    public var days: Int
    /// The formula's guess, for comparison ("maintenance looks lower than expected").
    public var formula: Double

    public var spread: Double { (high - low) / 2 }

    public var label: String {
        switch spread {
        case 350...: "Early estimate, still learning"
        case 200..<350: "Getting there"
        default: "Solid"
        }
    }
}

/// Energy balance over a window: mean intake on usable days against the slope of the weigh-ins.
public struct EnergyObservation: Hashable, Sendable {
    /// Usable days: complete with entries, or fasting with none. Gaps and partial days are unknown, never zero.
    public var used: Int
    /// Mean intake on the usable days.
    public var intake: Double
    /// Day-to-day scatter of that intake.
    public var intakeSpread: Double
    /// Weight change in kg a day, from a straight line through the weigh-ins.
    public var slope: Double
    /// Standard error of that slope.
    public var slopeError: Double
    public var weighInDays: Int
    /// Days from the first weigh-in in the window to the last.
    public var span: Int

    /// What maintenance must have been.
    public var raw: Double { intake - slope * Energy.kcalPerKg }
    public var weeklyKg: Double { slope * 7 }
    /// Standard error of ``raw``: scale scatter, intake scatter, and a floor for logging error.
    public var rawError: Double {
        let fromWeight = slopeError * Energy.kcalPerKg
        let fromIntake = intakeSpread / Double(max(1, used)).squareRoot()
        return (fromWeight * fromWeight + fromIntake * fromIntake + Energy.loggingError * Energy.loggingError).squareRoot()
    }
}

public enum Energy {
    /// kcal in a kg of body-weight change, mixed fat and lean tissue.
    public static let kcalPerKg = 7700.0
    /// The floor on how well logs can know intake, kcal a day: labels and portions are never exact.
    public static let loggingError = 75.0

    /// Mifflin–St Jeor resting energy.
    public static func restingEnergy(sex: BiologicalSex, kg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * kg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    /// Activity multiplier from training days and other weekly activity. With a step count,
    /// everyday movement comes from it (0.02 of resting energy per 1,000 steps either side of
    /// 7,500) instead of an assumed average.
    public static func activityFactor(trainingDays: Int, otherActiveMinutes: Double, dailySteps: Double? = nil) -> Double {
        let everyday = dailySteps.map { clamp(1.35 + 0.02 * ($0 - 7_500) / 1_000, 1.2, 1.6) } ?? 1.35
        return clamp(everyday + 0.04 * Double(trainingDays) + otherActiveMinutes / 60 * 0.012, 1.2, 1.8)
    }

    /// The formula guess, with a typical error of about 15%.
    public static func formula(sex: BiologicalSex, kg: Double, heightCm: Double?, age: Int?, trainingDays: Int,
                               otherActiveMinutes: Double, dailySteps: Double? = nil) -> Double {
        let height = heightCm ?? (sex == .female ? 165 : 177)
        return restingEnergy(sex: sex, kg: kg, heightCm: height, age: age ?? 35)
            * activityFactor(trainingDays: trainingDays, otherActiveMinutes: otherActiveMinutes, dailySteps: dailySteps)
    }

    /// Energy balance over a window. The weight change comes from a least-squares line through
    /// the weigh-ins themselves, not the smoothed trend, which lags. Intake is the mean of usable
    /// days, so a missing or partial day is unknown rather than zero.
    public static func observe(trend: WeightTrend, usable: [Day: Double], window: DayRange) -> EnergyObservation {
        let intakes = window.days.compactMap { usable[$0] }
        let used = intakes.count
        let intake = used == 0 ? 0 : intakes.reduce(0, +) / Double(used)
        let intakeSpread = used < 2 ? 400 : (intakes.map { ($0 - intake) * ($0 - intake) }.reduce(0, +) / Double(used - 1)).squareRoot()

        let readings = trend.points.filter { window.contains($0.day) && $0.counted }.compactMap { p in p.scale.map { (p.day, $0) } }
        guard readings.count >= 2, let first = readings.first?.0, let last = readings.last?.0 else {
            return EnergyObservation(used: used, intake: intake, intakeSpread: intakeSpread, slope: 0, slopeError: 1,
                                     weighInDays: readings.count, span: 0)
        }
        let xs = readings.map { Double(first.days(until: $0.0)) }
        let ys = readings.map(\.1)
        let n = Double(readings.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
        }
        let slope = sxx == 0 ? 0 : sxy / sxx
        // Scatter around the line, inflated by a third: water swings run for days at a time, so
        // weigh-ins are less independent than they look. A floor for when the points happen to line up.
        let residual = zip(xs, ys).map { x, y in y - (my + slope * (x - mx)) }
        let fitted = readings.count > 2 ? (residual.map { $0 * $0 }.reduce(0, +) / (n - 2)).squareRoot() : 0.6
        let sigma = max(fitted * 1.3, readings.count >= 8 ? 0.3 : 0.6)
        let slopeError = sxx == 0 ? 1 : sigma / sxx.squareRoot()
        return EnergyObservation(used: used, intake: intake, intakeSpread: intakeSpread, slope: slope, slopeError: slopeError,
                                 weighInDays: readings.count, span: first.days(until: last))
    }

    /// Blends the formula with energy balance by how much each can be trusted. The first week
    /// of weigh-ins is skipped: early changes are water.
    public static func estimate(trend: WeightTrend, usable: [Day: Double], formula: Double, through: Day, window: Int = 28) -> MaintenanceEstimate {
        let formulaSD = formula * 0.15
        guard let firstDay = trend.points.first?.day else {
            return estimate(formula, sd: formulaSD, basis: .formula, days: 0, formula: formula)
        }
        let start = max(firstDay.adding(days: 7), through.adding(days: -(window - 1)))
        guard start < through else { return estimate(formula, sd: formulaSD, basis: .formula, days: 0, formula: formula) }
        let observation = observe(trend: trend, usable: usable, window: DayRange(start, through))
        guard observation.used >= 5, observation.weighInDays >= 4, observation.span >= 6 else {
            return estimate(formula, sd: formulaSD, basis: .formula, days: observation.used, formula: formula)
        }
        let dataSD = max(50, observation.rawError)
        let wf = 1 / (formulaSD * formulaSD), wd = 1 / (dataSD * dataSD)
        let blended = (formula * wf + observation.raw * wd) / (wf + wd)
        let sd = 1 / (wf + wd).squareRoot()
        return estimate(blended, sd: sd, basis: wd > wf * 3 ? .data : .blended, days: observation.used, formula: formula)
    }

    private static func estimate(_ kcal: Double, sd: Double, basis: MaintenanceEstimate.Basis, days: Int, formula: Double) -> MaintenanceEstimate {
        func round50(_ x: Double) -> Double { (x / 50).rounded() * 50 }
        return MaintenanceEstimate(kcal: round50(kcal), low: round50(kcal - 1.5 * sd), high: round50(kcal + 1.5 * sd), basis: basis,
                                   days: days, formula: round50(formula))
    }
}

// MARK: - Weekly check-ins

/// The targets in force from a day on: set at onboarding's end and by each weekly check-in.
public struct CheckIn: Hashable, Codable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// Updated from the data.
        case updated
        /// Not enough data yet; the previous numbers stand.
        case learning
        /// Something looked off (a jump, a fast change); the previous numbers stand.
        case holding
        /// Set by the person.
        case manual
        /// Maintenance dropped mostly because steps fell: targets hold once while they come back.
        case steps
    }

    public var id: UUID
    public var day: Day
    /// The maintenance the targets are built on.
    public var expenditure: Double
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var status: Status
    public var reason: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), day: Day, expenditure: Double, kcal: Double, protein: Double, carbs: Double, fat: Double,
                status: Status, reason: String, updatedAt: Date = Date()) {
        self.id = id
        self.day = day
        self.expenditure = expenditure
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.status = status
        self.reason = reason
        self.updatedAt = updatedAt
    }
}

public enum CheckIns {
    /// How far the expenditure moves toward a new observation each week.
    public static let damping = 0.35

    public static func isDue(last: CheckIn?, today: Day) -> Bool {
        guard let last else { return true }
        return last.day.days(until: today) >= 7
    }

    /// The week's review: observe the last 21 days, move expenditure part of the way, and move
    /// targets at most 150 kcal (or 7.5%). Holds rather than reacting to a jump or a lone misread.
    /// In a deficit, when fewer steps explain most of a lower maintenance, it holds once and says
    /// to walk back up before calories come down.
    public static func review(previous: CheckIn?, trend: WeightTrend, usable: [Day: Double], today: Day, phase: PlannedPhase?,
                              weightKg: Double, referenceKg: Double, fallbackExpenditure: Double, steps: StepSummary? = nil) -> CheckIn {
        let prior = previous?.expenditure ?? fallbackExpenditure
        let window = DayRange(today.adding(days: -21), today.adding(days: -1))
        let observation = Energy.observe(trend: trend, usable: usable, window: window)
        func make(_ expenditure: Double, _ status: CheckIn.Status, _ reason: String) -> CheckIn {
            var kcal = Targets.calories(maintenance: expenditure, phase: phase, weightKg: weightKg)
            if let old = previous?.kcal {
                let step = min(Targets.weeklyStep, old * 0.075)
                kcal = clamp(kcal, old - step, old + step)
            }
            let m = Targets.macros(kcal: kcal, referenceKg: referenceKg, phase: phase?.kind)
            return CheckIn(day: today, expenditure: (expenditure / 10).rounded() * 10, kcal: kcal, protein: m.protein, carbs: m.carbs,
                           fat: m.fat, status: status, reason: reason)
        }
        let recentWeighIn = trend.points.last { $0.scale != nil }?.day
        guard let recentWeighIn, recentWeighIn >= window.end.adding(days: -3) else {
            return make(prior, .learning, "Add a recent weigh-in so the plan can use your current trend.")
        }
        guard observation.used >= 12, observation.weighInDays >= 6 else {
            return make(prior, .learning, "Learning from your logs: 12 complete days and 6 weigh-ins over three weeks. Gaps pause learning without resetting it.")
        }
        if !trend.outliers.isEmpty, trend.outliers.contains(where: { window.contains($0.day) }) {
            return make(prior, .holding, "One weigh-in is far from the ones around it, so it was left out. Ignore it if it was a misread.")
        }
        if abs(observation.weeklyKg) > weightKg * 0.01 {
            return make(prior, .holding, "Weight moved more than 1% a week, which is mostly water. Holding until it settles.")
        }
        let raw = observation.raw
        guard (1200...5000).contains(raw) else {
            return make(prior, .holding, "The numbers don't add up yet (often a few unlogged meals). Holding.")
        }
        let expenditure = prior + damping * clamp(raw - prior, -500, 500)
        let change = expenditure - prior
        if change <= -25, phase?.kind.energy == .deficit, let steps, let fall = Steps.fall(steps.days, window: window) {
            let burned = Double(fall.before - fall.during) * Steps.kcalPerStep(kg: weightKg)
            let fell = "Steps fell from \(fall.before.formatted()) to \(fall.during.formatted()) a day, about \(Int((burned / 10).rounded() * 10)) kcal less burned"
            let aim = steps.aim.map { "back toward \($0.formatted()) a day" } ?? "back up"
            if burned >= min(prior - raw, 500) * 0.5, previous?.status != .steps {
                return make(prior, .steps, "\(fell), which is most of the lower maintenance. Maintenance holds this week: walk \(aim) before calories come down. If steps stay down, next week follows the data.")
            }
            let lower = "Maintenance looks lower than last week (about \(Int((expenditure / 10).rounded() * 10)) kcal), so targets move down a little."
            return make(expenditure, .updated, "\(lower) \(fell); walking \(aim) would win some of it back.")
        }
        let reason = abs(change) < 25
            ? "Maintenance holding at about \(Int((expenditure / 10).rounded() * 10)) kcal."
            : "Maintenance looks \(change > 0 ? "higher" : "lower") than last week (about \(Int((expenditure / 10).rounded() * 10)) kcal), so targets move \(change > 0 ? "up" : "down") a little."
        return make(expenditure, .updated, reason)
    }
}
