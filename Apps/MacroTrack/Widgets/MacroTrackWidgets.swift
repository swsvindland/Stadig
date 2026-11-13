import AppIntents
import SwiftUI
import SystemCore
import WidgetKit

#if canImport(UIKit)
import UIKit
#endif

@main
struct MacroTrackWidgets: WidgetBundle {
    var body: some Widget {
        RemainingWidget()
        FastWidget()
        #if os(iOS)
        FastLiveActivity()
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
        .description("Opens Stadig Macro ready to record this morning's weight.")
    }
}

func logControl(kind: String, entry: LoggerEntryPoint, title: LocalizedStringResource, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "dev.svindland.stadig.macro.control.\(kind)") {
        ControlWidgetButton(action: OpenLoggerIntent(entry: entry)) {
            Label(title, systemImage: symbol)
        }
    }
    .displayName(title)
    .description("Opens Stadig Macro ready to log.")
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

    /// Now, one for each food logged for later today, and a fresh day at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let now = Date()
        let snapshot = MacroSnapshot.load()
        // The next calendar day, not 24 hours on, which misses midnight or lands before it when the clocks change.
        let midnight = Day(now).adding(days: 1).date()
        let dates = [now] + snapshot.laterDates(after: now, before: midnight) + [midnight]
        completion(
            Timeline(
                entries: dates.map { MacroEntry(date: $0, snapshot: snapshot.current(now: $0)) }, policy: .after(midnight.addingTimeInterval(60))))
    }
}

/// Calories and protein left, with one-tap ways to log.
struct RemainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "remaining", provider: MacroProvider()) { entry in
            RemainingView(snapshot: entry.snapshot)
                .inkWidgetBackground()
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
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let snapshot: MacroSnapshot

    var body: some View { RemainingFace(snapshot: snapshot, family: family, desk: Self.isStandBy(showsBackground: showsBackground)) }

    /// StandBy, where the system drops the background and scales a small widget up to half the
    /// screen: only an iPhone's (an iPad's Lock Screen drops it too, at the widget's own size).
    static func isStandBy(showsBackground: Bool) -> Bool {
        #if os(iOS)
        return !showsBackground && UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}

/// What's left today in the family given: the widget passes the system's.
struct RemainingFace: View {
    let snapshot: MacroSnapshot
    let family: WidgetFamily
    /// StandBy's desk view of the small widget (`RemainingView.isStandBy`).
    var desk = false

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            RemainingCircular(snapshot: snapshot)
                .widgetURL(URL(string: "macrotrack://log"))
        case .accessoryRectangular:
            RemainingRectangular(snapshot: snapshot)
                .widgetURL(URL(string: "macrotrack://log"))
        case .accessoryInline:
            Text(snapshot.kcalLine)
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 18) {
                LeftToday(snapshot: snapshot, showsMacros: false)
                VStack(alignment: .leading, spacing: 0) {
                    MacroRows(snapshot: snapshot)
                    Spacer(minLength: 8)
                    LogButtons(weighedToday: snapshot.weighedToday)
                }
            }
        default:
            Group {
                if desk {
                    LeftTodayDesk(snapshot: snapshot)
                } else {
                    LeftToday(snapshot: snapshot, showsMacros: true)
                }
            }
            .widgetURL(URL(string: "macrotrack://log"))
        }
    }
}

extension MacroSnapshot {
    /// The hero number: kcal left, over, or before targets, eaten.
    var kcalNumber: String { Int((kcalLeft.map { max(0, kcalOver ? -$0 : $0) } ?? kcal).rounded()).formatted() }

    /// Over by a whole kcal or more (`MacroProgress.isOver`'s rule), so a fraction over never reads "0 over".
    var kcalOver: Bool { (kcalLeft ?? 0) <= -1 }

    /// "Left today", "Over today", "Eaten today".
    var kcalEyebrow: String {
        guard kcalLeft != nil else { return "Eaten today" }
        return kcalOver ? "Over today" : "Left today"
    }

    /// Under the number: "kcal of 2,200", "kcal over 2,200", or "kcal" before targets.
    var kcalOfTarget: String {
        guard let target = kcalTarget else { return "kcal" }
        return "kcal \(kcalOver ? "over" : "of") \(Int(target.rounded()).formatted())"
    }

