import Foundation
import SystemCore
import Testing

@testable import FoodDatabase

/// The Foods table on iPad and the Mac: rows at the portion they'd log, the scopes, the filter and
/// the column sorts.
@Suite("Food listings")
struct ListingTests {
    static let oats = Food(
        id: "custom:oats", name: "Rolled oats", basis: .g, nutrients: Nutrients(kcal: 380, protein: 13, carbs: 67, fat: 7, fiber: 10),
        portions: [Portion(label: "1/2 cup (40 g)", amount: 40)], source: .custom, processing: .whole)
    static let yogurt = Food(
        id: "off:1", name: "Greek yogurt", brand: "Fage", basis: .g,
        nutrients: Nutrients(kcal: 97, protein: 9, carbs: 4, fat: 5, sugar: 4, sodium: 35),
        portions: [Portion(label: "1 container (170 g)", amount: 170)], source: .off, processing: .processed)
    static let creme = Food(
        id: "usda:2", name: "Crème fraîche", basis: .g, nutrients: Nutrients(kcal: 393, protein: 2, carbs: 3, fat: 40), source: .usda)
    static let bar = Food(
        id: "off:3", name: "Protein bar", brand: "Acme", basis: .g, nutrients: Nutrients(kcal: 400, protein: 33, carbs: 40, fat: 13, sodium: 300),
        portions: [Portion(label: "1 bar (60 g)", amount: 60)], source: .off, processing: .ultraProcessed)

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var personal: [PersonalFood] {
        [
            PersonalFood(food: Self.yogurt, score: 5, favorite: true, lastLogged: now.addingTimeInterval(-86400)),
            PersonalFood(food: Self.oats, score: 9, lastCount: 80, lastUnitID: "g", lastAmount: 80, lastLogged: now.addingTimeInterval(-3600)),
            PersonalFood(food: Self.bar, score: 2, favorite: true),
        ]
    }

    func names(_ listings: [FoodListing]) -> [String] { listings.map(\.food.name) }

    @Test("a row is the portion it would log: the person's last one, else the food's own")
    func portion() throws {
        let rows = FoodBrowser.listings(.all, query: "", personal: personal, custom: [Self.oats])
        let oats = try #require(rows.first { $0.food.id == Self.oats.id })
        #expect(oats.portion == "80 g")
        #expect(abs(oats.nutrients.kcal - 304) < 0.01)
        #expect(oats.personal && !oats.favorite && oats.lastLogged != nil)
        let yogurt = try #require(rows.first { $0.food.id == Self.yogurt.id })
        #expect(yogurt.portion == "1 container")
        #expect(abs(yogurt.nutrients.protein - 15.3) < 0.01)
        #expect(yogurt.favorite)
    }

    @Test("scopes: all by how much it's eaten, recent newest first, favourites and own foods by name")
    func scopes() {
        #expect(names(FoodBrowser.listings(.all, query: "", personal: personal, custom: [])) == ["Rolled oats", "Greek yogurt", "Protein bar"])
        // The bar is a favourite never logged: not recent.
        #expect(names(FoodBrowser.listings(.recent, query: "", personal: personal, custom: [])) == ["Rolled oats", "Greek yogurt"])
        #expect(names(FoodBrowser.listings(.favorites, query: "", personal: personal, custom: [])) == ["Greek yogurt", "Protein bar"])
        let mine = FoodBrowser.listings(.mine, query: "", personal: personal, custom: [Self.oats, Self.creme])
        #expect(names(mine) == ["Crème fraîche", "Rolled oats"])
        #expect(mine.allSatisfy { $0.personal }, "an own food is the person's even before it's logged")
        #expect(mine.map(\.rank) == [0, 1])
    }

    @Test("typing keeps a scope to foods with every word in the name or brand, ignoring case and accents")
    func filter() {
        #expect(names(FoodBrowser.listings(.favorites, query: "fage YOG", personal: personal, custom: [])) == ["Greek yogurt"])
        #expect(names(FoodBrowser.listings(.mine, query: "creme", personal: personal, custom: [Self.oats, Self.creme])) == ["Crème fraîche"])
        #expect(FoodBrowser.listings(.recent, query: "bar", personal: personal, custom: []).isEmpty)
        #expect(FoodBrowser.words("  Greek,  Yogurt ") == ["greek", "yogurt"])
    }

    @Test("search results keep the search's order and know the person's own foods")
    func search() {
        let matches = [
            FoodMatch(food: Self.creme, score: 3, personal: false), FoodMatch(food: Self.yogurt, score: 2, personal: true),
        ]
        let rows = FoodBrowser.listings(matches, personal: personal)
        #expect(names(rows) == ["Crème fraîche", "Greek yogurt"])
        #expect(rows.map(\.personal) == [false, true])
        #expect(rows[1].favorite)
    }

    @Test("a sorted column puts foods without the value last, whichever way it's sorted")
    func sorting() {
        let rows = FoodBrowser.listings(
            [Self.oats, Self.yogurt, Self.creme, Self.bar].map { FoodMatch(food: $0, score: 1, personal: false) }, personal: [])
        func sorted(_ column: FoodListingOrder.Column, _ order: SortOrder) -> [String] {
            names(rows.sorted(using: FoodListingOrder(column, order: order)))
        }
        #expect(sorted(.sodium, .forward) == ["Greek yogurt", "Protein bar", "Rolled oats", "Crème fraîche"])
        #expect(sorted(.sodium, .reverse) == ["Protein bar", "Greek yogurt", "Rolled oats", "Crème fraîche"])
        #expect(sorted(.processing, .reverse) == ["Protein bar", "Greek yogurt", "Rolled oats", "Crème fraîche"])
        // Per portion, not per 100 g: the yogurt's container has more protein than the oats' half cup.
        #expect(sorted(.protein, .reverse) == ["Protein bar", "Greek yogurt", "Rolled oats", "Crème fraîche"])
        #expect(sorted(.name, .forward) == ["Crème fraîche", "Greek yogurt", "Protein bar", "Rolled oats"])
        #expect(sorted(.relevance, .forward) == ["Rolled oats", "Greek yogurt", "Crème fraîche", "Protein bar"])
        // Equal values keep the search's order.
        #expect(sorted(.fiber, .reverse) == ["Rolled oats", "Greek yogurt", "Crème fraîche", "Protein bar"])
    }
}
