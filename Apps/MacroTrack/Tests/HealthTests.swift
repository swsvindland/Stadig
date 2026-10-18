import Foundation
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// What a read of Health does to the weigh-ins: scale readings come in, those deleted in Health
/// leave, and the anchor is kept on the device for the next read. Over Health's changes as the
/// bridge hands them over, since tests never reach Health itself.
@MainActor
struct HealthWeighInTests {
    func reading(_ id: UUID = UUID(), daysAgo: Int, kg: Double = 82) -> HealthWeight {
        HealthWeight(id: id, date: Day.today.adding(days: -daysAgo).at(hour: 7, minute: 0), kg: kg, sourceName: "Scale")
    }

    func healthIDs(_ model: AppModel) -> Set<UUID> {
        Set(
            model.weighIns.compactMap { weighIn in
                guard case .health(let id) = weighIn.source else { return nil }
                return id
            })
    }

    @Test func scaleReadingsComeInOnce() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let monday = reading(daysAgo: 2)
        let tuesday = reading(daysAgo: 1, kg: 81.6)
        model.merge(HealthWeightChanges(added: [monday, tuesday], deletedIDs: [], anchor: Data([1])))
        #expect(healthIDs(model) == [monday.id, tuesday.id])
        let saved = model.weighIns.first { $0.id == tuesday.id }
        #expect(saved?.kg == 81.6 && saved?.date == tuesday.date)
        #expect(model.weightAnchor == Data([1]))

        // Read again, with the whole window: nothing comes in twice, and a reading ignored here
        // isn't brought back as a fresh one.
        model.setExcluded(true, weighIn: try #require(model.weighIns.first { $0.id == monday.id }))
        model.merge(HealthWeightChanges(added: [tuesday], deletedIDs: [], anchor: Data([2])), window: [monday, tuesday])
        #expect(model.weighIns.count == 3, "the onboarding weigh-in and the two from the scale")
        #expect(model.weighIns.first { $0.id == monday.id }?.excluded == true)
        #expect(model.weightAnchor == Data([2]))
    }

    @Test func aWeighInDeletedInHealthLeaves() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let typed = try #require(model.weighIns.first)
        let misread = reading(daysAgo: 3, kg: 95)
        let kept = reading(daysAgo: 1)
        model.merge(HealthWeightChanges(added: [misread, kept], deletedIDs: [], anchor: Data([1])))
        // Ignored here first, then deleted in Health: it goes either way.
        model.delete(weighIn: try #require(model.weighIns.first { $0.id == misread.id }))
        #expect(model.weighIns.first { $0.id == misread.id }?.excluded == true)

        // Health reports deletions from any source, by sample id; one typed here has its own id
        // and stays, whatever Health says.
        model.merge(HealthWeightChanges(added: [], deletedIDs: [misread.id, typed.id, UUID()], anchor: Data([2])))
        #expect(healthIDs(model) == [kept.id])
        #expect(model.weighIns.contains { $0.id == typed.id })
        #expect(model.store.all(WeighIn.self).count == 2)
    }

    @Test func aSampleDeletedAsItsReadDoesntComeIn() {
        let model = TestEnvironment().model()
        model.onboard()
        let gone = reading(daysAgo: 1)
        let found = reading(daysAgo: 2)
        model.merge(HealthWeightChanges(added: [], deletedIDs: [gone.id], anchor: Data([1])), window: [gone, found])
        #expect(healthIDs(model) == [found.id])
    }

    @Test func theAnchorStaysOnTheDeviceForTheNextLaunch() throws {
        let suite = "MacroTrackTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = TestEnvironment()
        func model() -> AppModel {
            AppModel(
                store: environment.store, shared: environment.shared, widgetURL: environment.widgetURL, defaults: defaults,
                catalog: Catalogs.food, supplementCatalog: nil)
        }
        #expect(model().weightAnchor == nil, "a first read starts from the beginning")
        model().merge(HealthWeightChanges(added: [], deletedIDs: [], anchor: Data([7])))
        #expect(model().weightAnchor == Data([7]))
        #expect(environment.model().weightAnchor == nil, "nothing kept where nothing is to be kept")
    }
}

/// When Health is read: a launch reads it once, though the launch, the scene becoming active and
/// the observer starting each ask; a change the observer reports is always read; and the weigh-ins'
/// whole window is read beside the anchor only when the anchor may have passed some by.
@MainActor
struct HealthReadTests {
    let launch = date(2027, 3, 15, 7, 0)

    @Test func aLaunchReadsOnce() {
        var reads = HealthReads()
        let launched = reads.shouldRead(.returned, now: launch)
        let active = reads.shouldRead(.returned, now: launch + 0.5)
        reads.observerStarted(at: launch + 1)
        let observerStarting = reads.shouldRead(.changed, now: launch + 1.2)
        let weighIn = reads.shouldRead(.changed, now: launch + 30)
        let another = reads.shouldRead(.changed, now: launch + 40)
        #expect(launched, "the launch reads")
        #expect(!active, "the scene becoming active doesn't read again")
        #expect(!observerStarting, "nor does the observer's call as it starts")
        #expect(weighIn && another, "every change the observer hears is read")
    }

    @Test func aReturnReadsOnlyOnceItsStale() {
        var reads = HealthReads()
        let first = reads.shouldRead(.returned, now: launch)
        let soon = reads.shouldRead(.returned, now: launch + 4 * 60)
        let later = reads.shouldRead(.returned, now: launch + 6 * 60)
        let asked = reads.shouldRead(.asked, now: launch + 6 * 60 + 1)
        #expect(first && !soon && later)
        #expect(asked, "pull to refresh, or Connect, always reads")
        #expect(reads.last == launch + 6 * 60 + 1)
    }

    @Test func anObserverThatNeverCalledAsItStartedMissesNoChange() {
        var reads = HealthReads()
        _ = reads.shouldRead(.returned, now: launch)
        reads.observerStarted(at: launch)
        // Its first call a minute on is a change, not the call it makes as it starts.
        let change = reads.shouldRead(.changed, now: launch + 60)
        #expect(change)
    }

    @Test func theWholeWindowIsReadOnceARun() {
        let since = launch.addingTimeInterval(-60 * 86_400)
        // This device's first read, with no anchor yet, finds every weigh-in already.
        var first = HealthReads()
        #expect(!first.readsWholeWindow(since: since, anchored: false))
        first.windowRead(since: since)
        #expect(!first.readsWholeWindow(since: since, anchored: true), "nor again that run")

        // A later launch: the anchor may have passed weigh-ins Health hid until reading was allowed.
        var later = HealthReads()
        #expect(later.readsWholeWindow(since: since, anchored: true))
        later.windowRead(since: since)
        #expect(!later.readsWholeWindow(since: since, anchored: true), "once")
        #expect(!later.readsWholeWindow(since: since + 86_400, anchored: true), "a window that moved on is covered")
        #expect(later.readsWholeWindow(since: since - 86_400, anchored: true), "one reaching further back isn't")
        later.windowRead(since: since - 86_400)
        #expect(!later.readsWholeWindow(since: since - 86_400, anchored: true))

        // "Connect Apple Health": what was hidden is there now, behind the anchor.
        later.permissionAsked()
        #expect(later.readsWholeWindow(since: since, anchored: true))
    }

    @Test func anObserverStartingFirstStillMeansOneRead() {
        var reads = HealthReads()
        reads.observerStarted(at: launch)
        let starting = reads.shouldRead(.changed, now: launch + 0.2)
        let launched = reads.shouldRead(.returned, now: launch + 1)
        #expect(starting, "nothing read yet, so its starting call reads")
        #expect(!launched)
    }
}
