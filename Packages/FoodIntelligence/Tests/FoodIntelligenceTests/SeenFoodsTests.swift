import Testing

@testable import FoodIntelligence

@Suite("Words")
struct WordTests {
    @Test func stemsMatchSingularsAndPlurals() {
        #expect(FoodText.stem("tomatoes") == "tomato")
        #expect(FoodText.stem("berries") == "berr")
        #expect(FoodText.stem("strawberry") == "strawberr")
        #expect(FoodText.stem("hummus") == "hummus")
        #expect(FoodText.stem("cookies") == "cookie")
        #expect(FoodText.stem("wendys") == "wend")
        #expect(FoodText.stem("egg") == "egg")
        #expect(FoodText.words("Crème brûlée & the fries") == ["creme", "brulee", "fries"])
        #expect(FoodText.nameWords("tomato slice") == ["tomato"])
        #expect(FoodText.nameWords("Mini Wheats") == ["mini", "wheats"])
    }

    @Test func unitsAreNormalised() {
        for (unit, key) in [
            ("lbs", "lb"), ("kgs", "kg"), ("fluid ounces", "floz"), ("fl. oz.", "floz"), ("Fluid Ounce", "floz"),
            ("tbs", "tbsp"), ("tablespoons", "tbsp"), ("slices", "slice"), ("each", "piece"), ("bowl", "serving"), ("", "piece"),
        ] {
            #expect(Measures.unitKey(unit) == key, "\(unit)")
        }
        #expect(Measures.parseAmount("1 1/2") == 1.5)
        #expect(Measures.parseAmount("1½") == 1.5)
        #expect(Measures.parseAmount(".5") == 0.5)
        #expect(Measures.parseAmount("x") == nil)
    }
}

