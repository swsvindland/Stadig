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
// Each app supplies the few things that differ between them: `Ink.onAccent` and the `.pageBackground`
// and `.cardBackground` fills (Components/Theme.swift), and `hoverHighlight()`, `inlineTitle()`,
// `adaptiveGlass(in:tint:interactive:)` and the glass button styles Vision Pro keeps
// (Platform/Adaptive.swift).

// MARK: - Palette

enum Ink {
    static let ground = Color(light: 0xF4F2ED, dark: 0x0D0E10)
    #if os(visionOS)
    // On Vision Pro's glass the ink's dark fills are black slabs: there a card, a raised control
    // and a ruler's track are white at strengths the glass shows through.
    static let surface = Color.white.opacity(0.08)
    static let raised = Color.white.opacity(0.14)
    static let track = Color.white.opacity(0.16)
    #else
    static let surface = Color(light: 0xFFFFFF, dark: 0x17191C)
    // With Increase Contrast every fill a word or a fill sits on steps further from the card, and
    // every colour below steps further from them: each passes 4.5:1 on the ground, the card, the
    // raised grey and a pill's wash of itself, where a few of the light theme's are just under.
    static let raised = Color(light: 0xEBE8E1, dark: 0x212429, increased: (0xE2DED6, 0x2A2E34))
    static let track = Color(light: 0xE4E1DA, dark: 0x2A2D32, increased: (0xD9D5CD, 0x33363C))
    #endif
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
    static let hairline = Color(light: 0x16171A, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.09, increasedAlpha: (0.28, 0.24))
    static let text = Color(light: 0x16171A, dark: 0xF4F2EE)
    /// Every grey that carries words passes 4.5:1 on both grounds and the card.
    static let text2 = Color(light: 0x55575A, dark: 0xB1B2AD, increased: (0x3F4144, 0xD0D1CC))
    static let text3 = Color(light: 0x6C6E70, dark: 0x8D8F8A, increased: (0x505255, 0xB4B5B0))
    #endif

    static let good = Color(light: 0x12804F, dark: 0x3ECF8E, increased: (0x0D6B42, 0x5BDDA0))
    static let ok = Color(light: 0xA86400, dark: 0xF5B544, increased: (0x875000, 0xF8C463))
    static let bad = Color(light: 0xC8372B, dark: 0xFF6B5E, increased: (0xA82E24, 0xFF8A7F))

    static let protein = Color(light: 0xC63B30, dark: 0xFF7A70, increased: (0xA8302A, 0xFF958C))
    static let carbs = Color(light: 0x1F6FD0, dark: 0x5AA9FF, increased: (0x1A5CAE, 0x7DBBFF))
    static let fat = Color(light: 0xA86400, dark: 0xF5B544, increased: (0x875000, 0xF8C463))

    /// The two apps' accents, for saying which app measures a score. An app's own accent is
    /// `Color.accentColor`, whose asset has the same colours for Increase Contrast.
    static let lift = Color(light: 0x3355E0, dark: 0x6D8BFF, increased: (0x2B4CD0, 0x8AA2FF))
    static let macro = Color(light: 0x12804F, dark: 0x3ECF8E, increased: (0x0D6B42, 0x5BDDA0))

    static func app(_ app: AppID) -> Color { app == .macroTrack ? macro : lift }

    /// A colour for words: the accent on a link, good on "+2", protein's red on "15 P". On Vision
    /// Pro's glass a hue at text size is about as bright as the lit room through the glass and can't
    /// be read, so there words are white and the colour stays in the marks beside them (a dot, a
    /// ruler, a filled chip).
    static func words(_ color: Color) -> Color {
        #if os(visionOS)
        return text
        #else
        return color
        #endif
    }
}

