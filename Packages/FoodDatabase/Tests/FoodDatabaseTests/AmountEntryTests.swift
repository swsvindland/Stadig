import Foundation
import Testing

@testable import FoodDatabase

struct AmountEntryTests {
    let grams = PortionUnit(id: "g", label: "g", kind: .mass, amount: 1)
    let ounces = PortionUnit(id: "oz", label: "oz", kind: .mass, amount: 28.35)
    let cups = PortionUnit(id: "cup", label: "cup", kind: .volume, amount: 240)

    @Test func theFirstKeyReplaces() {
        var amount = AmountEntry(count: 150, unit: grams)
        #expect(amount.isSelected)
        amount.press(.digit(2))
        #expect(amount.text == "2")
        #expect(!amount.isSelected)
        amount.press(.digit(0))
        #expect(amount.count == 20)
    }

    @Test func deleteClearsWhatWasOffered() {
        var amount = AmountEntry(count: 150, unit: grams)
        amount.press(.delete)
        #expect(amount.text.isEmpty)
        #expect(amount.count == nil)
        #expect(amount.display() == "0")
    }

    @Test func deleteTakesOneAtATimeAfterThat() {
        var amount = AmountEntry(count: 150, unit: grams)
        for digit in [1, 2, 3] { amount.press(.digit(digit)) }
        amount.press(.delete)
        #expect(amount.text == "12")
    }

    @Test func aDecimalAndItsLimit() {
        var amount = AmountEntry(count: 150, unit: grams)
        amount.press(.point)
        #expect(amount.text == "0.")
        amount.press(.digit(5))
        #expect(amount.count == 0.5)
        amount.press(.digit(2))
        amount.press(.digit(9))
        amount.press(.point)
        #expect(amount.text == "0.52")
    }

    @Test func aPointAloneStillCounts() {
        var amount = AmountEntry(count: 150, unit: grams)
        amount.press(.digit(2))
        amount.press(.point)
        #expect(amount.count == 2)
    }

    @Test func wholeNumbersStopAtSixDigits() {
        var amount = AmountEntry(count: 1, unit: grams)
        for _ in 0..<9 { amount.press(.digit(9)) }
        #expect(amount.text == "999999")
    }

    @Test func zeroIsNotAnAmount() {
        var amount = AmountEntry(count: 1, unit: grams)
        amount.press(.digit(0))
        #expect(amount.count == nil)
        amount.press(.digit(7))
        #expect(amount.text == "7")
    }

    @Test func aFractionAfterAWholeNumber() {
        var amount = AmountEntry(count: 1, unit: cups)
        amount.press(.digit(1))
        amount.press(.fraction("½"))
        #expect(amount.text == "1½")
        #expect(amount.count == 1.5)
    }

    @Test func aFractionAlone() {
        var amount = AmountEntry(count: 2, unit: cups)
        amount.press(.fraction("¾"))
        #expect(amount.count == 0.75)
    }

    @Test func aSecondFractionTakesThePlaceOfTheFirst() {
        var amount = AmountEntry(count: 1, unit: cups)
        amount.press(.digit(2))
        amount.press(.fraction("½"))
        amount.press(.fraction("¼"))
        #expect(amount.count == 2.25)
    }

    @Test func nothingFollowsAFraction() {
        var amount = AmountEntry(count: 1, unit: cups)
        amount.press(.fraction("½"))
        amount.press(.digit(3))
        amount.press(.point)
        #expect(amount.text == "½")
    }

    @Test func aFractionDoesntJoinADecimal() {
        var amount = AmountEntry(count: 1, unit: cups)
        amount.press(.digit(1))
        amount.press(.point)
        amount.press(.fraction("½"))
        #expect(amount.text == "1.")
    }

    @Test func aChangeOfUnitConvertsWhatWasOffered() {
        var amount = AmountEntry(count: 1, unit: cups)
        amount.change(to: grams)
        #expect(amount.count == 240)
        #expect(amount.unit == grams)
        #expect(amount.base == 240)
        #expect(amount.isSelected)
    }

    @Test func aChangeOfUnitKeepsWhatWasTyped() {
        var amount = AmountEntry(count: 100, unit: grams)
        amount.press(.digit(5))
        amount.change(to: ounces)
        #expect(amount.count == 5)
        #expect(amount.unit == ounces)
        #expect(amount.base == 5)
    }

    @Test func aChoiceReplacesAndCanBeReplaced() {
        var amount = AmountEntry(count: 100, unit: grams)
        amount.press(.digit(5))
        amount.choose(200)
        #expect(amount.count == 200)
        #expect(amount.isSelected)
        amount.press(.digit(3))
        #expect(amount.count == 3)
    }

    @Test func nudgingStaysAboveNothing() {
        var amount = AmountEntry(count: 10, unit: grams)
        amount.nudge(up: true)
        #expect(amount.count == 20)
        amount.nudge(up: false)
        amount.nudge(up: false)
        #expect(amount.count == 10)
    }

    @Test func aMacsFieldKeepsWhatsTyped() {
        var amount = AmountEntry(count: 150, unit: grams)
        amount.type("2,5")
        #expect(amount.count == 2.5)
        #expect(amount.isTyped)
    }

    @Test func withoutAUnitItsAMultiplier() {
        var amount = AmountEntry(count: 1, unit: nil)
        #expect(amount.text == "1")
        amount.press(.digit(2))
        #expect(amount.count == 2)
        amount.choose(1.5)
        #expect(amount.text == "1.5")
    }

    @Test func itReadsInTheLocale() {
        var amount = AmountEntry(count: 1, unit: grams)
        amount.press(.digit(1))
        amount.press(.point)
        amount.press(.digit(5))
        #expect(amount.display(locale: Locale(identifier: "de_DE")) == "1,5")
    }
}
