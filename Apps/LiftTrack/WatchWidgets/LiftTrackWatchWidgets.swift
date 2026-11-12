import SwiftUI
import SystemCore
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
            NextSessionView(snapshot: entry.snapshot.shown(on: Day(entry.date)))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Session")
        .description("Today's Stadig Lift session, or what's next.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

/// The app reloads timelines whenever the snapshot changes. A second entry at midnight shows a day's
/// plan as stale once that day is over, with the Watch app closed.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        if snapshot.day != nil, let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View { NextSessionComplication(snapshot: snapshot, family: family) }
}

/// The complication in the family given, in Stadig's look: an accent eyebrow over the session's name
/// as the hero, and numbers set heavy and tabular. Only the eyebrow and the symbols are accentable, so
/// a tinted face keeps the name in its plain colour.
struct NextSessionComplication: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    /// "Upper A · 60 min" or "Rest day · Next: …", for VoiceOver.
    private var line: String {
        [snapshot.badge, snapshot.detail, snapshot.minutes.map { "\($0) min" }].compactMap(\.self).joined(separator: " · ")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line)
                .eyebrow()
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text(snapshot.title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.6)
                .minimumScaleFactor(0.7)
            if !snapshot.exercises.isEmpty {
                Text(snapshot.exercises.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if snapshot.plannedThisWeek > 0 {
                WeekStrip(done: snapshot.doneThisWeek, planned: snapshot.plannedThisWeek)
                    .padding(.top, 4)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(snapshot.title), \(line)"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: snapshot.minutes == nil ? 20 : 12, weight: .semibold))
                    .widgetAccentable()
                if let minutes = snapshot.minutes {
                    Text("\(minutes)").numeral(20)
                    Text("min").eyebrow(size: 8).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(snapshot.title), \(line)"))
    }

    private var inline: some View {
        Label(snapshot.minutes.map { "\(snapshot.title) · \($0) min" } ?? snapshot.title, systemImage: "dumbbell.fill")
    }

    private var corner: some View {
        Image(systemName: "dumbbell.fill")
            .font(.title3)
            .widgetAccentable()
            .widgetLabel(snapshot.minutes.map { "\(snapshot.title) · \($0)m" } ?? snapshot.title)
            .accessibilityLabel(Text("\(snapshot.title), \(line)"))
    }
}
