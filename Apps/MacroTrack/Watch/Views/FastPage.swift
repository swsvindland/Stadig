import NutritionEngine
import SwiftUI
import SystemCore

/// The running fast as a ring toward its goal with its phase, and End; or the time since the last
/// meal, and a fast to start with one tap (up to a day: longer ones start on the phone).
struct FastPage: View {
    @Environment(WristModel.self) private var model
    let today: WristToday

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let status = today.fast {
                    TimelineView(.periodic(from: status.fast.start, by: 60)) { context in
                        let now = Fasting.status(status.fast, now: context.date)
                        ring(hours: now.hours, of: status.fast.goalHours, label: WristFormat.duration(now.elapsed), caption: now.phase.title)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(WristFormat.duration(now.elapsed)) of a \(WristFormat.hours(status.fast.goalHours)) fast, \(now.phase.title)"
                            )
                            .accessibilityIdentifier("fast.ring")
                    }
                    Button("End Fast", role: .destructive) { model.endFast() }
                        .accessibilityIdentifier("fast.end")
                } else {
                    if let last = today.lastMealEnd {
                        TimelineView(.periodic(from: last, by: 60)) { context in
                            let hours = context.date.timeIntervalSince(last) / 3600
                            ring(hours: hours, of: 5, label: WristFormat.duration(hours * 3600), caption: "since you ate")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(WristFormat.duration(hours * 3600)) since your last meal")
                                .accessibilityIdentifier("fast.since")
                        }
                    }
                    Text("Start a fast").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach([13.0, 16, 18], id: \.self) { goal in
                            Button(WristFormat.hours(goal)) { model.startFast(goalHours: goal) }
                                .font(.footnote.weight(.semibold))
                                .accessibilityIdentifier("fast.start.\(Int(goal))")
                        }
                    }
                    Button("24 h") { model.startFast(goalHours: 24) }
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("fast.start.24")
                }
            }
        }
        .navigationTitle(today.fast == nil ? "Meal Timing" : "Fasting")
    }

    func ring(hours: Double, of goal: Double, label: String, caption: String) -> some View {
        ZStack {
            Circle().stroke(Color.teal.opacity(0.2), lineWidth: 8)
            Circle().trim(from: 0, to: min(1, hours / max(1, goal))).stroke(Color.teal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.title3.weight(.semibold).monospacedDigit()).minimumScaleFactor(0.6)
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: 110, height: 110)
    }
}
