import SwiftUI
import WidgetKit

// The complications' share of Stadig's look (docs/design.md), from the iPhone app's
// `Components/Stadig.swift` and the widgets' `WidgetInk.swift`, neither of which this extension can
// see. A watch face is black or tinted by the face, so there's no paper here: greys are hierarchical
// styles and the track is translucent, which every rendering mode keeps.

extension View {
    /// A number set as the hero: heavy, tabular, tightly tracked, shrinking to fit the complication.
    func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(.system(size: size, weight: weight))
            .monospacedDigit()
            .tracking(-size * 0.035)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// The small uppercase label over a number or a name: "TODAY · 60 MIN".
    func eyebrow(size: CGFloat = 11) -> some View {
        font(.system(size: size, weight: .semibold)).textCase(.uppercase).tracking(size * 0.06).lineLimit(1)
    }
}

/// This week's sessions as a strip of segments, done ones filled in the accent.
struct WeekStrip: View {
    let done: Int
    let planned: Int
    var height: CGFloat = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(planned, 1), id: \.self) { index in
                if index < done {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.accentColor).widgetAccentable()
                } else {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.primary.opacity(0.25))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
