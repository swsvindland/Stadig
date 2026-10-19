import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

@main
struct LiftTrackApp: App {
    /// Nil while XCTest hosts the unit tests: they build models of their own, so the app builds none
    /// and starts nothing.
    @State private var model: AppModel?

    init() {
        let launch = LaunchOptions.current
        // Tests and UI tests: no Health prompts, reads or writes, from before anything asks.
        if launch.isQuiet { HealthBridge.shared.disable() }
        guard !launch.isHostingTests else { return }
        if launch.isUITesting { Platform.disableAnimations() }
        let model = AppModel.shared
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|program|library|history|progress|body opens
        // a destination; -startSession starts today's session. For checking screens quickly.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if let tab = launch.value(after: "-tab") { model.tab = AppTab(rawValue: tab) ?? .today }
        // -exercise <id> opens Library on that exercise.
        if let exercise = launch.value(after: "-exercise") { model.show(inLibrary: exercise) }
        // -gymSauna gives the gym a sauna, for the recovery screen.
        if launch.has("-gymSauna") {
            var gym = model.gym
            gym.apparatus.insert(.sauna)
            model.save(gym: gym)
        }
        if launch.has("-startSession"), model.live == nil, let plan = model.plan() { model.start(plan) }
        #endif
        #if os(iOS)
        // No Watch under tests: nothing to activate, and nothing to wait on.
        if !launch.isQuiet {
            WatchLink.shared.activate()
            WorkoutMirror.shared.onData = { data in AppModel.shared.fromWatch(data) }
            WorkoutMirror.shared.activate()
        }
        #endif
        _model = State(initialValue: model)
    }

    static let mainWindow = "main"

    var body: some Scene {
        #if os(macOS)
        // One main window, sized for the program beside the sidebar; the session gets its own window
        // and Settings the app menu's (⌘,).
        Window("Lift Track", id: Self.mainWindow) {
            if let model {
                AppRoot(model: model)
                    .frame(minWidth: 820, minHeight: 560)
            }
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            LiftCommands(model: model)
            // File ▸ Import from iPhone or iPad: a progress photo taken with the phone (Body).
            ImportFromDevicesCommands()
        }
        Window("Session", id: SessionWindow.id) {
            if let model {
                SessionWindow(model: model)
            }
        }
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        // Opened from the Session menu and the toolbar's Resume, which know whether there's a
        // session; an item of its own in the Window menu would open it without one.
        .commandsRemoved()
        Settings {
            if let model {
                MacSettings(model: model)
            }
        }
        #else
        WindowGroup {
            if let model {
                AppRoot(model: model)
            }
        }
        .commands { LiftCommands(model: model) }
        #endif
    }
}

/// The app's window: the model in the environment, links from the widget and the Live Activity, and
/// Health and the purchase brought up to date on launch and on each return.
private struct AppRoot: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS) && DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        RootView()
            .environment(model)
            .environment(model.purchases)
            .onOpenURL { url in model.open(url) }
            // The Mac's forms look as they do on the other platforms, in sheets and panes alike.
            .formStyle(.grouped)
            #if os(macOS) && DEBUG
        // -openSettings opens the Settings window, for checking its panes.
        .task { if LaunchOptions.current.has("-openSettings") { openSettings() } }
            #endif
            .task {
                // Tests and UI tests ask StoreKit and Health nothing.
                guard !LaunchOptions.current.isQuiet else { return }
                await model.purchases.start()
                await HealthBridge.shared.requestAddedTypes()
                // Observing first: the read after it stands for the observer's first call.
                model.startHealthObserving()
                await model.refreshHealthIfStale()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.reloadIfChanged()
                    if model.today != .today { model.recompute() }
                    // Sleep, weigh-ins, steps and outside workouts came in while the app was away.
                    Task { await model.refreshHealthIfStale() }
                }
            }
    }
}
