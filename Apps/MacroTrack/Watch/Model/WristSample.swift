#if DEBUG
import Foundation
import NutritionEngine
import SystemCore
import SystemStore

/// The phone's sample person, for the Watch: three and a half weeks of logging most days and
/// weighing in most mornings, a little under a true maintenance of 2,600 kcal, and today logged up
/// to now (lunch at the latest, so there's room left). There's no food catalog on the Watch, so the
/// foods carry their USDA numbers. The same person every launch: the randomness is seeded.
///
/// `-seedSampleData` fills an empty store; `-seedPlan` also starts the recommended plan, so today
/// has calorie targets; `-seedSupplements` adds a stack due through the day, two weeks of it taken,
/// coffee and water, with drinks turned on; `-imperial` weighs in pounds; `-page logAgain|water|
/// supplements|weigh` opens a page; `-seedHour 9` logs today's food up to that hour (breakfast, here),
/// whatever the time (before then, dated a minute ago).
enum WristSample {
    /// What, how much, when (hours) and its numbers: three meals and two snacks.
    private static let menu: [(name: String, amount: String, grams: Double, hour: Double, n: Nutrients)] = [
        ("Oats", "100 g", 100, 8, Nutrients(kcal: 379, protein: 13, carbs: 68, fat: 6.5)),
        ("Greek yogurt", "200 g", 200, 8.05, Nutrients(kcal: 118, protein: 20.6, carbs: 7.2, fat: 0.8)),
        ("Banana", "1 medium", 118, 8.1, Nutrients(kcal: 105, protein: 1.3, carbs: 27, fat: 0.4)),
        ("Chicken breast", "200 g", 200, 12.5, Nutrients(kcal: 330, protein: 62, carbs: 0, fat: 7.2)),
        ("White rice", "1½ cups", 250, 12.55, Nutrients(kcal: 325, protein: 6.8, carbs: 70, fat: 0.7)),
        ("Broccoli", "1 cup", 100, 12.6, Nutrients(kcal: 35, protein: 2.4, carbs: 7.2, fat: 0.4)),
        ("Almonds", "40 g", 40, 15.5, Nutrients(kcal: 232, protein: 8.5, carbs: 8.6, fat: 20)),
        ("Apple", "1 medium", 182, 16.5, Nutrients(kcal: 95, protein: 0.5, carbs: 25, fat: 0.3)),
        ("Salmon", "180 g", 180, 19, Nutrients(kcal: 371, protein: 39.7, carbs: 0, fat: 22)),
        ("Baked potato", "300 g", 300, 19.05, Nutrients(kcal: 279, protein: 7.5, carbs: 63, fat: 0.4)),
        ("Olive oil", "1 tbsp", 14, 19.1, Nutrients(kcal: 124, protein: 0, carbs: 0, fat: 14)),
        ("Whey protein", "1 scoop", 31, 21, Nutrients(kcal: 120, protein: 24, carbs: 3, fat: 1.5)),
    ]

    @MainActor
    static func apply(_ launch: LaunchOptions, to model: WristModel) {
        if launch.has("-seedSampleData") { seedIfEmpty(model, launch: launch) }
        if launch.has("-seedSupplements") { seedSupplements(model) }
    }

