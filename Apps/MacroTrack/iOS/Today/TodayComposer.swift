import FoodDatabase
import NutritionEngine
import Observation
import SwiftUI
import SystemCore

/// Today's composer: what's typed, read into foods (`AddFoodText`), the best match for each,
/// and Return logging all of them at once. The person's own foods answer at once; the catalogs
/// answer a beat later, off the main actor, and each query's answer is kept while it's typed.
@MainActor @Observable
final class TodayComposer {
    var text = "" {
        didSet { if text != oldValue { reread() } }
    }
    /// The parts of what's typed, in order.
    private(set) var parts: [AddFoodPart] = []
    /// What the part being typed could be, best first, at the amount typed.
    private(set) var matches: [Candidate] = []
    /// The parts before it, as they'd be logged.
    private(set) var earlier: [Resolved] = []
    /// What everything typed would add, for the header's "→".
    private(set) var adding: Nutrients?
    /// One-tap foods above the field, and what they're for.
    private(set) var tiles: [LogAgainItem] = []
    private(set) var tilesTitle = "Usually around now"
    /// In the evening, with no meal open: one or two usual foods that finish the day, in the
    /// tiles' place.
    private(set) var fits: [WhatFits.Option] = []
    /// Return pressed, the foods it logs being found.
    private(set) var submitting = false

    /// Search answers by query, kept while the composer is up: earlier parts don't search again.
    @ObservationIgnored private var answers: [String: [FoodMatch]] = [:]
    @ObservationIgnored private var personal: [PersonalFood] = []
    @ObservationIgnored private weak var model: AppModel?

    /// A food the composer could log, with the entry it would make.
    struct Candidate: Identifiable, Equatable {
        var entry: FoodEntry
        var food: Food?
        var id: String
        /// Quick add, or words no food matched.
        var kind: Kind

        enum Kind: Equatable {
            case food
            case quickAdd
            case unmatched(String)
        }
    }

    /// A part as it would be logged: its best food's entry, or the words nothing matched.
    struct Resolved: Identifiable, Equatable {
        var id: Int
        var entry: FoodEntry?
        var unmatched: String?
    }

    /// Takes the person's own foods as they are now: on appearing, and whenever they change.
    func attach(_ model: AppModel) {
        self.model = model
        personal = model.personal
        answers = [:]
        reread()
    }

    /// Reads what's typed again, from what's known now: own foods at once, catalog answers kept.
    private func reread() {
        guard let model else { return }
        parts = AddFoodText.parse(text)
        let resolved = parts.enumerated().map { index, part in resolve(part, index: index, model: model) }
        let active = parts.last
        earlier = active.map { _ in Array(resolved.dropLast()) } ?? []
        if let active, active.kind != .typing {
            matches = candidates(for: active, model: model)
        } else {
            matches = []
        }
        let best = matches.first.flatMap { $0.kind == .food || $0.kind == .quickAdd ? $0.entry : nil }
        let entries = earlier.compactMap(\.entry) + (best.map { [$0] } ?? [])
        adding = entries.isEmpty ? nil : Nutrients.sum(entries.map(\.nutrients))
    }

    /// Searches for the parts typed that haven't an answer yet, a beat after the last key.
    func search() async {
        guard let model else { return }
        let queries = Set(parts.filter { $0.kind == .food && !$0.words.isEmpty }.map(\.query)).filter { answers[$0] == nil }
        guard !queries.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        for query in queries {
            let found = await Self.find(query, catalog: model.catalog, personal: personal)
            guard !Task.isCancelled else { return }
            answers[query] = model.corrected(found)
        }
        reread()
    }

    /// The catalogs' answer for a query, with the person's own foods ahead for the same words.
    nonisolated static func find(_ query: String, catalog: FoodCatalog, personal: [PersonalFood]) async -> [FoodMatch] {
        await Task.detached(priority: .userInitiated) {
            let found = catalog.search(query, personal: personal, limit: 12)
            let words = AddFoodText.parse(query).first?.words ?? []
            let scores = Dictionary(personal.map { ($0.food.id, $0.score) }, uniquingKeysWith: max)
            return AddFoodRanking.rank(found, words: words, name: \.food.name, own: { $0.personal ? scores[$0.food.id] ?? 0 : nil })
        }.value
    }

    /// The best foods for a part: what's been found for its words, or meanwhile the person's own
    /// foods that match them.
    private func foods(for part: AddFoodPart) -> [FoodMatch] {
        if let found = answers[part.query] { return found }
        let own = personal.filter { AddFoodRanking.matches(part.words, name: $0.food.name) }.sorted { $0.score > $1.score }
        return own.prefix(3).map { FoodMatch(food: $0.food, score: $0.score, personal: true) }
    }

