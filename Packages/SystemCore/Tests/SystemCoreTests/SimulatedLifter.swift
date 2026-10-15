import Foundation
@testable import SystemCore

/// A minimal exercise for tests.
struct TestExercise: ExerciseTraits {
    var id: String
    var name: String
    var pattern: MovementPattern
    var equipment: Equipment
    var muscles: [MuscleShare]
    var joints: [JointLoad]
    var fatigue: FatigueProfile
    var safetyTier: SafetyTier
    var strength: StrengthMapping?
    var loadBasis: LoadBasis = .external

    static let chestPress = TestExercise(
        id: "machine-chest-press", name: "Machine Chest Press", pattern: .horizontalPress, equipment: .machine,
        muscles: [MuscleShare(.chest, 1), MuscleShare(.triceps, 0.5)], joints: [JointLoad(.shoulder, .moderate), JointLoad(.elbow, .low)],
        fatigue: FatigueProfile(systemic: 0.35, local: 0.4, stimulus: 0.8, failureMultiplier: 1.2), safetyTier: .safeToFail)

    static let bench = TestExercise(
        id: "barbell-bench-press", name: "Barbell Bench Press", pattern: .horizontalPress, equipment: .barbell,
        muscles: [MuscleShare(.chest, 1), MuscleShare(.triceps, 0.5), MuscleShare(.frontDelts, 0.5)],
        joints: [JointLoad(.shoulder, .high), JointLoad(.elbow, .moderate), JointLoad(.wrist, .moderate)],
        fatigue: FatigueProfile(systemic: 0.55, local: 0.45, stimulus: 0.85, failureMultiplier: 1.5), safetyTier: .failWithSetup,
        strength: StrengthMapping(.horizontalPress))

    static let deadlift = TestExercise(
        id: "conventional-deadlift", name: "Deadlift", pattern: .hinge, equipment: .barbell,
        muscles: [MuscleShare(.hamstrings, 1), MuscleShare(.glutes, 1), MuscleShare(.lowerBack, 1)],
        joints: [JointLoad(.lowerBack, .high), JointLoad(.hip, .high), JointLoad(.knee, .moderate)],
        fatigue: FatigueProfile(systemic: 1, local: 0.5, stimulus: 0.8, failureMultiplier: 2), safetyTier: .failWithSetup,
        strength: StrengthMapping(.floorPull))

    static let legExtension = TestExercise(
        id: "leg-extension", name: "Leg Extension", pattern: .legExtension, equipment: .machine,
        muscles: [MuscleShare(.quads, 1)], joints: [JointLoad(.knee, .high)],
        fatigue: FatigueProfile(systemic: 0.15, local: 0.4, stimulus: 0.75, failureMultiplier: 1.1), safetyTier: .safeToFail)

    static let pullUp = TestExercise(
        id: "pull-up", name: "Pull-up", pattern: .verticalPull, equipment: .bodyweight,
        muscles: [MuscleShare(.lats, 1), MuscleShare(.biceps, 0.5)], joints: [JointLoad(.shoulder, .moderate), JointLoad(.elbow, .moderate)],
        fatigue: FatigueProfile(systemic: 0.45, local: 0.4, stimulus: 0.85), safetyTier: .safeToFail,
        strength: StrengthMapping(.verticalPull), loadBasis: .bodyweightPlus)
}

/// A person with a true strength that grows (or doesn't) and a characteristic way of misjudging
/// effort. Their performance follows Epley exactly, with a little fatigue set to set.
struct SimulatedLifter {
    var name: String
    var experience: TrainingExperience
    /// True estimated 1RM per exercise at week 0, kg.
    var start: [String: Double]
    /// Weekly fractional growth.
    var growth: Double
    /// Reps of reserve they fail to perceive: +4 is a sandbagger, −2 is overconfident.
    var perceptionBias: Double
    /// Reps in reserve they leave when picking a weight to find "a weight for 10".
    var guessReserve: Double

    func trueE1RM(_ exercise: String, week: Double) -> Double {
        (start[exercise] ?? 50) * pow(1 + growth, week)
    }

    /// Does a set as prescribed and rates it the way this person would.
    func perform(_ prescription: SetPrescription, exercise: some ExerciseTraits, week: Double, setIndex: Int,
                 date: Date, increments: any LoadIncrements) -> LoggedSet {
        let fresh = trueE1RM(exercise.id, week: week)
        let e1rm = fresh * (1 - 0.02 * Double(setIndex))
        let load = prescription.loadKg ?? increments.round(OneRepMax.load(e1rm: fresh, reps: prescription.targetReps, rir: guessReserve), down: true)
        let capacity = Int(OneRepMax.repsToFailure(e1rm: e1rm, at: load).rounded(.down))
        if prescription.kind == .repOut {
            return LoggedSet(exerciseID: exercise.id, date: date, kind: .repOut, loadKg: load, reps: capacity, targetReps: prescription.targetReps)
        }
        let target = prescription.targetReps
        if capacity < target {
            return LoggedSet(exerciseID: exercise.id, date: date, kind: prescription.kind, loadKg: load, reps: max(0, capacity),
                             targetReps: target, rating: .red)
        }
        let perceived = Double(capacity - target) - perceptionBias
        let rating: SetRating = perceived >= 3 ? .green : .orange
        return LoggedSet(exerciseID: exercise.id, date: date, kind: prescription.kind, loadKg: load, reps: target, targetReps: target,
                         rating: rating)
    }

