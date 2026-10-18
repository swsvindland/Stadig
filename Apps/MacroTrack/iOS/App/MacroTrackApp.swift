import AppIntents
import FoodDatabase
import HealthBridge
import NutritionEngine
import SwiftUI
import SystemCore
import UIKit

@main
struct MacroTrackApp: App {
    /// Nil while XCTest hosts the unit tests: they build models of their own, and the app stays
    /// out of their way.
    @State private var model: AppModel? = nil
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let launch = LaunchOptions.current
        // The tests' models never reach Health either.
        if launch.isQuiet { HealthBridge.shared.disable() }
        guard !launch.isHostingTests else { return }
        if launch.isUITesting { UIView.setAnimationsEnabled(false) }
        let model = AppModel.shared
        _model = State(initialValue: model)
        model.ai.configure(catalog: model.catalog, allowCloud: model.settings.allowCloudAI)
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|progress opens a tab; -log search|describe|quickAdd
        // opens a logger. For checking screens quickly, and for the UI tests.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if launch.has("-seedSupplements") { SampleData.seedSupplements(model) }
        if launch.has("-showSupplements") { model.showSupplements = true }
        if launch.has("-showSettings") { model.showSettings = true }
        if let tab = launch.value(after: "-tab") {
            model.tab =
                switch tab {
                case "plan": .plan
                case "progress": .progress
                default: .today
                }
        }
        if let mode = launch.value(after: "-log") { model.logger = LogMode(rawValue: mode) }
        #endif
        MacroShortcuts.updateAppShortcutParameters()
        // Reminders' Taken button; tests and UI tests never schedule any.
        if !launch.isQuiet { SupplementReminders.register() }
    }

    var body: some Scene {
        WindowGroup {
            if let model { root(model) }
        }
    }

    private func root(_ model: AppModel) -> some View {
        RootView()
            .environment(model)
            .environment(model.purchases)
            .onOpenURL { url in DeepLink.open(url, model: model) }
            .task { await model.purchases.start() }
            // Not after StoreKit, which can take its time on a slow network: a scale's weigh-in
            // would go unheard until it answered.
            .task {
                // Unless becoming active just did.
                await model.refreshHealthIfStale()
                model.startHealthObserving()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.refreshDay()
                    // Apple Intelligence may have been turned on, or finished downloading, meanwhile.
                    model.ai.configure(catalog: model.catalog, allowCloud: model.settings.allowCloudAI)
                    Task { await model.refreshHealthIfStale() }
                case .background:
                    releaseCatalogMemory(model)
                default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                releaseCatalogMemory(model)
            }
    }

    /// What searches keep around, freed off the main thread; the next search is as quick as after launch.
    private func releaseCatalogMemory(_ model: AppModel) {
        let catalog = model.catalog
        Task.detached(priority: .utility) { catalog.releaseMemory() }
    }
}

/// macrotrack://log, scan, camera, describe, quickadd, weigh: the widget buttons and Shortcuts land
/// straight on the step they name, in place of any sheet already up.
enum DeepLink {
    @MainActor
    static func open(_ url: URL, model: AppModel) {
        guard model.onboarded else { return }
        model.selectedDay = model.today
        func log(_ mode: LogMode) {
            model.dismissSheets()
            model.openLogger(mode)
        }
        switch url.host() {
        case "log", "search": log(.search)
        case "scan": log(.scan)
        case "camera", "photo": log(.camera)
        case "describe": log(.describe)
        case "quickadd": log(.quickAdd)
        case "weigh":
            model.dismissSheets()
            model.showWeighIn = true
        case "supplements":
            model.dismissSheets()
            model.showSupplements = true
        case "plan": model.tab = .plan
        default: model.tab = .today
        }
    }
}
