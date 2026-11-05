import HubEngine
import SwiftUI
import SystemCore

@main
struct HubApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let launch = LaunchOptions.current
        Platform.styleControls()
        // UI tests tap through screens faster without animations to wait for.
        if launch.isUITesting { Platform.disableAnimations() }
        // The unit tests build models of their own: the app only needs to come up, empty.
        guard !launch.isHostingTests else { return }
        #if DEBUG
        DebugLaunch.apply(launch, to: AppModel.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in DeepLink.open(url, model: model) }
                .task { await model.keepTime() }
                .onChange(of: scenePhase) { _, phase in
                    // What the apps published while this one was away: nothing reaches a suspended app.
                    if phase == .active { model.readShared() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        #endif
    }
}

/// stadig://today, stadig://week, stadig://stats, stadig://rhythm.
enum DeepLink {
    @MainActor
    static func open(_ url: URL, model: AppModel) {
        guard model.onboarded else { return }
        model.tab = url.host().flatMap(AppTab.init(rawValue:)) ?? .today
    }
}

#if DEBUG
/// The DEBUG launch arguments that set up a screen (docs/hub.md lists them). Run once the model is up.
enum DebugLaunch {
    static func apply(_ launch: LaunchOptions, to model: AppModel) {
        // -seedSampleData fills an empty hub with a week and what the apps would have published;
        // -tab opens a tab; -showPlansChanged opens the sheet.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if let tab = launch.value(after: "-tab").flatMap(AppTab.init(rawValue:)) { model.tab = tab }
        if launch.has("-showPlansChanged") { model.showPlansChanged = true }
        // -day sun picks a day; -showMove "Muay Thai" opens the move sheet for that class on it.
        if let name = launch.value(after: "-day"),
            let day = (0..<7).map(model.today.startOfWeek.adding(days:)).first(where: { $0.weekday.short.lowercased() == name })
        {
            model.selectedDay = day
        }
        if let title = launch.value(after: "-showMove") { model.moving = model.shownDay?.items.first { $0.title == title } }
    }
}
#endif
