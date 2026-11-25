import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// The app model over an in-memory store: onboarding, sample data and the session loop, and that what
/// it saves is there after a relaunch.
@MainActor
@Suite("App model")
struct AppModelTests {
    /// The hub left its last rhythm and changes on devices and in iCloud. A lighter week in them used
    /// to shorten the session; nothing reads them now, and nothing rewrites or deletes them either.
    @Test("What the hub left doesn't shorten a session, and stays as it was")
    func hubFilesAreIgnored() throws {
        let app = TestApp()
        let model = app.onboarded()
        let full = try #require(model.plan())
        let written = [
            "hub/changes.json": """
            {"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":[{"id":"\(UUID().uuidString)","kind":"lighter",\
            "day":"\(model.today.startOfWeek.iso)","parts":[],"updatedAt":1793613600000}]}
            """,
            "hub/rhythm.json": """
            {"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":{"wake":360,"bed":1350,"clearEvenings":2,"dayStart":4,\
            "placements":[{"title":"Lift","weekday":\(model.today.weekday.rawValue),"part":"early"}],"updated":1793613600000}}
            """,
        ]
        for (path, json) in written {
            let url = app.shared.directory.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)
        }
        model.readShared()
        model.recompute()
        #expect(try #require(model.plan()).estimatedMinutes == full.estimatedMinutes)
        for (path, json) in written {
            #expect(try Data(contentsOf: app.shared.directory.appending(path: path)) == Data(json.utf8), "\(path)")
        }
    }

    @Test("A fresh install isn't onboarded and has nothing to plan")
    func freshModel() {
        let model = TestApp().model()
        #expect(!model.onboarded)
        #expect(model.analysis == nil)
        #expect(model.plan() == nil)
        #expect(model.live == nil)
        #expect(model.arrival == nil, "a store that keeps nothing has nothing coming from iCloud to wait for")
    }

    @Test("Onboarding saves the profile, settings, gym and measurements, and starts the assessment today")
    func onboarding() throws {
        let app = TestApp()
        let model = app.onboarded()
        #expect(model.onboarded)
        #expect(model.profile?.schedule.daysPerWeek == 4)
        #expect(model.settings.onboardedAt != nil)
        #expect(model.settings.assessmentStart == .today)
        #expect(model.settings.gymID == model.gym.id)
        #expect(model.measurements.count == 1)
        let block = try #require(model.mesocycles.first)
        #expect(model.mesocycles.count == 1)
        #expect(block.block.kind == .assessment)
        #expect(block.block.start == .today)
        let analysis = try #require(model.analysis)
        #expect(analysis.assessment != nil)
        #expect(model.plan() != nil)
        // Asked once for every app in the family.
        #expect(app.shared.read(.profile)?.schedule.daysPerWeek == 4)
    }

    @Test("Onboarding offers a profile another app already shared")
    func reusesSharedProfile() {
        let app = TestApp()
        var other = TestApp.profile()
        other.createdBy = .macroTrack
        other.heightCm = 172
        try? app.shared.write(other, to: .profile, by: .macroTrack)
        let model = app.model()
        #expect(model.sharedProfile?.heightCm == 172)
        #expect(!model.onboarded)
    }

    @Test("Onboarding on a second device keeps the settings and block that synced in")
    func onboardingKeepsSyncedRecords() throws {
        let app = TestApp()
        // What iCloud brought from the first device: onboarded weeks ago, a block under way.
        let first = app.onboarded()
        let synced = first.settings
        let block = try #require(first.mesocycles.first)
        var older = block
        older.block.start = Day.today.adding(days: -14)
        first.save(older)

        let second = app.model()
        var answers = LiftSettings(selfReportedPhase: .cutting, saveToHealth: true)
        answers.focus = [.arms]
        second.completeOnboarding(profile: TestApp.profile(), settings: answers, gym: Gym.preset(.homeGym, unit: .kg), measurements: nil)
        #expect(second.settings.id == synced.id)
        #expect(second.settings.onboardedAt == synced.onboardedAt)
        #expect(second.settings.focus.isEmpty)
        #expect(second.mesocycles.count == 1)
        #expect(second.mesocycles.first?.block.start == Day.today.adding(days: -14))
    }

    @Test("New settings are kept under the one id every device uses, and read ahead of any saved under an id of their own")
    func settingsUnderOneID() {
        let app = TestApp()
        let model = app.onboarded()
        #expect(model.settings.id == LiftSettings.singletonID)
        #expect(app.store.all(LiftSettings.self).map(\.id) == [LiftSettings.singletonID])

        // From a device still on a version before the fixed id: newer, but not the one read.
        var older = model.settings
        older.id = UUID()
        older.includeCooldown.toggle()
        older.updatedAt = Date().addingTimeInterval(60)
        app.store.save(older)
        model.reloadIfChanged()
        #expect(model.settings.id == LiftSettings.singletonID)
        #expect(model.settings.includeCooldown != older.includeCooldown)
        #expect(app.model().settings.id == LiftSettings.singletonID)
    }

    @Test("Settings saved before the fixed id are read, and saved again under their own id")
    func settingsFromBeforeTheFixedID() {
        let app = TestApp()
        let old = LiftSettings(selfReportedPhase: .maintaining, saveToHealth: false, onboardedAt: Date().addingTimeInterval(-86_400 * 30))
        app.store.save(ProfileRecord(TestApp.profile()))
        app.store.save(old)
        let model = app.model()
        #expect(model.onboarded)
        #expect(model.settings.id == old.id)

        var changed = model.settings
        changed.includeCooldown.toggle()
        model.save(settings: changed)
        #expect(app.store.all(LiftSettings.self).map(\.id) == [old.id])
        #expect(model.settings.includeCooldown == changed.includeCooldown)
    }

    @Test("A block that synced in before its settings is kept, and the assessment is counted from its start")
    func onboardingAfterABlockSyncedIn() throws {
        let app = TestApp()
        let first = app.onboarded()
        var block = try #require(first.mesocycles.first)
        block.block.start = Day.today.adding(days: -7)
        // Only the block arrived: a fresh store with just that record in it.
        let second = TestApp()
        second.store.save(block)
        let model = second.model()
        TestApp.onboard(model)
        #expect(model.mesocycles.count == 1)
        #expect(model.mesocycles.first?.id == block.id)
        #expect(model.settings.assessmentStart == Day.today.adding(days: -7))
    }

    /// One seeding for both, as seeding is the slow part: the store, then `-sessionAt summary`'s session.
    @Test("Sample data gives an analysis, a history and today's plan, which -sessionAt summary does whole, ending now")
    func sampleData() throws {
        let model = TestApp().model()
        SampleData.seedIfEmpty(model)
        #expect(model.onboarded)
        let analysis = try #require(model.analysis)
        #expect(!model.sessions.isEmpty)
        #expect(!model.activities.isEmpty)
        #expect(!analysis.history.isEmpty)
        #expect(analysis.assessment != nil)
        let plan = try #require(model.plan())
        #expect(!plan.items.isEmpty)
        // A second seed leaves the store alone.
        let sessions = model.sessions.count
        SampleData.seedIfEmpty(model)
        #expect(model.sessions.count == sessions)

        // -sessionAt summary: every set, about as long as the plan, ending now, moving a main lift and Strength.
        let before = try #require(analysis.strength.overall)
        model.start(plan)
        let now = Date()
        SampleData.finishToday(model, now: now)
        #expect(model.live == nil)
        let record = try #require(model.finished)
        let baseline = try #require(model.finishedBaseline)
        // The plan's lifting sets, not its drills: every one done.
        #expect(baseline.plannedSets == plan.items.filter(\.isStrength).reduce(0) { $0 + $1.workSets.count })
        #expect(record.workSets.count >= baseline.plannedSets)
        #expect(abs(record.minutes - baseline.plannedMinutes) <= 10, "about as long as the plan: \(record.minutes) of \(baseline.plannedMinutes)")
        #expect(abs(record.end.timeIntervalSince(now)) < 60)
        #expect(record.exercises.flatMap(\.sets).allSatisfy { $0.date > record.start && $0.date <= record.end })
        let after = try #require(model.analysis)
        let strength = try #require(after.strength.overall)
        #expect(Int(strength.rounded()) > Int(before.rounded()), "Strength's gain: \(before) to \(strength)")
        let moved = plan.items.filter { $0.block == .main }.contains { item in
            let bests = StrengthEstimator.sessionBests(
                after.history[item.exerciseID] ?? [], basis: model.catalog.resolve(item.exerciseID).loadBasis, trust: after.trust)
            guard let last = bests.last, last.day == record.day, let earlier = bests.dropLast().map(\.e1rm).max() else { return false }
            return last.e1rm > earlier * 1.01
        }
        #expect(moved, "a main lift's estimate rose")

        // What it taught: what next time does with the main lifts' loads, as the planner has it, and the
        // rests the Watch's heart rate ended early. Which day of the program it is goes by the weekday,
        // as the sample is seeded back from today: a day with rests heart rate guides (accessories, and
        // compounds over six reps, outside supersets) has its rests in the lessons, but a day of heavy
        // compounds alone (bench, row and press) has none to end early, and its lessons can be one held
        // lift, since a weight done for its reps holds and the summary says held of one lift.
        #expect(record.averageHeartRate != nil)
        let lessons = baseline.lessons
        #expect((1...SessionLessons.limit).contains(lessons.count), "\(lessons.map(\.title))")
        #expect(lessons.contains { [.up, .held, .down].contains($0.kind) }, "\(lessons.map(\.title))")
        let guidedRests = plan.items.filter { $0.isStrength && $0.rest.heartRateGuided && $0.supersetGroup == nil }
            .reduce(0) { $0 + max(0, $1.workSets.count - 1) }
        if guidedRests >= 2 {
            let rest = try #require(lessons.first { $0.kind == .rest }, "\(lessons.map(\.title))")
            #expect(rest.detail.hasPrefix("Heart rate recovered early on ") || rest.title == "Short rests cost reps", "\(rest.detail)")
        }
        let state = try #require(model.state)
        let next = NextTime.items(after: record, state: state, analysis: after)
        for lesson in lessons where lesson.kind == .up || lesson.kind == .held {
            let id = try #require(lesson.exerciseID)
            let load = try #require(next[id]?.workSets.first?.loadKg)
            #expect(lesson.detail.contains(Format.number(load, digits: 2)), "\(lesson.title): \(lesson.detail), next time \(load)")
        }
    }

    @Test("Plan, start, log and finish records a session that's there after a relaunch")
    func sessionLoopPersists() throws {
        let app = TestApp()
        let model = app.onboarded()
        let plan = try #require(model.plan())
        model.start(plan)
        #expect(model.live != nil)
        #expect(model.showSession)
        model.logUntilAWorkSet()
        model.logNext(2)
        model.finish(feedback: SessionFeedback(soreness: 1, energy: 4))
        #expect(model.live == nil)
        #expect(!model.showSession)
        let finished = try #require(model.finished)
        #expect(finished.title == plan.title)
        #expect(!finished.exercises.isEmpty)
        #expect(model.sessions.map(\.id) == [finished.id])
        #expect(!FileManager.default.fileExists(atPath: app.liveURL.path(percentEncoded: false)))

        let relaunched = app.model()
        #expect(relaunched.sessions.map(\.id) == [finished.id])
        #expect(relaunched.sessions.first?.feedback?.energy == 4)
        #expect(relaunched.live == nil)
        // The session counts toward the week.
        #expect(relaunched.analysis?.next?.doneThisWeek == 1)
    }

    @Test("Measurements add a row that's there after a relaunch")
    func measurementsAddARow() {
        let app = TestApp()
        let model = app.onboarded()
        let before = model.measurements.count
        model.save(measurements: BodyMeasurements(day: .today, waistCm: 84))
        #expect(model.measurements.count == before + 1)
        #expect(app.model().measurements.count == before + 1)
    }

    @Test("Export writes a CSV file for each table, with the session logged in it")
    func exportWritesEachTable() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.logUntilAWorkSet()
        model.logNext(2)
        model.finish(feedback: nil)

        let files = try model.exportCSV()
        #expect(Set(files.map(\.lastPathComponent)) == ["sets.csv", "sessions.csv", "outside-activities.csv", "measurements.csv", "tests.csv"])
        let sessions = try #require(files.first { $0.lastPathComponent == "sessions.csv" })
        let lines = try String(contentsOf: sessions, encoding: .utf8).split(whereSeparator: \.isNewline)
        #expect(lines.count == 2, "a header and the session")
    }

    @Test("A vacation saves as its editor opens, a week from now")
    func aNewVacationSaves() {
        let model = TestApp().onboarded()
        #expect(model.save(lifeMode: LifeModeKindChoice.vacation.newPeriod))
        #expect(model.lifeModes.count == 1)
    }

    @Test("Finishing a session with nothing logged keeps nothing and shows no summary")
    func emptySessionIsDropped() throws {
        let model = TestApp().onboarded()
        model.start(try #require(model.plan()))
        model.finish(feedback: nil)
        #expect(model.live == nil)
        #expect(model.finished == nil)
        #expect(model.sessions.isEmpty)
    }

    @Test("A session with only the sauna in it is kept")
    func heatOnlySessionIsKept() {
        let model = TestApp().onboarded()
        let record = SessionRecord(
            start: Date().addingTimeInterval(-900), end: Date(), title: "Recovery",
            heat: [HeatLog(exerciseID: "sauna", date: Date(), minutes: 12, temperatureC: 85, rating: .orange)])
        model.keep(record)
        #expect(model.sessions.map(\.id) == [record.id])
        model.keep(SessionRecord(start: Date(), end: Date(), title: "Nothing"))
        #expect(model.sessions.count == 1)
    }

    @Test("Discarding a session keeps nothing from it")
    func discard() throws {
        let app = TestApp()
        let model = app.onboarded()
        model.start(try #require(model.plan()))
        model.logNext(3)
        model.discardLive()
        #expect(model.live == nil)
        #expect(model.sessions.isEmpty)
        #expect(app.model().live == nil)
    }

    @Test("A record finished on the Watch is saved once, however often it arrives")
    func watchRecordSavedOnce() throws {
        let model = TestApp().onboarded()
        var session = LiveSession(plan: try #require(model.plan()), device: "Watch")
        let environment = try #require(model.environment)
        while session.items.allSatisfy({ $0.loggedSets.isEmpty }), let (i, s) = session.current {
            session.log(item: i, set: s, reps: 5, loadKg: 20, rating: .orange, environment: environment)
        }
        let record = session.record(feedback: nil)
        model.keep(record)
        model.keep(record)
        #expect(model.sessions.count == 1)
    }

    @Test("Changes another device made, as CloudKit imports them, reach the running model")
    func reloadPicksUpOtherWrites() {
        let app = TestApp()
        let model = app.onboarded()
        // Written straight to the store, as an import does, without the model hearing of it.
        app.store.save(ActivityRecord(log: ActivityLog(type: .running, start: Date().addingTimeInterval(-3_600), minutes: 30)))
        #expect(model.activities.isEmpty)
        model.reloadIfChanged()
        #expect(model.activities.count == 1)
    }

    @Test("A model built for a test goes away when the test drops it")
    func modelDeallocates() throws {
        weak var weakModel: AppModel?
        do {
            let model = TestApp().onboarded()
            model.start(try #require(model.plan()))
            model.logUntilAWorkSet()
            model.readShared()
            weakModel = model
            #expect(weakModel != nil)
        }
        #expect(weakModel == nil)
    }
}
