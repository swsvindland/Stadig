import FoodDatabase
import Foundation
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore

/// A drink one tap logs: a catalog food at a usual size.
struct QuickDrink: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var foodID: String
    /// Millilitres (grams) of the usual size.
    var ml: Double

    /// Brewed coffee, a double espresso and black or green tea, from USDA, which lists their caffeine.
    static let standard = [
        QuickDrink(id: "coffee", name: "Coffee", symbol: "cup.and.saucer.fill", foodID: "usda:171890", ml: 237),
        QuickDrink(id: "espresso", name: "Espresso", symbol: "cup.and.heat.waves.fill", foodID: "usda:171891", ml: 59),
        QuickDrink(id: "tea", name: "Tea", symbol: "mug.fill", foodID: "usda:173227", ml: 237),
        QuickDrink(id: "green-tea", name: "Green tea", symbol: "leaf.fill", foodID: "usda:171917", ml: 245),
    ]
}

extension AppModel {
    var tracksDrinks: Bool { settings.drinks }

    /// Imperial people drink in fluid ounces.
    var fluidOunces: Bool { units.weight == .lb }

    /// A glass and a bottle, in the person's units.
    var waterSizes: [(label: String, ml: Double)] {
        fluidOunces ? [("8 oz", 236.6), ("16.9 oz", 500)] : [("Glass", 250), ("Bottle", 500)]
    }

    func addWater(ml: Double) {
        let log = WaterLog(date: drinkDate(), ml: ml)
        store.save(log)
        reload()
        toast = Toast(message: "Water · \(Format.volume(ml, ounces: fluidOunces))", undoWater: [log.id])
        if settings.saveToHealth {
            Task {
                await HealthBridge.shared.saveFoods([
                    HealthFood(
                        id: log.id, date: log.date, name: "Water", nutrients: .zero, micros: ["water": ml],
                        version: Int(log.updatedAt.timeIntervalSince1970 * 1000))
                ])
            }
        }
    }

    func delete(water ids: [UUID]) {
        for id in ids { store.delete(WaterLog.self, id: id) }
        reload()
        Task { await HealthBridge.shared.deleteFoods(ids: ids) }
    }

    /// Now, or this time of day on a day being caught up. The logger's picked time isn't used:
    /// a drink tapped on Today is drunk now.
    private func drinkDate() -> Date {
        let now = Date()
        guard selectedDay != today else { return now }
        return selectedDay.at(sameTimeAs: now)
    }

    /// One tap on a standard drink: logged as food, so its calories and caffeine count.
    func log(_ drink: QuickDrink) {
        guard let food = food(id: drink.foodID) else { return }
        let units = FoodUnits.units(for: food)
        // The unit nearest the usual size, in a whole or half count of it.
        let unit =
            units.filter { $0.kind != .energy && $0.amount > 0 }
            .min { abs(log2($0.amount / drink.ml)) < abs(log2($1.amount / drink.ml)) } ?? PortionUnit(id: "g", label: "g", kind: .mass, amount: 1)
        let count = max(0.5, (drink.ml / unit.amount * 2).rounded() / 2)
        var entry = entry(for: food, count: count, unit: unit, source: .drink)
        entry.name = drink.name
        entry.date = drinkDate()
        entry.day = Day(entry.date)
        log([entry])
    }

    /// The person's own drinks, most logged first: one tap logs the same again.
    var usualDrinks: [FoodEntry] {
        let standard = Set(QuickDrink.standard.map(\.foodID))
        var seen = Set(QuickDrink.standard.map { $0.name.lowercased() })
        var scored: [String: (score: Double, entry: FoodEntry)] = [:]
        let now = Date()
        for entry in entries where entry.date > now.addingTimeInterval(-60 * 86400) && Hydration.fluid(of: entry) != nil {
            if let id = entry.foodID, standard.contains(id), entry.source == .drink { continue }
            let key = entry.foodID ?? entry.name.lowercased()
            let weight = pow(0.5, now.timeIntervalSince(entry.date) / (21 * 86400))
            let current = scored[key]
            scored[key] = ((current?.score ?? 0) + weight, current.map { $0.entry.date > entry.date ? $0.entry : entry } ?? entry)
        }
        return scored.values.sorted { $0.score > $1.score }.map(\.entry).filter { seen.insert($0.name.lowercased()).inserted }.prefix(6).map { $0 }
    }

    func logAgain(drink entry: FoodEntry) {
        log([LogAgain.copy(entry, to: drinkDate(), source: .drink)])
    }

    // MARK: Caffeine

    /// Starts a cut-back from the week's average to a goal, a step a week. The daily limit is left
    /// as it is: the report takes the lower of it and this week's step, so the steps apply.
    func startCutBack(from: Double, goal: Double) {
        let start = today
        updateSettings { $0.caffeineCutBack = CaffeineCutBack(start: start, from: from, goal: goal) }
    }

    /// Stops a cut-back. Once the goal's been reached it stays as the daily limit; stopped before
    /// then, the limit is what it was.
    func endCutBack() {
        let today = today
        updateSettings { s in
            if let cut = s.caffeineCutBack, today >= cut.reachesGoal { s.caffeineLimit = cut.goal }
            s.caffeineCutBack = nil
        }
    }

    func setTracksDrinks(_ on: Bool) {
        updateSettings { $0.tracksDrinks = on }
        // Water is a new kind of sample for Health to allow.
        if on { Task { _ = await HealthBridge.shared.requestAuthorization(.nutrition) } }
    }
}

extension Format {
    /// "1.2 L", "350 ml", "40 fl oz".
    static func volume(_ ml: Double, ounces: Bool) -> String {
        if ounces { return "\(Int((ml / 29.5735).rounded())) fl oz" }
        return ml >= 1000 ? "\(number(ml / 1000, digits: 1)) L" : "\(Int(ml.rounded())) ml"
    }

    /// "245 mg".
    static func mg(_ value: Double) -> String { "\(Int(value.rounded())) mg" }
}
