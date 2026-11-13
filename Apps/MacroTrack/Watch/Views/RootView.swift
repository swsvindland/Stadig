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
        .overlay { ToastView() }
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

/// After each log, for a few seconds: food takes the whole screen (`LoggedFace`); anything else is
/// "Took Creatine" with Undo along the foot.
struct ToastView: View {
    @Environment(WristModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            Group {
                if let logged = toast.logged {
                    LoggedFace(toast: toast, logged: logged, seconds: Self.seconds(toast))
                        .transition(.opacity)
                } else {
                    capsule(toast)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: toast.id) {
                #if DEBUG
                // `-demoLog`'s confirmation stays, to be looked at.
                if LaunchOptions.current.has("-demoLog") { return }
                #endif
                try? await Task.sleep(for: .seconds(Self.seconds(toast)))
                if model.toast?.id == toast.id { withAnimation { model.toast = nil } }
            }
        }
    }

    /// Food stays a moment longer: the face has more to read.
    static func seconds(_ toast: WristToast) -> Double { toast.logged == nil ? 4 : 5 }

    private func capsule(_ toast: WristToast) -> some View {
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
    }
}

/// Food just logged from the wrist, the whole screen for a few seconds, as the design draws it:
/// what went in, each with its marker and calories, calories left before and after, and Tap to
/// undo across the foot, a line over it running out while the chance lasts. A tap anywhere else
/// puts it away; nothing needs confirming.
struct LoggedFace: View {
    @Environment(WristModel.self) private var model
    let toast: WristToast
    let logged: LoggedFood
    let seconds: Double
    @State private var spent = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Logged").faceFont(13).foregroundStyle(WristInk.text2)
                }
                .faceTopLine()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(logged.items.prefix(WristFace.small ? 2 : 3)) { item in
                        row(item)
                    }
                    if logged.items.count > (WristFace.small ? 2 : 3) {
                        Text("and \(logged.items.count - (WristFace.small ? 2 : 3)) more").faceFont(13).foregroundStyle(WristInk.text2)
                    }
                }
                .padding(.top, WristFace.small ? 6 : 11)
                Spacer(minLength: 4)
                if let before = logged.leftBefore, let after = logged.leftAfter {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(WristFormat.whole(abs(before))).foregroundStyle(WristInk.text3)
                        Text("→ \(WristFormat.whole(abs(after)))").foregroundStyle(Color.accentColor)
                        Text(after <= -1 ? "over" : "left").font(.system(size: 13)).foregroundStyle(WristInk.text2)
                    }
                    .font(.system(size: 19 * min(1, WristFace.scale), weight: .bold).monospacedDigit())
                    .tracking(-0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 11)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(WristFormat.whole(abs(after))) kcal \(after <= -1 ? "over" : "left")")
                }
            }
            .padding(.leading, WristFace.margin)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Button {
                model.undo(toast)
            } label: {
                Label("Tap to undo", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WristInk.text)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, minHeight: WristFace.small ? 46 : 52, maxHeight: WristFace.small ? 46 : 52)
                    .background(WristInk.raised)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(WristInk.text2)
                            .frame(height: 3)
                            .scaleEffect(x: spent ? 0 : 1, anchor: .leading)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toast.undo")
            .accessibilityLabel("Undo: \(toast.message)")
        }
        .background(Color.black)
        .contentShape(.rect)
        .onTapGesture { withAnimation { model.toast = nil } }
        .ignoresSafeArea()
        .accessibilityIdentifier("toast.message")
        .onAppear { withAnimation(.linear(duration: seconds)) { spent = true } }
    }

    /// The food's marker on its tile, its name over the amount, and its calories.
    private func row(_ item: LoggedFood.Item) -> some View {
        HStack(spacing: 10) {
            Text(item.marker)
                .font(.system(size: 21))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 38, height: 38)
                .background(WristInk.surface, in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.system(size: 16, weight: .semibold)).tracking(-0.16)
                Text(item.amount).faceFont(13).foregroundStyle(WristInk.text2)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(WristFormat.whole(item.kcal))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.amount), \(WristFormat.kcal(item.kcal))")
    }
}
