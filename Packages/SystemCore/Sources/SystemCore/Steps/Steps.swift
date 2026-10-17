import Foundation

/// A day's step count from Health, every source merged the way Health shows it (an iPhone and a
/// Watch don't double count).
public struct StepDay: Hashable, Codable, Sendable {
    public var day: Day
    public var steps: Int

    public init(day: Day, steps: Int) {
        self.day = day
        self.steps = steps
    }
}

/// The daily step aim. It starts from the person's own usual count, not a universal 10,000, is set
/// by the nutrition phase, and is judged as a weekly average so one quiet day doesn't matter.
/// Not a stat, a streak or a ring: it's shown only when there's something to do.
public struct StepAim: Hashable, Codable, Sendable {
    /// Usual steps a day before the current phase began.
    public var baseline: Int
    /// Where the aim is heading.
    public var target: Int
    /// This week's aim, a day.
    public var aim: Int
    /// The last seven complete days, oldest first, unknown days included as they came.
    public var week: [StepDay]
    /// The average over those days, when at least four are known.
    public var recent: Int?
    /// Today so far.
    public var today: Int?
    public var energy: PhaseKind.Energy
    /// Always in a cut; otherwise only while building up to the floor, or when steps have slipped.
    public var shown: Bool
    /// Why the aim is what it is, in plain words.
    public var reason: String

    public init(baseline: Int, target: Int, aim: Int, week: [StepDay], recent: Int?, today: Int?, energy: PhaseKind.Energy,
                shown: Bool, reason: String) {
        self.baseline = baseline
        self.target = target
        self.aim = aim
        self.week = week
        self.recent = recent
        self.today = today
        self.energy = energy
        self.shown = shown
        self.reason = reason
    }

    /// Whether the last week's average is close enough to the aim.
    public var onTrack: Bool? { recent.map { Double($0) >= Double(aim) * Steps.onTrackShare } }

    /// Steps a day between the last week's average and the aim.
    public var gap: Int { max(0, aim - (recent ?? baseline)) }
}

/// What Lift Track publishes about steps, for Macro Track's check-ins and the hub.
public struct StepSummary: Hashable, Codable, Sendable {
    /// Complete days, oldest first: the last eight weeks.
    public var days: [StepDay]
    public var aim: Int?
    public var baseline: Int?

    public init(days: [StepDay], aim: Int?, baseline: Int?) {
        self.days = days
        self.aim = aim
        self.baseline = baseline
    }
}

public enum Steps {
    /// Days under this usually mean the phone stayed on a desk: unknown, not sedentary.
    public static let carriedMinimum = 1_000
    /// How far the aim rises in a week.
    public static let weeklyStep = 1_000
    /// What a cut adds to the usual count.
    public static let cutExtra = 2_000
    /// In a cut, the extra stops at this; a higher usual count is held.
    public static let cutCap = 12_000
    /// Outside a cut there's nothing to prescribe above this.
    public static let holdCap = 10_000
    public static let onTrackShare = 0.95
    /// Brisk walking, for turning steps into minutes.
    public static let perMinute = 100

    /// Where the benefit of daily steps levels off in large cohort studies: about 6,000–8,000 a day
    /// over 60 and 8,000–10,000 under. The floor sits at the bottom of each.
    public static func floor(age: Int?) -> Int { (age ?? 35) >= 60 ? 7_000 : 8_000 }

    /// Energy a step costs above resting, in kcal: about 0.04 at 80 kg, scaling with body weight.
    public static func kcalPerStep(kg: Double) -> Double { 0.0005 * kg }