@Suite("Seen foods")
struct SeenFoodsTests {
    @Test func repliesAreValidatedCleanedAndDeduplicated() {
        let foods = SeenFoods.read(
            reply([
                item("  Pepperoni   pizza ", 3, "1 slice", 330, brand: "none"),
                item("", 1, "cup", 5),
                item("Salmon nigiri", 99, "", -4),
                item("salmon nigiri", 2, "piece", 60),
            ]))
        #expect(
            foods == [
                SeenFood(name: "Pepperoni pizza", brand: "", quantity: 3, unit: "slice", grams: 330),
                SeenFood(name: "Salmon nigiri", brand: "", quantity: 1, unit: "serving", grams: nil),
            ])
        let many = SeenFoods.read(reply((0..<20).map { item("Food \($0)", 1, "g") }))
        #expect(many.count == 12)
        // Weights above the count limit are ordinary; counts above it are a generation loop.
        let amounts = SeenFoods.read(reply([item("Rice", 200, "g", 200), item("Nigiri", 200, "piece", 300)]))
        #expect(amounts.map(\.quantity) == [200, 1])
    }

    @Test func aPhotoWithoutFoodYieldsNothingUnlessTheNoteNamesFood() {
        let burger = item("Cheeseburger", 1, "burger", 220)
        let person = reply([burger], scene: "a person smiling", food: false)
        #expect(SeenFoods.read(person).isEmpty)
        #expect(SeenFoods.read(person, description: "   ", photo: true).isEmpty)
        #expect(SeenFoods.read(person, description: "a cheeseburger", photo: true).map(\.name) == ["Cheeseburger"])
        #expect(SeenFoods.read(reply([burger], scene: "a burger", food: true)).count == 1)
        // Description replies have no verdict at all.
        #expect(SeenFoods.read(reply([burger])).count == 1)
    }

    @Test func aChainsPizzaKeepsItsToppingsWhileSidesAndDrinksStay() {
        let foods = SeenFoods.read(
            reply([
                item("Pepperoni pizza", 3, "slice", 330, brand: "Domino's"),
                item("Ham", 1, "piece", 30),
                item("Sliced mushrooms", 1, "piece", 30),
                item("White rice", 1, "cup", 160),
                item("Cola", 1, "cup", 250),
                item("Garlic bread", 2, "piece", 60),
            ]))
        // A cup of rice weighs more than a topping, so it is a side.
        #expect(foods.map(\.name) == ["Pepperoni pizza", "White rice", "Cola", "Garlic bread"])
        // Without a brand, a burger is split into its components as seen.
        let burger = SeenFoods.read(reply(["Hamburger bun", "Beef patty", "Cheddar cheese", "Lettuce"].map { item($0) }))
        #expect(burger.count == 4)
    }

    @Test func aChainInTheNameOrOnlyInTheDescriptionKeepsTheDishWhole() {
        // The reply Apple's model gave for a Domino's box photo and "large pepperoni from dominos, ate 3 slices".
        let toppings = ["ham slice", "beef patty", "cheese slice", "pepperoni slice", "sausage slice", "onion slice", "green pepper slice"]
        let boxed = reply([item("dominos pepperoni pizza", 3, "slice", 330)] + toppings.map { item($0, 1, "piece", 20) })
        #expect(
            SeenFoods.read(boxed, description: "large pepperoni from dominos, ate 3 slices", photo: true)
                == [SeenFood(name: "pepperoni pizza", brand: "Domino's", quantity: 3, unit: "slice", grams: 330)])
        let unnamed = reply([item("Pepperoni pizza", 2, "slice", 220), item("Ham", 1, "piece", 30), item("Garlic knots", 2, "piece", 60)])
        #expect(
            SeenFoods.read(unnamed, description: "Domino’s, 2 slices", photo: true).map { [$0.brand, $0.name] }
                == [["Domino's", "Pepperoni pizza"], ["", "Garlic knots"]])
        #expect(SeenFoods.read(unnamed).count == 3, "without a chain, every food stays")
        let other = SeenFoods.read(
            reply([
                item("Starbucks grande latte", 1, "cup", 470),
                item("Chipotle mayo", 1, "tbsp", 15),
                item("Big Mac", 1, "sandwich", 215, brand: "mcdonalds"),
            ]))
        #expect(other.map { [$0.brand, $0.name] } == [["Starbucks", "grande latte"], ["", "Chipotle mayo"], ["McDonald's", "Big Mac"]])
    }

    @Test func aChainItemSplitIntoPartsIsLoggedWhole() {
        let parts = ["Hamburger bun", "Beef patties", "Cheese slice", "Shredded lettuce", "Pickles", "Special sauce", "Onions"]
        let split = reply(parts.map { item($0, 2, "piece", 40, brand: "McDonald's") } + [item("Cola", 1, "cup", 350)])
        #expect(
            SeenFoods.read(split, description: "big mac from mcdonalds", photo: true).map { [$0.brand, $0.name] }
                == [["McDonald's", "big mac"], ["", "Cola"]])
        // Without a dish in the description the parts are all we know, so they stay.
        #expect(SeenFoods.read(split).count == 8)
    }

    @Test func collapsingAbsorbsTheMuffinEggAndCheeseButNotAListedDish() {
        let mcmuffin = [
            item("English muffin", 1, "piece", 55), item("Sausage patty", 1, "patty", 45), item("Egg", 1, "piece", 50),
            item("American cheese", 1, "slice", 20),
        ]
        func read(_ description: String, _ items: [MealReply.Item]) -> [[String]] {
            SeenFoods.read(reply(items), description: description, photo: true).map { [$0.brand, $0.name] }
        }
        #expect(
            read("mcdonalds sausage mcmuffin with egg", mcmuffin + [item("Hash brown", 1, "piece", 55)])
                == [["McDonald's", "sausage mcmuffin with egg"], ["", "Hash brown"]])
        // "From mcdonalds" covers the whole order; the dish is still the first thing named.
        #expect(
            read("sausage mcmuffin with egg and a hash brown from mcdonalds", mcmuffin + [item("Hash brown", 1, "piece", 55)])
                == [["McDonald's", "sausage mcmuffin with egg"], ["", "Hash brown"]])
        #expect(read("mcdonalds, sausage mcmuffin with egg", mcmuffin) == [["McDonald's", "sausage mcmuffin with egg"]])
        // A chain dish already listed is not rebuilt from the other foods.
        #expect(
            read(
                "starbucks latte, scrambled eggs and an english muffin",
                [
                    item("Latte", 1, "cup", 470, brand: "Starbucks"), item("Scrambled eggs", 2, "piece", 100), item("English muffin", 1, "piece", 55),
                ]
            ).map { $0[1] } == ["Latte", "Scrambled eggs", "English muffin"])
    }

    @Test func aChainDishIsNeverRebuiltFromFoodsOrderedOnTheirOwn() {
        func read(_ description: String, _ items: [MealReply.Item]) -> [[String]] {
            SeenFoods.read(reply(items), description: description, photo: true).map { [$0.brand, $0.name] }
        }
        #expect(
            read(
                "scrambled eggs, an english muffin and a starbucks latte",
                [
                    item("Scrambled eggs", 2, "piece", 100), item("English muffin", 1, "piece", 55), item("Latte", 1, "cup", 470, brand: "Starbucks"),
                ]) == [["", "Scrambled eggs"], ["", "English muffin"], ["Starbucks", "Latte"]])
        #expect(
            read(
                "bacon and eggs with a dunkin coffee",
                [
                    item("Bacon", 3, "strip", 30), item("Eggs", 2, "piece", 100), item("Coffee", 1, "cup", 350, brand: "Dunkin'"),
                ]) == [["", "Bacon"], ["", "Eggs"], ["Dunkin'", "Coffee"]])
        #expect(
            read(
                "starbucks egg bites and a blueberry muffin",
                [
                    item("Egg bites", 2, "piece", 130, brand: "Starbucks"), item("Blueberry muffin", 1, "piece", 110),
                ]) == [["Starbucks", "Egg bites"], ["", "Blueberry muffin"]])
        #expect(
            read(
                "mcdonalds sausage biscuit and scrambled eggs",
                [
                    item("Sausage biscuit", 1, "piece", 120, brand: "McDonald's"), item("Scrambled eggs", 2, "piece", 100),
                ]) == [["McDonald's", "Sausage biscuit"], ["", "Scrambled eggs"]])
        // Sauces the person named are theirs, and the nuggets are the McNuggets.
        let nuggets = [item("Chicken nuggets", 10, "piece", 160), item("BBQ sauce", 1, "packet", 28), item("Sweet and sour sauce", 1, "packet", 28)]
        for said in ["mcdonalds 10 piece mcnuggets with bbq and sweet and sour sauce", "mcdonalds 10 piece mcnuggets"] {
            #expect(read(said, nuggets).map { $0[1] } == ["Chicken nuggets", "BBQ sauce", "Sweet and sour sauce"], "\(said)")
        }
    }

    @Test func aChainDishDropsSmallToppingsButKeepsRealSides() {
        let starbucks = SeenFoods.read(
            reply([
                item("Bacon gouda sandwich", 1, "sandwich", 150), item("Banana", 1, "piece", 118), item("Tomato", 2, "slices", 60),
                item("Bacon", 2, "strip", nil),
            ]), description: "starbucks bacon gouda sandwich and a banana", photo: true)
        #expect(starbucks.map { [$0.brand, $0.name] } == [["Starbucks", "Bacon gouda sandwich"], ["", "Banana"]])
        let popeyes = SeenFoods.read(
            reply([
                item("Chicken sandwich", 1, "sandwich", 200, brand: "Popeyes"), item("Red beans and rice", 1, "cup", 240),
                item("Pickles", 3, "piece", 15),
            ]), description: "popeyes chicken sandwich and red beans and rice", photo: true)
        #expect(popeyes.map(\.name) == ["Chicken sandwich", "Red beans and rice"])
    }

    @Test func aDescriptionsFoodsAreTheOnesItNames() {
        // Apple's model echoed its instructions' typical weights for this one.
        let echo = reply([
            item("chicken breast", 1, "piece", 170), item("lettuce", 1, "leaf", 10), item("hamburger bun", 1, "piece", 55),
            item("diet coke", 1, "can", 355),
        ])
        #expect(SeenFoods.read(echo, description: "a can of diet coke").map(\.name) == ["diet coke"])
        // A brand the description doesn't name is a guess; a signature item names its own chain.
        let mac = reply([item("Big Mac", 1, "sandwich", 215, brand: "Burger King"), item("medium fries", 1, "serving", 115)])
        #expect(SeenFoods.read(mac, description: "big mac and medium fries").map(\.brand) == ["McDonald's", ""])
        #expect(SeenFoods.read(mac, description: "burger king big mac").first?.brand == "Burger King")
        let latte = reply([item("Latte", 1, "cup", 350, brand: "Starbucks")])
        #expect(SeenFoods.read(latte, description: "a latte").first?.brand == "")
        // A named dish may be split into parts the description doesn't name.
        let burger = reply(["Hamburger bun", "Beef patty", "Cheddar cheese", "Ketchup"].map { item($0) } + [item("Cola", 1, "can", 355)])
        #expect(SeenFoods.read(burger, description: "a cheeseburger and a coke").count == 5)
        // Nothing recognisably named leaves the reading as it is.
        let pbj = reply([item("Peanut butter", 2, "tbsp", 32), item("Grape jelly", 1, "tbsp", 20), item("White bread", 2, "slice", 60)])
        #expect(SeenFoods.read(pbj, description: "a pb&j").count == 3)
        // Seen in a photo, foods stand without being named.
        #expect(SeenFoods.read(echo, description: "a can of diet coke", photo: true).count == 4)
    }

    @Test func anEspressoDrinkIsWhatIsInTheCup() {
        let flatWhite = SeenFoods.read(reply([item("flat white", 1, "cup", 200)]), description: "a flat white")
        #expect(
            flatWhite == [
                SeenFood(name: "espresso", brand: "", quantity: 60, unit: "ml", grams: nil, label: "flat white"),
                SeenFood(name: "whole milk", brand: "", quantity: 120, unit: "ml", grams: nil, label: "flat white"),
            ])
        let lattes = SeenFoods.read(reply([item("large oat milk latte", 2, "piece", 700)]), description: "two large oat milk lattes")
        #expect(lattes.map(\.name) == ["espresso", "oat milk"])
        #expect(lattes.map(\.quantity) == [168, 784])
        // A stated volume is the whole drink.
        let poured = SeenFoods.read(reply([item("skim cappuccino", 12, "fl oz", 355)]), description: "12 oz skim cappuccino")
        #expect(poured.map(\.name) == ["espresso", "nonfat milk"])
        #expect(poured.map(\.quantity) == [118, 237])
        #expect(SeenFoods.read(reply([item("americano", 1, "cup", 240)]), description: "an americano").map(\.name) == ["brewed coffee"])
        #expect(
            SeenFoods.read(reply([item("mocha", 1, "cup", 300)]), description: "a mocha").map(\.name)
                == ["espresso", "whole milk", "chocolate syrup"])
        // The milk the model listed beside the drink is the drink's own; a size in the description sizes it.
        let latte = SeenFoods.read(reply([item("oat milk", 1, "cup", 240), item("latte", 1, "cup", 350)]), description: "a large oat milk latte")
        #expect(latte.map(\.name) == ["espresso", "oat milk"])
        #expect(latte.map(\.quantity) == [84, 392])
        // A chain's drink stays whole, and other drinks are untouched.
        #expect(SeenFoods.read(reply([item("latte", 1, "cup", 350, brand: "Starbucks")]), description: "starbucks latte").map(\.name) == ["latte"])
        #expect(SeenFoods.read(reply([item("chai", 1, "cup", 240)]), description: "a chai").map(\.name) == ["chai"])
    }

    @Test func anEspressoDrinksMilkAndSizeComeFromItsOwnItem() {
        func cup(_ description: String, _ items: [MealReply.Item]) -> [String] {
            SeenFoods.read(reply(items), description: description).map { "\(Int($0.quantity)) \($0.name)" }
        }
        // Another food's almond or size word is not the drink's.
        #expect(
            cup("a latte and an almond croissant", [item("latte", 1, "cup", 350), item("almond croissant", 1, "piece", 70)])
                == ["60 espresso", "280 whole milk", "1 almond croissant"])
        #expect(
            cup("a latte and a large croissant", [item("latte", 1, "cup", 350), item("croissant", 1, "piece", 70)])
                == ["60 espresso", "280 whole milk", "1 croissant"])
        #expect(
            cup("a small latte and a big muffin", [item("latte", 1, "cup", 350), item("muffin", 1, "piece", 110)])
                == ["45 espresso", "210 whole milk", "1 muffin"])
        #expect(
            cup("a latte with an almond croissant", [item("latte", 1, "cup", 350), item("almond croissant", 1, "piece", 70)])
                == ["60 espresso", "280 whole milk", "1 almond croissant"])
        // Two drinks, each with its own milk, by name or by what was ordered.
        let named = cup("an oat milk latte and a soy cappuccino", [item("oat milk latte", 1, "cup", 350), item("soy cappuccino", 1, "cup", 180)])
        #expect(named == ["60 espresso", "280 oat milk", "60 espresso", "120 soy milk"])
        let ordered = cup("an oat milk latte and a soy cappuccino", [item("latte", 1, "cup", 350), item("cappuccino", 1, "cup", 180)])
        #expect(ordered == ["60 espresso", "280 oat milk", "60 espresso", "120 soy milk"])
        #expect(cup("a latte with oat milk", [item("latte", 1, "cup", 350)]) == ["60 espresso", "280 oat milk"])
        #expect(cup("a 2% latte", [item("latte", 1, "cup", 350)]) == ["60 espresso", "280 2% milk"])
    }

    @Test func milkOrCoffeeOrderedOnItsOwnIsKept() {
        func names(_ description: String, _ items: [MealReply.Item]) -> [String] {
            SeenFoods.read(reply(items), description: description).map(\.name)
        }
        #expect(
            names("a mocha and a glass of milk", [item("Mocha", 1, "cup", 300), item("Milk", 1, "glass", 250)])
                == ["espresso", "whole milk", "chocolate syrup", "Milk"])
        #expect(
            names("cereal with milk and a latte", [item("Cereal", 1, "cup", 40), item("Milk", 1, "cup", 240), item("Latte", 1, "cup", 350)])
                == ["Cereal", "Milk", "espresso", "whole milk"])
        #expect(
            names("a latte and a coffee", [item("Latte", 1, "cup", 350), item("Coffee", 1, "cup", 240)]) == ["espresso", "whole milk", "Coffee"])
        // The drink's own milk, said with it, is still absorbed.
        #expect(names("a latte with oat milk", [item("latte", 1, "cup", 350), item("oat milk", 1, "cup", 240)]) == ["espresso", "oat milk"])
        // A photo's milk beside a latte is the latte's, and its kind is the latte's milk.
        let photo = SeenFoods.read(reply([item("oat milk", 1, "cup", 240), item("latte", 1, "cup", 350)], scene: "a latte", food: true), photo: true)
        #expect(photo.map(\.name) == ["espresso", "oat milk"])
        // So is a milk added "with" the drink, in a photo's note or after a comma.
        let noted = SeenFoods.read(
            reply([item("latte", 1, "cup", 350), item("oat milk", 1, "cup", 240)], scene: "a latte", food: true),
            description: "with oat milk", photo: true)
        #expect(noted.map(\.name) == ["espresso", "oat milk"])
        #expect(names("a latte, with oat milk", [item("latte", 1, "cup", 350), item("oat milk", 1, "cup", 240)]) == ["espresso", "oat milk"])
    }

    @Test func theDishADescriptionNames() throws {
        let chain = try #require(Chain.find(in: "big mac from mcdonalds and a banana"))
        let (dish, others) = SeenFoods.dishNamed(by: chain)
        #expect(dish == "big mac")
        #expect(others == ["banana"])
        #expect(Chain.all.count == 31)
        #expect(Chain.find(in: "a chipotle burrito bowl")?.brand == "Chipotle")
        #expect(Chain.find(in: "chipotle mayo") == nil)
    }
}

