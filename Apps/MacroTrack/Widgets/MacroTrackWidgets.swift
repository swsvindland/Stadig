import AppIntents
import SwiftUI
import SystemCore
import WidgetKit

@main
struct MacroTrackWidgets: WidgetBundle {
    var body: some Widget {
        RemainingWidget()
        #if os(iOS)
        SnapMealControl()
        ScanBarcodeControl()
        #endif
        #if os(iOS) || os(macOS)
        // The Mac's Control Center and menu bar take controls too; it has no camera to snap or scan
        // with, so it gets the two that need none. Vision Pro has no controls.
        LogFoodControl()
        WeighInControl()
        #endif
    }
}

#if os(iOS) || os(macOS)

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
        StaticControlConfiguration(kind: "dev.svindland.stadig.macro.control.weigh") {
            ControlWidgetButton(action: OpenLoggerIntent(entry: .weigh)) {
                Label("Weigh In", systemImage: "scalemass")
            }
        }
        .displayName("Weigh In")
        .description("Opens Macro Track ready to record this morning's weight.")
    }
}

func logControl(kind: String, entry: LoggerEntryPoint, title: LocalizedStringResource, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "dev.svindland.stadig.macro.control.\(kind)") {
        ControlWidgetButton(action: OpenLoggerIntent(entry: entry)) {
            Label(title, systemImage: symbol)
        }
    }
    .displayName(title)
    .description("Opens Macro Track ready to log.")
}

#endif

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
        // The next calendar day, not 24 hours on, which misses midnight or lands before it when the clocks change.
        let midnight = Day(now).adding(days: 1).date()
        completion(
            Timeline(
                entries: [
                    MacroEntry(date: now, snapshot: snapshot.current(now: now)),
                    MacroEntry(date: midnight, snapshot: snapshot.current(now: midnight)),
                ],
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
        .supportedFamilies(Self.families)
    }

    /// The Home Screen and Lock Screen on iPhone and iPad; the desktop and Notification Center on the
    /// Mac; and Vision Pro's walls and tables.
    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .systemMedium]
        #endif
    }
}

struct RemainingView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MacroSnapshot

    var body: some View {
        switch family {
        #if os(iOS)
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
        #endif
        case .systemMedium:
            HStack(spacing: 16) {
                ring.frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 8) {
                    bars
                    HStack(spacing: 8) {
                        button("magnifyingglass", "macrotrack://log")
                        // A camera only where there's one; elsewhere the same links choose a photo and type a barcode.
                        button(Self.hasCamera ? "camera" : "photo.on.rectangle", "macrotrack://camera")
                        button(Self.hasCamera ? "barcode.viewfinder" : "barcode", "macrotrack://scan")
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

    static var hasCamera: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
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
            Circle().trim(from: 0, to: fraction).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(
                .degrees(-90))
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
                Text(target.map { "\(Int(max(0, $0 - value))) g left" } ?? "\(Int(value)) g").font(.caption2.monospacedDigit()).foregroundStyle(
                    .secondary)
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
