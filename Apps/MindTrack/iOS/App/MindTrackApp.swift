import SwiftUI
import MindEngine
import SystemCore

@main
struct MindTrackApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // -seedSampleData fills an empty store with five weeks of study; -tab plan|progress opens a
        // tab; -startSession starts today's session; -showSettings opens Settings.
        let model = AppModel.shared
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedSampleData") { SampleData.seedIfEmpty(model) }
        // -onboarded skips setup with the defaults and starts the first session.
        if arguments.contains("-onboarded"), !model.onboarded {
            model.completeOnboarding(MindSettings(readsKana: true, genres: [.fantasy]), booksRead: [])
        }
        if let i = arguments.firstIndex(of: "-tab"), arguments.indices.contains(i + 1) {
            model.tab = switch arguments[i + 1] {
            case "plan": .plan
            case "progress": .progress
            default: .today
            }
        }
        if arguments.contains("-showSettings") { model.showSettings = true }
        if arguments.contains("-startSession") { model.startToday() }
        // -study japanese|maths|writing|reading starts a session of one subject; -steps N then
        // answers N steps (right, except every third), to reach later screens without tapping.
        if let i = arguments.firstIndex(of: "-study"), arguments.indices.contains(i + 1), let domain = Domain(rawValue: arguments[i + 1]) {
            model.startSession([domain])
        }
        // -checkIn writing starts a check-in of that subject now, whatever the calendar says.
        if let i = arguments.firstIndex(of: "-checkIn"), arguments.indices.contains(i + 1), let domain = Domain(rawValue: arguments[i + 1]) {
            model.debugCheckIn([domain])
        }
        if let i = arguments.firstIndex(of: "-steps"), arguments.indices.contains(i + 1), let steps = Int(arguments[i + 1]) {
            model.debugSteps(steps)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.purchases)
                .onOpenURL { url in DeepLink.open(url, model: model) }
                .task { await model.purchases.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reloadIfChanged()
                        if model.today != .today { model.recompute() }
                    }
                }
        }
    }
}

/// mindtrack://start opens today's session; mindtrack://plan and progress open those tabs.
enum DeepLink {
    @MainActor
    static func open(_ url: URL, model: AppModel) {
        guard model.onboarded else { return }
        switch url.host() {
        case "start": if model.run == nil { model.startToday() }
        case "plan": model.tab = .plan
        case "progress": model.tab = .progress
        default: model.tab = .today
        }
    }
}
