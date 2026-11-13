import ExerciseLibrary
import Foundation
import HealthBridge
import LiftEngine
import OSLog
import Observation
import SystemCore
import SystemPurchases
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.stadig.lift", category: "app")

/// The app's destinations. The iPhone's tab bar has Today, Plan, Progress and Body; the sidebar on
/// the iPad, the Mac and Vision Pro adds Program, Library and History.
enum AppTab: String, Hashable, CaseIterable {
    case today, plan, program, library, history, progress, body

    var title: String {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .program: "Program"
        case .library: "Library"
        case .history: "History"
        case .progress: "Progress"
        case .body: "Body"
        }
    }

    var symbol: String {
        switch self {
        case .today: "dumbbell"
        case .plan: "calendar"
        case .program: "list.bullet.rectangle"
        case .library: "books.vertical"
        case .history: "clock.arrow.circlepath"
        case .progress: "chart.line.uptrend.xyaxis"
        case .body: "figure.arms.open"
        }
    }

    /// The tab that reaches a sidebar destination where there's no sidebar (an iPhone, an iPad in a
    /// narrow split): the block's days on Plan for the program and the library, and History behind
    /// Progress, as on the iPhone.
    var tabBarFallback: AppTab {
        switch self {
        case .program, .library: .plan
        case .history: .progress
        case .today, .plan, .progress, .body: self
        }
    }
}

/// What the menu bar asks of the session on screen.
enum SessionRequest: Hashable {
    case finish, discard
}

/// A sheet the menu bar (or a shortcut) asks for, shown over whichever destination is open.
enum AppSheet: String, Identifiable {
    case logActivity, checkIn, measurements, nextBlock

    var id: String { rawValue }
}

