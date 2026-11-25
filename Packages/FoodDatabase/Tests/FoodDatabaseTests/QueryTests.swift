import Foundation
import SystemCore
import Testing

@testable import FoodDatabase

@Suite("Reading a typed search")
struct QueryTests {
    @Test(
        "search expressions keep the food words as stemmed prefixes",
        arguments: [
            ("eggs", #""egg"*"#),
            ("cherry", #""cherr"*"#),
            ("blueberries", #""blueberr"*"#),
            ("mcdonalds", #""mcdonald"*"#),
            ("McDonald's", #""mcdonald"*"#),
            ("Wendy's", #""wend"*"#),
            ("cookies", #""cookie"*"#),
            ("cup of coffee", #""coffee"*"#),
            ("2 eggs", #""egg"*"#),
            ("200 g chicken breast", #""chicken"* AND "breast"*"#),
            ("200g chicken breast", #""chicken"* AND "breast"*"#),
            ("1.5 cups rice", #""rice"*"#),
            ("1/2 cup oats", #""oat"*"#),
            ("8 fl oz milk", #""milk"*"#),
            ("slice of pizza", #""pizza"*"#),
            ("large egg", #""egg"*"#),
            ("2 large eggs", #""egg"*"#),
            ("2 cups", #""cup"*"#),
            ("12", ""),
            // Numbers written into a name stay, and match only themselves.
            ("2% milk", #""2" AND "milk"*"#),
            ("3.25% milk", #""3" AND "25" AND "milk"*"#),
            ("93/7 ground beef", #""93" AND "7" AND "ground"* AND "beef"*"#),
            ("7-up", #""7" AND "up"*"#),
            ("7up", #""7up"*"#),
            // Count and unit words stay when they name the food.
            ("cup", #""cup"*"#),
            ("cup noodles", #""cup"* AND "noodle"*"#),
            // A letter on its own is a whole word: a search waits for a last word's second letter.
            ("k cup", #""k" AND "cup"*"#),
            ("peanut butter cups", #""peanut"* AND "butter"* AND "cup"*"#),
            ("mini wheats", #""mini"* AND "wheat"*"#),
            ("or", #""or"*"#),
            ("crème brûlée", #""creme"* AND "brulee"*"#),
            // The model's looser wordings don't take over a typed word.
            ("fries", #""fries"*"#),
            ("pop", #""pop"*"#),
            ("ketchup", #"("ketchup"* OR "catsup"*)"#),
            ("glazed donut", #""glazed"* AND ("donut"* OR "doughnut"*)"#),
            // A size in inches isn't a word the food must have.
            ("papa johns 14 inch pepperoni", #""papa"* AND "john"* AND "pepperoni"*"#),
            ("6-inch sub", #""sub"*"#),
            (#"" OR - NEAR ( *"#, #""near"*"#),
            ("", ""),
        ])
    func expression(query: String, expected: String) {
        #expect(searchExpression(query) == expected)
    }

    @Test("a number before a food is kept as an optional phrase")
    func counts() {
        #expect(readQuery("12 grain bread").counts.map { [$0.0, $0.1] } == [["12", "grain"]])
        #expect(readQuery("2 eggs").counts.map { [$0.0, $0.1] } == [["2", "eggs"]])
        #expect(readQuery("2 cups rice").counts.isEmpty)
        #expect(readQuery("2% milk").counts.isEmpty)
    }

    @Test("a size in inches is kept aside, however it's written")
    func sizes() {
        // A phone's keyboard types the curly quote after a number.
        for query in [
            "papa johns 14 inch pepperoni", #"papa johns 14" pepperoni"#, "papa johns 14” pepperoni", "papa johns 14-inch pepperoni",
            "papa johns 14in pepperoni", "papa johns 14 in pepperoni", "papa johns 14 inches pepperoni",
        ] {
            #expect(readQuery(query) == QueryReading(words: ["papa", "johns", "pepperoni"], counts: [], sizes: ["14"]), "\(query)")
        }
        #expect(readQuery("6 inch turkey sub") == QueryReading(words: ["turkey", "sub"], counts: [], sizes: ["6"]))
        // Weights and counts are amounts, and a number written into a name stays in it.
        #expect(readQuery("14 oz steak").sizes.isEmpty)
        #expect(readQuery("2 eggs").sizes.isEmpty)
        #expect(readQuery("7-up").sizes.isEmpty)
        #expect(readQuery("12 grain bread").sizes.isEmpty)
    }

    @Test("stems match singular and plural prefixes")
    func stems() {
        #expect(stem("tomatoes") == "tomato")
        #expect(stem("berries") == "berr")
        #expect(stem("strawberry") == "strawberr")
        #expect(stem("hummus") == "hummus")
        #expect(stem("cookies") == "cookie")
        #expect(stem("turkeys") == "turke" && stem("turkey") == "turke")
        #expect(stem("pie") == "pie")
    }

    @Test("a word is another only by an ending words take on")
    func sameWord() {
        // A plural the stem leaves, and a participle: "toast" finds toasted bread.
        #expect(same("pies", "pie") && same("boxes", "box"))
        #expect(same("toasted", "toast") && same("smoked", "smoke") && same("mixed", "mix"))
        // Not any letter or two more.
        for (word, form) in [("pear", "pea"), ("peach", "pea"), ("bunch", "bun"), ("mace", "mac"), ("tartar", "tart"), ("creamer", "cream")] {
            #expect(!same(word, form), "\(form) isn't \(word)")
        }
        // Nor a "d" after a word that doesn't end in "e", nor anything after two letters.
        #expect(!same("brand", "bran") && !same("cod", "co") && !same("loin", "lo"))
    }

    @Test("a word still being typed is read as the everyday word it's on its way to")
    func likelyWords() {
        #expect(EverydayPhrases.likely(["chees"]) == "cheese")
        #expect(EverydayPhrases.likely(["mil"]) == "milk")
        // By the words before it, where a food has them: the "bee" of ground beef, not beets.
        #expect(EverydayPhrases.likely(["ground", "bee"]) == "beef")
        #expect(EverydayPhrases.likely(["kirkland", "chees"]) == "cheese")
        // A word that's already a food's isn't on its way to a longer one.
        for word in ["milk", "pepper", "eggs", "toast"] { #expect(EverydayPhrases.likely([word]) == nil, "\(word)") }
        // One letter is enough after a food's or a brand's first words, and only there.
        #expect(EverydayPhrases.completing(["chicken", "b"]) == "breast")
        #expect(EverydayPhrases.completing(["trader", "j"]) == "joe's")
        #expect(EverydayPhrases.completing(["vitamin", "d"]) == nil)
        #expect(EverydayPhrases.completing(["b"]) == nil)
    }

    @Test("a name being typed as one word is read as its words")
    func typedAsOne() {
        #expect(EverydayPhrases.apart("hotd") == "hot d")
        #expect(EverydayPhrases.apart("icecr") == "ice cr")
        #expect(EverydayPhrases.apart("redb") == "red b")
        // Not a word that is one already, could be one, or stops inside the first.
        #expect(EverydayPhrases.apart("eggs") == nil)
        #expect(EverydayPhrases.apart("blackb") == nil)
        #expect(EverydayPhrases.apart("hot") == nil)
        // Nor one that is only the plural of a name's first word: "fruits" isn't fruit snacks
        // begun, though a letter more is.
        #expect(EverydayPhrases.apart("fruits") == nil)
        #expect(EverydayPhrases.apart("fruitsn") == "fruit sn")
    }

    @Test("a number word or a container before a food is its amount, and part of a name isn't")
    func amountsInWords() {
        #expect(readQuery("two eggs").words == ["eggs"] && readQuery("one banana").words == ["banana"])
        #expect(readQuery("three slices of pizza").words == ["pizza"] && readQuery("two cups of rice").words == ["rice"])
        #expect(readQuery("two scrambled eggs").words == ["scrambled", "eggs"] && readQuery("two large eggs").words == ["eggs"])
        // A name: it goes on in the singular, or is no everyday food.
        #expect(readQuery("three cheese pizza").words == ["three", "cheese", "pizza"])
        #expect(readQuery("two egg omelet").words == ["two", "egg", "omelet"] && readQuery("seven grain bread").words.first == "seven")
        #expect(readQuery("five guys").words == ["five", "guys"] && readQuery("three musketeers").words == ["three", "musketeers"])
        #expect(readQuery("two good yogurt").words.first == "two" && readQuery("seven up").words == ["seven", "up"])
        #expect(readQuery("one bar").words == ["one", "bar"] && readQuery("one a day").words.first == "one")
        // Nor before a unit of a letter or two, which follows a figure: "two g" is Two Good begun.
        #expect(readQuery("two g").words == ["two", "g"] && readQuery("two tablespoons butter").words == ["butter"])
        // Only first, and not alone.
        #expect(readQuery("two").words == ["two"] && readQuery("eggs two").words == ["eggs", "two"])
        // What a food comes in, before "of" or after a number.
        #expect(readQuery("bag of chips").words == ["chips"] && readQuery("head of lettuce").words == ["lettuce"])
        #expect(readQuery("12 pack coke").words == ["coke"] && readQuery("2 ears corn").words == ["corn"])
        #expect(readQuery("small bag of chips").words == ["chips"] && readQuery("jar of peanut butter").words == ["peanut", "butter"])
        // Named last it's part of the food.
        #expect(readQuery("tea bag").words == ["tea", "bag"] && readQuery("cheese stick").words == ["cheese", "stick"])
        #expect(readQuery("juice box").words == ["juice", "box"] && readQuery("head cheese").words == ["head", "cheese"])
        #expect(readQuery("2 fish sticks").words == ["fish", "sticks"])
    }

    @Test("a search in Spanish, or a food's Hindi name, reads as its English")
    func otherLanguages() {
        #expect(inEnglish("pollo") == "chicken" && inEnglish("Frijoles") == "beans" && inEnglish("aloo") == "potato")
        // Spanish says the food and then its kind; an amount stays first.
        #expect(inEnglish("pechuga de pollo") == "chicken breast" && inEnglish("frijoles negros") == "black beans")
        #expect(inEnglish("jugo de naranja") == "orange juice" && inEnglish("pechuga de pollo asada") == "grilled chicken breast")
        #expect(inEnglish("tortillas de harina") == "flour tortillas" && inEnglish("2 huevos") == "2 egg")
        // Each food of two, joined as it was.
        #expect(inEnglish("huevos con chorizo") == "egg with chorizo" && inEnglish("arroz y frijoles") == "rice and beans")
        // A name that isn't the sum of its words, and with accents.
        #expect(
            inEnglish("papas fritas") == "french fries" && inEnglish("jamón") == "ham" && inEnglish("piña y fresas") == "pineapple and strawberries")
        // Not a word that is English alone, a colour with no food, or a name the catalogs have.
        #expect(inEnglish("pan") == nil && inEnglish("queso") == nil && inEnglish("sal") == nil && inEnglish("verde") == nil)
        #expect(inEnglish("carne asada") == nil && inEnglish("arroz con pollo") == nil && inEnglish("pan dulce") == nil)
        #expect(inEnglish("carne asadas") == nil && inEnglish("cafe con leche") == nil)
        // Nor the plural of such a word, which may be as far as another is typed: "sals" is salsa begun.
        #expect(inEnglish("sals") == nil && inEnglish("pans") == nil && inEnglish("papas") == "potato")
        // Nor English made of words Spanish has too, or a name with a word that isn't Spanish.
        #expect(inEnglish("pan pizza") == nil && inEnglish("mango salsa") == nil && inEnglish("del taco") == nil)
        #expect(inEnglish("carne asada fries") == nil && inEnglish("pollo loco") == nil && inEnglish("chicken") == nil)
        // A Hindi name alone; with another word it's a dish.
        #expect(inEnglish("dal") == "lentil curry" && inEnglish("moong dal") == "mung beans" && inEnglish("aloo gobi") == nil)
    }

    @Test("typos count a swapped pair as one and read the start of a word")
    func typoDistance() {
        #expect(typos("protien", "protein", limit: 2) == 1)
        #expect(typos("chiken", "chicken", limit: 1) == 1)
        #expect(typos("abc", "xyz", limit: 1) == 2)
        #expect(misread("chikc", "chicken")?.edits == 1)
        #expect(misread("brocoli", "broccoli")?.meant == "broccoli")
        #expect(misread("coke", "cake")?.edits == 1)
        #expect(misread("cok", "cake") == nil, "short words get no typos")
    }

    @Test("typed searches match the person's own foods by word, not by substring")
    func ownFoods() {
        func named(_ name: String, _ brand: String? = nil) -> Food {
            Food(id: "custom:\(name)", name: name, brand: brand, basis: .g, nutrients: .zero, source: .custom)
        }
        #expect(matchesQuery("eggs", named("Egg, whole, cooked, hard-boiled")))
        #expect(matchesQuery("chicken breast", named("Chicken, broilers or fryers, breast")))
        #expect(matchesQuery("chic", named("Chicken thigh")), "a half-typed word counts")
        #expect(matchesQuery("or", named("Orange juice")), "a short word may be a prefix")
        #expect(matchesQuery("cup of coffee", named("Coffee, brewed")))
        #expect(matchesQuery("tyson", named("Chicken breast", "Tyson")))
        #expect(matchesQuery("oat", named("Oat breakfast")))
        #expect(!matchesQuery("oat", named("Goat cheese")))
        #expect(!matchesQuery("rice", named("Licorice")))
        #expect(!matchesQuery("chicken breast", named("Chicken thigh")))
        #expect(!matchesQuery("", named("Anything")))
        // A number in the search is the variety asked for.
        #expect(matchesQuery("2% milk", named("Milk, reduced fat, fluid, 2% milkfat")))
        #expect(!matchesQuery("2% milk", named("Milk, whole, 3.25% milkfat")))
        #expect(!matchesQuery("2% milk", named("Whole milk")))
        #expect(matchesQuery("93/7 beef", named("Ground beef 93/7")))
        #expect(!matchesQuery("93/7 beef", named("Ground beef 80/20")))
        // A corrected word finds them too.
        #expect(!matchesQuery("chiken", named("Chicken thigh")))
        #expect(matchesQuery("chiken", named("Chicken thigh"), fixes: ["chiken": ["chicken"]]))
        #expect(!matchesQuery("chiken", named("Beef thigh"), fixes: ["chiken": ["chicken"]]))
        // Every word the search looks for, not just one: a frequent food doesn't answer a search it
        // shares one word with.
        #expect(!matchesQuery("flat white", named("Rice, white, long-grain, regular, enriched, cooked")))
        #expect(!matchesQuery("chicken soup", named("Chicken breast")))
        #expect(!matchesQuery("rice cake", named("White rice")))
        #expect(matchesQuery("white ri", named("Rice, white, long-grain, regular, enriched, cooked")))
        // A last letter on its own waits for the next, as the catalog search does.
        #expect(matchesQuery("chicken b", named("Chicken thigh")))
        #expect(!matchesQuery("c", named("C")))
        #expect(!matchesQuery("12", named("12 grain bread")))
    }

    @Test("a profile tells a kind of food from others named with the same words")
    func profiles() throws {
        func food(_ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, _ basis: FoodBasis = .g) -> Food {
            Food(id: "x", name: "x", basis: basis, nutrients: Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat), source: .custom)
        }
        // Mini-Wheats as their labels give them.
        let cereal = try #require(profile([food(360, 9, 82, 2), food(350, 8.3, 85, 2.2), food(370, 10, 80, 1.7), food(345, 9.1, 81.7, 2.5)]))
        #expect(likeness(food(377, 16.4, 78.7, 0), cereal) > 0.9, "shredded wheat")
        #expect(likeness(food(229, 11.4, 42.9, 4.3), cereal) < -0.9, "wheat bread")
        #expect(likeness(food(268, 10.7, 51.8, 0.9), cereal) < 0, "pita pockets")
        // A food counted per serving has no amounts to compare, and three foods are too few to say.
        #expect(likeness(food(110, 3, 23, 0.5, .serving), cereal) == 0)
        #expect(profile([food(360, 9, 82, 2), food(350, 8, 85, 2), food(370, 10, 80, 2)]) == nil)
    }

    @Test("a food named after the one searched for ranks below it")
    func namedAfter() {
        func packaged(_ name: String) -> Food { Food(id: "off:\(name)", name: name, brand: "Acme", basis: .g, nutrients: .zero, source: .off) }
        let cakes = [
            "Celebration Cake Pretzels", "Cinnamon Coffee Cake Muffins", "Cinnamon Coffee Cake", "Chocolate Cake with Fudge Filling",
            "Carrot Cake Cookies",
        ]
        let ranked = rankSearch("cake", cakes.map(packaged)).map(\.food.name)
        // Filling after "with" is what's in the cake, not what the cake is made into.
        #expect(Set(ranked.prefix(2)) == ["Cinnamon Coffee Cake", "Chocolate Cake with Fudge Filling"], "\(ranked)")
        // Asked for by name, the other food comes first.
        #expect(rankSearch("cake pretzels", cakes.map(packaged)).first?.food.name == "Celebration Cake Pretzels")
        let spreads = rankSearch("peanut butter", ["Peanut Butter Cups", "Creamy Peanut Butter"].map(packaged)).map(\.food.name)
        #expect(spreads == ["Creamy Peanut Butter", "Peanut Butter Cups"])
    }

    @Test("restaurant and packaged foods are recognized as branded")
    func branded() {
        func usda(_ name: String) -> Food { Food(id: "usda:1", name: name, basis: .g, nutrients: .zero, source: .usda) }
        #expect(isBranded(usda("McDONALD'S, french fries")))
        #expect(isBranded(usda("T.G.I. FRIDAY'S, french fries")))
        #expect(isBranded(usda("DOMINO'S 14\" Pepperoni Pizza, Classic Hand-Tossed Crust")))
        #expect(isBranded(Food(id: "off:1", name: "Ketchup", basis: .g, nutrients: .zero, source: .off)))
        #expect(!isBranded(usda("Fast foods, potato, french fried in vegetable oil")))
        #expect(!isBranded(usda("Tomatoes, red, ripe, raw, year round average")))
        #expect(brandWords(name: "McDONALD'S, BIG MAC", brand: "") == ["mcdonald"])
        // A chain or brand USDA writes in capitals before the food is its brand.
        #expect(brandWords(name: #"PAPA JOHN'S 14" Pepperoni Pizza, Original Crust"#, brand: "") == ["papa", "john"])
        #expect(brandWords(name: #"LITTLE CAESARS 14" Original Round Cheese Pizza, Regular Crust"#, brand: "") == ["little", "caesars"])
        #expect(brandWords(name: "SILK Chocolate, soymilk", brand: "") == ["silk"])
        #expect(brandWords(name: "T.G.I. FRIDAY'S, chicken fingers", brand: "") == ["t", "g", "i", "friday"])
        #expect(brandWords(name: "Fast foods, potato, french fried in vegetable oil", brand: "").isEmpty)
        #expect(brandWords(name: "Pizza, cheese topping, regular crust", brand: "").isEmpty)
        // It isn't what the name leads with: the food after it is.
        let pizza = FoodText(name: #"PAPA JOHN'S 14" Pepperoni Pizza, Original Crust"#, brand: "", source: .usda)
        #expect(pizza.lead == ["pepperoni", "pizza"] && pizza.own == ["papa", "john"])
        #expect(FoodText(name: "McDONALD'S, BIG MAC", brand: "", source: .usda).lead == ["mcdonald"])
    }
}