extension Color {
    /// A colour for each appearance, from 0xRRGGBB, and with Increase Contrast on, the `increased`
    /// pair (light, dark) and alphas in place of them. Nonisolated, and its provider `@Sendable`:
    /// SwiftUI resolves colours on its render thread too, where a main-actor closure traps.
    nonisolated init(
        light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1, increased: (UInt32, UInt32)? = nil,
        increasedAlpha: (Double, Double)? = nil
    ) {
        let high = (light: increased?.0 ?? light, dark: increased?.1 ?? dark)
        let highAlpha = (light: increasedAlpha?.0 ?? lightAlpha, dark: increasedAlpha?.1 ?? darkAlpha)
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { @Sendable traits in
                let more = traits.accessibilityContrast == .high
                return traits.userInterfaceStyle == .dark
                    ? UIColor(rgb: more ? high.dark : dark, alpha: more ? highAlpha.dark : darkAlpha)
                    : UIColor(rgb: more ? high.light : light, alpha: more ? highAlpha.light : lightAlpha)
            })
        #else
        self.init(
            nsColor: NSColor(name: nil) { @Sendable appearance in
                switch appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua]) {
                case .darkAqua: NSColor(rgb: dark, alpha: darkAlpha)
                case .accessibilityHighContrastDarkAqua: NSColor(rgb: high.dark, alpha: highAlpha.dark)
                case .accessibilityHighContrastAqua: NSColor(rgb: high.light, alpha: highAlpha.light)
                default: NSColor(rgb: light, alpha: lightAlpha)
                }
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
    /// default text size; it grows with Dynamic Type to half again, or to the body text's size where
    /// that's more (a score in a row is never smaller than the words beside it), and shrinks to fit.
    func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        modifier(NumeralStyle(size: size, weight: weight))
    }

    /// The small uppercase label over a number or a group: "SET 2 OF 3", "USUALLY AROUND NOW".
    func eyebrow(_ color: Color = Ink.text3) -> some View {
        #if os(visionOS)
        // A coloured eyebrow is a lit one: on glass, full white over the usual grey (`Ink.words`).
        let color = color == Ink.text3 || color == Ink.text2 ? color : Ink.text
        #endif
        return font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(color)
    }
}

/// A unit beside a numeral: grows with Dynamic Type like the numeral does, to half again or the
/// caption's size, whichever is more.
private struct UnitStyle: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    @ScaledMetric(relativeTo: .caption) private var caption: CGFloat = 12
    private let size: CGFloat

    init(size: CGFloat) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.size = size
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(scaled, max(size * 1.5, caption)), weight: .semibold))
    }
}

