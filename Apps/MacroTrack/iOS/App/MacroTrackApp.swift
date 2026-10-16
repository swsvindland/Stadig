import SwiftUI
import AppIntents
import NutritionEngine
import SystemCore

@main
struct MacroTrackApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel.shared
        model.ai.configure(catalog: model.catalog, allowCloud: model.settings.allowCloudAI)
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|progress opens a tab; -log search|describe|quickAdd
        // opens a logger. For checking screens quickly.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedSampleData") { SampleData.seedIfEmpty(model) }
        if let i = arguments.firstIndex(of: "-tab"), arguments.indices.contains(i + 1) {
            model.tab = switch arguments[i + 1] {
            case "plan": .plan
            case "progress": .progress
            default: .today
            }
        }
        if let i = arguments.firstIndex(of: "-log"), arguments.indices.contains(i + 1) { model.logger = LogMode(rawValue: arguments[i + 1]) }
        #endif
        MacroShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.purchases)
                .onOpenURL { url in DeepLink.open(url, model: model) }
                .task {
                    await model.purchases.start()
                    await model.refreshHealth()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reloadIfChanged()
                        if model.today != .today { model.recompute() }
                    }
                }
        }
    }
}

/// macrotrack://log, scan, camera, describe, quickadd, weigh: the widget buttons and Shortcuts land
/// straight on the step they name.
enum DeepLink {
    @MainActor
    static func open(_ url: URL, model: AppModel) {
        guard model.onboarded else { return }
        model.selectedDay = model.today
        switch url.host() {
        case "log", "search": model.logger = .search
        case "scan": model.logger = .scan
        case "camera", "photo": model.logger = .camera
        case "describe": model.logger = .describe
        case "quickadd": model.logger = .quickAdd
        case "weigh": model.showWeighIn = true
        case "plan": model.tab = .plan
        default: model.tab = .today
        }
    }
}
