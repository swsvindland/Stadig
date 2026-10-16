import AppIntents
import SwiftUI
import WidgetKit

@main
struct MacroTrackWidgets: WidgetBundle {
    var body: some Widget {
        RemainingWidget()
        SnapMealControl()
        ScanBarcodeControl()
        LogFoodControl()
        WeighInControl()
    }
}

/// Control Center and Lock Screen buttons straight into one way of logging.
struct SnapMealControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        logControl(kind: "camera", entry: .camera, title: "Snap a Meal", symbol: "camera")
    }
}

struct ScanBarcodeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        logControl(kind: "scan", entry: .scan, title: "Scan Barcode", symbol: "barcode.viewfinder")
    }
}

struct LogFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        logControl(kind: "search", entry: .search, title: "Log Food", symbol: "fork.knife")
    }
}

struct WeighInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.svindland.macrotrack.control.weigh") {
            ControlWidgetButton(action: OpenLoggerIntent(entry: .weigh)) {
                Label("Weigh In", systemImage: "scalemass")
            }
        }
        .displayName("Weigh In")
        .description("Opens Macro Track ready to record this morning's weight.")
    }
}

func logControl(kind: String, entry: LoggerEntryPoint, title: LocalizedStringResource, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "dev.svindland.macrotrack.control.\(kind)") {
        ControlWidgetButton(action: OpenLoggerIntent(entry: entry)) {
            Label(title, systemImage: symbol)
        }
    }
    .displayName(title)
    .description("Opens Macro Track ready to log.")
}

struct MacroEntry: TimelineEntry {
    let date: Date
    let snapshot: MacroSnapshot
}

struct MacroProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacroEntry { MacroEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (MacroEntry) -> Void) {
        completion(MacroEntry(date: Date(), snapshot: context.isPreview ? .sample : MacroSnapshot.load().current()))
    }

    /// Now, and a fresh day at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let now = Date()
        let snapshot = MacroSnapshot.load()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        completion(Timeline(entries: [MacroEntry(date: now, snapshot: snapshot.current(now: now)),
                                      MacroEntry(date: midnight, snapshot: snapshot.current(now: midnight))],
                            policy: .after(midnight.addingTimeInterval(60))))
    }
}

/// Calories and protein left, with one-tap ways to log.
struct RemainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "remaining", provider: MacroProvider()) { entry in
            RemainingView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Left today")
        .description("Calories and protein left, with buttons to log.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RemainingView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MacroSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(snapshot.kcal, snapshot.kcalTarget ?? snapshot.kcal), in: 0...max(1, snapshot.kcalTarget ?? max(1, snapshot.kcal))) {
                Text("kcal")
            } currentValueLabel: {
                Text(shortKcal)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(URL(string: "macrotrack://log"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(kcalLine).font(.headline).widgetAccentable()
                if let p = snapshot.proteinLeft { Text("\(Int(max(0, p))) g protein to go") }
                if let badge = snapshot.badge { Text(badge).foregroundStyle(.secondary) }
            }
            .widgetURL(URL(string: "macrotrack://log"))
        case .accessoryInline:
            Text(kcalLine)
        case .systemMedium:
            HStack(spacing: 16) {
                ring.frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 8) {
                    bars
                    HStack(spacing: 8) {
                        button("magnifyingglass", "macrotrack://log")
                        button("camera", "macrotrack://camera")
                        button("barcode.viewfinder", "macrotrack://scan")
                        if !snapshot.weighedToday { button("scalemass", "macrotrack://weigh") }
                    }
                }
            }
        default:
            VStack(spacing: 6) {
                ring
                if let p = snapshot.proteinLeft {
                    Text("\(Int(max(0, p))) g protein").font(.caption2.weight(.semibold)).foregroundStyle(.pink)
                }
            }
            .widgetURL(URL(string: "macrotrack://log"))
        }
    }

    var shortKcal: String {
        let value = snapshot.kcalLeft ?? snapshot.kcal
        return abs(value) >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))"
    }

    var kcalLine: String {
        if let left = snapshot.kcalLeft { return left >= 0 ? "\(Int(left)) kcal left" : "\(Int(-left)) kcal over" }
        return "\(Int(snapshot.kcal)) kcal eaten"
    }

    var ring: some View {
        let target = snapshot.kcalTarget
        let fraction = target.map { $0 > 0 ? min(1, snapshot.kcal / $0) : 0 } ?? 0
        return ZStack {
            Circle().stroke(Color.accentColor.opacity(0.18), lineWidth: 10)
            Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(abs(snapshot.kcalLeft ?? snapshot.kcal)))").font(.title3.weight(.bold).monospacedDigit()).minimumScaleFactor(0.6)
                Text(snapshot.kcalLeft.map { $0 >= 0 ? "left" : "over" } ?? "eaten").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    var bars: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar("Protein", snapshot.protein, snapshot.proteinTarget, .pink)
            if snapshot.carbsTarget != nil { bar("Carbs", snapshot.carbs, snapshot.carbsTarget, .blue) }
            if snapshot.fatTarget != nil { bar("Fat", snapshot.fat, snapshot.fatTarget, .orange) }
            if let badge = snapshot.badge, snapshot.carbsTarget == nil { Text(badge).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    func bar(_ label: String, _ value: Double, _ target: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2.weight(.semibold))
                Spacer()
                Text(target.map { "\(Int(max(0, $0 - value))) g left" } ?? "\(Int(value)) g").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: proxy.size.width * min(1, target.map { $0 > 0 ? value / $0 : 0 } ?? 0))
                }
            }
            .frame(height: 5)
        }
    }

    func button(_ symbol: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color.accentColor.opacity(0.16), in: .capsule)
        }
    }
}
