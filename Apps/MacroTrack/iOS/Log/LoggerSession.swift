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
    var mode: LogMode {
        // The camera and the photo library are two doors to one way of logging.
        didSet { if mode != oldValue, !(mode.isPhoto && oldValue.isPhoto) { stopRead() } }
    }
    var query = ""
    private(set) var results: [FoodMatch] = []
    /// Which query `results` were found for, and a Return waiting for its rows.
    @ObservationIgnored private var searchReturn = FoodSearchReturn()
    private(set) var searching = false
    var portion: AmountRequest?
    var openMeal: SavedMeal.ID?
    /// What the model saw, being checked. It lasts until it's logged, however many other foods go
    /// in meanwhile: one the model missed is often why the person left it.
    var review: MealReview?
    /// The model reading a photo or a description: one at a time, and only while its way of logging
    /// is on. Left running it would spend Private Cloud Compute's quota on nothing, and land over
    /// whatever the person went on to.
    @ObservationIgnored private(set) var read: Task<Void, Never>?
    private(set) var reading = false
    /// Why the last read came to nothing, in words.
    private(set) var readProblem: String?
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
    /// it starts on that one, without the review. The camera and the photo library are one way of
    /// logging here too: which of them started a review doesn't decide whether it's kept.
    func go(to target: LogMode) {
        portion = nil
        openMeal = nil
        if let review, review.mode.isSameWay(as: target) {
            if !mode.isSameWay(as: target) { stopFinding() }
        } else if mode.isSameWay(as: target) {
            mode = target
        } else {
            review = nil
            finding = nil
            query = ""
            mode = target
        }
        focusSearch()
    }

    /// Reads a photo or a description, in place of any read under way, into a review on this way
    /// of logging.
    func startRead(_ source: EntrySource, _ model: AppModel, _ work: @escaping @MainActor () async -> MealRead) {
        stopRead()
        let startedOn = mode
        reading = true
        read = Task { [weak self] in
            let outcome = await work()
            guard let self, !Task.isCancelled else { return }
            read = nil
            reading = false
            switch outcome {
            case .foods(let guess): review = MealReview(guess: guess, source: source, mode: startedOn, corrected: model.corrected)
            case .nothing(let why): readProblem = why
            }
        }
    }

    /// Stops a read, and the model with it, whatever it would have said: its way of logging was
    /// left, or the logger closed.
    func stopRead() {
        read?.cancel()
        read = nil
        reading = false
        readProblem = nil
    }

    /// Back to the search for the next food: every way of logging ends here, until Done. A review
    /// stays, a tap on its way of logging away.
    func backToSearch() {
        finding = nil
        query = ""
        mode = .search
        focusSearch()
    }

    /// Logs what's ticked in the review, which ends it, and goes on to the next food. If it didn't
    /// save, the toast says so and the review is still there to try again.
    func logReview(_ model: AppModel) {
        guard let review else { return }
        let entries = review.chosen.compactMap { item -> FoodEntry? in
            guard let food = item.food, let unit = item.unit else { return nil }
            return model.entry(
                for: food, count: item.count, unit: unit, source: review.source, confidence: item.seen.sure && !item.seen.approximate ? 0.8 : 0.5)
        }
        guard model.log(entries) else { return }
        self.review = nil
        backToSearch()
    }

    /// A food corrected from an amount. The correction is saved whether or not that amount is then
    /// used, so wherever the review has the food, it shows and logs the new numbers.
    func useCorrection(_ food: Food) {
        guard let items = review?.items else { return }
        for index in items.indices where items[index].food?.id == food.id { review?.items[index].correct(to: food) }
    }

    /// What the review has of each food, read again: a food changed anywhere else (from the hours,
    /// from the meal, on another device) shows and logs its new numbers here too.
    func refreshFoods(_ model: AppModel) {
        guard let items = review?.items else { return }
        for index in items.indices {
            guard let food = items[index].food, let current = model.food(id: food.id), current != food else { continue }
            review?.items[index].correct(to: current)
        }
    }

    /// Another of what the model thought it might be, as that food stands now: what it thought was
    /// read back when the photo was, and may have been corrected since.
    func swap(_ item: UUID, to food: Food, _ model: AppModel) {
        review?.items[id: item]?.swap(to: model.food(id: food.id) ?? food)
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

    /// What Log again offers: finding a food for a review, only what's one food can be its answer.
    func again(_ items: [LogAgainItem]) -> [LogAgainItem] {
        finding == nil ? items : items.filter { $0.template.foodID != nil }
    }

    /// The + on Log again: the same food and amount, or the food being found for the review.
    func addAgain(_ item: LogAgainItem, model: AppModel) {
        guard finding != nil else {
            model.logAgain(item)
            return
        }
        if let food = item.template.foodID.flatMap(model.food(id:)) { use(food) }
    }

    /// Back to the review with the item as it was.
    func stopFinding() {
        guard let review else { return }
        finding = nil
        query = ""
        mode = review.mode
    }
}

extension LogMode {
    var isPhoto: Bool { self == .camera || self == .photoLibrary }

    /// The same way of logging, by either door.
    func isSameWay(as other: LogMode) -> Bool { self == other || (isPhoto && other.isPhoto) }
}

/// What a read of a photo or a description came to.
enum MealRead {
    /// Foods to check.
    case foods(MealGuess)
    /// Why there's nothing to check, in words.
    case nothing(String)
}

/// What the model saw in a photo or a description, as it's being checked.
struct MealReview {
    var guess: MealGuess
    var source: EntrySource
    /// Where the review is shown, to come back to.
    var mode: LogMode
    var items: [Item]

    /// What Log would log: ticked, and matched to a food.
    var chosen: [Item] { items.filter { $0.included && $0.food != nil } }

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

        /// The same food with the person's numbers, at the same count of the same unit, as an amount
        /// being picked for it keeps (`AmountDraft.use`), though one counted in calories holds a
        /// different amount now. A food corrected to no calories can't be counted in them, so it
        /// goes to its basis at the same amount.
        mutating func correct(to corrected: Food) {
            food = corrected
            let units = FoodUnits.units(for: corrected)
            guard let old = unit else { return }
            if let same = units.first(where: { $0.id == old.id }) {
                unit = same
            } else if let basis = units.first(where: { $0.id == corrected.basis.rawValue }) {
                let converted = FoodUnits.convert(count, from: old, to: basis)
                if converted.isFinite { count = converted }
                unit = basis
            }
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
