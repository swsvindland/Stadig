import NutritionEngine
import OSLog
import SwiftUI
import SystemCore
import SystemStore
import WatchKit

/// CloudKit's pushes: another device's logs reach the Watch, and its complications, while the app
/// isn't open.
final class WristDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        guard !LaunchOptions.current.usesInMemoryStore else { return }
        WKApplication.shared().registerForRemoteNotifications()
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: any Error) {
        watchLog.error("Couldn't register for CloudKit's pushes: \(error.localizedDescription)")
    }

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        // The import runs on its own once the push lands, and the model hears it (`observeChanges`)
        // and analyses again; this keeps the app awake while it does, and then until the analysis
        // has written the complications' snapshot and reloaded them, which watchOS could otherwise
        // suspend halfway. Both waits together stay well inside the time a push is given.
        let model = WristModel.shared
        let before = model.store.revision
        try? await Task.sleep(for: .seconds(8))
        model.reloadIfChanged()
        await model.analysisFinished(within: .seconds(12))
        return model.store.revision == before ? .noData : .newData
    }
}

@main
struct MacroTrackWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WristDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WristModel.shared
    @State private var page = WristPage.today
    @State private var path: [WristRoute] = []
    /// When the app last went inactive: back after a while, it opens on Today again.
    @State private var inactiveSince: Date?

    var body: some Scene {
        WindowGroup {
            root
                .environment(model)
                #if DEBUG
            // `-largeText` previews an accessibility text size (simctl can't set one on watchOS).
            .transformEnvironment(\.dynamicTypeSize) { size in
                if LaunchOptions.current.has("-largeText") { size = .accessibility3 }
            }
                #endif
                .task {
                    model.refresh()
                    #if DEBUG
                    await openDebugPage()
                    #endif
                }
                // Brought back from suspension, perhaps the next day: `.task` doesn't run again.
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if let inactiveSince, Date().timeIntervalSince(inactiveSince) > 120 {
                            path = []
                            page = .today
                        }
                        inactiveSince = nil
                        model.refresh()
                    default:
                        if inactiveSince == nil { inactiveSince = Date() }
                    }
                }
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if LaunchOptions.current.has("-complications") {
            NavigationStack { ComplicationGallery() }
        } else {
            RootView(page: $page, path: $path)
        }
        #else
        RootView(page: $page, path: $path)
        #endif
    }

    #if DEBUG
    /// `-seedSampleData` and the rest (see `WristSample`), then the page `-page` names, once the
    /// pages are there: a vertical TabView shows its first page if the selection is set before it.
    /// `-complications` shows the complications' gallery in place of the app.
    private func openDebugPage() async {
        let launch = LaunchOptions.current
        WristSample.apply(launch, to: model)
        let route = launch.value(after: "-page")
        guard route != nil || launch.has("-demoLog") else { return }
        for _ in 0..<50 where model.today == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
        // `-demoLog` logs the first food in Log Again, to see the confirmation and its Undo.
        if launch.has("-demoLog"), let item = model.today?.logAgain.first { model.log(item) }
        switch route {
        case "logAgain": page = .logAgain
        case "water": page = .water
        case "supplements": page = .supplements
        case "weigh": path = [.weighIn]
        default: break
        }
    }
    #endif
}
