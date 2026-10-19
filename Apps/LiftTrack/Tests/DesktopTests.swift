import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// The model behind the iPad and Mac screens: swaps for the rest of a block, exercises set aside
/// and allowed back, injury overrides from Library, the next block offered, refits to look at,
/// History's rows and their deletes, a session reordered, and where a narrow window sends the
/// sidebar's destinations.
@MainActor
@Suite("Program, Library and History")
struct DesktopTests {
    /// The current block's first main-lift slot, with its day.
    private func mainSlot(_ model: AppModel) throws -> (mesocycle: Mesocycle, day: PlannedDay, slot: SlotPlan) {
        let mesocycle = try #require(model.currentMesocycle)
        for day in mesocycle.days {
            if let slot = day.strengthSlots.first(where: { $0.role == .main }) { return (mesocycle, day, slot) }
        }
        Issue.record("No main lift in the block")
        throw CancellationError()
    }

    @Test("A swap for the rest of the block replaces that slot's exercise, says why, and lasts")
    func swapForTheRestOfTheBlock() throws {
        let app = TestApp()
        let model = app.onboarded()
        let (mesocycle, day, slot) = try mainSlot(model)
        let replacement = try #require(model.swapCandidates(for: slot.exerciseID).first)
        let before = model.catalog.resolve(slot.exerciseID)

        #expect(model.swap(slot: slot.id, day: day.id, of: mesocycle.id, to: replacement.id))
        let saved = try #require(model.mesocycles.first { $0.id == mesocycle.id }?.days.first { $0.id == day.id }?.slots.first { $0.id == slot.id })
        #expect(saved.exerciseID == replacement.id)
        #expect(saved.reason == "You swapped this in for \(before.name).")
        // Every other slot is as it was.
        let others = mesocycle.days.flatMap(\.slots).filter { $0.id != slot.id }
        let savedOthers = try #require(model.mesocycles.first { $0.id == mesocycle.id }).days.flatMap(\.slots).filter { $0.id != slot.id }
        #expect(others == savedOthers)
        // Kept across a relaunch.
        #expect(app.model().mesocycles.first { $0.id == mesocycle.id }?.days.flatMap(\.slots).contains { $0.exerciseID == replacement.id } == true)

        // Nothing to do for the same exercise, or a slot that isn't there.
        #expect(!model.swap(slot: slot.id, day: day.id, of: mesocycle.id, to: replacement.id))
        #expect(!model.swap(slot: UUID(), day: day.id, of: mesocycle.id, to: before.id))
        #expect(!model.swap(slot: slot.id, day: day.id, of: UUID(), to: before.id))
    }

    @Test("A swap stamps the block as edited, so it beats older copies, and keeps the slot in its superset")
    func swapKeepsTheSuperset() throws {
        let app = TestApp()
        let model = app.onboarded()
        let (current, day, slot) = try mainSlot(model)
        let partner = try #require(day.strengthSlots.first { $0.id != slot.id })
        // The block as another device saved it an hour ago, the main lift paired with the next exercise.
        var paired = current
        paired.id = UUID()
        paired.updatedAt = Date().addingTimeInterval(-3_600)
        let d = try #require(paired.days.firstIndex { $0.id == day.id })
        for b in paired.days[d].blocks.indices {
            for s in paired.days[d].blocks[b].slots.indices where [slot.id, partner.id].contains(paired.days[d].blocks[b].slots[s].id) {
                paired.days[d].blocks[b].slots[s].supersetGroup = 1
            }
        }
        for old in model.mesocycles { app.store.delete(Mesocycle.self, id: old.id) }
        app.store.save(paired)
        model.reload()
        #expect(model.currentMesocycle?.id == paired.id)

        let replacement = try #require(model.swapCandidates(for: slot.exerciseID).first)
        #expect(model.swap(slot: slot.id, day: day.id, of: paired.id, to: replacement.id))
        let saved = try #require(model.mesocycles.first { $0.id == paired.id })
        #expect(saved.updatedAt > paired.updatedAt)
        let savedDay = try #require(saved.days.first { $0.id == day.id })
        let swapped = try #require(savedDay.slots.first { $0.id == slot.id })
        #expect(swapped.exerciseID == replacement.id && swapped.supersetGroup == 1)
        #expect(savedDay.slots.first { $0.id == partner.id }?.supersetGroup == 1)
    }

