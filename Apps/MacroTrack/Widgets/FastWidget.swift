import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

struct FastEntry: TimelineEntry {
    let date: Date
    let snapshot: MacroSnapshot
}

/// An entry now, at each new phase and the goal, and every half hour between, so the ring and the
/// phase move on without the app.
struct FastProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastEntry { FastEntry(date: Date(), snapshot: .fastSample) }

    func getSnapshot(in context: Context, completion: @escaping (FastEntry) -> Void) {
        completion(FastEntry(date: Date(), snapshot: context.isPreview ? .fastSample : MacroSnapshot.load().current()))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<FastEntry>) -> Void) {
        let now = Date()
        let snapshot = MacroSnapshot.load()
        guard let from = snapshot.fastStart ?? snapshot.lastMealEnd else {
            completion(WidgetKit.Timeline(entries: [FastEntry(date: now, snapshot: snapshot)], policy: .never))
            return
        }
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = stride(from: 0.0, to: 24 * 3600, by: 1800).map { now.addingTimeInterval($0) }
        dates += FastPhase.allCases.map { from.addingTimeInterval($0.startHours * 3600) }
        if let goal = snapshot.fastGoalHours { dates.append(from.addingTimeInterval(goal * 3600)) }
        // A meal logged for later ends the fast at its time.
        dates += snapshot.laterDates(after: now, before: horizon)
        let entries = Set(dates.filter { $0 >= now && $0 <= horizon }).sorted().map { FastEntry(date: $0, snapshot: snapshot.current(now: $0)) }
        completion(WidgetKit.Timeline(entries: entries, policy: .after(horizon)))
    }
}

/// How long since the last meal, or into a fast, with its phase: Zero's circle on the Lock Screen.
struct FastWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fast", provider: FastProvider()) { entry in
            FastWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fasting")
        .description("How long since you last ate, or into a fast, and what's likely happening.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall]
        #endif
    }
}

struct FastWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FastEntry

    var snapshot: MacroSnapshot { entry.snapshot }
    var from: Date? { snapshot.fastStart ?? snapshot.lastMealEnd }
    var hours: Double { from.map { max(0, entry.date.timeIntervalSince($0) / 3600) } ?? 0 }
    var phase: FastPhase { FastPhase.at(hours: hours) }
    var fasting: Bool { snapshot.fastStart != nil }
    /// A phase only for a fast started on purpose: a long gap without one may be meals not logged.
    var symbol: String { fasting ? phase.symbol : "fork.knife" }
    /// Toward the goal while fasting; between meals, toward 5 hours (the end of the 3–5 hour band).
    var progress: Double { min(1, hours / (snapshot.fastGoalHours ?? 5)) }
    var wholeHours: String { hours < 1 ? "\(Int(hours * 60))m" : "\(Int(hours))h" }

    var body: some View {
        Group {
            if snapshot.tracksMealTiming != true || from == nil {
                off
            } else {
                switch family {
                #if os(iOS)
                case .accessoryCircular:
                    Gauge(value: progress) {
                        Image(systemName: symbol)
                    } currentValueLabel: {
                        Text(wholeHours)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Label(fasting ? "Fasting · \(phase.title.lowercased())" : "Since you ate", systemImage: symbol)
                            .font(.headline).widgetAccentable()
                        if let from { Text(from, style: .timer).monospacedDigit() }
                        if let goal = snapshot.fastGoalHours, let start = snapshot.fastStart {
                            Text("Goal \(start.addingTimeInterval(goal * 3600).formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                .foregroundStyle(.secondary)
                        }
                    }
                case .accessoryInline:
                    Text(fasting ? "Fasting \(wholeHours) · \(phase.title.lowercased())" : "\(wholeHours) since you ate")
                #endif
                default:
                    small
                }
            }
        }
        .widgetURL(URL(string: "macrotrack://fast"))
    }

    var small: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.teal.opacity(0.18), lineWidth: 10)
                Circle().trim(from: 0, to: progress).stroke(Color.teal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    if let from {
                        Text(from, style: .timer).font(.headline.monospacedDigit()).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    }
                    Text(fasting ? "fasting" : "since you ate").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .padding(4)
            Label(fasting ? phase.title : "Between meals", systemImage: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.teal)
                .lineLimit(1)
        }
    }

    var off: some View {
        VStack(spacing: 4) {
            Image(systemName: "timer").font(.title3)
            Text(snapshot.tracksMealTiming == true ? "Log a meal to start the clock" : "Turn on meal timing in Stadig Macro")
                .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}
