import SwiftUI
import HealthBridge
import SystemCore

@main
struct LiftTrackApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // -seedSampleData fills an empty store; -tab plan|progress|body opens a tab; -startSession
        // starts today's session. For checking screens quickly.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedSampleData") { SampleData.seedIfEmpty(AppModel.shared) }
        if let i = arguments.firstIndex(of: "-tab"), arguments.indices.contains(i + 1) {
            AppModel.shared.tab = switch arguments[i + 1] {
            case "plan": .plan
            case "progress": .progress
            case "body": .body
            default: .today
            }
        }
        if arguments.contains("-startSession"), AppModel.shared.live == nil, let plan = AppModel.shared.plan() { AppModel.shared.start(plan) }
        #endif
        WatchLink.shared.activate()
        WorkoutMirror.shared.onData = { data in AppModel.shared.fromWatch(data) }
        WorkoutMirror.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.purchases)
                .onOpenURL { url in
                    switch url.host() {
                    case "start":
                        if model.live != nil { model.showSession = true } else if let plan = model.plan() { model.start(plan) }
                    case "session":
                        if model.live != nil { model.showSession = true }
                    default:
                        break
                    }
                }
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