    @Test("An exercise set aside isn't offered as a swap, leaves today's session, and can be allowed back")
    func setAsideAndAllowBack() throws {
        let model = TestApp().onboarded()
        let (_, _, slot) = try mainSlot(model)
        let candidate = try #require(model.swapCandidates(for: slot.exerciseID).first)
        model.setAside(candidate.id, true)
        #expect(model.settings.avoid.contains(candidate.id))
        #expect(!model.swapCandidates(for: slot.exerciseID).contains { $0.id == candidate.id })

        // Today's planned exercises, set aside: the session swaps them all out.
        let planned = try #require(model.plan()).items.filter(\.isStrength).map(\.exerciseID)
        for id in planned { model.setAside(id, true) }
        let today = try #require(model.plan())
        #expect(today.items.filter(\.isStrength).allSatisfy { !model.settings.avoid.contains($0.exerciseID) })

        for id in planned + [candidate.id] { model.setAside(id, false) }
        #expect(model.settings.avoid.isEmpty)
        #expect(model.swapCandidates(for: slot.exerciseID).contains { $0.id == candidate.id })
    }

    @Test("Library's override for an injury is saved on the injury, both ways")
    func injuryOverrideFromLibrary() throws {
        let model = TestApp().onboarded()
        let injury = Injury(parts: [InjuredPart(.knee)], severity: .severe)
        #expect(model.save(lifeMode: LifeModePeriod(kind: .injury(injury), start: .today, createdBy: .liftTrack)))
        let period = try #require(model.activeInjuries.first)
        let squat = try #require(model.catalog["barbell-back-squat"])
        #expect(model.analysis?.life.injuries.contains { $0.excludes(squat) } == true)

        model.toggleInjuryOverride(for: squat, in: period.id)
        #expect(model.analysis?.life.injuries.contains { $0.excludes(squat) } == false)
        model.toggleInjuryOverride(for: squat, in: period.id)
        #expect(model.analysis?.life.injuries.contains { $0.excludes(squat) } == true)
        // A period that's over isn't one to override.
        #expect(model.activeInjuries.count == 1)
    }

    @Test("The next block is offered once the block is over, and not while one is waiting")
    func nextBlockOffered() throws {
        let app = TestApp()
        let model = app.onboarded()
        #expect(!model.nextBlockOffered)
        // A real block that ended last week, the assessment long done.
        var finished = model.generate(kind: .standard, start: Day.today.adding(days: -60))
        finished.block.loadingWeeks = 4
        for assessment in model.mesocycles { app.store.delete(Mesocycle.self, id: assessment.id) }
        model.save(finished)
        #expect(model.nextBlockOffered)
        // Planned to follow a running block: waiting, so not offered again.
        var running = model.generate(kind: .standard, start: Day.today.adding(days: -7))
        running.block.loadingWeeks = 4
        model.save(running)
        model.accept(nextBlock: model.generate(kind: .standard, start: model.nextBlockStart))
        #expect(model.analysis?.upcoming != nil)
        #expect(!model.nextBlockOffered)
    }

    @Test("A day refitted to look at takes the minutes asked, the same way every time, and saves nothing")
    func refitToLookAt() throws {
        let model = TestApp().onboarded()
        let mesocycle = try #require(model.currentMesocycle)
        let day = try #require(mesocycle.days.first)
        let short = try #require(model.refitted(day, of: mesocycle, minutes: 30))
        let long = try #require(model.refitted(day, of: mesocycle, minutes: 90))
        #expect(short.minutes < long.minutes)
        #expect(short.minutes <= 35)
        #expect(model.refitted(day, of: mesocycle, minutes: 30) == short)
        #expect(model.currentMesocycle == mesocycle)
    }