private struct NumeralStyle: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    /// The body text's size now: past half again, a small numeral keeps growing with it. A hero's
    /// half again is already larger than any body text.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    private let size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: size >= 40 ? .largeTitle : .title2)
        self.size = size
        self.weight = weight
    }

    func body(content: Content) -> some View {
        let points = min(scaled, max(size * 1.5, bodySize))
        content
            .font(.system(size: points, weight: weight))
            .monospacedDigit()
            .tracking(-points * 0.035)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A hero number and what's beside it at its foot (how it moved), as the boards have it; under it
/// where the two don't fit on a line, as at the larger text sizes, rather than the number squeezed
/// to a sliver.
struct HeroRow<Number: View, Beside: View>: View {
    @ViewBuilder let number: Number
    @ViewBuilder let beside: Beside

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                number
                Spacer(minLength: 8)
                beside
            }
            VStack(alignment: .leading, spacing: 8) {
                number
                beside
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        // One phrase, "70 kg", rather than the number and its unit read as two.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([value, unit].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")))
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

// MARK: - Set back

extension View {
    /// Set back from the rest (a set done, a food still to come) by fading it to `opacity`. With
    /// Increase Contrast on it fades only a little, so its words, in that setting's stronger greys,
    /// still pass 4.5:1.
    func setBack(_ on: Bool, opacity: Double = 0.6) -> some View {
        modifier(SetBack(on: on, opacity: opacity))
    }
}

private struct SetBack: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let on: Bool
    let opacity: Double

    func body(content: Content) -> some View {
        content.opacity(on ? (contrast == .increased ? max(opacity, 0.8) : opacity) : 1)
    }
}

// MARK: - Motion

extension AnyTransition {
    /// Rising in from the bottom edge as it fades, or with Reduce Motion on, only the fade.
    static func rise(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
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

    /// A content card (`.card`): the card fill on the ground, 22-point continuous corners.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// The design's tight card of rows (`.card.tight`): 18-point corners, 14 points in from the sides.
    func tightCard() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }

    func floatingGlass(in shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = true) -> some View {
        adaptiveGlass(in: shape, tint: tint, interactive: interactive)
    }

    /// Rows of a form or list as quiet cards on the ink ground, rather than the system's grey (a
    /// sheet's lighter grey in dark mode). A row that sets its own background keeps it.
    func inkRows() -> some View {
        #if os(iOS)
        return listRowBackground(Color.cardBackground)
        #else
        return self
        #endif
    }

    /// Readable line length on iPad.
    func readableWidth(_ width: CGFloat = 720) -> some View { frame(maxWidth: width).frame(maxWidth: .infinity) }

    /// A choice's tint: the accent when picked, grey otherwise. On Vision Pro's glass a grey tint is
    /// white on white, so there an unpicked choice keeps the system's own glass.
    func choiceTint(_ picked: Bool) -> some View {
        #if os(visionOS)
        tint(picked ? Color.accentColor : nil)
        #else
        tint(picked ? Color.accentColor : .secondary)
        #endif
    }
}

// MARK: - Pages

/// A screen's title as the design sets it (`.title`): 32 points, bold and tightly tracked, growing
/// with the text size to half again, and wrapping rather than shrinking.
struct PageTitle: View {
    let text: String
    @ScaledMetric private var scaled: CGFloat
    private let size: CGFloat

    init(_ text: String, size: CGFloat = 32) {
        self.text = text
        self.size = size
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        let points = min(scaled, size * 1.5)
        Text(text)
            .font(.system(size: points, weight: .bold))
            .tracking(-points * 0.035)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tab's header on a phone, where the design has it rather than a navigation bar: what the screen
/// is about as an eyebrow, the title, and its round buttons beside them.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    @ViewBuilder let trailing: Trailing

    init(eyebrow: String?, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        PageHeading(eyebrow: eyebrow, title: title, trailing: trailing).padding(.top, 8)
    }
}

/// A pushed page's header on a phone: the eyebrow (where it was opened from) over the title, under
/// the bar's round back button. The bar stays, title-less, so the edge swipe still goes back
/// (`detailPage(title:wide:)`).
struct DetailHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    @ViewBuilder let trailing: Trailing

    init(eyebrow: String? = nil, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        PageHeading(eyebrow: eyebrow, title: title, trailing: trailing)
            .padding(.top, 2)
            // As a list's row, on the ground and clear of the corners: an inset grouped list rounds
            // each section's first and last rows, clear background or not, and the round cut the
            // eyebrow's first letter and the foot of the title's. Outside a list these do nothing.
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 12, trailing: 0))
    }
}

private struct PageHeading<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let eyebrow: String?
    let title: String
    let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // A line, until the accessibility sizes leave a line a word or two beside the buttons.
                if let eyebrow { Text(eyebrow).eyebrow().lineLimit(typeSize.isAccessibilitySize ? 3 : 1) }
                PageTitle(title)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, 4)
    }
}

extension View {
    /// A pushed phone page that sets its own title large (`DetailHeader`): the bar keeps only its
    /// round back button, and the tab bar goes, as on the design's detail screens. Wide windows keep
    /// their bar and its title.
    func detailPage(title: String, wide: Bool) -> some View {
        navigationTitle(title)
            .inlineTitle()
            #if os(iOS)
        .toolbar(removing: wide ? nil : .title)
        .toolbarVisibility(wide ? .automatic : .hidden, for: .tabBar)
            #endif
    }
}

