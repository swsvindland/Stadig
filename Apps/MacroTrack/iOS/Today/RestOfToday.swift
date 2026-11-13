import NutritionEngine
import SwiftUI
import SystemCore

/// Today's second column where there's room (iPad, the Mac, Vision Pro): everything a phone folds
/// under More today, open beside the thread. The targets' note, the plan's asks and the check-in,
/// the weigh-in, the meal plan's meals, Same as yesterday and saved meals, whether the day's logging
/// is done, then meal timing, supplements, drinks and the week's food, as cards on the ground.
struct RestOfToday: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Group {
                if let analysis = model.analysis, !analysis.targets.note.isEmpty {
                    Section {
                        ModeLine(targets: analysis.targets, assessment: analysis.assessment)
                    } header: {
                        Text("More today").eyebrow().padding(.horizontal, -6)
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
        .insetGroupedList()
        .sectionSpacing(14)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("today.rest")
    }
}
