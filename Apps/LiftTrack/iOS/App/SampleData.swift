#if DEBUG
import Foundation
import ExerciseLibrary
import LiftEngine
import SystemCore
import SystemStore

/// `-seedSampleData`: a lifter three weeks into the assessment, every session run through the
/// real engine (plan, live session, autoregulation), so the screens show realistic data.
@MainActor
enum SampleData {
    static func seedIfEmpty(_ model: AppModel) {
        guard model.profile == nil else { return }
        let start = Day.today.adding(days: -20)
        let profile = SharedProfile(
            goals: [.biggerAndStronger, .leaner], schedule: TrainingSchedule(daysPerWeek: 4, minutesPerSession: 60),
            equipment: .fullGym, experience: .intermediate,
            recurring: [RecurringActivity(activity: .bjj, weekdays: [.tuesday, .thursday], minutes: 75, intensity: 7)],
            sex: .male, birthYear: 1991, heightCm: 180, units: UnitPreference(weight: .kg, length: .cm), createdBy: .liftTrack)
        var settings = LiftSettings(selfReportedPhase: .maintaining, saveToHealth: false)
        let gym = Gym.preset(.fullGym, unit: .kg)
        settings.gymID = gym.id
        // Two full check-ins, the left arm a little behind both times.
        model.completeOnboarding(
            profile: profile, settings: settings, gym: gym,
            measurements: BodyMeasurements(
                day: start, weightKg: 82, neckCm: 39, shouldersCm: 116, chestCm: 104, waistCm: 86,
                naturalWaistCm: 82, hipsCm: 94, glutesCm: 100, armLeftCm: 35.2, armRightCm: 37,
                thighLeftCm: 58, thighRightCm: 58.5, calfLeftCm: 38, calfRightCm: 38.2))
        model.save(
            measurements: BodyMeasurements(
                day: .today.adding(days: -2), neckCm: 39, shouldersCm: 116.5, chestCm: 104.5, waistCm: 85,
                naturalWaistCm: 81, hipsCm: 93.5, glutesCm: 100, armLeftCm: 35.6, armRightCm: 37.4,
                thighLeftCm: 58.5, thighRightCm: 58.6, calfLeftCm: 38.1, calfRightCm: 38.2))
        // Move the assessment back three weeks.
        if var assessment = model.mesocycles.last {
            assessment.block.start = start
            model.save(assessment)
            var s = model.settings
            s.assessmentStart = start
            model.save(settings: s)
        }
        var day = start
        var sessionsDone = 0
        while day < .today {
            if profile.schedule.trainingDays.contains(day.weekday), let analysis = model.analysis, let next = analysis.next,
                let mesocycle = analysis.mesocycle
            {
                let context = PlanningContext(
                    catalog: model.catalog, gym: gym, profile: profile, settings: model.settings, trust: analysis.trust,
                    phase: analysis.phase, life: analysis.life, history: analysis.history, bodyweightKg: 82,
                    enduranceScore: analysis.endurance.score, sessionIndexInWeek: next.doneThisWeek)
                let plan = SessionPlanner.plan(next.day, of: mesocycle, on: day, context: context)
                let begin = day.date().addingTimeInterval(17.5 * 3600)
                var live = LiveSession(plan: plan, device: "iPhone", now: begin)
                let environment = SessionEnvironment(
                    catalog: model.catalog, gym: gym, trust: analysis.trust, phase: analysis.phase.effects,
                    bodyweightKg: 82, history: analysis.history, enduranceScore: nil, heartRateGuidedRest: false)
                perform(&live, growth: growth(after: sessionsDone), environment: environment, begin: begin)
                model.keep(
                    live.record(
                        feedback: SessionFeedback(soreness: sessionsDone % 3 == 0 ? 2 : 1, energy: 3 + sessionsDone % 2),
                        now: begin.addingTimeInterval(62 * 60)))
                sessionsDone += 1
            }
            if [.tuesday, .thursday].contains(day.weekday), day < .today {
                model.save(
                    activity: ActivityLog(
                        type: .bjj, start: day.date().addingTimeInterval(19 * 3600), minutes: 75, intensity: 7,
                        martialArts: MartialArtsDetails(classType: .sparring, sparringRounds: 5, roundsBeforeGassed: 4)))
            }
            day = day.adding(days: 1)
        }
        model.save(mobility: [
            MobilityResult(test: .hip9090, day: start.adding(days: 3), value: 1),
            MobilityResult(test: .deepSquatHold, day: start.adding(days: 3), value: 35),
            MobilityResult(test: .kneeToWall, day: start.adding(days: 3), value: 9),
            MobilityResult(test: .sitAndReach, day: start.adding(days: 3), value: -4),
            MobilityResult(test: .overheadReach, day: start.adding(days: 3), value: 2),
        ])
        model.save(benchmark: BenchmarkResult(benchmark: .stairs10min, day: start.adding(days: 4), value: 52))
        model.steps = steps()
        model.recompute()
        // The scores day by day since they began, arriving at today's.
        model.store.save(scores(arrivingAt: model.stats, since: start, today: model.today))
        model.recompute()
    }