    @Test("History's rows follow the sessions and activities, and a row's delete takes the right record")
    func historyRows() throws {
        let model = TestApp().onboarded()
        #expect(model.historyRows.isEmpty)
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        model.finish(feedback: nil)
        let bjj = ActivityLog(type: .bjj, start: Date().addingTimeInterval(-3_600), minutes: 60)
        model.save(activity: bjj)
        #expect(model.historyRows.count == 2)
        let session = try #require(model.historyRows.first { $0.isSession })
        #expect(session.id == model.sessions.first?.id)
        #expect(session.workSets > 0)
        #expect(session.source == Platform.deviceName)

        model.delete(historyRow: try #require(model.historyRows.first { !$0.isSession }))
        #expect(model.activities.isEmpty)
        model.delete(historyRow: session)
        #expect(model.sessions.isEmpty)
        #expect(model.historyRows.isEmpty)
    }

    @Test("Deleting several History rows takes every record and reads the records once")
    func deleteSeveralRows() throws {
        let app = TestApp()
        let model = app.onboarded()
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        model.finish(feedback: nil)
        for hours in 1...3 {
            model.save(activity: ActivityLog(type: .bjj, start: Date().addingTimeInterval(-3_600 * Double(hours) - 7_200), minutes: 60))
        }
        #expect(model.historyRows.count == 4)

        let reloads = model.reloads
        model.delete(historyRows: model.historyRows)
        #expect(model.reloads == reloads + 1)
        #expect(model.historyRows.isEmpty && model.sessions.isEmpty && model.activities.isEmpty)
        // Gone for good, not only from this model.
        #expect(app.model().historyRows.isEmpty)
        // Nothing to delete reads nothing.
        model.delete(historyRows: [])
        #expect(model.reloads == reloads + 1)
    }

    @Test("Dragging an exercise in the session reorders it and keeps what's logged")
    func reorderTheSession() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.logNext(1)
        let before = try #require(model.live)
        let last = before.items.count - 1
        model.moveLive(items: [last], to: 1)
        let after = try #require(model.live)
        #expect(after.items[1].id == before.items[last].id)
        #expect(Set(after.items.map(\.id)) == Set(before.items.map(\.id)))
        #expect(after.items[0].loggedSets == before.items[0].loggedSets)
        model.discardLive()
    }

    @Test("Start Today's Session starts one, then brings it back; a destination opens from its launch name")
    func menuActions() throws {
        let model = TestApp().onboarded()
        #expect(model.canStartToday)
        model.startToday()
        let id = try #require(model.live?.id)
        #expect(model.showSession)
        #expect(!model.canStartToday)
        model.showSession = false
        model.startToday()
        #expect(model.live?.id == id)
        #expect(model.showSession)
        model.discardLive()

        for tab in AppTab.allCases { #expect(AppTab(rawValue: tab.rawValue) == tab) }
        #expect(AppTab(rawValue: "program") == .program)
        model.show(inLibrary: "barbell-bench-press")
        #expect(model.tab == .library && model.libraryFocus == "barbell-bench-press")
    }

    @Test("Without a sidebar, its destinations show the tab that reaches them, as on the iPhone")
    func tabBarFallbacks() {
        #expect(AppTab.program.tabBarFallback == .plan)
        #expect(AppTab.library.tabBarFallback == .plan)
        #expect(AppTab.history.tabBarFallback == .progress)
        for tab in [AppTab.today, .plan, .progress, .body] { #expect(tab.tabBarFallback == tab) }
        // Always one of the iPhone's four tabs.
        #expect(Set(AppTab.allCases.map(\.tabBarFallback)) == [.today, .plan, .progress, .body])
    }
}
