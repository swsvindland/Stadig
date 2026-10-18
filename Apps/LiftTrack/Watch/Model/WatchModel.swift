import Foundation
import Observation
import OSLog
import WatchKit
import WidgetKit
import ExerciseLibrary
import HealthBridge
import LiftEngine
import SystemCore

/// What the session screen shows next.
enum SessionStep: Equatable {
    case rest
    /// A loaded set: crown for the load, then a rating.
    case set(item: Int, set: Int)
    /// Mobility, warm-up, stretches and unloaded holds: a countdown or a count, then Done.
    case timed(item: Int, set: Int)
    case conditioning(item: Int)
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
    var ratings: [SetRating: Int]
    var conditioningMinutes: Int
    var averageHeartRate: Double?

    init(_ record: SessionRecord) {
        title = record.title
        minutes = record.minutes
        exercises = record.exercises.count
        workSets = record.workSets.count
        ratings = Dictionary(grouping: record.workSets.compactMap(\.rating)) { $0 }.mapValues(\.count)
        conditioningMinutes = record.conditioning.map(\.minutes).reduce(0, +)
        averageHeartRate = record.averageHeartRate
    }
}

/// The Watch's state: the phone's latest context, the session in progress and its live workout.
/// The session is the same pure state machine the phone runs; this model persists it after every
/// change, feeds it heart rate, and keeps the timers and haptics that rests and drills need.
@MainActor @Observable
final class WatchModel {
    /// One model: the app's scene and the phone's request to start a workout share it.
    static let shared = WatchModel()

    let catalog = ExerciseCatalog()
    let workout = LiveWorkoutSession()

    /// Measuring heart rate for a session the iPhone runs, since this time.
    private(set) var companionSince: Date?

    private(set) var context: PhoneContext?
    private(set) var session: StoredSession?
    /// The last finished session, until the person dismisses it.
    var summary: SessionSummary?
    private(set) var notice: Notice?
    /// False skips HealthKit (sample sessions in the simulator).
    var healthEnabled = true
    #if DEBUG
    /// A screen for the sample session to open on.
    var debugRoute: String?
    #endif

