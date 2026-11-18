import SystemCore
import Testing

@testable import FoodDatabase

/// Everyday foods as they're typed with no brand, a word or two, each with a pattern for the plain
/// food that should come first: the cooked chicken, the whole milk, the raw apple, and the food
/// itself where USDA files it under another word ("Pork, cured, bacon", "Salad dressing,
/// mayonnaise", "Frankfurter").
let staples: [(String, String)] = [
    // Meat, fish and eggs.
    ("chicken", "^Chicken, broilers or fryers, .*cooked, roasted"),
    ("chicken breast", "^Chicken, broilers or fryers, breast, .*cooked, roasted"),
    ("chicken thigh", "^Chicken, broilers or fryers, thigh, .*cooked"),
    ("chicken wings", "^Chicken, broilers or fryers, wing, .*cooked"),
    ("ground beef", "^Beef, ground, .*cooked"),
    ("steak", "^Beef, .*steak.*cooked"),
    ("ribeye", "^Beef, rib ?eye"),
    ("sirloin", "^Beef, .*sirloin"),
    ("pork chop", "^Pork, fresh, .*chops.*cooked"),
    ("bacon", "^Pork, cured, bacon, .*cooked"),
    ("ham", "^Ham, "),
    ("sausage", "^Sausage, "),
    ("hot dog", "^Frankfurter, (beef|meat|pork)"),
    ("turkey", "^Turkey, .*cooked, roasted"),
    ("ground turkey", "^Turkey, [Gg]round, .*cooked"),
    ("turkey breast", "^Turkey, .*breast, .*(cooked|roasted)"),
    ("salmon", "^Fish, salmon, .*cooked"),
    ("tuna", "^Fish, tuna, "),
    ("shrimp", "^Crustaceans, shrimp, .*cooked"),
    ("tilapia", "^Fish, tilapia, cooked"),
    ("cod", "^Fish, cod, .*cooked"),
    ("egg", "^Egg, whole, cooked"),
    ("egg white", "^Egg, white, "),
    ("tofu", "^Tofu, (raw|firm|extra firm|soft|hard)"),
    ("meatballs", "^Meatballs, frozen, Italian style"),
    ("pepperoni", "^Pepperoni"),
    ("salami", "^Salami"),
    ("beef jerky", "(?i)jerky"),
    // Dairy.
    ("milk", "^Milk, whole"),
    ("skim milk", "^Milk, nonfat, fluid"),
    ("whole milk", "^Milk, whole"),
    ("almond milk", "^Beverages, almond milk, (unsweetened|sweetened)"),
    ("soy milk", "^Soymilk, original"),
    ("butter", "^Butter, (salted|without salt)"),
    ("cheese", "^Cheese, cheddar"),
    ("cheddar", "^Cheese, cheddar"),
    ("mozzarella", "^Cheese, mozzarella"),
    ("parmesan", "^Cheese, parmesan"),
    ("swiss cheese", "^Cheese, swiss$"),
    ("feta", "^Cheese, feta"),
    ("cream cheese", "^Cheese, cream$"),
    ("cottage cheese", "^Cheese, cottage, (creamed, large or small curd|lowfat, [12]% milkfat$)"),
    ("yogurt", "^Yogurt, plain"),
    ("greek yogurt", "^Yogurt, Greek, plain"),
    ("sour cream", "^Cream, sour, cultured"),
    ("heavy cream", "^Cream, fluid, heavy"),
    ("half and half", "^Cream, fluid, half and half"),
    ("ice cream", "^Ice creams, vanilla"),
    ("whipped cream", "^Cream, whipped"),
    // Grains and bread.
    ("rice", "^Rice, white, long-grain, .*cooked"),
    ("brown rice", "^Rice, brown, .*cooked"),
    ("pasta", "^Pasta, cooked"),
    ("spaghetti", "^Pasta, cooked"),
    ("macaroni", "^Pasta, cooked"),
    ("bread", "^Bread, (white|wheat)"),
    ("white bread", "^Bread, white, commercially prepared \\(includes"),
    ("wheat bread", "^Bread, (wheat|whole-wheat)"),
    ("toast", "^Bread, .*toasted"),
    ("bagel", "^Bagels, plain"),
    ("tortilla", "^Tortillas, ready-to-bake or -fry, (corn|flour)"),
    ("flour tortilla", "^Tortillas, ready-to-bake or -fry, flour"),
    ("corn tortilla", "^Tortillas, ready-to-bake or -fry, corn"),
    ("oatmeal", "^Cereals, oats, .*cooked"),
    ("granola", "^Cereals ready-to-eat, granola"),
    ("quinoa", "^Quinoa, cooked"),
    ("couscous", "^Couscous, cooked"),
    ("pancake", "^Pancakes, plain"),
    ("waffle", "^Waffles?, plain"),
    ("english muffin", "^Muffins, English, plain"),
    ("croissant", "^Croissants, butter"),
    ("crackers", "^Crackers, "),
    ("pita", "^Bread, pita"),
    ("noodles", "^Noodles, egg, .*cooked"),
    // Fruit.
    ("apple", "^Apples, raw, with(out)? skin"),
    ("banana", "^Bananas, raw"),
    ("orange", "^Oranges, raw"),
    ("grapes", "^Grapes, red or green"),
    ("strawberries", "^Strawberries, raw"),
    ("blueberries", "^Blueberries, raw"),
    ("raspberries", "^Raspberries, raw"),
    ("pineapple", "^Pineapple, raw"),
    ("mango", "^Mangos, raw"),
    ("watermelon", "^Watermelon, raw"),
    ("peach", "^Peaches, yellow, raw"),
    ("pear", "^Pears, raw"),
    ("avocado", "^Avocados, raw"),
    ("lemon", "^Lemons, raw"),
    ("lime", "^Limes, raw"),
    ("cherries", "^Cherries, sweet, raw"),
    ("kiwi", "^Kiwifruit"),
    ("grapefruit", "^Grapefruit, raw"),
    ("cantaloupe", "^Melons, cantaloupe, raw"),
    ("raisins", "^Raisins"),
    ("dates", "^Dates"),
    // Vegetables.
    ("broccoli", "^Broccoli, (raw|cooked)"),
    ("spinach", "^Spinach, (raw|cooked)"),
    ("carrot", "^Carrots, (raw|cooked)"),
    ("tomato", "^Tomatoes, red, ripe, raw"),
    ("potato", "^Potatoes, (baked|boiled)"),
    ("sweet potato", "^Sweet potato, cooked, (baked|boiled)"),
    ("onion", "^Onions, raw"),
    ("garlic", "^Garlic, raw"),
    ("lettuce", "^Lettuce, (iceberg|cos or romaine|green leaf|red leaf)"),
    ("cucumber", "^Cucumber, "),
    ("bell pepper", "^Peppers, sweet, (red|green|yellow), raw"),
    ("mushrooms", "^Mushrooms, white"),
    ("corn", "^Corn, sweet, (yellow|white), (cooked|raw)"),
    ("peas", "^Peas, green"),
    ("green beans", "^Beans, snap, green"),
    ("cauliflower", "^Cauliflower, (raw|cooked)"),
    ("zucchini", "^Squash, summer, zucchini"),
    ("asparagus", "^Asparagus"),
    ("kale", "^Kale"),
    ("cabbage", "^Cabbage, (raw|cooked)"),
    ("celery", "^Celery"),
    ("brussels sprouts", "^Brussels sprouts"),
    ("eggplant", "^Eggplant"),
    // Beans, nuts and seeds.
    ("black beans", "^Beans, black, mature seeds, cooked"),
    ("pinto beans", "^Beans, pinto, mature seeds, cooked"),
    ("kidney beans", "^Beans, kidney, .*cooked"),
    ("chickpeas", "^Chickpeas .*cooked"),
    ("lentils", "^Lentils, .*cooked"),
    ("peanuts", "^Peanuts, all types"),
    ("almonds", "^Nuts, almonds"),
    ("walnuts", "^Nuts, walnuts, english"),
    ("cashews", "^Nuts, cashew nuts"),
    ("peanut butter", "^Peanut butter, (smooth|chunk)"),
    ("almond butter", "^Nuts, almond butter"),
    ("hummus", "^Hummus, commercial"),
    ("pistachios", "^Nuts, pistachio nuts"),
    ("sunflower seeds", "^Seeds, sunflower seed kernels"),
    ("chia seeds", "^Seeds, chia seeds"),
    // Oils, sauces and sweeteners.
    ("olive oil", "^Oil, olive"),
    ("canola oil", "^Oil, canola"),
    ("coconut oil", "^Oil, coconut$"),
    ("mayo", "^Salad dressing, mayonnaise, regular"),
    ("mayonnaise", "^Salad dressing, mayonnaise, regular"),
    ("ketchup", "^Catsup$"),
    ("mustard", "^Mustard, prepared, yellow"),
    ("soy sauce", "^Soy sauce made from soy"),
    ("salsa", "^Sauce, salsa, ready-to-serve"),
    ("ranch", "^Salad dressing, ranch dressing, regular"),
    ("honey", "^Honey$"),
    ("maple syrup", "^Syrups, maple"),
    ("sugar", "^Sugars, granulated"),
    ("jam", "^Jams and preserves$"),
    ("jelly", "^Jellies$"),
    ("bbq sauce", "^Sauce, barbecue"),
    ("hot sauce", "^Sauce, (ready-to-serve, pepper or hot|hot chile)"),
    ("vinegar", "^Vinegar, "),
    // Drinks.
    ("coffee", "^Beverages, coffee, brewed, prepared with tap water$"),
    ("tea", "^Beverages, tea, black, brewed"),
    ("orange juice", "^Orange juice"),
    ("apple juice", "^Apple juice, canned or bottled"),
    ("soda", "^Beverages, carbonated, cola"),
    ("coke", "(?i)^(Beverages, carbonated, cola|coca.cola|coke)"),
    ("beer", "^Alcoholic beverage, beer, regular"),
    ("wine", "^Alcoholic beverage, wine, table"),
    ("red wine", "^Alcoholic beverage, wine, table, red"),
    ("white wine", "^Alcoholic beverage, wine, table, white"),
    ("vodka", "^Alcoholic beverage, distilled, vodka"),
    ("whiskey", "^Alcoholic beverage, distilled, whiskey"),
    ("espresso", "^Beverages, coffee, brewed, espresso"),
    ("milkshake", "^Milk shakes?, "),
    // Snacks and sweets.
    ("chips", "^Snacks, potato chips, plain"),
    ("potato chips", "^Snacks, potato chips, plain, salted"),
    ("tortilla chips", "^(Snacks, )?[Tt]ortilla chips"),
    ("popcorn", "^Snacks, popcorn, (air-popped|oil-popped|home-prepared)"),
    ("pretzels", "^(Snacks, pretzels|Pretzels)"),
    ("cookie", "^Cookies, "),
    ("chocolate", "^(Chocolate|Candies, milk chocolate)"),
    ("dark chocolate", "^Chocolate, dark"),
    ("brownie", "^Cookies, brownies"),
    ("donut", "^Doughnuts"),
    ("muffin", "^Muffins, (blueberry|plain)"),
    ("granola bar", "granola bars?"),
    // Dishes.
    ("french fries", "[Ff]rench fries"),
    ("pizza", "^Pizza, cheese"),
    ("burger", "^(Hamburger|Cheeseburger)"),
    ("hamburger", "^Hamburger"),
    ("cheeseburger", "^Cheeseburger"),
    ("burrito", "^(Fast foods, burrito, with beans$|Burrito, beef and bean, microwaved)"),
    ("mac and cheese", "^Macaroni and [Cc]heese"),
    ("fried rice", "(?i)fried rice"),
]

