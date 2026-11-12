import SwiftUI
import WidgetKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The widgets' share of Stadig's look ("Steady Instrument", docs/design.md): the palette, the
// eyebrow and numeral type and the ruler, copied from the app's `Components/Stadig.swift`, which the
// extension can't see. Keep the colours in step with it (and with Stadig Lift's copy, which differs in
// the Dynamic Island's accent and has the week strip where this has the macros' colours). What's
// different here is for the Lock Screen, StandBy and the tinted Home Screen, where the system
// recolours everything it draws: there only opacity survives, so the greys become hierarchical
// styles, the ruler's track is translucent and its ticks are cut out of it rather than painted on.

// MARK: - Palette

enum Ink {
    static let ground = Color(light: 0xF4F2ED, dark: 0x0D0E10)
    static let raised = Color(light: 0xEBE8E1, dark: 0x212429)
    static let track = Color(light: 0xE4E1DA, dark: 0x2A2D32)
    static let text = Color(light: 0x16171A, dark: 0xF4F2EE)
    static let text2 = Color(light: 0x55575A, dark: 0xB1B2AD)
    static let text3 = Color(light: 0x6C6E70, dark: 0x8D8F8A)

    /// The Dynamic Island is black whatever the phone's appearance, so it takes the dark palette.
    enum Island {
        static let text = Color(rgb: 0xF4F2EE)
        static let text2 = Color(rgb: 0xB1B2AD)
        static let text3 = Color(rgb: 0x8D8F8A)
        static let track = Color(rgb: 0x2A2D32)
        /// Stadig Macro's leaf, as the dark appearance has it.
        static let accent = Color(rgb: 0x3ECF8E)
    }

    static let protein = Color(light: 0xC63B30, dark: 0xFF7A70)
    static let carbs = Color(light: 0x1F6FD0, dark: 0x5AA9FF)
    static let fat = Color(light: 0xA86400, dark: 0xF5B544)
}

extension Color {
    /// A colour for each appearance, from 0xRRGGBB. Nonisolated, and its provider `@Sendable`:
    /// SwiftUI resolves colours on its render thread too, where a main-actor closure traps.
    nonisolated init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { @Sendable traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) })
        #else
        self.init(
            nsColor: NSColor(name: nil) { @Sendable appearance in
                NSColor(rgb: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            })
        #endif
    }

    nonisolated init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

#if canImport(UIKit)
extension UIColor {
    fileprivate nonisolated convenience init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
extension NSColor {
    fileprivate nonisolated convenience init(rgb: UInt32) {
        self.init(srgbRed: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

/// Which of Ink's greys a line of words is set in.
enum InkTone {
    case primary, secondary, tertiary

    var color: Color {
        switch self {
        case .primary: Ink.text
        case .secondary: Ink.text2
        case .tertiary: Ink.text3
        }
    }

    var hierarchical: HierarchicalShapeStyle {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .tertiary: .tertiary
        }
    }
}

/// Ink's grey in full colour; where the system tints the widget, the matching hierarchical style,
/// since an opaque grey there comes out as bright as the text above it.
private struct InkToneStyle: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let tone: InkTone

    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content.foregroundStyle(tone.color)
        } else {
            content.foregroundStyle(tone.hierarchical)
        }
    }
}

// MARK: - Type

extension View {
    func ink(_ tone: InkTone) -> some View {
        modifier(InkToneStyle(tone: tone))
    }

    /// A number set as the hero: heavy, tabular, tightly tracked (`tightness` of its size), shrinking
    /// to fit the widget.
    func numeral(_ size: CGFloat, weight: Font.Weight = .bold, tightness: CGFloat = 0.035) -> some View {
        font(.system(size: size, weight: weight))
            .monospacedDigit()
            .tracking(-size * tightness)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// The small uppercase label over a number or a group: "LEFT TODAY", "FASTING".
    func eyebrow(size: CGFloat = 11) -> some View {
        font(.system(size: size, weight: .semibold)).textCase(.uppercase).tracking(size * 0.08).lineLimit(1)
    }

    /// The page behind a Home Screen widget: ink, or paper in light mode. Vision Pro's widgets keep
    /// the system's material, as its windows keep their glass. The system drops it where it tints the
    /// widget or StandBy shows it on black.
    func inkWidgetBackground() -> some View {
        #if os(visionOS)
        containerBackground(.fill.tertiary, for: .widget)
        #else
        containerBackground(Ink.ground, for: .widget)
        #endif
    }
}

// MARK: - The ruler

/// The one gauge: a fill on a track, ticked every tenth so it reads as an instrument. Its ticks are
/// gaps, and its track translucent where the system tints the widget, so it keeps its shape in every
/// rendering mode; the fill is the accentable part.
struct Ruler: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    /// 0 to 1; anything else is clamped.
    var value: Double
    var color: Color = .accentColor
    var height: CGFloat = 12
    /// How many divisions to tick; 0 or 1 for none. Rulers under 8 points are never ticked.
    var divisions = 10
    /// The track's colour in full colour; the Dynamic Island passes its own.
    var track: Color = Ink.track

    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(renderingMode == .fullColor ? track : Color.primary.opacity(0.25))
                Rectangle()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(height * 0.5, width * fraction) : 0)
                    .widgetAccentable()
            }
            .mask { TickedOutline(size: geometry.size, divisions: height >= 8 ? divisions : 0) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A rounded bar with a gap at each division, filled even-odd so the gaps are holes.
struct TickedOutline: View {
    let size: CGSize
    let divisions: Int

    var body: some View {
        Path { path in
            let radius = min(7, size.height * 0.3)
            path.addRoundedRect(in: CGRect(origin: .zero, size: size), cornerSize: CGSize(width: radius, height: radius), style: .continuous)
            guard divisions > 1 else { return }
            for index in 1..<divisions {
                let x = (size.width * Double(index) / Double(divisions)).rounded()
                path.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: size.height))
            }
        }
        .fill(style: FillStyle(eoFill: true))
    }
}
