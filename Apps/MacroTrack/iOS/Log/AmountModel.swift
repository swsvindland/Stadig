import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore

/// What the amount panel is doing: adding a food, or changing an entry already logged. The panel
/// holds no navigation of its own, so a sheet, an inspector or a pane can each show it.
struct AmountRequest: Identifiable, Hashable {
    enum Purpose: Hashable {
        case add(EntrySource)
        case edit(FoodEntry)
    }

    var purpose: Purpose
    var food: Food?
    var closeAfterAdd = false

    var id: String {
        switch purpose {
        case .add: "add-\(food?.id ?? "")"
        case .edit(let entry): "edit-\(entry.id)"
        }
    }

    static func add(_ food: Food, source: EntrySource, closeAfterAdd: Bool = false) -> AmountRequest {
        AmountRequest(purpose: .add(source), food: food, closeAfterAdd: closeAfterAdd)
    }

    static func edit(_ entry: FoodEntry) -> AmountRequest { AmountRequest(purpose: .edit(entry)) }

    var entry: FoodEntry? {
        if case .edit(let entry) = purpose { return entry }
        return nil
    }
}

extension AppModel {
    /// An entry at a new amount, with what it knew beyond the food scaling along with it (a drink's
    /// caffeine, when the catalog didn't list it, and its fluid). A food that's gone from the catalog,
    /// or never was in it (a quick add, an estimate), scales by `count` as a multiplier.
    func rescaled(_ entry: FoodEntry, food: Food?, unit: PortionUnit?, count: Double) -> FoodEntry {
        var updated = entry
        if let food, let unit {
            let amount = FoodUnits.amount(count, unit)
            var micros = FoodUnits.micros(food, count: count, unit: unit)
            let ratio = entry.grams.flatMap { $0 > 0 ? amount / $0 : nil }
            if micros["caffeine"] == nil, let mg = entry.micros?["caffeine"], let ratio { micros["caffeine"] = mg * ratio }
            updated.nutrients = FoodUnits.nutrients(food, count: count, unit: unit)
            updated.micros = micros
            updated.fluid = entry.fluid.map { fluid in ratio.map { fluid * $0 } ?? fluid }
            updated.amountLabel = FoodUnits.entryLabel(for: food, count: count, unit: unit, estimate: entry.isEstimate)
            updated.grams = amount
            updated.unitID = unit.id
            updated.count = count
        } else if count != 1 {
            updated.nutrients = entry.nutrients.scaled(count)
            updated.micros = entry.micros?.mapValues { $0 * count }
            updated.fluid = entry.fluid.map { $0 * count }
            updated.amountLabel = "\(Format.number(count, digits: 2)) × \(entry.amountLabel)"
            updated.grams = entry.grams.map { $0 * count }
        }
        return updated
    }
}

/// The 0.5–2× choices on an amount.
enum AmountChoices {
    /// Half, one, one and a half and two of the usual amount, each rounded the way that unit is
    /// measured (quarters of a cup or a portion, tenths of an ounce or a pound, whole grams),
    /// without repeats.
    static func quick(base: Double, unit: PortionUnit) -> [Double] {
        var seen = Set<Double>()
        return [0.5, 1, 1.5, 2].map { FoodUnits.convert(base * $0, from: unit, to: unit) }.filter { $0.isFinite && seen.insert($0).inserted }
    }

    /// A weight or volume with its unit ("0.5 lb", "150 g"), a count of portions on its own.
    static func label(_ value: Double, unit: PortionUnit) -> String {
        unit.kind == .mass || unit.kind == .volume ? FoodUnits.label(count: value, unit: unit) : Format.number(value, digits: 2)
    }

    /// The same for an entry with no unit, as multiples of what was logged.
    static let multipliers: [Double] = [0.5, 1, 1.5, 2]

    /// Half, one, one and a half and two times: what a person sees for an entry with no food.
    static func label(multiplier: Double) -> String { "\(Format.number(multiplier, digits: 2))×" }
}