    /// The scores each day from `start` to yesterday, as the lifter's store would have recorded them,
    /// arriving at today's: Strength climbing as the assessment found working weights, Discipline
    /// settling in, Endurance a little up, Agility steady, and Physique up a point at the second
    /// check-in, two days ago. The same path every launch.
    static func scores(arrivingAt lines: [StatLine], since start: Day, today: Day) -> [ScoreDayRecord] {
        let rise: [StatKind: Double] = [.strength: 5.2, .endurance: 1.4, .agility: 0.4, .discipline: 4.3]
        let now = lines.compactMap { line in line.sources.first { $0.app == .liftTrack }?.exact.map { (stat: line.stat, score: $0) } }
        let span = Double(max(1, start.days(until: today)))
        return stride(from: start.days(until: today), to: 0, by: -1).map { back in
            let day = today.adding(days: -back)
            var scores: [StatKind: Double] = [:]
            for (stat, score) in now {
                let wobble = 0.3 * sin(Double(day.ordinal + 7 * stat.rawValue.count))
                let then = stat == .physique ? (back > 2 ? score - 1.2 : score) : score - (rise[stat] ?? 0) * Double(back) / span + wobble
                scores[stat] = (then * 10).rounded() / 10
            }
            return ScoreDayRecord(day: day, scores: scores, updatedAt: day.at(hour: 21, minute: 0))
        }
    }

    /// Steps when Health has none (the simulator): about 5,700 a day for ten weeks, busier at
    /// weekends, and this morning's so far.
    static func steps(today: Day = .today) -> [StepDay] {
        (0...70).reversed().map { back in
            let day = today.adding(days: -back)
            let wobble = (day.ordinal * 7_919) % 2_400 - 1_200
            let weekend = day.weekday == .saturday || day.weekday == .sunday ? 1_800 : 0
            return StepDay(day: day, steps: back == 0 ? 3_150 : 5_200 + weekend + wobble)
        }
    }

    /// The lifter's one-rep maxes, fresh, on the first day of the sample: what each set is worked
    /// out from (`perform`).
    static let truth: [String: Double] = [
        "barbell-back-squat": 140, "conventional-deadlift": 165, "barbell-bench-press": 92,
        "barbell-incline-bench-press": 78, "barbell-overhead-press": 55, "pull-up": 108, "barbell-row": 80,
    ]

    /// How much stronger than on the first day the lifter is after so many sessions.
    static func growth(after sessions: Int) -> Double { 1 + 0.004 * Double(sessions) }

    /// `-sessionAt summary`: today's session, begun by `-startSession`, done the whole way through as
    /// the sample lifter would, each set after its rest, with a Watch on (its heart rate ending the
    /// rests it guides once recovered), then finished, for its summary. Its numbers, what moved,
    /// Strength's gain and the lessons all come from the real engine. Today is a good day on the main
    /// lifts, as a session that ends on a new best is, each one's last set taken a few reps past what
    /// was asked: the smallest good day, from 2% over the lifter's trend, on which the session moves
    /// Strength a whole point, so the summary has Strength's gain whichever day of the week the sample
    /// lands on.
    static func finishToday(_ model: AppModel, now: Date = Date()) {
        guard let started = model.live, let environment = model.environment, let state = model.state else { return }
        let trend = growth(after: model.sessions.count)
        let zones = model.heartRateZones
        // Everything in a session is timed from its start, so a session done from the same start is
        // the same session wherever it's begun.
        func run(onAGoodDay boost: Double) -> (session: LiveSession, end: Date) {
            var session = started
            let end = perform(
                &session, growth: trend, mainLifts: boost, environment: environment, begin: started.startedAt, timed: true, heartRate: zones)
            return (session, end)
        }
        func strength(with session: LiveSession, end: Date) -> Int? {
            var after = state
            after.sessions.append(session.record(feedback: nil, now: end))
            return Analyst.analyse(after).strength.overall.map { Int($0.rounded()) }
        }
        let before = model.analysis?.strength.overall.map { Int($0.rounded()) }
        let boost =
            stride(from: 1.02, through: 1.12, by: 0.01).first { boost in
                let trial = run(onAGoodDay: boost)
                guard let before, let after = strength(with: trial.session, end: trial.end) else { return false }
                return after > before
            } ?? 1.03
        // Begun as long ago as it takes, so it ends now.
        let length = run(onAGoodDay: boost).end.timeIntervalSince(started.startedAt)
        model.update { live in
            live.startedAt = now.addingTimeInterval(-length)
            perform(&live, growth: trend, mainLifts: boost, environment: environment, begin: live.startedAt, timed: true, heartRate: zones)
        }
        model.finish(feedback: SessionFeedback(soreness: 1, jointPain: [], energy: 4))
    }

