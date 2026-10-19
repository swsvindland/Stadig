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
        .commands { MindCommands(model: model) }
        #if os(macOS)
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        #endif

        #if os(macOS)
        // A session in a window of its own, at a size for reading and writing: the main window
        // stays behind it for the plan and progress.
        Window("Session", id: SessionWindow.id) {
            SessionWindow()
                .environment(model)
                .environment(model.purchases)
        }
        .defaultSize(width: 940, height: 800)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        // The unlock in a window of its own: asked for from the menu bar or Settings, the main
        // window may be closed or behind, and a sheet on it would go unseen.
        Window("Unlock Mind Track", id: PaywallView.windowID) {
            PaywallView()
                .environment(model.purchases)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            MacSettings()
                .environment(model)
                .environment(model.purchases)
        }
        #endif
    }
}

/// mindtrack://start opens today's session; mindtrack://plan and progress open those tabs, and
/// shelf, writing and courses those destinations (or, on an iPhone, the tab that reaches them).
enum DeepLink {
    @MainActor
    static func open(_ url: URL, model: AppModel) {
        guard model.onboarded else { return }
        if url.host() == "start" {
            if model.run == nil { model.startToday() }
            return
        }
        // A session covers the screen on iPhone, iPad and Vision Pro: a tab changed behind it would
        // open unseen. The Mac's main window is beside the session's.
        guard model.run == nil || Platform.isMac else { return }
        model.tab = url.host().flatMap(AppTab.init(rawValue:)) ?? .today
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
        // -tab plan|progress|shelf|writing|courses opens a tab or, in a wide window, a destination.
        if let tab = launch.value(after: "-tab") { model.tab = AppTab(rawValue: tab) ?? .today }
        if launch.has("-showSettings") { model.showSettings = true }
        // -showShelf opens the reading shelf (-findBook <title or ISBN> then searches for a book).
        if launch.has("-showShelf") || launch.has("-findBook") { model.showShelf = true }
        if launch.has("-findBook") { model.addingBook = true }
        // A session never starts over another: -startSession and -study replace the first one
        // -onboarded started, of which nothing was answered or saved.
        if launch.has("-startSession") {
            model.run = nil
            model.startToday()
        }
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
            model.run = nil
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
