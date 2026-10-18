import CoreGraphics
import FoodDatabase
import Foundation
import SystemCore

/// One of Apple's models behind the two requests a meal needs. The FoundationModels engines
/// conform; tests script one.
protocol MealModel: Sendable {
    var engine: MealEngine { get }
    /// The first pass: the foods in a photo and/or description.
    func readMeal(instructions: String, prompt: String, image: CGImage?) async throws -> MealReply
    /// The second, text-only pass: an entry number per near-tied food.
    func pick(instructions: String, prompt: String, foods: Int) async throws -> [Pick]
}

/// A meal before timing and engine are added.
struct MealDraft: Sendable {
    var scene: String?
    var isFood: Bool
    var items: [GuessedItem]
}

/// The two-pass analysis: the model names foods and amounts, the catalog supplies everything
/// else, and the model is asked again only to settle near-ties.
enum MealAnalysis {
    static func run(
        description: String, image: CGImage?, personal: [PersonalFood], reader: any MealModel,
        picker: (any MealModel)?, catalog: any MealCatalog
    ) async throws -> MealDraft {
        let photo = image != nil
        let clock = ContinuousClock()
        let start = clock.now
        let reply = try await reader.readMeal(
            instructions: Prompts.mealInstructions,
            prompt: Prompts.meal(description: description, photo: photo), image: image)
        let seen = SeenFoods.read(reply, description: description, photo: photo)
        let scene = reply.scene.map { FoodText.clean($0) }?.nilIfEmpty
        Trace.note(
            "read \(reader.engine) in \(clock.now - start): scene \(scene ?? "-") food \(reply.food.map(String.init) ?? "-"), "
                + "items \(reply.items.map { "\($0.brand) \($0.name) \($0.quantity) \($0.unit) \($0.grams ?? 0)g" }) → seen \(seen.map(\.name))")
        guard !seen.isEmpty else { return MealDraft(scene: scene, isFood: false, items: []) }
        let looking = clock.now
        let found = await candidates(for: seen, catalog: catalog, personal: personal)
        Trace.note("catalog in \(clock.now - looking)")
        let asked = Matching.asked(found)
        var picks: [Pick] = []
        if !asked.isEmpty, let picker {
            let meal = [scene, description.nilIfEmpty].compactMap { $0 }.joined(separator: ". ")
            let asking = clock.now
            do {
                picks = try await picker.pick(
                    instructions: Prompts.pickInstructions,
                    prompt: Matching.pickPrompt(seen: seen, found: found, asked: asked, meal: meal), foods: asked.count)
                Trace.note("picked \(picks.map { "\($0.food):\($0.entry)" }) for \(asked.map { seen[$0].name }) in \(clock.now - asking)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The ranked first choices are a usable draft on their own.
                Trace.note("pick failed in \(clock.now - asking): \(error)")
            }
        }
        for (food, row) in zip(seen, found) {
            Trace.note(
                "  \(food.name): sure \(row.sure) tied \(row.tied) "
                    + row.matches.prefix(4).map { "\($0.food.name) [\($0.score)]" }.joined(separator: " | "))
        }
        let chosen = Matching.choices(picks, found: found, asked: asked)
        let items = seen.indices.map { Drafting.item(seen[$0], found[$0], chosen: chosen[$0], said: description, meal: seen, catalog: catalog) }
        return MealDraft(scene: scene, isFood: true, items: items)
    }

    /// Catalog lookups for every seen food at once; the catalog is thread-safe and synchronous.
    static func candidates(for seen: [SeenFood], catalog: any MealCatalog, personal: [PersonalFood]) async -> [Candidates] {
        await withTaskGroup(of: (Int, Candidates).self) { group in
            for (i, food) in seen.enumerated() {
                group.addTask { (i, Matching.candidates(for: food, catalog: catalog, personal: personal)) }
            }
            var found = [Candidates](repeating: Candidates(matches: [], tied: 0, sure: false), count: seen.count)
            for await (i, row) in group { found[i] = row }
            return found
        }
    }
}

/// Step-by-step notes for evaluation, off unless a task sets a receiver.
enum Trace {
    @TaskLocal static var receiver: (@Sendable (String) -> Void)?

    static func note(_ message: @autoclosure () -> String) { receiver?(message()) }

    static func note(_ message: () -> String) { receiver?(message()) }
}

/// A seen food and its match as a guessed diary item.
enum Drafting {
    /// `meal` is every food seen with this one.
    static func item(_ seen: SeenFood, _ found: Candidates, chosen: Int?, said: String, meal: [SeenFood] = [], catalog: any MealCatalog)
        -> GuessedItem
    {
        let brand = seen.brand.nilIfEmpty
        guard let chosen, found.matches.indices.contains(chosen) else {
            return GuessedItem(
                seenName: seen.label ?? seen.name, seenBrand: brand, match: nil, alternatives: [], unit: nil, count: seen.quantity,
                nutrients: .zero, sure: false, approximate: true)
        }
        let match = found.matches[chosen]
        let resolved = Amounts.resolve(seen, food: match.food)
        let (unit, count) = portionUnit(for: resolved, food: match.food, units: catalog.units(for: match.food))
        return GuessedItem(
            seenName: seen.label ?? seen.name, seenBrand: brand, match: match,
            alternatives: Matching.alternatives(found.matches, chosen: chosen, branded: brand != nil),
            unit: unit, count: count, nutrients: FoodUnits.nutrients(match.food, count: count, unit: unit),
            sure: found.sure, approximate: !resolved.exact || !stated(seen, in: said, among: meal))
    }

