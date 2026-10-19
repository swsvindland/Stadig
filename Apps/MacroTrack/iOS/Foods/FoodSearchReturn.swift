import FoodDatabase
import Foundation

/// Return in the Foods search while the rows catch up with the typing. A query's rows arrive after
/// a short pause and a search off the main thread, and until then the table still shows the last
/// query's, with its selection: typing "banana" and pressing Return at once would log that. So the
/// rows on screen are known by the query they were found for, and a Return pressed before the
/// current query's rows are there waits for them and logs the best of them.
struct FoodSearchReturn: Equatable {
    /// What was searched: the words typed (trimmed) and the scope.
    struct Query: Hashable {
        var text: String
        var scope: FoodScope
    }

    enum Action: Equatable {
        /// The rows are the query's: log the selected food.
        case log
        /// The rows are the query's but nothing is selected: select the first, to log next.
        case select
        /// The query's rows aren't there yet: Return logs the best of them when they come.
        case wait
    }

    /// The query the rows shown were found for; nil before the first rows.
    private(set) var shownFor: Query?
    /// A Return waiting for this query's rows.
    private(set) var waiting: Query?

    /// Return pressed with `query` typed.
    mutating func pressed(_ query: Query, hasSelection: Bool) -> Action {
        guard query == shownFor else {
            waiting = query
            return .wait
        }
        return hasSelection ? .log : .select
    }

    /// The query changed. A Return held for another query is dropped: it was pressed before the
    /// person typed on, so it wasn't for what they're typing now.
    mutating func typed(_ query: Query) {
        if waiting != query { waiting = nil }
    }

    /// The rows for `query` arrived, in the table's order: which to select, and whether a held
    /// Return logs it. A new query selects its first row, so a selection made for the last query
    /// doesn't stay on a refined one ("ban" picked banana bread; "banana" picks banana); the same
    /// query searched again (something was logged, so the person's foods moved) keeps the one
    /// selected while it's still listed.
    mutating func arrived(_ query: Query, rows ids: [FoodListing.ID], selection: FoodListing.ID?) -> Arrival {
        let again = query == shownFor
        shownFor = query
        let held = waiting == query
        if held { waiting = nil }
        if again && !held, let selection, ids.contains(selection) { return Arrival(selection: selection, log: false) }
        return Arrival(selection: ids.first, log: held && !ids.isEmpty)
    }

    /// The row to select as new rows arrive, and whether to log it.
    struct Arrival: Equatable {
        var selection: FoodListing.ID?
        var log: Bool
    }
}
