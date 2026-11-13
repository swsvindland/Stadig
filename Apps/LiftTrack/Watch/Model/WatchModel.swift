import ExerciseLibrary
import Foundation
import HealthBridge
import LiftEngine
import OSLog
import Observation
import SystemCore
import WatchKit
import WidgetKit

/// What the session screen shows next.
enum SessionStep: Equatable {
    case rest
    /// A loaded set: crown for the load, then a rating.
    case set(item: Int, set: Int)
    /// Mobility, warm-up, stretches and unloaded holds: a countdown or a count, then Done.
    case timed(item: Int, set: Int)
    case conditioning(item: Int)
    /// The sauna or steam room, in a session the iPhone runs: the thermometer is logged there.
    case heat(item: Int)
    /// Everything is done, or the person chose to end: feedback, then save.
    case finish
}

/// A set as the person did it, between the set screen and the rating.
struct SetDraft: Hashable {
    var item: Int
    var set: Int
    var loadKg: Double?
    var reps: Int
    var seconds: Int?
}

/// The rest ran out on its own (its time, or heart rate): the next set's face comes up in the accent
/// for a few seconds, with the heart rate and how early, so a glance after the tap on the wrist says
/// what's next.
struct GoMoment: Equatable {
    var id = UUID()
    var heartRate: Double?
    /// Seconds before the rest's time, when heart rate ended it.
    var early: Int?
}

/// A short line shown on the next screen: "Heart rate recovered".
struct Notice: Equatable {
    var text: String
    var symbol: String
    var id = UUID()
}

/// What a finished session comes to, for the summary screen.
struct SessionSummary: Equatable {
    var title: String
    var minutes: Int
    var exercises: Int
    var workSets: Int
    /// The plan's work sets, to count the session's against.
    var plannedSets: Int?
    var ratings: [SetRating: Int]
    var conditioningMinutes: Int
    var averageHeartRate: Double?
    /// The iPhone ran the session and saved it; this Watch logged into it.
    var savedOnPhone: Bool
    /// The lifts whose estimated one-rep max it raised, from what this Watch knew going in.
    var moved: [EstimateMove]

    init(
        _ record: SessionRecord, plan: SessionPlan? = nil, savedOnPhone: Bool = false, known: PhoneContext? = nil,
        catalog: ExerciseCatalog? = nil
    ) {
        title = record.title
        minutes = record.minutes
        exercises = record.exercises.count
        workSets = record.workSets.count
        plannedSets = plan.map { $0.items.filter(\.isStrength).reduce(0) { $0 + $1.workSets.count } }
        ratings = Dictionary(grouping: record.workSets.compactMap(\.rating)) { $0 }.mapValues(\.count)
        conditioningMinutes = record.conditioning.map(\.minutes).reduce(0, +)
        averageHeartRate = record.averageHeartRate
        self.savedOnPhone = savedOnPhone
        if let known, let catalog {
            moved = EstimateMove.moves(history: known.history, session: record.exercises.flatMap(\.sets), trust: known.trust) {
                catalog[$0]?.loadBasis
            }
        } else {
            moved = []
        }
    }
}

/// The Watch's state: the phone's latest context, the session in progress and its live workout.
/// The session is the same pure state machine the phone runs, and it's one of two kinds. Started
/// here, it's the Watch's own: this model persists it after every change, and the record goes to
/// the phone at the end. Started on the iPhone, the Watch measures heart rate for it and shows a
/// copy of it (`mirrored`): every change made here goes to the phone, which sends its session back.
/// Either way the model feeds it heart rate and keeps the timers and haptics that rests and drills need.
@MainActor @Observable
final class WatchModel {
    /// One model: the app's scene and the phone's request to start a workout share it.
    static let shared = WatchModel()

    let catalog = ExerciseCatalog()
    let workout = LiveWorkoutSession()

    /// Measuring heart rate for a session the iPhone runs, since this time.
    private(set) var companionSince: Date?

