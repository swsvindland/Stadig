import FoodDatabase
import Testing

@testable import MacroTrack

/// Return in the Foods search logs what was typed, not what the last query's rows had selected.
struct FoodSearchReturnTests {
    let mine = FoodSearchReturn.Query(text: "", scope: .all)
    let banana = FoodSearchReturn.Query(text: "banana", scope: .all)

    @Test("Return straight after typing waits for the new rows and logs the best of them")
    func returnBeforeTheRowsArrive() {
        var search = FoodSearchReturn()
        // The person's own foods, the first selected, as the Mac shows them on arrival.
        #expect(search.arrived(mine, rows: ["oats", "eggs"], selection: nil) == .init(selection: "oats", log: false))

        // "banana" typed and Return pressed at once: the table still shows oats, selected.
        search.typed(banana)
        #expect(search.pressed(banana, hasSelection: true) == .wait)
        let next = search.arrived(banana, rows: ["banana", "banana-bread"], selection: "oats")
        #expect(next == .init(selection: "banana", log: true))

        // Its rows are the ones shown now, so the next Return logs at once.
        #expect(search.pressed(banana, hasSelection: true) == .log)
        #expect(search.waiting == nil)
    }

    @Test("a held Return finds nothing to log when nothing matches")
    func nothingMatches() {
        var search = FoodSearchReturn()
        _ = search.arrived(mine, rows: ["oats"], selection: nil)
        #expect(search.pressed(banana, hasSelection: true) == .wait)
        #expect(search.arrived(banana, rows: [], selection: "oats") == .init(selection: nil, log: false))
    }

    @Test("a Return held for a query typed past is dropped")
    func typingOnDropsTheReturn() {
        var search = FoodSearchReturn()
        let ban = FoodSearchReturn.Query(text: "ban", scope: .all)
        _ = search.arrived(mine, rows: ["oats"], selection: nil)
        #expect(search.pressed(ban, hasSelection: true) == .wait)
        search.typed(banana)
        #expect(search.waiting == nil)
        #expect(search.arrived(banana, rows: ["banana"], selection: "oats") == .init(selection: "banana", log: false))

        // Rows for a query on its way out don't spend a Return held for the newer one.
        let bananas = FoodSearchReturn.Query(text: "bananas", scope: .all)
        search.typed(bananas)
        #expect(search.pressed(bananas, hasSelection: true) == .wait)
        #expect(search.arrived(banana, rows: ["banana"], selection: "banana").log == false)
        #expect(search.arrived(bananas, rows: ["bananas-dried"], selection: "banana") == .init(selection: "bananas-dried", log: true))
    }

    @Test("a refined query selects its best match; the same query searched again keeps the selection")
    func selectionFollowsTheQuery() {
        var search = FoodSearchReturn()
        let ban = FoodSearchReturn.Query(text: "ban", scope: .all)
        #expect(search.arrived(ban, rows: ["banana-bread", "banana"], selection: nil) == .init(selection: "banana-bread", log: false))
        // A selection still listed doesn't survive the refined query.
        #expect(search.arrived(banana, rows: ["banana", "banana-bread"], selection: "banana-bread") == .init(selection: "banana", log: false))
        // Logging moves the person's foods and the same query runs again: the row picked stays.
        #expect(search.arrived(banana, rows: ["banana", "banana-bread"], selection: "banana-bread") == .init(selection: "banana-bread", log: false))
        #expect(search.arrived(banana, rows: ["banana"], selection: "banana-bread") == .init(selection: "banana", log: false))
        // Another scope is another query.
        let favorites = FoodSearchReturn.Query(text: "banana", scope: .favorites)
        #expect(search.pressed(favorites, hasSelection: true) == .wait)
        #expect(search.pressed(banana, hasSelection: false) == .select)
    }
}
