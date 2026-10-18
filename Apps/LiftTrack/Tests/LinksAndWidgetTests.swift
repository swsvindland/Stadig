import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import Testing

@testable import LiftTrack

/// The widget's and the Live Activity's links, and the snapshot the widgets draw from.
@MainActor
@Suite("Links and widgets")
struct LinksAndWidgetTests {
    // MARK: Deep links

    @Test("lifttrack://start starts today's session and shows it")
    func startLink() throws {
        let model = TestApp().onboarded()
        let plan = try #require(model.plan())
        model.open(try #require(URL(string: "lifttrack://start")))
        #expect(model.live?.plan.title == plan.title)
        #expect(model.showSession)
    }

    @Test("lifttrack://start with a session running brings that one back rather than starting another")
    func startLinkResumes() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.logNext(2)
        let running = try #require(model.live)
        model.showSession = false
        model.open(try #require(URL(string: "lifttrack://start")))
        #expect(model.live?.id == running.id)
        #expect(model.showSession)
    }

    @Test("lifttrack://session shows the running session, and does nothing without one")
    func sessionLink() throws {
        let model = TestApp().onboarded()
        let link = try #require(URL(string: "lifttrack://session"))
        model.open(link)
        #expect(model.live == nil)
        #expect(!model.showSession)
        model.start(try #require(model.plan()))
        model.showSession = false
        model.open(link)
        #expect(model.showSession)
    }

    @Test("Other links, and links before setup, change nothing")
    func otherLinks() throws {
        let fresh = TestApp().model()
        fresh.open(try #require(URL(string: "lifttrack://start")))
        #expect(fresh.live == nil)
        #expect(!fresh.showSession)

        let model = TestApp().onboarded()
        model.open(try #require(URL(string: "lifttrack://settings")))
        model.open(try #require(URL(string: "https://example.com/start")))
        #expect(model.live == nil)
        #expect(!model.showSession)
    }

    // MARK: Widget snapshot

    @Test("The snapshot is today's session as Today shows it, written where the model was told")
    func snapshotForToday() throws {
        let app = TestApp()
        let model = app.onboarded()
        let snapshot = try #require(WidgetBridge.snapshot(for: model))
        let plan = try #require(model.plan())
        let next = try #require(model.analysis?.next)
        #expect(snapshot.title == plan.title)
        #expect(snapshot.minutes == plan.estimatedMinutes)
        #expect(snapshot.badge == "Assessment week 1")
        #expect(snapshot.day == (next.scheduledToday ? model.today : next.nextDay))
        #expect(snapshot.weekStart == model.today.startOfWeek)
        #expect(snapshot.plannedThisWeek == next.plannedThisWeek)
        #expect(snapshot.exercises.count <= 5)
        #expect(snapshot.exercises == plan.items.filter(\.isStrength).prefix(5).map { model.catalog.resolve($0.exerciseID).name })

        // What the model wrote, in its own folder rather than the App Group.
        var stored = WidgetSnapshot.load(from: app.widgetURL)
        stored.updated = snapshot.updated
        #expect(stored == snapshot)
    }

    @Test("No snapshot before setup")
    func noSnapshotBeforeSetup() {
        #expect(WidgetBridge.snapshot(for: TestApp().model()) == nil)
    }

    @Test("A snapshot round-trips through its file, and saving the same one again reports no change")
    func snapshotRoundTrip() throws {
        let url = URL.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var snapshot = WidgetSnapshot.sample
        snapshot.day = Day(year: 2026, month: 10, day: 19)
        snapshot.weekStart = Day(year: 2026, month: 10, day: 19)
        #expect(snapshot.save(to: url))
        #expect(WidgetSnapshot.load(from: url) == snapshot)
        var later = snapshot
        later.updated = snapshot.updated.addingTimeInterval(60)
        #expect(!later.save(to: url))
        #expect(WidgetSnapshot.load(from: url.appending(path: "missing")) == .empty)
    }

    @Test("A snapshot written before it had a day still reads")
    func olderSnapshotDecodes() throws {
        let json = #"{"title":"Upper A","detail":"Today","exercises":[],"doneThisWeek":1,"plannedThisWeek":4,"updated":0}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.day == nil)
        #expect(snapshot.reading(on: Day(year: 2026, month: 10, day: 20)).detail == "Today")
    }

    @Test("The iPhone widget reads the session's day against the day it's drawn on")
    func readingOnADay() {
        let monday = Day(year: 2026, month: 10, day: 19)
        var snapshot = WidgetSnapshot.sample
        snapshot.day = monday.adding(days: 2)
        snapshot.weekStart = monday
        snapshot.doneThisWeek = 2
        #expect(snapshot.reading(on: monday).detail == "Next: Wednesday")
        #expect(snapshot.reading(on: monday.adding(days: 2)).detail == "Today")
        let late = snapshot.reading(on: monday.adding(days: 3))
        #expect(late.detail == "Open Lift Track for today's plan")
        #expect(late.minutes == nil)
        #expect(late.doneThisWeek == 2)
        // A new week starts the count again.
        #expect(snapshot.reading(on: monday.adding(days: 7)).doneThisWeek == 0)
    }

    @Test("The Watch complication keeps its own wording until its day has gone by")
    func shownOnADay() {
        let monday = Day(year: 2026, month: 10, day: 19)
        var snapshot = WidgetSnapshot.sample
        snapshot.detail = "Done today"
        snapshot.day = monday
        #expect(snapshot.shown(on: monday) == snapshot)
        let tuesday = snapshot.shown(on: monday.adding(days: 1))
        #expect(tuesday.detail == "Open Lift Track on iPhone")
        #expect(tuesday.exercises.isEmpty)
        #expect(tuesday.minutes == nil)
        #expect(tuesday.badge == nil)
        #expect(tuesday.title == snapshot.title)
        var inProgress = snapshot
        inProgress.day = nil
        #expect(inProgress.shown(on: monday.adding(days: 5)) == inProgress)
    }
}
