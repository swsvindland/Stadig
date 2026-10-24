#if DEBUG
import Foundation
import ExerciseLibrary
import LiftEngine
import SystemCore

/// Debug launch arguments for trying the app without a phone:
/// `-sampleContext` seeds a small context; `-sampleScreen set|rating|rest|timed|conditioning|finish`
/// also starts a fresh sample session (without HealthKit) and moves it to that screen, and
/// `-sampleScreen home` drops any session to show the home screen. `-sampleScreen phone` shows the
/// sample session as if the iPhone ran it and this Watch were logging into it, and `phone-set`,
/// `phone-rating`, `phone-finish` and so on move it to that screen; `phone-saving` is the wait for the
/// phone after Save. (No phone answers, so what's logged stays pending.)
extension WatchModel {
    func applyLaunchArguments() {
        let launch = LaunchOptions.current
        guard var screen = launch.value(after: "-sampleScreen") ?? (launch.has("-sampleContext") ? "" : nil) else { return }
        receive(SampleContext.make())
        guard !screen.isEmpty, let plan = context?.plan else { return }
        healthEnabled = false
        if session != nil { discard() }
        guard screen != "home" else { return }
        if screen.hasPrefix("phone") {
            followSample(plan, context: SampleContext.make())
            screen = String(screen.dropFirst("phone".count).drop { $0 == "-" })
        } else {
            start(plan)
        }
        switch screen {
        case "set", "rating", "rest":
            skip(item: 0)
            log(item: 1, set: 0, reps: 10, loadKg: nil, rating: nil)
            log(item: 1, set: 1, reps: 5, loadKg: nil, rating: nil)
            endRest()
            if screen == "rating" {
                debugRoute = "rating"
            } else {
                // An easy first set, so the next one shows the adjustment.
                log(item: 1, set: 2, reps: 8, loadKg: nil, rating: .green)
                if screen == "set" { endRest() }
            }
        case "conditioning":
            for item in 0..<4 { skip(item: item) }
            startTimer(item: 4, set: 0)
        case "finish", "saving":
            skip(item: 0)
            log(item: 1, set: 0, reps: 10, loadKg: nil, rating: nil)
            endRest()
            wrapUp()
            if screen == "saving" { finish(feedback: nil) }
        default:
            break
        }
    }
}

/// A context like the phone's: an upper-body day with a drill, a main lift with ramp-up sets,
/// a finding-weight accessory, a bodyweight lift with a rep-out, intervals and a stretch.
enum SampleContext {
    static func make() -> PhoneContext {
        let gym = Gym.preset(.fullGym, unit: .kg)
        let heavy = Rest.plan(role: .heavyCompound, reps: 8, defaultSeconds: 180, enduranceScore: nil, hrGuidance: true)
        let accessory = Rest.plan(role: .accessory, reps: 12, defaultSeconds: 75, enduranceScore: nil, hrGuidance: true)
        let compound = Rest.plan(role: .compound, reps: 8, defaultSeconds: 120, enduranceScore: nil, hrGuidance: true)
        let work = { (load: Double?, reps: Int) in SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: 2) }
        let intervals = ConditioningPlan(minutes: 10, zones: 4...5, style: .intervals, workSeconds: 30, restSeconds: 30)
        let items = [
            PlannedItem(
                slotID: nil, block: .limiter, exerciseID: "couch-stretch", role: .mobility,
                sets: Array(repeating: SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 5, seconds: 45), count: 2),
                repRange: RepRange(1, 1), rest: RestPlan(target: 15, minimum: 0, heartRateGuided: false), seconds: 45),
            PlannedItem(
                slotID: nil, block: .main, exerciseID: "barbell-bench-press", role: .main,
                sets: [
                    SetPrescription(kind: .warmup, loadKg: 20, targetReps: 10, targetRIR: 5),
                    SetPrescription(kind: .warmup, loadKg: 50, targetReps: 5, targetRIR: 5),
                    work(80, 8), work(80, 8), work(80, 8),
                ],
                repRange: RepRange(6, 10), rest: heavy, restFiller: "hip-90-90-switches",
                note: "Up 2.5 kg: every set last time was just right."),
            PlannedItem(
                slotID: nil, block: .accessory, exerciseID: "db-lateral-raise", role: .accessory,
                sets: Array(repeating: SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: 12, targetRIR: 2), count: 3),
                repRange: RepRange(10, 15), rest: accessory,
                note: "Pick a weight you think you can do for 12, then rate it. The next set adjusts."),
            PlannedItem(
                slotID: nil, block: .accessory, exerciseID: "pull-up", role: .accessory,
                sets: [work(0, 8), work(0, 8), SetPrescription(kind: .repOut, loadKg: 0, targetReps: 8, targetRIR: 0)],
                repRange: RepRange(6, 10), rest: compound),
            PlannedItem(
                slotID: nil, block: .conditioning, exerciseID: "bike-30-30-intervals", role: .conditioning,
                sets: [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 3, seconds: 600)],
                repRange: RepRange(1, 1), rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false), seconds: 600,
                conditioning: intervals),
            PlannedItem(
                slotID: nil, block: .cooldown, exerciseID: "doorway-chest-stretch", role: .stretch,
                sets: [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 5, seconds: 30)],
                repRange: RepRange(1, 1), rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false), seconds: 30),
        ]
        let plan = SessionPlan(
            day: .today, title: "Upper A", mesocycleID: nil, dayID: nil, week: 1, deload: false, checkIn: false,
            assessment: false, minimumEffectiveDose: false, items: items,
            notes: ["Week 2: leave about two reps in the tank on every set."], quests: [])
        let lastWeek = Date().addingTimeInterval(-7 * 86400)
        let bench = (0..<3).map { _ in
            LoggedSet(exerciseID: "barbell-bench-press", date: lastWeek, kind: .working, loadKg: 77.5, reps: 8, targetReps: 8, rating: .orange)
        }
        return PhoneContext(
            plan: plan, upNext: nil, gym: gym, trust: TrustState(prior: 0.6), phase: NutritionPhase.assumedMaintenance.effects,
            bodyweightKg: 80, history: ["barbell-bench-press": bench], enduranceScore: 55, heartRateGuidedRest: true,
            zones: .estimated(age: 35, resting: 58), units: UnitPreference(weight: .kg, length: .cm))
    }
}
#endif
