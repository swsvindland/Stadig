import AppIntents
import FoodDatabase
import HealthBridge
import NutritionEngine
import SwiftUI
import SystemCore
import SystemPurchases

#if canImport(UIKit)
import UIKit
#endif

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
        if launch.isUITesting { Platform.disableAnimations() }
        let model = AppModel.shared
        _model = State(initialValue: model)
        model.ai.configure(catalog: model.catalog, allowCloud: model.settings.allowCloudAI)
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|progress (or foods|mealplan|supplements|history,
        // the sidebar's) opens a tab; -daysAgo 1 opens Today on an earlier day; -log search|describe|quickAdd
        // opens a logger. For checking screens quickly, and for the UI tests.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if launch.has("-seedLongHistory") { SampleData.seedLongHistory(model, years: launch.number(after: "-seedLongHistory") ?? 5) }
        if launch.has("-seedSupplements") { SampleData.seedSupplements(model) }
        if launch.has("-showSupplements") { model.showSupplements = true }
        if launch.has("-showSettings") { model.showSettings = true }
        if launch.has("-seedMealTiming") || launch.has("-seedFast") { SampleData.seedMealTiming(model, fast: launch.has("-seedFast")) }
        if launch.has("-showFast") { model.showFast = true }
        if let tab = launch.value(after: "-tab") {
            model.tab = AppTab.allCases.first { $0.rawValue.lowercased() == tab.lowercased() } ?? .today
        }
        if let days = launch.value(after: "-daysAgo").flatMap(Int.init) { model.selectedDay = model.today.adding(days: -days) }
        if let mode = launch.value(after: "-log") { model.logger = LogMode(rawValue: mode) }
        #endif
        MacroShortcuts.updateAppShortcutParameters()
        // Reminders' Taken button; tests and UI tests never schedule any.
        if !launch.isQuiet { SupplementReminders.register() }
    }

    /// The Mac's one window: the model holds what's on screen (the tab, the logger, the day), so a
    /// second window would only mirror it.
    static let mainWindow = "main"

    var body: some Scene {
        #if os(macOS)
        Window("Stadig Macro", id: Self.mainWindow) {
            if let model { root(model).frame(minWidth: 900, minHeight: 580) }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { MacroCommands(model: model) }
        Settings {
            if let model { MacSettingsView().environment(model).environment(model.purchases) }
        }
        #else
        WindowGroup {
            if let model { root(model) }
        }
        .commands { MacroCommands(model: model) }
        #if os(visionOS)
        // Room for a section's own sidebar beside the iPad's layout: at visionOS's 1280 the
        // tables beside their inspectors clip.
        .defaultSize(width: 1440, height: 900)
        #endif
        #endif
    }

    private func root(_ model: AppModel) -> some View {
        RootView()
            // The grouped forms of iPhone and iPad everywhere: the Mac's default puts labels in a
            // column of their own, which reads badly in a sheet.
            .formStyle(.grouped)
            .environment(model)
            .environment(model.purchases)
            .onOpenURL { url in DeepLink.open(url, model: model) }
            .task {
                await model.purchases.start()
                model.askForPurchaseIfDue()
            }
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
                    // What another device logged while Health couldn't be written (the phone locked,
                    // Health not connected yet) goes in now, not at the next import.
                    model.healthBackfill?.run()
                    // The system ends a fast's Live Activity after about 8 hours; opening the app starts it again.
                    if model.usesSystemServices { FastActivityBridge.update(model) }
                    Task {
                        await model.purchases.refresh()
                        model.askForPurchaseIfDue()
                    }
                case .background:
                    releaseCatalogMemory(model)
                default:
                    break
                }
            }
            #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            releaseCatalogMemory(model)
        }
            #endif
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
        case "fast":
            model.dismissSheets()
            model.tab = .today
            if model.tracksMealTiming { model.showFast = true }
        case "plan": model.tab = .plan
        default: model.tab = .today
        }
    }
}