    @MainActor
    private static func seedIfEmpty(_ model: WristModel, launch: LaunchOptions) {
        guard !model.onboarded, model.store.all(FoodEntry.self).isEmpty else { return }
        let now = Date()
        let today = Day(now)
        let days = 24
        let start = today.adding(days: -days)
        let imperial = launch.has("-imperial")
        let profile = SharedProfile(
            goals: [.biggerAndStronger, .leaner], schedule: TrainingSchedule(daysPerWeek: 4), experience: .intermediate, sex: .male,
            birthYear: 1991, heightCm: 180, units: UnitPreference(weight: imperial ? .lb : .kg, length: imperial ? .inch : .cm),
            createdBy: .macroTrack)
        var rng = SampleRandom(seed: 2_600)
        var kg = 84.0
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        for i in 0..<days {
            let day = start.adding(days: i)
            if Double.random(in: 0...1, using: &rng) < 0.9 {
                let water = i < 7 ? 0.8 * (1 - Double(i) / 7) : 0
                weighIns.append(WeighIn(date: day.at(hour: 7, minute: 0), kg: kg + water + Double.random(in: -0.5...0.5, using: &rng)))
            }
            var eaten = 0.0
            if Double.random(in: 0...1, using: &rng) < 0.85 {
                for food in menu where Double.random(in: 0...1, using: &rng) < 0.92 {
                    let entry = entry(food, on: day, scale: Double.random(in: 0.9...1.2, using: &rng))
                    eaten += entry.nutrients.kcal
                    entries.append(entry)
                }
                statuses.append(DayStatus(day: day, state: .complete))
            }
            kg += ((eaten > 0 ? eaten : 2_300) - 2_600) / Energy.kcalPerKg
        }
        // Today so far, up to lunch (or up to `-seedHour`'s hour, whatever the time).
        let hour =
            launch.value(after: "-seedHour").flatMap(Double.init)
            ?? Double(Calendar.current.component(.hour, from: now)) + Double(Calendar.current.component(.minute, from: now)) / 60
        for food in menu where food.hour < min(hour, 15) {
            var eaten = entry(food, on: today, scale: 1)
            // With `-seedHour` early in the day, what's "eaten" by then is dated by now, so it counts.
            if eaten.date > now { eaten.date = max(today.date(), now.addingTimeInterval(-60)) }
            entries.append(eaten)
        }
        weighIns.append(WeighIn(date: today.at(hour: 7, minute: 0), kg: kg))
        model.seed { store in
            store.save(ProfileRecord(profile))
            store.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: start.date(), assessmentStart: start, dietHistory: .none))
            store.save(entries)
            store.save(weighIns)
            store.save(statuses)
        }
        guard launch.has("-seedPlan"), let analysis = model.analyseNow() else { return }
        // As the phone starts a plan: the recommendation, and its first targets straight from the
        // maintenance estimate.
        let plan = PhasePlanner.recommend(analysis.plannerInput)
        let checkIn = CheckIns.start(
            plan, today: today, maintenance: analysis.maintenance.kcal, weightKg: analysis.trend.latest?.trend ?? kg,
            referenceKg: analysis.referenceKg)
        model.seed { store in
            store.save(plan)
            store.save(checkIn)
        }
    }

    private static func entry(
        _ food: (name: String, amount: String, grams: Double, hour: Double, n: Nutrients), on day: Day, scale: Double
    ) -> FoodEntry {
        let date = day.at(minutes: Int((food.hour * 60).rounded()))
        let label = scale == 1 ? food.amount : "\(Int((food.grams * scale).rounded())) g"
        return FoodEntry(
            date: date, name: food.name, amountLabel: label, grams: food.grams * scale, nutrients: food.n.scaled(scale), source: .search,
            updatedAt: date)
    }

    /// A fish oil and a multivitamin in the morning, creatine at midday, the multi again in the
    /// evening and magnesium at bedtime, two weeks of them taken; coffee most mornings and water
    /// through the day, with drinks turned on. Today's fish oil is taken; the rest is still to do.
    @MainActor
    private static func seedSupplements(_ model: WristModel) {
        guard model.onboarded, model.store.all(Supplement.self).isEmpty else { return }
        func facts(_ name: String, _ count: Double, _ unit: String, _ lines: [(String, Double, String)]) -> SupplementFacts {
            SupplementFacts(
                id: "custom:\(name)", name: name, servingCount: count, unit: unit,
                ingredients: lines.map { SupplementIngredient(name: $0.0, amount: $0.1, unit: $0.2) }, source: .custom)
        }
        let fish = Supplement(
            facts: facts("Fish Oil", 1, "softgel", [("Calories", 10, "kcal"), ("EPA", 216, "mg"), ("DHA", 144, "mg")]),
            doses: [Dose(time: .morning, count: 2)])
        let multi = Supplement(
            facts: facts("Multivitamin", 1, "tablet", [("Vitamin D3", 25, "mcg"), ("Vitamin C", 90, "mg"), ("Zinc", 11, "mg")]),
            doses: [Dose(time: .morning), Dose(time: .evening)])
        let creatine = Supplement(facts: facts("Creatine", 1, "scoop", [("Creatine Monohydrate", 5, "g")]), doses: [Dose(time: .midday)])
        let magnesium = Supplement(
            facts: facts("Magnesium Glycinate", 2, "capsule", [("Magnesium", 200, "mg")]), doses: [Dose(time: .bedtime, count: 2)])
        let stack = [fish, multi, creatine, magnesium]

        let now = Date()
        let today = Day(now)
        var rng = SampleRandom(seed: 14)
        var logs: [SupplementLog] = []
        var drinks: [FoodEntry] = []
        var water: [WaterLog] = []
        for offset in 1...14 {
            let day = today.adding(days: -offset)
            for supplement in stack {
                for dose in supplement.doses where Double.random(in: 0...1, using: &rng) < 0.85 {
                    let date = day.at(minutes: dose.time.defaultMinutes + Int.random(in: -20...40, using: &rng))
                    logs.append(SupplementLog(supplement: supplement, doseID: dose.id, date: date, day: day, count: dose.count))
                }
            }
            if Double.random(in: 0...1, using: &rng) < 0.8 { drinks.append(coffee(day.at(hour: 7, minute: 30))) }
            for hour in [9, 12, 15, 18] where Double.random(in: 0...1, using: &rng) < 0.7 {
                water.append(WaterLog(date: day.at(hour: hour, minute: 0), ml: 500))
            }
        }
        let morning = today.at(hour: 8, minute: 15)
        if now > morning {
            logs.append(SupplementLog(supplement: fish, doseID: fish.doses[0].id, date: morning, day: today, count: 2))
            drinks.append(coffee(today.at(hour: 7, minute: 30)))
        }
        for hour in [9, 12] where now > today.at(hour: hour, minute: 0) {
            water.append(WaterLog(date: today.at(hour: hour, minute: 0), ml: 500))
        }
        let settings = MacroSettings.inForce(model.store.all(MacroSettings.self))
        model.seed { store in
            store.save(stack)
            store.save(logs)
            store.save(drinks)
            store.save(water)
            if var settings {
                settings.tracksDrinks = true
                settings.updatedAt = Date()
                store.save(settings)
            }
        }
    }

    /// A cup of brewed coffee, as the phone's Coffee button logs it.
    private static func coffee(_ date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: "Coffee", amountLabel: "1 cup", grams: 237, nutrients: Nutrients(kcal: 2, protein: 0.3, carbs: 0, fat: 0),
            micros: ["caffeine": 95], fluid: 237, source: .drink, updatedAt: date)
    }

    /// The same person every launch (SplitMix64), as on the phone.
    struct SampleRandom: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
#endif
