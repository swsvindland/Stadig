import MindEngine
import SwiftUI
import SystemPurchases
import SystemStore

/// Today for the session, Plan for the week and what's next, Progress for the honest measures. In a
/// wide window (iPad, the Mac, Vision Pro) the tabs are a sidebar, with the shelf, your writing and
/// the courses as destinations of their own; an iPhone keeps its three tabs and reaches those from
/// them. A session covers the screen, or on the Mac opens in a window of its own.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var model = model
        Group {
            // The offer ends onboarding, after the first session it runs into: the app opens once
            // it's answered.
            if model.onboarded, model.purchases.firstChoiceDue {
                PaywallView()
            } else if model.onboarded {
                TabView(selection: selection) {
                    Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView() }
                    Tab("Plan", systemImage: "calendar", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                    TabSection("Library") {
                        Tab("Shelf", systemImage: "books.vertical", value: AppTab.shelf) { ShelfDestination() }
                            .tabPlacement(.sidebarOnly)
                        Tab("Writing", systemImage: "doc.richtext", value: AppTab.writing) { WritingDestination() }
                            .tabPlacement(.sidebarOnly)
                        Tab("Courses", systemImage: "square.stack.3d.up", value: AppTab.courses) { CoursesDestination() }
                            .tabPlacement(.sidebarOnly)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else if let arrival = model.arrival, arrival.isWaiting {
                ICloudWaitView(arrival: arrival)
            } else {
                OnboardingView()
            }
        }
        #if os(macOS)
        // The session's own window: opened when one starts (here, from the menu bar or a link), and
        // brought forward if it's behind.
        .onChange(of: model.sessionOpen, initial: true) { _, running in
            if running { openWindow(id: SessionWindow.id) }
        }
        // Settings is a window of its own on the Mac (⌘,): anything asking for it opens that.
        .onChange(of: model.showSettings, initial: true) { _, show in
            guard show else { return }
            model.showSettings = false
            openSettings()
        }
        // So is the unlock (`PaywallView.windowID`).
        .onChange(of: model.showPaywall, initial: true) { _, show in
            guard show else { return }
            model.showPaywall = false
            openWindow(id: PaywallView.windowID)
        }
        #else
        .cover(isPresented: Binding(get: { model.sessionOpen }, set: { if !$0 { model.endSession() } })) {
            SessionView()
            .environment(model)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $model.showPaywall) {
            PaywallView()
        }
        #endif
        .sheet(item: $model.episodeLanguage) { language in
            EpisodeSheet(language: language)
        }
        .sheet(isPresented: shelfSheet) {
            NavigationStack { ShelfView() }
        }
        // In a wide window the shelf is in the sidebar: a request for it (an action on Today, Add a
        // Book…) goes there. A narrow window changes nothing in the model, so two windows of
        // different widths never undo each other.
        .onChange(of: model.showShelf, initial: true) { openShelfInSidebar() }
        .onChange(of: model.addingBook) { openShelfInSidebar() }
        .onChange(of: sizeClass) { openShelfInSidebar() }
        // Another app or Shortcuts opening a link: this window handles it rather than a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 540)
        #endif
    }

    /// The tabs are a sidebar: iPad, the Mac and Vision Pro at a regular width. An iPhone's tab bar
    /// has no room for the destinations past its three.
    var wide: Bool { sizeClass != .compact && !Platform.isPhone }

    /// The tab shown: the destination itself in a wide window, or in a narrow one the tab that
    /// reaches it (an iPhone, an iPad in a narrow split).
    var selection: Binding<AppTab> {
        Binding(get: { wide ? model.tab : model.tab.tabBarFallback }, set: { model.tab = $0 })
    }

    /// The shelf as a sheet over the tabs, in a narrow window: asked for, or chosen as a destination.
    var shelfSheet: Binding<Bool> {
        Binding(
            get: { !wide && (model.showShelf || model.addingBook || model.tab == .shelf) },
            set: { shown in
                guard !shown else { return }
                model.showShelf = false
                model.addingBook = false
                if model.tab == .shelf { model.tab = .today }
            })
    }

    func openShelfInSidebar() {
        guard wide, model.showShelf || model.addingBook else { return }
        model.showShelf = false
        model.tab = .shelf
    }
}
