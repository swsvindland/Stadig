import Foundation
import LiftEngine
import Observation
import SystemCore

/// Floor mode on the iPhone: the session set down on the gym floor or a bench, where the whole
/// screen is the button. It comes on when the phone has lain flat and still for two seconds (unless
/// that's switched off in Settings) or from the session's menu, and goes off when the phone is picked
/// up (`FloorDetector`). The screen stays awake while it's on. The session screen owns one, and
/// stops it when it goes.
@MainActor @Observable
final class FloorMode {
    /// Settings' switch for coming on by itself. Kept on this device rather than synced with the
    /// training settings: it's about how this phone behaves when it's put down.
    static let automaticKey = "floorMode.automatic"

    /// Whether the phone is set down. The session shows the floor when there's a set or a rest for it.
    private(set) var isOn = false
    /// Moves with each set logged from the floor, for its haptic.
    private(set) var logs = 0
    /// Moves with each rest skipped or changed and each rep counted from the floor, for its haptic.
    private(set) var nudges = 0

    @ObservationIgnored private var detector = FloorDetector()
    @ObservationIgnored private var motion: FloorMotion?
    @ObservationIgnored private var running = false
    /// `-floorMode`: on whatever the sensors say, for the simulator, which has none.
    @ObservationIgnored private let forced: Bool

    init(launch: LaunchOptions = .current) {
        #if DEBUG
        forced = launch.has("-floorMode")
        #else
        forced = false
        #endif
    }

    /// The session is on screen: read the sensors, where there's Floor mode.
    func start(automatic: Bool) {
        guard Platform.hasFloorMode else { return }
        detector.automatic = automatic
        running = true
        if forced { show(true) }
        listen()
    }

    /// The session's screen has gone, or the app has: stop reading and let the screen sleep.
    func stop() {
        running = false
        detector.turnOff()
        show(false)
        listen()
    }

    /// Settings' switch changed while the session is up.
    func setAutomatic(_ automatic: Bool) {
        detector.automatic = automatic
        listen()
    }

    /// From the session's menu: on now, at whatever angle; off again when the phone is picked up.
    func turnOn() {
        guard Platform.hasFloorMode else { return }
        detector.turnOn()
        show(true)
        listen()
    }

    /// A touch on the session's normal screen: someone is using it, so it isn't set down yet.
    func touched() {
        detector.touched(at: FloorMotion.now)
    }

    func logged() { logs += 1 }
    func nudged() { nudges += 1 }

    private func take(_ reading: FloorDetector.Reading) {
        show(detector.take(reading) == .floor)
        listen()
    }

    private func show(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        Platform.keepScreenAwake(on)
    }

    /// Reads the sensors only while something can come of it: it may come on by itself, or it's on
    /// and picking the phone up turns it off.
    private func listen() {
        let needed = running && !forced && (detector.automatic || isOn)
        if needed, motion == nil {
            motion = FloorMotion { [weak self] reading in self?.take(reading) }
        } else if !needed, let motion {
            motion.stop()
            self.motion = nil
        }
    }
}

/// What the floor shows: the rest, or the set in front of you with what its gestures do.
enum FloorContent: Hashable {
    case rest
    case set(item: Int, set: Int, kind: FloorSet)
}

extension AppModel {
    /// What Floor mode shows now, or nil where the session keeps its normal screen: every set done,
    /// or a set the gestures don't fit (a conditioning piece, the sauna).
    var floorContent: FloorContent? {
        guard let live else { return nil }
        if activeRest != nil { return .rest }
        guard let (item, set) = live.current, let kind = FloorSet(current: live, catalog: catalog) else { return nil }
        return .set(item: item, set: set, kind: kind)
    }
}
