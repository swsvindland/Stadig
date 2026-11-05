import Foundation
import HubEngine
import OSLog
import SwiftUI
import SystemCore
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.stadig.hub", category: "app")

enum AppTab: String, Hashable {
    case today, week, rhythm
}

/// The hub keeps two things of its own, the rhythm and what changed, and publishes them for the
/// other apps. Everything else it shows is worked out from what the apps last published, whenever
/// anything moves, so there's no plan to go out of date. It logs nothing: its buttons open the apps.
@MainActor @Observable
final class AppModel {
    /// One for the life of the process, so what it observes is never torn down.
    static let shared = AppModel(launch: .current)

    let store: RecordStore
    let shared: SharedContainer
    @ObservationIgnored private let now: () -> Date

    var tab = AppTab.today
    var showPlansChanged = false
    /// The day Today shows.
    var selectedDay: Day
    /// An app that wouldn't open, because it isn't on this device.
    var missingApp: AppID?

    private(set) var today: Day
    /// The part of the day it is.
    private(set) var part: DayPart
    private(set) var rhythm: Rhythm?
    private(set) var changes: [DayChange] = []
    private(set) var thisWeek: HubWeek?
    private(set) var nextWeek: HubWeek?
    private(set) var lines: [RhythmLine] = []
    /// A second device or a reinstall, with the rhythm still on its way: the wait for it.
    private(set) var arrival: ICloudArrival?
    /// The shared container mirrored to the person's other devices, which is also how the rhythm
    /// reaches their other apps there. Nil in tests.
    @ObservationIgnored private(set) var family: FamilySync?

    @ObservationIgnored private var sharedToken: AnyObject?
    @ObservationIgnored private var storeToken: AnyObject?

