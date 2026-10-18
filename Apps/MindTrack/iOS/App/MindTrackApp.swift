import MindEngine
import SwiftUI
import SystemCore

@main
struct MindTrackApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let launch = LaunchOptions.current
        // UI tests tap through screens faster without animations to wait for.
        if launch.isUITesting { UIView.setAnimationsEnabled(false) }
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
                .environment(model.purchases)
                .onOpenURL { url in DeepLink.open(url, model: model) }
                .task {
                    // Tests and UI tests never ask StoreKit.
                    guard !LaunchOptions.current.isQuiet else { return }
                    await model.purchases.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reloadIfChanged()
                        model.refreshDay()
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

#if DEBUG
/// The DEBUG launch arguments that set up a screen (docs/mind-track.md lists them), applied once the
/// model is up.
enum DebugLaunch {
    static func apply(_ launch: LaunchOptions, to model: AppModel) {
        // -seedSampleData fills an empty store with eight and a half weeks of study; -tab plan|progress
        // opens a tab; -startSession starts today's session; -showSettings opens Settings.
        if launch.has("-seedSampleData") { SampleData.seedIfEmpty(model) }
        // -courses maths,writing keeps only those courses (as Focus), to reach their screens without
        // scrolling; with -onboarded, the first session is theirs alone.
        let courses = launch.value(after: "-courses").map {
            Dictionary(
                $0.split(separator: ",").compactMap { Domain(rawValue: String($0)) }.map { ($0, CourseMode.focus) },
                uniquingKeysWith: { first, _ in first })
        }
        // -onboarded skips setup with the defaults and starts the first session.
        if launch.has("-onboarded"), !model.onboarded {
            var settings = MindSettings(readsKana: true, genres: [.fantasy])
            if let courses { settings.courses = courses }
            model.completeOnboarding(settings, booksRead: [])
        }
        if let tab = launch.value(after: "-tab") {
            model.tab =
                switch tab {
                case "plan": .plan
                case "progress": .progress
                default: .today
                }
        }
        if launch.has("-showSettings") { model.showSettings = true }
        // -showShelf opens the reading shelf (-findBook <title or ISBN> then searches for a book).
        if launch.has("-showShelf") || launch.has("-findBook") { model.showShelf = true }
        if launch.has("-startSession") { model.startToday() }
        if let courses, var settings = model.settings, settings.courses != courses {
            settings.courses = courses
            model.save(settings: settings)
        }
        // -mathsStrands discrete,classic sets the maths strands after numeracy, most important first.
        if let strands = launch.value(after: "-mathsStrands"), var settings = model.settings {
            settings.mathsStrands = [.numeracy] + strands.split(separator: ",").compactMap { MathsStrand(rawValue: String($0)) }
            model.save(settings: settings)
        }
        // -study japanese|maths|writing|reading starts a session of one subject; -steps N then
        // answers N steps (right, except every third), to reach later screens without tapping, and
        // -skipParts N moves past N parts (maths' timed numeracy block, say). The two run in the
        // order given.
        if let domain = launch.value(after: "-study").flatMap(Domain.init(rawValue:)) {
            model.startSession([domain])
        }
        // -checkIn writing starts a check-in of that subject now, whatever the calendar says.
        if let domain = launch.value(after: "-checkIn").flatMap(Domain.init(rawValue:)) {
            model.debugCheckIn([domain])
        }
        for (i, argument) in launch.arguments.enumerated() where argument == "-steps" || argument == "-skipParts" {
            guard let count = launch.arguments.indices.contains(i + 1) ? Int(launch.arguments[i + 1]) : nil, count > 0 else { continue }
            if argument == "-steps" { model.debugSteps(count) }
            if argument == "-skipParts" { for _ in 0..<count { model.act { $0.skipPart(now: model.now()) } } }
        }
    }
}
#endif
