import Testing

@testable import FoodDatabase

@Suite("Shorthand")
struct ShorthandTests {
    @Test func whatIsTypedInPlaceOfWordsIsReadAsTheWords() {
        let read = Shorthand.spelledOut
        // An emoji is its food, once where it follows its own word, with or without the
        // selector some keyboards add.
        #expect(read("🍌") == "banana" && read("2 🥚") == "2 egg" && read("banana 🍌") == "banana")
        #expect(read("🍔 and 🍟") == "hamburger and french fries" && read("🌶\u{FE0F}") == "chili pepper")
        // "w/" and "w/o", and a "w" between two foods; not the W of A & W.
        #expect(read("chicken w/ rice") == "chicken with rice" && read("chicken w rice") == "chicken with rice")
        #expect(read("coffee w/cream") == "coffee with cream" && read("burger w/o bun") == "burger without bun")
        #expect(read("a & w root beer") == "a & w root beer")
        // A cup written "c" after its number, which vitamin C isn't.
        #expect(read("1 c milk") == "1 cup milk" && read("1 c. milk") == "1 cup milk" && read("1c milk") == "1 cup milk")
        #expect(read("vitamin c") == "vitamin c")
        // A count, a size or a measure said after the food, once it's typed whole.
        #expect(read("egg x2") == "2 egg" && read("fries large") == "large fries" && read("fries large ") == "large fries ")
        #expect(read("coke can") == "can of coke" && read("almonds handful") == "1 handful of almonds")
        #expect(read("fries l") == "fries l" && read("coke c") == "coke c")
        // A cup, a bowl and a bar named last are part of the food.
        #expect(read("fruit cup") == "fruit cup" && read("rice bowl") == "rice bowl" && read("protein bar") == "protein bar")
        // A measure first with no number is one of it.
        #expect(read("tbsp peanut butter") == "1 tbsp peanut butter" && read("handful almonds") == "1 handful almonds")
        // A little of a food is the food; a bite alone is one, and "taste of" starts a brand.
        #expect(read("bite of cake") == "cake" && read("a sip of wine") == "wine")
        #expect(read("egg bites") == "egg bites" && read("taste of india") == "taste of india")
        // One word, and words as they are, are left alone.
        #expect(read("chicken") == "chicken" && read("mahi mahi") == "mahi mahi" && read("Chicken Breast") == "Chicken Breast")
    }

    @Test func aSearchReadsIt() {
        let catalog = Catalogs.usda
        #expect(catalog.top("🍕", 1).first?.hasPrefix("Pizza") == true && catalog.top("🍌", 1) == ["Bananas, raw"])
        #expect(catalog.top("coke can", 1).first?.hasPrefix("Beverages, carbonated, cola") == true)
        #expect(catalog.top("fries large", 1).first?.hasPrefix("Potato, french fries") == true)
        #expect(
            catalog.top("egg x2", 1).first?.hasPrefix("Egg, whole") == true && catalog.top("1 c. milk", 1).first?.hasPrefix("Milk, whole") == true)
        #expect(catalog.top("tbsp peanut butter", 1).first?.hasPrefix("Peanut butter") == true)
        // With "w/" a food and what it comes with are found as they are with "with".
        #expect(catalog.top("coffee w/ cream", 2) == catalog.top("coffee with cream", 2))
        // A model's name is read the same way.
        #expect(
            catalog.candidates(name: "Coffee w/ cream", brand: nil).first?.food.name
                == catalog.candidates(name: "Coffee with cream", brand: nil).first?.food.name)
        #expect(FoodCatalog.food(in: "Chicken w/ rice") == FoodCatalog.food(in: "Chicken with rice"))
    }
}