    /// "left", "over" or "eaten", after "kcal".
    var kcalWord: String { kcalLeft == nil ? "eaten" : kcalOver ? "over" : "left" }

    /// "1,601 kcal left", for the inline family and VoiceOver.
    var kcalLine: String { "\(kcalNumber) kcal \(kcalWord)" }

    /// How much of the target is eaten, 0 to 1; nil before targets.
    var kcalFraction: Double? { kcalTarget.map { $0 > 0 ? kcal / $0 : 0 } }

    /// Each macro with a target (protein always, as before targets it's still eaten): its name, its
    /// letter, its colour, what's left (or eaten) and how much of the target is eaten.
    var macroLines: [MacroLine] {
        var lines = [MacroLine(name: "Protein", letter: "P", color: Ink.protein, eaten: protein, target: proteinTarget)]
        if let carbsTarget { lines.append(MacroLine(name: "Carbs", letter: "C", color: Ink.carbs, eaten: carbs, target: carbsTarget)) }
        if let fatTarget { lines.append(MacroLine(name: "Fat", letter: "F", color: Ink.fat, eaten: fat, target: fatTarget)) }
        return lines
    }
}

struct MacroLine: Identifiable {
    let name: String
    let letter: String
    let color: Color
    let eaten: Double
    let target: Double?

    var id: String { name }
    /// Grams left, never below nothing; before a target, grams eaten.
    var grams: Int { Int((target.map { max(0, $0 - eaten) } ?? eaten).rounded()) }
    var fraction: Double { target.map { $0 > 0 ? eaten / $0 : 0 } ?? 0 }
    var sentence: String { target == nil ? "\(grams) g \(name.lowercased()) eaten" : "\(grams) g \(name.lowercased()) left" }
}

/// Kcal left as the hero over its ruler: the small widget, and the medium one's left half. The
/// small one has the macros under it in their colours, StandBy's desk view.
struct LeftToday: View {
    let snapshot: MacroSnapshot
    let showsMacros: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.kcalEyebrow).eyebrow().ink(.tertiary)
            Text(snapshot.kcalNumber)
                .numeral(42, tightness: 0.05)
                .ink(.primary)
                .padding(.top, 2)
            Text(snapshot.kcalOfTarget)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .ink(.secondary)
            Spacer(minLength: 6)
            if let fraction = snapshot.kcalFraction {
                Ruler(value: fraction, height: 12)
            }
            if showsMacros {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(snapshot.macroLines) { line in
                        VStack(alignment: .leading, spacing: 3) {
                            MacroAmount(line: line, size: 12)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if line.target != nil {
                                Ruler(value: line.fraction, color: line.color, height: 4, divisions: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 9)
            } else if let badge = snapshot.badge {
                Text(badge).eyebrow(size: 10).ink(.tertiary).padding(.top, 6)
            } else if snapshot.kcalTarget != nil {
                Text("\(Int(snapshot.kcal.rounded()).formatted()) eaten").eyebrow(size: 10).ink(.tertiary).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(([snapshot.kcalLine] + (showsMacros ? snapshot.macroLines.map(\.sentence) : [])).joined(separator: ", ")))
    }
}

/// "102 P": the grams heavy, the letter lighter in the second grey; the ruler under it carries the
/// macro's colour.
struct MacroAmount: View {
    let line: MacroLine
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.25) {
            Text("\(line.grams)").font(.system(size: size, weight: .bold)).monospacedDigit().ink(.primary)
            Text(line.letter).font(.system(size: size, weight: .semibold)).ink(.secondary)
        }
    }
}

/// The small widget in StandBy, on the desk across the room, as the design draws it: kcal left as
/// large as the widget is wide, its words small beside it, a tall ruler of what's eaten and the
/// macros under it. StandBy scales the widget about twice over, so it's laid out on the design's
/// widget and scaled to this one.
struct LeftTodayDesk: View {
    let snapshot: MacroSnapshot

