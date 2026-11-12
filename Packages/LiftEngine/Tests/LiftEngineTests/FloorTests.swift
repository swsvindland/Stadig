import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// Floor mode: when a phone set down on the gym floor becomes one big button and when picking it up
/// gives the normal screen back, from made-up sensor readings ten times a second; and what the three
/// gestures do to each kind of set.
@Suite("Floor mode")
struct FloorTests {
    typealias Vector = FloorDetector.Vector

    static let still = Vector(x: 0, y: 0, z: 0)
    static let flat = tilted(0)

    /// Gravity with the phone tilted toward the person by `degrees` from lying face up.
    static func tilted(_ degrees: Double) -> Vector {
        let radians = degrees * .pi / 180
        return Vector(x: 0, y: -sin(radians), z: -cos(radians))
    }

    /// A push of `g` along the phone's z axis: lifting it straight up, or a knock through the floor.
    static func push(_ g: Double) -> Vector { Vector(x: 0, y: 0, z: g) }

    /// Feeds readings from `from` through `through` tenths of a second and returns the time (in
    /// seconds) the state first changed, or nil when it never did.
    @discardableResult
    func feed(
        _ detector: inout FloorDetector, from: Int, through: Int, gravity: Vector = flat, acceleration: Vector = still
    ) -> Double? {
        let before = detector.state
        for tenth in from...through {
            let time = Double(tenth) / 10
            if detector.take(FloorDetector.Reading(time: time, gravity: gravity, acceleration: acceleration)) != before { return time }
        }
        return nil
    }

    @Test("Lying flat and still for two seconds turns it on, not before")
    func setDown() {
        var detector = FloorDetector()
        #expect(feed(&detector, from: 0, through: 19) == nil)
        #expect(detector.state == .held)
        #expect(feed(&detector, from: 20, through: 20) == 2)
        #expect(detector.state == .floor)

        // Within 20° of level counts as flat: a gym floor isn't a spirit level.
        var slightly = FloorDetector()
        #expect(feed(&slightly, from: 0, through: 30, gravity: Self.tilted(15)) == 2)
    }

    @Test("Face down, propped up or on a shaking bench, it stays off")
    func notSetDown() {
        var faceDown = FloorDetector()
        feed(&faceDown, from: 0, through: 100, gravity: Vector(x: 0, y: 0, z: 1))
        #expect(faceDown.state == .held)

        var propped = FloorDetector()
        feed(&propped, from: 0, through: 100, gravity: Self.tilted(30))
        #expect(propped.state == .held)

        var shaking = FloorDetector()
        feed(&shaking, from: 0, through: 100, acceleration: Self.push(0.08))
        #expect(shaking.state == .held)

        // On its side against a wall.
        var standing = FloorDetector()
        feed(&standing, from: 0, through: 100, gravity: Vector(x: 0, y: -1, z: 0))
        #expect(standing.state == .held)
    }

