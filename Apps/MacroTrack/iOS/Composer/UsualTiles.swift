import NutritionEngine
import SwiftUI
import SystemCore

/// The usual foods for now, or what goes with the meal being eaten, one tap each: over Today's field,
/// and over any tab's while it's empty and has the keyboard.
struct UsualTiles: View {
    let composer: TodayComposer
    /// Four, or a row of two at the accessibility sizes, where the thread needs the room.
    let most: Int
    /// Where it is, for the UI tests: "today" on Today, "tab" on the others.
    var prefix = "today"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(composer.tilesTitle, detail: "One tap logs it")
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(composer.tiles.prefix(most).enumerated()), id: \.element.id) { index, item in
                    Button {
                        composer.log(item)
                    } label: {
                        HStack(spacing: 10) {
                            FoodTile(name: item.template.name, fill: Ink.raised)
                            VStack(alignment: .leading, spacing: 1) {
                                // "Chicken breast" is a few points wider than half a phone's tile.
                                Text(FoodLabel.title(item.template.name)).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                Text("\(item.template.amountLabel) · \(Format.whole(item.template.nutrients.kcal)) kcal")
                                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(prefix).usual.\(index)")
                    .accessibilityLabel(
                        "Log \(FoodLabel.short(item.template.name)), \(item.template.amountLabel), \(Format.kcal(item.template.nutrients.kcal))")
                }
            }
        }
    }
}
