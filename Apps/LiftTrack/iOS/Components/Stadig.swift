import SwiftUI
import SystemCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Stadig's look, "Steady Instrument" (docs/design.md): an ink ground that turns to paper in light
// mode, warm type, oversized tabular numerals, and one gauge everywhere, the ruler. Each app has a
// single accent, its asset catalog's AccentColor; everything in this file is the same in Stadig Lift
// and Stadig Macro, which each keep a copy (there's no shared UI package), so change both together.

// MARK: - Palette

enum Ink {
    static let ground = Color(light: 0xF4F2ED, dark: 0x0D0E10)
    static let surface = Color(light: 0xFFFFFF, dark: 0x17191C)
    static let raised = Color(light: 0xEBE8E1, dark: 0x212429)
    static let track = Color(light: 0xE4E1DA, dark: 0x2A2D32)
    /// The ruler's tick marks, cut into the fill.
    static let tick = Color(light: 0xFFFFFF, dark: 0x0D0E10, lightAlpha: 0.7, darkAlpha: 0.55)

    #if os(visionOS)
    // Vision Pro's windows are glass over a lit room, not ink: greys that read on ink vanish there,
    // so words and lines are white at strengths the glass carries.
    static let hairline = Color.white.opacity(0.2)
    static let text = Color.white
    static let text2 = Color.white.opacity(0.8)
    static let text3 = Color.white.opacity(0.68)
    #else
    static let hairline = Color(light: 0x16171A, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.09)
    static let text = Color(light: 0x16171A, dark: 0xF4F2EE)
    /// Every grey that carries words passes 4.5:1 on both grounds.
    static let text2 = Color(light: 0x55575A, dark: 0xB1B2AD)
    static let text3 = Color(light: 0x6C6E70, dark: 0x8D8F8A)
    #endif

    static let good = Color(light: 0x12804F, dark: 0x3ECF8E)
    static let ok = Color(light: 0xA86400, dark: 0xF5B544)
    static let bad = Color(light: 0xC8372B, dark: 0xFF6B5E)

    static let protein = Color(light: 0xC63B30, dark: 0xFF7A70)
    static let carbs = Color(light: 0x1F6FD0, dark: 0x5AA9FF)
    static let fat = Color(light: 0xA86400, dark: 0xF5B544)

    /// The two apps' accents, for saying which app measures a score. An app's own accent is `Color.accentColor`.
    static let lift = Color(light: 0x3355E0, dark: 0x6D8BFF)
    static let macro = Color(light: 0x12804F, dark: 0x3ECF8E)

    static func app(_ app: AppID) -> Color { app == .macroTrack ? macro : lift }
}

extension Color {
    /// A colour for each appearance, from 0xRRGGBB. Nonisolated, and its provider `@Sendable`:
    /// SwiftUI resolves colours on its render thread too, where a main-actor closure traps.
    nonisolated init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { @Sendable traits in
                traits.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: darkAlpha) : UIColor(rgb: light, alpha: lightAlpha)
            })
        #else
        self.init(
            nsColor: NSColor(name: nil) { @Sendable appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(rgb: dark, alpha: darkAlpha) : NSColor(rgb: light, alpha: lightAlpha)
            })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    fileprivate nonisolated convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#else
extension NSColor {
    fileprivate nonisolated convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#endif

// MARK: - Type

extension View {
    /// A number set as the hero of a screen: heavy, tabular, tightly tracked. `size` is its size at the
    /// default text size; it grows with Dynamic Type, but no more than half again, and shrinks to fit.
    func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        modifier(NumeralStyle(size: size, weight: weight))
    }

    /// The small uppercase label over a number or a group: "SET 2 OF 3", "USUALLY AROUND NOW".
    func eyebrow(_ color: Color = Ink.text3) -> some View {
        font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(color)
    }
}

/// A unit beside a numeral: grows with Dynamic Type like the numeral does, to the same cap.
private struct UnitStyle: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let size: CGFloat

    init(size: CGFloat) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.size = size
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(scaled, size * 1.5), weight: .semibold))
    }
}

