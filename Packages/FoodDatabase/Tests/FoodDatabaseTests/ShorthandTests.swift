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

    @Test func whatOnlySaysAFoodWasEatenIsLeftOut() {
        let read = Shorthand.spelledOut
        // That it was eaten, and when, before the food or after it.
        #expect(read("i had 2 eggs and toast") == "2 eggs and toast" && read("just ate a banana") == "a banana")
        #expect(read("for breakfast oatmeal with banana") == "oatmeal with banana" && read("breakfast: eggs") == "eggs")
        #expect(read("eggs for breakfast") == "eggs" && read("coffee this morning") == "coffee" && read("wine with dinner") == "wine")
        #expect(read("protein shake after workout") == "protein shake" && read("i had eggs for breakfast today") == "eggs")
        #expect(read("plus a coffee") == "a coffee" && read("coffee at home") == "coffee")
        // How much, said too loosely to be an amount.
        #expect(read("a lot of rice") == "rice" && read("some more rice") == "rice" && read("a little butter") == "butter")
        #expect(read("a bit of cheese") == "cheese" && read("more chicken") == "chicken" && read("another slice of pizza") == "slice of pizza")
        #expect(read("two more cookies") == "two cookies" && read("one more slice of pizza") == "one slice of pizza")
        // "My" and "extra" before an everyday food, and not where they start a name or say its kind.
        #expect(read("my coffee") == "coffee" && read("i had my coffee") == "coffee" && read("extra rice") == "rice")
        #expect(read("my protein bar") == "my protein bar" && read("extra virgin olive oil") == "extra virgin olive oil")
        #expect(read("extra lean ground beef") == "extra lean ground beef" && read("extra gum") == "extra gum")
        // Not the brands that start so, whole or on their way.
        #expect(read("a little debbie") == "a little debbie" && read("little bites") == "little bites" && read("big mac") == "big mac")
        #expect(read("a little deb") == "a little deb" && read("a little bu") == "bu")
        // A size said of what the food is in, as the amounts know it.
        #expect(read("big glass of milk") == "large glass of milk" && read("tiny piece of cake") == "small piece of cake")
        // A chain said after "from" or "at" comes first, as its foods are found; nothing else does.
        #expect(read("fries from mcdonalds") == "mcdonalds fries" && read("large fries from mcdonalds") == "mcdonalds large fries")
        #expect(read("burger at five guys") == "five guys burger" && read("sandwich from the cheesecake factory") == "cheesecake factory sandwich")
        #expect(read("lunch at subway") == "subway" && read("something from wendys") == "wendys")
        // A chain named by a food's word, with what's ordered there: no chipotle dip.
        #expect(read("lunch at chipotle") == "chipotle burrito bowl")
        #expect(read("orange juice from concentrate") == "orange juice from concentrate" && read("pizza from restaurant") == "pizza from restaurant")
        // Something is always left, and a food's own "breakfast" stays.
        #expect(read("had") == "had" && read("i had") == "i had" && read("more") == "more" && read("breakfast burrito") == "breakfast burrito")
        #expect(read("i had ") == "i had " && read("had d") == "d" && read("after dinner mints") == "after dinner mints")
        #expect(read("pre workout") == "pre workout" && read("for breakfast") == "for breakfast" && read("ihop at home") == "ihop at home")
    }

    @Test func whatsSaidAfterAFoodIsLeftOutWhileItsTyped() {
        let read = Shorthand.spelledOut
        // On its way to "for breakfast", "this morning" or a chain: still the food, where each
        // letter was searched as another word of it.
        for typed in [
            "eggs for b", "eggs for br", "eggs for breakfas", "eggs this", "eggs this m", "eggs last ni", "eggs for a", "eggs for a s", "eggs at",
        ] {
            #expect(read(typed) == "eggs", "\(typed)")
        }
        #expect(read("fries from mc") == "fries" && read("fries from mcd") == "fries" && read("coffee at h") == "coffee")
        // Not what joins a food to the next, nor a word that could be the food's own.
        #expect(read("eggs on t") == "eggs on t" && read("salad with d") == "salad with d" && read("eggs fo") == "eggs fo")
        #expect(read("juice from conce") == "juice from conce")
    }

    @Test func aSearchReadsIt() {
        let catalog = Catalogs.usda
        #expect(catalog.top("🍕", 1).first?.hasPrefix("Pizza") == true && catalog.top("🍌", 1) == ["Bananas, raw"])
        #expect(catalog.top("coke can", 1).first?.hasPrefix("Beverages, carbonated, cola") == true)
        #expect(catalog.top("fries large", 1).first?.hasPrefix("Potato, french fries") == true)
        #expect(
            catalog.top("egg x2", 1).first?.hasPrefix("Egg, whole") == true && catalog.top("1 c. milk", 1).first?.hasPrefix("Milk, whole") == true)
        #expect(catalog.top("tbsp peanut butter", 1).first?.hasPrefix("Peanut butter") == true)
        // Said as it would be told: the eggs and the toast, the fries from McDonald's.
        #expect(catalog.top("i had 2 eggs and toast", 2) == catalog.top("2 eggs and toast", 2))
        #expect(catalog.top("eggs for breakfast", 1) == catalog.top("eggs", 1) && catalog.top("a lot of rice", 1) == catalog.top("rice", 1))
        #expect(catalog.top("fries from mcdonalds", 1) == ["McDONALD'S, french fries"])
        #expect(
            catalog.top("my coffee", 1) == catalog.top("coffee", 1) && catalog.top("one more slice of pizza", 1) == catalog.top("slice of pizza", 1))
        // With "w/" a food and what it comes with are found as they are with "with".
        #expect(catalog.top("coffee w/ cream", 2) == catalog.top("coffee with cream", 2))
        // A model's name is read the same way.
        #expect(
            catalog.candidates(name: "Coffee w/ cream", brand: nil).first?.food.name
                == catalog.candidates(name: "Coffee with cream", brand: nil).first?.food.name)
        #expect(FoodCatalog.food(in: "Chicken w/ rice") == FoodCatalog.food(in: "Chicken with rice"))
    }
}
