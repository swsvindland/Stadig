import LiftEngine
import SwiftUI
import SystemCore

/// Screens pushed over the current step.
enum SessionRoute: Hashable {
    case rate(SetDraft)
    /// Reps done: after a rep-out (no rating) or a miss.
    case reps(SetDraft, SetRating?)
}

/// The session in progress: one screen for whatever comes next, the exercise list and the
/// end-or-discard options in the toolbar.
struct SessionView: View {
    @Environment(WatchModel.self) private var model
    @State private var path: [SessionRoute] = []
    @State private var showingList = false
    @State private var showingOptions = false
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack(path: $path) {
            step
                .toolbar {
                    if model.step != .finish {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Exercises", systemImage: "list.bullet") { showingList = true }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Options", systemImage: "ellipsis") { showingOptions = true }
                        }
                    }
                }
                .navigationDestination(for: SessionRoute.self) { route in
                    switch route {
                    case .rate(let draft): RatingView(draft: draft)
                    case .reps(let draft, let rating): RepsView(draft: draft, rating: rating)
                    }
                }
        }
        // Logging moves the session on; whatever was pushed over the old step goes with it.
        .onChange(of: model.step) { path.removeAll() }
        .sheet(isPresented: $showingList) {
            NavigationStack { ExerciseListView { showingList = false } }
        }
        .confirmationDialog("Session", isPresented: $showingOptions) {
            Button("End Session") { model.wrapUp() }
            Button("Discard Session", role: .destructive) { confirmingDiscard = true }
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
            SetView(item: item, set: set, done: setDone)
                .id(stepID(item, set))
        case .timed(let item, let set):
            TimedView(item: item, set: set)
                .id(stepID(item, set))
        case .conditioning(let item):
            ConditioningView(item: item)
                .id(stepID(item, 0))
        case .finish, nil:
            FinishView()
        }
    }

    private func stepID(_ item: Int, _ set: Int) -> String {
        "\(model.live?.items[item].id.uuidString ?? "")-\(set)"
    }

    /// Warm-ups and timed sets log straight away; rep-outs ask for the reps; the rest are rated.
    private func setDone(_ draft: SetDraft) {
        guard let live = model.live else { return }
        let prescription = live.items[draft.item].sets[draft.set].prescription
        if prescription.kind == .warmup || draft.seconds != nil {
            model.log(item: draft.item, set: draft.set, reps: draft.reps, loadKg: draft.loadKg, rating: nil, seconds: draft.seconds)
        } else if prescription.kind == .repOut {
            path.append(.reps(draft, nil))
        } else {
            path.append(.rate(draft))
        }
    }

    #if DEBUG
    private func openDebugRoute() {
        guard model.debugRoute == "rating", case .set(let item, let set) = model.step, let live = model.live else { return }
        model.debugRoute = nil
        let prescription = live.items[item].sets[set].prescription
        path = [.rate(SetDraft(item: item, set: set, loadKg: prescription.loadKg, reps: prescription.targetReps))]
    }
    #endif
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
                .glassEffect(.regular.tint(.green.opacity(0.35)), in: .capsule)
                .transition(.opacity)
        }
    }
}
