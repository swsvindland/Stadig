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
        FastComplicationWidget()
    }
}

/// The fast, or the time since the last meal, on the watch face.
struct FastComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Fast", provider: FastSnapshotProvider()) { entry in
            FastComplicationEntry(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Fasting")
        .description("How long since you last ate, or into a fast.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// Entries every half hour and at each phase and the goal for the next day, so the ring moves on
/// with the Watch app closed.
struct FastSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? Self.sample : WristSnapshotFile.load().shown(at: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WristSnapshotFile.load()
        guard let from = snapshot.fastStart ?? snapshot.lastMealEnd else {
            completion(WidgetKit.Timeline(entries: [SnapshotEntry(date: now, snapshot: snapshot)], policy: .never))
            return
        }
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = stride(from: 0.0, to: 24 * 3600, by: 1800).map { now.addingTimeInterval($0) }
        dates += FastPhase.allCases.map { from.addingTimeInterval($0.startHours * 3600) }
        if let goal = snapshot.fastGoalHours { dates.append(from.addingTimeInterval(goal * 3600)) }
        // A meal logged for later ends the fast at its time.
        dates += snapshot.laterDates(after: now, before: horizon)
        let entries = Set(dates.filter { $0 >= now && $0 <= horizon }).sorted().map { SnapshotEntry(date: $0, snapshot: snapshot.shown(at: $0)) }
        completion(WidgetKit.Timeline(entries: entries, policy: .after(horizon)))
    }

    /// Fourteen hours into a sixteen-hour fast.
    static var sample: WristSnapshot {
        var sample = WristSnapshot.sample(on: .today)
        sample.fastStart = Date().addingTimeInterval(-14 * 3600)
        sample.fastGoalHours = 16
        return sample
    }
}

struct FastComplicationEntry: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WristSnapshot
    let date: Date

    var body: some View { FastComplication(snapshot: snapshot, date: date, family: family) }
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

/// The app reloads the timelines whenever the snapshot changes. An entry for each food logged for
/// later today counts it at its time, one at midnight starts the new day at nothing eaten, and the
/// timeline is read again just after, for that day's food, all with the Watch app closed.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample(on: .today))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview ? .sample(on: Day(now)) : WristSnapshotFile.load().shown(at: now)
        completion(SnapshotEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WristSnapshotFile.load()
        let timeline = snapshot.timeline(from: Date())
        completion(
            WidgetKit.Timeline(
                entries: timeline.dates.map { SnapshotEntry(date: $0, snapshot: snapshot.shown(at: $0)) }, policy: .after(timeline.reload)))
    }
}

/// The complication for the family the face asks for.
struct MacroComplicationEntry: View {
    @Environment(\.widgetFamily) private var family
    let macro: ComplicationMacro
    let snapshot: WristSnapshot

    var body: some View { MacroComplication(macro: macro, snapshot: snapshot, family: family) }
}