/// The everyday form of a plain food: what a word or two typed with no brand most likely means.
/// These rank foods made here, so they run without either catalog.
@Suite("Everyday forms")
struct EverydayFormTests {
    func first(_ query: String, _ names: [String], hints: RankHints = RankHints()) -> String {
        rankSearch(query, names.map { OwnWordsTests.food($0) }, hints: hints).first?.food.name ?? ""
    }

    @Test("the word USDA files a food under isn't held against it")
    func filedUnder() {
        // Most salsas are under "Sauce", so that's where salsa is: the plain one comes before a
        // kind that happens to lead with the word.
        let salsas = ["Sauce, salsa", "Sauce, salsa, verde", "Sauce, salsa, chipotle", "Salsa, mango", "Tortilla chips with salsa"]
        #expect(first("salsa", salsas) == "Sauce, salsa")
        // A food or two don't say where a food is filed.
        #expect(first("salsa", ["Sauce, salsa", "Salsa, mango", "Bread, wheat"]) == "Salsa, mango")
    }

    @Test("the word naming the food isn't one a name only includes")
    func includes() {
        let foods = ["Bagels, plain (includes onion, poppy, sesame)", "Snacks, popcorn, air-popped", "Spices, poppy seed"]
        #expect(first("pop", foods) == "Snacks, popcorn, air-popped")
        #expect(first("poppy", foods) == "Spices, poppy seed")
        // A word describing the food may be one of those it includes.
        #expect(first("poppy bagel", foods) == "Bagels, plain (includes onion, poppy, sesame)")
    }