private struct NumeralStyle: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: size >= 40 ? .largeTitle : .title2)
        self.size = size
        self.weight = weight
    }

    func body(content: Content) -> some View {
        let points = min(scaled, size * 1.5)
        content
            .font(.system(size: points, weight: weight))
            .monospacedDigit()
            .tracking(-points * 0.035)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A number with its unit set smaller beside it: "70 kg", "1,601 kcal left".
struct Measure: View {
    let value: String
    var unit: String?
    var size: CGFloat = 30
    var weight: Font.Weight = .bold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            Text(value).numeral(size, weight: weight)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .modifier(UnitStyle(size: max(12, size * 0.36)))
                    .foregroundStyle(Ink.text2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The ruler

/// The one gauge: a fill on a track, ticked every tenth so it reads as an instrument, not a progress
/// bar. Calories, macros, scores, rest, a session's progress: all of them are rulers.
struct Ruler: View {
    /// 0 to 1; anything else is clamped.
    var value: Double
    var color: Color = .accentColor
    var height: CGFloat = 14
    /// How many divisions to tick; 0 or 1 for none. Thin rulers (under 8 points) are never ticked.
    var divisions: Int = 10
    /// A target line, 0 to 1.
    var marker: Double?

    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let radius = min(7, height * 0.3)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Ink.track)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: fraction > 0 ? max(height * 0.5, width * fraction) : 0)
                if divisions > 1, height >= 8 {
                    Path { path in
                        for index in 1..<divisions {
                            let x = (width * Double(index) / Double(divisions)).rounded()
                            path.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: height))
                        }
                    }
                    .fill(Ink.tick)
                }
                if let marker {
                    Rectangle()
                        .fill(Ink.text)
                        .frame(width: 2, height: height + 6)
                        .offset(x: width * min(1, max(0, marker)) - 1)
                }
            }
        }
        .frame(height: height)
        .animation(.snappy(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}

extension Ruler {
    /// A slim ruler for a secondary number: no ticks.
    static func thin(_ value: Double, color: Color = .accentColor) -> Ruler {
        Ruler(value: value, color: color, height: 6, divisions: 0)
    }
}

// MARK: - Surfaces

extension View {
    /// A card on the ink ground. On Vision Pro the window is glass already, so a card there is the
    /// system's own fill rather than an opaque slab.
    func inkCard(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(visionOS)
        .background(.regularMaterial, in: .rect(cornerRadius: radius, style: .continuous))
            #else
        .background(Ink.surface, in: .rect(cornerRadius: radius, style: .continuous))
            #endif
    }

    /// The page behind everything: ink, or paper in light mode. Vision Pro keeps its glass.
    func inkGround() -> some View {
        #if os(visionOS)
        return self
        #else
        return background(Ink.ground.ignoresSafeArea())
        #endif
    }
}

// MARK: - Which app measures a score

/// "Lift", "Macro" or "Lift + Macro", with each app's colour: which app measures a score.
struct SourceChip: View {
    let apps: [AppID]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(apps, id: \.self) { app in
                Circle().fill(Ink.app(app)).frame(width: 6, height: 6)
            }
            Text(apps.map(Self.short).joined(separator: " + "))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Ink.text2)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Ink.raised, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Measured by \(apps.map(\.displayName).joined(separator: " and "))"))
    }

    static func short(_ app: AppID) -> String { app == .macroTrack ? "Macro" : "Lift" }
}

// MARK: - Your shape

/// The six scores drawn as one figure: a hexagon whose spokes are rulers. It grows where the work
/// is done. Corners are coloured by the app that measures them; a score nothing measures yet leaves
/// its spoke dashed and the figure open there.
struct ScoreShape: View {
    struct Axis: Identifiable, Hashable {
        var stat: StatKind
        var score: Int?
        /// The score some time ago, drawn as a dashed outline behind.
        var earlier: Int?
        var apps: [AppID]
        var id: StatKind { stat }
    }

    /// Clockwise from the top.
    static let order: [StatKind] = [.strength, .endurance, .agility, .vitality, .discipline, .physique]

    let axes: [Axis]
    var showsLabels = true

