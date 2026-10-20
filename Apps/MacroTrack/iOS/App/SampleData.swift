#if DEBUG
import Foundation
import FoodDatabase
import MealPlanner
import NutritionEngine
import SystemCore
import SystemStore

/// Three and a half weeks of a believable person: logging most days, weighing in most mornings,
/// eating a little under a true maintenance of 2,600 kcal. Debug builds only (-seedSampleData), and
/// the same person each time: the randomness is seeded.
enum SampleData {
    @MainActor
    static func seedIfEmpty(_ model: AppModel) {
        guard model.entries.isEmpty, model.profile == nil else { return }
        var profile =
            model.sharedProfile
            ?? SharedProfile(
                goals: [.biggerAndStronger, .leaner], schedule: TrainingSchedule(daysPerWeek: 4),
                experience: .intermediate, sex: .male, birthYear: 1991, heightCm: 180,
                units: UnitPreference(weight: .kg, length: .cm), createdBy: .macroTrack)
        profile.updatedAt = Date()
        let days = 24
        let start = Day.today.adding(days: -days)
        model.store.save(ProfileRecord(profile))
        model.store.save(MacroSettings(id: MacroSettings.singletonID, onboardedAt: start.date(), assessmentStart: start, dietHistory: .none))

        // What, how much, and when (hours): three meals and a couple of snacks on most days.
        // -sampleProcessed eats the convenient way instead, for the food-quality views.
        let menu: [(String, Double, Double)] =
            LaunchOptions.current.has("-sampleProcessed")
            ? [
                ("toaster pastries", 100, 8), ("cola", 370, 8.05),
                ("chicken nuggets", 170, 12.5), ("french fries", 130, 12.55),
                ("pepperoni pizza", 220, 19), ("broccoli", 90, 19.05),
                ("whey protein", 35, 15.5), ("apple", 180, 16.5),
            ]
            : [
                ("oats", 80, 8), ("greek yogurt", 170, 8.05), ("banana", 120, 8.1),
                ("chicken breast", 150, 12.5), ("white rice cooked", 200, 12.55), ("broccoli", 90, 12.6),
                ("salmon", 160, 19), ("potato", 250, 19.05), ("olive oil", 12, 19.1),
                ("almonds", 30, 15.5), ("apple", 180, 16.5),
            ]
        var foods: [String: Food] = [:]
        for (query, _, _) in menu where foods[query] == nil {
            if let food = model.catalog.search(query, limit: 1).first?.food { foods[query] = food }
        }

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
                for (query, grams, hour) in menu where Double.random(in: 0...1, using: &rng) < 0.85 {
                    let date = day.at(minutes: Int((hour * 60).rounded()))
                    let scale = Double.random(in: 0.8...1.25, using: &rng)
                    if let food = foods[query] {
                        let unit = PortionUnit(id: "g", label: "g", kind: .mass, amount: 1)
                        let n = food.nutrients(for: grams * scale)
                        eaten += n.kcal
                        entries.append(
                            FoodEntry(
                                date: date, name: food.name, brand: food.brand, foodID: food.id,
                                amountLabel: FoodUnits.label(count: (grams * scale).rounded(), unit: unit), grams: grams * scale,
                                nutrients: n, micros: food.extras(for: grams * scale), processing: food.processing,
                                fermented: food.fermented, source: .search, updatedAt: date))
                    } else {
                        let n = Nutrients(kcal: 220 * scale, protein: 15 * scale, carbs: 22 * scale, fat: 7 * scale)
                        eaten += n.kcal
                        entries.append(
                            FoodEntry(
                                date: date, name: query.capitalized, amountLabel: "\(Int(grams)) g",
                                grams: grams, nutrients: n, source: .search, updatedAt: date))
                    }
                }
                statuses.append(DayStatus(day: day, state: .complete))
            }
            kg += ((eaten > 0 ? eaten : 2300) - 2600) / Energy.kcalPerKg
        }
        model.store.save(entries)
        model.store.save(weighIns)
        model.store.save(statuses)
        model.reload()
        if LaunchOptions.current.has("-seedPlan"), let plan = model.recommendation {
            model.start(plan)
        }
        // A week of meals being eaten from, started yesterday: Today shows its meals.
        if LaunchOptions.current.has("-seedMealPlan") {
            model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: .today.adding(days: -1))
        }
    }

    /// The stack from the design brief, two weeks of it taken, and drinks: fish oil and a
    /// multivitamin in the morning, pre-workout in the afternoon on training days, the multi again
    /// in the evening and a sleep gummy at bedtime; coffee most mornings, an energy drink some
    /// afternoons, and some water. Debug builds only (-seedSupplements).
    @MainActor
    static func seedSupplements(_ model: AppModel) {
        guard model.supplements.isEmpty, model.profile != nil else { return }
        func label(_ query: String, fallback: SupplementFacts) -> SupplementFacts {
            model.supplementCatalog?.search(query, limit: 1).first ?? fallback
        }
        func custom(_ name: String, _ count: Double, _ unit: String, _ lines: [(String, Double, String)]) -> SupplementFacts {
            SupplementFacts(
                id: "custom:\(name)", name: name, servingCount: count, unit: unit,
                ingredients: lines.map { SupplementIngredient(name: $0.0, amount: $0.1, unit: $0.2) }, source: .custom)
        }
        let fish =
            model.supplementCatalog?.supplement(barcode: "031604010539")
            ?? custom("Fish Oil 1200 mg", 1, "softgel", [("Calories", 10, "kcal"), ("EPA", 216, "mg"), ("DHA", 144, "mg")])
        let multi = label(
            "centrum adults multivitamin",
            fallback: custom(
                "Multivitamin", 1, "tablet",
                [
                    ("Vitamin D3", 25, "mcg"), ("Vitamin C", 90, "mg"), ("Zinc", 11, "mg"), ("Magnesium", 50, "mg"), ("Vitamin B12", 25, "mcg"),
                ]))
        let pre = label(
            "c4 original pre workout",
            fallback: custom(
                "Pre-Workout", 1, "scoop",
                [
                    ("Calories", 5, "kcal"), ("Caffeine Anhydrous", 150, "mg"), ("Beta-Alanine", 1.6, "g"),
                ]))
        let sleep = custom("Sleep Gummies", 2, "gummy", [("Calories", 15, "kcal"), ("Magnesium", 50, "mg"), ("Melatonin", 3, "mg")])
        let stack = [
            Supplement(facts: fish, doses: [Dose(time: .morning, count: 2)]),
            Supplement(facts: multi, doses: [Dose(time: .morning, count: 1), Dose(time: .evening, count: 1)]),
            Supplement(facts: pre, doses: [Dose(time: .afternoon, count: 1, days: .trainingDays)]),
            Supplement(facts: sleep, doses: [Dose(time: .bedtime, count: 2)]),
        ]
        model.store.save(stack)
        model.reload()

        var rng = SampleRandom(seed: 14)
        var logs: [SupplementLog] = []
        var drinks: [FoodEntry] = []
        var water: [WaterLog] = []
        let coffee = model.food(id: "usda:171890")
        let energy = model.catalog.food(barcode: "070847811169") ?? model.catalog.search("monster energy", limit: 1).first?.food
        for offset in 1...14 {
            let day = model.today.adding(days: -offset)
            for dose in model.doses(on: day) where Double.random(in: 0...1, using: &rng) < 0.85 {
                let date = day.at(minutes: model.settings.minutes(dose.dose.time)).addingTimeInterval(
                    Double(Int.random(in: -20...40, using: &rng)) * 60)
                logs.append(SupplementLog(supplement: dose.supplement, doseID: dose.dose.id, date: date, day: day, count: dose.dose.count))
            }
            if let coffee {
                for cup in 0..<(Double.random(in: 0...1, using: &rng) < 0.5 ? 2 : 1) {
                    let date = day.at(minutes: 450 + cup * 180)
                    drinks.append(sampleDrink(coffee, ml: 237, date: date, name: "Coffee"))
                }
            }
            if let energy, Double.random(in: 0...1, using: &rng) < 0.4 {
                drinks.append(sampleDrink(energy, ml: 473, date: day.at(hour: 15, minute: 30), name: nil))
            }
            for hour in [9.0, 12.0, 15.0, 18.0] where Double.random(in: 0...1, using: &rng) < 0.7 {
                water.append(WaterLog(date: day.at(minutes: Int(hour * 60)), ml: 500))
            }
        }
        if let coffee { drinks.append(sampleDrink(coffee, ml: 237, date: model.today.at(hour: 7, minute: 30), name: "Coffee")) }
        model.store.save(logs)
        model.store.save(drinks)
        model.store.save(water)
        // Stamped later than the settings it edits, as every settings change is, then reloaded.
        model.updateSettings { $0.tracksDrinks = true }
    }

    /// Meal timing on, with an overnight fast pushed to 16 hours earlier in the week (-seedMealTiming); with
    /// `fast`, a 24-hour fast running from last night's dinner too (-seedFast). Needs Macro Track set
    /// up, which -seedSampleData does.
    @MainActor
    static func seedMealTiming(_ model: AppModel, fast: Bool) {
        guard model.profile != nil else { return }
        model.updateSettings { $0.tracksMealTiming = true }
        // The latest evening at least two days back with its dinner logged.
        let nights = (2...7).map { model.today.adding(days: -$0) }
        let dinners = nights.lazy.compactMap { night in
            MealTiming.lastMeal(before: night.at(hour: 23, minute: 0), entries: model.entries(on: night)).map { (night, $0) }
        }
        if model.fasts.isEmpty, let (night, dinner) = dinners.first(where: { $0.1.end >= $0.0.at(hour: 18, minute: 0) }) {
            // Breakfast skipped, so the fast ran its 16 hours.
            let end = dinner.end.addingTimeInterval(16 * 3600)
            for entry in model.entries(on: night.adding(days: 1)) where entry.date > dinner.end && entry.date < end {
                model.store.delete(FoodEntry.self, id: entry.id)
            }
            model.store.save(Fast(start: dinner.end, goalHours: 16, end: end))
            model.reload()
        }
        if fast, model.analysis?.fast == nil { model.startFast(goalHours: 24) }
    }

    /// The same person every launch (SplitMix64), so screens and UI tests see the same weeks.
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

    @MainActor
    private static func sampleDrink(_ food: Food, ml: Double, date: Date, name: String?) -> FoodEntry {
        let unit = PortionUnit(
            id: food.basis == .ml ? "ml" : "g", label: food.basis == .ml ? "ml" : "g", kind: food.basis == .ml ? .volume : .mass, amount: 1)
        var micros = FoodUnits.micros(food, count: ml, unit: unit)
        if micros["caffeine"] == nil { micros["caffeine"] = Caffeine.estimate(name: food.name, brand: food.brand, grams: ml) }
        return FoodEntry(
            date: date, name: name ?? food.name, brand: food.brand, foodID: food.id, amountLabel: FoodUnits.label(count: ml, unit: unit),
            grams: ml, unitID: unit.id, count: ml, nutrients: FoodUnits.nutrients(food, count: ml, unit: unit), micros: micros,
            processing: food.processing, fermented: food.fermented, fluid: ml, source: .drink, updatedAt: date)
    }
}
#endif
