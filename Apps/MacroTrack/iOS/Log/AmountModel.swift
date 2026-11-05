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
        /// An amount chosen for something else, handed back: a food of the AI's review, by its id.
        case pick(item: UUID, count: Double, unit: PortionUnit)
    }

    var purpose: Purpose
    var food: Food?

    var id: String {
        switch purpose {
        case .add: "add-\(food?.id ?? "")"
        case .edit(let entry): "edit-\(entry.id)"
        case .pick(let item, _, _): "pick-\(item)"
        }
    }

    static func add(_ food: Food, source: EntrySource) -> AmountRequest { AmountRequest(purpose: .add(source), food: food) }

    static func edit(_ entry: FoodEntry) -> AmountRequest { AmountRequest(purpose: .edit(entry)) }

    var entry: FoodEntry? {
        if case .edit(let entry) = purpose { return entry }
        return nil
    }
}

/// What the amount panel holds while it's open: the amount, the food it's of and the units it can
/// be counted in. It's apart from the view so what the panel says and what it saves can't drift.
struct AmountDraft {
    var amount = AmountEntry(count: 1, unit: nil)
    private(set) var entry: FoodEntry?
    private(set) var food: Food?
    private(set) var units: [PortionUnit] = []
    /// The amount as it reopened, so a change of time alone saves the entry's own numbers.
    private var original: (unitID: String?, count: Double)?
    /// Choosing an amount for a row that already has one, which stays beside its count.
    private var picking = false

    init() {}

    init(entry: FoodEntry?, food: Food?, amount: AmountEntry, picking: Bool = false) {
        self.entry = entry
        self.food = food
        self.amount = amount
        self.picking = picking
        original = (amount.unit?.id, amount.count ?? 1)
        if let food { units = Self.offered(FoodUnits.units(for: food), first: amount.unit) }
    }

    /// Filled in from a request, which happens once: reading it again would lose what's typed.
    var isOpen: Bool { original != nil }

    /// Whether the amount was changed, rather than only the time.
    var amountChanged: Bool {
        guard let original else { return true }
        return amount.unit?.id != original.unitID || abs((amount.count ?? 0) - original.count) > 1e-9
    }

    /// What saving would store. An entry keeps its numbers until its amount changes, even when its
    /// food reads differently now, because Save does.
    var nutrients: Nutrients {
        if let entry, !amountChanged { return entry.nutrients }
        let count = amount.count ?? 0
        if let food, let unit = amount.unit { return FoodUnits.nutrients(food, count: count, unit: unit) }
        return entry?.nutrients.scaled(count) ?? .zero
    }

    /// The food as corrected (or the catalog's again). Its units are the same ones, but calories
    /// hold a different amount now, and a food corrected to no calories can't be counted in them.
    mutating func use(_ corrected: Food) {
        let kept = picking || (entry != nil && !amountChanged)
        let all = FoodUnits.units(for: corrected)
        func current(_ unit: PortionUnit?) -> PortionUnit? { all.first { $0.id == unit?.id } }
        food = corrected
        units = Self.offered(all, first: current(units.first))
        if let unit = current(amount.unit) ?? all.first(where: { $0.id == corrected.basis.rawValue }) {
            // An entry staying as logged stays beside the number it was logged at, or the panel
            // would read 150 kcal over a Save of 120. A review's row keeps its count the same way
            // (`MealReview.Item.correct`), so closing the panel and tapping Use agree.
            if kept, unit.id == amount.unit?.id, let count = amount.count {
                amount = AmountEntry(count: count, unit: unit)
            } else {
                amount.change(to: unit)
            }
        }
        if kept { original = (amount.unit?.id, amount.count ?? 1) }
    }

    /// The one it opened in, then the food's own order, which starts with its natural portions.
    private static func offered(_ all: [PortionUnit], first: PortionUnit?) -> [PortionUnit] {
        guard let first else { return all }
        return [first] + all.filter { $0.id != first.id }
    }
}

extension AppModel {
    /// A request as the panel opens it: an entry in the unit it was logged in, a food at its usual
    /// amount, and an amount being picked as it stands.
    func draft(for request: AmountRequest) -> AmountDraft {
        if let entry = request.entry {
            guard let id = entry.foodID, let found = food(id: id) else {
                return AmountDraft(entry: entry, food: nil, amount: AmountEntry(count: 1, unit: nil))
            }
            // In the unit it was logged in while that still holds the amount logged, else the
            // food's basis counting that amount: a catalog update can reorder or reword portions.
            let reopened = FoodUnits.logged(for: found, unitID: entry.unitID, count: entry.count, amount: entry.grams)
            return AmountDraft(entry: entry, food: found, amount: AmountEntry(count: reopened.count, unit: reopened.unit))
        }
        if case .pick(_, let count, let unit) = request.purpose {
            return AmountDraft(entry: nil, food: request.food, amount: AmountEntry(count: count, unit: unit), picking: true)
        }
        guard let food = request.food else { return AmountDraft(entry: nil, food: nil, amount: AmountEntry(count: 1, unit: nil)) }
        let personal = personalFood(food.id)
        let suggestion = FoodUnits.suggested(
            for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
        return AmountDraft(entry: nil, food: food, amount: AmountEntry(count: suggestion.count, unit: suggestion.unit))
    }

    /// The entry as the panel has it. A change of time alone keeps the entry's own numbers.
    func edited(_ draft: AmountDraft, at date: Date) -> FoodEntry? {
        guard var entry = draft.entry, let count = draft.amount.count else { return nil }
        if draft.amountChanged { entry = rescaled(entry, food: draft.food, unit: draft.amount.unit, count: count) }
        entry.date = date
        return entry
    }

    /// Picks the entry out to take elsewhere, with whatever the panel changed saved first: a food
    /// goes as it stands there, and the panel closing shouldn't lose what's typed.
    func take(_ draft: AmountDraft, at date: Date, intent: LogSelection.Intent) {
        guard let entry = draft.entry else { return }
        if draft.amountChanged || date != entry.date, let edited = edited(draft, at: date) { update(edited) }
        select(entry, intent: intent)
    }

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
