import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

// The complications' views, compiled into the complications and into the Watch app, whose DEBUG
// gallery (`-complications`) draws them with the app's own numbers.

/// Which macro a complication shows, and how it's worded.
enum ComplicationMacro {
    case kcal, protein

    var symbol: String { self == .kcal ? "flame.fill" : "p.circle.fill" }
    var color: Color { self == .kcal ? .accentColor : .pink }
    var name: String { self == .kcal ? "Calories" : "Protein" }
    /// The unit after a number: "1,060 kcal", "74 g".
    var unit: String { self == .kcal ? "kcal" : "g" }

    func progress(_ snapshot: WristSnapshot) -> MacroProgress { self == .kcal ? snapshot.kcal : snapshot.protein }
}

/// What's left: "1,060" and "left", "120" and "over", or before targets, "1,240" and "eaten".
struct ComplicationText {
    var value: String
    var word: String

    init(_ progress: MacroProgress) {
        let number = progress.left.map(abs) ?? progress.eaten
        value = Int(number.rounded()).formatted()
        word = progress.left == nil ? "eaten" : progress.isOver ? "over" : "left"
    }

    /// "1,060 kcal left", for VoiceOver and the inline family.
    func sentence(_ macro: ComplicationMacro) -> String { "\(value) \(macro.unit) \(macro == .protein ? "protein " : "")\(word)" }
}

/// One macro on the watch face, in the family given (the widget passes the face's; the Watch app's
/// DEBUG gallery passes each in turn).
struct MacroComplication: View {
    let macro: ComplicationMacro
    let snapshot: WristSnapshot
    let family: WidgetFamily

    private var progress: MacroProgress { macro.progress(snapshot) }
    private var text: ComplicationText { ComplicationText(progress) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    @ViewBuilder private var circular: some View {
        if let fraction = progress.fraction {
            Gauge(value: fraction) {
                Image(systemName: macro.symbol)
            } currentValueLabel: {
                Text(text.value)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(macro.color)
            .widgetAccentable()
            .accessibilityLabel(text.sentence(macro))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: macro.symbol)
                        .font(.caption)
                        .widgetAccentable()
                    Text(text.value)
                        .font(.caption.monospacedDigit())
                        .minimumScaleFactor(0.5)
                }
                .padding(4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.sentence(macro))
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(macro.name, systemImage: macro.symbol)
                .font(.headline)
                .foregroundStyle(macro.color)
                .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text.value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("\(macro.unit) \(text.word)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fraction = progress.fraction {
                Gauge(value: fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(macro.color)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.sentence(macro))
    }

    private var inline: some View {
        Label(text.sentence(macro), systemImage: macro.symbol)
    }

    private var corner: some View {
        Image(systemName: macro.symbol)
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                if let fraction = progress.fraction {
                    Gauge(value: fraction) {
                        Text(macro.unit)
                    } currentValueLabel: {
                        Text(text.value)
                    }
                    .tint(macro.color)
                } else {
                    Text("\(text.value) \(macro.unit)")
                }
            }
            .accessibilityLabel(text.sentence(macro))
    }
}

/// Calories and protein left, each with its bar: the Smart Stack's card.
struct TodayStackView: View {
    let snapshot: WristSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(.kcal)
            row(.protein)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ComplicationText(snapshot.kcal).sentence(.kcal)), \(ComplicationText(snapshot.protein).sentence(.protein))")
    }

    private func row(_ macro: ComplicationMacro) -> some View {
        let progress = macro.progress(snapshot)
        let text = ComplicationText(progress)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: macro.symbol)
                    .font(.caption)
                    .foregroundStyle(macro.color)
                    .widgetAccentable()
                Text("\(text.value) \(macro.unit)")
                    .font(.headline.monospacedDigit())
                Text(text.word)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if let fraction = progress.fraction {
                Gauge(value: fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(macro.color)
            }
        }
    }
}
