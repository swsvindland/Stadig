import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Today's session and a Start button; on a rest day, what's next and "Train anyway".
struct HomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let context = model.context {
                    if let upNext = context.upNext {
                        restDay(upNext: upNext, plan: context.plan)
                    } else if let plan = model.upcoming {
                        today(plan)
                    } else {
                        message("calendar", "Nothing planned today.", "Open Stadig Lift on your iPhone to plan your week.")
                    }
                } else {
                    message("iphone", "Open Stadig Lift on your iPhone to set up.", "Your sessions appear here once it's done.")
                    Button("Try Again", systemImage: "arrow.clockwise") { model.requestContext() }
                        .buttonStyle(.glass)
                }
            }
        }
        .navigationTitle("Stadig Lift")
    }

    private func today(_ plan: SessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let badge = badge(plan) {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.4)), in: .capsule)
            }
            Text(plan.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("About \(plan.estimatedMinutes) min · ^[\(plan.items.count(where: \.isStrength)) exercise](inflect: true)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.finishedToday {
                Label("Done today", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(WatchInk.good)
            }
            Button {
                model.start(plan)
            } label: {
                Label(model.finishedToday ? "Train Again" : "Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .handGestureShortcut(.primaryAction)
            if model.offersFollowing {
                Text("Next in your program, after the session you did on your Watch. Open Stadig Lift on your iPhone to update it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.isStale {
                Text("Planned \(plan.day.date().formatted(.dateTime.weekday(.wide))). Open Stadig Lift on your iPhone to update it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let note = plan.notes.first {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(plan.items.filter(\.isStrength)) { item in
                Label(model.catalog.resolve(item.exerciseID).name, systemImage: item.block.symbol)
                    .font(.footnote)
                    .lineLimit(2)
            }
        }
    }

    private func restDay(upNext: String, plan: SessionPlan?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rest day", systemImage: "moon.zzz.fill")
                .font(.title3.weight(.semibold))
            Text("Next: \(upNext)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let plan {
                Button {
                    model.start(plan)
                } label: {
                    Label("Train Anyway", systemImage: "figure.strengthtraining.traditional")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Text("\(plan.title), about \(plan.estimatedMinutes) min")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func message(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badge(_ plan: SessionPlan) -> String? {
        if plan.deload { return "Deload" }
        if plan.checkIn { return "Check-in" }
        if plan.assessment { return "Assessment" }
        return nil
    }
}
