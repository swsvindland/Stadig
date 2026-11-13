import CoreText
import SwiftUI
import UIKit
import WatchKit

// The faces' look, from the design's Watch board: the face is the gauge, numbers set big, the one
// action a band of the accent across the foot of the screen that Double Tap presses. The Watch has no
// Stadig.swift; its colours are the dark palette's (the Watch is always dark), and its accent the
// asset catalog's. Stadig Lift's Watch draws its faces with the same pieces (`WatchFaces.swift`):
// change both together.

enum WristInk {
    static let text = Color(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEE / 255)
    static let text2 = Color(red: 0xB1 / 255, green: 0xB2 / 255, blue: 0xAD / 255)
    static let text3 = Color(red: 0x8D / 255, green: 0x8F / 255, blue: 0x8A / 255)
    static let surface = Color(red: 0x17 / 255, green: 0x19 / 255, blue: 0x1C / 255)
    static let raised = Color(red: 0x21 / 255, green: 0x24 / 255, blue: 0x29 / 255)
    /// Text and marks on the accent: the deep green-black the phone's dark theme uses.
    static let onAccent = Color(red: 0x04 / 255, green: 0x29 / 255, blue: 0x1A / 255)
}

/// The design draws its faces 198 points wide (a 45 mm screen); the big numbers scale with the
/// screen from there, so a 40 mm Watch sets them smaller and a 46 mm one a touch larger.
enum WristFace {
    static let width = WKInterfaceDevice.current().screenBounds.width
    static let scale = min(1.05, width / 198)
    /// The 40 and 41 mm Watches.
    static let small = width < 180
    /// The band's height: the design's 60 points, less on the smallest screens.
    static let band: CGFloat = small ? 52 : 60
    /// The design's 16-point margins, 12 on the smallest screens.
    static let margin: CGFloat = small ? 12 : 16
    /// Room left at the top right for the time, from the screen's edge (the system draws it there): a face's top line
    /// shares its row.
    static let clock: CGFloat = small ? 52 : 58

    /// The size, the design's `nominal` scaled to this screen at most, at which numbers set side by
    /// side fit across the face beside `fixed` points of other things (margins, the "×").
    static func numeralSize(_ nominal: CGFloat, fitting texts: [String], besides fixed: CGFloat) -> CGFloat {
        let points = nominal * scale
        let total = texts.map { numeralWidth($0, points: points) }.reduce(0, +)
        let available = width - fixed
        guard total > available, total > 0 else { return points }
        return max(points * 0.5, (points * available / total).rounded(.down))
    }

    /// How wide a face's numeral sets `text` at `points`; a trailing "+" is set smaller, as a rep-out's is.
    static func numeralWidth(_ text: String, points: CGFloat) -> CGFloat {
        let plus = text.hasSuffix("+")
        let digits = plus ? String(text.dropLast()) : text
        let font = UIFont.monospacedDigitSystemFont(ofSize: points, weight: .heavy)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: digits, attributes: [.font: font, .kern: -points * 0.055]) as CFAttributedString)
        let measured = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // SF's heavy figures are about 0.62 of the size, a point 0.3, should the measure come back empty.
        let estimate = digits.reduce(CGFloat(0)) { $0 + ($1.isNumber ? 0.62 : 0.3) * points }
        return max(measured, estimate * 0.9) + (plus ? points * 0.4 : 0)
    }
}