@Suite("Stated amounts")
struct StatedAmountTests {
    func read(_ description: String, _ items: [MealReply.Item]) -> [String] {
        SeenFoods.read(reply(items), description: description).map {
            "\(FoodText.clean(String(format: "%g", $0.quantity))) \($0.unit) \($0.name) \($0.grams.map { String(format: "%g", $0) } ?? "-")"
        }
    }

    @Test func whatThePersonSaidOverridesTheModel() {
        #expect(
            read("8 oz steak and a baked potato", [item("Steak", 1, "1 piece", 170), item("Baked potato", 1, "piece", 250)])
                == ["8 oz Steak 226.796", "1 piece Baked potato 250"])
        #expect(
            read("200g chicken breast with a cup of rice", [item("Chicken breast", 1, "piece", 170), item("Rice", 1, "cup", 160)])
                == ["200 g Chicken breast 200", "1 cup Rice 160"])
        #expect(
            read("2 cups of milk and half a bagel", [item("milk", 1, "cup", 250), item("bagel", 1, "piece", 100)])
                == ["2 cups milk 500", "0.5 piece bagel 50"])
        #expect(read("two eggs", [item("Eggs", 1, "piece", 50)]) == ["2 piece Eggs 100"])
        // A bowl keeps the model's weight; a measured food isn't recounted by a bare number.
        #expect(read("a bowl of oatmeal", [item("Oatmeal", 1, "cup", 250)]) == ["1 bowl Oatmeal 250"])
        #expect(read("a handful of almonds", [item("almonds", 30, "g", 30)]) == ["30 g almonds 30"])
        // A note without a food counts the one food measured that way.
        #expect(
            SeenFoods.read(
                reply([item("Pepperoni pizza", 1, "slice", 110)], scene: "a pizza box", food: true),
                description: "large pepperoni, ate 3 slices", photo: true
            ).first?.quantity == 3)
        // "150 g" in the unit field is 150 g.
        #expect(read("", [item("Greek yogurt", 1, "150 g", 150)]) == ["150 g Greek yogurt 150"])
    }

    @Test func fractionsAndQuantityWordsAreReadWhole() {
        // "1/2" is a half, not 1 with "/2 bagel" left over.
        #expect(
            read("1/2 bagel with cream cheese", [item("bagel", 0.5, "piece", 50), item("cream cheese", 1, "tbsp", 15)])
                == ["0.5 piece bagel 50", "1 tbsp cream cheese 15"])
        #expect(read("1/2 bagel", [item("bagel", 1, "piece", 100)]) == ["0.5 piece bagel 50"])
        #expect(read("1 1/2 slices of toast", [item("Toast", 1, "slice", 30)]) == ["1.5 slices Toast 45"])
        #expect(read("1½ slices of toast", [item("Toast", 1, "slice", 30)]) == ["1.5 slices Toast 45"])
        #expect(read("3/4 cup of oats", [item("Oats", 1, "cup", 80)]) == ["0.75 cup Oats 60"])
        // An article before a quantity word or an amount gives way to it.
        #expect(read("a couple of slices of pizza", [item("Pizza", 2, "slice", 220)]) == ["2 slice Pizza 220"])
        #expect(read("a couple of slices of pizza", [item("Pizza", 1, "slice", 110)]) == ["2 slices Pizza 220"])
        #expect(read("a dozen eggs", [item("Eggs", 1, "piece", 50)]) == ["12 piece Eggs 600"])
        #expect(read("a pair of eggs", [item("Eggs", 1, "piece", 50)]) == ["2 piece Eggs 100"])
        #expect(read("a half dozen eggs", [item("Eggs", 1, "piece", 50)]) == ["6 piece Eggs 300"])
        #expect(read("half a dozen eggs", [item("Eggs", 1, "piece", 50)]) == ["6 piece Eggs 300"])
        #expect(read("an 8 oz steak", [item("Steak", 1, "piece", 170)]) == ["8 oz Steak 226.796"])
        // "A few" and "a handful" say no amount: the model's stands.
        #expect(read("a few cookies", [item("Cookies", 3, "piece", 45)]) == ["3 piece Cookies 45"])
        #expect(read("a bunch of grapes", [item("Grapes", 20, "piece", 100)]) == ["20 piece Grapes 100"])
        // A plain article still counts one.
        #expect(read("a banana", [item("Banana", 2, "piece", 236)]) == ["1 piece Banana 118"])
    }

    @Test func aFatLevelOrASizeIsNotACount() {
        #expect(
            read("cereal with 2% milk", [item("Cereal", 1, "cup", 40), item("2% milk", 1, "glass", 250)])
                == ["1 cup Cereal 40", "1 glass 2% milk 250"])
        #expect(read("6 inch turkey sub", [item("Turkey sub", 1, "sandwich", 230)]) == ["1 sandwich Turkey sub 230"])
        #expect(read("a 12-inch pizza", [item("Pizza", 1, "pizza", 800)]) == ["1 pizza Pizza 800"])
        #expect(read("12-inch pizza", [item("Pizza", 1, "pizza", 800)]) == ["1 pizza Pizza 800"])
        // Nor is the start of a longer number.
        #expect(
            read("cereal with 1.5% milk", [item("Cereal", 1, "cup", 40), item("1.5% milk", 2, "glass", 500)])
                == ["1 cup Cereal 40", "2 glass 1.5% milk 500"])
    }

    @Test func aDescribedWholeDishKeepsItsToppings() {
        #expect(
            read(
                "two slices of pepperoni pizza",
                [
                    item("Pepperoni pizza", 2, "slice", 220), item("Tomato", 1, "slice", 15),
                    item("Lettuce", 1, "leaf", 10),
                ]) == ["2 slice Pepperoni pizza 220"])
    }
}