    private(set) var context: PhoneContext?
    /// The session on screen: this Watch's own, or its copy of the phone's.
    private(set) var session: StoredSession?
    /// The session the iPhone runs, while this Watch logs into it; nil when the session on screen
    /// (if any) is this Watch's own.
    private(set) var mirrored: MirroredSession?
    /// Ending the phone's session was asked for here, until the phone says it's over.
    private(set) var endingOnPhone: MirrorMessage?
    /// The last finished session, until the person dismisses it.
    var summary: SessionSummary?
    private(set) var notice: Notice?
    /// The rest just ran out on its own, while the set face says so.
    private(set) var go: GoMoment?
    /// Moves when a rest in the phone's session runs out, so the screen moves on: the phone keeps the
    /// rest until the next set is logged (that set's rest is timed from it), as the Watch's copy does.
    private(set) var restsRunOut = 0
    /// False skips HealthKit (sample sessions in the simulator).
    var healthEnabled = true
    #if DEBUG
    /// A screen for the sample session to open on.
    var debugRoute: String?
    /// A heart rate to show in place of the workout's (`-sampleHeartRate`).
    var debugHeartRate: Double?
    #endif

    @ObservationIgnored private var alarm: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var goTask: Task<Void, Never>?
    @ObservationIgnored private var lastSave = Date.distantPast
    /// The context the phone sent with its session: the gym, loads and zones it runs it with.
    @ObservationIgnored private var mirroredContext: PhoneContext?
    /// Asks the phone again for what it hasn't answered, while measuring for it.
    @ObservationIgnored private var linkRetry: Task<Void, Never>?
    /// Sends over the workout not yet returned, nor ten seconds old. A send there can hang; while
    /// three are out, only WatchConnectivity carries messages.
    @ObservationIgnored private var mirrorSendsInFlight: Set<UUID> = []
    /// The phone's sessions this Watch has left, the last few: a late end or copy of one (it can come
    /// by either route, and after the next session has started) is ignored.
    @ObservationIgnored private var leftSessions: [UUID] = []
    private static let restoreWindow: TimeInterval = 6 * 3600

    init() {
        context = WatchStorage.load(PhoneContext.self, from: WatchStorage.context)
        if let stored = WatchStorage.load(StoredSession.self, from: WatchStorage.session) {
            if Date().timeIntervalSince(stored.live.updatedAt) < Self.restoreWindow {
                session = stored
            } else {
                Self.finishLeftOver(stored)
            }
        }
        workout.onHeartRate = { [weak self] bpm in self?.heartRate(bpm) }
        workout.onRemoteData = { [weak self] data in self?.fromPhone(data) }
        workout.onEndedRemotely = { [weak self] in self?.stopCompanion() }
        // Wired here rather than from a view: a background wake to deliver a context may never render one.
        PhoneLink.shared.onContext = { [weak self] context in self?.receive(context) }
        PhoneLink.shared.onMirror = { [weak self] data in self?.fromPhone(data) }
        PhoneLink.shared.activate()
    }

    /// Picks a restored session back up, and brings today up to date.
    func launch() {
        refresh()
        if let session {
            startWorkout(syncID: session.live.id)
            scheduleAlarm()
        }
    }

    /// On launch and whenever the app comes back on screen, perhaps on a later day: asks for a
    /// context if there's none for today, and redraws Home and the complication for the day.
    func refresh() {
        moveDayOn()
        if context == nil || isStale { PhoneLink.shared.requestContext() }
        writeSnapshot()
    }

    func receive(_ new: PhoneContext) {
        if let context, context.sentAt > new.sentAt { return }
        context = new
        WatchStorage.save(new, to: WatchStorage.context)
        writeSnapshot()
    }

    func requestContext() { PhoneLink.shared.requestContext() }

    // MARK: Today

    /// The day Home and the complication were last brought up to date for. Kept here, not read from
    /// the clock in the views, so moving it on redraws them after midnight.
    private(set) var today = Day.today

    private func moveDayOn() {
        if today != Day.today { today = Day.today }
    }

    /// The context's plan is for an earlier day: the phone hasn't been opened since.
    var isStale: Bool {
        guard let plan = context?.plan else { return false }
        return plan.day < today
    }

    /// Today's planned session was already finished on this Watch (an old plan's isn't today's).
    var finishedToday: Bool {
        guard let plan = context?.plan, !isStale else { return false }
        return Self.isFinished(plan)
    }

    /// Home offers the session after the phone's plan: this Watch has done the plan since the phone
    /// last planned (on an earlier day, so the phone was left behind), and the program goes on.
    var offersFollowing: Bool {
        guard isStale, let plan = context?.plan, let following = context?.following else { return false }
        return Self.isFinished(plan) && !Self.isFinished(following)
    }

    /// The session Home offers: the phone's plan, or the one after it (`offersFollowing`).
    var upcoming: SessionPlan? { offersFollowing ? context?.following : context?.plan }

