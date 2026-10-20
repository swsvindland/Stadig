import Foundation
import NutritionEngine
import SystemCore
import SystemStore

extension AppModel {
    /// Meal timing and fasting on Today, Progress and the History.
    var tracksMealTiming: Bool { settings.mealTiming }

    /// Turned off, a running fast ends now: nothing would show it, and it would go on quieting
    /// Today's nudges and holding the check-in.
    func setTracksMealTiming(_ on: Bool) {
        if !on, let running = analysis?.fast?.fast { saveEnd(of: running, at: Date()) }
        updateSettings { $0.tracksMealTiming = on }
    }

    /// Notifications at each phase of a fast and its goal.
    var fastAlerts: Bool { settings.fastAlerts ?? true }

    func setFastAlerts(_ on: Bool) {
        updateSettings { $0.fastAlerts = on }
        if on { Task { _ = await SupplementReminders.requestPermission() } }
    }

    /// Whether a goal this long needs the safety screen first: over a day, until it's been read once.
    func needsFastingScreen(goalHours: Double) -> Bool {
        goalHours > FastSafety.screenHours && settings.fastingScreenSeen == nil
    }

    func acknowledgeFastingScreen(now: Date = Date()) {
        updateSettings { $0.fastingScreenSeen = now }
    }

    /// Why fasts over a day aren't offered to this person (under 18, underweight); nil when they are.
    var fastingBlock: FastSafety.Block? {
        guard let profile else { return nil }
        let weight = analysis?.trend.latest?.trend ?? latestWeighIn?.kg
        return FastSafety.block(profile: profile, weightKg: weight, today: today)
    }

    /// The longest goal this person can set now: a day until the safety notes are read (or for
    /// someone fasts over a day aren't offered to), else a week.
    var longestFast: Double {
        settings.fastingScreenSeen == nil ? min(FastSafety.screenHours, FastSafety.longest(fastingBlock)) : FastSafety.longest(fastingBlock)
    }

    /// Where a fast started now begins: the end of the last meal in the last day, else now.
    func suggestedFastStart(now: Date = Date()) -> Date {
        Fasting.suggestedStart(entries: entries(on: Day(now)) + entries(on: Day(now).adding(days: -1)), now: now)
    }

    /// The earliest a fast running now can have started: the end of the last meal logged before
    /// now (a start before it would be ended by it at once), and at most a week back.
    func earliestFastStart(now: Date = Date()) -> Date {
        let week = now.addingTimeInterval(-7 * 86_400)
        let recent = DayRange(Day(week), Day(now)).days.flatMap { entries(on: $0) }
        return max(week, MealTiming.lastMeal(before: now, entries: recent)?.end ?? week)
    }

    /// Starts a fast toward a goal, from `start` (the last meal's end by default), with Undo.
    /// Nothing happens while one is running: Today and the sheet offer the running one instead.
    @discardableResult
    func startFast(goalHours: Double, start: Date? = nil, now: Date = Date()) -> Bool {
        guard analysis?.fast == nil else { return false }
        let goal = min(max(1, goalHours), longestFast)
        let from = min(max(start ?? suggestedFastStart(now: now), earliestFastStart(now: now)), now)
        let fast = Fast(start: from, goalHours: goal)
        store.save(fast)
        reload()
        toast = Toast(message: "Fasting from \(Format.moment(fast.start, now: now)) · goal \(Format.goal(goal))", fast: .started(fast.id))
        if fastAlerts, usesSystemServices { Task { _ = await SupplementReminders.requestPermission() } }
        return true
    }

    /// Ends the running fast now, with Undo.
    func endFast(at end: Date = Date()) {
        guard let running = analysis?.fast?.fast else { return }
        let ended = saveEnd(of: running, at: end)
        toast = Toast(message: "Fast ended · \(Format.duration(ended.end?.timeIntervalSince(ended.start) ?? 0))", fast: .ended(running))
    }

    @discardableResult
    private func saveEnd(of running: Fast, at end: Date) -> Fast {
        var fast = running
        fast.end = max(fast.start, end)
        fast.updatedAt = Date()
        store.save(fast)
        reload()
        return fast
    }

    /// A fast's start taken back, or its end: running again as it was.
    func undo(_ fast: Toast.FastUndo) {
        switch fast {
        case .started(let id):
            store.delete(Fast.self, id: id)
        case .ended(let before):
            var running = before
            running.end = nil
            running.updatedAt = Date()
            store.save(running)
        }
        reload()
    }

    /// A different goal or start for the running fast. The start can't go back past the last meal
    /// logged before now: that meal would end the fast at once.
    func updateFast(goalHours: Double? = nil, start: Date? = nil, now: Date = Date()) {
        guard var fast = analysis?.fast?.fast else { return }
        if let goalHours { fast.goalHours = min(max(1, goalHours), longestFast) }
        if let start { fast.start = min(max(start, earliestFastStart(now: now)), now) }
        fast.updatedAt = Date()
        store.save(fast)
        reload()
    }

    /// A past fast removed from the record (started by mistake).
    func delete(fast id: UUID) {
        store.delete(Fast.self, id: id)
        reload()
    }

    /// A day's meals and gaps as the analysis reads them: nil for a day whose log isn't trusted.
    func eating(on day: Day) -> EatingDay? {
        guard let analysis, let profile else { return nil }
        if day == today { return analysis.eatingToday }
        let known = Set(analysis.usable.keys)
        guard known.contains(day) else { return nil }
        let nearby = DayRange(day.adding(days: -3), day.adding(days: 1)).days.flatMap { entries(on: $0) }
        let state = MacroState(profile: profile, settings: settings, today: today)
        return MealTiming.days(nearby, in: DayRange(day, day), known: known, bedtime: { state.bedtime(on: $0) }, proteinPerMeal: nil).first
    }

    /// Past fasts, newest first.
    var pastFasts: [FastRun] { (analysis?.fasts ?? []).filter { !$0.isRunning }.reversed() }
}