    @ObservationIgnored private var alarm: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var lastSave = Date.distantPast
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
        guard let plan = context?.plan, !isStale, let done = UserDefaults.standard.string(forKey: "finished") else { return false }
        return done == Self.finishedKey(plan)
    }

    private static func finishedKey(_ plan: SessionPlan) -> String { "\(plan.day.iso) \(plan.dayID?.uuidString ?? plan.title)" }

    // MARK: Where we are

    var live: LiveSession? { session?.live }

    /// Loads, zones and the gym come from the context the session started with.
    var sessionContext: PhoneContext? { session?.context ?? context }
    var unit: WeightUnit { sessionContext?.gym.unit ?? .kg }
    var zones: HeartRateZones { sessionContext?.zones ?? .estimated(age: nil, resting: nil) }

    /// The item and set to do next, in the session's order (which "Do This Now" changes), alternating
    /// within a superset.
    var position: (item: Int, set: Int)? { session?.live.current }

    var step: SessionStep? {
        guard let stored = session else { return nil }
        if stored.wrappingUp { return .finish }
        if stored.live.rest != nil { return .rest }
        guard let (item, set) = position else { return .finish }
        let planned = stored.live.items[item].plan
        if planned.role == .conditioning || planned.conditioning != nil { return .conditioning(item: item) }
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

    /// Where the crown starts: the prescribed load, else a sensible guess for a finding-weight set
    /// (the last load used, the phone's estimate, none for bodyweight and assisted work, else the
    /// lightest makeable load).
    func startingLoad(item index: Int, set setIndex: Int) -> Double? {
        guard let live, live.items.indices.contains(index), live.items[index].sets.indices.contains(setIndex) else { return nil }
        let item = live.items[index]
        let exercise = catalog.resolve(item.exerciseID)
        guard exercise.loadBasis != .none else { return nil }
        if let load = item.sets[setIndex].prescription.loadKg { return load }
        if let last = item.loggedSets.last { return last.loadKg }
        if let last = context?.history[item.exerciseID]?.last(where: { $0.kind.countsAsWork }) { return last.loadKg }
        // The phone's guess from bodyweight and experience, so a heavy leg press isn't a long crown turn away.
        if let guess = context?.startingLoads?[item.exerciseID] { return guess }
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
        guard let environment = session?.context.environment(catalog: catalog) else { return }
        let peak = workout.heartRate
        update { stored in
            stored.live.log(item: item, set: set, reps: reps, loadKg: loadKg, rating: rating, seconds: seconds,
                            heartRatePeak: peak, environment: environment)
            stored.timer = nil
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
        guard let stored = session else { return }
        let now = Date()
        let started = timer(for: item, set: 0)?.started ?? now
        let minutes = max(1, Int((now.timeIntervalSince(started) / 60).rounded()))
        let average = stored.live.averageHeartRate(from: started, to: now)
        let zoneMinutes = stored.live.zoneMinutes(from: started, to: now, zones: stored.context.zones)
        update { stored in
            stored.live.logConditioning(item: item, minutes: minutes, averageHeartRate: average, zoneMinutes: zoneMinutes)
            stored.timer = nil
        }
    }

    func skipSet(item: Int, set: Int) {
        update { stored in
            guard stored.live.items.indices.contains(item) else { return }
            stored.live.skipSet(item: item, set: set)
            // Its countdown would otherwise carry over to the next set.
            if let timer = stored.timer, timer.item == stored.live.items[item].id, timer.set == set { stored.timer = nil }
        }
    }

    func skip(item: Int) {
        update { stored in
            guard stored.live.items.indices.contains(item) else { return }
            stored.live.skip(item: item)
            if stored.timer?.item == stored.live.items[item].id { stored.timer = nil }
        }
    }

    func addSet(item: Int) { update { $0.live.addSet(item: item) } }

    /// Does an item next, ahead of the plan's order: it moves up with its superset partner, as on
    /// the phone, so the pair still alternates with their own rests.
    func focus(item: Int) {
        update { stored in
            guard stored.live.items.indices.contains(item) else { return }
            let id = stored.live.items[item].id
            stored.live.doNext(item: item)
            stored.live.endRest()
            // A countdown left running on the item put aside would still go off, and show again on return.
            if let timer = stored.timer, timer.item != id { stored.timer = nil }
        }
    }

    func endRest() { update { $0.live.endRest() } }

    func extendRest(by seconds: Int) { update { $0.live.extendRest(by: seconds) } }

    func wrapUp() { update { $0.wrappingUp = true } }

    func keepGoing() { update { $0.wrappingUp = false } }

    /// Saves the session: the record goes to the phone and the workout to Health. A session with
    /// nothing logged is discarded instead.
    func finish(feedback: SessionFeedback?) {
        guard let stored = session else { return }
        let record = stored.live.record(feedback: feedback)
        guard record.hasContent else {
            discard()
            return
        }
        PhoneLink.shared.send(record)
        UserDefaults.standard.set(Self.finishedKey(stored.live.plan), forKey: "finished")
        summary = SessionSummary(record)
        close()
        Task { _ = await workout.end() }
    }

    func discard() {
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
            UserDefaults.standard.set(finishedKey(stored.live.plan), forKey: "finished")
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

    private func save() {
        guard let session else { return }
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

    // MARK: Heart rate for the iPhone

    /// The phone started a session and asked for heart rate: a workout here, mirrored to it. A
    /// session already running on this Watch carries on instead.
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
            if companionSince != since { await workout.discard() }
        }
    }

    /// Stops measuring for the iPhone: Stop here, or the system ending the workout (another workout
    /// app started, say). The session carries on on the phone, which saves the workout to Health
    /// itself once it no longer sees this one, so this one is discarded rather than saved: it has no
    /// session id yet, and the two would overlap in Health.
    func stopCompanion() {
        // Never a workout this Watch's own session is running.
        guard companionSince != nil || workout.isMirrored else { return }
        companionSince = nil
        Task { await workout.discard() }
    }

    /// Messages only arrive over the mirrored workout, so they act on it whatever `companionSince` says.
    private func fromPhone(_ data: [Data]) {
        for item in data {
            guard let message = try? JSONDecoder().decode(MirrorMessage.self, from: item) else { continue }
            switch message {
            case .finish(let id, _):
                // The phone's session is over: this workout, with its heart rate and energy, is the one Health keeps.
                companionSince = nil
                Task { _ = await workout.end(syncID: id) }
            case .discard:
                companionSince = nil
                Task { await workout.discard() }
            case .heartRate:
                break
            }
        }
    }

    private func heartRate(_ bpm: Double) {
        if companionSince != nil, let data = try? JSONEncoder().encode(MirrorMessage.heartRate(bpm: bpm, date: Date())) {
            Task { await workout.send(data) }
            return
        }
        guard var stored = session else { return }
        if stored.live.record(heartRate: bpm, zones: stored.context.zones) {
            stored.live.endRest()
            session = stored
            changed()
            show(Notice(text: "Heart rate recovered", symbol: "heart.fill"))
            WKInterfaceDevice.current().play(.success)
        } else {
            session = stored
            // Samples arrive every few seconds; they needn't hit the disk as often.
            if Date().timeIntervalSince(lastSave) > 30 { save() }
        }
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
    /// conditioning reaching its minutes, or an interval switching.
    private func nextAlarm(after now: Date) -> (date: Date, alarm: Alarm)? {
        guard let stored = session else { return nil }
        if let rest = stored.live.rest { return (rest.endsAt, .restOver) }
        guard let timer = stored.timer, let item = stored.live.items.first(where: { $0.id == timer.item }) else { return nil }
        if let plan = item.plan.conditioning {
            let target = timer.started.addingTimeInterval(TimeInterval(plan.minutes * 60))
            var next: (date: Date, alarm: Alarm)? = target > now ? (target, .conditioningDone) : nil
            if plan.style == .intervals, let work = plan.workSeconds, let easy = plan.restSeconds, work > 0, easy > 0 {
                let cycle = Double(work + easy)
                let round = (now.timeIntervalSince(timer.started) / cycle).rounded(.down)
                let workEnds = timer.started.addingTimeInterval(round * cycle + Double(work))
                let switchAt: (date: Date, alarm: Alarm) = workEnds > now
                    ? (workEnds, .interval(work: false))
                    : (timer.started.addingTimeInterval((round + 1) * cycle), .interval(work: true))
                if switchAt.date < target { next = switchAt }
            }
            return next
        }
        guard item.sets.indices.contains(timer.set),
              let seconds = item.sets[timer.set].prescription.seconds ?? item.plan.seconds else { return nil }
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
            endRest()
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
                snapshot.detail = "Open Lift Track on iPhone"
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
