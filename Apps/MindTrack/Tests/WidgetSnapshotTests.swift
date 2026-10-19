import Foundation
import MindEngine
import SystemCore
import SystemStore
import Testing

@testable import MindTrack

/// What the widgets show: today's session as Today shows it, the week's count, and how a snapshot
/// reads once its day has gone by.
@MainActor
struct WidgetSnapshotTests {
    @Test func beforeSetupItAsksToSetUp() {
        let snapshot = WidgetBridge.snapshot(for: TestApp.model())
        #expect(snapshot.status == .setUp)
        #expect(snapshot == .empty)
    }

    @Test func aStudyDayShowsTheSessionAsTodayHasIt() throws {
        let model = TestApp.model()
        SampleData.seedIfEmpty(model)
        let plan = try #require(model.analysis?.today, "a Wednesday is a study day")
        let snapshot = WidgetBridge.snapshot(for: model)
        #expect(snapshot.status == .today)
        #expect(snapshot.headline == plan.headline)
        #expect(snapshot.parts.map(\.title) == plan.parts.map(\.title))
        #expect(snapshot.parts.map(\.minutes) == plan.parts.map(\.minutes))
        #expect(snapshot.symbols == plan.domains.map(\.symbol))
        #expect(snapshot.day == model.today)
        #expect(snapshot.plannedThisWeek > 0)
        #expect(snapshot.doneThisWeek <= snapshot.plannedThisWeek)
    }

    @Test func afterASessionItShowsWhatTodayShows() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        model.startToday()
        Student.answer(model, steps: 12, clock: clock)
        clock.advance(30)
        model.endSession()
        let analysis = try #require(model.analysis)
        #expect(analysis.doneToday.count == 1)
        let snapshot = WidgetBridge.snapshot(for: model)
        // Today's card: the session again while it still waits (left early), otherwise done.
        if let plan = analysis.today {
            #expect(snapshot.status == .today)
            #expect(snapshot.headline == plan.headline)
        } else {
            #expect(snapshot.status == .done)
            #expect(snapshot.headline == "Done for today")
            #expect(snapshot.symbols == analysis.doneToday[0].domains.map(\.symbol))
        }
    }

    @Test func aSnapshotFromAnEarlierDayNudgesToOpenTheApp() {
        var snapshot = MindSnapshot.sample
        let written = Day(year: 2026, month: 10, day: 14)
        snapshot.day = written
        snapshot.nextDay = written.adding(days: 1)
        #expect(snapshot.reading(on: written) == snapshot, "on its own day it reads as written")

        let tomorrow = snapshot.reading(on: written.adding(days: 1))
        #expect(tomorrow.headline == "Study day: open Mind Track")
        #expect(tomorrow.parts.isEmpty)
        #expect(tomorrow.doneThisWeek == snapshot.doneThisWeek, "same week")

        let nextWeek = snapshot.reading(on: written.startOfWeek.adding(days: 8))
        #expect(nextWeek.headline == "Open Mind Track for today's plan")
        #expect(nextWeek.doneThisWeek == 0, "a new week counts from zero")
    }

    @Test func aStaleSnapshotKeepsOnlyWhatItKnows() {
        let written = Day(year: 2026, month: 10, day: 14)
        var snapshot = MindSnapshot.sample
        snapshot.day = written
        snapshot.phaseLastDay = written.adding(days: 4)

        // Done on Wednesday, the next study day Friday: Thursday is a rest day, as the app had it.
        var done = snapshot
        done.status = .done
        done.headline = "Done for today"
        done.nextDay = written.adding(days: 2)
        let thursday = done.reading(on: written.adding(days: 1))
        #expect(thursday.status == .rest && thursday.headline == "Rest day")
        #expect(thursday.symbols.isEmpty && thursday.parts.isEmpty, "yesterday's courses aren't today's")
        #expect(thursday.phase == snapshot.phase, "the week's phase still holds")
        #expect(thursday.link == URL(string: "mindtrack://today"), "a rest day opens Today, not a session")
        let friday = done.reading(on: written.adding(days: 2))
        #expect(friday.status == .today && friday.headline == "Study day: open Mind Track")
        #expect(friday.link == URL(string: "mindtrack://start"))
        let monday = done.reading(on: written.adding(days: 5))
        #expect(monday.status == .today && monday.headline == "Open Mind Track for today's plan")
        #expect(monday.phase == MindSnapshot.empty.phase, "the phase ended on Sunday")

        // A vacation to Sunday is still one on Friday; by Monday it's over, and only the app knows what's next.
        var paused = snapshot
        paused.status = .paused
        paused.headline = "Vacation"
        paused.phase = "Vacation"
        paused.nextDay = nil
        let stillAway = paused.reading(on: written.adding(days: 2))
        #expect(stillAway.status == .paused && stillAway.headline == "Vacation" && stillAway.phase == "Vacation")
        #expect(stillAway.link == URL(string: "mindtrack://today"))
        let back = paused.reading(on: written.adding(days: 5))
        #expect(back.status == .today && back.headline == "Open Mind Track for today's plan")

        // An illness with no end set holds until the app says otherwise.
        var ill = paused
        ill.headline = "Illness"
        ill.phaseLastDay = nil
        #expect(ill.reading(on: written.adding(days: 20)).status == .paused)
    }

    @Test func aPauseInTheModelReachesTheSnapshotWithItsEnd() throws {
        let clock = TestClock()
        let model = TestApp.onboardedModel(clock: clock)
        let end = model.today.adding(days: 3)
        #expect(model.save(lifeMode: LifeModePeriod(kind: .vacation, start: model.today, end: end, createdBy: .knowledge)))
        let snapshot = WidgetBridge.snapshot(for: model)
        #expect(snapshot.status == .paused)
        #expect(snapshot.phaseLastDay == end)
        #expect(snapshot.reading(on: end).status == .paused)
    }

    @Test func savingTheSameSnapshotTwiceWritesOnce() throws {
        let url = TestApp.folder().appending(path: "widget.json")
        var snapshot = MindSnapshot.sample
        #expect(try snapshot.save(to: url))
        snapshot.updated = Date().addingTimeInterval(60)
        #expect(try !snapshot.save(to: url), "only the stamp moved")
        snapshot.dueReviews += 1
        #expect(try snapshot.save(to: url))
        #expect(MindSnapshot.load(from: url) == snapshot)
    }

    @Test func aTestModelNeverWritesTheRealWidgetsSnapshot() throws {
        // Its shared container is a temporary folder, not the App Group: every recompute, and an
        // update asked for outright, leaves the real snapshot as it was (there or not, and when it
        // was last written).
        func stamp(_ url: URL?) -> Date?? {
            guard let url else { return .none }
            let path = url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { return .some(nil) }
            return .some((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)
        }
        let real = MindSnapshot.appGroupURL
        let before = stamp(real)
        let model = TestApp.model()
        SampleData.seedIfEmpty(model)
        #expect(!model.shared.isAppGroup)
        WidgetBridge.update(model)
        #expect(stamp(real) == before, "the App Group's widget.json was touched")
    }
}
