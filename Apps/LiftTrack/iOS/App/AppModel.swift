import Foundation
import Observation
import OSLog
import ExerciseLibrary
import HealthBridge
import LiftEngine
import SystemCore
import SystemStore

let appLog = Logger(subsystem: "dev.svindland.lifttrack", category: "app")

enum AppTab: Hashable {
    case today, plan, progress, body
}

/// The app's state: records from Lift Track's own synced store, what other apps published to the
/// shared container, what Health knows, and the analysis computed from all of it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let store: RecordStore
    let shared: SharedContainer
    let catalog = ExerciseCatalog()
    let purchases = Purchases()

    // Records.
    private(set) var profile: SharedProfile?
    private(set) var settings = LiftSettings()
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
    @ObservationIgnored private var stepsReadAt = Date.distantPast
    var bodyweightKg: Double?
    var vo2Max: Double?
    var restingHeartRate: Double?

    // From the other apps and the hub.
    private(set) var nutrition: NutritionSummary?
    private(set) var recommendations: [Recommendation] = []
    /// A profile another app wrote before Lift Track was set up: onboarding reuses it.
    private(set) var sharedProfile: SharedProfile?

    // Derived.
    private(set) var analysis: LiftAnalysis?

    // Live session and presentation.
    var live: LiveSession? { didSet { persistLive() } }
    /// The latest reading from the Watch during a session led from here, and when it came.
    private(set) var heartRate: Double?
    private(set) var heartRateAt: Date?
    @ObservationIgnored private var lastLivePersist = Date.distantPast
    @ObservationIgnored private var heartRateOnly = false
    var showSession = false
    var finished: SessionRecord?
    var tab: AppTab = .today
    var showSettings = false
    var showPaywall = false
    var today: Day = .today

    @ObservationIgnored private var sharedObserver: AnyObject?
    @ObservationIgnored private var healthObserver: AnyObject?
    @ObservationIgnored private var lastRevision = -1

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let memory = arguments.contains("-inMemoryStore")
        store = RecordStore(name: "LiftTrack", cloudKitContainer: memory ? nil : "iCloud.dev.svindland.lifttrack", inMemory: memory)
        shared = SharedContainer()
        #if DEBUG
        if arguments.contains("-resetData") { store.eraseAll() }
        #endif
        reload()
        restoreLive()
        LiveActivityBridge.resume(live, catalog: catalog, unit: gym.unit)
        sharedObserver = SharedContainer.observeChanges { [weak self] in self?.readShared() }
    }

    var onboarded: Bool { profile != nil && settings.onboardedAt != nil }

    var units: UnitPreference { profile?.units ?? .regional }

    // MARK: Loading

    /// Reads everything from the store and recomputes. Cheap enough to call after every change.
    func reload() {
        lastRevision = store.revision
        profile = store.all(ProfileRecord.self).first?.profile
        settings = store.all(LiftSettings.self).first ?? LiftSettings()
        let gyms = store.all(Gym.self)
        gym = gyms.first { $0.id == settings.gymID } ?? gyms.first ?? Gym.preset(profile?.equipment ?? .fullGym, unit: units.weight)
        sessions = store.all(SessionRecord.self).sorted { $0.start < $1.start }
        activities = store.all(ActivityRecord.self).map(\.log).sorted { $0.start < $1.start }
        measurements = store.all(MeasurementRecord.self).map(\.measurements).sorted { $0.day < $1.day }
        photos = store.all(ProgressPhoto.self).sorted { $0.day < $1.day }
        mobility = store.all(MobilityRecord.self).map(\.result).sorted { $0.day < $1.day }
        benchmarks = store.all(BenchmarkRecord.self).map(\.result).sorted { $0.day < $1.day }
        mesocycles = store.all(Mesocycle.self).sorted { $0.block.start < $1.block.start }
        readShared(recompute: false)
        recompute()
    }

    /// Picks up changes that arrived from iCloud.
    func reloadIfChanged() {
        if store.revision != lastRevision { reload() }
    }

    /// What other apps and the hub published. Our own writes notify us too, so this only
    /// recomputes when something actually changed.
    func readShared(recompute again: Bool = true) {
        let nutrition = shared.read(.nutrition)
        let recommendations = (shared.read(.recommendations) ?? []).filter { $0.to == .liftTrack && $0.isActive() }
        let sharedProfile = shared.read(.profile)
        // Life modes are system-wide: ours, merged with any another app set, newest wins.
        var merged: [UUID: LifeModePeriod] = [:]
        for period in store.all(LifeModeRecord.self).map(\.period) + (shared.read(.lifeModes) ?? []) {
            if let existing = merged[period.id], existing.updatedAt >= period.updatedAt { continue }
            merged[period.id] = period
        }
        let lifeModes = merged.values.sorted { $0.start < $1.start }
        let changed = nutrition != self.nutrition || recommendations != self.recommendations || sharedProfile != self.sharedProfile
            || lifeModes != self.lifeModes
        guard changed else { return }
        self.nutrition = nutrition
        self.recommendations = recommendations
        self.sharedProfile = sharedProfile
        self.lifeModes = lifeModes
        if again { recompute() }
    }

    var state: LiftState? {
        guard let profile else { return nil }
        return LiftState(profile: profile, settings: settings, gym: gym, catalog: catalog, sessions: sessions, activities: activities,
                         measurements: measurements, mobility: mobility, benchmarks: benchmarks, mesocycles: mesocycles,
                         lifeModes: lifeModes, recovery: recovery, steps: steps, bodyweightKg: bodyweightKg, vo2Max: vo2Max,
                         restingHeartRate: restingHeartRate, nutrition: nutrition, recommendations: recommendations, today: today)
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

    /// Small summaries for the other apps, the hub, the widgets and the Watch, written only when
    /// they change.
    private func publish(_ state: LiftState, _ analysis: LiftAnalysis) {
        var summary = Analyst.summary(state, analysis)
        var calendar = analysis.calendar
        if let last = lastPublished {
            summary.updated = last.summary.updated
            calendar.updated = last.calendar.updated
        }
        if lastPublished.map({ $0.summary != summary || $0.calendar != calendar }) ?? true {
            summary.updated = Date()
            calendar.updated = Date()
            do {
                try shared.write(summary, to: .summary(.liftTrack), by: .liftTrack)
                try shared.write(calendar, to: .calendar, by: .liftTrack)
                lastPublished = (summary, calendar)
            } catch {
                appLog.error("Couldn't publish the summary: \(error.localizedDescription)")
            }
        }
        WidgetBridge.update(self)
        WatchLink.shared.publish(self)
    }

    // MARK: Saving

    func save(profile: SharedProfile) {
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        try? shared.write(profile, to: .profile, by: .liftTrack)
        reload()
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

    func save(lifeMode period: LifeModePeriod) {
        var period = period
        period.updatedAt = Date()
        store.save(LifeModeRecord(period))
        publishLifeModes(replacing: period)
        reload()
    }

    func delete(lifeMode id: UUID) {
        store.delete(LifeModeRecord.self, id: id)
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == id }
        try? shared.write(all, to: .lifeModes, by: .liftTrack)
        reload()
    }

    private func publishLifeModes(replacing period: LifeModePeriod) {
        var all = shared.read(.lifeModes) ?? []
        all.removeAll { $0.id == period.id }
        all.append(period)
        try? shared.write(all, to: .lifeModes, by: .liftTrack)
    }

    func delete(session id: UUID) {
        store.delete(SessionRecord.self, id: id)
        reload()
        Task { await HealthBridge.shared.deleteWorkout(id: id) }
    }

    // MARK: Onboarding

    /// Saves the shared setup answers and Lift Track's own, then starts the assessment.
    func completeOnboarding(profile: SharedProfile, settings: LiftSettings, gym: Gym, measurements: BodyMeasurements?) {
        var settings = settings
        settings.gymID = gym.id
        settings.onboardedAt = Date()
        settings.assessmentStart = .today
        if settings.selfReportedPhase != nil { settings.selfReportedPhaseSince = .today }
        settings.updatedAt = Date()
        var profile = profile
        profile.updatedAt = Date()
        store.save(ProfileRecord(profile))
        try? shared.write(profile, to: .profile, by: .liftTrack)
        store.save(gym)
        store.save(settings)
        if let measurements, !measurements.isEmpty { store.save(MeasurementRecord(measurements)) }
        reload()
        let assessment = generate(kind: .assessment, start: .today)
        store.save(assessment)
        reload()
    }

    // MARK: Blocks

    var currentMesocycle: Mesocycle? { analysis?.mesocycle }

    /// Whether the person may generate a block now: the assessment is free, real blocks need the unlock.
    var canPlanNextBlock: Bool { purchases.unlocked }

    /// Builds a mesocycle from everything known right now. Not saved until accepted.
    func generate(kind: BlockKind, start: Day, phase: NutritionPhase? = nil) -> Mesocycle {
        guard let profile else { fatalError("generate before onboarding") }
        let analysis = self.analysis
        let phase = phase ?? analysis?.phase ?? .assumedMaintenance
        let weeks = kind == .assessment
            ? (profile.experience.assessmentWeeks)
            : BlockScheduler.loadingWeeks(phase: phase.effects, experience: profile.experience)
        let input = GeneratorInput(
            profile: profile, settings: settings, gym: gym, catalog: catalog, kind: kind, start: start, loadingWeeks: weeks, phase: phase,
            strength: analysis?.strength, physique: analysis?.physique, agility: analysis?.agility, endurance: analysis?.endurance,
            fatigue: analysis?.fatigue, recommendations: recommendations, injuries: analysis?.life.injuries ?? [],
            previous: mesocycles.last, stalled: Set(analysis?.stalls.filter { $0.reading == .programming }.map(\.exerciseID) ?? []),
            trust: analysis?.trust ?? TrustState(experience: profile.experience))
        return ProgramGenerator.generate(input)
    }

    /// Ends the current block's loading now and makes this week the deload.
    func deloadNow(reason: String) {
        guard var m = currentMesocycle else { return }
        m.block.deloadStart = .today
        m.block.endOverride = Day.today.adding(days: 6)
        m.block.deloadReason = reason
        save(m)
    }

    // MARK: Sessions

    var environment: SessionEnvironment? {
        guard let analysis else { return nil }
        var environment = SessionEnvironment(catalog: catalog, gym: gymForToday, trust: analysis.trust, phase: analysis.phase.effects,
                                             bodyweightKg: state?.effectiveBodyweight, history: analysis.history,
                                             enduranceScore: analysis.endurance.score, heartRateGuidedRest: settings.heartRateGuidedRest)
        environment.heat = analysis.heat
        return environment
    }

    /// Thermometers read in Fahrenheit where weights are in pounds.
    var fahrenheit: Bool { (profile?.units.weight ?? gym.unit) == .lb }

    var gymForToday: Gym {
        guard let profile, let analysis else { return gym }
        let context = PlanningContext(catalog: catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust,
                                      phase: analysis.phase, life: analysis.life, history: [:], bodyweightKg: nil, enduranceScore: nil,
                                      sessionIndexInWeek: 0)
        return context.todaysGym
    }

    /// Today's session from the program, fitted to the minutes available if they differ.
    func plan(minutes: Int? = nil) -> SessionPlan? {
        guard let profile, let analysis, let next = analysis.next else { return nil }
        var day = next.day
        var minutesAvailable = minutes
        if let cap = analysis.life.maxMinutes { minutesAvailable = min(minutesAvailable ?? cap, cap) }
        if let minutesAvailable, minutesAvailable != next.mesocycle.minutesPerSession {
            var input = GeneratorInput(profile: profile, settings: settings, gym: gymForToday, catalog: catalog, kind: next.mesocycle.block.kind,
                                       start: next.mesocycle.block.start, loadingWeeks: next.mesocycle.block.loadingWeeks,
                                       phase: analysis.phase, agility: analysis.agility, endurance: analysis.endurance,
                                       injuries: analysis.life.injuries, trust: analysis.trust)
            input.profile.schedule.minutesPerSession = minutesAvailable
            day = ProgramGenerator.refit(next.day, minutes: minutesAvailable, input: input)
        }
        var context = PlanningContext(catalog: catalog, gym: gym, profile: profile, settings: settings, trust: analysis.trust,
                                      phase: analysis.phase, life: analysis.life, history: analysis.history,
                                      bodyweightKg: state?.effectiveBodyweight, enduranceScore: analysis.endurance.score,
                                      sessionIndexInWeek: next.doneThisWeek)
        context.heat = analysis.heat
        return SessionPlanner.plan(day, of: next.mesocycle, on: today, context: context)
    }

    func start(_ plan: SessionPlan) {
        live = LiveSession(plan: plan, device: "iPhone")
        showSession = true
        RestAlerts.shared.requestPermission()
        LiveActivityBridge.update(live, catalog: catalog, unit: gym.unit)
        heartRate = nil
        // A workout on the Watch, mirrored here, for heart rate: warm-up, rests and conditioning.
        if WatchLink.shared.watchAppInstalled { Task { await WorkoutMirror.shared.startWatchWorkout() } }
    }

    /// Readings from the Watch's mirrored workout.
    func fromWatch(_ data: [Data]) {
        for item in data {
            guard case .heartRate(let bpm, let date)? = try? JSONDecoder().decode(MirrorMessage.self, from: item) else { continue }
            heartRate = bpm
            heartRateAt = date
            guard var session = live else { continue }
            let recovered = session.record(heartRate: bpm, zones: heartRateZones, now: date)
            // Samples come every few seconds: they needn't hit the disk as often.
            heartRateOnly = true
            live = session
            heartRateOnly = false
            if recovered, settings.heartRateGuidedRest, session.rest != nil {
                update { $0.endRest() }
                RestAlerts.shared.heartRateRecovered()
            }
        }
    }

    /// A reading from the last half minute, or nothing.
    var currentHeartRate: Double? {
        guard let heartRate, let heartRateAt, Date().timeIntervalSince(heartRateAt) < 30 else { return nil }
        return heartRate
    }

    var heartRateZones: HeartRateZones { HeartRateZones.estimated(age: profile?.age(), resting: restingHeartRate) }

    private func tellWatch(_ message: MirrorMessage) {
        guard WorkoutMirror.shared.isConnected, let data = try? JSONEncoder().encode(message) else { return }
        Task { await WorkoutMirror.shared.send(data) }
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
        // The Watch measured it: its workout, with heart rate and energy, is the one Health keeps.
        let watchSaves = WorkoutMirror.shared.isConnected
        tellWatch(.finish(id: record.id, title: record.title))
        self.live = nil
        showSession = false
        RestAlerts.shared.cancel()
        LiveActivityBridge.end()
        keep(record, savedByWatch: watchSaves)
        finished = record
    }

    /// Saves a finished session from this phone or the Watch, and to Health when it ran here
    /// (unless the Watch recorded the workout alongside).
    func keep(_ record: SessionRecord, savedByWatch: Bool = false) {
        guard !record.exercises.isEmpty || !record.conditioning.isEmpty || !record.mobility.isEmpty else { return }
        store.save(record)
        reload()
        if settings.saveToHealth, record.device != "Watch", !savedByWatch {
            Task {
                try? await HealthBridge.shared.saveStrengthWorkout(id: record.id, version: 2, start: record.start, end: record.end,
                                                                   title: record.title, energyKcal: nil)
            }
        }
    }

    func discardLive() {
        tellWatch(.discard)
        live = nil
        showSession = false
        RestAlerts.shared.cancel()
        LiveActivityBridge.end()
    }

    private var liveURL: URL {
        URL.applicationSupportDirectory.appending(path: "live-session.json")
    }

    private func persistLive() {
        if heartRateOnly, Date().timeIntervalSince(lastLivePersist) < 30 { return }
        lastLivePersist = Date()
        if let live, let data = try? SystemJSON.encoder().encode(live) {
            try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            try? data.write(to: liveURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: liveURL)
        }
    }

    private func restoreLive() {
        guard let data = try? Data(contentsOf: liveURL), let session = try? SystemJSON.decoder().decode(LiveSession.self, from: data),
              Date().timeIntervalSince(session.updatedAt) < 6 * 3600 else { return }
        live = session
    }

    // MARK: Health

    func connectHealth() async {
        _ = await HealthBridge.shared.requestAuthorization()
        await refreshHealth()
        if healthObserver == nil {
            healthObserver = HealthBridge.shared.observeChanges { Task { @MainActor in await AppModel.shared.refreshHealth() } }
        }
    }

    /// Body weight, recovery signals, steps and workouts other apps wrote.
    func refreshHealth() async {
        let health = HealthBridge.shared
        guard health.isAvailable else { return }
        let since = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        async let weight = health.latestBodyweight()
        async let recovery = health.recoveryDays(since: Day.today.adding(days: -42))
        async let vo2 = health.latestVO2Max()
        async let rhr = health.latestRestingHeartRate()
        async let steps = health.dailySteps(since: stepsSince)
        async let workouts = health.externalWorkouts(since: since, excludingBundlePrefix: "dev.svindland.lifttrack")
        let (w, r, v, h, s, outside) = await (weight, recovery, vo2, rhr, steps, workouts)
        bodyweightKg = w?.kg
        self.recovery = r
        vo2Max = v
        restingHeartRate = h
        self.steps = stepsOrSample(s)
        stepsReadAt = Date()
        let known = Set(activities.compactMap { log -> UUID? in
            if case .health(let id, _) = log.source { return id }
            return nil
        })
        let new = outside.filter { log in
            if case .health(let id, _) = log.source { return !known.contains(id) }
            return false
        }
        if !new.isEmpty { store.save(new.map { ActivityRecord(log: $0) }) }
        reload()
    }

    /// Steps change all day: read again on coming back to the app, at most every ten minutes.
    func refreshSteps() async {
        guard HealthBridge.shared.isAvailable, Date().timeIntervalSince(stepsReadAt) > 600 else { return }
        stepsReadAt = Date()
        let steps = stepsOrSample(await HealthBridge.shared.dailySteps(since: stepsSince))
        guard steps != self.steps else { return }
        self.steps = steps
        recompute()
    }

    /// Far enough back for the usual count before the current phase began.
    private var stepsSince: Day { state?.stepsNeededSince ?? Day.today.adding(days: -56) }

    private func stepsOrSample(_ steps: [StepDay]) -> [StepDay] {
        #if DEBUG
        if steps.isEmpty, ProcessInfo.processInfo.arguments.contains("-seedSampleData") { return SampleData.steps() }
        #endif
        return steps
    }

    // MARK: Data

    /// CSV files in a fresh folder, ready to share.
    func exportCSV() throws -> [URL] {
        guard let state else { return [] }
        let folder = URL.temporaryDirectory.appending(path: "Lift Track Export \(Day.today.iso)")
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

    func backupFile() throws -> URL {
        let data = try store.exportBackup(app: .liftTrack, shared: shared)
        let url = URL.temporaryDirectory.appending(path: "Lift Track \(Day.today.iso).liftbackup")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func restore(from url: URL) throws -> BackupSummary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let summary = try store.importBackup(data, shared: shared)
        reload()
        return summary
    }

    #if DEBUG
    func eraseEverything() {
        store.eraseAll()
        discardLive()
        reload()
    }
    #endif
}
