import NutritionEngine
import SwiftUI

/// Today to log, Plan for the phase and targets, Progress for the trend. Logging is one tap away
/// from every tab, in the bar above the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    Tab("Today", systemImage: "fork.knife", value: AppTab.today) { TodayView() }
                    Tab("Plan", systemImage: "map", value: AppTab.plan) { PlanView() }
                    Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressTab() }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory { QuickLogBar() }
                .toastOverlay(bottomPadding: 130)
            } else {
                OnboardingView()
            }
        }
        // Closing it drops a picked time (the model does that), so later one-tap logs are now.
        .sheet(item: $model.logger) { mode in
            LoggerSheet(start: mode)
        }
        .sheet(isPresented: $model.showWeighIn) {
            WeighInSheet()
        }
        .sheet(isPresented: $model.showSupplements) {
            SupplementsView()
        }
        .sheet(isPresented: $model.showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $model.showPaywall) {
            PaywallView()
        }
    }
}

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