    private static func finishedKey(_ plan: SessionPlan) -> String { "\(plan.day.iso) \(plan.dayID?.uuidString ?? plan.title)" }

    /// The plans this Watch has finished sessions of, oldest first, the last ten.
    private static var finishedPlans: [String] {
        get {
            var plans = UserDefaults.standard.stringArray(forKey: "finishedPlans") ?? []
            // Builds before this kept only the last one.
            if let old = UserDefaults.standard.string(forKey: "finished"), !plans.contains(old) { plans.insert(old, at: 0) }
            return plans
        }
        set {
            UserDefaults.standard.set(Array(newValue.suffix(10)), forKey: "finishedPlans")
            UserDefaults.standard.removeObject(forKey: "finished")
        }
    }

    private static func isFinished(_ plan: SessionPlan) -> Bool { finishedPlans.contains(finishedKey(plan)) }

    private static func markFinished(_ plan: SessionPlan) {
        let key = finishedKey(plan)
        finishedPlans = finishedPlans.filter { $0 != key } + [key]
    }

    // MARK: Where we are

    var live: LiveSession? { session?.live }

    /// Loads, zones and the gym come from the context the session started with.
    var sessionContext: PhoneContext? { session?.context ?? context }
    var unit: WeightUnit { sessionContext?.gym.unit ?? .kg }
    var zones: HeartRateZones { sessionContext?.zones ?? .estimated(age: nil, resting: nil) }

    /// The iPhone runs the session on screen; this Watch logs into it.
    var phoneLed: Bool { mirrored != nil }

    /// The item and set to do next, in the session's order (which "Do This Now" changes), alternating
    /// within a superset.
    var position: (item: Int, set: Int)? { session?.live.current }

    /// The item to do next, by id: the phone's "Do This Now" can put another exercise at the same
    /// place on the same set number, which `step` alone wouldn't show.
    var currentItemID: UUID? {
        guard let live, let position else { return nil }
        return live.items[position.item].id
    }

    var step: SessionStep? {
        _ = restsRunOut
        guard let stored = session else { return nil }
        if stored.wrappingUp || endingOnPhone != nil { return .finish }
        if let rest = stored.live.rest, mirrored == nil || rest.endsAt > Date() { return .rest }
        guard let (item, set) = position else { return .finish }
        let planned = stored.live.items[item].plan
        if planned.role == .conditioning || planned.conditioning != nil { return .conditioning(item: item) }
        if planned.role == .recovery, mirrored != nil { return .heat(item: item) }
        let exercise = catalog.resolve(stored.live.items[item].exerciseID)
        if !planned.isStrength || (exercise.timed && exercise.loadBasis == .none) { return .timed(item: item, set: set) }
        return .set(item: item, set: set)
    }

    func exercise(_ item: Int) -> Exercise {
        guard let live, live.items.indices.contains(item) else { return .placeholder(id: "unknown") }
        return catalog.resolve(live.items[item].exerciseID)
    }

    func increments(for exercise: Exercise) -> GymIncrements? {
        sessionContext?.gym.increments(for: exercise.equipment)
    }

    /// What an item's exercise could be swapped for here, closest first. It searches the whole
    /// library, so off the main actor.
    func swaps(for item: Int) async -> [Exercise] {
        guard let context = sessionContext, let live, live.items.indices.contains(item), live.items[item].plan.isStrength else { return [] }
        let exercise = exercise(item)
        let catalog = catalog
        return await Task.detached(priority: .userInitiated) { context.swaps(for: exercise, catalog: catalog, limit: 8) }.value
    }

    /// Where the crown starts: the prescribed load, else a sensible guess for a finding-weight set
    /// (the last load used, the phone's estimate, none for bodyweight and assisted work, else the
    /// lightest makeable load).
    func startingLoad(item index: Int, set setIndex: Int) -> Double? {
        guard let live, live.items.indices.contains(index), live.items[index].sets.indices.contains(setIndex) else { return nil }
        let item = live.items[index]
        let exercise = catalog.resolve(item.exerciseID)
        guard exercise.loadBasis != .none else { return nil }
        if let load = item.sets[setIndex].prescription.loadKg { return load }
        if let last = item.loggedSets.last(where: { $0.exerciseID == item.exerciseID }) { return last.loadKg }
        let known = sessionContext?.history[item.exerciseID] ?? context?.history[item.exerciseID]
        if let last = known?.last(where: { $0.kind.countsAsWork }) { return last.loadKg }
        // The phone's guess from bodyweight and experience, so a heavy leg press isn't a long crown turn away.
        if let guess = sessionContext?.startingLoads?[item.exerciseID] ?? context?.startingLoads?[item.exerciseID] { return guess }
        switch exercise.loadBasis {
        case .bodyweightPlus, .assisted, .none: return 0
        case .external, .perHand: return increments(for: exercise)?.around(nil).first { $0 > 0 } ?? 0
        }
    }

