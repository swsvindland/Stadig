#if DEBUG
import Foundation
import SystemCore

/// Years of one believable person, for measuring what the app does with a long log: 12 foods every
/// day, a weigh-in most mornings, a check-in a week, supplements, water and a fast a week. The same
/// person each time: the randomness is seeded. Debug builds only: `AnalysisBenchmarkTests`,
/// `LogPathBenchmarkTests` and the app's `-seedLongHistory` all read it.
public struct LongHistory: Sendable {
    public static let entriesPerDay = 12

    public var profile: SharedProfile
    public var settings: MacroSettings
    public var plan: PhasePlan
    public var entries: [FoodEntry] = []
    public var weighIns: [WeighIn] = []
    public var statuses: [DayStatus] = []
    public var checkIns: [CheckIn] = []
    public var supplements: [Supplement]
    public var supplementLogs: [SupplementLog] = []
    public var water: [WaterLog] = []
    public var fasts: [Fast] = []
    public var savedMeals: [SavedMeal] = []
    public var today: Day
    public var now: Date

    /// `years` of 365 days up to `now`: the days before today whole, and today's food so far.
    public init(years: Int, now: Date = Date(), seed: UInt64 = 2_600, calendar: Calendar = .current) {
        self.now = now
        today = Day(now, calendar: calendar)
        let days = years * 365
        let start = today.adding(days: -days)
        let begun = start.date(calendar: calendar)
        var rng = SeededRandom(seed: seed)

        profile = SharedProfile(
            goals: [.biggerAndStronger, .leaner], schedule: TrainingSchedule(daysPerWeek: 4), experience: .intermediate, sex: .male,
            birthYear: 1990, heightCm: 180, units: UnitPreference(weight: .kg, length: .cm), createdBy: .macroTrack, updatedAt: begun)
        settings = MacroSettings(
            onboardedAt: begun, assessmentStart: start, dietHistory: .none, updatedAt: begun)
        // Sixteen weeks at a time, up to and past today, as a plan kept going for years would read.
        let cycle: [PhaseKind] = [.cut, .maintenance, .leanBulk, .maintenance]
        plan = PhasePlan(
            phases: (0...(days / 112 + 1)).map { PlannedPhase(kind: cycle[$0 % cycle.count], weeks: 16, start: start.adding(days: $0 * 112)) },
            headline: "Long history", reasons: [], confidence: nil, arc: "", created: begun, updatedAt: begun)

        let fish = Supplement(
            facts: SupplementFacts(
                id: "custom:long-fish-oil", name: "Fish Oil", unit: "softgel",
                ingredients: [
                    SupplementIngredient(name: "EPA", amount: 216, unit: "mg"), SupplementIngredient(name: "DHA", amount: 144, unit: "mg"),
                ],
                source: .custom),
            doses: [Dose(time: .morning, count: 2)], updatedAt: begun)
        let multi = Supplement(
            facts: SupplementFacts(
                id: "custom:long-multi", name: "Multivitamin", unit: "tablet",
                ingredients: [
                    SupplementIngredient(name: "Vitamin D3", amount: 25, unit: "mcg"), SupplementIngredient(name: "Zinc", amount: 11, unit: "mg"),
                ],
                source: .custom),
            doses: [Dose(time: .morning, count: 1), Dose(time: .evening, count: 1)], updatedAt: begun)
        supplements = [fish, multi]

        entries.reserveCapacity(days * Self.entriesPerDay)
        var kg = 84.0
        for offset in 0...days {
            let day = start.adding(days: offset)
            for meal in Self.meals {
                let minute = meal.minute + Int(rng.below(61)) - 30
                let foods = Self.foods(for: meal, day: offset, using: &rng)
                for (index, food) in foods.enumerated() {
                    let date = day.at(minutes: minute, calendar: calendar).addingTimeInterval(Double(index) * 60)
                    guard date <= now else { continue }
                    entries.append(food.entry(at: date, day: day, scale: 0.8 + rng.unit() * 0.45))
                }
            }
            guard day < today else { continue }
            kg += (rng.unit() - 0.5) * 0.06
            if rng.unit() < 0.9 {
                let date = day.at(minutes: 420, calendar: calendar)
                weighIns.append(WeighIn(date: date, kg: kg + (rng.unit() - 0.5) * 1.2, updatedAt: date))
            }
            // Most days are marked done; the rest are read from what was logged.
            if rng.unit() < 0.9 { statuses.append(DayStatus(day: day, state: .complete, updatedAt: day.at(minutes: 1320, calendar: calendar))) }
            for ml in 0..<4 {
                let date = day.at(minutes: 540 + ml * 180, calendar: calendar)
                water.append(WaterLog(date: date, day: day, ml: 350, updatedAt: date))
            }
            for (supplement, doses, minute) in [(fish, fish.doses, 480), (multi, multi.doses, 480)] {
                for (index, dose) in doses.enumerated() {
                    let date = day.at(minutes: minute + index * 720, calendar: calendar)
                    supplementLogs.append(
                        SupplementLog(supplement: supplement, doseID: dose.id, date: date, day: day, count: dose.count, updatedAt: date))
                }
            }
            if offset % 7 == 3 {
                // Overnight to a late breakfast: the day's first meal ends it.
                let date = day.at(minutes: 1260, calendar: calendar)
                fasts.append(Fast(start: date, goalHours: 16, updatedAt: date))
            }
        }

        // A check-in a week, the last of them yesterday, so none is due on the first read.
        var back = 1
        while back <= days {
            let day = today.adding(days: -back)
            let date = day.at(minutes: 480, calendar: calendar)
            checkIns.append(
                CheckIn(
                    id: CheckIn.id(for: day), day: day, expenditure: 2600 + (rng.unit() - 0.5) * 200, kcal: 2500, protein: 170, carbs: 280, fat: 70,
                    status: .updated, reason: "On track.", updatedAt: date))
            back += 7
        }
        checkIns.reverse()

        let moments = Timeline.moments(entries.filter { $0.day == start.adding(days: 1) })
        savedMeals = moments.enumerated().map { index, moment in
            SavedMeal(name: "Meal \(index + 1)", from: moment.entries, updatedAt: moment.end)
        }
    }

