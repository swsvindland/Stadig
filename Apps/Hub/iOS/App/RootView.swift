import SwiftUI
import SystemCore
import SystemStore

/// Today for what's next, Week for the shape of it, Rhythm for the normal week it fits around. In a
/// wide window the tabs are a sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView() }
                    Tab("Week", systemImage: "calendar", value: AppTab.week) { WeekView() }
                    Tab("Rhythm", systemImage: "repeat", value: AppTab.rhythm) { RhythmView() }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else if let arrival = model.arrival, arrival.isWaiting {
                ICloudWaitView(arrival: arrival)
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $model.showPlansChanged) {
            PlansChangedView()
        }
        .alert(
            model.missingApp.map { "\($0.displayName) isn't on this device" } ?? "",
            isPresented: Binding(get: { model.missingApp != nil }, set: { if !$0 { model.missingApp = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text("It stays on your plan, and you can open it where you have it.")
        }
        // Another app or Shortcuts opening a link: this window handles it rather than a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 540)
        #endif
    }
}
