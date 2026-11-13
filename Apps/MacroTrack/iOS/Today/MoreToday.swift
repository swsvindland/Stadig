import NutritionEngine
import SwiftUI
import SystemCore

/// Everything on a phone's Today that isn't the day's food: the targets' note, the plan's asks and
/// the check-in, the weigh-in, the meal plan's meals, Same as yesterday and saved meals, whether the
/// day's logging is done, then meal timing, supplements, drinks and the week's food. Folded under one
/// quiet line after the thread, in the thread's own voice (an eyebrow, and what's waiting on the
/// right), so Today reads as its design does: what's left, the day's food, the usual foods, the
/// field. A tap opens it in place, where everything in it works as it always has.
struct MoreToday: View {
    @Environment(AppModel.self) private var model
    let open: Bool
    let toggle: () -> Void

    /// Where Today scrolls to when it opens.
    static let id = "today.more"

    var body: some View {
        let summary = Self.summary(model)
        Section {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("More today").eyebrow()
                    Spacer(minLength: 8)
                    Text(summary).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Ink.text3)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // In line with the meals' times. Closed, it's the thread's end, kept in sight over the
            // foot: the room under it is what the foot's fade covers.
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: open ? 0 : 26, trailing: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("More today")
            .accessibilityValue(summary)
            .accessibilityHint(
                open ? "Folds the weigh-in, the plan, supplements and the rest away" : "Shows the weigh-in, the plan, supplements and the rest"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("today.more")
            .id(Self.id)
        }
        if open {
            Group {
                if let analysis = model.analysis, !analysis.targets.note.isEmpty {
                    Section {
                        ModeLine(targets: analysis.targets, assessment: analysis.assessment)
                    }
                }
                ActionsSection()
                WeightSection(day: model.today)
                PlannedMealsSection(day: model.today)
                if model.usualNow != nil || !model.usualMeals.isEmpty { LogAgainSection(foods: false) }
                DayStateSection(day: model.today)
                TodayMore(day: model.today)
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    /// What's waiting, in a few words: the plan's ask ("Your plan is ready"), the weigh-in (or the
    /// day's weight once it's in), the supplements still to take, a fast running and the meal plan's
    /// meals. Three at most; with none of them, the day's state. Protein to go isn't said: the
    /// numbers over the thread say it.
    static func summary(_ model: AppModel) -> String {
        var parts: [String] = []
        let analysis = model.analysis
        let asks: Set<MacroAction.Kind> = [.planReady, .reviewPlan, .logYesterday]
        if let analysis, let action = ActionsSection.actions(analysis).first(where: { asks.contains($0.kind) }) { parts.append(action.title) }
        if let reading = model.latestWeighIn, reading.day == model.today {
            parts.append(Format.weight(reading.kg, unit: model.units.weight))
        } else if !(analysis.map { $0.targets.mode == .vacation || $0.targets.mode == .illness } ?? false) {
            parts.append("Weigh in")
        }
        let open = model.doses(on: model.today).filter(\.open).count
        if open > 0 { parts.append(open == 1 ? "1 supplement" : "\(open) supplements") }
        if analysis?.fast != nil { parts.append("Fasting") }
        if model.mealPlan(covering: model.today) != nil { parts.append("Meal plan") }
        return parts.isEmpty ? "Done logging?" : parts.prefix(3).joined(separator: " · ")
    }
}