/// The app's state: records from Stadig Lift's own synced store, what other apps published to the
/// shared container, what Health knows, and the analysis computed from all of it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel(launch: .current)
    /// What Health records this app wrote carry as their source: the current id and the one it had
    /// before the 2026-10 rename, so samples saved before it still count as the app's own.
    static let ownBundlePrefixes = ["dev.svindland.stadig.lift", "dev.svindland.lifttrack"]

    let store: RecordStore
    let shared: SharedContainer
    let catalog = ExerciseCatalog()
    let purchases: Purchases
    /// Where a session in progress is kept, so it survives the app being closed.
    let liveURL: URL
    /// Where the widgets' snapshot is written: the App Group, or a scratch folder when nothing is kept.
    let widgetURL: URL?

    // Records.
    private(set) var profile: SharedProfile?
    private(set) var settings = LiftSettings(id: LiftSettings.singletonID)
    private(set) var gym = Gym.preset(.fullGym, unit: UnitPreference.regional.weight)
    private(set) var sessions: [SessionRecord] = []
    private(set) var activities: [ActivityLog] = []
    private(set) var measurements: [BodyMeasurements] = []
    private(set) var photos: [ProgressPhoto] = []
    private(set) var mobility: [MobilityResult] = []
    private(set) var benchmarks: [BenchmarkResult] = []
    private(set) var mesocycles: [Mesocycle] = []
    private(set) var lifeModes: [LifeModePeriod] = []

    // From Health.
    var recovery: [RecoveryDay] = []
    var steps: [StepDay] = []
    @ObservationIgnored private var lastHealthRefresh: Date?
    /// When the Health observer started, until the call HealthKit makes as it starts (which brings
    /// nothing new) has come.
    @ObservationIgnored private var healthObserverStarted: Date?
    var bodyweightKg: Double?
    /// When Health's weight was measured, so a later one typed on the tape counts instead.
    var bodyweightDate: Date?
    /// From Health, only when it's from the last two weeks.
    var bodyFatPercent: Double?
    var vo2Max: Double?
    var restingHeartRate: Double?

    // From the shared container.
    private(set) var nutrition: NutritionSummary?
    /// A profile another app wrote before Stadig Lift was set up: onboarding reuses it.
    private(set) var sharedProfile: SharedProfile?
    /// What Stadig Macro published, for the scores it measures.
    private(set) var macroSummary: AppSummary?

    // Derived.
    private(set) var analysis: LiftAnalysis?
    /// The six scores as Your shape shows them: this app's, fresh, with Stadig Macro's once it's set
    /// up too (`StatsBoard`), so both apps give the same numbers.
    private(set) var stats: [StatLine] = []

    // Live session and presentation.
    var live: LiveSession? {
        didSet {
            persistLive()
            watchRestTime()
            // The Watch logging into this session gets a copy after every change, but not for each heart-rate reading.
            if let live, live.id != oldValue?.id || live.updatedAt != oldValue?.updatedAt { shareWithWatch() }
        }
    }
    /// The latest reading from the Watch during a session led from here, and when it came.
    private(set) var heartRate: Double?
    private(set) var heartRateAt: Date?
    @ObservationIgnored private var lastLivePersist = Date.distantPast
    @ObservationIgnored private var heartRateOnly = false
    /// Moves when a rest's time runs out, so what shows the rest redraws without the session changing.
    private var restsRunOut = 0
    @ObservationIgnored private var restTimer: Task<Void, Never>?
    @ObservationIgnored private var restTimerEnds: Date?
    var showSession = false
    var finished: SessionRecord?
    /// What the finished session's summary sets it against, taken as it ended.
    var finishedBaseline: SummaryBaseline?
    var tab: AppTab = .today
    var showSettings = false
    var sheet: AppSheet?
    /// Finish… or Discard… from the menu bar, for the session screen to ask about.
    var sessionRequest: SessionRequest?
    /// The exercise Library shows next, when another screen sent the person there.
    var libraryFocus: String?
    /// Sessions and outside activities as the History table shows them, newest first: rebuilt when
    /// either changes, not on every redraw.
    private(set) var historyRows: [HistoryRow] = []
    var today: Day = .today

    /// The shared container mirrored to the person's other devices through the family's CloudKit
    /// database; nil when nothing is kept (tests, UI tests, `-inMemoryStore`).
    @ObservationIgnored private(set) var family: FamilySync?
    /// On a launch that found Stadig Lift not set up: the person's training on its way from iCloud,
    /// which onboarding waits for. Nil when there was nothing to look for.
    private(set) var arrival: ICloudArrival?
    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var storeObserver: AnyObject?
    @ObservationIgnored private var healthObserver: AnyObject?
    @ObservationIgnored private var lastRevision = -1
    /// How many times the records have been read and the analysis run: a batch of changes should
    /// cost one, however many records it touches.
    @ObservationIgnored private(set) var reloads = 0
    /// The store's `revision(of:)` for each kind when it was last read, so a save re-reads only its kind.
    @ObservationIgnored private var readRevisions: [String: Int] = [:]

    /// Stadig Lift's own synced store and the App Group, or, when nothing is to be kept (tests, UI
    /// tests, `-inMemoryStore`), an in-memory store and a fresh folder for the shared files and the
    /// session in progress, so a test or a sample run never writes where the other apps read and
    /// never picks up a real session left open.
    convenience init(launch: LaunchOptions) {
        // Tests and UI tests: no Health prompts, reads or writes.
        if launch.isQuiet { HealthBridge.shared.disable() }
        let memory = launch.usesInMemoryStore
        let store = RecordStore(name: "LiftTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.stadig.lift", inMemory: memory)
        let files = memory ? Files.scratch() : Files.app
        #if DEBUG
        if launch.has("-resetData") {
            store.eraseAll()
            try? FileManager.default.removeItem(at: files.liveURL)
        }
        #endif
        self.init(store: store, shared: files.shared, liveURL: files.liveURL, widgetURL: files.widgetURL)
        if !memory { family = FamilySync(shared: files.shared) }
        #if DEBUG
        // The wait a second device shows while its data comes down, over a store that never gets any.
        if launch.has("-simulateICloudData"), !onboarded { arrival = ICloudArrival(store: store) { .records } }
        #endif
    }

    /// Everything outside the store the model reads or writes: tests pass a store in memory and a
    /// temporary folder for the rest.
    init(store: RecordStore, shared: SharedContainer, liveURL: URL, widgetURL: URL?) {
        self.store = store
        self.shared = shared
        self.liveURL = liveURL
        self.widgetURL = widgetURL
        purchases = Purchases(.lift, store: store)
        reload()
        // A second device or a reinstall: onboarding waits while the person's data comes down.
        if !onboarded { arrival = ICloudArrival.start(for: store) }
        restoreLive()
        LiveActivityBridge.resume(live, catalog: catalog, unit: gym.unit)
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
        // Another device's changes, as CloudKit imports them while the app is open: a second device
        // or a reinstall leaves onboarding as soon as the person's data arrives.
        storeObserver = store.observeChanges { [weak self] in self?.reloadIfChanged() }
    }

    /// Where the model's files live outside its store.
    struct Files {
        var shared: SharedContainer
        var liveURL: URL
        var widgetURL: URL?

        /// The App Group the other apps and the widgets read, and Application Support for the session.
        static var app: Files {
            Files(
                shared: SharedContainer(), liveURL: URL.applicationSupportDirectory.appending(path: "live-session.json"),
                widgetURL: WidgetSnapshot.appGroupURL)
        }

        /// A fresh folder of its own, for a launch that keeps nothing: a sample run or a test never
        /// writes where the other apps read, and never picks up a real session left open.
        static func scratch(in folder: URL = URL.temporaryDirectory.appending(path: "LiftTrack \(UUID().uuidString)", directoryHint: .isDirectory))
            -> Files
        {
            // The folder and never an App Group: a made-up group id isn't enough, since a simulator
            // may hand out a folder for any group.
            Files(
                shared: SharedContainer(directory: folder.appending(path: "SystemShared", directoryHint: .isDirectory)),
                liveURL: folder.appending(path: "live-session.json"),
                widgetURL: folder.appending(path: "widget.json"))
        }
    }

    var onboarded: Bool { profile != nil && settings.onboardedAt != nil }

    var units: UnitPreference { profile?.units ?? .regional }

    // MARK: Loading

    /// Re-reads the kinds of record that changed since the last read, then recomputes. Unchanged
    /// kinds (the photos in particular) aren't read or sorted again, but the analysis still runs over
    /// everything.
    func reload() {
        reloads += 1
        let profileChanged = needsReading(ProfileRecord.self)
        if profileChanged { profile = store.all(ProfileRecord.self).first?.profile }
        let settingsChanged = needsReading(LiftSettings.self)
        if settingsChanged {
            // The record under the fixed id, which every device saves new settings under; settings
            // saved before it keep their own id, and the newest of those counts until there's one.
            let all = store.all(LiftSettings.self)
            settings = all.first { $0.id == LiftSettings.singletonID } ?? all.first ?? LiftSettings(id: LiftSettings.singletonID)
        }
        if needsReading(Gym.self) || settingsChanged || profileChanged {
            let gyms = store.all(Gym.self)
            gym = gyms.first { $0.id == settings.gymID } ?? gyms.first ?? Gym.preset(profile?.equipment ?? .fullGym, unit: units.weight)
        }
        let sessionsChanged = needsReading(SessionRecord.self)
        if sessionsChanged { sessions = store.all(SessionRecord.self).sorted { $0.start < $1.start } }
        let activitiesChanged = needsReading(ActivityRecord.self)
        if activitiesChanged { activities = store.all(ActivityRecord.self).map(\.log).sorted { $0.start < $1.start } }
        if needsReading(MeasurementRecord.self) {
            measurements = store.all(MeasurementRecord.self).map(\.measurements).sorted { $0.day < $1.day }
        }
        if needsReading(ProgressPhoto.self) { photos = store.all(ProgressPhoto.self).sorted { $0.day < $1.day } }
        if needsReading(MobilityRecord.self) { mobility = store.all(MobilityRecord.self).map(\.result).sorted { $0.day < $1.day } }
        if needsReading(BenchmarkRecord.self) { benchmarks = store.all(BenchmarkRecord.self).map(\.result).sorted { $0.day < $1.day } }
        if needsReading(Mesocycle.self) { mesocycles = store.all(Mesocycle.self).sorted { $0.block.start < $1.block.start } }
        readShared(recompute: false)
        recompute()
        // After the analysis: the top sets are read with the trust it rebuilt from these sessions.
        if sessionsChanged || activitiesChanged {
            historyRows = HistoryRow.rows(
                sessions: sessions, activities: activities, catalog: catalog, trust: analysis?.trust ?? TrustState(prior: 0.5))
        }
        lastRevision = store.revision
    }

    /// Whether records of a kind changed since this model last read them, noting that it's reading them now.
    private func needsReading<T: StoredRecord>(_ type: T.Type) -> Bool {
        let revision = store.revision(of: type)
        guard readRevisions[T.kind] != revision else { return false }
        readRevisions[T.kind] = revision
        return true
    }

    /// Picks up changes that arrived from iCloud.
    func reloadIfChanged() {
        if store.revision != lastRevision { reload() }
    }

    /// What Stadig Macro published, and the profile and life modes both apps share. Our own writes
    /// notify us too, so this only recomputes when something actually changed.
    func readShared(recompute again: Bool = true) {
        let nutrition = shared.read(.nutrition)
        let sharedProfile = shared.read(.profile)
        let lifeModes = syncLifeModes()
        let macroSummary = shared.read(.summary(.macroTrack))
        let changed =
            nutrition != self.nutrition || sharedProfile != self.sharedProfile || lifeModes != self.lifeModes || macroSummary != self.macroSummary
        guard changed else { return }
        self.macroSummary = macroSummary
        self.nutrition = nutrition
        self.sharedProfile = sharedProfile
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    /// Life modes from every app: the shared file and this app's synced copies merged, the newest
    /// edit or delete of each winning (deletes are kept as tombstones so they keep spreading). What
    /// came from elsewhere is kept here too, so it reaches this app on the person's other devices,
    /// and the merged list goes back to the file, so the other apps hear about this app's changes and
    /// what iCloud brought. The file goes first so that on a tie its copy wins and no app rewrites it.
    /// Returns the periods in force, end after start.
    private func syncLifeModes() -> [LifeModePeriod] {
        let own = store.all(LifeModeRecord.self).map(\.period)
        let file = shared.read(.lifeModes) ?? []
        let merged = LifeModePeriod.merge([file, own])
        let mine = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arrived = merged.filter { mine[$0.id] != $0 }
        if !arrived.isEmpty { store.save(arrived.map(LifeModeRecord.init)) }
        if merged != file {
            do {
                try shared.write(merged, to: .lifeModes, by: .liftTrack)
            } catch {
                appLog.error("Couldn't share the life modes: \(error.localizedDescription)")
            }
        }
        return merged.live.map { $0.normalized() }
    }

    var state: LiftState? {
        guard let profile else { return nil }
        return LiftState(
            profile: profile, settings: settings, gym: gym, catalog: catalog, sessions: sessions, activities: activities,
            measurements: measurements, mobility: mobility, benchmarks: benchmarks, mesocycles: mesocycles,
            lifeModes: lifeModes, recovery: recovery, steps: steps, bodyweightKg: bodyweightKg, bodyweightDate: bodyweightDate,
            bodyFatPercent: bodyFatPercent, vo2Max: vo2Max, restingHeartRate: restingHeartRate, nutrition: nutrition, today: today)
    }

    func recompute() {
        today = .today
        guard let state else {
            analysis = nil
            return
        }
        let analysis = Analyst.analyse(state)
        self.analysis = analysis
        publish(state, analysis)
    }

    @ObservationIgnored private var lastPublished: (summary: AppSummary, calendar: SystemCalendar)?

    /// The profile in the shared file, which the other apps plan from.
    private func share(_ profile: SharedProfile) {
        do {
            try shared.write(profile, to: .profile, by: .liftTrack)
            sharedProfile = profile
        } catch {
            appLog.error("Couldn't share the profile: \(error.localizedDescription)")
        }
    }

    /// Small summaries for Stadig Macro, the widgets and the Watch, written only when they change.
    private func publish(_ state: LiftState, _ analysis: LiftAnalysis) {
        // Without their stamps: compared with what was last published here, then with the files on
        // disk (after a relaunch), so readers are woken and "updated" moves only when something did.
        var summary = Analyst.summary(state, analysis)
        let lines = StatsBoard.lines(lift: summary, macro: macroSummary, today: today)
        if lines != stats { stats = lines }
        var calendar = analysis.calendar
        summary.updated = .distantPast
        calendar.updated = .distantPast
        if lastPublished.map({ $0.summary != summary || $0.calendar != calendar }) ?? true {
            do {
                try shared.writeIfChanged(summary, to: .summary(.liftTrack), by: .liftTrack, stamp: \.updated)
                try shared.writeIfChanged(calendar, to: .calendar, by: .liftTrack, stamp: \.updated)
                lastPublished = (summary, calendar)
            } catch {
                appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
            }
        }
        if let profile, let shareable = profile.sharing(over: sharedProfile, writtenBy: shared.envelope(.profile)?.writtenBy, now: Date()) {
            share(shareable)
        }
        WidgetBridge.update(self)
        #if os(iOS)
        WatchLink.shared.publish(self)
        #endif
    }

    // MARK: Links

    /// The widget's link (lifttrack://start) starts today's session, or brings back the one running;
    /// the Live Activity's (lifttrack://session) brings the running one back.
    func open(_ url: URL) {
        guard url.scheme == "lifttrack" else { return }
        switch url.host() {
        case "start":
            startToday()
        case "session":
            if live != nil { showSession = true }
        default:
            break
        }
    }

    // MARK: Saving

    func save(profile: SharedProfile) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        share(profile)
        reload()
    }

    /// Saves what a settings screen changed, from `original` (the copy it opened with) to `edited`,
    /// field by field onto the latest profile: a field left alone there keeps whatever synced in
    /// meanwhile, here or from another app. Nothing is saved when nothing changed. Returns the
    /// profile as saved, for the screen to carry on from.
    @discardableResult
    func save(profileEdits edited: SharedProfile, from original: SharedProfile) -> SharedProfile? {
        guard edited != original else { return nil }
        var latest = profile ?? original
        func take<T: Equatable>(_ field: WritableKeyPath<SharedProfile, T>) {
            if edited[keyPath: field] != original[keyPath: field] { latest[keyPath: field] = edited[keyPath: field] }
        }
        take(\.goals)
        take(\.schedule.daysPerWeek)
        take(\.schedule.minutesPerSession)
        take(\.schedule.preferredDays)
        take(\.experience)
        take(\.recurring)
        take(\.sex)
        take(\.birthYear)
        take(\.heightCm)
        take(\.units.weight)
        take(\.units.length)
        save(profile: latest)
        return profile
    }

    /// The gym's counterpart of `save(profileEdits:from:)`: only what the screen changed, onto the
    /// gym as it is now (`Gym.applying(_:from:)`).
    @discardableResult
    func save(gymEdits edited: Gym, from original: Gym) -> Gym? {
        guard edited != original else { return nil }
        save(gym: gym.applying(edited, from: original))
        return gym
    }

    func save(settings: LiftSettings) {
        var settings = settings
        if settings.selfReportedPhase != self.settings.selfReportedPhase { settings.selfReportedPhaseSince = .today }
        settings.updatedAt = Date()
        store.save(settings)
        reload()
    }

    func save(gym: Gym) {
        var gym = gym
        gym.updatedAt = Date()
        store.save(gym)
        if settings.gymID != gym.id {
            var s = settings
            s.gymID = gym.id
            s.updatedAt = Date()
            store.save(s)
        }
        reload()
    }

    func save(_ mesocycle: Mesocycle) {
        var m = mesocycle
        m.updatedAt = Date()
        store.save(m)
        reload()
    }

    func save(activity: ActivityLog) {
        store.save(ActivityRecord(log: activity))
        reload()
    }

    func delete(activity id: UUID) {
        store.delete(ActivityRecord.self, id: id)
        reload()
    }

    func save(measurements m: BodyMeasurements) {
        store.save(MeasurementRecord(m))
        reload()
        Task { await HealthBridge.shared.saveMeasurements(m) }
    }

    func delete(measurement id: UUID) {
        store.delete(MeasurementRecord.self, id: id)
        reload()
        // Its waist and body fat leave Health too, or the body fat would come back as Health's latest.
        Task {
            await HealthBridge.shared.deleteMeasurements(id: id)
            await refreshHealth()
        }
    }

    func save(photo: ProgressPhoto) {
        store.save(photo)
        reload()
    }

    func delete(photo id: UUID) {
        store.delete(ProgressPhoto.self, id: id)
        reload()
    }

    func save(mobility results: [MobilityResult]) {
        store.save(results.map { MobilityRecord($0) })
        reload()
    }

    func save(benchmark: BenchmarkResult) {
        store.save(BenchmarkRecord(benchmark))
        reload()
    }

    /// Saves a period with its dates in order, refusing one that can't apply (see `isValid`).
    @discardableResult
    func save(lifeMode period: LifeModePeriod) -> Bool {
        var period = period.normalized()
        guard period.isValid else {
            appLog.error("Not saving an invalid \(period.kind.label, privacy: .public) period")
            return false
        }
        period.updatedAt = Date()
        store.save(LifeModeRecord(period))
        // Shared by the reload, merged with the file.
        reload()
        return true
    }

    /// A delete is kept as a tombstone and shared like an edit, so it reaches the app that made the
    /// period and the person's other devices instead of being brought back by their copies.
    func delete(lifeMode id: UUID) {
        guard let period = lifeModes.first(where: { $0.id == id }) else { return }
        store.save(LifeModeRecord(period.deleted(at: Date())))
        reload()
    }

    /// Whether "End it now" applies: the period has started and hasn't ended. One still to come has
    /// nothing to end; deleting it calls it off.
    func canEnd(_ period: LifeModePeriod) -> Bool {
        period.start <= today && (period.end.map { $0 >= today } ?? true)
    }

    /// Ends a period yesterday, so today is back to normal. No range ends before it starts, so one
    /// that started today is called off, except an injury or illness: that keeps today, and the ramp
    /// or the lighter week back follows from tomorrow.
    func end(lifeMode period: LifeModePeriod) {
        var period = period
        let yesterday = today.adding(days: -1)
        if period.start <= yesterday {
            period.end = yesterday
            save(lifeMode: period)
        } else {
            switch period.kind {
            case .injury, .illness:
                period.end = period.start
                save(lifeMode: period)
            case .vacation, .crunch:
                delete(lifeMode: period.id)
            }
        }
    }

    /// Deletes what a History row stands for: the session (and its workout in Health) or the activity.
    func delete(historyRow row: HistoryRow) {
        delete(historyRows: [row])
    }

    /// Deletes what several History rows stand for, then reads the records once: the analysis runs
    /// over everything, so a reload per row would make a long selection slow to delete.
    func delete(historyRows rows: [HistoryRow]) {
        guard !rows.isEmpty else { return }
        for row in rows {
            if row.isSession { store.delete(SessionRecord.self, id: row.id) } else { store.delete(ActivityRecord.self, id: row.id) }
        }
        reload()
        let workouts = rows.filter(\.isSession).map(\.id)
        guard !workouts.isEmpty else { return }
        Task {
            for id in workouts { await HealthBridge.shared.deleteWorkout(id: id) }
        }
    }

    func delete(session id: UUID) {
        store.delete(SessionRecord.self, id: id)
        reload()
        Task { await HealthBridge.shared.deleteWorkout(id: id) }
    }

    // MARK: Onboarding

    /// Saves the shared setup answers and Stadig Lift's own, then starts the assessment. On a second
    /// device or after a reinstall, the person's settings, gym and block can sync in while they
    /// answer: those are kept, rather than replaced on every device by a new assessment, and only the
    /// answers just given are saved.
    func completeOnboarding(profile: SharedProfile, settings: LiftSettings, gym: Gym, measurements: BodyMeasurements?) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        share(profile)
        if let measurements, !measurements.isEmpty { store.save(MeasurementRecord(measurements)) }
        reload()
        guard !store.all(LiftSettings.self).contains(where: { $0.onboardedAt != nil }) else { return }
        var settings = settings
        // Under the one id every device uses, so two devices set up apart converge on the newest.
        settings.id = LiftSettings.singletonID
        settings.gymID = gym.id
        settings.onboardedAt = Date()
        // A block that synced in ahead of its settings carries on, counted from its start.
        settings.assessmentStart = mesocycles.map(\.block.start).min() ?? .today
        if settings.selfReportedPhase != nil { settings.selfReportedPhaseSince = .today }
        settings.updatedAt = Date()
        store.save(gym)
        store.save(settings)
        reload()
        guard mesocycles.isEmpty else { return }
        store.save(generate(kind: .assessment, start: .today))
        reload()
    }

    // MARK: Blocks

    var currentMesocycle: Mesocycle? { analysis?.mesocycle }

    /// Builds a mesocycle from everything known right now. Not saved until accepted.
    func generate(kind: BlockKind, start: Day, phase: NutritionPhase? = nil) -> Mesocycle {
        guard let profile else { fatalError("generate before onboarding") }
        let phase = phase ?? analysis?.phase ?? .assumedMaintenance
        let weeks =
            kind == .assessment
            ? (profile.experience.assessmentWeeks)
            : BlockScheduler.loadingWeeks(phase: phase.effects, experience: profile.experience)
        return ProgramGenerator.generate(generatorInput(profile: profile, gym: gym, kind: kind, start: start, loadingWeeks: weeks, phase: phase))
    }

    /// Everything the generator weighs, from what's known now: a new block and a day refitted to
    /// other minutes see the same fatigue and priorities. Internal for the tests.
    func generatorInput(
        profile: SharedProfile, gym: Gym, kind: BlockKind, start: Day, loadingWeeks: Int,
        phase: NutritionPhase
    ) -> GeneratorInput {
        GeneratorInput(
            profile: profile, settings: settings, gym: gym, catalog: catalog, kind: kind, start: start, loadingWeeks: loadingWeeks, phase: phase,
            strength: analysis?.strength, physique: analysis?.physique, agility: analysis?.agility, endurance: analysis?.endurance,
            fatigue: analysis?.fatigue, injuries: analysis?.life.injuries ?? [],
            // The block running now, not one already accepted to follow it.
            previous: analysis?.mesocycle ?? mesocycles.last,
            stalled: Set(analysis?.stalls.filter { $0.reading == .programming }.map(\.exerciseID) ?? []),
            trust: analysis?.trust ?? TrustState(experience: profile.experience))
    }

    /// Takes the early deload the Fatigue Budget offers: its dates, worked out in the stored block's
    /// own dates (a vacation may have pushed the block back), so this week becomes the deload.
    func deloadNow(reason: String) {
        guard var m = currentMesocycle, let suggested = analysis?.suggestedDeload else { return }
        m.block.deloadStart = suggested.deloadStart
        m.block.endOverride = suggested.endOverride
        m.block.deloadReason = reason
        save(m)
    }

    /// Where a block planned now starts: today, or the day after the current block while it's still
    /// running, so its deload and check-in stay. An assessment gives way today.
    var nextBlockStart: Day {
        guard let block = analysis?.block else { return today }
        return block.end >= today && block.kind != .assessment ? max(today, block.end.adding(days: 1)) : today
    }

    /// Whether "Plan the next block" is offered now: the assessment is done (or can finish early), or
    /// the block is over or in the last days of its deload, and no next block is waiting already.
    var nextBlockOffered: Bool {
        guard let analysis, let block = analysis.block, analysis.upcoming == nil else { return false }
        let assessmentDone = analysis.assessment.map { $0.complete || $0.canFinishEarly } ?? false
        let ending = today > block.end || block.week(of: today) == .deload && today.days(until: block.end) <= 2
        return assessmentDone || ending
    }

    /// Replacements for a slot's exercise for the rest of the block: the same movement first,
    /// filtered by the gym, any injury and the exercises set aside.
    func swapCandidates(for exerciseID: String, limit: Int = 20) -> [Exercise] {
        Substitutions.candidates(
            for: catalog.resolve(exerciseID), in: catalog.all, availability: gym.availability,
            injuries: analysis?.life.injuries ?? [], avoid: settings.avoid, limit: limit)
    }

    /// Swaps one slot of one day for another exercise for the rest of the block, saying why on the
    /// slot. False when the block, day or slot isn't there, or it's the exercise already.
    @discardableResult
    func swap(slot slotID: UUID, day dayID: UUID, of mesocycleID: UUID, to exerciseID: String) -> Bool {
        guard var m = mesocycles.first(where: { $0.id == mesocycleID }), let d = m.days.firstIndex(where: { $0.id == dayID }) else { return false }
        for b in m.days[d].blocks.indices {
            guard let s = m.days[d].blocks[b].slots.firstIndex(where: { $0.id == slotID }) else { continue }
            let current = catalog.resolve(m.days[d].blocks[b].slots[s].exerciseID)
            guard current.id != exerciseID else { return false }
            m.days[d].blocks[b].slots[s].exerciseID = exerciseID
            m.days[d].blocks[b].slots[s].reason = "You swapped this in for \(current.name)."
            save(m)
            return true
        }
        return false
    }

    /// A day of a block fitted to other minutes, for a look at it before the day comes: the same
    /// fatigue and priorities a new block weighs, in the person's usual gym.
    /// Nothing is saved; Today's "Short on time?" is what refits a session.
    func refitted(_ day: PlannedDay, of mesocycle: Mesocycle, minutes: Int) -> PlannedDay? {
        guard let profile, let analysis else { return nil }
        var input = generatorInput(
            profile: profile, gym: gym, kind: mesocycle.block.kind, start: mesocycle.block.start, loadingWeeks: mesocycle.block.loadingWeeks,
            phase: analysis.phase)
        input.profile.schedule.minutesPerSession = minutes
        return ProgramGenerator.refit(day, minutes: minutes, input: input)
    }

    // MARK: Library

    /// Sets an exercise aside, or allows it back. One set aside is never programmed in a new block,
    /// and today's session swaps it out of the block it's in.
    func setAside(_ exerciseID: String, _ aside: Bool) {
        var s = settings
        if aside { s.avoid.insert(exerciseID) } else { s.avoid.remove(exerciseID) }
        guard s.avoid != settings.avoid else { return }
        save(settings: s)
    }

    /// The injuries in force today, as their periods, so an override can be saved on the right one.
    var activeInjuries: [LifeModePeriod] {
        lifeModes.filter { period in
            guard case .injury = period.kind else { return false }
            return canEnd(period)
        }
    }

    /// Allows an exercise an injury rules out, or sets one it allows aside again: the same override
    /// the injury's own list makes, saved on that period so every app and device sees it.
    func toggleInjuryOverride(for exercise: Exercise, in periodID: UUID) {
        guard var period = lifeModes.first(where: { $0.id == periodID }), case .injury(var injury) = period.kind else { return }
        injury.toggleOverride(for: exercise)
        period.kind = .injury(injury)
        save(lifeMode: period)
    }

    /// Opens Library on an exercise. Only where there's a sidebar: a narrow window has no Library
    /// tab, so its screens push the exercise in place instead.
    func show(inLibrary exerciseID: String) {
        libraryFocus = exerciseID
        tab = .library
    }

    /// The person's own history with an exercise.
    func record(for exercise: Exercise) -> ExerciseRecord {
        ExerciseRecord.of(analysis?.history[exercise.id] ?? [], exercise: exercise, trust: analysis?.trust ?? TrustState(prior: 0.5))
    }

    /// Saves the next block. An assessment finished early ends the day before it starts.
    func accept(nextBlock m: Mesocycle) {
        if var current = currentMesocycle, current.block.kind == .assessment, current.block.end >= m.block.start {
            current.block.endOverride = m.block.start.adding(days: -1)
            current.updatedAt = Date()
            store.save(current)
        }
        save(m)
    }

    // MARK: Sessions

    var environment: SessionEnvironment? {
        guard let analysis else { return nil }
        var environment = SessionEnvironment(
            catalog: catalog, gym: gymForToday, trust: analysis.trust, phase: analysis.phase.effects,
            bodyweightKg: state?.effectiveBodyweight, history: analysis.history,
            enduranceScore: analysis.endurance.score, heartRateGuidedRest: settings.heartRateGuidedRest)
        environment.heat = analysis.heat
        return environment
    }

    /// Thermometers read in Fahrenheit where weights are in pounds.
    var fahrenheit: Bool { (profile?.units.weight ?? gym.unit) == .lb }

    var gymForToday: Gym {
        guard let profile, let analysis else { return gym }
        let context = PlanningContext(
            catalog: catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust,
            phase: analysis.phase, life: analysis.life, history: [:], bodyweightKg: nil, enduranceScore: nil,
            sessionIndexInWeek: 0)
        return context.todaysGym
    }

    /// Today's session from the program, fitted to the minutes available if they differ.
    func plan(minutes: Int? = nil) -> SessionPlan? {
        guard let next = analysis?.next else { return nil }
        return plan(next.day, of: next, minutes: minutes, sessionIndexInWeek: next.doneThisWeek)
    }

    /// The session after today's in the program, planned as things stand: the Watch goes on to it
    /// once it has done today's, when it hasn't heard from here since (the phone left at home).
    func followingPlan() -> SessionPlan? {
        guard let next = analysis?.next else { return nil }
        return plan(next.followingDay, of: next, minutes: nil, sessionIndexInWeek: next.doneThisWeek + 1)
    }

    private func plan(_ planned: PlannedDay, of next: NextSession, minutes: Int?, sessionIndexInWeek: Int) -> SessionPlan? {
        guard let profile, let analysis else { return nil }
        var day = planned
        var minutesAvailable = minutes
        if let cap = analysis.life.maxMinutes { minutesAvailable = min(minutesAvailable ?? cap, cap) }
        if let minutesAvailable, minutesAvailable != next.mesocycle.minutesPerSession {
            var input = generatorInput(
                profile: profile, gym: gymForToday, kind: next.mesocycle.block.kind, start: next.mesocycle.block.start,
                loadingWeeks: next.mesocycle.block.loadingWeeks, phase: analysis.phase)
            input.profile.schedule.minutesPerSession = minutesAvailable
            day = ProgramGenerator.refit(planned, minutes: minutesAvailable, input: input)
        }
        var context = PlanningContext(
            catalog: catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust,
            phase: analysis.phase, life: analysis.life, history: analysis.history,
            bodyweightKg: state?.effectiveBodyweight, enduranceScore: analysis.endurance.score,
            sessionIndexInWeek: sessionIndexInWeek)
        context.heat = analysis.heat
        return SessionPlanner.plan(day, of: next.mesocycle, on: today, context: context)
    }

    /// Whether the menu's "Start Today's Session" can: no session running and a block to plan from.
    var canStartToday: Bool { live == nil && analysis?.next != nil }

    /// Today's session as Today plans it, or the one running brought back.
    func startToday() {
        if live != nil {
            showSession = true
        } else if let plan = plan() {
            start(plan)
        }
    }

    /// The session's exercises reordered by a drag; supersets move whole.
    func moveLive(items: IndexSet, to destination: Int) {
        update { $0.move(items: items, to: destination) }
    }

    func start(_ plan: SessionPlan) {
        // The device it ran on, as History shows it: "iPhone", "iPad", "Mac", "Apple Vision Pro".
        live = LiveSession(plan: plan, device: Platform.deviceName)
        showSession = true
        RestAlerts.shared.requestPermission()
        LiveActivityBridge.update(live, catalog: catalog, unit: gym.unit)
        heartRate = nil
        // A new session: what the Watch did with the last one is past.
        watchFollows = nil
        endedForWatch = nil
        #if os(iOS)
        // A workout on the Watch, mirrored here, for heart rate: warm-up, rests and conditioning.
        if WatchLink.shared.watchAppInstalled { Task { await WorkoutMirror.shared.startWatchWorkout() } }
        #endif
    }

    /// What the Watch sends during a session led from here: its readings, the sets logged on it, and
    /// the session ended there.
    func fromWatch(_ data: [Data]) {
        for item in data {
            guard let message = MirrorMessage(encoded: item) else { continue }
            switch message {
            case .heartRate(let bpm, let date):
                heartRate(bpm, at: date)
            case .join:
                watchFollows = live?.id
                // The context goes with the next copy, whatever the Watch was sent before.
                watchHasContextFor = nil
                shareWithWatch()
            case .changes(let changes):
                guard let live, let environment else { continue }
                watchFollows = live.id
                update { session in
                    for change in changes { session.take(change, environment: environment) }
                }
                // Even when nothing was new: the copy is how the Watch learns what landed.
                shareWithWatch()
            case .finishFromWatch(let id, let feedback):
                if live?.id == id {
                    watchFollows = id
                    finish(feedback: feedback)
                } else if let ended = endedForWatch, ended.id == id {
                    // Already over here; the Watch missed hearing so.
                    tellWatch(ended.message)
                }
            case .discardFromWatch(let id):
                if live?.id == id {
                    watchFollows = id
                    discardLive()
                } else if let ended = endedForWatch, ended.id == id {
                    tellWatch(ended.message)
                }
            case .finish, .discard, .session:
                break
            }
        }
    }

    private func heartRate(_ bpm: Double, at date: Date) {
        heartRate = bpm
        heartRateAt = date
        guard var session = live else { return }
        let recovered = session.record(heartRate: bpm, zones: heartRateZones, now: date)
        // Samples come every few seconds: they needn't hit the disk as often.
        heartRateOnly = true
        live = session
        heartRateOnly = false
        if recovered, settings.heartRateGuidedRest {
            update { $0.endRest() }
            RestAlerts.shared.heartRateRecovered()
        }
    }

    // MARK: The Watch logging into a session led from here

    /// The session the Watch has been sent the context for, so it goes with the first copy only.
    @ObservationIgnored private var watchHasContextFor: UUID?
    /// The session the Watch has joined (asked for it, or sent changes or an end for it). Messages
    /// keep going to it over WatchConnectivity when the mirrored workout drops (out of range for a
    /// minute), which nothing restarts from here.
    @ObservationIgnored private var watchFollows: UUID?
    /// The copy waiting a moment to go, so a burst of changes sends one; kept so a test can wait for it.
    @ObservationIgnored private(set) var watchShare: Task<Void, Never>?
    /// The latest copy for the Watch, waiting for the send over the workout before it to finish.
    @ObservationIgnored private var watchCopyWaiting: Data?
    @ObservationIgnored private var watchCopySend: Task<Void, Never>?
    /// The last session ended while the Watch was logging into it, and what it was told, for an end
    /// asked for on the Watch that arrives after the session is already over here.
    @ObservationIgnored private var endedForWatch: (id: UUID, message: MirrorMessage)?

    /// The Watch can be told things: over its mirrored workout, or over WatchConnectivity once it has
    /// joined the session.
    private var watchListening: Bool { workoutHandOff.watchConnected() || watchFollows != nil }

    /// The Watch's mirrored workout has connected (again): it gets the session, with its context.
    func watchJoined() {
        watchFollows = live?.id
        watchHasContextFor = nil
        shareWithWatch()
    }

    /// Sends the Watch a copy of the session a moment from now, so the copies for a burst of changes
    /// (a change, and the copy that says it landed; sixty changes after a reconnect) are one.
    private func shareWithWatch() {
        guard live != nil, watchListening, watchShare == nil else { return }
        watchShare = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.sendCopyToWatch()
            self?.watchShare = nil
        }
    }

    /// The session as it stands, stamped now. It goes over WatchConnectivity at once and over the
    /// workout one send at a time, the latest copy when the send before it is done: a send over the
    /// workout can hang, and the Watch drops a copy older than the one it has.
    private func sendCopyToWatch() {
        guard let live, watchListening else { return }
        var context: PhoneContext?
        if watchHasContextFor != live.id {
            let exercises = Dictionary(live.items.map { ($0.exerciseID, $0.plan) }, uniquingKeysWith: { first, _ in first })
            context = watchContext(plan: nil, exercises: exercises, withSwaps: false)
            if context != nil { watchHasContextFor = live.id }
        }
        guard let data = MirrorMessage.session(live.withoutHeartRate, context: context, sentAt: Date()).encoded() else { return }
        workoutHandOff.sendToWatchApp(data)
        guard workoutHandOff.watchConnected() else { return }
        watchCopyWaiting = data
        guard watchCopySend == nil else { return }
        let handOff = workoutHandOff
        watchCopySend = Task { [weak self] in
            while let data = self?.takeWatchCopy() {
                _ = await handOff.sendToWatch(data)
            }
            self?.watchCopySend = nil
        }
    }

    private func takeWatchCopy() -> Data? {
        defer { watchCopyWaiting = nil }
        return watchCopyWaiting
    }

    /// What the Watch needs to run or follow a session: the gym's loads, trust, zones, recent sets for
    /// its exercises (and their likely swaps, for a session the Watch runs itself), and first guesses
    /// at the weight for strength work with no history. `exercises` are by id, each with its planned item.
    func watchContext(plan: SessionPlan?, exercises: [String: PlannedItem], withSwaps: Bool) -> PhoneContext? {
        guard let analysis, let profile else { return nil }
        var ids = Set(exercises.keys)
        if withSwaps {
            for id in exercises.keys {
                let exercise = catalog.resolve(id)
                for option in Substitutions.candidates(for: exercise, in: catalog.all, availability: gym.availability, limit: 4) {
                    ids.insert(option.id)
                }
            }
        }
        var history: [String: [LoggedSet]] = [:]
        for id in ids {
            let sets = analysis.history[id] ?? []
            let days = Array(Set(sets.map { Day($0.date) })).sorted().suffix(4)
            history[id] = sets.filter { days.contains(Day($0.date)) }
        }
        let zones = HeartRateZones.estimated(age: profile.age(), resting: restingHeartRate)
        let todaysGym = gymForToday
        // Where the Watch's crown starts for exercises with no history yet.
        var startingLoads: [String: Double] = [:]
        for (id, item) in exercises where item.isStrength && (analysis.history[id] ?? []).isEmpty {
            let exercise = catalog.resolve(id)
            if let guess = StartingLoad.estimate(
                exercise, reps: item.repRange.middle, bodyweightKg: state?.effectiveBodyweight, sex: profile.sex,
                experience: profile.experience)
            {
                startingLoads[id] = todaysGym.increments(for: exercise.equipment).round(guess, down: true)
            }
        }
        var context = PhoneContext(
            plan: plan, upNext: nil, gym: todaysGym, trust: analysis.trust, phase: analysis.phase.effects,
            bodyweightKg: state?.effectiveBodyweight, history: history, enduranceScore: analysis.endurance.score,
            heartRateGuidedRest: settings.heartRateGuidedRest, zones: zones, units: profile.units, startingLoads: startingLoads)
        context.injuries = analysis.life.injuries
        context.avoid = settings.avoid
        return context
    }

    /// The rest being taken: nil once its time is up, though the session keeps it until the next set
    /// is logged (that set's rest is timed from it).
    var activeRest: RestState? {
        _ = restsRunOut
        guard let rest = live?.rest, rest.endsAt > Date() else { return nil }
        return rest
    }

    /// Wakes when the rest's time is up, so the session screen, the minimized session and the Live
    /// Activity move on to the next set whether or not anything else happens.
    private func watchRestTime() {
        let ends = live?.rest?.endsAt
        guard ends != restTimerEnds else { return }
        restTimerEnds = ends
        restTimer?.cancel()
        guard let ends, ends > Date() else { return }
        restTimer = Task { [weak self] in
            // A moment past the end, so the rest reads as over when it wakes.
            try? await Task.sleep(for: .seconds(ends.timeIntervalSinceNow + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.restsRunOut += 1
            LiveActivityBridge.update(self.live, catalog: self.catalog, unit: self.gym.unit)
        }
    }

    /// A reading from the last half minute, or nothing.
    var currentHeartRate: Double? {
        guard let heartRate, let heartRateAt, Date().timeIntervalSince(heartRateAt) < 30 else { return nil }
        return heartRate
    }

    var heartRateZones: HeartRateZones { HeartRateZones.estimated(age: profile?.age(), resting: restingHeartRate) }

    /// Where a session's workout goes: the Watch's mirrored workout, while there is one, and Health.
    /// Tests put their own in, since under XCTest there's no Watch and Health is off.
    struct WorkoutHandOff {
        var watchConnected: @MainActor () -> Bool
        /// Over the mirrored workout. Whether the message reached the Watch.
        var sendToWatch: @MainActor (Data) async -> Bool
        var saveToHealth: @MainActor (SessionRecord) async -> Void
        /// The same message over WatchConnectivity, when the Watch app is reachable: the second route,
        /// for when a send over the workout hangs or fails.
        var sendToWatchApp: @MainActor (Data) -> Void = { _ in }

        static let live = WorkoutHandOff(
            watchConnected: {
                #if os(iOS)
                WorkoutMirror.shared.isConnected
                #else
                // Only an iPhone pairs with a Watch; the Mac and Vision Pro save the workout themselves.
                false
                #endif
            },
            sendToWatch: { data in
                #if os(iOS)
                await WorkoutMirror.shared.send(data)
                #else
                false
                #endif
            },
            saveToHealth: { record in
                do {
                    try await HealthBridge.shared.saveStrengthWorkout(
                        id: record.id, version: 2, start: record.start, end: record.end, title: record.title, energyKcal: nil)
                } catch {
                    appLog.error("Couldn't save the workout to Health: \(error.localizedDescription)")
                }
            },
            sendToWatchApp: { data in
                #if os(iOS)
                WatchLink.shared.sendLive(data)
                #endif
            })
    }

    @ObservationIgnored var workoutHandOff = WorkoutHandOff.live
    /// The last thing handed to the Watch or Health about a session's workout, kept so a test can
    /// wait for it.
    @ObservationIgnored private(set) var workoutTask: Task<Void, Never>?

    /// By both routes: WatchConnectivity, and the mirrored workout while there is one.
    private func tellWatch(_ message: MirrorMessage) {
        guard watchListening, let data = message.encoded() else { return }
        let handOff = workoutHandOff
        handOff.sendToWatchApp(data)
        guard handOff.watchConnected() else { return }
        workoutTask = Task { _ = await handOff.sendToWatch(data) }
    }

    /// Mutates the live session and keeps rest alerts and the Live Activity in step.
    func update(_ change: (inout LiveSession) -> Void) {
        guard var session = live else { return }
        change(&session)
        live = session
        RestAlerts.shared.schedule(for: session.rest, catalog: catalog, session: session)
        LiveActivityBridge.update(session, catalog: catalog, unit: gym.unit)
    }

    func finish(feedback: SessionFeedback?) {
        guard let live else { return }
        let record = live.record(feedback: feedback)
        // The Watch measured it: its workout, with heart rate and energy, is the one Health keeps, when
        // there's a session to keep and Health is to have it. Otherwise the Watch throws its workout away.
        let watchSaves = workoutHandOff.watchConnected() && record.hasContent && settings.saveToHealth
        let ending: MirrorMessage = watchSaves ? .finish(id: record.id, title: record.title) : .discard(id: live.id, saved: record.hasContent)
        if !watchSaves { tellWatch(ending) }
        endedForWatch = (live.id, ending)
        self.live = nil
        showSession = false
        RestAlerts.shared.cancel()
        LiveActivityBridge.end()
        finishedBaseline = SummaryBaseline(record: record, plan: live.plan, strength: analysis?.strength.overall)
        keep(record, savedByWatch: watchSaves)
        if watchSaves { handWorkoutToWatch(record) }
        if record.hasContent { finished = record }
    }

    /// Asks the Watch to save its workout under the session's id, over the workout alone: a copy over
    /// WatchConnectivity could save it there while this send failed and the phone saved a second.
    /// When the send doesn't get there within 15 seconds (out of range, its workout already over, or a
    /// send that hangs), the workout is saved from here, as with no Watch, rather than not at all, and
    /// the Watch is told by the other route to throw its own away.
    private func handWorkoutToWatch(_ record: SessionRecord) {
        let handOff = workoutHandOff
        guard let message = MirrorMessage.finish(id: record.id, title: record.title).encoded() else { return }
        let fallback = MirrorMessage.discard(id: record.id, saved: true).encoded()
        workoutTask = Task {
            if await Self.delivered(within: 15, { await handOff.sendToWatch(message) }) { return }
            appLog.notice("The Watch didn't get the session's end, so the workout is saved from the phone")
            if let fallback { handOff.sendToWatchApp(fallback) }
            await handOff.saveToHealth(record)
        }
    }

    /// Whether a send says it got there within `seconds`. One that hangs counts as not (and is left
    /// to hang: a send over a workout can't be cancelled).
    private static func delivered(within seconds: Double, _ send: @escaping @MainActor () async -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            Task { @MainActor in answer.give(await send()) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                answer.give(false)
            }
        }
    }

    /// Saves a finished session from this phone or the Watch, and to Health when it ran here
    /// (unless the Watch recorded the workout alongside).
    func keep(_ record: SessionRecord, savedByWatch: Bool = false) {
        guard record.hasContent else { return }
        store.save(record)
        reload()
        if settings.saveToHealth, record.device != "Watch", !savedByWatch {
            let handOff = workoutHandOff
            workoutTask = Task { await handOff.saveToHealth(record) }
        }
    }

    func discardLive() {
        if let live {
            let ending = MirrorMessage.discard(id: live.id, saved: false)
            tellWatch(ending)
            endedForWatch = (live.id, ending)
        }
        live = nil
        showSession = false
        RestAlerts.shared.cancel()
        LiveActivityBridge.end()
    }

    private func persistLive() {
        if heartRateOnly, Date().timeIntervalSince(lastLivePersist) < 30 { return }
        lastLivePersist = Date()
        if let live, let data = try? SystemJSON.encoder().encode(live) {
            try? FileManager.default.createDirectory(at: liveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: liveURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: liveURL)
        }
    }

    /// How long a session left open stays open across a relaunch, counted from the last thing done in it.
    private static let liveRestoreWindow: TimeInterval = 6 * 3600

    /// Picks up the session left open when the app was closed. One left longer than the window was
    /// over: what was logged is kept, ending at the last thing done, and shown as finished.
    private func restoreLive() {
        guard FileManager.default.fileExists(atPath: liveURL.path(percentEncoded: false)) else { return }
        let session: LiveSession
        do {
            session = try SystemJSON.decoder().decode(LiveSession.self, from: Data(contentsOf: liveURL))
        } catch {
            // Moved aside rather than dropped: the next session would write over it here.
            appLog.error("Couldn't read the session left open: \(error.localizedDescription)")
            let aside = liveURL.deletingLastPathComponent().appending(path: "live-session.unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            do {
                try FileManager.default.moveItem(at: liveURL, to: aside)
            } catch {
                appLog.error("Couldn't move the unreadable session aside: \(error.localizedDescription)")
            }
            return
        }
        guard Date().timeIntervalSince(session.updatedAt) >= Self.liveRestoreWindow else {
            live = session
            return
        }
        let record = session.record(feedback: nil, now: session.updatedAt)
        try? FileManager.default.removeItem(at: liveURL)
        finishedBaseline = SummaryBaseline(record: record, plan: session.plan, strength: analysis?.strength.overall)
        keep(record)
        if record.hasContent { finished = record }
    }

    // MARK: Health

    func connectHealth() async {
        _ = await HealthBridge.shared.requestAuthorization()
        startHealthObserving()
        await refreshHealth()
    }

    /// Outside workouts and weigh-ins arrive while the app runs. Asks nothing: without permission the
    /// query just doesn't report, so it's started at every launch, not only by "Connect Apple Health".
    /// Health is read straight after starting it, at launch and on connecting, and that read stands
    /// for the call HealthKit makes as the query starts.
    func startHealthObserving() {
        guard healthObserver == nil, HealthBridge.shared.isAvailable else { return }
        healthObserverStarted = Date()
        healthObserver = HealthBridge.shared.observeChanges { [weak self] in
            Task { @MainActor in await self?.healthChanged() }
        }
    }

    /// The observer's call: the first, straight after it starts, only says the query is running, and
    /// the rest are changes.
    private func healthChanged() async {
        if let started = healthObserverStarted {
            healthObserverStarted = nil
            if Date().timeIntervalSince(started) < 10 { return }
        }
        await refreshHealth()
    }

    /// `refreshHealth`, unless it ran in the last ten minutes: for each return to the app, since last
    /// night's sleep, this morning's weigh-in and today's steps and outside workouts came in while it
    /// was suspended, and the observer hears nothing then.
    func refreshHealthIfStale(now: Date = Date()) async {
        if let lastHealthRefresh, now.timeIntervalSince(lastHealthRefresh) < 10 * 60 { return }
        await refreshHealth()
    }

    /// Body weight, recovery signals, steps and workouts other apps wrote.
    func refreshHealth() async {
        let health = HealthBridge.shared
        guard health.isAvailable else { return }
        lastHealthRefresh = Date()
        let since = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        async let weight = health.latestBodyweight()
        async let fat = health.latestBodyFat()
        async let recovery = health.recoveryDays(since: Day.today.adding(days: -42))
        async let vo2 = health.latestVO2Max()
        async let rhr = health.latestRestingHeartRate()
        async let steps = health.dailySteps(since: stepsSince)
        async let workouts = health.externalWorkouts(since: since, excludingBundlePrefixes: AppModel.ownBundlePrefixes)
        let (w, f, r, v, h, s, outside) = await (weight, fat, recovery, vo2, rhr, steps, workouts)
        bodyweightKg = w?.kg
        bodyweightDate = w?.date
        bodyFatPercent = f.flatMap { $0.date > Date().addingTimeInterval(-14 * 86_400) ? $0.percent : nil }
        self.recovery = r
        vo2Max = v
        restingHeartRate = h
        self.steps = stepsOrSample(s)
        importOutside(outside)
        reload()
    }

    /// Saves the workouts other apps wrote to Health that aren't here yet, as outside activities.
    /// Each is stamped with when it happened, so a delete made here afterwards is newer than every
    /// later import of it and the workout stays deleted. Doesn't reload; returns how many were new.
    @discardableResult
    func importOutside(_ outside: [ActivityLog]) -> Int {
        let known = Set(
            activities.compactMap { log -> UUID? in
                if case .health(let id, _) = log.source { return id }
                return nil
            })
        let new = outside.filter { log in
            if case .health(let id, _) = log.source { return !known.contains(id) }
            return false
        }
        if !new.isEmpty { store.save(new.map { ActivityRecord(log: $0, updatedAt: $0.start) }) }
        return new.count
    }

    /// Far enough back for the usual count before the current phase began.
    private var stepsSince: Day { state?.stepsNeededSince ?? Day.today.adding(days: -56) }

    private func stepsOrSample(_ steps: [StepDay]) -> [StepDay] {
        #if DEBUG
        if steps.isEmpty, LaunchOptions.current.has("-seedSampleData") { return SampleData.steps() }
        #endif
        return steps
    }

    // MARK: Data

    /// CSV files in a fresh folder, ready to share.
    func exportCSV() throws -> [URL] {
        guard let state else { return [] }
        let folder = URL.temporaryDirectory.appending(path: "Stadig Lift Export \(Day.today.iso)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try Export.tables(state).map { table in
            var csv = CSVTable(header: table.header)
            for row in table.rows { csv.append(row) }
            let url = folder.appending(path: "\(table.name).csv")
            try csv.data.write(to: url)
            return url
        }
    }

    private var backupURL: URL { URL.temporaryDirectory.appending(path: "Stadig Lift \(today.iso).liftbackup") }

    /// Every record and shared file in one `.liftbackup` file, encoded and written off the main
    /// actor: with years of records and photos the JSON takes seconds.
    func exportBackup() async throws -> URL {
        let data = try await store.exportBackup(app: .liftTrack, shared: shared)
        let url = backupURL
        try await Task.detached { try data.write(to: url, options: .atomic) }.value
        return url
    }

    /// Merges a Stadig Lift backup in, read and decoded off the main actor; another app's backup is
    /// refused before anything is written.
    @discardableResult
    func importBackup(from url: URL) async throws -> BackupSummary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        // Also when it throws: the records may be in before the shared files fail.
        defer { reload() }
        return try await store.importBackup(data, app: .liftTrack, shared: shared)
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        discardLive()
        reload()
    }
    #endif
}

/// Resumes a continuation once, with the first answer given: a send or its time limit, whichever comes first.
@MainActor
private final class FirstAnswer {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func give(_ answer: Bool) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}