    /// What the analysis reads.
    public var state: MacroState {
        MacroState(
            profile: profile, settings: settings, entries: entries, weighIns: weighIns, dayStatus: statuses, plan: plan, checkIns: checkIns,
            supplements: supplements, supplementLogs: supplementLogs, water: water, fasts: fasts, today: today, now: now)
    }

    /// A food this person rotates through, its numbers per serving.
    private struct Staple: Sendable {
        var id: String
        var name: String
        var brand: String?
        var grams: Double
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var processing: Processing

        func entry(at date: Date, day: Day, scale: Double) -> FoodEntry {
            // A label's worth of micros, as a catalog food carries.
            let micros = Self.microKeys.enumerated().reduce(into: [String: Double]()) { result, item in
                result[item.element] = kcal * scale * Double(item.offset + 1) * 0.01
            }
            return FoodEntry(
                date: date, day: day, name: name, brand: brand, foodID: id, amountLabel: "\(Int((grams * scale).rounded())) g",
                grams: grams * scale, unitID: "g", count: grams * scale,
                nutrients: Nutrients(kcal: kcal * scale, protein: protein * scale, carbs: carbs * scale, fat: fat * scale), micros: micros,
                processing: processing, source: .search, updatedAt: date)
        }

        static let microKeys = [
            "fiber", "potassium", "magnesium", "calcium", "iron", "vitaminC", "folate", "vitaminB12", "sodium", "saturatedFat", "vitaminD", "omega3",
            "zinc", "vitaminA",
        ]
    }

    private struct Meal: Sendable {
        var minute: Int
        var foods: Int
        var pool: [Staple]
    }

