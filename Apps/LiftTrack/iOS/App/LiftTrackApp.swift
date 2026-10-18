import SwiftUI
import ExerciseLibrary
import HealthBridge
import LiftEngine
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
        if launch.isUITesting { UIView.setAnimationsEnabled(false) }
        let model = AppModel.shared
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|progress|body opens a tab; -startSession
        // starts today's session. For checking screens quickly.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if let tab = launch.value(after: "-tab") {
            model.tab =
                switch tab {
                case "plan": .plan
                case "progress": .progress
                case "body": .body
                default: .today
                }
        }
        // -gymSauna gives the gym a sauna, for the recovery screen.
        if launch.has("-gymSauna") {
            var gym = model.gym
            gym.apparatus.insert(.sauna)
            model.save(gym: gym)
        }
        if launch.has("-startSession"), model.live == nil, let plan = model.plan() { model.start(plan) }
        #endif
        // No Watch under tests: nothing to activate, and nothing to wait on.
        if !launch.isQuiet {
            WatchLink.shared.activate()
            WorkoutMirror.shared.onData = { data in AppModel.shared.fromWatch(data) }
            WorkoutMirror.shared.activate()
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                AppRoot(model: model)
            }
        }
    }
}

/// The app's window: the model in the environment, links from the widget and the Live Activity, and
/// Health and the purchase brought up to date on launch and on each return.
private struct AppRoot: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootView()
            .environment(model)
            .environment(model.purchases)
            .onOpenURL { url in model.open(url) }
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
