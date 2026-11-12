import Foundation
import NutritionEngine
import OSLog
import Observation
import SystemCore
import SystemStore
import WatchKit
import WidgetKit

let watchLog = Logger(subsystem: "dev.svindland.stadig.macro.watchkitapp", category: "watch")

/// A short confirmation after logging, with what its Undo takes back.
struct WristToast: Identifiable, Equatable {
    enum Undo: Equatable {
        case entries([UUID])
        case water(UUID)
        case doses([UUID])
        case weighIn(UUID)
        /// The day's state before it was marked: Undo puts it back.
        case dayState(DayState?)
        /// A fast just started: Undo removes it. One just ended: Undo runs it again.
        case fastStarted(UUID)
        case fastEnded(Fast)
    }

    var id = UUID()
    var message: String
    var undo: Undo
}

/// The Watch's state: Stadig Macro's own synced records, the family's shared files (Stadig Lift's
/// calendar and summary, the life modes), and today as the phone's analysis sees it.
///
/// The Watch opens the same CloudKit database as the phone, the iPad and the Mac, so what it logs
/// syncs to them and works with no phone nearby. It writes nothing to Apple Health: the iPhone puts
/// what arrives from the Watch (and the Mac) into Health once (`HealthBackfill`), so a food never
/// lands there twice under two sources. It never applies the weekly check-in either: that's the
/// phone's, which reads Health and Stadig Lift first; until it has, the Watch shows the check-in the
/// analysis says is due, as the phone would.
@MainActor @Observable
final class WristModel {
    /// One model for the app's scene and the background refreshes. Lives as long as the app.
    static let shared = WristModel(launch: .current)

    let store: RecordStore
    let shared: SharedContainer
    /// Where the complications' snapshot goes: the App Group, or a fresh folder when nothing is kept.
    let snapshotURL: URL?
    /// Whether this model reloads the complications: not in UI tests.
    let usesSystemServices: Bool

    /// Today, once the first analysis has run; nil before it, and before setup.
    private(set) var today: WristToday?
    /// Whether the records have been read once: until then the app shows a spinner, not "Set up".
    private(set) var loaded = false
    private(set) var onboarded = false
    private(set) var units: UnitPreference = .regional
    var toast: WristToast?

    // Records, read from the store and the shared container.
    @ObservationIgnored private var profile: SharedProfile?
    @ObservationIgnored private var settings = MacroSettings(id: MacroSettings.singletonID)
    @ObservationIgnored private var entries: [FoodEntry] = []
    @ObservationIgnored private var weighIns: [WeighIn] = []
    @ObservationIgnored private var dayStatus: [DayStatus] = []
    @ObservationIgnored private var plan: PhasePlan?
    @ObservationIgnored private var checkIns: [CheckIn] = []
    @ObservationIgnored private var supplements: [Supplement] = []
    @ObservationIgnored private var supplementLogs: [SupplementLog] = []
    @ObservationIgnored private var water: [WaterLog] = []
    @ObservationIgnored private var fasts: [Fast] = []
    @ObservationIgnored private var ownLifeModes: [LifeModePeriod] = []
    @ObservationIgnored private var lifeModes: [LifeModePeriod] = []
    @ObservationIgnored private var lift: AppSummary?
    @ObservationIgnored private var calendar: SystemCalendar?
    @ObservationIgnored private var sharedProfile: SharedProfile?

    /// The family's shared files, mirrored from the person's other devices; nil when nothing is kept.
    @ObservationIgnored private var family: FamilySync?
    @ObservationIgnored private var storeObserver: AnyObject?
    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var readRevisions: [String: Int] = [:]
    @ObservationIgnored private var lastRevision = -1
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    /// Bumped by every recompute, so an analysis that finishes after a newer one started is dropped.
    @ObservationIgnored private var generation = 0

