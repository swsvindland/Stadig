import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Today to train, Plan for the block, Progress for the stats, Body for physique. The sidebar on the
/// iPad, the Mac and Vision Pro adds the planning desk: Program, Library and History.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        @Bindable var model = model
        ZStack {
            if model.onboarded {
                tabs
            } else {
                OnboardingView()
            }
        }
        #if os(macOS)
        // The session runs in a window of its own, so the program stays in view beside it.
        .onChange(of: model.showSession, initial: true) { _, show in
            if show { openWindow(id: SessionWindow.id) } else { dismissWindow(id: SessionWindow.id) }
        }
        #else
        .cover(isPresented: $model.showSession) {
            SessionScreen()
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        #endif
        .sheet(item: $model.finished) { record in
            SessionSummaryView(record: record)
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .logActivity: ActivityLogSheet()
            case .checkIn: CheckInView()
            case .measurements: MeasurementEditor(measurements: BodyMeasurements(day: .today))
            case .nextBlock: NextBlockView()
            }
        }
    }

    /// The tab shown: the destination itself where there's a sidebar, or in a narrow window the tab
    /// that reaches it (`AppTab.tabBarFallback`), since the tab bar has no Program, Library or
    /// History. A narrow window never writes the fallback back, so an iPad with a wide and a narrow
    /// window open on the one model can't undo the other's choice.
    private var selection: Binding<AppTab> {
        Binding(get: { sizeClass.isWide ? model.tab : model.tab.tabBarFallback }, set: { model.tab = $0 })
    }

    private var tabs: some View {
        TabView(selection: selection) {
            Tab(AppTab.today.title, systemImage: AppTab.today.symbol, value: AppTab.today) { TodayView() }
            TabSection("Training") {
                Tab(AppTab.plan.title, systemImage: AppTab.plan.symbol, value: AppTab.plan) { PlanView() }
                Tab(AppTab.program.title, systemImage: AppTab.program.symbol, value: AppTab.program) { ProgramView() }
                    .tabPlacement(.sidebarOnly)
                Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) { LibraryView() }
                    .tabPlacement(.sidebarOnly)
            }
            TabSection("Records") {
                Tab(AppTab.history.title, systemImage: AppTab.history.symbol, value: AppTab.history) { HistoryTab() }
                    .tabPlacement(.sidebarOnly)
                Tab(AppTab.progress.title, systemImage: AppTab.progress.symbol, value: AppTab.progress) { ProgressTab() }
                Tab(AppTab.body.title, systemImage: AppTab.body.symbol, value: AppTab.body) { BodyView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: model.live != nil && !model.showSession) {
            SessionAccessory()
        }
        #endif
    }
}

/// The minimized session in the tab bar's accessory: the rest, or the next set.
struct SessionAccessory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showSession = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                SessionStatusLine()
                Spacer()
                Text("Resume").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.accessory")
    }
}

/// What the minimized session is doing: resting, or the exercise up next.
struct SessionStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let live = model.live {
            if let rest = model.activeRest {
                Text("Rest").font(.subheadline.weight(.semibold))
                Text(timerInterval: Date()...max(Date(), rest.endsAt), countsDown: true).monospacedDigit()
            } else if let current = live.current {
                Text(model.catalog.resolve(live.items[current.item].exerciseID).name).lineLimit(1)
            } else {
                Text("Finish session")
            }
        }
    }
}

extension View {
    /// Where there's no tab bar accessory (the Mac, Vision Pro), a session that's running but not on
    /// screen is a Resume button in the toolbar of every destination.
    func sessionResumeToolbar() -> some View {
        modifier(SessionResumeToolbar())
    }
}

private struct SessionResumeToolbar: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(iOS)
        content
        #else
        content.toolbar {
            if model.live != nil && !model.showSession {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.showSession = true
                    } label: {
                        Label("Resume", systemImage: "figure.strengthtraining.traditional").labelStyle(.titleAndIcon)
                    }
                    .help("Back to the session in progress")
                    .accessibilityIdentifier("session.resume")
                }
            }
        }
        #endif
    }
}

/// The gear that opens Settings on iPhone, iPad and Vision Pro. The Mac has none: Settings is in the
/// app menu (⌘,), as on every Mac app.
struct SettingsToolbarItem: ToolbarContent {
    @Environment(AppModel.self) private var model
    let identifier: String

    var body: some ToolbarContent {
        #if !os(macOS)
        ToolbarItem(placement: .barTrailing) {
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(identifier)
        }
        #endif
    }
}