    private static func staple(
        _ id: Int, _ name: String, _ grams: Double, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, brand: String? = nil
    ) -> Staple {
        Staple(
            id: "long:\(id)", name: name, brand: brand, grams: grams, kcal: kcal, protein: p, carbs: c, fat: f,
            processing: brand == nil ? .whole : .processed)
    }

    /// Twelve foods a day: three at breakfast, lunch and dinner, two with a snack, one late.
    private static let meals: [Meal] = [
        Meal(
            minute: 480, foods: 3,
            pool: [
                staple(1, "Oats", 80, 300, 11, 54, 5), staple(2, "Greek yogurt", 170, 100, 17, 6, 1, brand: "Fage"),
                staple(3, "Banana", 120, 107, 1, 27, 0),
                staple(4, "Eggs", 100, 143, 13, 1, 10), staple(5, "Whole wheat toast", 60, 150, 7, 26, 2),
                staple(6, "Blueberries", 100, 57, 1, 14, 0),
                staple(7, "Coffee", 237, 2, 0, 0, 0), staple(8, "Peanut butter", 32, 190, 8, 7, 16, brand: "Smucker's"),
            ]),
        Meal(
            minute: 750, foods: 3,
            pool: [
                staple(11, "Chicken breast", 150, 248, 46, 0, 5), staple(12, "White rice", 200, 260, 5, 57, 1),
                staple(13, "Broccoli", 90, 31, 3, 6, 0),
                staple(14, "Turkey sandwich", 220, 420, 28, 45, 12, brand: "Jersey Mike's"), staple(15, "Black beans", 130, 170, 11, 31, 1),
                staple(16, "Avocado", 70, 112, 1, 6, 10), staple(17, "Mixed salad", 100, 20, 1, 4, 0), staple(18, "Tuna", 100, 116, 26, 0, 1),
            ]),
        Meal(
            minute: 930, foods: 2,
            pool: [
                staple(21, "Almonds", 30, 174, 6, 6, 15), staple(22, "Apple", 180, 94, 0, 25, 0),
                staple(23, "Protein bar", 60, 210, 20, 22, 7, brand: "Quest"),
                staple(24, "Whey protein", 35, 140, 25, 4, 2, brand: "Optimum Nutrition"), staple(25, "Cottage cheese", 150, 123, 17, 5, 3),
            ]),
        Meal(
            minute: 1140, foods: 3,
            pool: [
                staple(31, "Salmon", 160, 330, 35, 0, 21), staple(32, "Potato", 250, 193, 5, 44, 0), staple(33, "Olive oil", 12, 106, 0, 0, 12),
                staple(34, "Ground beef", 150, 375, 37, 0, 25), staple(35, "Pasta", 180, 284, 10, 56, 2),
                staple(36, "Tomato sauce", 120, 70, 2, 12, 2, brand: "Rao's"),
                staple(37, "Green beans", 100, 35, 2, 8, 0), staple(38, "Tofu", 150, 120, 14, 3, 7),
            ]),
        Meal(
            minute: 1275, foods: 1,
            pool: [
                staple(41, "Dark chocolate", 30, 170, 2, 14, 12, brand: "Lindt"), staple(42, "Casein shake", 35, 120, 24, 3, 1),
                staple(43, "Kiwi", 70, 42, 1, 10, 0),
            ]),
    ]

    /// A meal's foods for a day: a usual first food most days, the rest drawn from what this person
    /// keeps around.
    private static func foods(for meal: Meal, day: Int, using rng: inout SeededRandom) -> [Staple] {
        var pool = meal.pool
        var picked: [Staple] = []
        // The same breakfast for a few weeks, then another: what a person's habits do to the rankings.
        picked.append(pool.remove(at: (day / 21) % pool.count))
        while picked.count < meal.foods { picked.append(pool.remove(at: Int(rng.below(UInt64(pool.count))))) }
        return picked
    }
}

/// SplitMix64: small, seeded and the same everywhere.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func below(_ limit: UInt64) -> UInt64 { next() % limit }
}
#endif