    /// The countdown or stopwatch running for this set (conditioning runs as set 0).
    func timer(for item: Int, set: Int) -> ItemTimer? {
        guard let stored = session, stored.live.items.indices.contains(item), let timer = stored.timer,
            timer.item == stored.live.items[item].id, timer.set == set
        else { return nil }
        return timer
    }

    // MARK: Session

    func start(_ plan: SessionPlan) {
        guard var snapshot = context else { return }
        snapshot.history = [:]
        let live = LiveSession(plan: plan, device: "Watch")
        session = StoredSession(live: live, context: snapshot)
        summary = nil
        changed()
        writeSnapshot()
        startWorkout(syncID: live.id)
    }

    func log(item: Int, set: Int, reps: Int, loadKg: Double?, rating: SetRating?, seconds: Int? = nil) {
        guard let id = itemID(item) else { return }
        let peak = workout.heartRate
        perform(.log(item: id, set: set, reps: reps, loadKg: loadKg, rating: rating, seconds: seconds, heartRatePeak: peak)) {
            $0.timer = nil
        }
    }

    /// Logs a drill or hold: the time it ran (no more than planned), or the planned time.
    func finishTimed(item: Int, set: Int) {
        guard let live, live.items.indices.contains(item), live.items[item].sets.indices.contains(set) else { return }
        let prescription = live.items[item].sets[set].prescription
        let planned = prescription.seconds ?? live.items[item].plan.seconds
        var seconds = planned
        if let timer = timer(for: item, set: set) {
            let elapsed = Int(Date().timeIntervalSince(timer.started).rounded())
            seconds = planned.map { min($0, elapsed) } ?? elapsed
        }
        log(item: item, set: set, reps: prescription.targetReps, loadKg: nil, rating: nil, seconds: seconds)
    }

    func startTimer(item: Int, set: Int) {
        update { stored in
            guard stored.live.items.indices.contains(item) else { return }
            stored.timer = ItemTimer(item: stored.live.items[item].id, set: set, started: Date())
        }
    }

    /// Logs conditioning with its minutes, average heart rate and minutes in each zone.
    func finishConditioning(item: Int) {
        guard let stored = session, let id = itemID(item) else { return }
        let now = Date()
        let started = timer(for: item, set: 0)?.started ?? now
        let minutes = max(1, Int((now.timeIntervalSince(started) / 60).rounded()))
        let average = stored.live.averageHeartRate(from: started, to: now)
        let zoneMinutes = stored.live.zoneMinutes(from: started, to: now, zones: stored.context.zones)
        perform(.logConditioning(item: id, minutes: minutes, averageHeartRate: average, zoneMinutes: zoneMinutes)) { $0.timer = nil }
    }

    func skipSet(item: Int, set: Int) {
        guard let id = itemID(item) else { return }
        perform(.skipSet(item: id, set: set)) { stored in
            // Its countdown would otherwise carry over to the next set.
            if let timer = stored.timer, timer.item == id, timer.set == set { stored.timer = nil }
        }
    }

    func skip(item: Int) {
        guard let id = itemID(item) else { return }
        perform(.skip(item: id)) { stored in
            if stored.timer?.item == id { stored.timer = nil }
        }
    }

    func addSet(item: Int) {
        guard let id = itemID(item) else { return }
        perform(.addSet(item: id))
    }

    /// Swaps an exercise for the rest of the session: its open sets are prescribed afresh.
    func swap(item: Int, to exercise: Exercise) {
        guard let id = itemID(item) else { return }
        perform(.swap(item: id, to: exercise.id)) { stored in
            if stored.timer?.item == id { stored.timer = nil }
        }
    }

    /// Does an item next, ahead of the plan's order: it moves up with its superset partner, as on
    /// the phone, so the pair still alternates with their own rests.
    func focus(item: Int) {
        guard let id = itemID(item) else { return }
        perform(.doNext(item: id)) { stored in
            // A countdown left running on the item put aside would still go off, and show again on return.
            if let timer = stored.timer, timer.item != id { stored.timer = nil }
        }
    }

