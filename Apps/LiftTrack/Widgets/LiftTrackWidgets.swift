import SwiftUI
import SystemCore
import WidgetKit

@main
struct LiftTrackWidgets: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
        #if os(iOS)
        SessionLiveActivity()
        #endif
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads timelines when the plan changes. Each entry reads the snapshot for its own
        // day, so the one at midnight turns "Next: Tuesday" into "Today" with the app closed.
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let snapshot = WidgetSnapshot.load()
        completion(
            Timeline(
                entries: [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)],
                policy: .after(midnight)))
    }
}

/// The next session at a glance; tapping it opens Lift Track ready to start.
struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-session", provider: SnapshotProvider()) { entry in
            NextSessionView(snapshot: entry.snapshot.reading(on: Day(entry.date)))
                .widgetURL(URL(string: "lifttrack://start"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Session")
        .description("Your next session, one tap from starting.")
        .supportedFamilies(Self.families)
    }

    /// The Lock Screen's accessory families are the iPhone's and iPad's; the Mac's desktop and Vision
    /// Pro's walls take the small and medium ones.
    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            Text("\(snapshot.title) · \(snapshot.detail)")
        case .accessoryCircular:
            Gauge(value: Double(snapshot.doneThisWeek), in: 0...Double(max(snapshot.plannedThisWeek, 1))) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(snapshot.doneThisWeek)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title).font(.headline).widgetAccentable()
                Text(snapshot.badge ?? snapshot.detail).font(.caption)
                Text(snapshot.exercises.prefix(2).joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
            }
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                summary
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.exercises.prefix(5), id: \.self) { name in
                        Text(name).font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "figure.strengthtraining.traditional").font(.title2).foregroundStyle(.tint)
            Spacer(minLength: 0)
            if let badge = snapshot.badge { Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(.tint) }
            Text(snapshot.title).font(.headline).lineLimit(2)
            Text(snapshot.detail).font(.caption).foregroundStyle(.secondary)
            if let minutes = snapshot.minutes { Text("~\(minutes) min").font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
