import Foundation

/// When Floor mode comes on and goes off: the phone set down flat and face up a metre or two away,
/// or picked up again, read from the motion sensors. Pure, so it's tested with made-up readings;
/// the app feeds it Core Motion's device motion about ten times a second.
///
/// Coming on is slow and strict, going off quick and loose, so it doesn't flicker: on after two
/// seconds within 20° of flat and still, with nothing touched for four; off after a quarter of a
/// second turned more than 35° from how it lay, or moving.
public struct FloorDetector: Sendable {
    /// A direction or an acceleration in g, in the phone's frame: x across the screen, y up it and z
    /// out of it, so a phone lying face up feels gravity as (0, 0, −1).
    public struct Vector: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        public var length: Double { (x * x + y * y + z * z).squareRoot() }

        func dot(_ other: Vector) -> Double { x * other.x + y * other.y + z * other.z }

        /// The same direction, one long; nil for no direction at all.
        var unit: Vector? {
            let length = length
            guard length > 0.0001 else { return nil }
            return Vector(x: x / length, y: y / length, z: z / length)
        }
    }

    /// One reading of the sensors.
    public struct Reading: Sendable, Hashable {
        /// Seconds, on any clock that only goes forward.
        public var time: TimeInterval
        /// Which way is down, as the sensors fuse it: steady through a knock, unlike raw acceleration.
        public var gravity: Vector
        /// The acceleration the person gives the phone, gravity taken out.
        public var acceleration: Vector

        public init(time: TimeInterval, gravity: Vector, acceleration: Vector) {
            self.time = time
            self.gravity = gravity
            self.acceleration = acceleration
        }
    }

    public struct Thresholds: Sendable, Hashable {
        /// Flat enough to be set down: gravity's share along −z. 0.94 is within 20° of level.
        public var flat = 0.94
        /// Turned from how it lay when gravity's share along that direction falls under this: 0.82
        /// is 35°. The gap from `flat` is the hysteresis.
        public var turned = 0.82
        /// Lying still: the person's acceleration under this, in g. A phone on a bench reads about 0.01.
        public var still = 0.05
        /// Moving: over this, in g. A hand lifting a phone gives 0.2 to 0.5.
        public var moving = 0.2
        /// How long it lies flat and still before Floor mode comes on.
        public var settle: TimeInterval = 2
        /// How long turned or moving lasts before it counts as picked up, so a tap on the glass or a
        /// bar dropped beside it, over in a moment, doesn't.
        public var pickUp: TimeInterval = 0.25
        /// After a touch on the session's normal screen, how long before it can come on: a phone
        /// lying on a bench while the weight is changed on it hasn't been set down.
        public var afterTouch: TimeInterval = 4
        /// Turned on from the session's menu: how long it lies still, at whatever angle, before
        /// picking it up can turn it off.
        public var rest: TimeInterval = 1

        public init() {}
    }

    public enum State: Sendable, Hashable {
        /// In the hand: the session's normal screen.
        case held
        /// Set down: the whole screen is the button.
        case floor
    }

    public var thresholds: Thresholds
    /// Whether lying flat turns it on by itself (a setting). Turned on from the menu, it still goes
    /// off when picked up.
    public var automatic: Bool
    public private(set) var state: State = .held

    /// Since when it has lain flat and still (held), or still at any angle (turned on from the
    /// menu and not yet settled).
    private var quietSince: TimeInterval?
    private var lastTouch: TimeInterval?
    /// Which way was down when it settled: picking it up is measured from here, so a phone turned
    /// on from the menu while propped on a bag goes off when it's turned from that.
    private var resting: Vector?
    /// Since when it has been turned or moving.
    private var disturbedSince: TimeInterval?
    private var lastReading: TimeInterval?

    /// The longest pause between readings that still counts as one stretch.
    static let gap: TimeInterval = 0.5

    /// Whether `start` to `end` is at least `duration`, with a millisecond's slack for times in
    /// floating point (2 s after 3.6 is 5.599999…).
    static func lasted(_ start: TimeInterval, _ end: TimeInterval, _ duration: TimeInterval) -> Bool {
        end - start >= duration - 0.001
    }

    public init(thresholds: Thresholds = Thresholds(), automatic: Bool = true) {
        self.thresholds = thresholds
        self.automatic = automatic
    }

    /// Takes a reading and returns the state after it.
    @discardableResult
    public mutating func take(_ reading: Reading) -> State {
        // A gap in the readings (the app away for a moment) starts both clocks again: what the
        // phone did in it isn't known.
        if let lastReading, reading.time - lastReading > Self.gap {
            quietSince = nil
            disturbedSince = nil
        }
        lastReading = reading.time
        let still = reading.acceleration.length < thresholds.still
        guard let down = reading.gravity.unit else { return state }
        switch state {
        case .held:
            guard automatic, still, -down.z >= thresholds.flat else {
                quietSince = nil
                return state
            }
            let since = quietSince ?? reading.time
            quietSince = since
            let untouched = lastTouch.map { Self.lasted($0, reading.time, thresholds.afterTouch) } ?? true
            if Self.lasted(since, reading.time, thresholds.settle), untouched { setDown(resting: down) }
        case .floor:
            guard let resting else {
                // Turned on from the menu and still on its way down: it waits to lie still, at
                // whatever angle, before anything counts as picking it up.
                guard still else {
                    quietSince = nil
                    return state
                }
                let since = quietSince ?? reading.time
                quietSince = since
                if Self.lasted(since, reading.time, thresholds.rest) { self.resting = down }
                return state
            }
            let turned = down.dot(resting) < thresholds.turned
            let moving = reading.acceleration.length > thresholds.moving
            guard turned || moving else {
                disturbedSince = nil
                return state
            }
            let since = disturbedSince ?? reading.time
            disturbedSince = since
            if Self.lasted(since, reading.time, thresholds.pickUp) { pickedUp() }
        }
        return state
    }

    /// Floor mode from the session's menu, at once and at whatever angle (propped on a bag, leaning on
    /// a bottle). It goes off when the phone is picked up after lying still a moment.
    public mutating func turnOn() {
        state = .floor
        resting = nil
        quietSince = nil
        disturbedSince = nil
    }

    /// Off, as when the session's screen goes away: a phone still lying flat comes back on once it has
    /// settled again.
    public mutating func turnOff() {
        pickedUp()
    }

    /// A touch on the session's normal screen: someone is using it, so it isn't set down yet.
    public mutating func touched(at time: TimeInterval) {
        lastTouch = time
    }

    private mutating func setDown(resting down: Vector) {
        state = .floor
        resting = down
        quietSince = nil
        disturbedSince = nil
    }

    private mutating func pickedUp() {
        state = .held
        resting = nil
        quietSince = nil
        disturbedSince = nil
    }
}