    @Test("A knock while it settles starts the two seconds again")
    func knockWhileSettling() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 9)
        feed(&detector, from: 10, through: 10, acceleration: Self.push(0.6))
        #expect(feed(&detector, from: 11, through: 40) == 3.1)
    }

    @Test("Picked up when turned or lifted for a quarter of a second; a tap on the glass or a bar dropped beside it isn't")
    func pickUp() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 20)
        #expect(detector.state == .floor)

        // A tap: one sharp reading.
        feed(&detector, from: 21, through: 29)
        feed(&detector, from: 30, through: 30, acceleration: Self.push(0.4))
        // A bar dropped on the platform beside it: a tenth of a second of shaking.
        feed(&detector, from: 31, through: 39)
        feed(&detector, from: 40, through: 41, acceleration: Self.push(0.5))
        #expect(feed(&detector, from: 42, through: 69) == nil)
        #expect(detector.state == .floor)

        // Turned toward a face: 40° from how it lay, for a quarter of a second.
        #expect(feed(&detector, from: 70, through: 75, gravity: Self.tilted(40)) == 7.3)
        #expect(detector.state == .held)

        // Lifted straight up without turning it, as off a bench.
        var lifted = FloorDetector()
        feed(&lifted, from: 0, through: 29)
        #expect(feed(&lifted, from: 30, through: 35, acceleration: Self.push(0.3)) == 3.3)
    }

    @Test("Between flat and turned it keeps whatever it was, so it doesn't flicker")
    func hysteresis() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 20)
        // 25° is too far to come on but not far enough to go off.
        #expect(feed(&detector, from: 21, through: 120, gravity: Self.tilted(25)) == nil)
        #expect(detector.state == .floor)

        feed(&detector, from: 121, through: 125, gravity: Self.tilted(60))
        #expect(detector.state == .held)
        #expect(feed(&detector, from: 126, through: 226, gravity: Self.tilted(25)) == nil)
        #expect(detector.state == .held)

        // Wobbling either side of the 20° line never lies flat for two seconds together.
        for tenth in 227...327 {
            detector.take(
                FloorDetector.Reading(time: Double(tenth) / 10, gravity: Self.tilted(tenth.isMultiple(of: 2) ? 19 : 21), acceleration: Self.still))
        }
        #expect(detector.state == .held)
    }

    @Test("A gap in the readings starts the clocks again")
    func gap() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 15)
        // Two seconds of nothing: it isn't known to have lain still through them.
        #expect(feed(&detector, from: 36, through: 56) == 5.6)
        detector.take(FloorDetector.Reading(time: 6, gravity: Self.tilted(40), acceleration: Self.still))
        #expect(feed(&detector, from: 70, through: 71, gravity: Self.tilted(40)) == nil)
    }

    @Test("Touching the normal screen keeps it off for four seconds, even lying flat")
    func touchHoldsItOff() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 10)
        detector.touched(at: 1)
        #expect(feed(&detector, from: 11, through: 49) == nil)
        #expect(feed(&detector, from: 50, through: 50) == 5)
    }

    @Test("Turned off in Settings it never comes on by itself, but the menu turns it on, and picking it up off, at any angle")
    func manual() {
        var detector = FloorDetector(automatic: false)
        feed(&detector, from: 0, through: 100)
        #expect(detector.state == .held)

        detector.turnOn()
        #expect(detector.state == .floor)
        // Carried to the bench: moving and turning, but it hasn't been set down yet.
        feed(&detector, from: 101, through: 110, gravity: Self.tilted(70), acceleration: Self.push(0.4))
        #expect(detector.state == .floor)
        // Propped at 50° on a bag, still for a second: that's where it lies.
        #expect(feed(&detector, from: 111, through: 125, gravity: Self.tilted(50)) == nil)
        // Nudged 10° by a tap: still where it was.
        #expect(feed(&detector, from: 126, through: 140, gravity: Self.tilted(60)) == nil)
        // Picked up: turned 40° from how it lay.
        #expect(feed(&detector, from: 141, through: 150, gravity: Self.tilted(90)) == 14.4)
        #expect(detector.state == .held)
        // And with the setting off, lying flat doesn't bring it back.
        feed(&detector, from: 151, through: 250)
        #expect(detector.state == .held)
    }

    @Test("Off when the session's screen goes, and back on once it has settled again")
    func turnOff() {
        var detector = FloorDetector()
        feed(&detector, from: 0, through: 20)
        detector.turnOff()
        #expect(detector.state == .held)
        #expect(feed(&detector, from: 30, through: 60) == 5)
    }

    // MARK: The gestures

    static let catalog = Fixture.catalog

    func item(_ id: String, role: SlotRole, block: SessionBlockKind = .main, _ sets: [SetPrescription]) -> LiveItem {
        LiveItem(
            plan: PlannedItem(
                slotID: nil, block: block, exerciseID: id, role: role, sets: sets, repRange: RepRange(5, 8),
                rest: RestPlan(target: 150, minimum: 90, heartRateGuided: false)))
    }

    func floor(_ item: LiveItem, _ set: Int = 0) -> FloorSet? {
        FloorSet(item: item, set: item.sets[set], exercise: Self.catalog.resolve(item.exerciseID))
    }

    @Test("Each kind of set gets the dock's buttons as gestures, and those that don't fit keep the normal screen")
    func gestures() throws {
        let bench = item(
            "barbell-bench-press", role: .main,
            [
                SetPrescription(kind: .warmup, loadKg: 40, targetReps: 5, targetRIR: 5),
                SetPrescription(kind: .working, loadKg: 70, targetReps: 7, targetRIR: 2),
                SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: 7, targetRIR: 2),
                SetPrescription(kind: .deload, loadKg: 60, targetReps: 7, targetRIR: 4),
                SetPrescription(kind: .repOut, loadKg: 70, targetReps: 7, targetRIR: 0),
            ])
        #expect(floor(bench, 0) == .warmup)
        #expect(floor(bench, 1) == .rated)
        #expect(floor(bench, 2) == .rated)
        #expect(floor(bench, 3) == .rated)
        #expect(floor(bench, 4) == .repOut)
        #expect(floor(bench, 1)?.swipes == true && floor(bench, 4)?.swipes == true && floor(bench, 0)?.swipes == false)

        // A plank is held for time, even as an accessory: tap to start, tap when done.
        let plank = item("plank", role: .accessory, [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 2, seconds: 45)])
        #expect(Self.catalog.resolve("plank").timed)
        #expect(floor(plank) == .timed(seconds: 45))

        // A drill in the warm-up: reps, nothing to rate.
        let drill = item("cat-cow", role: .mobility, block: .warmup, [SetPrescription(kind: .working, loadKg: nil, targetReps: 8, targetRIR: 3)])
        #expect(floor(drill) == .done)

        var bike = item(
            "easy-bike-warmup", role: .conditioning, block: .conditioning, [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 3)]
        )
        bike.plan.conditioning = ConditioningPlan(minutes: 20, zones: 2...2, style: .steady)
        #expect(floor(bike) == nil)

        let sauna = item("sauna", role: .recovery, block: .recovery, [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 3)])
        #expect(floor(sauna) == nil)
    }

    @Test("The set in front of you in a session, alternating through a superset")
    func currentSet() throws {
        let set = SetPrescription(kind: .working, loadKg: 30, targetReps: 10, targetRIR: 2)
        var row = item("barbell-bench-press", role: .accessory, block: .accessory, [set, set])
        var curl = item(
            "plank", role: .accessory, block: .accessory, [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 2, seconds: 30)])
        row.plan.supersetGroup = 1
        curl.plan.supersetGroup = 1
        let plan = SessionPlan(
            day: Fixture.start, title: "Upper A", mesocycleID: nil, dayID: nil, week: nil, deload: false, checkIn: false,
            assessment: false, minimumEffectiveDose: false, items: [row.plan, curl.plan], notes: [], quests: [])
        var live = LiveSession(plan: plan, device: "iPhone")
        #expect(FloorSet(current: live, catalog: Self.catalog) == .rated)
        live.items[0].sets[0].logged = LoggedSet(exerciseID: row.exerciseID, loadKg: 30, reps: 10, rating: .orange)
        #expect(FloorSet(current: live, catalog: Self.catalog) == .timed(seconds: 30))
        live.items[1].skipped = true
        live.items[0].skipped = true
        #expect(FloorSet(current: live, catalog: Self.catalog) == nil)
    }
}
