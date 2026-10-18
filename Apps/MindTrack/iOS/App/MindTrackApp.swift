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
        // -courses maths,writing keeps only those courses (as Focus), to reach their screens without
        // scrolling; with -onboarded, the first session is theirs alone.
        let courses = arguments.firstIndex(of: "-courses").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .map { Dictionary(uniqueKeysWithValues: $0.split(separator: ",").compactMap { Domain(rawValue: String($0)) }.map { ($0, CourseMode.focus) }) }
        // -onboarded skips setup with the defaults and starts the first session.
        if arguments.contains("-onboarded"), !model.onboarded {
            var settings = MindSettings(readsKana: true, genres: [.fantasy])
            if let courses { settings.courses = courses }
            model.completeOnboarding(settings, booksRead: [])
        }
        if let i = arguments.firstIndex(of: "-tab"), arguments.indices.contains(i + 1) {
            model.tab = switch arguments[i + 1] {
            case "plan": .plan
            case "progress": .progress
            default: .today
            }
        }
        if arguments.contains("-showSettings") { model.showSettings = true }
        // -showShelf opens the reading shelf (-findBook <title or ISBN> then searches for a book).
        if arguments.contains("-showShelf") || arguments.contains("-findBook") { model.showShelf = true }
        if arguments.contains("-startSession") { model.startToday() }
        if let courses, var settings = model.settings, settings.courses != courses {
            settings.courses = courses
            model.save(settings: settings)
        }
        // -mathsStrands discrete,classic sets the maths strands after numeracy, most important first.
        if let i = arguments.firstIndex(of: "-mathsStrands"), arguments.indices.contains(i + 1), var settings = model.settings {
            settings.mathsStrands = [.numeracy] + arguments[i + 1].split(separator: ",").compactMap { MathsStrand(rawValue: String($0)) }
            model.save(settings: settings)
        }
        // -study japanese|maths|writing|reading starts a session of one subject; -steps N then
        // answers N steps (right, except every third), to reach later screens without tapping, and
        // -skipParts N moves past N parts (maths' timed numeracy block, say). The two run in the
        // order given.
        if let i = arguments.firstIndex(of: "-study"), arguments.indices.contains(i + 1), let domain = Domain(rawValue: arguments[i + 1]) {
            model.startSession([domain])
        }
        // -checkIn writing starts a check-in of that subject now, whatever the calendar says.
        if let i = arguments.firstIndex(of: "-checkIn"), arguments.indices.contains(i + 1), let domain = Domain(rawValue: arguments[i + 1]) {
            model.debugCheckIn([domain])
        }
        for (i, argument) in arguments.enumerated() where arguments.indices.contains(i + 1) {
            guard let count = Int(arguments[i + 1]) else { continue }
            if argument == "-steps" { model.debugSteps(count) }
            if argument == "-skipParts" { for _ in 0..<count { model.act { $0.skipPart(now: Date()) } } }
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
