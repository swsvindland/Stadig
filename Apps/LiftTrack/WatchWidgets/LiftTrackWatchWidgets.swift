import SwiftUI
import WidgetKit

@main
struct LiftTrackWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
    }
}

/// Today's session (or what's next) on the watch face, from the snapshot the Watch app writes.
struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: SnapshotProvider()) { entry in
            NextSessionView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Session")
        .description("Today's Lift Track session, or what's next.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

/// One entry; the app reloads timelines whenever the snapshot changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    /// "Upper A · 60 min" or "Rest day · Next: …", for the line under the title.
    private var line: String {
        [snapshot.badge, snapshot.detail, snapshot.minutes.map { "\($0) min" }].compactMap(\.self).joined(separator: " · ")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(snapshot.title, systemImage: "dumbbell.fill")
                .font(.headline)
                .widgetAccentable()
            Text(line)
                .font(.caption)
            if !snapshot.exercises.isEmpty {
                Text(snapshot.exercises.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var circular: some View {
        if snapshot.plannedThisWeek > 0 {
            Gauge(value: Double(min(snapshot.doneThisWeek, snapshot.plannedThisWeek)), in: 0...Double(snapshot.plannedThisWeek)) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(snapshot.doneThisWeek)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("\(snapshot.doneThisWeek) of \(snapshot.plannedThisWeek) sessions this week")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "dumbbell.fill")
                        .font(.body)
                        .widgetAccentable()
                    if let minutes = snapshot.minutes {
                        Text("\(minutes)m").font(.caption2.monospacedDigit())
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.title), \(line)")
        }
    }

    private var inline: some View {
        Label(snapshot.minutes.map { "\(snapshot.title) · \($0) min" } ?? snapshot.title, systemImage: "dumbbell.fill")
    }

    private var corner: some View {
        Image(systemName: "dumbbell.fill")
            .font(.title3)
            .widgetAccentable()
            .widgetLabel(snapshot.minutes.map { "\(snapshot.title) · \($0)m" } ?? snapshot.title)
            .accessibilityLabel("\(snapshot.title), \(line)")
    }
}