    @Test("a people's traditional food is a kind of its own unless it's asked for")
    func tradition() {
        let corn = ["Corn, white, steamed (Navajo)", "Corn, white, steamed, kernels on cob"]
        #expect(first("corn", corn) == "Corn, white, steamed, kernels on cob")
        #expect(first("navajo corn", corn) == "Corn, white, steamed (Navajo)")
    }

    @Test("a food made of something else comes after a form of the food")
    func instead() {
        #expect(first("meatballs", ["Meatballs, meatless", "Meatballs, frozen, Italian style"]) == "Meatballs, frozen, Italian style")
        #expect(first("meatless meatballs", ["Meatballs, meatless", "Meatballs, frozen, Italian style"]) == "Meatballs, meatless")
    }

    @Test("the usual kind of a food is the one filed under what it's made of")
    func usual() {
        let bacon = ["Bacon, turkey, low sodium", "Pork, cured, bacon, cooked, pan-fried", "Bacon bits, meatless"]
        #expect(first("bacon", bacon) == "Pork, cured, bacon, cooked, pan-fried")
        #expect(first("turkey bacon", bacon) == "Bacon, turkey, low sodium")
        // Looked up by the stem a word is searched by.
        let whiskey = ["Whiskey sour mix, bottled", "Alcoholic beverage, distilled, whiskey, 86 proof"]
        #expect(first("whiskey", whiskey) == "Alcoholic beverage, distilled, whiskey, 86 proof")
    }