    func endRest() { perform(.endRest) }

    func extendRest(by seconds: Int) { perform(.extendRest(seconds: seconds)) }

    func wrapUp() { update { $0.wrappingUp = true } }

    func keepGoing() { update { $0.wrappingUp = false } }

    /// Saves the session: the record goes to the phone and the workout to Health. A session with
    /// nothing logged is discarded instead. The phone's session is the phone's to save: it's asked
    /// to, and the session closes here when it says it has.
    func finish(feedback: SessionFeedback?) {
        guard let stored = session else { return }
        if mirrored != nil {
            endOnPhone(.finishFromWatch(id: stored.live.id, feedback: feedback))
            return
        }
        let record = stored.live.record(feedback: feedback)
        guard record.hasContent else {
            discard()
            return
        }
        PhoneLink.shared.send(record)
        Self.markFinished(stored.live.plan)
        // The stored session's context drops its history; the phone's latest still has it.
        summary = SessionSummary(record, plan: stored.live.plan, known: context, catalog: catalog)
        close()
        Task { _ = await workout.end() }
    }

    func discard() {
        if let mirrored {
            endOnPhone(.discardFromWatch(id: mirrored.session.id))
            return
        }
        close()
        Task { await workout.discard() }
    }

    /// A session too old to pick back up (the Watch died or restarted mid-session and nobody came
    /// back to save it): what was logged goes to the phone as it stood at the last change, rather
    /// than being lost with the file.
    private static func finishLeftOver(_ stored: StoredSession) {
        let record = stored.live.record(feedback: nil, now: stored.live.updatedAt)
        if record.hasContent {
            WatchStorage.log.notice("Saving a session left unfinished since \(stored.live.updatedAt, privacy: .public)")
            PhoneLink.shared.send(record)
            markFinished(stored.live.plan)
        }
        WatchStorage.remove(WatchStorage.session)
    }

    private func close() {
        alarm?.cancel()
        session = nil
        WatchStorage.remove(WatchStorage.session)
        writeSnapshot()
    }

    // MARK: Changes

    /// The item's id: changes name items by id, since either device can reorder them.
    private func itemID(_ index: Int) -> UUID? {
        guard let live, live.items.indices.contains(index) else { return nil }
        return live.items[index].id
    }

    /// Makes a change to the session on screen: this Watch's own, or its copy of the phone's, which
    /// the change goes to as well. `local` changes what only this Watch keeps (its timers).
    private func perform(_ kind: SessionChange.Kind, local: (inout StoredSession) -> Void = { _ in }) {
        guard var stored = session else { return }
        var environment = stored.context.environment(catalog: catalog)
        if var copy = mirrored {
            // Every change not yet taken, in order: one sent earlier may not have got there.
            if copy.make(kind, environment: environment) != nil { send(.changes(copy.pending)) }
            mirrored = copy
            stored.live = copy.session
        } else {
            // A session of the Watch's own keeps no history (it's saved after every change); a swap
            // prescribes from the history the phone sent for the plan's likely swaps.
            if environment.history.isEmpty, let history = context?.history { environment.history = history }
            stored.live.apply(kind, environment: environment)
        }
        local(&stored)
        session = stored
        changed()
    }

    /// A change only this Watch keeps: its timers, and whether it's wrapping up.
    private func update(_ change: (inout StoredSession) -> Void) {
        guard var stored = session else { return }
        change(&stored)
        session = stored
        changed()
    }

    private func changed() {
        save()
        scheduleAlarm()
    }

    /// The Watch's own session goes to disk after every change. The phone's is the phone's to keep.
    private func save() {
        guard let session, mirrored == nil else { return }
        WatchStorage.save(session, to: WatchStorage.session)
        lastSave = Date()
    }

    // MARK: Heart rate

    private func startWorkout(syncID: UUID) {
        guard healthEnabled, !workout.isRunning else { return }
        Task {
            _ = await HealthBridge.shared.requestAuthorization()
            try? await workout.start(syncID: syncID)
        }
    }

    // MARK: The iPhone's session

