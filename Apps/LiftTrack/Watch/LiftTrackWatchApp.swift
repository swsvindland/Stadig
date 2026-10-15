import SwiftUI

@main
struct LiftTrackWatchApp: App {
    @State private var model = WatchModel()

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