    /// The six axes from the stats board, in drawing order.
    static func axes(_ lines: [StatLine]) -> [Axis] {
        order.map { stat in
            let line = lines.first { $0.stat == stat }
            return Axis(stat: stat, score: line?.score, earlier: nil, apps: line?.apps ?? [])
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset: CGFloat = showsLabels ? 46 : 4
            let radius = max(10, min(size.width, size.height) / 2 - inset)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                grid(center: center, radius: radius)
                if axes.contains(where: { $0.earlier != nil }) {
                    polygon(center: center, radius: radius, values: axes.map { $0.earlier.map(Double.init) })
                        .stroke(Ink.text2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                let values = axes.map { $0.score.map(Double.init) }
                polygon(center: center, radius: radius, values: values).fill(Color.accentColor.opacity(0.16))
                outline(center: center, radius: radius, values: values, acrossGaps: false)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                // Where a score isn't measured yet the figure stays open: a faint dashed edge
                // jumps the gap instead of a solid side through the missing corner.
                outline(center: center, radius: radius, values: values, acrossGaps: true)
                    .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
                ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                    if let score = axis.score {
                        Circle()
                            .fill(dotColor(axis.apps))
                            .overlay { Circle().stroke(Ink.ground, lineWidth: 1.6) }
                            .frame(width: 8, height: 8)
                            .position(point(center: center, radius: radius * Double(score) / 100, index: index))
                    }
                    if showsLabels {
                        label(axis)
                            .position(point(center: center, radius: radius + 28, index: index))
                    }
                }
            }
        }
        .aspectRatio(1.08, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your shape"))
        .accessibilityValue(
            Text(axes.map { "\($0.stat.label) \($0.score.map(String.init) ?? "not measured yet")" }.joined(separator: ", ")))
    }

    private func label(_ axis: Axis) -> some View {
        VStack(spacing: 1) {
            Text(axis.score.map(String.init) ?? "–")
                .numeral(17, weight: .heavy)
                .foregroundStyle(axis.score == nil ? Ink.text3 : Ink.text)
            Text(axis.stat.label).eyebrow()
        }
        .fixedSize()
        // The corners sit in a fixed ring around the figure: past this they'd run off its card.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func dotColor(_ apps: [AppID]) -> Color {
        apps.count > 1 ? Ink.text : apps.first.map(Ink.app) ?? Color.accentColor
    }

    private func point(center: CGPoint, radius: Double, index: Int) -> CGPoint {
        let angle = (-90 + 60 * Double(index)) * .pi / 180
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func grid(center: CGPoint, radius: Double) -> some View {
        ZStack {
            Path { path in
                for level in stride(from: 20.0, through: 100, by: 20) {
                    let corners = (0..<6).map { point(center: center, radius: radius * level / 100, index: $0) }
                    path.addLines(corners + [corners[0]])
                }
                for index in 0..<6 where axes.indices.contains(index) && axes[index].score != nil {
                    path.move(to: center)
                    path.addLine(to: point(center: center, radius: radius, index: index))
                }
            }
            .stroke(Ink.hairline, lineWidth: 1)
            Path { path in
                for index in 0..<6 where axes.indices.contains(index) && axes[index].score == nil {
                    path.move(to: center)
                    path.addLine(to: point(center: center, radius: radius, index: index))
                }
            }
            .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // The spokes are rulers: a tick every ten.
            Path { path in
                for index in 0..<6 where axes.indices.contains(index) && axes[index].score != nil {
                    let angle = (-90 + 60 * Double(index)) * .pi / 180
                    let across = CGVector(dx: -sin(angle), dy: cos(angle))
                    for step in stride(from: 10.0, to: 100, by: 10) {
                        let at = point(center: center, radius: radius * step / 100, index: index)
                        let half = step.truncatingRemainder(dividingBy: 20) == 0 ? 2.6 : 1.6
                        path.move(to: CGPoint(x: at.x - across.dx * half, y: at.y - across.dy * half))
                        path.addLine(to: CGPoint(x: at.x + across.dx * half, y: at.y + across.dy * half))
                    }
                }
            }
            .stroke(Ink.text3, lineWidth: 0.8)
        }
    }

    /// The figure's edges: between neighbouring known corners, or (`acrossGaps`) only the edges
    /// that jump over an unknown one.
    private func outline(center: CGPoint, radius: Double, values: [Double?], acrossGaps: Bool) -> Path {
        Path { path in
            let known = values.indices.filter { values[$0] != nil }
            guard known.count > 1 else { return }
            for (offset, index) in known.enumerated() {
                let next = known[(offset + 1) % known.count]
                let neighbours = (next - index + values.count) % values.count == 1
                guard neighbours != acrossGaps, let from = values[index], let to = values[next] else { continue }
                path.move(to: point(center: center, radius: radius * from / 100, index: index))
                path.addLine(to: point(center: center, radius: radius * to / 100, index: next))
            }
        }
    }

    /// The filled figure through every known corner; an unknown one is skipped.
    private func polygon(center: CGPoint, radius: Double, values: [Double?]) -> Path {
        Path { path in
            let corners = values.enumerated().compactMap { index, value in
                value.map { point(center: center, radius: radius * $0 / 100, index: index) }
            }
            guard corners.count > 1 else { return }
            path.addLines(corners)
            path.closeSubpath()
        }
    }
}