/// A round button's face (`.ibtn`): a symbol on the card colour, 44 points across. A menu's label
/// too, where `CircleIconButton` can't be.
struct CircleIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Ink.text)
            .frame(width: 44, height: 44)
            // The card colour is a black disc on Vision Pro's glass: there, the system's material, as
            // a card has.
            #if os(visionOS)
        .background(.regularMaterial, in: .circle)
            #else
        .background(Ink.surface, in: .circle)
            #endif
            .contentShape(.circle)
    }
}

/// A round icon button, as in a page's header.
struct CircleIconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CircleIcon(symbol: symbol) }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }
}

/// Onboarding's top: back, a thin ruler filling a step at a time, and how far along ("2 of 9").
struct StepBar: View {
    let step: Int
    let count: Int
    let back: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CircleIconButton(symbol: "chevron.left", label: "Back", identifier: "onboarding.back", action: back)
            Ruler.thin(Double(step) / Double(max(1, count)))
                .accessibilityHidden(true)
            Text("\(step) of \(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Ink.text3)
                .frame(minWidth: 44, alignment: .trailing)
                .accessibilityLabel("Step \(step) of \(count)")
        }
    }
}

/// An onboarding step's question and what it's for: the title larger than a page's, as the
/// design's first run has it.
struct StepHeading: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageTitle(title, size: 36)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Controls

/// The design's buttons (`.btn`): the accent filled for the one action on a screen (`.solid`), the
/// raised grey for the rest (`.ghost`). The control size sets the height: 52 points large, 44
/// regular (`.btn.sm`), 34 small, so a small one still fits in a row.
struct InkButtonStyle: ButtonStyle {
    var filled = true
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let (height, radius, inset): (CGFloat, CGFloat, CGFloat) =
            switch size {
            case .mini, .small: (34, 12, 12)
            case .large, .extraLarge: (52, 16, 20)
            default: (44, 14, 16)
            }
        configuration.label
            .font(height >= 52 ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(filled ? Ink.onAccent : Ink.text)
            .padding(.horizontal, inset)
            .frame(minHeight: height)
            .background(filled ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
            .hoverHighlight()
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    /// The accent, filled: the one action that matters on a screen.
    static var solid: InkButtonStyle { InkButtonStyle(filled: true) }
    /// The raised grey: every other button.
    static var ghost: InkButtonStyle { InkButtonStyle(filled: false) }
}

extension View {
    /// The one action that matters on a screen: filled with the accent. Vision Pro keeps its own
    /// prominent button over the glass.
    func primaryAction() -> some View {
        #if os(visionOS)
        prominentGlassButtonStyle().buttonBorderShape(.capsule)
        #else
        buttonStyle(.solid)
        #endif
    }

    func secondaryAction() -> some View {
        #if os(visionOS)
        // Untinted: under the app's accent tint Vision Pro fills a bordered button with it, which
        // made every secondary action (the rest's −15, +15 and Skip) as loud as the one that matters.
        glassButtonStyle().buttonBorderShape(.capsule).tint(nil as Color?)
        #else
        buttonStyle(.ghost)
        #endif
    }
}

/// A few choices on the raised grey, the chosen one lifted onto the card colour (`.seg`).
struct InkSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(on ? Ink.text : Ink.text2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ControlFill.chosen)
                                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ControlFill.track, in: .rect(cornerRadius: 13, style: .continuous))
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

/// What a segmented control and a chip are drawn on: the raised grey, the chosen one lifted onto the
/// card colour. On Vision Pro's glass those greys are black slabs, so there they're the system's
/// material and a brighter wash of white, as a round button's there.
enum ControlFill {
    static var track: AnyShapeStyle {
        #if os(visionOS)
        AnyShapeStyle(.regularMaterial)
        #else
        AnyShapeStyle(Ink.raised)
        #endif
    }