    /// Mean steps over the known days in a range (carried, and not exempt), or nil with too few.
    public static func average(_ days: [StepDay], in range: DayRange, exempt: Set<Day> = [], minimumDays: Int) -> Int? {
        let values = days.filter { range.contains($0.day) && $0.steps >= carriedMinimum && !exempt.contains($0.day) }.map(\.steps)
        guard !values.isEmpty, values.count >= minimumDays else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// Usual steps before the phase began: the four weeks before it; failing that (Health is new),
    /// the first four weeks of it; failing that, the last four weeks.
    public static func baseline(_ days: [StepDay], anchor: Day, today: Day, exempt: Set<Day> = []) -> Int? {
        let yesterday = today.adding(days: -1)
        var windows = [DayRange(anchor.adding(days: -28), anchor.adding(days: -1))]
        if anchor <= yesterday { windows.append(DayRange(anchor, min(anchor.adding(days: 27), yesterday))) }
        windows.append(DayRange(today.adding(days: -28), yesterday))
        for window in windows where window.end < today {
            if let mean = average(days, in: window, exempt: exempt, minimumDays: 7) { return mean }
        }
        return nil
    }

    /// Where the aim heads. A cut adds 2,000 to the usual count (at least the floor; a usual count
    /// already over 12,000 is held). Otherwise the usual count is held, raised to the floor if it's
    /// under it, and nothing over 10,000 is prescribed.
    public static func target(baseline: Int, energy: PhaseKind.Energy, age: Int?) -> Int {
        let floor = floor(age: age)
        let raw = switch energy {
        case .deficit: max(floor, min(baseline + cutExtra, max(baseline, cutCap)))
        case .maintenance, .surplus: max(floor, min(baseline, holdCap))
        }
        return round(raw, to: 500)
    }

    /// A calendar week's aim: a week's step up from last week's average, never under the usual
    /// count, never past the target. Missing a week doesn't raise the next one.
    public static func weeklyAim(target: Int, baseline: Int, lastWeek: Int?) -> Int {
        guard target > baseline else { return target }
        let next = (lastWeek ?? baseline) + weeklyStep
        return min(target, roundUp(max(baseline, next), to: 500))
    }

    /// The aim for today, or nil without enough step data to know the usual count.
    public static func aim(days: [StepDay], anchor: Day, energy: PhaseKind.Energy, age: Int?, today: Day,
                           exempt: Set<Day> = []) -> StepAim? {
        guard let baseline = baseline(days, anchor: anchor, today: today, exempt: exempt) else { return nil }
        let target = target(baseline: baseline, energy: energy, age: age)
        let weekStart = today.startOfWeek
        let lastWeek = average(days, in: DayRange(weekStart.adding(days: -7), weekStart.adding(days: -1)), exempt: exempt, minimumDays: 4)
        let aim = weeklyAim(target: target, baseline: baseline, lastWeek: lastWeek)
        let recentRange = DayRange(today.adding(days: -7), today.adding(days: -1))
        let byDay = Dictionary(days.map { ($0.day, $0.steps) }, uniquingKeysWith: max)
        let week = recentRange.days.map { StepDay(day: $0, steps: byDay[$0] ?? 0) }
        let recent = average(days, in: recentRange, exempt: exempt, minimumDays: 4)

        let usual = round(baseline, to: 100).formatted()
        let building = target > baseline + 250
        let slipped = recent.map { $0 < aim - 1_000 } ?? false
        let reason: String
        switch energy {
        case .deficit:
            let cut = "In a cut, everyday movement tends to drop without anyone noticing, and that's often what stalls one."
            if !building {
                reason = "\(cut) You already walk plenty, so the aim is to hold your usual \(usual)."
            } else if target == round(baseline + cutExtra, to: 500) {
                reason = "\(cut) The aim is your usual \(usual) plus about 2,000, raised about 1,000 a week."
            } else {
                reason = "\(cut) The aim is \(target.formatted()), up from your usual \(usual), raised about 1,000 a week."
            }
        case .maintenance, .surplus:
            if building {
                reason = "About \(target.formatted()) a day is where the health benefit of walking levels off. Your usual is \(usual), so the aim rises about 1,000 a week."
            } else {
                reason = "Steps have slipped from your usual \(usual) a day. Getting back there is the aim."
            }
        }
        return StepAim(baseline: baseline, target: target, aim: aim, week: week, recent: recent, today: byDay[today], energy: energy,
                       shown: energy == .deficit || building || slipped, reason: reason)
    }

    /// Long days on foot nobody logged (a hike, a day of sightseeing), as minutes of walking beyond
    /// the usual: at least 7,000 over it and 15,000 in all. Ordinary days cost next to nothing.
    public static func longDays(_ days: [StepDay], baseline: Int, skipping: Set<Day> = []) -> [(day: Day, minutes: Int)] {
        days.compactMap { d in
            guard !skipping.contains(d.day), d.steps >= max(15_000, baseline + 7_000) else { return nil }
            return (d.day, (d.steps - baseline) / perMinute)
        }
    }

    /// Whether steps fell between the four weeks before a window and the window itself: by at
    /// least 1,500 a day and an eighth.
    public static func fall(_ days: [StepDay], window: DayRange) -> (before: Int, during: Int)? {
        guard let during = average(days, in: window, minimumDays: 10),
              let before = average(days, in: DayRange(window.start.adding(days: -28), window.start.adding(days: -1)), minimumDays: 10),
              before - during >= max(1_500, before / 8) else { return nil }
        return (before, during)
    }

    /// To the nearest `step`: aims to 500, counts shown to people to 100.
    public static func round(_ value: Int, to step: Int) -> Int { Int((Double(value) / Double(step)).rounded()) * step }
    static func roundUp(_ value: Int, to step: Int) -> Int { Int((Double(value) / Double(step)).rounded(.up)) * step }
}
