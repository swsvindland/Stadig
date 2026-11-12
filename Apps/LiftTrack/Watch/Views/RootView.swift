import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

/// Home, the session in progress, or the summary of the one just finished.
struct RootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if let summary = model.summary {
            NavigationStack { SummaryView(summary: summary) }
        } else if model.session != nil {
            SessionView()
        } else if model.companionSince != nil {
            CompanionView()
        } else {
            NavigationStack { HomeView() }
        }
    }
}

/// Heart rate for a session running on the iPhone: the reading, its zone, and a way to stop.
struct CompanionView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        let zones = model.context?.zones ?? HeartRateZones.estimated(age: nil, resting: nil)
        VStack(spacing: 6) {
            if let bpm = model.workout.heartRate {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(WatchInk.bad).symbolEffect(.pulse)
                    Text("\(Int(bpm))").font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Text("Zone \(zones.zone(for: bpm))").font(.headline).foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Finding your heart rate").font(.footnote).foregroundStyle(.secondary)
            }
            if let since = model.companionSince {
                Text(since, style: .timer).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Until the phone's session arrives, to log into.
            Text("Getting your iPhone session").font(.caption2).foregroundStyle(.tertiary)
            Button("Stop", systemImage: "stop.fill", role: .destructive) { model.stopCompanion() }
                .padding(.top, 4)
        }
        .padding()
    }
}
