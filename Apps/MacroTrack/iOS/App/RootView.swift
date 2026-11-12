import NutritionEngine
import SwiftUI
import SystemStore

/// Today for the day at a glance, Log for its food hour by hour, Plan for the phase and targets,
/// Progress for the trend. Logging is one tap away from every tab, in the bar above the tabs. With
/// room for a sidebar (iPad, the Mac, Vision Pro) the sidebar adds Foods to find and compare, the
/// Meal Plan, Supplements and History, and logging moves to the toolbars, the Foods screen and the
/// menu bar.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    /// Room for the sidebar's destinations. The Mac reports no size class: it always has room.
    private var wide: Bool { sizeClass != .compact }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                tabs
            } else if let arrival = model.arrival, arrival.isWaiting {
                ICloudWaitView(arrival: arrival)
            } else {
                OnboardingView()
            }
        }
        // Closing it drops a picked time (the model does that), so later one-tap logs are now.
        // Where there's room the logger is a pane of the Log tab, not a sheet over it.
        .sheet(item: Binding(get: { wide ? nil : model.logger }, set: { model.logger = $0 })) { mode in
            LoggerSheet(start: mode).macSheetSize(width: 600, height: 700)
        }
        .sheet(isPresented: $model.showWeighIn) {
            WeighInSheet().macSheetSize(width: 440, height: 520)
        }
        .sheet(isPresented: $model.showFast) {
            FastSheet().macSheetSize(width: 520, height: 680)
        }
        .sheet(isPresented: $model.showSupplements) {
            SupplementsView().macSheetSize(width: 520, height: 640)
        }
        // Prep day at the counter, over everything (a large sheet on the Mac).
        .cover(isPresented: $model.showPrepCounter) {
            if let run = model.prepRun { PrepCounter(run: run) }
        }
        #if !os(macOS)
        // The Mac's settings are a window of their own (⌘,).
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        #endif
        .onChange(of: wide, initial: true) { _, wide in
            model.usesSidebar = wide
            // Widened with a logger open (or launched with one): its pane is on the Log tab.
            if wide, model.logger != nil { model.tab = .log }
            // Narrowed (an iPad window in Split View) on a screen only the sidebar has: the nearest
            // one the tab bar has.
            guard !wide else { return }
            model.tab = model.tab.compactFallback
        }
        #if os(macOS)
        .onChange(of: model.showSettings, initial: true) { _, show in
            guard show else { return }
            model.showSettings = false
            openSettings()
        }
        #endif
    }

    var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.tab) {
            Tab("Today", systemImage: "fork.knife", value: AppTab.today) { TodayView() }
            Tab("Log", systemImage: "list.bullet.clipboard", value: AppTab.log) { LogTab() }
            if wide {
                TabSection("Food") {
                    Tab("Foods", systemImage: "carrot", value: AppTab.foods) { FoodsView() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.foods")
                    Tab("Meal Plan", systemImage: "takeoutbag.and.cup.and.straw", value: AppTab.mealPlan) { MealPlanTab() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.mealPlan")
                    Tab("Supplements", systemImage: "pills", value: AppTab.supplements) { SupplementsTab() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.supplements")
                }
                TabSection("Review") {
                    Tab("Plan", systemImage: "map", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                    Tab("History", systemImage: "calendar", value: AppTab.history) { HistoryView() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.history")
                }
            } else {
                Tab("Plan", systemImage: "map", value: AppTab.plan) { PlanView() }
                Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        #if DEBUG
        // -sidebar opens an iPad on its sidebar, where the screens have the least room.
        .defaultAdaptableTabBarPlacement(ProcessInfo.processInfo.arguments.contains("-sidebar") ? .sidebar : .automatic)
        #endif
        .tabBarMinimizeBehavior(.onScrollDown)
        // On a phone's Today the composer is the way to log; every other tab keeps the bar.
        .tabViewBottomAccessory(isEnabled: !wide && model.tab != .today) {
            if model.selection.isEmpty { QuickLogBar() } else { SelectionBar() }
        }
        #endif
        // Clear of the selection bar where it's at the foot of the screen. The logger shows its own, in with the meal: one behind it would be a second Undo nobody can
        // reach. It takes over when the logger closes, with its few seconds starting again.
        // A phone's Today shows its own, over the composer, and an Undo in the meal just logged.
        .toastOverlay(
            bottomPadding: wide ? (model.selection.isEmpty ? 24 : 92) : 130,
            showing: model.logger == nil && !model.toastCovered && (wide || model.tab != .today)
        )
        // A meal photo dragged onto the window from Photos or Finder is read like one chosen.
        .dropDestination(for: DroppedImage.self) { images, _ in
            if let photo = images.first?.data { model.logDroppedPhoto(photo) }
        }
    }
}

#if os(iOS)
/// The ways to log, above the tab bar: search, camera, barcode, description and a weigh-in.
/// Collapses to icons when the tab bar minimises.
struct QuickLogBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 4) {
            Button {
                open(.search)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    if placement != .inline { Text(model.logTargetTitle).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .accessibilityLabel(model.logTargetTitle)
            .accessibilityIdentifier("quickLog.search")
            icon("camera", "Log a photo", .camera)
            icon("barcode.viewfinder", "Scan a barcode", .scan)
            icon("text.bubble", "Describe a meal", .describe)
            // Nothing to weigh yet on a day to come.
            if model.selectedDay <= model.today {
                Button {
                    model.showWeighIn = true
                } label: {
                    Image(systemName: "scalemass").frame(width: 44, height: 40).contentShape(.rect)
                }
                .accessibilityLabel("Weigh in")
                .accessibilityIdentifier("quickLog.weighIn")
                .padding(.trailing, 6)
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .font(.body.weight(.medium))
    }

    func icon(_ symbol: String, _ label: String, _ mode: LogMode) -> some View {
        Button {
            open(mode)
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 40).contentShape(.rect)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("quickLog.\(mode.rawValue)")
    }

    func open(_ mode: LogMode) {
        model.openLogger(mode)
    }
}
#endif

extension View {
    /// Shows the model's toast at the bottom for a few seconds.
    func toastOverlay(bottomPadding: CGFloat = 24, showing: Bool = true) -> some View {
        modifier(ToastOverlay(bottomPadding: bottomPadding, showing: showing))
    }

    /// Tells the model a sheet of this screen's is open, or a food's open beside it, which it can't
    /// see for itself: `open` is held in the view. It's what someone's in the middle of, so the
    /// offer on opening waits for it. `covering` says it's over where the toast shows, whose few
    /// seconds would run out behind it: a pane isn't.
    func notesWork(_ open: Bool, covering: Bool = true) -> some View { modifier(WorkNote(open: open, covering: covering)) }
}

private struct WorkNote: ViewModifier {
    @Environment(AppModel.self) private var model
    let open: Bool
    let covering: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: note)
            .onChange(of: open) { _, _ in note() }
            .onChange(of: covering) { _, _ in note() }
            // Off screen it's over, wherever it was left: a tab that's gone, a screen that went.
            .onDisappear { model.noteWork(id, open: false, covering: false) }
    }

    func note() { model.noteWork(id, open: open, covering: covering) }
}

private struct ToastOverlay: ViewModifier {
    @Environment(AppModel.self) private var model
    let bottomPadding: CGFloat
    let showing: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if showing { ToastSlot().padding(.bottom, bottomPadding) }
        }
        .animation(.snappy, value: model.toast)
    }
}

/// The model's toast, for a few seconds, where a screen places it.
struct ToastSlot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            ToastView(toast: toast) { model.undo(toast) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) { await model.expire(toast) }
        }
    }
}
