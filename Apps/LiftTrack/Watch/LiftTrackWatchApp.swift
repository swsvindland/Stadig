import HealthKit
import SwiftUI
import SystemCore
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if DEBUG
            // `-largeText` previews an accessibility text size (simctl can't set one on watchOS).
            .transformEnvironment(\.dynamicTypeSize) { size in
                if LaunchOptions.current.has("-largeText") { size = .accessibility3 }
            }
                #endif
                .task {
                    #if DEBUG
                    model.applyLaunchArguments()
                    #endif
                    model.launch()
                }
                // Brought back from suspension, perhaps the next day: `.task` doesn't run again.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
        // The phone's context can arrive with the app in the background; let it land before suspending.
        .backgroundTask(.watchConnectivity) {
            await PhoneLink.shared.drain()
        }
    }
}