    /// The phone started a session and asked for heart rate: a workout here, mirrored to it, and then
    /// the session itself, to log into. A session already running on this Watch carries on instead.
    func startCompanion() {
        guard session == nil, companionSince == nil, healthEnabled else { return }
        // A summary still on screen from earlier would cover the heart rate and its Stop button.
        summary = nil
        let since = Date()
        companionSince = since
        Task {
            _ = await HealthBridge.shared.requestAuthorization()
            // Stopped while Health was asking: nothing to start.
            guard companionSince == since else { return }
            do {
                try await workout.startMirrored()
            } catch {
                if companionSince == since { companionSince = nil }
                return
            }
            // Stopped while it was starting: nothing would ever end it.
            if companionSince != since {
                await workout.discard()
                return
            }
            send(.join)
            startLinkRetry()
        }
    }

    /// Stops measuring for the iPhone: Stop or Continue on iPhone here, or the system ending the
    /// workout (another workout app started, say). The session carries on on the phone, which saves
    /// the workout to Health itself once it no longer sees this one, so this one is discarded rather
    /// than saved: it has no session id yet, and the two would overlap in Health.
    func stopCompanion() {
        // Never a workout this Watch's own session is running.
        guard companionSince != nil || workout.isMirrored else { return }
        // Sets logged here that haven't landed get one last try.
        if let pending = mirrored?.pending, !pending.isEmpty { send(.changes(pending)) }
        companionSince = nil
        leavePhoneSession(saved: false)
        Task { await workout.discard() }
    }

    /// What the phone sends, over the workout or WatchConnectivity.
    private func fromPhone(_ data: [Data]) {
        for item in data {
            guard let message = MirrorMessage(encoded: item) else { continue }
            switch message {
            case .finish(let id, _):
                // The phone's session is over: this workout, with its heart rate and energy, is the one Health keeps.
                guard endsWorkout(for: id) else { continue }
                leavePhoneSession(saved: true)
                companionSince = nil
                Task { _ = await workout.end(syncID: id) }
            case .discard(let id, let saved):
                guard endsWorkout(for: id) else { continue }
                leavePhoneSession(saved: saved)
                companionSince = nil
                Task { await workout.discard() }
            case .session(let copy, let sent, let sentAt):
                receive(copy, context: sent, sentAt: sentAt)
            case .heartRate, .join, .changes, .finishFromWatch, .discardFromWatch:
                break
            }
        }
    }

    /// Whether the phone's end of session `id` is for the workout running here: the session on screen,
    /// or, before its first copy has come, any but one already left (a late end of the last session,
    /// by the slower route, mustn't end the next one's workout).
    private func endsWorkout(for id: UUID) -> Bool {
        guard companionSince != nil || mirrored != nil, !leftSessions.contains(id) else { return false }
        return mirrored.map { $0.session.id == id } ?? true
    }

    /// The phone's session as it stands: shown, with what's been done here since made on top. Only
    /// while measuring for the phone: not after Stop, and never over a session of this Watch's own,
    /// one already left, or a copy older than the session on screen.
    private func receive(_ copy: LiveSession, context sent: PhoneContext?, sentAt: Date) {
        guard companionSince != nil, mirrored != nil || session == nil, !leftSessions.contains(copy.id) else { return }
        if let mirrored, mirrored.session.id != copy.id, sentAt <= mirrored.sentAt { return }
        if let sent { mirroredContext = sent }
        // Without the gym's loads there's nothing to show the session with: the retry asks again.
        guard let context = mirroredContext ?? context else { return }
        let environment = context.environment(catalog: catalog)
        if var here = mirrored, here.session.id == copy.id {
            guard here.receive(copy, sentAt: sentAt, environment: environment) else { return }
            mirrored = here
            session?.live = here.session
            session?.context = context
        } else {
            // The first copy, or a new session started on the phone (the last one's end never came).
            if let old = mirrored { remember(left: old.session.id) }
            mirrored = MirroredSession(copy, sentAt: sentAt)
            session = StoredSession(live: copy, context: context)
            endingOnPhone = nil
            summary = nil
            writeSnapshot()
        }
        // Ending waits for the sets logged here to land, so the phone saves them.
        if let endingOnPhone, mirrored?.pending.isEmpty == true { send(endingOnPhone) }
        scheduleAlarm()
    }

    #if DEBUG
    /// A session as if the phone ran it and had sent it, for trying the Watch's side without a phone.
    func followSample(_ plan: SessionPlan, context sample: PhoneContext) {
        companionSince = Date()
        receive(LiveSession(plan: plan, device: "iPhone"), context: sample, sentAt: Date())
    }
    #endif

    /// Asks the phone to finish or discard its session, once what was logged here has landed.
    private func endOnPhone(_ message: MirrorMessage) {
        endingOnPhone = message
        if mirrored?.pending.isEmpty == true { send(message) }
    }

