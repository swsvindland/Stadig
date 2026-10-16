import SwiftUI
import HealthKit
import WatchKit

/// The phone starting a session asks this Watch for a workout, to measure heart rate.
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchModel.shared.startCompanion()
    }
}

@main
struct LiftTrackWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchDelegate
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if DEBUG
                // `-largeText` previews an accessibility text size (simctl can't set one on watchOS).
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("-largeText") { size = .accessibility3 }
                }
                #endif
                .task {
                    #if DEBUG
                    model.applyLaunchArguments()
                    #endif
                    model.launch()
                }
        }
        // The phone's context can arrive with the app in the background; let it land before suspending.
        .backgroundTask(.watchConnectivity) {
            await PhoneLink.shared.drain()
        }
    }
}