extension View {
    /// A face's words at the design's size, growing with Dynamic Type to half again.
    func faceFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(FaceFont(size: size, weight: weight))
    }

    /// A face's big number: heavy, tabular, tightly tracked.
    func faceNumeral(points: CGFloat) -> some View {
        font(.system(size: points, weight: .heavy))
            .monospacedDigit()
            .tracking(-points * 0.055)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }

    /// A face's top line, sharing its row with the time: it keeps clear of the time, and takes a second
    /// line before it shrinks much.
    func faceTopLine() -> some View {
        lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, WristFace.clock - WristFace.margin)
            .padding(.top, 18)
    }

    /// The small uppercase label at the top of a face: "BENCH PRESS", "KCAL LEFT TODAY".
    func faceEyebrow(_ color: Color) -> some View {
        faceFont(13, weight: .semibold)
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

private struct FaceFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        // The design's size on its 45 mm face, a little smaller on the smallest Watches; text sizes
        // larger than the default (large on the small Watches, extra large on the others) make it
        // larger, to half again.
        let grow: CGFloat =
            switch typeSize {
            case ...DynamicTypeSize.xLarge: 1
            case .xxLarge: 1.12
            case .xxxLarge: 1.25
            default: 1.5
            }
        content.font(.system(size: size * max(0.92, WristFace.scale) * grow, weight: weight))
    }
}

/// Double Tap's mark: two chevrons pinching toward a dot, beside whatever the gesture presses.
struct DoubleTapGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            var chevrons = Path()
            chevrons.move(to: CGPoint(x: 2.5 * s, y: 7.5 * s))
            chevrons.addLine(to: CGPoint(x: 7 * s, y: 12 * s))
            chevrons.addLine(to: CGPoint(x: 2.5 * s, y: 16.5 * s))
            chevrons.move(to: CGPoint(x: 21.5 * s, y: 7.5 * s))
            chevrons.addLine(to: CGPoint(x: 17 * s, y: 12 * s))
            chevrons.addLine(to: CGPoint(x: 21.5 * s, y: 16.5 * s))
            context.stroke(chevrons, with: .foreground, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round, lineJoin: .round))
            for x in [10.1, 13.9] {
                context.fill(Path(ellipseIn: CGRect(x: (x - 1.5) * s, y: 10.5 * s, width: 3 * s, height: 3 * s)), with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The band across the foot of a face: the accent, edge to edge, carrying the one thing Double Tap
/// does, and sometimes a number at its end ("1,455 left").
struct ActionBand: View {
    let title: String
    var detail: String?
    /// Whether Double Tap presses it: only the face in view's band, where several are laid out.
    var doubleTap = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WristFace.small ? 6 : 8) {
                DoubleTapGlyph(size: WristFace.small ? 19 : 22)
                Text(title)
                    .font(.system(size: WristFace.small ? 18 : 20, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Spacer(minLength: 4)
                    Text(detail).faceFont(13, weight: .bold).monospacedDigit().lineLimit(1).fixedSize().layoutPriority(1)
                }
            }
            .foregroundStyle(WristInk.onAccent)
            .padding(.horizontal, WristFace.small ? 14 : 20)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, minHeight: WristFace.band, maxHeight: WristFace.band)
            .background(Color.accentColor)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction, isEnabled: doubleTap)
    }
}

/// A face's edge marked in tenths from the foot, as a level is read: on the ground in grey, on the
/// level in ink.
struct EdgeTicks: View {
    var color: Color = .white.opacity(0.26)

    var body: some View {
        Canvas { context, size in
            for index in 1..<10 {
                let y = size.height * (1 - Double(index) / 10)
                context.fill(Path(CGRect(x: size.width - 9, y: y - 0.75, width: 9, height: 1.5)), with: .color(color))
            }
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// A face's hero number as the design sets it: heavy and tight, in a box no taller than its digits
/// (the design's line height of 0.9), so what's under it sits close; a rep-out's "+" raised beside it.
struct BigNumber: View {
    let value: String
    /// Its size in points (`WristFace.numeralSize` fits it to the screen).
    let points: CGFloat
    var plus = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value).faceNumeral(points: points)
            if plus {
                Text("+")
                    .font(.system(size: points * 0.6, weight: .heavy))
                    .baselineOffset(points * 0.6 * 0.24)
            }
        }
        // SF's line is 1.19 of its size; the design's is 0.9: take the difference off both ends.
        .padding(.vertical, -points * 0.146)
    }
}
