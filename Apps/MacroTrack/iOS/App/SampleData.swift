#if DEBUG
import Foundation
import FoodDatabase
import NutritionEngine
import SystemCore
import SystemStore

/// Three and a half weeks of a believable person: logging most days, weighing in most mornings,
/// eating a little under a true maintenance of 2,600 kcal. Debug builds only (-seedSampleData).
enum SampleData {
    @MainActor
    static func seedIfEmpty(_ model: AppModel) {
        guard model.entries.isEmpty, model.profile == nil else { return }
        var profile = model.sharedProfile ?? SharedProfile(goals: [.biggerAndStronger, .leaner], schedule: TrainingSchedule(daysPerWeek: 4),
                                                           experience: .intermediate, sex: .male, birthYear: 1991, heightCm: 180,
                                                           units: UnitPreference(weight: .kg, length: .cm), createdBy: .macroTrack)
        profile.updatedAt = Date()
        let days = 24
        let start = Day.today.adding(days: -days)
        model.store.save(ProfileRecord(profile))
        model.store.save(MacroSettings(onboardedAt: start.date(), assessmentStart: start, dietHistory: .none))

        // What, how much, and when (hours): three meals and a couple of snacks on most days.
        let menu: [(String, Double, Double)] = [
            ("oats", 80, 8), ("greek yogurt", 170, 8.05), ("banana", 120, 8.1),
            ("chicken breast", 150, 12.5), ("white rice cooked", 200, 12.55), ("broccoli", 90, 12.6),
            ("salmon", 160, 19), ("potato", 250, 19.05), ("olive oil", 12, 19.1),
            ("almonds", 30, 15.5), ("apple", 180, 16.5),
        ]
        var foods: [String: Food] = [:]
        for (query, _, _) in menu where foods[query] == nil {
            if let food = model.catalog.search(query, limit: 1).first?.food { foods[query] = food }
        }

        var rng = SystemRandomNumberGenerator()
        var kg = 84.0
        var entries: [FoodEntry] = []
        var weighIns: [WeighIn] = []
        var statuses: [DayStatus] = []
        for i in 0..<days {
            let day = start.adding(days: i)
            if Double.random(in: 0...1, using: &rng) < 0.9 {
                let water = i < 7 ? 0.8 * (1 - Double(i) / 7) : 0
                weighIns.append(WeighIn(date: day.date().addingTimeInterval(7 * 3600), kg: kg + water + Double.random(in: -0.5...0.5, using: &rng)))
            }
            var eaten = 0.0
            if Double.random(in: 0...1, using: &rng) < 0.85 {
                for (query, grams, hour) in menu where Double.random(in: 0...1, using: &rng) < 0.85 {
                    let date = day.date().addingTimeInterval(hour * 3600)
                    let scale = Double.random(in: 0.8...1.25, using: &rng)
                    if let food = foods[query] {
                        let unit = PortionUnit(id: "g", label: "g", kind: .mass, amount: 1)
                        let n = food.nutrients(for: grams * scale)
                        eaten += n.kcal
                        entries.append(FoodEntry(date: date, name: food.name, brand: food.brand, foodID: food.id,
                                                 amountLabel: FoodUnits.label(count: (grams * scale).rounded(), unit: unit), grams: grams * scale,
                                                 nutrients: n, micros: food.extras(for: grams * scale), source: .search, updatedAt: date))
                    } else {
                        let n = Nutrients(kcal: 220 * scale, protein: 15 * scale, carbs: 22 * scale, fat: 7 * scale)
                        eaten += n.kcal
                        entries.append(FoodEntry(date: date, name: query.capitalized, amountLabel: "\(Int(grams)) g",
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
        if ProcessInfo.processInfo.arguments.contains("-seedPlan"), let plan = model.recommendation {
            model.start(plan)
        }
    }
}
#endif
