import NutritionEngine
import SwiftUI
import SystemCore
import SystemStore

/// Today for the day at a glance, Log for its food hour by hour, Plan for the phase and targets,
/// Progress for the trend. On a phone every tab has the same composer at its foot, above the tabs:
/// Today's own, and `TabComposer` on the others, logging where it is. With room for a sidebar (iPad,
/// the Mac, Vision Pro) the sidebar adds the Week desk, Foods to find and compare, the Meal Plan,
/// Supplements and History; logging is Today's and Log's composer, Log's pane, the Foods screen and
/// the menu bar.
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
            Tab("Log", systemImage: "list.bullet", value: AppTab.log) { LogTab().tabComposer(.log, isEnabled: !wide) }
            if wide {
                Tab("Week", systemImage: "rectangle.split.3x1", value: AppTab.week) { WeekDeskView() }
                    .accessibilityIdentifier("sidebar.week")
                TabSection {
                    Tab("Foods", systemImage: "carrot", value: AppTab.foods) { FoodsView() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.foods")
                    Tab("Meal Plan", systemImage: "takeoutbag.and.cup.and.straw", value: AppTab.mealPlan) { MealPlanTab() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.mealPlan")
                    Tab("Supplements", systemImage: "pills", value: AppTab.supplements) { SupplementsTab() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.supplements")
                } header: {
                    TabSectionTitle("Food", systemImage: "basket")
                }
                TabSection {
                    Tab("Plan", systemImage: "flag", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                    Tab("History", systemImage: "calendar", value: AppTab.history) { HistoryView() }
                        .tabPlacement(.sidebarOnly)
                        .accessibilityIdentifier("sidebar.history")
                } header: {
                    TabSectionTitle("Review", systemImage: "chart.bar.xaxis")
                }
            } else {
                // A page pushed from them has the screen to itself (`pushedPage()`).
                Tab("Plan", systemImage: "flag", value: AppTab.plan) { PlanView().tabComposer(.plan, isEnabled: !model.pageCoversComposer) }
                Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                    ProgressTab().tabComposer(.progress, isEnabled: !model.pageCoversComposer)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Over the sidebar's destinations, the day's one number, as the menu bar has it.
        .tabViewSidebarHeader { SidebarHeader() }
        #if os(iOS)
        #if DEBUG
        // -sidebar opens an iPad on its sidebar, where the screens have the least room.
        .defaultAdaptableTabBarPlacement(ProcessInfo.processInfo.arguments.contains("-sidebar") ? .sidebar : .automatic)
        #endif
        // The tab bar stays whole: every phone tab has the composer standing on it, and the composer
        // doesn't follow the bar down, so a bar shrunk to a button left an empty band under the field.
        .tabBarMinimizeBehavior(.never)
        #endif
        // Clear of the selection bar where it's at the foot of the screen. The logger shows its own,
        // in with the meal: one behind it would be a second Undo nobody can reach. It takes over when
        // the logger closes, with its few seconds starting again. On a phone each tab shows it over
        // its composer, and Today an Undo in the meal just logged too. Today and Log, wide as well,
        // show theirs over their composers. A page pushed over a phone's tab, with no composer at
        // its foot, shows it here.
        .toastOverlay(
            bottomPadding: model.selection.isEmpty ? 24 : 92,
            showing: model.logger == nil && !model.toastCovered && model.tab != .today && model.tab != .log
                && (wide || model.pageCoversComposer)
        )
        // A meal photo dragged onto the window from Photos or Finder is read like one chosen.
        .dropDestination(for: DroppedImage.self) { images, _ in
            if let photo = images.first?.data { model.logDroppedPhoto(photo) }
        }
    }
}

/// The sidebar's head: the app's name over what's left today on a thin ruler, so the number is in
/// sight from Foods or History as it is from the menu bar.
private struct SidebarHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let eaten = model.dayIntake(on: model.today).eaten.kcal
        VStack(alignment: .leading, spacing: 6) {
            Text("Stadig Macro").eyebrow()
            if let kcal = model.analysis?.targets.kcal, kcal > 0 {
                let left = kcal - eaten
                Measure(value: Format.whole(abs(left)), unit: left >= 0 ? "kcal left" : "kcal over", size: 24, weight: .heavy)
                    .foregroundStyle(Ink.text)
                Ruler.thin(eaten / kcal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar.left")
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let toast = model.toast {
            ToastView(toast: toast) { model.undo(toast) }
                .transition(.rise(reduceMotion: reduceMotion))
                .task(id: toast.id) { await model.expire(toast) }
        }
    }
}
