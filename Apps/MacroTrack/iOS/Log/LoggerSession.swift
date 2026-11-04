import FoodDatabase
import FoodIntelligence
import NutritionEngine
import Observation
import SwiftUI
import SystemCore

/// One logger's state, whichever way it's logging: the one search, the amount open, and what the AI
/// saw, which a host owns so that going off to search for one of its foods doesn't lose it.
@MainActor @Observable
final class LoggerSession {
    var mode: LogMode
    var query = ""
    private(set) var results: [FoodMatch] = []
    /// Which query `results` were found for, and a Return waiting for its rows.
    @ObservationIgnored private var searchReturn = FoodSearchReturn()
    private(set) var searching = false
    var portion: AmountRequest?
    var openMeal: SavedMeal.ID?
    /// What the model saw, being checked.
    var review: MealReview?
    /// The item of the review a search is finding a food for.
    private(set) var finding: UUID?
    /// Asks the host to give the search the keyboard, or take it away.
    private(set) var focusRequest = 0
    private(set) var blurRequest = 0

    init(mode: LogMode) { self.mode = mode }

    private var typedQuery: FoodSearchReturn.Query {
        FoodSearchReturn.Query(text: query.trimmingCharacters(in: .whitespaces), scope: .all)
    }

    func focusSearch() { focusRequest += 1 }
    func blurSearch() { blurRequest += 1 }

    /// Runs the search for what's typed, a beat after the last key.
    func search(_ model: AppModel) async {
        let asked = typedQuery
        let text = asked.text
        searchReturn.typed(asked)
        guard !text.isEmpty else {
            results = []
            _ = searchReturn.arrived(asked, rows: [], selection: nil)
            return
        }
        searching = true
        // A short pause so fast typing doesn't queue a search per keystroke.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        let catalog = model.catalog
        let personal = model.personal
        let found = await Task.detached(priority: .userInitiated) { catalog.search(text, personal: personal, limit: 60) }.value
        guard !Task.isCancelled else { return }
        results = model.corrected(found)
        searching = false
        if searchReturn.arrived(asked, rows: results.map(\.food.id), selection: nil).log, let food = results.first?.food { add(food, model) }
    }

    /// Return in the search: the best match of what's typed. Until those rows are in, the ones on
    /// screen are the last query's, so it waits for them, and goes if the person types on.
    func pressedReturn(_ model: AppModel) {
        let typed = typedQuery
        guard !typed.text.isEmpty, searchReturn.pressed(typed, hasSelection: !results.isEmpty) == .log, let food = results.first?.food else { return }
        add(food, model)
    }

    /// A food at its suggested (or last-used) portion, logged now, and the search cleared for the
    /// next one. While the AI's review is finding a food, this is the one.
    func add(_ food: Food, _ model: AppModel) {
        guard finding == nil else {
            use(food)
            return
        }
        let p = model.personalFood(food.id)
        let suggestion = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount, lastAmount: p?.lastAmount)
        model.log([model.entry(for: food, count: suggestion.count, unit: suggestion.unit, source: .search)])
        query = ""
        focusSearch()
    }

    /// Asked from outside for a way of logging: a widget, a control, a link, the menu or the toolbar.
    /// An amount or a saved meal over it closes, so the ask shows. Asked for the way it's on, what's
    /// there stays. Asked for the way a review is on, it's back at the review. Asked for another,
    /// it starts on that one, without the review.
    func go(to target: LogMode) {
        portion = nil
        openMeal = nil
        if review?.mode == target, mode != target {
            stopFinding()
        } else if mode != target {
            review = nil
            finding = nil
            query = ""
            mode = target
        }
        focusSearch()
    }

    /// Back to the search for the next food: every way of logging ends here, until Done.
    func backToSearch() {
        review = nil
        finding = nil
        query = ""
        mode = .search
        focusSearch()
    }

    /// Off to the search for one of the review's foods, keeping the review to come back to.
    func find(_ text: String, for item: UUID) {
        finding = item
        query = text
        mode = .search
        focusSearch()
    }

    /// The food searched for, in the review's place for it.
    func use(_ food: Food) {
        guard let finding, let review else { return }
        self.review?.items[id: finding]?.swap(to: food)
        self.finding = nil
        query = ""
        mode = review.mode
    }

    /// Back to the review with the item as it was.
    func stopFinding() {
        guard let review else { return }
        finding = nil
        query = ""
        mode = review.mode
    }
}

/// What the model saw in a photo or a description, as it's being checked.
struct MealReview {
    var guess: MealGuess
    var source: EntrySource
    /// Where the review is shown, to come back to.
    var mode: LogMode
    var items: [Item]

    struct Item: Identifiable {
        var id: UUID
        var seen: GuessedItem
        var food: Food?
        var unit: PortionUnit?
        var count: Double
        var included: Bool

        var nutrients: Nutrients {
            if let food, let unit { return FoodUnits.nutrients(food, count: count, unit: unit) }
            return seen.nutrients.scaled(seen.count > 0 ? count / seen.count : 1)
        }

        var amount: String { unit.map { FoodUnits.label(count: count, unit: $0) } ?? Format.number(count) }

        /// Another food for what was seen, at the same unit if it has one, else its usual amount.
        mutating func swap(to food: Food) {
            let units = FoodUnits.units(for: food)
            if let current = unit, let same = units.first(where: { $0.id == current.id }) {
                unit = same
            } else {
                let suggestion = FoodUnits.suggested(for: food)
                unit = suggestion.unit
                count = suggestion.count
            }
            self.food = food
            included = true
        }
    }

    init(guess: MealGuess, source: EntrySource, mode: LogMode, corrected: (Food) -> Food) {
        self.guess = guess
        self.source = source
        self.mode = mode
        // A catalog match the person corrected shows (and logs) their numbers.
        items = guess.items.map { g in
            Item(id: g.id, seen: g, food: g.match.map { corrected($0.food) }, unit: g.unit, count: g.count, included: g.match != nil)
        }
    }
}

extension Array where Element: Identifiable {
    fileprivate subscript(id id: Element.ID) -> Element? {
        get { first { $0.id == id } }
        set {
            guard let newValue, let index = firstIndex(where: { $0.id == id }) else { return }
            self[index] = newValue
        }
    }
}
