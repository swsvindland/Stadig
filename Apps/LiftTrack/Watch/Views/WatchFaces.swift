import LiftEngine
import SwiftUI
import SystemCore

// The faces' look, from the design's Watch board: the face is the gauge, numbers set big, the one
// action a full-width band of the accent that Double Tap presses. The Watch has no Stadig.swift; its
// colours are the dark palette's, and its accent the asset catalog's.

enum WatchInk {
    /// Text and marks on the accent: the deep ink the phone's dark theme uses.
    static let onAccent = Color(red: 0x0B / 255, green: 0x10 / 255, blue: 0x30 / 255)
    static let good = Color(red: 0x3E / 255, green: 0xCF / 255, blue: 0x8E / 255)
    static let ok = Color(red: 0xF5 / 255, green: 0xB5 / 255, blue: 0x44 / 255)
    static let bad = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255)
    static let track = Color.white.opacity(0.16)
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

/// Where a set sits in its group (the warm-ups, or the work): a short bar for each, the done ones
/// grey, this one in the accent.
struct SetDots: View {
    let index: Int
    let sets: [LiveSet]

    var body: some View {
        let warmup = sets[index].prescription.kind == .warmup
        let group = sets.indices.filter { (sets[$0].prescription.kind == .warmup) == warmup }
        HStack(spacing: 4) {
            ForEach(group, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Color.accentColor : position < index ? Color.white.opacity(0.55) : WatchInk.track)
                    .frame(width: group.count > 6 ? 10 : 18, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchFormat.setPosition(index, in: sets))
    }
}

/// The band at the foot of a face: the accent, edge to edge, carrying the one thing Double Tap does.
struct ActionBand<Trailing: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 8) {
                    DoubleTapGlyph(size: 20)
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .tracking(-0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction)
            trailing
        }
        .foregroundStyle(WatchInk.onAccent)
        .padding(.horizontal, 8)
        .background(Color.accentColor, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

extension ActionBand where Trailing == EmptyView {
    init(title: String, action: @escaping () -> Void) {
        self.init(title: title, action: action) { EmptyView() }
    }
}
