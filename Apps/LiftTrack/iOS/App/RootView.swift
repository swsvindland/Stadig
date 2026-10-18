import SwiftUI
import ExerciseLibrary
import LiftEngine

/// Today to train, Plan for the block, Progress for the stats, Body for physique.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    Tab("Today", systemImage: "figure.strengthtraining.traditional", value: AppTab.today) { TodayView() }
                    Tab("Plan", systemImage: "calendar", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                    Tab("Body", systemImage: "figure.arms.open", value: AppTab.body) { BodyView() }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: model.live != nil && !model.showSession) {
                    SessionAccessory()
                }
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(isPresented: $model.showSession) {
            SessionScreen()
        }
        .sheet(item: $model.finished) { record in
            SessionSummaryView(record: record)
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
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
                Spacer()
                Text("Resume").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.accessory")
    }
}
