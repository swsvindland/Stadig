import MindEngine
import SwiftUI

/// Today for the session, Plan for the week and what's next, Progress for the honest measures.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView() }
                    Tab("Plan", systemImage: "calendar", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { model.run != nil }, set: { if !$0 { model.endSession() } })) {
            SessionView()
                .environment(model)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $model.showPaywall) {
            PaywallView()
        }
        .sheet(item: $model.episodeLanguage) { language in
            EpisodeSheet(language: language)
        }
        .sheet(isPresented: $model.showShelf) {
            NavigationStack { ShelfView() }
        }
    }
}
