import NutritionEngine
import SwiftUI

/// Today to log, Plan for the phase and targets, Progress for the trend. Logging is one tap away
/// from every tab, in the bar above the tabs. With room for a sidebar (iPad, the Mac, Vision Pro)
/// the sidebar adds Foods to find and compare, the Meal Plan, Supplements and History, and logging
/// moves to Today's toolbar, the Foods screen and the menu bar.
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
            } else {
                OnboardingView()
            }
        }
        // Closing it drops a picked time (the model does that), so later one-tap logs are now.
        .sheet(item: $model.logger) { mode in
            LoggerSheet(start: mode).macSheetSize(width: 600, height: 700)
        }
        .sheet(isPresented: $model.showWeighIn) {
            WeighInSheet().macSheetSize(width: 440, height: 520)
        }
        .sheet(isPresented: $model.showSupplements) {
            SupplementsView().macSheetSize(width: 520, height: 640)
        }
        #if !os(macOS)
        // The Mac's settings are a window of their own (⌘,).
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        #endif
        .sheet(isPresented: $model.showPaywall) {
            PaywallView().macSheetSize(width: 480, height: 560)
        }
        .onAppear { model.usesSidebar = wide }
        .onChange(of: wide) { _, wide in
            model.usesSidebar = wide
            // Narrowed (an iPad window in Split View) on a screen only the sidebar has: the nearest
            // one the tab bar has.
            guard !wide, model.tab.isSidebarOnly else { return }
            model.tab =
                switch model.tab {
                case .mealPlan: .plan
                case .history: .progress
                default: .today
                }
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
        // The iPad opens on its sidebar, where the destinations are.
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: !wide) { QuickLogBar() }
        #endif
        .toastOverlay(bottomPadding: wide ? 24 : 130)
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
                    if placement != .inline { Text("Log food").foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .accessibilityLabel("Search foods")
            .accessibilityIdentifier("quickLog.search")
            icon("camera", "Log a photo", .camera)
            icon("barcode.viewfinder", "Scan a barcode", .scan)
            icon("text.bubble", "Describe a meal", .describe)
            Button {
                model.showWeighIn = true
            } label: {
                Image(systemName: "scalemass").frame(width: 44, height: 40).contentShape(.rect)
            }
            .accessibilityLabel("Weigh in")
            .accessibilityIdentifier("quickLog.weighIn")
            .padding(.trailing, 6)
        }
        .buttonStyle(.plain)
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
    func toastOverlay(bottomPadding: CGFloat = 24) -> some View { modifier(ToastOverlay(bottomPadding: bottomPadding)) }
}

private struct ToastOverlay: ViewModifier {
    @Environment(AppModel.self) private var model
    let bottomPadding: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.undo(toast) }
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if model.toast?.id == toast.id { model.toast = nil }
                    }
            }
        }
        .animation(.snappy, value: model.toast)
    }
}