    private func resolve(_ part: AddFoodPart, index: Int, model: AppModel) -> Resolved {
        switch part.kind {
        case .typing: return Resolved(id: index)
        case .quickAdd(let kcal): return Resolved(id: index, entry: Self.quickAdd(part, kcal: kcal, model: model))
        case .food:
            guard !part.words.isEmpty else { return Resolved(id: index) }
            if let best = foods(for: part).first { return Resolved(id: index, entry: Self.entry(part, food: best.food, model: model)) }
            // Not found yet, or not at all: only once the catalogs have answered is it nothing.
            return Resolved(id: index, unmatched: answers[part.query] == nil ? nil : part.text)
        }
    }

    private func candidates(for part: AddFoodPart, model: AppModel) -> [Candidate] {
        switch part.kind {
        case .typing: return []
        case .quickAdd(let kcal):
            let entry = Self.quickAdd(part, kcal: kcal, model: model)
            return [Candidate(entry: entry, food: nil, id: "quickAdd", kind: .quickAdd)]
        case .food:
            guard !part.words.isEmpty else { return [] }
            let found = foods(for: part).prefix(3)
            if found.isEmpty, answers[part.query] != nil {
                let entry = FoodEntry(date: Date(), name: part.text, amountLabel: "", nutrients: .zero, source: .description)
                return [Candidate(entry: entry, food: nil, id: "unmatched", kind: .unmatched(part.text))]
            }
            return found.map { Candidate(entry: Self.entry(part, food: $0.food, model: model), food: $0.food, id: $0.food.id, kind: .food) }
        }
    }

    // MARK: Logging

    /// Return: every part typed, each as its best food at the amount typed, logged together. The
    /// field clears for the next food, and keeps the keyboard. Words nothing matched go on to the
    /// logger, to be described or searched there.
    func submit() async {
        guard let model, !submitting else { return }
        let typed = AddFoodText.loggable(AddFoodText.parse(text))
        guard !typed.isEmpty else { return }
        submitting = true
        defer { submitting = false }
        var entries: [FoodEntry] = []
        var unmatched: [String] = []
        for part in typed {
            switch part.kind {
            case .typing: continue
            case .quickAdd(let kcal): entries.append(Self.quickAdd(part, kcal: kcal, model: model))
            case .food:
                var found = answers[part.query]
                if found == nil {
                    let answer = model.corrected(await Self.find(part.query, catalog: model.catalog, personal: personal))
                    answers[part.query] = answer
                    found = answer
                }
                if let best = found?.first {
                    entries.append(Self.entry(part, food: best.food, model: model))
                } else {
                    unmatched.append(part.text)
                }
            }
        }
        log(entries, unmatched: unmatched, model: model)
    }

    /// A match tapped: the parts before it as they'd be logged, and this one.
    func log(_ candidate: Candidate) {
        guard let model else { return }
        let before = earlier.compactMap(\.entry)
        switch candidate.kind {
        case .food, .quickAdd: log(before + [candidate.entry], unmatched: earlier.compactMap(\.unmatched), model: model)
        case .unmatched(let words): log(before, unmatched: earlier.compactMap(\.unmatched) + [words], model: model)
        }
    }

    /// A tile: the parts typed before it, and its food at its usual amount, now.
    func log(_ tile: LogAgainItem) {
        guard let model else { return }
        log(earlier.compactMap(\.entry) + [LogAgain.copy(tile.template, to: Date())], unmatched: earlier.compactMap(\.unmatched), model: model)
    }

    private func log(_ entries: [FoodEntry], unmatched: [String], model: AppModel) {
        // Today is always today, whichever day the Log tab was left on. A meal's foods go in a
        // second apart, so they keep the order they were typed in.
        let now = Date()
        let timed = entries.enumerated().map { index, entry in
            var entry = entry
            entry.date = now.addingTimeInterval(Double(index))
            entry.day = Day(entry.date)
            return entry
        }
        text = ""
        if !timed.isEmpty { model.log(timed) }
        if !unmatched.isEmpty { model.openLogger(with: unmatched.joined(separator: ", ")) }
    }

    // MARK: Entries

    /// A part's food at the amount typed: grams, a measure, so many of its own portion, or a
    /// multiple of the usual amount (the last one logged, else the food's own portion).
    static func entry(_ part: AddFoodPart, food: Food, model: AppModel) -> FoodEntry {
        let last = model.personalFood(food.id)
        let usual = FoodUnits.suggested(for: food, lastUnitID: last?.lastUnitID, lastCount: last?.lastCount, lastAmount: last?.lastAmount)
        let amount = part.amount.map { portion($0, food: food, usual: usual) } ?? usual
        return model.entry(for: food, count: amount.count, unit: amount.unit, source: .search)
    }

