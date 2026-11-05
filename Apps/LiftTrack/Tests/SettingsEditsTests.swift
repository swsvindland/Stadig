import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// Settings screens edit a copy and save it on the way out. The Mac keeps its Settings panes alive
/// between visits, so a pane must catch up with what synced in, and write only what it changed.
@MainActor
@Suite("Settings edits")
struct SettingsEditsTests {
    /// Two hours ago, when the records were first saved: what syncs in afterwards is newer, and an
    /// edit saved now newer still.
    private let start = Date().addingTimeInterval(-7_200)

    /// A model over a profile saved at `start`.
    private func model(_ app: TestApp) -> AppModel {
        var profile = TestApp.profile()
        profile.updatedAt = start
        app.store.save(ProfileRecord(profile))
        return app.model()
    }

    /// The profile as another device saved it at `date`.
    private func sync(at date: Date, _ change: (inout SharedProfile) -> Void, into app: TestApp, _ model: AppModel) throws {
        var newer = try #require(model.profile)
        change(&newer)
        newer.updatedAt = date
        app.store.save(ProfileRecord(newer))
        model.reload()
    }

    @Test("A pane left open catches up with a newer profile, and a visit that changes nothing writes nothing")
    func paneCatchesUp() throws {
        let app = TestApp()
        let model = model(app)
        var pane = EditedCopy(try #require(model.profile))

        // Three days on the Mac, saved as the pane is left.
        pane.value.schedule.daysPerWeek = 3
        pane.saved(try #require(model.save(profileEdits: pane.value, from: pane.original)))
        #expect(!pane.isPending)
        #expect(app.shared.read(.profile)?.schedule.daysPerWeek == 3)

        // Five on the iPhone a minute later, synced in; the pane catches up.
        try sync(at: Date().addingTimeInterval(60), { $0.schedule.daysPerWeek = 5 }, into: app, model)
        pane.catchUp(to: model.profile)
        #expect(pane.value.schedule.daysPerWeek == 5)

        // What synced in reaches the shared file, for the apps that plan around it.
        #expect(app.shared.read(.profile)?.schedule.daysPerWeek == 5)

        // Back to the pane and away again, changing nothing: nothing is written, here or for the other apps.
        let revision = app.store.revision
        let written = app.shared.envelope(.profile)?.writtenAt
        #expect(model.save(profileEdits: pane.value, from: pane.original) == nil)
        #expect(app.store.revision == revision)
        #expect(model.profile?.schedule.daysPerWeek == 5)
        #expect(app.shared.envelope(.profile)?.writtenAt == written, "the shared profile isn't rewritten by a visit")
    }

    @Test("Edits made on an old copy write only the fields changed, over what synced in")
    func onlyWhatChanged() throws {
        let app = TestApp()
        let model = model(app)
        var pane = EditedCopy(try #require(model.profile))

        // Changed here, and not saved yet, when the iPhone's change to the days syncs in.
        pane.value.goals.append(.fitter)
        pane.value.schedule.minutesPerSession = 45
        try sync(at: start.addingTimeInterval(60), { $0.schedule.daysPerWeek = 5 }, into: app, model)
        pane.catchUp(to: model.profile)
        #expect(pane.value.schedule.daysPerWeek == 4, "pending edits aren't replaced")

        // Each part of the schedule is a field of its own: the minutes changed here keep the synced days.
        let saved = try #require(model.save(profileEdits: pane.value, from: pane.original))
        #expect(saved.goals.contains(.fitter))
        #expect(saved.schedule.minutesPerSession == 45 && saved.schedule.daysPerWeek == 5)
        #expect(app.shared.read(.profile)?.schedule.daysPerWeek == 5)
        #expect(app.model().profile == saved)
        pane.saved(saved)
        #expect(pane.value == model.profile && !pane.isPending)
    }

    @Test("The gym pane writes what it changed onto the gym as it is, not the copy it opened with")
    func gymEdits() throws {
        let app = TestApp()
        var gym = Gym.preset(.fullGym, unit: .kg)
        gym.updatedAt = start
        app.store.save(gym)
        let model = app.model()
        var pane = EditedCopy(model.gym)
        #expect(model.save(gymEdits: pane.value, from: pane.original) == nil)

        // A sauna added on another device while the pane was open.
        var newer = model.gym
        newer.apparatus.insert(.sauna)
        newer.updatedAt = start.addingTimeInterval(60)
        app.store.save(newer)
        model.reload()

        pane.value.name = "Garage"
        let saved = try #require(model.save(gymEdits: pane.value, from: pane.original))
        #expect(saved.name == "Garage" && saved.apparatus.contains(.sauna))
        #expect(app.model().gym.apparatus.contains(.sauna))
        pane.saved(saved)
        #expect(pane.value == model.gym && !pane.isPending)
    }
}