    /// Off the phone's session: it's over there, or this Watch stopped following it. The summary
    /// shows when the phone saved it with something in it.
    private func leavePhoneSession(saved: Bool) {
        linkRetry?.cancel()
        linkRetry = nil
        guard let copy = mirrored else { return }
        remember(left: copy.session.id)
        if saved {
            let record = copy.session.record(feedback: nil)
            if record.hasContent {
                summary = SessionSummary(
                    record, plan: copy.session.plan, savedOnPhone: true, known: mirroredContext ?? context, catalog: catalog)
            }
        }
        mirrored = nil
        mirroredContext = nil
        endingOnPhone = nil
        alarm?.cancel()
        session = nil
        writeSnapshot()
    }

    private func remember(left id: UUID) {
        leftSessions = Array((leftSessions.filter { $0 != id } + [id]).suffix(10))
    }

    /// Every couple of seconds while measuring for the phone: whatever it hasn't answered goes again.
    private func startLinkRetry() {
        linkRetry?.cancel()
        linkRetry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.retryLink()
            }
        }
    }

    /// Joining, until the session (and the gym to show it with) arrives; then the changes the phone
    /// hasn't taken, and ending the session once they're in.
    private func retryLink() {
        guard companionSince != nil else { return }
        guard let mirrored, (mirroredContext ?? context) != nil else {
            send(.join)
            return
        }
        if !mirrored.pending.isEmpty {
            send(.changes(mirrored.pending))
        } else if let endingOnPhone {
            send(endingOnPhone)
        }
    }

    /// To the phone: over WatchConnectivity when it's reachable, and over the workout unless sends
    /// there are stuck. Heart rate goes over the workout only, unless sends there are stuck: a
    /// reading twice would count twice.
    private func send(_ message: MirrorMessage, bothRoutes: Bool = true) {
        guard let data = message.encoded() else { return }
        let workoutRouteFull = mirrorSendsInFlight.count >= 3
        if bothRoutes || workoutRouteFull { PhoneLink.shared.sendLive(data) }
        guard !workoutRouteFull else { return }
        // A send that hangs stops counting after ten seconds, so a few can't close the route for good.
        let token = UUID()
        mirrorSendsInFlight.insert(token)
        let workout = workout
        Task { [weak self] in
            await workout.send(data)
            self?.mirrorSendsInFlight.remove(token)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.mirrorSendsInFlight.remove(token)
        }
    }

    private func heartRate(_ bpm: Double) {
        if companionSince != nil {
            send(.heartRate(bpm: bpm, date: Date()), bothRoutes: false)
            // Kept on the copy for zone minutes; the phone decides whether it ends a rest.
            guard var copy = mirrored else { return }
            copy.record(heartRate: bpm, zones: zones)
            mirrored = copy
            session?.live = copy.session
            return
        }
        guard var stored = session else { return }
        let endsAt = stored.live.rest?.endsAt
        if stored.live.record(heartRate: bpm, zones: stored.context.zones) {
            stored.live.endRest()
            session = stored
            changed()
            show(Notice(text: "Heart rate recovered", symbol: "heart.fill"))
            showGo(early: endsAt.map { Int($0.timeIntervalSinceNow.rounded()) })
            WKInterfaceDevice.current().play(.success)
        } else {
            session = stored
            // Samples arrive every few seconds; they needn't hit the disk as often.
            if Date().timeIntervalSince(lastSave) > 30 { save() }
        }
    }

    /// The heart rate on screen: the workout's, or a sample one in DEBUG.
    var heartRate: Double? {
        #if DEBUG
        if let debugHeartRate { return debugHeartRate }
        #endif
        return workout.heartRate
    }

    /// Puts the set face in the accent for a few seconds after a rest ran out on its own.
    private func showGo(early: Int?) {
        go = GoMoment(heartRate: heartRate, early: early.flatMap { $0 > 0 ? $0 : nil })
        goTask?.cancel()
        goTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.go = nil
        }
    }

    #if DEBUG
    /// `-sampleRestElapsed 96`: the rest as if it began that long ago, to see its level part way up.
    func ageSampleRest(by seconds: TimeInterval) {
        guard var stored = session, var rest = stored.live.rest else { return }
        rest.started.addTimeInterval(-seconds)
        rest.endsAt.addTimeInterval(-seconds)
        stored.live.rest = rest
        session = stored
        scheduleAlarm()
    }

    /// `-sampleScreen go`: the go face, as heart rate ending a rest early leaves it.
    func showSampleGo() {
        go = GoMoment(heartRate: heartRate, early: 22)
    }
    #endif

    func dismissGo() {
        goTask?.cancel()
        go = nil
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: Timers and haptics

    private enum Alarm {
        case restOver, timerDone, conditioningDone
        case interval(work: Bool)
    }

    /// The next moment something should happen on its own: a rest ending, a drill's countdown,
    /// conditioning reaching its minutes, or an interval switching. A rest in the phone's session
    /// that has run out is left for the phone, which keeps it until the next set.
    private func nextAlarm(after now: Date) -> (date: Date, alarm: Alarm)? {
        guard let stored = session else { return nil }
        if let rest = stored.live.rest, mirrored == nil || rest.endsAt > now { return (rest.endsAt, .restOver) }
        guard let timer = stored.timer, let item = stored.live.items.first(where: { $0.id == timer.item }) else { return nil }
        if let plan = item.plan.conditioning {
            let target = timer.started.addingTimeInterval(TimeInterval(plan.minutes * 60))
            var next: (date: Date, alarm: Alarm)? = target > now ? (target, .conditioningDone) : nil
            if plan.style == .intervals, let work = plan.workSeconds, let easy = plan.restSeconds, work > 0, easy > 0 {
                let cycle = Double(work + easy)
                let round = (now.timeIntervalSince(timer.started) / cycle).rounded(.down)
                let workEnds = timer.started.addingTimeInterval(round * cycle + Double(work))
                let switchAt: (date: Date, alarm: Alarm) =
                    workEnds > now
                    ? (workEnds, .interval(work: false))
                    : (timer.started.addingTimeInterval((round + 1) * cycle), .interval(work: true))
                if switchAt.date < target { next = switchAt }
            }
            return next
        }
        guard item.sets.indices.contains(timer.set),
            let seconds = item.sets[timer.set].prescription.seconds ?? item.plan.seconds
        else { return nil }
        let done = timer.started.addingTimeInterval(TimeInterval(seconds))
        return done > now ? (done, .timerDone) : nil
    }

    private func scheduleAlarm(after now: Date = Date()) {
        alarm?.cancel()
        guard let next = nextAlarm(after: now) else { return }
        alarm = Task { [weak self] in
            let delay = next.date.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.fire(next.alarm, due: next.date)
        }
    }

    private func fire(_ alarm: Alarm, due: Date) {
        // Something that came due while the app wasn't running passes quietly.
        let late = Date().timeIntervalSince(due) > 10
        let device = WKInterfaceDevice.current()
        switch alarm {
        case .restOver:
            if !late { device.play(.stop) }
            if mirrored != nil {
                restsRunOut += 1
                scheduleAlarm(after: max(Date(), due.addingTimeInterval(0.01)))
            } else {
                endRest()
            }
            if !late { showGo(early: nil) }
        case .timerDone, .conditioningDone:
            if !late { device.play(.notification) }
            scheduleAlarm(after: max(Date(), due.addingTimeInterval(0.01)))
        case .interval(let work):
            if !late { device.play(work ? .start : .stop) }
            scheduleAlarm(after: max(Date(), due.addingTimeInterval(0.01)))
        }
    }

    // MARK: Complication

    private func writeSnapshot() {
        moveDayOn()
        var snapshot = WidgetSnapshot.empty
        if let context {
            if let stored = session {
                snapshot.title = stored.live.plan.title
                snapshot.detail = "In progress"
                snapshot.minutes = stored.live.plan.estimatedMinutes
            } else if isStale {
                snapshot.detail = "Open Stadig Lift on iPhone"
            } else if let plan = context.plan, context.upNext == nil {
                snapshot.day = plan.day
                snapshot.title = plan.title
                snapshot.detail = finishedToday ? "Done today" : "Today"
                snapshot.exercises = plan.items.filter(\.isStrength).prefix(5).map { catalog.resolve($0.exerciseID).name }
                snapshot.minutes = finishedToday ? nil : plan.estimatedMinutes
                snapshot.badge = plan.deload ? "Deload" : plan.assessment ? "Assessment" : plan.checkIn ? "Check-in" : nil
            } else {
                snapshot.day = Day(context.sentAt)
                snapshot.title = "Rest day"
                snapshot.detail = context.upNext.map { "Next: \($0)" } ?? "Nothing planned"
            }
        }
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }
}