    @Test("with or without its skin, a food is still the food")
    func skin() {
        let first = { (name: String, foods: [String]) in
            scoreFoods(Named(name: name, brand: ""), foods.map { OwnWordsTests.food($0) }).first?.food.name ?? ""
        }
        #expect(first("apple", ["Rose-apples, raw", "Apples, raw, with skin"]) == "Apples, raw, with skin")
        #expect(
            first("sweet potato", ["Sweet potato leaves, cooked", "Sweet potato, cooked, boiled, without skin"])
                == "Sweet potato, cooked, boiled, without skin")
        // The skin alone is still a part of its own.
        let chicken = ["Chicken, broilers or fryers, skin only, cooked, roasted", "Chicken, broilers or fryers, meat only, cooked, roasted"]
        #expect(first("chicken", chicken) == "Chicken, broilers or fryers, meat only, cooked, roasted")
    }

    @Test("a brand that is an everyday word of foods isn't a brand the search names")
    func plainBrand() {
        let listed = OwnWordsTests.food("Chia Seeds", brand: "Seeds")
        let plain = OwnWordsTests.food("Seeds, chia seeds, dried")
        let score = { (foods: [Food], hints: RankHints) in
            rankSearch("chia seeds", foods, hints: hints).first { $0.food.id == listed.id }?.score ?? 0
        }
        let hints = RankHints(plain: ["seeds"])
        // Beside a plain food with every word, the one listed under "Seeds" is no brand's.
        #expect(score([listed, plain], RankHints()) > score([listed, plain], hints) + 1.5)
        // With no plain food by those words, it is the food asked for.
        #expect(score([listed], hints) == score([listed], RankHints()))
    }
}

