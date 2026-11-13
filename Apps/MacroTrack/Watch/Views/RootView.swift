import NutritionEngine
import SwiftUI
import SystemCore

/// The pages, top to bottom: the Digital Crown moves between them.
enum WristPage: String, Hashable {
    case today, fast, logAgain, water, supplements
}

/// Screens pushed over the pages.
enum WristRoute: Hashable {
    case weighIn
}

/// Today first, then Log Again, water and supplements when the person tracks them; the weigh-in
/// is a tap away on Today. Every log shows a moment of Undo.
struct RootView: View {
    @Environment(WristModel.self) private var model
    @Binding var page: WristPage
    @Binding var path: [WristRoute]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: WristRoute.self) { route in
                    switch route {
                    case .weighIn:
                        if let today = model.today {
                            WeighInView(dial: today.dial, weighedToday: today.weighedToday, trendKg: today.trendKg)
                        }
                    }
                }
        }
        .overlay(alignment: .bottom) { ToastView() }
    }

    @ViewBuilder private var content: some View {
        if let today = model.today {
            TabView(selection: $page) {
                TodayPage(today: today).tag(WristPage.today)
                if today.tracksMealTiming {
                    FastPage(today: today).tag(WristPage.fast)
                }
                LogAgainPage(today: today, showing: page == .logAgain).tag(WristPage.logAgain)
                if let water = today.water {
                    WaterPage(water: water, glasses: today.glasses).tag(WristPage.water)
                }
                if today.dosesToday > 0 {
                    SupplementsPage(doses: today.doses, later: today.laterDoses).tag(WristPage.supplements)
                }
            }
            .tabViewStyle(.verticalPage)
        } else if model.loaded {
            SetUpView()
        } else {
            ProgressView()
                .accessibilityLabel("Loading")
        }
    }
}

/// Before Stadig Macro is set up on a phone, iPad or Mac, or before that setup has synced here.
struct SetUpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "fork.knife.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Set up Stadig Macro on your iPhone")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your targets and usual foods appear here once it syncs over iCloud.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("setUp.message")
        }
        .navigationTitle("Stadig Macro")
    }
}

/// "Logged Oats · 600 kcal" with Undo, for a few seconds after each log.
struct ToastView: View {
    @Environment(WristModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 6) {
                Text(toast.message)
                    .font(.footnote)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("toast.message")
                Button("Undo") { model.undo(toast) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
                    .fixedSize()
                    .accessibilityIdentifier("toast.undo")
                    .accessibilityLabel("Undo: \(toast.message)")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                #if DEBUG
                // `-demoLog`'s confirmation stays, to be looked at.
                if LaunchOptions.current.has("-demoLog") { return }
                #endif
                try? await Task.sleep(for: .seconds(4))
                if model.toast?.id == toast.id { withAnimation { model.toast = nil } }
            }
        }
    }
}
