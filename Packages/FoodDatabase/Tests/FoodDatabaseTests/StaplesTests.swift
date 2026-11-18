import SystemCore
import Testing

@testable import FoodDatabase

/// Everyday foods as they're typed with no brand, a word or two, each with a pattern for the plain
/// food that should come first: the cooked chicken, the whole milk, the raw apple, and the food
/// itself where USDA files it under another word ("Pork, cured, bacon", "Salad dressing,
/// mayonnaise", "Frankfurter").
let staples: [(String, String)] = [
    // Meat, fish and eggs.
    ("chicken", "^Chicken, (broilers or fryers|roasting), .*cooked, roasted"),
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

/// Foods from the pantry, dishes and the forms foods come in, measured after the staples: what a
/// suggestion leads to when it's tapped.
let pantry: [(String, String)] = [
    ("beef", "^Beef, ground, .*cooked"),
    ("pork", "^Pork, fresh, .*cooked"),
    ("ribs", "^Pork, fresh, .*ribs.*cooked"),
    ("cereal", "^Cereals ready-to-eat"),
    ("nuts", "^Nuts, mixed nuts"),
    ("coconut milk", "^(Nuts|Beverages), coconut milk"),
    ("tomato sauce", "^Tomato (sauce|products), canned"),
    ("tomato paste", "^Tomato products, canned, paste"),
    ("taco", "(?i)^(TACO BELL, Original Taco|Fast foods, taco|Taco)"),
    ("nachos", "^Fast foods, nachos"),
    ("chili", "^Chili"),
    ("egg roll", "^(Egg rolls|Restaurant, Chinese, egg rolls)"),
    ("enchiladas", "(?i)cheese enchilada"),
    ("beef stew", "^Beef stew"),
    ("tomato soup", "^Soup, tomato, canned, prepared"),
    ("chicken noodle soup", "^Soup, chicken noodle, canned, prepared"),
    ("pickles", "^Pickles, cucumber, dill"),
    ("sardines", "^Fish, sardine"),
    ("tuna", "^Fish, tuna, (light|white), canned"),
    ("canned tuna", "^Fish, tuna, (light|white), canned"),
    ("anchovies", "^Fish, anchovy, european, canned"),
    ("sourdough bread", "^Bread, french or vienna"),
    ("cornbread", "^Bread, cornbread, (prepared|dry mix, prepared)"),
    ("sports drink", "(?i)(gatorade|powerade|sports? drink)"),
    ("american cheese", "^Cheese, pasteurized process, American"),
    ("black coffee", "^Beverages, coffee, brewed"),
    ("lasagna", "(?i)lasagna with meat"),
    ("spam", "(?i)spam"),
    ("canned corn", "^Corn, sweet, (yellow|white), canned, (whole kernel|vacuum pack|brine pack)"),
    ("pumpkin puree", "^Pumpkin, canned"),
    ("condensed milk", "^Milk, canned, condensed, sweetened"),
    ("evaporated milk", "^Milk, (canned, )?evaporated"),
    ("refried beans", "^(Refried beans|Beans, refried)"),
    ("olives", "^Olives, ripe, canned"),
    ("black olives", "^Olives, ripe"),
    ("applesauce", "^Applesauce, canned, unsweetened"),
    ("baked beans", "^Beans, baked"),
    ("chicken broth", "^Soup, chicken broth"),
    ("oat milk", "(?i)^oat.?milk"),
    ("eggs", "^Egg, whole, cooked"),
    ("water", "^Water, (bottled|tap)"),
    ("white rice", "^Rice, white, long-grain, .*cooked"),
    ("carrots", "^Carrots, raw"),
    ("beans", "^Beans, (black|pinto), mature seeds, cooked"),
    ("fried egg", "^Egg, whole, cooked, fried"),
    ("scrambled eggs", "^Egg, whole, cooked, scrambled"),
    ("hard boiled egg", "^Egg, whole, cooked, hard-boiled"),
    ("grilled chicken", "^Chicken, .*grilled"),
    ("fried chicken", "^Chicken, .*fried"),
    ("chicken nuggets", "^Chicken nuggets"),
    ("chicken tenders", "^Chicken tenders"),
    ("turkey bacon", "^Bacon, turkey"),
    ("pulled pork", "^Pulled pork"),
    ("pork tenderloin", "^Pork, fresh, loin, tenderloin, .*cooked"),
    ("tuna salad", "^Fish, tuna salad"),
    ("crab", "^Crustaceans, crab, .*cooked"),
    ("lobster", "^Crustaceans, lobster, .*cooked"),
    ("2% milk", "^Milk, reduced fat, fluid, 2% milkfat"),
    ("chocolate milk", "^Milk, chocolate"),
    ("provolone", "^Cheese, provolone"),
    ("goat cheese", "^Cheese, goat"),
    ("ricotta", "^Cheese, ricotta"),
    ("pancakes", "^Pancakes, plain"),
    ("waffles", "^Waffles, plain"),
    ("french toast", "^French toast"),
    ("naan", "^Bread, naan"),
    ("biscuit", "^Biscuits, plain"),
    ("blueberry muffin", "^Muffins, blueberry"),
    ("banana bread", "^Bread, banana"),
    ("blackberries", "^Blackberries, raw"),
    ("baby carrots", "^Carrots, baby, raw"),
    ("romaine lettuce", "^Lettuce, cos or romaine"),
    ("arugula", "^Arugula"),
    ("edamame", "^Edamame"),
    ("butternut squash", "^Squash, winter, butternut"),
    ("jalapeno", "^Peppers, jalapeno"),
    ("coleslaw", "^Coleslaw"),
    ("baked potato", "^Potatoes, baked"),
    ("mashed potatoes", "^Potatoes, mashed"),
    ("hash browns", "^Potatoes, hash brown"),
    ("potato salad", "^Potato salad"),
    ("pecans", "^Nuts, pecans"),
    ("flax seeds", "^Seeds, flaxseed"),
    ("pumpkin seeds", "^Seeds, pumpkin"),
    ("trail mix", "^Snacks, trail mix"),
    ("vegetable oil", "^Oil, vegetable"),
    ("marinara sauce", "^Sauce, pasta, spaghetti/marinara"),
    ("italian dressing", "^Salad dressing, italian dressing"),
    ("caesar dressing", "^Salad dressing, caesar"),
    ("green tea", "^Beverages, tea, green, brewed"),
    ("iced tea", "^Tea, iced"),
    ("lemonade", "(?i)^(Beverages, )?lemonade"),
    ("coconut water", "^Nuts, coconut water"),
    ("hot chocolate", "(?i)(hot cocoa|hot chocolate)"),
    ("cheesecake", "^Cake, cheesecake"),
    ("apple pie", "^Pie, apple"),
    ("quesadilla", "(?i)quesadilla"),
    ("orange chicken", "(?i)orange chicken"),
    ("lo mein", "(?i)lo mein"),
    ("falafel", "^Falafel"),
    ("breakfast burrito", "(?i)breakfast burrito"),
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
        let score = { (foods: [Food]) in rankSearch("chia seeds", foods).first { $0.food.id == listed.id }?.score ?? 0 }
        // Beside a plain food with every word, the one listed under "Seeds" is no brand's; with
        // no plain food by those words, it is the food asked for.
        #expect(score([listed]) > score([listed, plain]) + 1.5)
        // A brand people scan keeps its foods whatever plain food has the word.
        let crackers = OwnWordsTests.food("Baked Snack Crackers", brand: "Goldfish")
        let fish = OwnWordsTests.food("Goldfish snack crackers, baked")
        let theirs = { (foods: [Food]) in rankSearch("goldfish crackers", foods).first { $0.food.id == crackers.id }?.score ?? 0 }
        #expect(theirs([crackers]) == theirs([crackers, fish]))
    }

    func first(seen name: String, _ names: [String]) -> String {
        scoreFoods(Named(name: name, brand: ""), names.map { OwnWordsTests.food($0) }).first?.food.name ?? ""
    }

    @Test("a food that lacks a word said is another food where some food has them all")
    func everyWord() {
        // Typed or seen: oat milk isn't sheep's milk, and a packaged food's whole name isn't the plain food.
        let milks = [OwnWordsTests.food("Milk, sheep, fluid"), OwnWordsTests.food("Oat Milk", brand: "Oatly")]
        #expect(scoreFoods(Named(name: "oat milk", brand: ""), milks).first?.food.brand == "Oatly")
        let rice = [
            OwnWordsTests.food("Rice, white, long-grain, regular, cooked"),
            OwnWordsTests.food("Dolmas Vine Leaves stuffed with rice", brand: "Trader Joe's"),
        ]
        #expect(rankSearch("dolmas vine leaves rice", rice).first?.food.brand == "Trader Joe's")
        // A word that only says how a food comes isn't one it lacks, and with no food that has
        // every word the nearest still answers.
        let berries = [OwnWordsTests.food("Strawberries, raw"), OwnWordsTests.food("Fresh Organic Strawberries", brand: "Driscoll's")]
        #expect(scoreFoods(Named(name: "fresh strawberries", brand: ""), berries).first?.food.name == "Strawberries, raw")
        #expect(rankSearch("zesty banana", [OwnWordsTests.food("Bananas, raw")]).first?.food.name == "Bananas, raw")
    }

    @Test("a food is the kind it usually comes in")
    func usualForms() {
        // Canned, for the fish that are: not counted against them, nor what they're packed in.
        let sardines = ["Fish oil, sardine", "Fish, sardine, Atlantic, canned in oil, drained solids with bone"]
        #expect(first("sardines", sardines) == "Fish, sardine, Atlantic, canned in oil, drained solids with bone")
        // A two-word food's own usual kind comes before either word's.
        #expect(
            first("tomato sauce", ["Sauce, tomato chili sauce, bottled", "Tomato sauce, canned, no salt added"])
                == "Tomato sauce, canned, no salt added")
        #expect(first("egg roll", ["Rolls, dinner, egg", "Egg rolls, pork, refrigerated, heated"]) == "Egg rolls, pork, refrigerated, heated")
        #expect(first("beef stew", ["Beef, chuck for stew, cooked, braised", "Beef stew, canned entree"]) == "Beef stew, canned entree")
        // A meat alone is the cut most logged, and the kind the list says ribs are stays ahead
        // of the kind most of USDA's entries are.
        #expect(
            first("beef", ["Beef, cured, corned beef, brisket, cooked", "Beef, ground, 85% lean meat / 15% fat, patty, cooked, broiled"]).hasPrefix(
                "Beef, ground"))
        let ribs = (1...5).map { "Beef, rib, cut \($0), cooked, braised" } + ["Pork, fresh, backribs, separable lean and fat, cooked, roasted"]
        #expect(first("ribs", ribs).hasPrefix("Pork, fresh, backribs"))
    }

    @Test("a group typed alone by its name leads its foods, and a raw food's cooked form is a kind of its own")
    func groups() {
        let nuts = ["Spices, nutmeg, ground", "Nuts, cashew nuts, raw", "Nuts, mixed nuts, dry roasted, with peanuts, with salt added"]
        #expect(first("nuts", nuts) == "Nuts, mixed nuts, dry roasted, with peanuts, with salt added")
        #expect(first("walnuts", ["Nuts, walnuts, dry roasted, with salt added", "Nuts, walnuts, english"]) == "Nuts, walnuts, english")
        #expect(
            first("roasted walnuts", ["Nuts, walnuts, dry roasted, with salt added", "Nuts, walnuts, english"])
                == "Nuts, walnuts, dry roasted, with salt added")
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

    @Test("an everyday food a model names is matched to the same food")
    func seenBasket() {
        var first = 0
        var three = 0
        var missed: [String] = []
        for (name, pattern) in staples {
            let names = catalog.candidates(name: name, brand: nil).prefix(3).map(\.food.name)
            if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(name): \(names.first ?? "nothing")") }
            if names.contains(where: { matches(pattern, $0) }) { three += 1 }
        }
        print("Staples as a model names them: \(first) of \(staples.count) first, \(three) in the first three")
        #expect(Double(first) >= 0.97 * Double(staples.count), "\(missed.joined(separator: " | "))")
        #expect(Double(three) >= 0.99 * Double(staples.count), "\(missed.joined(separator: " | "))")
    }

    @Test("an everyday food is first before its name is typed out")
    func letterByLetter() {
        // Every third staple, typed a letter at a time: the share of its letters it takes to come first.
        var shares: [Double] = []
        var slow: [String] = []
        for (query, pattern) in staples.enumerated().filter({ $0.offset % 3 == 0 }).map(\.element) {
            let letters = Array(query)
            let needed = (2...letters.count).first { count in
                letters[count - 1] != " " && catalog.top(String(letters[..<count]), 1).first.map { matches(pattern, $0) } == true
            }
            shares.append(Double(needed ?? letters.count) / Double(letters.count))
            if needed == nil || needed == letters.count { slow.append(query) }
        }
        let share = shares.reduce(0, +) / Double(shares.count)
        print(String(format: "Staples typed a letter at a time: first after %.0f%% of their letters", 100 * share))
        // Half the letters on this catalog; it was 63% while only whole words were read as foods.
        #expect(share <= 0.56, "only once typed whole: \(slow.joined(separator: ", "))")
    }

    @Test("an everyday food typed with a typo is still first")
    func typos() {
        // One typo in a word of five letters or more of every other staple and pantry food, never
        // its first letter.
        var random = SearchQualityTests.Seeded(state: 11)
        var first = 0
        var asked = 0
        var missed: [String] = []
        for (query, pattern) in (staples + pantry).enumerated().filter({ $0.offset % 2 == 0 }).map(\.element) {
            var words = query.split(separator: " ").map(String.init)
            guard let at = words.indices.filter({ words[$0].count >= 5 && words[$0].allSatisfy(\.isLetter) }).randomElement(using: &random) else {
                continue
            }
            let wrong = SearchQualityTests.typo(words[at], &random)
            guard wrong != words[at] else { continue }
            words[at] = wrong
            asked += 1
            let typed = words.joined(separator: " ")
            if catalog.top(typed, 1).first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append(typed) }
        }
        print("Everyday foods with a typo: \(first) of \(asked) first")
        // 85% before a typo's word was read by the names and usual kind of the word it meant.
        #expect(Double(first) >= 0.87 * Double(asked), "\(missed.joined(separator: ", "))")
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

    @Test("a food a label lists under its own name as a brand is still the plain food")
    func plainWords() {
        #expect(catalog.top("chia seeds", 1).first.map { matches("^Seeds, chia", $0) } == true)
        #expect(catalog.top("american cheese", 1).first.map { matches("^Cheese, pasteurized process, American", $0) } == true)
        // A brand that makes the food keeps it.
        #expect(catalog.search("kraft cheese").first?.food.brand?.lowercased() == "kraft")
        #expect(catalog.search("goldfish cheddar crackers").first.map { matches("(?i)goldfish", "\($0.food.name) \($0.food.brand ?? "")") } == true)
    }

    @Test("pantry foods, dishes and forms come first typed and named as a model would")
    func pantryBasket() {
        for seen in [false, true] {
            var first = 0
            var missed: [String] = []
            for (query, pattern) in pantry {
                let names = seen ? catalog.candidates(name: query, brand: nil).prefix(3).map(\.food.name) : catalog.top(query)
                if names.first.map({ matches(pattern, $0) }) == true { first += 1 } else { missed.append("\(query): \(names.first ?? "nothing")") }
            }
            print("Pantry foods \(seen ? "as a model names them" : "typed"): \(first) of \(pantry.count) first")
            #expect(Double(first) >= 0.95 * Double(pantry.count), "\(seen ? "seen" : "typed"): \(missed.joined(separator: " | "))")
        }
    }
}
