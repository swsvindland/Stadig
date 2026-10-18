import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// What Macro Track publishes to the shared container and what it takes from it: the nutrition
/// summary, its app summary, the profile, Lift Track's summary, and life modes from any app.
@MainActor
struct SharedContainerTests {
    @Test func aLaunchThatKeepsNothingSharesThroughAFolderOfItsOwn() throws {
        // A UI test's or -inMemoryStore's launch: what it publishes must never reach the App Group
        // the other apps read.
        let (shared, widgetURL) = AppModel.sharing(keepingNothing: true)
        #expect(!shared.isAppGroup)
        #expect(shared.directory.path(percentEncoded: false).hasPrefix(URL.temporaryDirectory.path(percentEncoded: false)))
        #expect(try #require(widgetURL).deletingLastPathComponent() == shared.directory.deletingLastPathComponent())
        #expect(AppModel.sharing(keepingNothing: true).0.directory != shared.directory, "a fresh one each launch")
    }

    @Test func publishesTheNutritionAndAppSummaries() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        #expect(environment.shared.read(.nutrition) == nil, "nothing before setup")
        SampleData.seedIfEmpty(model)

        let nutrition = try #require(environment.shared.envelope(.nutrition))
        #expect(nutrition.writtenBy == .macroTrack)
        #expect(nutrition.payload.maintenanceKcal != nil)
        #expect(!nutrition.payload.days.isEmpty)
        let summary = try #require(environment.shared.read(.summary(.macroTrack)))
        #expect(summary.app == .macroTrack)
    }

    @Test func anUnchangedSummaryIsntWrittenAgain() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        SampleData.seedIfEmpty(model)
        let first = try #require(environment.shared.envelope(.nutrition)).writtenAt

        // A relaunch with nothing new: the files stay as they are, so the other apps aren't woken.
        let relaunched = environment.model()
        relaunched.recompute()
        #expect(environment.shared.envelope(.nutrition)?.writtenAt == first)
    }

    @Test func readsLiftTracksSummary() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let lift = AppSummary(app: .liftTrack, updated: date(2027, 3, 14))
        try environment.shared.write(lift, to: .summary(.liftTrack), by: .liftTrack)

        model.readShared()
        #expect(model.lift == lift)
    }

    @Test func onboardingReusesAProfileFromAnotherApp() throws {
        let environment = TestEnvironment()
        try environment.shared.write(SharedProfile.sample(createdBy: .liftTrack), to: .profile, by: .liftTrack)
        let model = environment.model()
        #expect(!model.onboarded)
        #expect(model.sharedProfile?.createdBy == .liftTrack)
    }

    @Test func aNewerProfileFromLiftTrackIsAdopted() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        var edited = try #require(model.profile)
        edited.heightCm = 183
        edited.updatedAt = Date().addingTimeInterval(60)
        try environment.shared.write(edited, to: .profile, by: .liftTrack)

        model.readShared()
        #expect(model.profile?.heightCm == 183)
        #expect(environment.store.all(ProfileRecord.self).first?.profile.heightCm == 183, "kept for this app's other devices")

        // An older copy doesn't undo it.
        var stale = edited
        stale.heightCm = 170
        stale.updatedAt = Date().addingTimeInterval(-3600)
        try environment.shared.write(stale, to: .profile, by: .liftTrack)
        model.readShared()
        #expect(model.profile?.heightCm == 183)
    }

    // MARK: Life modes

    @Test func aLifeModeSavedHereIsShared() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let trip = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .macroTrack)

        #expect(model.save(lifeMode: trip))
        #expect(model.lifeModes.map(\.id) == [trip.id])
        #expect(environment.shared.read(.lifeModes)?.map(\.id) == [trip.id])
        #expect(model.analysis?.targets.mode == .vacation)
    }

    @Test func aPeriodAnEditorShouldntHaveOfferedIsntSaved() {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        // A trip with no end, and one that ends before it starts.
        let open = LifeModePeriod(kind: .vacation, start: model.today, createdBy: .macroTrack)
        #expect(!model.save(lifeMode: open))
        #expect(model.lifeModes.isEmpty)
        #expect(environment.store.all(LifeModeRecord.self).isEmpty)

        // An illness can run until it's better.
        let ill = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .macroTrack)
        #expect(model.save(lifeMode: ill))
        #expect(model.lifeModes.first?.end == nil)
    }

    @Test func aPeriodFromAnotherAppIsTakenUp() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let crunch = LifeModePeriod(kind: .crunch(CrunchDials()), start: model.today, end: model.today.adding(days: 3), createdBy: .liftTrack)
        try environment.shared.write([crunch], to: .lifeModes, by: .liftTrack)

        model.readShared()
        #expect(model.lifeModes.map(\.id) == [crunch.id])
        #expect(environment.store.all(LifeModeRecord.self).map(\.id) == [crunch.id], "kept, so it reaches this app's other devices")
        #expect(model.analysis?.targets.mode == .crunch)
    }

    @Test func aDeleteMadeElsewhereIsHonoured() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let trip = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .macroTrack)
        model.save(lifeMode: trip)
        let saved = try #require(environment.shared.read(.lifeModes)?.first)

        // Lift Track deletes it: a tombstone in the file.
        try environment.shared.write([saved.deleted(at: Date().addingTimeInterval(5))], to: .lifeModes, by: .liftTrack)
        model.readShared()

        #expect(model.lifeModes.isEmpty)
        #expect(model.analysis?.targets.mode != .vacation)
        let own = try #require(environment.store.all(LifeModeRecord.self).first)
        #expect(own.period.isDeleted, "this app's copy is the tombstone too, so its other devices drop it")
        #expect(environment.shared.read(.lifeModes)?.first?.isDeleted == true, "the tombstone stays, to keep spreading")

        // A relaunch doesn't bring it back.
        #expect(environment.model().lifeModes.isEmpty)
    }

    @Test func aDeleteHereIsATombstoneTheOtherAppsSee() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let trip = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .liftTrack)
        try environment.shared.write([trip], to: .lifeModes, by: .liftTrack)
        model.readShared()

        model.delete(lifeMode: trip.id)
        #expect(model.lifeModes.isEmpty)
        let shared = try #require(environment.shared.read(.lifeModes))
        #expect(shared.map(\.id) == [trip.id])
        #expect(shared.first?.isDeleted == true)
    }

    @Test func theNewerEditOfAPeriodWins() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let trip = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .macroTrack)
        model.save(lifeMode: trip)
        let saved = try #require(model.lifeModes.first)

        // Lift Track has an older copy with another end: this app's newer one stays, and goes back to the file.
        var older = saved
        older.end = model.today.adding(days: 2)
        older.updatedAt = saved.updatedAt.addingTimeInterval(-60)
        try environment.shared.write([older], to: .lifeModes, by: .liftTrack)
        model.readShared()
        #expect(model.lifeModes.first?.end == model.today.adding(days: 6))
        #expect(environment.shared.read(.lifeModes)?.first?.end == model.today.adding(days: 6))

        // A newer one from there is taken up.
        var newer = saved
        newer.end = model.today.adding(days: 9)
        newer.updatedAt = Date().addingTimeInterval(60)
        try environment.shared.write([newer], to: .lifeModes, by: .liftTrack)
        model.readShared()
        #expect(model.lifeModes.first?.end == model.today.adding(days: 9))
    }

    // MARK: The widgets' snapshot

    @Test func theWidgetSnapshotFollowsToday() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        model.log([try model.entry(foodID: Foods.bananaID, grams: 200)])

        let snapshot = MacroSnapshot.load(from: environment.widgetURL)
        #expect(snapshot.day == model.today.iso)
        #expect(abs(snapshot.kcal - 178) < 0.5)
        #expect(snapshot.weighedToday, "onboarding's weight is today's")
        #expect(snapshot.badge?.hasPrefix("Day 1 of") == true)
        #expect(MacroSnapshot.load(from: nil) == .empty)
    }
}