    var body: some View {
        GeometryReader { geometry in
            // The design's widget is 334 points with 28 of margin; the system's margins are already outside this.
            let u = geometry.size.width / 278
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.kcalEyebrow).eyebrow(size: 12 * u).ink(.tertiary)
                Text(snapshot.kcalNumber)
                    .numeral(108 * u, weight: .heavy, tightness: 0.06)
                    .ink(.primary)
                    // The design's line is 0.8 of the size, SF's 1.19: the difference comes off both ends.
                    .padding(.vertical, -21 * u)
                    .padding(.leading, -4 * u)
                    .padding(.top, 16 * u)
                Text(snapshot.kcalOfTarget)
                    .font(.system(size: 19 * u, weight: .semibold))
                    .lineLimit(1)
                    .ink(.secondary)
                    .padding(.top, 20 * u)
                Spacer(minLength: 0)
                if let fraction = snapshot.kcalFraction {
                    Ruler(value: fraction, height: 28 * u)
                }
                HStack(alignment: .top, spacing: 12 * u) {
                    ForEach(snapshot.macroLines) { line in
                        VStack(alignment: .leading, spacing: 5 * u) {
                            MacroAmount(line: line, size: 15 * u)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if line.target != nil {
                                Ruler(value: line.fraction, color: line.color, height: 6 * u, divisions: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 16 * u)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(([snapshot.kcalLine] + snapshot.macroLines.map(\.sentence)).joined(separator: ", ")))
    }
}

/// Each macro's grams left over a thin ruler in its colour: the medium widget's right half.
struct MacroRows: View {
    let snapshot: MacroSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(snapshot.macroLines) { line in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(line.name).font(.caption.weight(.semibold)).ink(.secondary)
                        Spacer(minLength: 4)
                        Text("\(line.grams)").font(.subheadline.weight(.bold)).monospacedDigit().ink(.primary)
                        Text(line.target == nil ? "g" : "g left").font(.caption.weight(.semibold)).ink(.secondary)
                    }
                    if line.target != nil {
                        Ruler(value: line.fraction, color: line.color, height: 5, divisions: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(line.sentence))
            }
        }
    }
}

/// One-tap ways to log: search, the camera (a photo where there's none), the scanner (a typed
/// barcode) and, until it's done, the weigh-in.
struct LogButtons: View {
    let weighedToday: Bool

    static var hasCamera: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            button("Search foods", "magnifyingglass", "macrotrack://log")
            // A camera only where there's one; elsewhere the same links choose a photo and type a barcode.
            button(Self.hasCamera ? "Snap a meal" : "Choose a photo", Self.hasCamera ? "camera" : "photo.on.rectangle", "macrotrack://camera")
            button(Self.hasCamera ? "Scan a barcode" : "Type a barcode", Self.hasCamera ? "barcode.viewfinder" : "barcode", "macrotrack://scan")
            if !weighedToday { button("Weigh in", "scalemass", "macrotrack://weigh") }
        }
    }

    @ViewBuilder private func button(_ title: LocalizedStringKey, _ symbol: String, _ link: String) -> some View {
        if let url = URL(string: link) {
            Link(destination: url) {
                Label(title, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.accentColor.opacity(0.16), in: .capsule)
                    .widgetAccentable()
            }
        }
    }
}

#if os(iOS)
/// Kcal left on the Lock Screen, with a slim ruler under it.
struct RemainingCircular: View {
    let snapshot: MacroSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(snapshot.kcalNumber).numeral(19)
                Text(snapshot.kcalLeft == nil ? "kcal" : snapshot.kcalWord)
                    .eyebrow(size: 8)
                    .foregroundStyle(.secondary)
                if let fraction = snapshot.kcalFraction {
                    Ruler(value: fraction, color: .primary, height: 4, divisions: 0)
                        .frame(width: 34)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(snapshot.kcalLine))
    }
}

/// The Lock Screen's line under the clock: kcal left over its ruler, then the protein to go.
struct RemainingRectangular: View {
    let snapshot: MacroSnapshot

    private var proteinLine: String? {
        guard let left = snapshot.proteinLeft else { return snapshot.badge }
        return "\(Int(max(0, left).rounded())) g protein to go"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.kcalNumber).numeral(24)
                Text("kcal \(snapshot.kcalWord)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let fraction = snapshot.kcalFraction {
                Ruler(value: fraction, color: .primary, height: 8)
            }
            if let proteinLine {
                Text(proteinLine).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([snapshot.kcalLine, proteinLine].compactMap(\.self).joined(separator: ", ")))
    }
}
#endif
