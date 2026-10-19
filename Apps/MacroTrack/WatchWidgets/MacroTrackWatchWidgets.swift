import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

@main
struct MacroTrackWatchWidgets: WidgetBundle {
    var body: some Widget {
        CaloriesLeftWidget()
        ProteinLeftWidget()
        TodayWidget()
    }
}

/// Calories left on the watch face, from the snapshot the Watch app writes.
struct CaloriesLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CaloriesLeft", provider: SnapshotProvider()) { entry in
            MacroComplicationEntry(macro: .kcal, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Calories Left")
        .description("What's left of today's calories.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// Protein left on the watch face.
struct ProteinLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProteinLeft", provider: SnapshotProvider()) { entry in
            MacroComplicationEntry(macro: .protein, snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Protein Left")
        .description("What's left of today's protein.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// Both at once, for the Smart Stack.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: SnapshotProvider()) { entry in
            TodayStackView(snapshot: entry.snapshot)
                .containerBackground(Color.accentColor.opacity(0.25).gradient, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Calories and protein left today.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WristSnapshot
}

/// The app reloads the timelines whenever the snapshot changes. A second entry at midnight starts
/// the new day at nothing eaten, with the Watch app closed.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample(on: .today))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview ? .sample(on: Day(now)) : WristSnapshotFile.load().shown(on: Day(now))
        completion(SnapshotEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WristSnapshotFile.load()
        let tomorrow = Day(now).adding(days: 1)
        // The next calendar day, not 24 hours on, which misses midnight the days the clocks change.
        let entries = [
            SnapshotEntry(date: now, snapshot: snapshot.shown(on: Day(now))),
            SnapshotEntry(date: tomorrow.date(), snapshot: snapshot.shown(on: tomorrow)),
        ]
        completion(WidgetKit.Timeline(entries: entries, policy: .never))
    }
}

/// The complication for the family the face asks for.
struct MacroComplicationEntry: View {
    @Environment(\.widgetFamily) private var family
    let macro: ComplicationMacro
    let snapshot: WristSnapshot

    var body: some View { MacroComplication(macro: macro, snapshot: snapshot, family: family) }
}