    /// An amount as typed in one of a food's units. A unit the food can't be counted in falls back
    /// to the usual amount, times the count.
    static func portion(_ amount: AddFoodAmount, food: Food, usual: (unit: PortionUnit, count: Double)) -> (unit: PortionUnit, count: Double) {
        let units = FoodUnits.units(for: food)
        let counted = usual.unit.kind == .portion || usual.unit.kind == .serving
        func unit(_ id: String) -> PortionUnit? { units.first { $0.id == id } }
        let times = (usual.unit, usual.count * amount.count)
        switch amount.portion(counted: counted) {
        case .times(let factor):
            return (usual.unit, usual.count * factor)
        case .basis(let grams):
            if let basis = unit("g") ?? unit("ml") { return (basis, grams) }
            return times
        case .measure(let id, let count):
            if let measure = unit(id) { return (measure, count) }
            // Ounces and pounds are grams by another name, and a spoon or a cup is millilitres.
            let grams = ["oz": 28.3495, "lb": 453.592][id]
            let millilitres = ["cup": 240.0, "tbsp": 15, "tsp": 5][id]
            if let grams, let g = unit("g") { return (g, count * grams) }
            if let millilitres, let ml = unit("ml") ?? unit("g") { return (ml, count * millilitres) }
            return times
        case .pieces(let word, let count):
            let portions = units.filter { $0.kind == .portion }
            if let word, let named = portions.first(where: { $0.label.lowercased().contains(word) }) { return (named, count) }
            if counted { return (usual.unit, count) }
            if let piece = portions.first ?? unit("serving") { return (piece, count) }
            return times
        }
    }

    static func quickAdd(_ part: AddFoodPart, kcal: Double, model: AppModel) -> FoodEntry {
        FoodEntry(
            date: model.logDate(), name: part.words.isEmpty ? "Quick add" : part.words.joined(separator: " ").capitalized,
            amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: 0, carbs: 0, fat: 0), source: .quickAdd)
    }

    // MARK: Tiles

    /// The one-tap foods: what goes with the meal being eaten (one that ended under 45 minutes
    /// ago), else what's usually eaten around now. Neither offers what's in that meal already.
    func refreshTiles(now: Date = Date()) {
        guard let model else { return }
        let today = model.allEntries(on: model.today).filter { $0.date <= now }
        let open = Timeline.moments(today).last.flatMap { now.timeIntervalSince($0.end) < Timeline.gap ? $0 : nil }
        let inMeal = Set(open?.entries.map(Self.key) ?? [])
        var offered: [LogAgainItem] = []
        if let open {
            offered = GoesWith.rank(with: open.entries, entries: model.entries, now: now).filter { !inMeal.contains(Self.key($0.template)) }
        }
        // Named for the meal's main food, the one with the most calories: "Goes with chicken", not
        // with the coffee after it.
        if !offered.isEmpty, let main = open?.entries.max(by: { $0.nutrients.kcal < $1.nutrients.kcal }) {
            tilesTitle = "Goes with \(Self.short(main.name).lowercased())"
        } else {
            tilesTitle = "Usually around now"
            offered = model.logAgain.filter { !inMeal.contains(Self.key($0.template)) }
        }
        tiles = Array(offered.prefix(4))
        fits = open == nil ? Self.fits(model: model, now: now, offered: offered) : []
    }

    /// The most left that "What fits tonight" finishes: more than this is a meal or two to plan.
    static let mostLeftToFit = 1200.0

    /// What fits what's left tonight, from the foods usually eaten now.
    static func fits(model: AppModel, now: Date, offered: [LogAgainItem]) -> [WhatFits.Option] {
        guard WhatFits.isEvening(now), let targets = model.analysis?.targets, let kcal = targets.kcal else { return [] }
        let eaten = model.dayIntake(on: model.today, now: now).eaten
        let left = Nutrients(
            kcal: kcal - eaten.kcal, protein: max(0, (targets.protein ?? 0) - eaten.protein), carbs: max(0, (targets.carbs ?? 0) - eaten.carbs),
            fat: max(0, (targets.fat ?? 0) - eaten.fat))
        guard left.kcal <= mostLeftToFit else { return [] }
        // Pairs from the last eight weeks: what's eaten together now, not years ago.
        let since = model.today.adding(days: -56)
        return WhatFits.options(offered.map(\.template), left: left, history: model.entries.filter { $0.day >= since })
    }

    /// An option of "What fits tonight": its foods at their usual amounts, now.
    func log(_ option: WhatFits.Option) {
        guard let model else { return }
        let now = Date()
        log(option.items.map { LogAgain.copy($0, to: now) }, unmatched: [], model: model)
    }

    static func key(_ entry: FoodEntry) -> String { entry.foodID ?? entry.name.lowercased() }

    /// "Greek yogurt" for "Greek yogurt, plain, lowfat": the name up to its first comma.
    static func short(_ name: String) -> String {
        String(name.split(separator: ",", maxSplits: 1).first ?? Substring(name)).trimmingCharacters(in: .whitespaces)
    }
}
