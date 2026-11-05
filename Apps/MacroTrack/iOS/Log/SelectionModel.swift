import Foundation
import NutritionEngine
import SystemCore

/// The foods picked out on the Log tab, and what an hour's button or a target does with them. It
/// survives a change of day, which is how a food is taken to another one.
struct LogSelection: Equatable {
    enum Intent: Equatable { case move, copy }

    var ids: Set<UUID> = []
    var intent: Intent = .move
    /// The food picked out last, which ⇧-click extends from.
    var anchor: UUID?

    var isEmpty: Bool { ids.isEmpty }
}

extension AppModel {
    /// The foods selected, earliest first.
    var selectedEntries: [FoodEntry] { selection.isEmpty ? [] : foodLog.all.filter { selection.ids.contains($0.id) } }

    func toggleSelection(_ entry: FoodEntry) {
        if selection.ids.remove(entry.id) == nil {
            selection.ids.insert(entry.id)
            selection.anchor = entry.id
        }
    }

    /// An hour's foods: a tap starts or extends the selection, so a partly selected hour selects
    /// the rest, and a whole one lets go.
    func toggleSelection(_ group: HourGroup) {
        let ids = Set(group.entries.map(\.id))
        if ids.isSubset(of: selection.ids) { selection.ids.subtract(ids) } else { selection.ids.formUnion(ids) }
    }

    /// A meal's foods, the same way.
    func toggleSelection(_ meal: Moment) {
        let ids = Set(meal.entries.map(\.id))
        if ids.isSubset(of: selection.ids) { selection.ids.subtract(ids) } else { selection.ids.formUnion(ids) }
    }

    /// From the food picked out last to this one, through what's between them on screen: ⇧-click.
    /// With that one no longer picked out or not on this day, from the nearest that is.
    func extendSelection(to entry: FoodEntry, in order: DayOrder = .time) {
        let all = allEntries(on: entry.day)
        let rows = order.listed(all) ?? all
        guard let target = rows.firstIndex(where: { $0.id == entry.id }) else { return toggleSelection(entry) }
        let last = selection.anchor.flatMap { id in selection.ids.contains(id) ? rows.firstIndex { $0.id == id } : nil }
        let selected = rows.indices.filter { selection.ids.contains(rows[$0].id) }
        guard let anchor = last ?? selected.min(by: { abs($0 - target) < abs($1 - target) }) else { return toggleSelection(entry) }
        selection.ids.formUnion(rows[min(anchor, target)...max(anchor, target)].map(\.id))
    }

    func clearSelection() { selection = LogSelection() }

    /// One food picked out to take elsewhere, from its amount.
    func select(_ entry: FoodEntry, intent: LogSelection.Intent) { selection = LogSelection(ids: [entry.id], intent: intent, anchor: entry.id) }

    /// Takes the selection to a place by its intent: a move ends the selection, and a copy keeps it,
    /// so the same foods can go to another day next.
    func placeSelection(_ placement: Placement, named name: String) {
        let chosen = selectedEntries
        guard !chosen.isEmpty else { return }
        let dates = Placing.dates(for: chosen, placement)
        switch selection.intent {
        case .move:
            move(chosen, to: dates, message: "Moved \(foods(chosen.count)) to \(name)")
            clearSelection()
        case .copy:
            copy(chosen, to: dates, message: "Copied \(foods(chosen.count)) to \(name)")
        }
    }

    /// Takes the selection to chosen days, each food at its own time of day. A move goes to the
    /// first of them and leaves copies on the rest.
    func placeSelection(on days: [Day]) {
        let chosen = selectedEntries
        guard !chosen.isEmpty, let first = days.sorted().first else { return }
        let rest = days.sorted().dropFirst()
        let name = days.count == 1 ? dayName(first) : "\(days.count) days"
        let copies = rest.flatMap { day in
            zip(chosen, Placing.dates(for: chosen, .sameTimes(on: day))).map { LogAgain.copy($0, to: $1, source: .copied) }
        }
        let dates = Placing.dates(for: chosen, .sameTimes(on: first))
        if selection.intent == .move {
            move(chosen, to: dates, leaving: copies, message: "Moved \(foods(chosen.count)) to \(name)")
            clearSelection()
        } else {
            copy(chosen, to: dates, also: copies, message: "Copied \(foods(chosen.count)) to \(name)")
        }
    }

    func deleteSelection() {
        delete(entries: selectedEntries.map(\.id))
        clearSelection()
    }

    /// "today", "tomorrow", "Mon, Nov 2": how a toast names a day.
    func dayName(_ day: Day) -> String {
        day == today.adding(days: 1) ? "tomorrow" : Format.relative(day, today: today)
    }

    private func foods(_ count: Int) -> String { count == 1 ? "1 food" : "\(count) foods" }

    /// Moves foods, leaving `copies` on other days, with one toast for it all: its Undo puts the
    /// foods back and takes the copies away. If the copies can't be saved, nothing moves.
    private func move(_ entries: [FoodEntry], to dates: [Date], leaving copies: [FoodEntry] = [], message: String) {
        let fast = fasts.last
        let before = fast.flatMap(fastRun)
        guard copies.isEmpty || log(copies) else { return }
        let moved = zip(entries, dates).map { entry, date in
            var entry = entry
            entry.date = date
            return entry
        }
        update(moved, message: message)
        toast?.undo = copies.map(\.id)
        noteFastChange(fast, from: before)
    }

    private func copy(_ entries: [FoodEntry], to dates: [Date], also more: [FoodEntry] = [], message: String) {
        log(zip(entries, dates).map { LogAgain.copy($0, to: $1, source: .copied) } + more, message: message)
    }

    /// Says so in the toast when moving food ended a fast, or set one running again.
    private func noteFastChange(_ fast: Fast?, from before: FastRun?) {
        guard let fast, let before, let after = fastRun(fast), before.isRunning != after.isRunning else { return }
        if after.isRunning {
            toast?.message += " · your fast is running again"
        } else if let end = after.end {
            toast?.message += " · ended your \(Format.duration(after.duration(at: end))) fast"
        }
    }
}
