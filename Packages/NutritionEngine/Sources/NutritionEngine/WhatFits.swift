import Foundation
import SystemCore

/// "What fits tonight": in the evening, one or two of the foods usually eaten now that fit what's
/// left of the day, for one tap. Protein first, then filling the calories without going over.
public enum WhatFits {
    /// One way to finish the day: its foods at their usual amounts, and what's left after them.
    public struct Option: Hashable, Sendable, Identifiable {
        public var items: [FoodEntry]
        public var nutrients: Nutrients
        /// Calories left after it; negative is over.
        public var leaves: Double
        /// Within `onTarget` of the day's calories.
        public var onTarget: Bool

        public var id: String { items.map { $0.foodID ?? $0.name }.joined(separator: "+") }
    }

    /// The hour from which the day's last meal is the one being planned.
    public static let eveningHour = 17
    /// Close enough to the target to call it there, in kcal.
    public static let onTarget = 60.0
    /// Food smaller than this isn't a meal to suggest (black coffee, a pinch of salt).
    public static let smallest = 40.0

    /// Whether it's the evening at `now`, when the last meal is the one left.
    public static func isEvening(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= eveningHour
    }

    /// Up to `limit` options from `candidates` (best first, as Log again ranks them for now), each
    /// one food or two, that don't go over `left` calories (give or take `onTarget`) and fill at
    /// least a quarter of them. Two foods go together only if they've been eaten in the same
    /// moment in `history` (when it's given): salmon and potatoes, not salmon and chicken. Ranked
    /// by the protein they cover of what's left (going well past it counts against them), then by
    /// how closely they fill the calories; an option's foods are offered once.
    public static func options(_ candidates: [FoodEntry], left: Nutrients, history: [FoodEntry]? = nil, limit: Int = 3) -> [Option] {
        guard left.kcal >= 150 else { return [] }
        var seen = Set<String>()
        let foods = candidates.filter { $0.nutrients.kcal >= smallest && seen.insert(LogAgain.key($0)).inserted }.prefix(10)
        let together = history.map(pairs)
        var combos: [[FoodEntry]] = foods.map { [$0] }
        for (i, a) in foods.enumerated() {
            for b in foods.dropFirst(i + 1) where together?.contains(pair(LogAgain.key(a), LogAgain.key(b))) ?? true {
                combos.append([a, b])
            }
        }
        let scored = combos.compactMap { items -> (Option, Double)? in
            let total = Nutrients.sum(items.map(\.nutrients))
            let leaves = left.kcal - total.kcal
            guard leaves >= -onTarget, total.kcal >= left.kcal * 0.25 else { return nil }
            let protein = left.protein > 0 ? (min(total.protein, left.protein) - max(0, total.protein - left.protein) / 2) / left.protein : 0
            let fill = 1 - abs(leaves) / left.kcal
            let option = Option(items: items, nutrients: total, leaves: leaves, onTarget: abs(leaves) <= onTarget)
            return (option, protein * 2 + fill)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
        var used = Set<String>()
        var chosen: [Option] = []
        for (option, _) in scored where chosen.count < limit {
            let keys = option.items.map(LogAgain.key)
            guard keys.allSatisfy({ !used.contains($0) }) else { continue }
            used.formUnion(keys)
            chosen.append(option)
        }
        return chosen
    }

    /// Every two foods eaten in the same moment, by `LogAgain`'s keys.
    static func pairs(_ history: [FoodEntry]) -> Set<String> {
        var pairs = Set<String>()
        for (_, day) in Dictionary(grouping: history, by: \.day) {
            for moment in Timeline.moments(day) {
                let keys = Set(moment.entries.map(LogAgain.key)).sorted()
                for (i, a) in keys.enumerated() {
                    for b in keys.dropFirst(i + 1) { pairs.insert(pair(a, b)) }
                }
            }
        }
        return pairs
    }

    static func pair(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }
}
