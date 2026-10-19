import MindEngine
import SwiftUI

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
            if model.onboarded {
                TabView(selection: $model.tab) {
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
            } else {
                OnboardingView()
            }
        }
        #if os(macOS)
        // The session's own window: opened when one starts (here, from the menu bar or a link), and
        // brought forward if it's behind.
        .onChange(of: model.run != nil, initial: true) { _, running in
            if running { openWindow(id: SessionWindow.id) }
        }
        // Settings is a window of its own on the Mac (⌘,): anything asking for it opens that.
        .onChange(of: model.showSettings, initial: true) { _, show in
            guard show else { return }
            model.showSettings = false
            openSettings()
        }
        #else
        .cover(isPresented: Binding(get: { model.run != nil }, set: { if !$0 { model.endSession() } })) {
            SessionView()
            .environment(model)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        #endif
        .sheet(isPresented: $model.showPaywall) {
            PaywallView()
        }
        .sheet(item: $model.episodeLanguage) { language in
            EpisodeSheet(language: language)
        }
        .sheet(isPresented: shelfSheet) {
            NavigationStack { ShelfView() }
        }
        .onChange(of: model.tab, initial: true) { fitDestination() }
        .onChange(of: model.showShelf, initial: true) { fitDestination() }
        .onChange(of: model.addingBook) { fitDestination() }
        .onChange(of: sizeClass) { fitDestination() }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 540)
        #endif
    }

    /// The tabs are a sidebar: iPad, the Mac and Vision Pro at a regular width. An iPhone's tab bar
    /// has no room for the destinations past its three.
    var wide: Bool { sizeClass != .compact && !Platform.isPhone }

    /// The shelf opens as a sheet over the tabs on an iPhone; in a wide window it's in the sidebar.
    var shelfSheet: Binding<Bool> {
        Binding(get: { model.showShelf && !wide }, set: { model.showShelf = $0 })
    }

    /// Puts what was asked for where this width keeps it: the shelf's sheet becomes its sidebar
    /// destination in a wide window, and a sidebar destination falls back to the tab that reaches it
    /// when the window narrows (an iPad in Split View, say) or on an iPhone.
    func fitDestination() {
        if wide {
            if model.showShelf || model.addingBook {
                model.showShelf = false
                model.tab = .shelf
            }
        } else {
            if model.addingBook { model.showShelf = true }
            guard !model.tab.inTabBar else { return }
            switch model.tab {
            case .shelf:
                model.tab = .today
                model.showShelf = true
            case .writing: model.tab = .progress
            case .courses: model.tab = .plan
            case .today, .plan, .progress: break
            }
        }
    }
}