    convenience init(launch: LaunchOptions) {
        let memory = launch.usesInMemoryStore
        let store = RecordStore(name: "Hub", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.stadig.hub", inMemory: memory)
        #if DEBUG
        if launch.has("-resetData") { store.eraseAll() }
        #endif
        if memory {
            let scratch = URL.temporaryDirectory.appending(path: "Hub \(UUID().uuidString)", directoryHint: .isDirectory)
            self.init(store: store, shared: SharedContainer(directory: scratch))
        } else {
            let shared = SharedContainer()
            self.init(store: store, shared: shared)
            family = FamilySync(shared: shared)
        }
    }

    /// Everything that touches disk comes in, so a test builds one over an in-memory store and a
    /// temporary shared container. `now` is the clock every date the model makes reads.
    init(store: RecordStore, shared: SharedContainer, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.shared = shared
        self.now = now
        let date = now()
        let day = Day(date, dayStartsAt: Rhythm().dayStart)
        today = day
        selectedDay = day
        part = DayPart(hour: Calendar.current.component(.hour, from: date))
        readShared()
        sharedToken = SharedContainer.observeChanges { [weak self] in self?.readShared() }
        storeToken = store.observeChanges { [weak self] in self?.readShared() }
        // The rhythm has two ways to arrive: its own record here, or the published file through the
        // family's container. Either one ends the wait, because either one sets `rhythm`.
        if !onboarded { arrival = ICloudArrival.start(for: store) }
    }

    /// Set up once there's a rhythm: from here, or from another device.
    var onboarded: Bool { rhythm != nil }

    var isOutTonight: Bool { changes.contains { $0.kind == DayChange.out && $0.day == today } }
    var isLighter: Bool { changes.isLighter(today.startOfWeek) }

    /// The day Today shows, as far as this week and next go.
    var shownDay: HubDay? {
        thisWeek?.days.first { $0.day == selectedDay } ?? nextWeek?.days.first { $0.day == selectedDay }
    }

    // MARK: Reading

    /// Reads everything again. Called when the app comes forward, when any app publishes, and when
    /// iCloud brings something: nothing here runs in the background.
    func readShared() {
        let rhythm = syncRhythm()
        // Before the changes, which are kept by the date.
        moveDay(rhythm.map(dayNow) ?? today)
        let changes = syncChanges().live
        let inputs = rhythm.map { rhythm in
            HubInputs(
                rhythm: rhythm, changes: changes, profile: shared.read(.profile), lift: shared.read(.summary(.liftTrack)),
                ask: shared.read(.blockAsk),
                meals: shared.read(.mealRhythm), today: today, now: now())
        }
        self.rhythm = rhythm
        self.changes = changes
        thisWeek = inputs.map { HubPlanner.week(of: today, $0) }
        nextWeek = inputs.map { HubPlanner.week(of: today.startOfWeek.adding(weeks: 1), $0) }
        lines = inputs.map(RhythmSummary.lines) ?? []
    }

    private func dayNow(_ rhythm: Rhythm) -> Day { Day(now(), dayStartsAt: rhythm.dayStart) }

    /// The newest of what's stored here and what's published wins, and the one behind catches up,
    /// so a rhythm set on another device arrives either way.
    private func syncRhythm() -> Rhythm? {
        let own = store.get(RhythmRecord.self, id: RhythmRecord.singletonID)?.rhythm
        let file = shared.read(.rhythm)
        guard let newest = [own, file].compactMap(\.self).max(by: { $0.updated < $1.updated }) else { return nil }
        if own != newest { store.save(RhythmRecord(newest)) }
        if file != newest {
            do {
                try shared.write(newest, to: .rhythm, by: .hub)
            } catch {
                appLog.error("Couldn't publish the rhythm: \(error.localizedDescription)")
            }
        }
        return newest
    }

    /// What changed, merged item by item with what's published, tombstones and all, as Stadig Mind
    /// does with life modes. Old ones go, so the file can't grow for ever.
    private func syncChanges() -> [DayChange] {
        let own = store.all(DayChangeRecord.self).map(\.change)
        let file = shared.read(.dayChanges) ?? []
        let merged = DayChange.merge([file, own]).kept(on: today)
        let mine = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arrived = merged.filter { mine[$0.id] != $0 }
        if !arrived.isEmpty { store.save(arrived.map(DayChangeRecord.init)) }
        let kept = Set(merged.map(\.id))
        let expired = own.filter { !kept.contains($0.id) }
        if !expired.isEmpty { store.delete(DayChangeRecord.self, ids: expired.map(\.id)) }
        if merged != file {
            do {
                try shared.write(merged, to: .dayChanges, by: .hub)
            } catch {
                appLog.error("Couldn't publish what changed: \(error.localizedDescription)")
            }
        }
        return merged
    }

    // MARK: The clock

    /// The selected day follows today when today moves on.
    private func moveDay(_ day: Day) {
        guard day != today else { return }
        if selectedDay == today { selectedDay = day }
        today = day
    }

    func tick() {
        let current = DayPart(hour: Calendar.current.component(.hour, from: now()))
        if current != part { part = current }
        if let rhythm, dayNow(rhythm) != today { readShared() }
    }

    /// Keeps the part of the day right while the app is open. It ends with the view that runs it.
    func keepTime() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            tick()
        }
    }

    /// Whole seconds: a date round-trips through a file to the millisecond, and a stamp that didn't
    /// come back the same would look like a change every time it was compared.
    private var stamp: Date { Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down)) }

    // MARK: The rhythm

    func finishSetup(pattern: WorkPattern, wake: Int, bed: Int) {
        save(Rhythm(pattern: pattern, wake: wake, bed: bed))
    }

    func updateRhythm(_ change: (inout Rhythm) -> Void) {
        guard var rhythm else { return }
        change(&rhythm)
        guard rhythm != self.rhythm else { return }
        save(rhythm)
    }

    private func save(_ rhythm: Rhythm) {
        var rhythm = rhythm
        rhythm.updated = stamp
        store.save(RhythmRecord(rhythm))
        readShared()
    }

    // MARK: Plans changed

    func outTonight() {
        guard !isOutTonight else { return }
        store.save(DayChangeRecord(.outTonight(on: today, at: stamp, during: part)))
        readShared()
    }

    func toggleLighterWeek() {
        if isLighter {
            remove(changes.filter { $0.kind == DayChange.lighter && $0.day == today.startOfWeek })
        } else {
            store.save(DayChangeRecord(.lighterWeek(of: today, at: stamp)))
            readShared()
        }
    }

    /// Back to the plan as it was: from today on. What's passed has passed.
    func backToPlan() {
        remove(changes.filter { ($0.kind == DayChange.lighter && $0.day == today.startOfWeek) || $0.day >= today })
    }

    private func remove(_ gone: [DayChange]) {
        let date = stamp
        store.save(gone.map { DayChangeRecord($0.deleted(at: date)) })
        readShared()
    }
}