    /// Stadig Macro's synced store and the App Group, or, when nothing is to be kept (UI tests,
    /// `-inMemoryStore`), an in-memory store and a fresh folder for the shared files and the snapshot.
    convenience init(launch: LaunchOptions) {
        let memory = launch.usesInMemoryStore
        let store = RecordStore(name: "MacroTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.stadig.macro", inMemory: memory)
        #if DEBUG
        if launch.has("-resetData") { store.eraseAll() }
        #endif
        var snapshotURL = WristSnapshotFile.appGroupURL
        let shared: SharedContainer
        if memory {
            let folder = URL.temporaryDirectory.appending(path: "MacroTrackWatch \(UUID().uuidString)", directoryHint: .isDirectory)
            shared = SharedContainer(directory: folder.appending(path: "SystemShared", directoryHint: .isDirectory))
            snapshotURL = folder.appending(path: "watch.json")
            #if DEBUG
            // So the complications can be looked at with the sample's numbers.
            if launch.has("-shareSnapshot") { snapshotURL = WristSnapshotFile.appGroupURL }
            #endif
        } else {
            shared = SharedContainer()
        }
        self.init(store: store, shared: shared, snapshotURL: snapshotURL, usesSystemServices: !launch.isUITesting)
        if !memory { family = FamilySync(shared: shared) }
    }

    init(store: RecordStore, shared: SharedContainer, snapshotURL: URL?, usesSystemServices: Bool) {
        self.store = store
        self.shared = shared
        self.snapshotURL = snapshotURL
        self.usesSystemServices = usesSystemServices
        reload()
        // The phone's, the iPad's and the Mac's changes, as CloudKit imports them.
        storeObserver = store.observeChanges { [weak self] in self?.reloadIfChanged() }
        // Stadig Lift's calendar and summary and the life modes, as the family's database brings them.
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
    }

    // MARK: Loading

    /// Re-reads the kinds of record that changed since the last read, then recomputes today.
    func reload() {
        if needsReading(ProfileRecord.self) { profile = store.all(ProfileRecord.self).first?.profile }
        if needsReading(MacroSettings.self) {
            settings = MacroSettings.inForce(store.all(MacroSettings.self)) ?? MacroSettings(id: MacroSettings.singletonID)
        }
        if needsReading(FoodEntry.self) { entries = store.all(FoodEntry.self).sorted { $0.date < $1.date } }
        if needsReading(WeighIn.self) { weighIns = store.all(WeighIn.self).sorted { $0.date < $1.date } }
        if needsReading(DayStatus.self) { dayStatus = store.all(DayStatus.self) }
        if needsReading(PhasePlan.self) { plan = store.all(PhasePlan.self).first }
        if needsReading(CheckIn.self) { checkIns = store.all(CheckIn.self) }
        if needsReading(Supplement.self) {
            supplements = store.all(Supplement.self).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if needsReading(SupplementLog.self) { supplementLogs = store.all(SupplementLog.self).sorted { $0.date < $1.date } }
        if needsReading(WaterLog.self) { water = store.all(WaterLog.self).sorted { $0.date < $1.date } }
        if needsReading(Fast.self) { fasts = store.all(Fast.self).sorted { $0.start < $1.start } }
        if needsReading(LifeModeRecord.self) { ownLifeModes = store.all(LifeModeRecord.self).map(\.period) }
        lastRevision = store.revision
        readShared(recompute: false)
        recompute()
    }

    /// Picks up changes that arrived from iCloud.
    func reloadIfChanged() {
        if store.revision != lastRevision { reload() }
    }

    /// On launch and each return to the app, perhaps on a later day or hours on: catches up with the
    /// store, and with the clock, which moves what "now" ranks and which doses are due.
    func refresh() {
        if store.revision != lastRevision {
            reload()
        } else {
            recompute()
        }
    }

    private func needsReading<T: StoredRecord>(_ type: T.Type) -> Bool {
        let revision = store.revision(of: type)
        guard readRevisions[T.kind] != revision else { return false }
        readRevisions[T.kind] = revision
        return true
    }

    /// What the other apps published, as the family's database brought it to this Watch. Read only:
    /// the phone merges and writes the shared files; the Watch never does.
    func readShared(recompute again: Bool = true) {
        let lift = shared.read(.summary(.liftTrack))
        let calendar = shared.read(.calendar)
        let sharedProfile = shared.read(.profile)
        let lifeModes = LifeModePeriod.merge([shared.read(.lifeModes) ?? [], ownLifeModes]).live
        let changed = lift != self.lift || calendar != self.calendar || sharedProfile != self.sharedProfile || lifeModes != self.lifeModes
        guard changed else { return }
        self.lift = lift
        self.calendar = calendar
        self.sharedProfile = sharedProfile
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    /// The setup answers in force: this app's own, or a newer copy edited in Stadig Lift (which the
    /// phone takes up into the store; the Watch just reads it).
    private var currentProfile: SharedProfile? {
        guard let profile else { return nil }
        guard let sharedProfile, sharedProfile.updatedAt > profile.updatedAt else { return profile }
        return sharedProfile
    }

    private func state(now: Date) -> MacroState? {
        guard let profile = currentProfile else { return nil }
        return MacroState(
            profile: profile, settings: settings, entries: entries, weighIns: weighIns, dayStatus: dayStatus, plan: plan,
            lifeModes: lifeModes, calendar: calendar, lift: lift, checkIns: checkIns, supplements: supplements,
            supplementLogs: supplementLogs, water: water, fasts: fasts, today: Day(now), now: now)
    }

    /// Runs the analysis off the main thread (it reads the whole history) and shows its today.
    func recompute() {
        let profile = currentProfile
        onboarded = profile != nil && settings.onboardedAt != nil
        units = profile?.units ?? .regional
        generation += 1
        analysisTask?.cancel()
        guard onboarded, let state = state(now: Date()) else {
            today = nil
            loaded = true
            return
        }
        let generation = generation
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let wrist = WristToday(state: state, analysis: MacroAnalyst.analyse(state))
            guard !Task.isCancelled else { return }
            await self?.show(wrist, generation: generation)
        }
    }

    /// Waits until the analysis running now, and any a newer change started meanwhile, has shown
    /// today and written the complications' snapshot, or until `limit` has passed.
    func analysisFinished(within limit: Duration) async {
        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(finished)
            let timeout = Task {
                try? await Task.sleep(for: limit)
                once.resume()
            }
            Task { [weak self] in
                var waited: Task<Void, Never>?
                while let task = self?.analysisTask, task != waited {
                    await task.value
                    waited = task
                }
                timeout.cancel()
                once.resume()
            }
        }
    }

