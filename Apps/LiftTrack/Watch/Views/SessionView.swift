import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Screens pushed over the current step.
enum SessionRoute: Hashable {
    case rate(SetDraft)
    /// Reps done: after a rep-out (no rating) or a miss.
    case reps(SetDraft, SetRating?)
}

/// The session in progress: one face for whatever comes next, and to its left, a swipe away as in
/// the Workout app, the session's controls: the exercise list, End, Continue on iPhone and Discard.
struct SessionView: View {
    @Environment(WatchModel.self) private var model
    @State private var path: [SessionRoute] = []
    @State private var page = Page.step
    @State private var showingList = false
    @State private var confirmingDiscard = false

    private enum Page { case controls, step }

    var body: some View {
        TabView(selection: $page) {
            if model.step != .finish {
                SessionControls(
                    exercises: { showingList = true },
                    end: {
                        page = .step
                        model.wrapUp()
                    },
                    discard: { confirmingDiscard = true }
                )
                .tag(Page.controls)
            }
            NavigationStack(path: $path) {
                step
                    .navigationDestination(for: SessionRoute.self) { route in
                        switch route {
                        case .rate(let draft): RatingView(draft: draft) { path.append($0) }
                        case .reps(let draft, let rating): RepsView(draft: draft, rating: rating)
                        }
                    }
            }
            .tag(Page.step)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Logging moves the session on; whatever was pushed over the old step goes with it. So does a
        // rating left open when the phone puts another exercise first, so it can't land on that one.
        .onChange(of: model.step) {
            path.removeAll()
            page = .step
        }
        .onChange(of: model.currentItemID) { path.removeAll() }
        .sheet(isPresented: $showingList) {
            NavigationStack {
                ExerciseListView {
                    showingList = false
                    page = .step
                }
            }
        }
        .confirmationDialog("Discard this session? Nothing is saved.", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.discard() }
        }
        #if DEBUG
        .task {
            // The stack registers its destinations after the first pass.
            try? await Task.sleep(for: .milliseconds(500))
            openDebugRoute()
        }
        #endif
    }

    @ViewBuilder private var step: some View {
        switch model.step {
        case .rest:
            RestView()
        case .set(let item, let set):
            SetView(item: item, set: set, done: setDone, rate: { path.append(.rate($0)) })
                .id(stepID(item, set))
        case .timed(let item, let set):
            TimedView(item: item, set: set)
                .id(stepID(item, set))
        case .conditioning(let item):
            ConditioningView(item: item)
                .id(stepID(item, 0))
        case .heat(let item):
            HeatOnPhoneView(item: item)
                .id(stepID(item, 0))
        case .finish, nil:
            FinishView()
        }
    }

    private func stepID(_ item: Int, _ set: Int) -> String {
        "\(model.live?.items[item].id.uuidString ?? "")-\(set)"
    }

    /// The set face's band. Warm-ups and timed sets log straight away; rep-outs ask for the reps; the
    /// rest log Just right, the rating the phone's dock fills too (Easy and Missed are a tap away).
    private func setDone(_ draft: SetDraft) {
        guard let live = model.live else { return }
        let prescription = live.items[draft.item].sets[draft.set].prescription
        if prescription.kind == .warmup || draft.seconds != nil {
            model.log(item: draft.item, set: draft.set, reps: draft.reps, loadKg: draft.loadKg, rating: nil, seconds: draft.seconds)
        } else if prescription.kind == .repOut {
            path.append(.reps(draft, nil))
        } else {
            model.log(item: draft.item, set: draft.set, reps: draft.reps, loadKg: draft.loadKg, rating: .orange)
        }
    }

    #if DEBUG
    private func openDebugRoute() {
        if model.debugRoute == "controls" {
            model.debugRoute = nil
            page = .controls
            return
        }
        guard model.debugRoute == "rating", case .set(let item, let set) = model.step, let live = model.live else { return }
        model.debugRoute = nil
        let prescription = live.items[item].sets[set].prescription
        path = [.rate(SetDraft(item: item, set: set, loadKg: prescription.loadKg, reps: prescription.targetReps))]
    }
    #endif
}

/// The session's controls, left of its face: the exercise list, End, Continue on iPhone (when the
/// phone runs it) and Discard, each a round button with its word under it.
struct SessionControls: View {
    @Environment(WatchModel.self) private var model
    let exercises: () -> Void
    let end: () -> Void
    let discard: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                control("Exercises", systemImage: "list.bullet", action: exercises)
                control("End", systemImage: "xmark", tint: WatchInk.bad, action: end)
                if model.phoneLed {
                    // Heart rate stops here; the session carries on on the phone.
                    control("On iPhone", systemImage: "iphone", action: model.stopCompanion)
                        .accessibilityLabel("Continue on iPhone")
                }
                control("Discard", systemImage: "trash", action: discard)
            }
            .padding(.top, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("session.controls")
    }

    private func control(_ title: String, systemImage: String, tint: Color = WatchInk.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(tint == WatchInk.text ? WatchInk.surface : tint.opacity(0.2), in: .rect(cornerRadius: 26, style: .continuous))
                Text(title)
                    .faceFont(13, weight: .semibold)
                    .foregroundStyle(WatchInk.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The sauna or steam room in a session the iPhone runs: the minutes follow the thermometer, which is
/// read and logged on the phone. The session moves on here once the phone has it.
struct HeatOnPhoneView: View {
    @Environment(WatchModel.self) private var model
    let item: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.title2)
                    .foregroundStyle(WatchInk.ok)
                    .accessibilityHidden(true)
                Text(model.exercise(item).name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Log it on your iPhone: the thermometer's reading sets the minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Skip", systemImage: "forward.end") { model.skip(item: item) }
                    .buttonStyle(.glass)
            }
        }
    }
}

/// A short confirmation from the model, such as heart rate ending a rest early.
struct NoticeRow: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            Label(notice.text, systemImage: notice.symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.tint(WatchInk.good.opacity(0.35)), in: .capsule)
                .transition(.opacity)
        }
    }
}