    static let honestNovice = SimulatedLifter(name: "Honest novice", experience: .novice,
                                              start: ["machine-chest-press": 70, "barbell-bench-press": 60, "leg-extension": 60],
                                              growth: 0.02, perceptionBias: 0, guessReserve: 4)
    static let sandbagger = SimulatedLifter(name: "Sandbagger", experience: .novice,
                                            start: ["machine-chest-press": 90, "barbell-bench-press": 80, "leg-extension": 80],
                                            growth: 0.01, perceptionBias: 5, guessReserve: 9)
    static let overconfident = SimulatedLifter(name: "Overconfident veteran", experience: .experienced,
                                               start: ["machine-chest-press": 120, "barbell-bench-press": 110, "leg-extension": 90],
                                               growth: 0.005, perceptionBias: -2.5, guessReserve: 1)
    static let plateaued = SimulatedLifter(name: "Plateaued veteran", experience: .experienced,
                                           start: ["machine-chest-press": 120, "barbell-bench-press": 110, "leg-extension": 90],
                                           growth: 0, perceptionBias: 0, guessReserve: 2)
}

/// Runs a lifter through weeks of sessions using the core's real progression, set-to-set
/// autoregulation and trust calibration.
struct TrainingSimulation {
    struct Slot {
        var exercise: TestExercise
        var increments: any LoadIncrements
        var sets: Int
        var repRange: RepRange
    }

    var lifter: SimulatedLifter
    var slots: [Slot]
    var sessionsPerWeek = 3
    var loadingWeeks = 5
    var assessmentWeeks = 4
    var phase = NutritionPhase.assumedMaintenance.effects
    var startDate = Day(year: 2026, month: 1, day: 5)

    private(set) var trust: TrustState
    private(set) var history: [String: [LoggedSet]] = [:]
    private(set) var prescriptions: [String: [ExercisePrescription]] = [:]
    private(set) var adjustments: [AdjustmentKind] = []

    init(lifter: SimulatedLifter, slots: [Slot]) {
        self.lifter = lifter
        self.slots = slots
        trust = TrustState(experience: lifter.experience)
    }

    mutating func run(weeks: Int, from first: Int = 0) {
        for week in first..<(first + weeks) {
            let blockWeek = week % (loadingWeeks + 1)
            let deload = blockWeek == loadingWeeks
            let assessment = week < assessmentWeeks
            for session in 0..<sessionsPerWeek {
                let day = startDate.adding(weeks: week).adding(days: session * 2)
                let date = day.date().addingTimeInterval(18 * 3600)
                let weekFraction = Double(week) + Double(session) / Double(sessionsPerWeek)
                var repOutsLeft = FailurePolicy.capPerSession(experience: lifter.experience, assessment: assessment)
                for slot in slots {
                    let checkIn = deload && session == sessionsPerWeek - 1
                    let wantsRepOut = FailurePolicy.wantsRepOut(trust: trust, assessment: assessment, checkIn: checkIn, sessionIndexInWeek: session)
                        && FailurePolicy.allowsRepOut(slot.exercise, trust: trust, experience: lifter.experience, hasSafeties: true)
                        && repOutsLeft > 0 && (!deload || checkIn)
                    if wantsRepOut { repOutsLeft -= 1 }
                    let target = SlotTarget(sets: slot.sets, repRange: slot.repRange,
                                            targetRIR: Progression.targetRIR(week: min(blockWeek, loadingWeeks - 1), of: loadingWeeks),
                                            deload: deload, repOut: wantsRepOut)
                    let context = ProgressionContext(exercise: slot.exercise, increments: slot.increments, trust: trust, phase: phase,
                                                     bodyweightKg: 80, history: history[slot.exercise.id] ?? [])
                    let prescription = Progression.prescribe(target, context)
                    prescriptions[slot.exercise.id, default: []].append(prescription)
                    var plan = prescription.sets
                    var done: [LoggedSet] = []
                    var verified = false
                    for index in plan.indices {
                        let set = lifter.perform(plan[index], exercise: slot.exercise, week: weekFraction, setIndex: index,
                                                 date: date.addingTimeInterval(Double(index) * 180), increments: slot.increments)
                        done.append(set)
                        guard index + 1 < plan.count else { break }
                        let adjustment = Autoregulation.next(after: set, planned: plan[index + 1], context: Autoregulation.Context(
                            exercise: slot.exercise, increments: slot.increments, trust: trust, repRange: slot.repRange, verifiedAlready: verified,
                            hasSafeties: true))
                        adjustments.append(adjustment.kind)
                        if adjustment.kind == .verify { verified = true }
                        for later in (index + 1)..<plan.count {
                            let kind = plan[later].kind
                            plan[later] = adjustment.next
                            if kind == .repOut { plan[later].kind = .repOut }
                        }
                    }
                    history[slot.exercise.id, default: []].append(contentsOf: done)
                    trust.record(Calibration.observations(sets: done, exercise: slot.exercise))
                }
            }
        }
    }

    func estimate(_ exercise: TestExercise) -> Double? {
        StrengthEstimator.current(history[exercise.id] ?? [], basis: exercise.loadBasis, trust: trust)
    }

    func lastWorkingLoad(_ exercise: TestExercise) -> Double? {
        history[exercise.id]?.last { $0.kind == .working || $0.kind == .repOut }?.loadKg
    }

    func firstWorkingLoad(_ exercise: TestExercise) -> Double? {
        history[exercise.id]?.first { $0.kind.countsAsWork }?.loadKg
    }
}
