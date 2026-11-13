import NutritionEngine
import SwiftUI
import SystemCore

/// While typing: the header in a line, what's left now and after what's typed. Today's, and the
/// same at the top of any tab or the logger while its composer has the keyboard.
struct TypingHeader: View {
    let targets: DailyTargets?
    let eaten: Nutrients
    let adding: Nutrients?

    var body: some View {
        let after = eaten + (adding ?? .zero)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let kcal = targets?.kcal {
                    Text(Format.whole(kcal - eaten.kcal)).numeral(30)
                    if adding != nil {
                        Text("→ \(Format.whole(kcal - after.kcal))").numeral(30).foregroundStyle(Color.accentColor)
                    }
                    Text("kcal left").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                } else {
                    Text(Format.whole(eaten.kcal)).numeral(30)
                    if adding != nil { Text("→ \(Format.whole(after.kcal))").numeral(30).foregroundStyle(Color.accentColor) }
                    Text("kcal eaten").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                }
            }
            .contentTransition(.numericText())
            if let kcal = targets?.kcal, kcal > 0 { Ruler.thin(after.kcal / kcal) }
            Text(line(after)).font(.caption).foregroundStyle(Ink.text2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .animation(.snappy, value: adding)
        // In words, "1,601 kcal left, 1,511 after it", where the arrow would be read as one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(after))
        .accessibilityIdentifier("today.typingHeader")
    }

    func spoken(_ after: Nutrients) -> String {
        let kcal: String
        if let target = targets?.kcal {
            kcal =
                "\(Format.whole(target - eaten.kcal)) kcal left" + (adding == nil ? "" : ", \(Format.whole(target - after.kcal)) after it")
        } else {
            kcal = "\(Format.whole(eaten.kcal)) kcal eaten" + (adding == nil ? "" : ", \(Format.whole(after.kcal)) with it")
        }
        let macros = line(after)
        return macros.isEmpty ? kcal : "\(kcal). \(macros)"
    }

    /// "Then 82 g protein · 168 g carbs · 54 g fat left".
    func line(_ after: Nutrients) -> String {
        let parts = [("protein", after.protein, targets?.protein), ("carbs", after.carbs, targets?.carbs), ("fat", after.fat, targets?.fat)]
            .compactMap { name, value, target in target.map { "\(Format.whole(max(0, $0 - value))) g \(name)" } }
        guard !parts.isEmpty else { return "" }
        return (adding == nil ? "" : "Then ") + parts.joined(separator: " · ") + " left"
    }
}