    private func show(_ wrist: WristToday, generation: Int) {
        guard generation == self.generation else { return }
        today = wrist
        loaded = true
        writeSnapshot(WristSnapshot(wrist))
    }

    /// The complications' numbers, written only when they change, and the complications reloaded then.
    private func writeSnapshot(_ snapshot: WristSnapshot) {
        if WristSnapshotFile.save(snapshot, to: snapshotURL), usesSystemServices { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Logging

    /// One tap in Log Again: the same food and amount, now.
    func log(_ item: LogAgainItem) {
        let entry = LogAgain.copy(item.template, to: Date())
        save([entry], message: "Logged \(FoodLabel.short(entry.name))")
    }

    /// Yesterday's meal again: every food of it, now.
    func log(_ moment: Moment) {
        let copies = LogAgain.copy(moment, to: Date())
        save(copies, message: copies.count == 1 ? "Logged \(FoodLabel.short(copies[0].name))" : "Logged \(copies.count) foods")
    }

    private func save(_ new: [FoodEntry], message: String) {
        guard !new.isEmpty else { return }
        store.save(LogAgain.settled(new, now: Date()))
        reload()
        let kcal = new.map(\.nutrients.kcal).reduce(0, +)
        confirm(WristToast(message: "\(message) · \(WristFormat.kcal(kcal))", undo: .entries(new.map(\.id))))
    }

    func addWater(_ glass: WaterGlass) {
        let log = WaterLog(date: Date(), ml: glass.ml)
        store.save(log)
        reload()
        confirm(WristToast(message: "Water · \(WristFormat.volume(glass.ml, ounces: units.weight == .lb))", undo: .water(log.id)))
    }

    /// Marks doses taken now, replacing a skip.
    func take(_ doses: [DueDose]) {
        guard let day = today?.day else { return }
        let open = doses.filter { !$0.taken }
        guard !open.isEmpty else { return }
        for dose in open {
            if let log = dose.log { store.delete(SupplementLog.self, id: log.id) }
        }
        let now = Date()
        let logs = open.map { SupplementLog(supplement: $0.supplement, doseID: $0.dose.id, date: now, day: day, count: $0.dose.count) }
        store.save(logs)
        reload()
        let message = open.count == 1 ? "Took \(open[0].supplement.name)" : "Took \(open.count) supplements"
        confirm(WristToast(message: message, undo: .doses(logs.map(\.id))))
    }

    /// A weigh-in typed here; nothing outside what the trend can use is saved.
    func weighIn(kg: Double) {
        guard Weight.isPlausible(kg: kg) else { return }
        let weighIn = WeighIn(date: Date(), kg: kg)
        store.save(weighIn)
        reload()
        confirm(WristToast(message: "Weighed in · \(WristFormat.weight(kg, unit: units.weight))", undo: .weighIn(weighIn.id)))
    }

    /// Marks today complete, or takes the mark off. The day's id is kept, so two devices write one record.
    func setDayComplete(_ complete: Bool) {
        guard let day = today?.day else { return }
        let before = setState(complete ? .complete : nil, for: day)
        confirm(WristToast(message: complete ? "Day complete" : "Day reopened", undo: .dayState(before)))
    }

    /// Returns the state the day had before.
    @discardableResult
    private func setState(_ state: DayState?, for day: Day) -> DayState? {
        let existing = dayStatus.filter { $0.day == day }
        for status in existing { store.delete(DayStatus.self, id: status.id) }
        if let state { store.save(DayStatus(id: existing.first?.id ?? UUID(), day: day, state: state)) }
        reload()
        return existing.first?.state
    }

    /// Starts a fast from the end of the last meal. Goals over a day start on the phone, where the
    /// safety notes are.
    func startFast(goalHours: Double) {
        guard let today else { return }
        let fast = Fast(start: today.suggestedFastStart, goalHours: min(goalHours, FastSafety.screenHours))
        store.save(fast)
        reload()
        confirm(WristToast(message: "Fasting · goal \(WristFormat.hours(fast.goalHours))", undo: .fastStarted(fast.id)))
    }

    func endFast() {
        guard var fast = today?.fast?.fast else { return }
        let before = fast
        fast.end = max(fast.start, Date())
        fast.updatedAt = Date()
        store.save(fast)
        reload()
        confirm(WristToast(message: "Fast ended · \(WristFormat.duration(Date().timeIntervalSince(fast.start)))", undo: .fastEnded(before)))
    }

    func undo(_ toast: WristToast) {
        switch toast.undo {
        case .fastStarted(let id): store.delete(Fast.self, id: id)
        case .fastEnded(let fast):
            var fast = fast
            fast.end = nil
            fast.updatedAt = Date()
            store.save(fast)
        case .entries(let ids): for id in ids { store.delete(FoodEntry.self, id: id) }
        case .water(let id): store.delete(WaterLog.self, id: id)
        case .doses(let ids): for id in ids { store.delete(SupplementLog.self, id: id) }
        case .weighIn(let id): store.delete(WeighIn.self, id: id)
        case .dayState(let state):
            if let day = today?.day { setState(state, for: day) }
        }
        if self.toast?.id == toast.id { self.toast = nil }
        reload()
        WKInterfaceDevice.current().play(.click)
    }

    private func confirm(_ toast: WristToast) {
        self.toast = toast
        WKInterfaceDevice.current().play(.success)
    }

    #if DEBUG
    /// Saves records straight into the store, for the sample data.
    func seed(_ save: (RecordStore) -> Void) {
        save(store)
        reload()
    }

    /// The analysis now, on this thread, for the sample data to start a plan from.
    func analyseNow() -> MacroAnalysis? {
        state(now: Date()).map(MacroAnalyst.analyse)
    }
    #endif
}

/// A continuation resumed by whichever of two waits ends first, and only once.
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