/// Everyday searches over the catalogs the app ships.
@Suite("Everyday staples", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"))
struct StaplesTests {
    let catalog = Catalogs.both

    @Test("an everyday food typed plainly comes first")
    func basket() {
        var first = 0
        var three = 0
        var missed: [String] = []
        for (query, pattern) in staples {
            let names = catalog.top(query)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            if names.contains(where: { matches(pattern, $0) }) { three += 1 }
        }
        print("Staples: \(first) of \(staples.count) first, \(three) in the first three")
        // A few points under what the ranking does on this catalog (every one first), so a change
        // can cost a staple or two for something worth more, and no more than that.
        #expect(Double(first) >= 0.97 * Double(staples.count), "\(missed.joined(separator: " | "))")
        #expect(Double(three) >= 0.99 * Double(staples.count), "\(missed.joined(separator: " | "))")
    }

    @Test("an everyday name finds the food the catalogs file under another")
    func everydayNames() {
        // Typed apart or as one word, hot dogs are USDA's frankfurters and a bell pepper its sweet pepper.
        #expect(catalog.respell("hot dog").also["dog"]?.contains("frankfurter") == true)
        #expect(catalog.respell("hotdogs").also["dogs"]?.contains("frankfurter") == true)
        #expect(catalog.respell("bell peppers").also["bell"] == ["sweet"])
        // Alone, ranch is the dressing and spaghetti is also "Pasta"; with another word they're themselves.
        #expect(catalog.respell("ranch").text == "ranch salad dressing")
        #expect(catalog.respell("ranch chicken").text == "ranch chicken")
        #expect(catalog.respell("spaghetti").also["spaghetti"] == ["pasta"])
        #expect(catalog.respell("spaghetti squash").also["spaghetti"] == nil)
        #expect(catalog.top("spaghetti squash", 1).first.map { matches("^Squash, winter, spaghetti", $0) } == true)
    }

    @Test("the person's own food is found by the name as typed")
    func ownFood() {
        // "ranch" alone is searched as "ranch salad dressing"; their Ranch Dip has only the word typed.
        let own = Food(id: "custom:dip", name: "Ranch Dip", basis: .g, nutrients: .zero, source: .custom)
        let found = catalog.search("ranch", personal: [PersonalFood(food: own, score: 1)])
        #expect(found.first?.food.id == own.id && found.first?.personal == true)
        #expect(found.dropFirst().first.map { matches("^Salad dressing, ranch dressing", $0.food.name) } == true)
    }

    @Test("a word of foods that a few are listed under as a brand is read as the food's")
    func plainWords() {
        #expect(catalog.searchCatalog("chia seeds", known: [:]).plain.contains("seeds"))
        // Oreo is a brand on most labels that have the word; cookies are cookies.
        #expect(catalog.searchCatalog("oreo cookies", known: [:]).plain == ["cookies"])
        // Counted past the first 2,000 labels: "organic" is in the brand of one food in seven that have it.
        #expect(catalog.searchCatalog("organic milk", known: [:]).plain == ["milk"])
    }
}
