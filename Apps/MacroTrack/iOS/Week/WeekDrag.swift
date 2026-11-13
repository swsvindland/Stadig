import NutritionEngine
import SwiftUI
import SystemCore
import UniformTypeIdentifiers

/// A meal being dragged across the week desk, and the day it's over: what the desk previews.
@Observable
final class WeekDrag {
    /// Set when a drag starts. A drag that's cancelled (Esc, or let go off the desk) leaves it set
    /// with no day under it, which previews nothing; the next drag replaces it.
    var meal: WeekMeal?
    /// The day the meal is over, other than its own.
    var over: Day?

    /// The meal over another day than its own: what's previewed.
    var held: (meal: WeekMeal, day: Day)? {
        guard let meal, let over, over != meal.day else { return nil }
        return (meal, over)
    }

    func start(_ meal: WeekMeal) {
        self.meal = meal
        over = nil
    }

    func end() {
        meal = nil
        over = nil
    }
}

/// A day's column as a place to drop a meal. What's dragged is the meal's id as text, which a drop
/// checks against the meal the desk is holding: text dragged in from another app, onto a desk that
/// still holds a meal from a drag that was cancelled, moves nothing.
struct WeekDropTarget: DropDelegate {
    let day: Day
    let drag: WeekDrag
    let drop: @MainActor (WeekMeal, Day) -> Void

    func validateDrop(info: DropInfo) -> Bool { drag.meal != nil && info.hasItemsConforming(to: [.text]) }

    func dropEntered(info: DropInfo) { if drag.over != day { drag.over = day } }

    /// Again as it moves: leaving one column can be heard after entering the next.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if drag.over != day { drag.over = day }
        return DropProposal(operation: drag.meal?.day == day ? .cancel : .move)
    }

    func dropExited(info: DropInfo) { if drag.over == day { drag.over = nil } }

    func performDrop(info: DropInfo) -> Bool {
        guard let meal = drag.meal, meal.day != day, let provider = info.itemProviders(for: [.text]).first else {
            drag.end()
            return false
        }
        drag.end()
        let id = meal.id
        let day = day
        let drop = drop
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let dragged = (object as? NSString).map(String.init)
            Task { @MainActor in if dragged == id { drop(meal, day) } }
        }
        return true
    }
}
