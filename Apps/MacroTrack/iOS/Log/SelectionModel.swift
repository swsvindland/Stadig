import Foundation
import NutritionEngine
import SystemCore

/// The foods picked out on the Log tab, and what an hour's button or a target does with them. It
/// survives a change of day, which is how a food is taken to another one.
struct LogSelection: Equatable {
    enum Intent: Equatable { case move, copy }

    var ids: Set<UUID> = []
    var intent: Intent = .move

    var isEmpty: Bool { ids.isEmpty }
}

extension AppModel {
    /// The foods selected, earliest first.
    var selectedEntries: [FoodEntry] { selection.isEmpty ? [] : foodLog.all.filter { selection.ids.contains($0.id) } }

    func toggleSelection(_ entry: FoodEntry) {
        if selection.ids.remove(entry.id) == nil { selection.ids.insert(entry.id) }
    }

    /// An hour's foods: a tap starts or extends the selection, so a partly selected hour selects
    /// the rest, and a whole one lets go.
    func toggleSelection(_ group: HourGroup) {
        let ids = Set(group.entries.map(\.id))
        if ids.isSubset(of: selection.ids) { selection.ids.subtract(ids) } else { selection.ids.formUnion(ids) }
    }

    /// From the entry selected last to this one, in the day's order: ⇧-click.
    func extendSelection(to entry: FoodEntry) {
        let day = allEntries(on: entry.day)
        let selected = day.indices.filter { selection.ids.contains(day[$0].id) }
        guard let target = day.firstIndex(of: entry), let anchor = selected.min(by: { abs($0 - target) < abs($1 - target) }) else {
            toggleSelection(entry)
            return
        }
        selection.ids.formUnion(day[min(anchor, target)...max(anchor, target)].map(\.id))
    }

    func clearSelection() { selection = LogSelection() }

    /// One food picked out to take elsewhere, from its amount.
    func select(_ entry: FoodEntry, intent: LogSelection.Intent) { selection = LogSelection(ids: [entry.id], intent: intent) }

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