    /// Performs a session the way a consistent, honest lifter would, and returns when it ended:
    /// `growth` over the first day's strength, and the main lifts `mainLifts` over that, a good day,
    /// when their last sets go past the reps asked for. The history's sessions are a set every 100
    /// seconds; a `timed` one waits out each rest and takes as long as each set would, and with
    /// `heartRate` sends readings as a Watch would, which end the rests heart rate guides once it's
    /// back down.
    @discardableResult
    private static func perform(
        _ live: inout LiveSession, growth: Double, mainLifts: Double = 1, environment: SessionEnvironment, begin: Date, timed: Bool = false,
        heartRate zones: HeartRateZones? = nil
    ) -> Date {
        var clock = begin
        var guardCount = 0
        var begun: Set<Int> = []
        var pulse = Pulse(at: begin)
        while let (i, s) = live.current, guardCount < 300 {
            guardCount += 1
            // A rest heart rate ends works the set's reps out again for the rest taken: read it after.
            if timed, let zones { clock = pulse.rest(&live, from: clock, zones: zones) }
            let item = live.items[i]
            let prescription = item.sets[s].prescription
            let set = item.plan.isStrength ? attempt(item, s, growth: growth, mainLifts: mainLifts, environment: environment) : nil
            if timed {
                let end = done(
                    item, prescription, reps: set?.reps ?? prescription.targetReps, after: clock, rest: live.rest,
                    settingUp: item.plan.isStrength && !begun.contains(i))
                if let zones {
                    pulse.work(&live, until: end, item: item, prescription: prescription, reps: set?.reps ?? prescription.targetReps, zones: zones)
                }
                clock = end
            } else {
                clock = clock.addingTimeInterval(100)
            }
            begun.insert(i)
            if item.plan.role == .conditioning {
                live.logConditioning(item: i, minutes: item.plan.conditioning?.minutes ?? 10, averageHeartRate: 128, zoneMinutes: [2: 10], now: clock)
                continue
            }
            guard let set else {
                live.log(
                    item: i, set: s, reps: prescription.targetReps, loadKg: nil, rating: nil, seconds: prescription.seconds,
                    environment: environment, now: clock)
                continue
            }
            live.log(item: i, set: s, reps: set.reps, loadKg: set.load, rating: set.rating, environment: environment, now: clock)
        }
        return clock
    }

