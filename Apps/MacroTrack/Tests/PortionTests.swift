import FoodDatabase
import Foundation
import Testing

@testable import MacroTrack

/// The amount screen's quick choices: half, one, one and a half and two of the usual amount, read
/// in the unit chosen.
@MainActor
struct PortionChoiceTests {
    @Test func poundsComeInTenths() throws {
        let banana = try #require(Catalogs.food.food(id: Foods.bananaID))
        let pound = try #require(FoodUnits.units(for: banana).first { $0.id == "lb" })
        let choices = PortionView.quickChoices(base: 1, unit: pound)
        #expect(choices == [0.5, 1, 1.5, 2], "not 1, 1, 2, 2: half a pound is a portion")
        #expect(choices.map { PortionView.quickChoiceLabel($0, unit: pound) } == ["0.5 lb", "1 lb", "1.5 lb", "2 lb"])

        // 200 g, picked in grams and switched to pounds, is 0.4 lb.
        let grams = try #require(FoodUnits.units(for: banana).first { $0.id == "g" })
        let base = FoodUnits.convert(200, from: grams, to: pound)
        #expect(base == 0.4)
        #expect(
            PortionView.quickChoices(base: base, unit: pound).map { PortionView.quickChoiceLabel($0, unit: pound) } == [
                "0.2 lb", "0.4 lb", "0.6 lb", "0.8 lb",
            ])
    }

    @Test func portionsComeInQuartersAndGramsWhole() throws {
        let banana = try #require(Catalogs.food.food(id: Foods.bananaID))
        let units = FoodUnits.units(for: banana)
        let grams = try #require(units.first { $0.id == "g" })
        #expect(PortionView.quickChoices(base: 118, unit: grams) == [59, 118, 177, 236])
        #expect(PortionView.quickChoiceLabel(59, unit: grams) == "59 g")
        let portion = try #require(units.first { $0.kind == .portion })
        #expect(PortionView.quickChoices(base: 1, unit: portion) == [0.5, 1, 1.5, 2])
        #expect(PortionView.quickChoiceLabel(1.5, unit: portion) == Format.number(1.5, digits: 2), "a count, without its unit")
    }
}
