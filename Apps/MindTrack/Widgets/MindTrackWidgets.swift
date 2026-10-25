import SwiftUI
import SystemCore
import WidgetKit

@main
struct MindTrackWidgets: WidgetBundle {
    var body: some Widget {
        TodayStudyWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MindSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : MindSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads the timeline when the day's plan changes. The entry when the next study
        // day starts (4 a.m. unless changed in the app) reads the snapshot for the new day, so
        // yesterday's session doesn't sit there with the app closed.
        let now = Date()
        let snapshot = MindSnapshot.load()
        let next = snapshot.nextDayStart(after: now)
        completion(
            Timeline(
                entries: [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: next, snapshot: snapshot)],
                policy: .after(next)))
    }
}

/// Today's study at a glance; tapping it opens Stadig Mind ready to start.
struct TodayStudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today-study", provider: SnapshotProvider()) { entry in
            let snapshot = entry.snapshot.reading(on: entry.snapshot.studyDay(entry.date))
            TodayStudyView(snapshot: snapshot)
                .widgetURL(snapshot.link)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Study")
        .description("Today's session, one tap from starting, and your week.")
        .supportedFamilies(Self.families)
    }

    /// The Lock Screen's families exist on iPhone and iPad; the Mac's desktop and Vision Pro take
    /// the system sizes.
    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct TodayStudyView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MindSnapshot

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            Text(snapshot.headline)
        case .accessoryCircular:
            Gauge(value: Double(snapshot.doneThisWeek), in: 0...Double(max(snapshot.plannedThisWeek, 1))) {
                Image(systemName: "brain.head.profile")
            } currentValueLabel: {
                Text("\(snapshot.doneThisWeek)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.headline).font(.headline).lineLimit(2).widgetAccentable()
                Text(weekLine).font(.caption)
            }
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                summary
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.parts.prefix(4), id: \.self) { part in
                        HStack(spacing: 6) {
                            Image(systemName: part.symbol).foregroundStyle(.tint).frame(width: 16)
                            Text(part.title).font(.caption).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(part.minutes) min").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if snapshot.parts.isEmpty {
                        Text(weekLine).font(.caption).foregroundStyle(.secondary)
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
            HStack(spacing: 4) {
                ForEach(badgeSymbols, id: \.self) { symbol in
                    Image(systemName: symbol).font(.title3).foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
            Text(snapshot.phase).font(.caption2.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
            Text(snapshot.headline).font(.headline).lineLimit(3)
            Text(weekLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgeSymbols: [String] {
        switch snapshot.status {
        case .today: snapshot.symbols.isEmpty ? ["brain.head.profile"] : Array(snapshot.symbols.prefix(3))
        case .done: ["checkmark.circle.fill"]
        case .rest: ["moon.zzz.fill"]
        case .paused: ["pause.circle.fill"]
        case .setUp: ["brain.head.profile"]
        }
    }

    private var weekLine: String {
        guard snapshot.status != .setUp, snapshot.plannedThisWeek > 0 else { return "" }
        return "\(snapshot.doneThisWeek) of \(snapshot.plannedThisWeek) this week"
    }
}
