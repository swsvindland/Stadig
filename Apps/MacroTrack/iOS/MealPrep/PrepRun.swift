import Foundation
import MealPlanner
import Observation

/// Prep day being cooked at the counter: the step the cook is on, when each step was done (a pot or
/// a tray's timer runs from its Next), and what the scale read. The guide and the dishes are taken
/// when prep starts, so the steps don't move under the cook, and readings always apply to the
/// dishes as planned.
@Observable
final class PrepRun {
    /// One thing cooking by itself, from its step's Next until it's taken off the rail.
    struct Timer: Identifiable, Equatable {
        var id: Int
        var name: String
        var place: String
        var ends: Date
        var seconds: TimeInterval
    }

    let planID: UUID
    let guide: PrepGuide
    /// The dishes when prep started.
    let planned: [PlannedRecipe]
    let started: Date
    private(set) var index = 0
    /// When each step was done, by step id.
    private(set) var done: [Int: Date] = [:]
    /// Timers taken off the rail.
    private(set) var cleared: Set<Int> = []
    /// Timers that have rung.
    private(set) var rung: Set<Int> = []
    private(set) var readings = PrepReadings()
    /// The dishes with every reading so far: what each container holds.
    private(set) var weighed: [PlannedRecipe]
    /// The dishes as the readings were last saved into the plan, by recipe id.
    @ObservationIgnored var saved: [String: PlannedRecipe] = [:]

    init(plan: MealPlan, now: Date) {
        planID = plan.id
        guide = PrepGuide.make(for: plan)
        planned = plan.recipes
        weighed = plan.recipes
        started = now
    }

    var step: PrepStep { guide.steps[index] }
    var next: PrepStep? { index + 1 < guide.steps.count ? guide.steps[index + 1] : nil }
    var isLast: Bool { index == guide.steps.count - 1 }

    /// The current step's done; on to the next. A step that cooks by itself starts its timer now.
    func advance(at now: Date) {
        done[step.id] = now
        if index + 1 < guide.steps.count { index += 1 }
    }

    /// Back a step, undoing its Next: its timer comes off.
    func back() {
        guard index > 0 else { return }
        index -= 1
        done[step.id] = nil
        rung.remove(step.id)
        cleared.remove(step.id)
    }

    /// What the scale read for a step's batch, or the plan's amount until it's set.
    func reading(for step: PrepStep) -> Double {
        readings.grams[step.id] ?? (step.weigh?.grams ?? 0).rounded()
    }

    /// A reading back at the plan's amount is no reading: the dishes are as planned again. One the
    /// batch couldn't be (a slip of the finger) is ignored.
    func read(_ grams: Double, for step: PrepStep) {
        guard let weigh = step.weigh, grams.isFinite else { return }
        let grams = grams.rounded()
        guard weigh.accepts(grams) else { return }
        readings.grams[step.id] = abs(grams - weigh.grams) < 0.5 ? nil : grams
        weighed = readings.apply(to: planned, guide: guide)
    }

    /// What this step's reading does to each container it fills.
    func changes(for step: PrepStep) -> [PrepChange] {
        readings.changes(for: step, in: planned, guide: guide)
    }

    /// What's cooking: every timed step that's been put on and not taken off, the soonest done first.
    var timers: [Timer] {
        guide.steps.compactMap { step in
            guard let timer = step.timer, let start = done[step.id], !cleared.contains(step.id) else { return nil }
            let seconds = TimeInterval(step.minutes * 60)
            return Timer(id: step.id, name: timer.name, place: timer.place, ends: start.addingTimeInterval(seconds), seconds: seconds)
        }
        .sorted { $0.ends < $1.ends }
    }

    /// The next timer to ring.
    var nextAlarm: Timer? { timers.first { !rung.contains($0.id) } }

    func ring(_ id: Int) { rung.insert(id) }

    func clear(_ id: Int) { cleared.insert(id) }

    /// A dish's parts in so far, of the steps that put one in.
    func parts(of recipeID: String) -> (done: Int, of: Int) {
        let steps = guide.steps.filter { $0.dishes.contains(recipeID) }
        return (steps.filter { done[$0.id] != nil }.count, steps.count)
    }

    /// The dishes made ahead, with their containers, as they fill.
    var dishes: [PlannedRecipe] {
        weighed.filter { recipe in recipe.servings > 0 && !recipe.madeOnTheDay && guide.steps.contains { $0.dishes.contains(recipe.id) } }
    }

    /// When it'll be done from here: the rest of the steps' time on from now.
    func doneBy(_ now: Date) -> Date {
        now.addingTimeInterval(TimeInterval((guide.minutes - step.minute) * 60))
    }

    #if DEBUG
    /// Prep day as if it had run to `index` at the plan's pace, each step done a minute after it
    /// started: for a screenshot of the timers mid-way (-prepCounter 6).
    static func underway(_ plan: MealPlan, at index: Int, now: Date) -> PrepRun {
        let probe = PrepGuide.make(for: plan)
        let index = min(max(0, index), probe.steps.count - 1)
        let run = PrepRun(plan: plan, now: now.addingTimeInterval(-TimeInterval(probe.steps[index].minute * 60)))
        for _ in 0..<index { run.advance(at: run.started.addingTimeInterval(TimeInterval(run.step.minute * 60 + 60))) }
        // Timers that ran out a while ago were taken off, as the cook would have.
        for timer in run.timers where timer.ends < now.addingTimeInterval(-60) {
            run.ring(timer.id)
            run.clear(timer.id)
        }
        return run
    }
    #endif
}
