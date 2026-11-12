#if DEBUG
import Foundation
import FoodDatabase
import FoodIntelligence
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
        // -sampleEmptyYesterday leaves yesterday's food out, for Today's "Catch up".
        let skipped = LaunchOptions.current.has("-sampleEmptyYesterday") ? start.adding(days: days - 1) : nil
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
            // The draw is made either way, so the other days stay the same person's.
            if Double.random(in: 0...1, using: &rng) < 0.85, day != skipped {
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
        // Breakfast and lunch saved as meals, as the person would from the last time each was eaten whole.
        let moments = Timeline.moments(entries)
        for (name, queries) in [
            ("Oats and yogurt", ["oats", "greek yogurt", "banana"]), ("Chicken and rice", ["chicken breast", "white rice cooked", "broccoli"]),
        ] {
            let ids = Set(queries.compactMap { foods[$0]?.id })
            // -sampleNoMeals: for Foods' Meals with nothing saved yet.
            guard !LaunchOptions.current.has("-sampleNoMeals"), ids.count == queries.count,
                let moment = moments.last(where: { ids.isSubset(of: $0.entries.compactMap(\.foodID)) })
            else { continue }
            model.store.save(SavedMeal(name: name, from: moment.entries.filter { $0.foodID.map(ids.contains) ?? false }, updatedAt: moment.end))
        }
        model.reload()
        if LaunchOptions.current.has("-seedPlan"), let plan = model.recommendation {
            model.start(plan)
        }
        // A week of meals being eaten from, started yesterday: Today shows its meals.
        if LaunchOptions.current.has("-seedMealPlan") {
            model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: .today.adding(days: -1))
        }
    }

    /// Food logged ahead: dinner later today if there's a later today, then lunch and dinner on the
    /// next two days. Debug builds only (-seedUpcoming; it needs -seedSampleData).
    @MainActor
    static func seedUpcoming(_ model: AppModel) {
        func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
            FoodEntry(
                date: date, name: name, amountLabel: "1 serving",
                nutrients: Nutrients(kcal: kcal, protein: kcal / 15, carbs: kcal / 9, fat: kcal / 30),
                source: .search)
        }
        let today = model.today
        var foods: [FoodEntry] = []
        let dinner = today.at(hour: 19, minute: 0)
        if dinner > Date() { foods.append(food("Salmon and rice", kcal: 650, at: dinner)) }
        for offset in 1...2 {
            let day = today.adding(days: offset)
            foods.append(food("Chicken salad", kcal: 480, at: day.at(hour: 12, minute: 30)))
            foods.append(food("Pasta bake", kcal: 720, at: day.at(hour: 19, minute: 0)))
        }
        model.store.save(foods)
        model.reload()
    }

    /// Today eaten as yesterday was up to 5 PM, where that time has passed: breakfast, lunch and the
    /// afternoon snacks, so an evening has dinner left to fit (-seedToday).
    @MainActor
    static func seedToday(_ model: AppModel, now: Date = Date()) {
        let yesterday = model.today.adding(days: -1)
        let copies = model.allEntries(on: yesterday).compactMap { entry -> FoodEntry? in
            let clock = Calendar.current.dateComponents([.hour, .minute], from: entry.date)
            guard (clock.hour ?? 0) < 17 else { return nil }
            let date = model.today.at(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
            return date < now ? LogAgain.copy(entry, to: date) : nil
        }
        model.store.save(copies)
        model.reload()
    }

    /// Years of the same log (`LongHistory`), through the real store, to see the app with a long
    /// history and measure it. Debug builds only (-seedLongHistory, 5 years unless a number follows).
    @MainActor
    static func seedLongHistory(_ model: AppModel, years: Int) {
        guard model.entries.isEmpty, model.profile == nil else { return }
        let history = LongHistory(years: years)
        var settings = history.settings
        settings.id = MacroSettings.singletonID
        model.store.save(ProfileRecord(history.profile))
        model.store.save(settings)
        model.store.save(history.plan)
        model.store.save(history.entries)
        model.store.save(history.weighIns)
        model.store.save(history.statuses)
        model.store.save(history.checkIns)
        model.store.save(history.supplements)
        model.store.save(history.supplementLogs)
        model.store.save(history.water)
        model.store.save(history.fasts)
        model.store.save(history.savedMeals)
        model.reload()
    }

    /// A meal as if the model had read it, ready to check, since a simulator may have no model.
    /// Debug builds only (-seedReview, with -log describe): one of the person's own foods at 300
    /// kcal, and something it couldn't match.
    @MainActor
    static func seedReview(_ session: LoggerSession, _ model: AppModel) {
        guard LaunchOptions.current.has("-seedReview"), session.review == nil else { return }
        let name = "Beef stew"
        let stew =
            model.customFoods.first { $0.food.name == name }?.food
            ?? model.save(
                customFood: Food(
                    id: "seed-stew", name: name, basis: .serving, nutrients: Nutrients(kcal: 300, protein: 25, carbs: 20, fat: 13), source: .custom))
        guard let serving = FoodUnits.units(for: stew).first else { return }
        let seen = [
            GuessedItem(
                seenName: name, seenBrand: nil, match: FoodMatch(food: stew, score: 1, personal: true), alternatives: [], unit: serving, count: 1,
                nutrients: stew.nutrients, sure: true, approximate: false),
            GuessedItem(
                seenName: "Mystery sauce", seenBrand: nil, match: nil, alternatives: [], unit: nil, count: 1, nutrients: .zero, sure: false,
                approximate: true),
        ]
        let guess = MealGuess(scene: nil, isFood: true, items: seen, engine: .onDevice, seconds: 1)
        session.review = MealReview(guess: guess, source: .description, mode: session.mode, corrected: model.corrected)
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
        // With its barcode, catalog or not: a UI test scans it.
        var fishOil = custom("Fish Oil 1200 mg", 1, "softgel", [("Calories", 10, "kcal"), ("EPA", 216, "mg"), ("DHA", 144, "mg")])
        fishOil.barcode = "00031604010539"
        let fish = model.supplementCatalog?.supplement(barcode: "031604010539") ?? fishOil
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
    /// `fast`, a 24-hour fast running from last night's dinner too (-seedFast). Needs Stadig Macro set
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
