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

/// How long since the last meal, or into a fast, with its phase, over a ruler toward the goal.
struct FastWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fast", provider: FastProvider()) { entry in
            FastWidgetView(entry: entry)
                .inkWidgetBackground()
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

    var body: some View {
        FastFace(entry: entry, family: family)
            .widgetURL(URL(string: "macrotrack://fast"))
    }
}

/// The fast in the family given: the widget passes the system's.
struct FastFace: View {
    let entry: FastEntry
    let family: WidgetFamily

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
        if snapshot.tracksMealTiming != true || from == nil {
            FastOff(tracksMealTiming: snapshot.tracksMealTiming == true, family: family)
        } else {
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                        Text(wholeHours).numeral(20)
                        Ruler(value: progress, color: .primary, height: 4, divisions: 0)
                            .frame(width: 34)
                            .padding(.top, 2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fasting ? "Fasting \(wholeHours), \(phase.title.lowercased())" : "\(wholeHours) since you ate"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(fasting ? phase.title : "Since you ate", systemImage: symbol)
                        .eyebrow()
                        .widgetAccentable()
                    if let from {
                        Text(from, style: .timer).numeral(24)
                    }
                    Ruler(value: progress, color: .primary, height: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Text(fasting ? "Fasting \(wholeHours) · \(phase.title.lowercased())" : "\(wholeHours) since you ate")
            #endif
            default:
                small
            }
        }
    }

    /// The ruler's ends: "16 h goal" and when it's reached, or between meals the 3–5 hour band's end.
    private var scale: (String, String) {
        guard fasting, let from, let goal = snapshot.fastGoalHours else { return ("Toward 5 h", "") }
        return ("\(Int(goal)) h goal", from.addingTimeInterval(goal * 3600).formatted(date: .omitted, time: .shortened))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fasting ? "Fasting" : "Since you ate").eyebrow().ink(.tertiary)
            if let from {
                Text(from, style: .timer)
                    .numeral(34, tightness: 0.05)
                    .ink(.primary)
                    .padding(.top, 4)
            }
            Label(fasting ? phase.title : "Between meals", systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: 6)
            Ruler(value: progress, height: 12)
            HStack {
                Text(scale.0)
                Spacer(minLength: 4)
                Text(scale.1)
            }
            .eyebrow(size: 10)
            .ink(.tertiary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Meal timing off, or no meal logged to count from.
struct FastOff: View {
    let tracksMealTiming: Bool
    let family: WidgetFamily

    private var words: String { tracksMealTiming ? "Log a meal to start the clock" : "Turn on meal timing in Stadig Macro" }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            Text(words)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "timer").font(.title3)
            }
            .accessibilityLabel(Text(words))
        #endif
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Fasting").eyebrow().ink(.tertiary)
                Text(words)
                    .font(.footnote.weight(.semibold))
                    .ink(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