    static var chosen: AnyShapeStyle {
        #if os(visionOS)
        AnyShapeStyle(Color.white.opacity(0.3))
        #else
        AnyShapeStyle(Ink.surface)
        #endif
    }
}

/// A small rounded label.
struct Pill: View {
    let text: String
    var symbol: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        #if os(visionOS)
        // On glass a tint's own text over a faint wash of it can't be read: the tint fills the
        // capsule instead, under white text.
        .foregroundStyle(color == .secondary ? color : .white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color == .secondary ? color.opacity(0.14) : color.opacity(0.7), in: .capsule)
        #else
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .capsule)
        #endif
    }
}

// MARK: - Cards and rows

/// A card's title over its number or chart (`.h3`), with a note at the right: "Your scores … All
/// progress".
struct CardTitle: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        TitleLine(stacked: typeSize.isAccessibilitySize) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).accessibilityAddTraits(.isHeader)
        } detail: {
            if let detail { Text(detail).font(.caption).foregroundStyle(Ink.text3) }
        }
    }
}

/// A title with a note at its right, as a card's and a group's are; where the two can't share a
/// line (always at the accessibility sizes), the note goes under the title, whole.
private struct TitleLine<Title: View, Detail: View>: View {
    let stacked: Bool
    @ViewBuilder let title: Title
    @ViewBuilder let detail: Detail

    var body: some View {
        if stacked {
            under
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 8)
                    detail.lineLimit(1)
                }
                under
            }
        }
    }

    private var under: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
            detail.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A group's eyebrow, on the page or at the top of a card, with a note at the right: "USUALLY
/// AROUND NOW … One tap logs it".
struct SectionEyebrow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        TitleLine(stacked: typeSize.isAccessibilitySize) {
            Text(title).eyebrow().accessibilityAddTraits(.isHeader)
        } detail: {
            if let detail { Text(detail).font(.caption).foregroundStyle(Ink.text3) }
        }
    }
}

/// Small uppercase labels along an axis or under a ruler (`.scale`): 10 points at the default text
/// size, growing with it to 16. They share a line with their neighbours, so they stop there and
/// shrink to fit; what they mark is said in full beside them (and to VoiceOver).
struct ScaleLabel: View {
    let text: String
    var highlighted = false
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    init(_ text: String, highlighted: Bool = false) {
        self.text = text
        self.highlighted = highlighted
    }

    var body: some View {
        Text(text)
            .font(.system(size: min(size, 16), weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(highlighted ? Ink.text : Ink.text3)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Rows in a tight card with hairlines between (`.card.tight` of `.list`), under an optional eyebrow
/// inside the card.
struct RowCard<Content: View>: View {
    var title: String?
    var detail: String?
    var minHeight: CGFloat = 52
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { rows in
            // Nothing to show: no empty card.
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if let title {
                        SectionEyebrow(title, detail: detail)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                        // A row that's a button (`rowButton()`) has its padding inside it, so the
                        // whole row is hit, not only its words.
                        row.padding(.vertical, row.containerValues.isRowButton ? 0 : 8).frame(minHeight: minHeight)
                    }
                }
                .tightCard()
                .environment(\.rowMinHeight, minHeight)
            }
        }
    }
}

extension View {
    /// A `RowCard`'s row that opens or does something: the row's full height to hit (at least 44
    /// points), where a plain button's would be only its words.
    func rowButton() -> some View {
        buttonStyle(RowButtonStyle()).containerValue(\.isRowButton, true)
    }
}

/// A row's button in a `RowCard`: the card's padding and height inside it, as a hit area.
struct RowButtonStyle: ButtonStyle {
    @Environment(\.rowMinHeight) private var minHeight
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: max(44, minHeight), alignment: .leading)
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.42)
    }
}

extension ContainerValues {
    @Entry var isRowButton = false
}

extension EnvironmentValues {
    /// The rows' least height in the `RowCard` around them.
    @Entry var rowMinHeight: CGFloat = 44
}

/// A row that opens something: a title, a caption under it, a value, and a chevron.
struct LinkRowLabel: View {
    let title: String
    var caption: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                if let caption, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.text3)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A section heading inside a scrolling page.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An empty state with a single next step.
struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(Ink.text3)
            Text(title).font(.headline).foregroundStyle(Ink.text)
            Text(detail).font(.subheadline).foregroundStyle(Ink.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

/// A list's bullet: a small dot on the first line.
struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary).alignmentGuide(.firstTextBaseline) {
                $0[VerticalAlignment.center] + 4
            }
            configuration.title
        }
    }
}

// MARK: - Sheets

// Sheets on the boards' terms rather than the system's: no bar of glass capsules over a small
// title, but the page's own furniture. A round close at the top left (as a page's header has its
// round buttons), the title set large in the content under an eyebrow saying where the sheet came
// from (`FormHeading`, `SheetHeading`), rows on cards under eyebrows, and the one action full width
// at the foot (as onboarding's Continue); Delete and the like are ghost buttons under the cards
// (`FormActionRow`). A sheet still swipes down to close. On the Mac, which has no swipe, the close
// is a button at the top right that says what it does (`Platform.closesSheetsInWords`).

/// A sheet's top: the close and, beside it, a round button or a small action. What scrolls passes
/// under it, except on the Mac, where it sits above.
struct SheetBar<Trailing: View>: View {
    let symbol: String
    let label: String
    let identifier: String
    let close: () -> Void
    let trailing: Trailing

    init(
        symbol: String = "xmark", label: String = "Close", identifier: String, close: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.symbol = symbol
        self.label = label
        self.identifier = identifier
        self.close = close
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            if Platform.closesSheetsInWords {
                Spacer(minLength: 8)
                trailing
                Button(label, action: close)
                    .buttonStyle(.ghost)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(identifier)
            } else {
                CircleIconButton(symbol: symbol, label: label, identifier: identifier, action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Color.pageBackground)
    }
}

/// A sheet's one action (and a quiet one beside it, if any), full width at the foot on the ground,
/// what scrolls fading under it.
struct SheetFoot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .readableWidth(620)
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.pageBackground.opacity(0), Color.pageBackground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                )
                .padding(.top, -20)
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    /// A sheet that draws its own bar (`SheetBar`) and foot (`SheetFoot`) in place of the system's
    /// navigation bar, on the ink ground.
    func inkSheet<Bar: View, Foot: View>(@ViewBuilder bar: () -> Bar, @ViewBuilder foot: () -> Foot) -> some View {
        // Grouped on the Mac too, where a sheet's form would otherwise set its rows in columns.
        formStyle(.grouped)
            .sheetChrome(bar: bar(), foot: foot())
            .background(.pageBackground)
    }

    /// A sheet with its own bar and nothing at the foot: one that closes, or acts from its rows.
    func inkSheet<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        // No foot at all: an empty one there leaves the content nothing to show in.
        formStyle(.grouped)
            .sheetChrome(bar: bar(), foot: Never?.none)
            .background(.pageBackground)
    }

    /// A row of a form that sits on the ground rather than on a card: its buttons.
    func groundRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets())
    }

    /// A page pushed inside a sheet or Settings that sets its own title large (`FormHeading`): the
    /// bar keeps only its round back button. The Mac's panes keep their window title, and no heading.
    func formPage(_ title: String) -> some View {
        detailPage(title: title, wide: false)
    }
}

/// A form's title, set large at its top as a pushed page's is: `DetailHeader` (where it was opened
/// from, and the title) and what it's for, on the ground as the form's first section's header,
/// where the words of a list go (`DetailHeader` keeps clear of a row's corners too, but a header
/// needs no room left for them).
struct FormHeading: View {
    var eyebrow: String?
    let title: String
    var detail: String?

    var body: some View {
        Section {
        } header: {
            SheetHeading(eyebrow: eyebrow, title: title, detail: detail)
                .textCase(nil)
                .padding(.bottom, 4)
                .listRowInsets(EdgeInsets())
        }
    }
}

