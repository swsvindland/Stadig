import NutritionEngine
import SwiftUI
import SystemCore

/// A past day being caught up: each time this person usually eats with nothing logged near it yet,
/// what they last ate then a tap away, and the logger a tap away at that time for something else.
/// "Log all" is the whole typical day at once.
struct CatchUpSection: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let missing = model.catchUp
        Section {
            Label(
                missing.isEmpty
                    ? "Catching up \(Format.relative(day, today: model.today)). New entries land on that day."
                    : "Catching up \(Format.relative(day, today: model.today)): what you usually eat, a tap each. Tap a time to log something else then.",
                systemImage: "clock.arrow.circlepath"
            )
            .font(.subheadline)
            ForEach(missing) { usual in
                CatchUpRow(usual: usual)
            }
            if missing.count > 1 {
                Button {
                    model.catchUpAll()
                } label: {
                    Label(
                        "Log all \(missing.count) · \(Format.kcal(missing.map(\.latest.nutrients.kcal).reduce(0, +)))",
                        systemImage: "plus.circle")
                }
                .hoverHighlight()
                .accessibilityIdentifier("catchUp.logAll")
            }
        }
    }
}

/// A usual time still to catch up: the time and what was last eaten then, which + logs; a tap on
/// the rest opens the logger at that time, ranked for it.
struct CatchUpRow: View {
    @Environment(AppModel.self) private var model
    let usual: UsualMeal

    var body: some View {
        let name = model.name(of: usual.latest)
        let time = Format.time(usual.time)
        let when = Format.relative(Day(usual.latest.start), today: model.today)
        HStack(spacing: 12) {
            Button {
                model.openLogger(.search, at: usual.time)
            } label: {
                HStack(spacing: 12) {
                    Text(time).font(.subheadline.weight(.semibold).monospacedDigit()).frame(minWidth: 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).lineLimit(1)
                        Text("Same as \(when) · \(Format.kcal(usual.latest.nutrients.kcal))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Log something else at \(time)")
            .accessibilityIdentifier("catchUp.time")
            Button {
                model.catchUp(usual)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel("Log \(name) at \(time), as \(when)")
            .accessibilityIdentifier("catchUp.log")
        }
    }
}
