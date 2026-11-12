import Foundation
import LiftEngine

#if os(iOS)
import CoreMotion
#endif

/// The motion sensors Floor mode reads: which way is down and the push the person gives the phone,
/// ten times a second, while the session is on an iPhone's screen. Device motion needs no permission
/// (no usage description: that's for the activity and step counts). Nothing anywhere else: Floor
/// mode is the iPhone's (`Platform.hasFloorMode`).
@MainActor
final class FloorMotion {
    #if os(iOS)
    private let manager = CMMotionManager()
    #endif
    /// The loop that reads the sensors; stopped by `stop()`, which the owner calls when it goes.
    private var reading: Task<Void, Never>?

    /// The clock the readings are on, for a touch to be compared with them: seconds since the
    /// device started.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Starts reading, handing each reading to `take`. Nothing happens where there are no sensors.
    init(take: @escaping @MainActor (FloorDetector.Reading) -> Void) {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        // No handler: the latest reading is taken from the manager on each pass of the loop, on the
        // main actor where the detector lives.
        manager.startDeviceMotionUpdates()
        reading = Task { [weak self] in
            while !Task.isCancelled {
                guard let manager = self?.manager else { return }
                if let motion = manager.deviceMotion {
                    take(
                        FloorDetector.Reading(
                            time: motion.timestamp,
                            gravity: FloorDetector.Vector(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                            acceleration: FloorDetector.Vector(
                                x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)))
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }

    func stop() {
        reading?.cancel()
        reading = nil
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
    }
}