/// A sheet's title in a scrolling page: `DetailHeader`, and what it's for under it.
struct SheetHeading: View {
    var eyebrow: String?
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailHeader(eyebrow: eyebrow, title: title)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Search in a sheet's content, on the raised grey, rather than the system's field in its bar.
struct InkSearchField: View {
    @Binding var text: String
    let prompt: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ink.text3).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .font(.callout)
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Ink.raised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// One of several things that can each be on (the joints that hurt, a supplement's days), as the
/// weekday chips are: the accent when on, the raised grey when off.
struct ChoiceChip: View {
    let title: String
    let isOn: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? AnyShapeStyle(Color.accentColor) : ControlFill.track, in: .rect(cornerRadius: 12, style: .continuous))
                .foregroundStyle(isOn ? Ink.onAccent : Ink.text)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A label over a value in a card's row: "From", "Nov 20".
struct ValueRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let value: String

    var body: some View {
        // The value under its label at the accessibility sizes, rather than both broken into a column each.
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(title).font(.subheadline).foregroundStyle(Ink.text2)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A form's quiet action on the ground under its cards: Delete, Remove, End it now. Destructive ones
/// say so in red.
struct FormActionRow: View {
    let title: String
    var destructive = false
    let identifier: String?
    let action: () -> Void

    init(_ title: String, destructive: Bool = false, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(destructive ? Ink.bad : Ink.text).frame(maxWidth: .infinity)
        }
        .buttonStyle(.ghost)
        .controlSize(.large)
        .accessibilityIdentifier(identifier ?? "")
        .groundRow()
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

// MARK: - How a score moved

extension ScoreChange {
    /// Up in good, down in ok (worth a look, not an alarm), steady in the second grey.
    var color: Color {
        switch direction {
        case .up: Ink.good
        case .down: Ink.ok
        case .steady: Ink.text2
        }
    }

    /// Its words: the colour, but white on Vision Pro's glass (`Ink.words`), where the sign says it.
    var wordColor: Color { direction == .steady ? Ink.text2 : Ink.words(color) }
}

/// A score's change this month beside it, as the boards have it: "+2", "−1" or "steady".
struct ScoreChangeLabel: View {
    let change: ScoreChange

    var body: some View {
        Text(change.short)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(change.wordColor)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(change.spoken(calendar: .current))
    }
}

/// The chip beside a large score: "+2 this month", "+3 since August", with an arrow while it moves.
struct ScoreChangeChip: View {
    let change: ScoreChange

    var body: some View {
        HStack(spacing: 4) {
            if change.direction != .steady {
                Image(systemName: change.direction == .up ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
            }
            Text(change.text(calendar: .current))
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(change.wordColor)
        .padding(.horizontal, 11)
        .frame(minHeight: 28)
        // On glass the faint wash is lost: the colour fills the chip under white words, as a `Pill` does there.
        .background(change.color.opacity(Platform.isVision && change.direction != .steady ? 0.7 : 0.14), in: .capsule)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(change.spoken(calendar: .current))
    }
}

/// Under Your shape with an outline behind it: the solid line is now, the dashed one the scores as
/// they stood when a month began.
struct ShapeLegend: View {
    let earlier: EarlierShape

    var body: some View {
        let month = earlier.period.monthName(calendar: .current) ?? ""
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Capsule().fill(Color.accentColor).frame(width: 16, height: 2.2)
                Text("Now")
            }
            HStack(spacing: 6) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1))
                    path.addLine(to: CGPoint(x: 16, y: 1))
                }
                .stroke(Ink.text2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 16, height: 2)
                Text(month)
            }
        }
        .font(.caption)
        .foregroundStyle(Ink.text2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The solid shape is now, the dashed one as it was when \(month) began"))
    }
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

    /// The six axes from the stats board, in drawing order, with the scores as they stood some time
    /// ago (`StatsBoard.earlier`) for the dashed outline.
    static func axes(_ lines: [StatLine], earlier: EarlierShape? = nil) -> [Axis] {
        order.map { stat in
            let line = lines.first { $0.stat == stat }
            return Axis(stat: stat, score: line?.score, earlier: earlier?.scores[stat], apps: line?.apps ?? [])
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