    /// The catalog's own unit for a resolved amount, so the portion editor opens on it: the same id
    /// ("g", "floz", "portion:2"), else the same name. A catalog unit is trusted for its size;
    /// without one, a unit of the same size and id is made.
    static func portionUnit(for resolved: ResolvedAmount, food: Food, units: [PortionUnit]) -> (PortionUnit, Double) {
        func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= max(abs(a), abs(b)) * tolerance }
        switch resolved.unit {
        case .basis:
            let (key, kind): (String, PortionUnit.Kind) =
                switch food.basis {
                case .g: ("g", .mass)
                case .ml: ("ml", .volume)
                case .serving: ("serving", .serving)
                }
            let unit =
                units.first { $0.id == key }
                ?? units.first { $0.kind == kind && near($0.amount, 1, 0.001) && Measures.unitKey($0.label) == key }
                ?? units.first { $0.kind == kind && near($0.amount, 1, 0.001) }
                ?? PortionUnit(id: key, label: key, kind: kind, amount: 1)
            return (unit, round(resolved.amount / unit.amount))
        case .measure(let key, let perUnit):
            let kind: PortionUnit.Kind =
                Measures.weights[key] != nil
                ? .mass
                : Measures.volumes[key] != nil
                    ? .volume
                    : key == "kcal" ? .energy : .serving
            if let unit = units.first(where: { $0.id == key }) ?? units.first(where: { $0.kind == kind && Measures.unitKey($0.label) == key }) {
                return (unit, resolved.count)
            }
            return (PortionUnit(id: key, label: key == "floz" ? "fl oz" : key, kind: kind, amount: perUnit), resolved.count)
        case .portion(let index, let label, let perUnit):
            let own = units.filter { $0.kind == .portion || $0.kind == .serving }
            let head = FoodText.words(label).first ?? label
            if let unit = own.first(where: { $0.id == "portion:\(index)" }) ?? own.first(where: { $0.label.lowercased() == label })
                ?? own.first(where: { near($0.amount, perUnit, 0.01) && FoodText.words($0.label).first == head })
            {
                return (unit, resolved.count)
            }
            return (PortionUnit(id: "portion:\(index)", label: label, kind: .portion, amount: perUnit), resolved.count)
        }
    }

    private static func round(_ count: Double) -> Double { (count * 100).rounded() / 100 }

    private static let countTokens: Set<String> = [
        "a", "an", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "dozen", "half", "couple", "single", "pair",
    ]
    private static let sizeTokens: Set<String> = ["small", "medium", "large", "big", "jumbo", "extra", "regular", "whole", "mini", "of"]
    private static let leadingDigits = Pattern(#"^[\d.]+"#)

    /// Whether the person said how much: the unit ("2 slices", "8 oz", "a can of") or a count right
    /// before the food ("two eggs", "a banana"). A unit said of another of the meal's foods ("toast
    /// and 2 slices of bacon") is that food's. A photo's amount, or one the model chose, is a guess.
    static func stated(_ seen: SeenFood, in said: String, among meal: [SeenFood] = []) -> Bool {
        let tokens = FoodText.tokens(said)
        guard !tokens.isEmpty else { return false }
        let unit = Measures.unitKey(seen.unit)
        func stems(_ food: SeenFood) -> [String] { FoodText.nameWords(food.name).map(FoodText.stem) }
        func naming(_ words: [String], _ names: [String]) -> Bool {
            names.contains { name in words.contains { FoodText.same($0, name) || FoodText.same(name, $0) } }
        }
        let names = stems(seen)
        if unit != "piece" {
            let others = meal.filter { $0 != seen }.map(stems)
            for segment in StatedAmounts.segments(said) {
                let words = FoodText.tokens(segment)
                for (i, token) in words.enumerated() where Measures.unitKey(leadingDigits.replacing(in: token, with: "")) == unit {
                    // "Ate 3 slices" and "a can of soda" name no other food, so they can be this one's.
                    let after = words[(i + 1)...].filter { !FoodText.stopWords.contains($0) }.map(FoodText.stem)
                    if naming(after, names) || !others.contains(where: { naming(after, $0) }) { return true }
                }
            }
        }
        for (i, token) in tokens.enumerated() where countTokens.contains(token) || Double(token) != nil {
            var j = i + 1
            while j < tokens.count, sizeTokens.contains(tokens[j]) { j += 1 }
            guard j < tokens.count else { continue }
            let word = FoodText.stem(tokens[j])
            if names.contains(where: { FoodText.same(word, $0) || FoodText.same($0, word) }) { return true }
        }
        return false
    }
}