    /// What the lifter does with a lifting set: its reps, at what weight, and how it felt. A warm-up
    /// as asked; a rep-out all there is; a work set as asked when it's in them (rated Easy with three
    /// or more left), else what's there, missed. On a good day a main lift's last set goes on while
    /// there are two reps in it, a few at most.
    private static func attempt(
        _ item: LiveItem, _ s: Int, growth: Double, mainLifts: Double, environment: SessionEnvironment
    ) -> (reps: Int, load: Double, rating: SetRating?) {
        let prescription = item.sets[s].prescription
        let exercise = environment.catalog.resolve(item.exerciseID)
        let fresh = (truth[exercise.id] ?? defaultTruth(exercise)) * growth * (item.plan.block == .main ? mainLifts : 1)
        let e1rm = fresh * (1 - 0.02 * Double(item.loggedSets.filter { $0.kind.countsAsWork }.count))
        let guess = OneRepMax.loggedLoad(forEffective: OneRepMax.load(e1rm: fresh, reps: 10, rir: 3), basis: exercise.loadBasis, bodyweightKg: 82)
        let load = prescription.loadKg ?? environment.increments(for: exercise).round(max(0, guess), down: true)
        let effective = OneRepMax.effectiveLoad(load, basis: exercise.loadBasis, bodyweightKg: 82)
        let capacity = effective > 0 ? Int(OneRepMax.repsToFailure(e1rm: e1rm, at: effective)) : 15
        switch prescription.kind {
        case .warmup: return (prescription.targetReps, load, nil)
        case .repOut: return (capacity, load, nil)
        default:
            if capacity < prescription.targetReps { return (capacity, load, .red) }
            var reps = prescription.targetReps
            let last = !item.sets.indices.contains { $0 > s && item.sets[$0].isOpen && item.sets[$0].prescription.kind.countsAsWork }
            if mainLifts > 1, item.plan.block == .main, last { reps = max(reps, min(capacity - 2, reps + 3)) }
            return (reps, load, capacity - reps >= 3 ? .green : .orange)
        }
    }

    /// When a set is done, from the last thing done, at the pace the plan's length assumes
    /// (`SessionPlan.estimatedMinutes`): the rest running out, getting set up for a lift, then the
    /// set itself, three seconds a rep done and a few to start, or its time, or the conditioning's minutes.
    private static func done(
        _ item: LiveItem, _ prescription: SetPrescription, reps: Int, after clock: Date, rest: RestState?, settingUp: Bool
    ) -> Date {
        let waiting = rest.map { max(0, $0.endsAt.timeIntervalSince(clock)) } ?? 0
        let work: TimeInterval =
            if item.plan.role == .conditioning {
                TimeInterval((item.plan.conditioning?.minutes ?? 10) * 60)
            } else if let seconds = prescription.seconds {
                TimeInterval(seconds)
            } else {
                15 + 3 * TimeInterval(reps)
            }
        return clock.addingTimeInterval(waiting + (settingUp ? 45 : 0) + work)
    }

    /// The sample lifter's heart rate, read every five seconds as the Watch sends it: climbing
    /// through a set toward its peak (higher for a main lift than an accessory, low for a warm-up or
    /// a drill, Zone 2 for the conditioning), and falling back toward 100 through the rest after it.
    private struct Pulse {
        var bpm = 95.0
        var peak = 95.0
        var settled: Date

        init(at start: Date) { settled = start }

        /// Through the rest running from `clock`: readings until heart rate ends it (`LiveSession.record`
        /// says it's recovered while it runs) or its time is up. Returns when the rest ended.
        mutating func rest(_ live: inout LiveSession, from clock: Date, zones: HeartRateZones) -> Date {
            guard let rest = live.rest, rest.endsAt > clock else { return clock }
            var time = clock.addingTimeInterval(5)
            while time < rest.endsAt {
                bpm = 100 + (peak - 100) * exp(-time.timeIntervalSince(settled) / 40)
                if live.record(heartRate: bpm.rounded(), zones: zones, now: time) {
                    live.endRest(now: time)
                    return time
                }
                time.addTimeInterval(5)
            }
            return clock
        }

        /// Through a set ending at `end`: from where heart rate was, up to the set's peak.
        mutating func work(
            _ live: inout LiveSession, until end: Date, item: LiveItem, prescription: SetPrescription, reps: Int, zones: HeartRateZones
        ) {
            let seconds = Double(prescription.seconds ?? (15 + 3 * reps))
            let top: Double =
                if item.plan.role == .conditioning {
                    128
                } else if !item.plan.isStrength {
                    105
                } else if prescription.kind == .warmup {
                    115
                } else {
                    item.plan.block == .main ? 150 : 140
                }
            let from = bpm
            var time = end.addingTimeInterval(-seconds)
            while time <= end {
                bpm = from + (top - from) * min(1, 1 - end.timeIntervalSince(time) / seconds)
                live.record(heartRate: bpm.rounded(), zones: zones, now: time)
                time.addTimeInterval(5)
            }
            peak = max(bpm, top)
            settled = end
        }
    }

    private static func defaultTruth(_ exercise: Exercise) -> Double {
        switch exercise.loadBasis {
        case .perHand: 32
        case .bodyweightPlus: 100
        case .assisted: 90
        default: exercise.isCompound ? 110 : 60
        }
    }
}
#endif
