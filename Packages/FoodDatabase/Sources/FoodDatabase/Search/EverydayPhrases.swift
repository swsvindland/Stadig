import Foundation

/// What people most often mean to type, said as they'd say it. The catalogs know which foods
/// exist but not which are eaten: USDA's foods carry no count, and a label's scans say nothing of
/// a banana. Suggestions lean on this list for the plain foods, the most logged first, and on the
/// search's own rows for brands, products and everything it doesn't have.
enum EverydayPhrases {
    /// The foods logged most of all.
    static let top: [String] = [
        "eggs", "chicken breast", "chicken", "rice", "banana", "coffee", "milk", "bread", "oatmeal", "greek yogurt", "peanut butter", "apple",
        "cheese", "butter", "avocado", "salmon", "ground beef", "potato", "protein shake", "olive oil", "almonds", "pasta", "broccoli", "yogurt",
        "toast", "water",
    ]

    /// The foods nearly everyone logs.
    static let first: [String] = [
        "egg whites", "chicken thigh", "ground turkey", "tuna", "shrimp", "steak", "bacon", "turkey", "ham", "sausage", "beef", "white rice",
        "brown rice", "bagel", "tortilla", "cereal", "granola", "quinoa", "whole milk", "almond milk", "oat milk", "cheddar cheese",
        "cottage cheese", "cream cheese", "orange", "strawberries", "blueberries", "grapes", "spinach", "carrots", "tomato", "sweet potato",
        "onion", "cucumber", "lettuce", "bell pepper", "mushrooms", "green beans", "corn", "black beans", "beans", "walnuts", "mayonnaise",
        "ketchup", "honey", "sugar", "black coffee", "tea", "orange juice", "protein bar", "protein powder", "pizza", "burger", "french fries",
        "sandwich", "salad", "soup", "chips", "cookie", "chocolate", "ice cream",
    ]

    /// Foods and dishes most people log now and then.
    static let second: [String] = [
        // Meat, fish and eggs.
        "chicken wings", "chicken drumstick", "chicken tenders", "chicken nuggets", "grilled chicken", "rotisserie chicken", "fried chicken",
        "chicken salad", "chicken soup", "chicken sandwich", "turkey breast", "turkey bacon", "pork chop", "pork tenderloin", "pulled pork",
        "ribs", "ribeye", "sirloin", "hot dog", "meatballs", "pepperoni", "salami", "beef jerky", "tilapia", "cod", "tuna salad", "sardines",
        "crab", "lobster", "scallops", "tofu", "hard boiled egg", "scrambled eggs", "fried egg", "omelet", "pork", "fish",
        // Dairy.
        "skim milk", "2% milk", "chocolate milk", "soy milk", "coconut milk", "half and half", "heavy cream", "sour cream", "whipped cream",
        "mozzarella", "parmesan", "swiss cheese", "feta", "string cheese", "american cheese", "provolone", "goat cheese", "ricotta", "kefir",
        // Grains and bread.
        "spaghetti", "macaroni", "noodles", "ramen", "white bread", "wheat bread", "sourdough bread", "english muffin", "croissant", "pancakes",
        "waffles", "french toast", "pita", "naan", "flour tortilla", "corn tortilla", "crackers", "couscous", "grits", "cornbread", "biscuit",
        "muffin", "blueberry muffin", "donut",
        // Fruit.
        "banana bread", "raspberries", "blackberries", "pineapple", "mango", "watermelon", "peach", "pear", "cherries", "kiwi", "lemon", "lime",
        "grapefruit",
        "cantaloupe", "clementine", "raisins", "dates", "dried cranberries", "applesauce",
        // Vegetables.
        "cauliflower", "zucchini", "asparagus", "kale", "cabbage", "celery", "brussels sprouts", "eggplant", "peas", "garlic", "red onion",
        "baby carrots", "cherry tomatoes", "romaine lettuce", "arugula", "sweet corn", "edamame", "beets", "butternut squash", "jalapeno",
        "olives", "pickles", "coleslaw", "baked potato", "mashed potatoes", "hash browns", "tater tots", "sweet potato fries", "potato salad",
        // Beans, nuts and seeds.
        "pinto beans", "kidney beans", "chickpeas", "lentils", "refried beans", "baked beans", "hummus", "peanuts", "cashews", "pistachios",
        "pecans", "almond butter", "sunflower seeds", "chia seeds", "flax seeds", "pumpkin seeds", "trail mix", "nuts",
        // Oils, sauces and sweeteners.
        "canola oil", "coconut oil", "vegetable oil", "mustard", "soy sauce", "salsa", "ranch", "bbq sauce", "hot sauce", "vinegar",
        "maple syrup", "chocolate syrup", "caramel sauce", "jam", "jelly", "guacamole", "marinara sauce", "tomato sauce", "alfredo sauce",
        "salad dressing", "italian dressing",
        "caesar dressing",
        // Drinks.
        "iced coffee", "decaf coffee", "latte", "cappuccino", "espresso", "green tea", "iced tea", "apple juice", "lemonade", "soda", "coke",
        "diet coke",
        "sparkling water", "coconut water", "sports drink", "energy drink", "beer", "wine", "red wine", "white wine", "vodka", "whiskey",
        "margarita", "smoothie", "milkshake", "hot chocolate", "juice",
        // Snacks and sweets.
        "potato chips", "tortilla chips", "popcorn", "pretzels", "granola bar", "dark chocolate", "brownie", "cake", "cheesecake", "cupcake",
        "apple pie", "candy",
        // Dishes.
        "cheeseburger", "hamburger", "burrito", "taco", "quesadilla", "nachos", "mac and cheese", "fried rice", "sushi", "pad thai", "lasagna",
        "chicken noodle soup", "tomato soup", "chili", "beef stew", "grilled cheese", "peanut butter and jelly", "caesar salad", "greek salad",
        "egg salad", "burrito bowl", "stir fry", "chicken curry", "dumplings", "egg roll", "orange chicken", "lo mein", "falafel", "enchiladas",
        "breakfast sandwich", "breakfast burrito",
    ]

    /// Foods from the kitchen, the bar and the deli that are logged less often than those: the
    /// drinks, produce by its variety, condiments, baking ingredients, spices and dishes that a
    /// search finds by these names. They're offered after the rest, and a word is only read as one of
    /// them begun from its fourth letter: "cha" isn't champagne yet.
    static let third: [String] = [
        // Drinks.
        "light beer", "ipa", "lager", "rose wine", "champagne", "prosecco", "tequila", "rum", "gin", "bourbon", "scotch", "brandy", "sake",
        "pina colada", "hard cider", "herbal tea", "chamomile tea", "sweet tea", "cranberry juice", "grapefruit juice", "tomato juice",
        "grape juice", "tonic water", "club soda", "ginger ale", "root beer", "eggnog", "buttermilk", "evaporated milk",
        // Fruit and vegetables.
        "granny smith apple", "gala apple", "fuji apple", "roma tomato", "russet potato", "yukon gold potato", "red potato", "sweet onion",
        "yellow onion", "green onion", "scallions", "shallot", "serrano pepper", "habanero", "bok choy", "napa cabbage", "acorn squash",
        "spaghetti squash", "portobello mushroom", "shiitake mushrooms", "navel orange", "mandarin", "pink grapefruit", "medjool dates",
        "dried apricots", "plantain", "leeks", "radishes", "artichoke", "okra", "collard greens", "swiss chard", "snap peas", "snow peas",
        "bean sprouts", "ginger", "basil", "cilantro", "parsley", "kimchi", "sauerkraut",
        // Meat and fish.
        "bratwurst", "chorizo", "pastrami", "corned beef", "liver", "chicken liver", "lamb", "duck", "venison", "bison", "anchovies",
        "mackerel", "trout", "halibut", "swordfish", "catfish", "clams", "mussels", "oysters", "calamari", "octopus", "crawfish",
        "tempeh",
        // Grains and pasta.
        "barley", "bulgur", "oat bran", "wheat germ", "cornmeal", "rice cakes", "rice noodles", "egg noodles", "soba", "ravioli",
        "tortellini",
        // Condiments and sauces.
        "yellow mustard", "honey mustard", "sriracha", "teriyaki sauce", "worcestershire sauce", "fish sauce", "oyster sauce",
        "hoisin sauce", "enchilada sauce", "tartar sauce", "ranch dressing", "balsamic vinegar", "pesto", "relish", "gravy", "tahini", "capers",
        "horseradish", "wasabi", "miso",
        // Fats and oils.
        "avocado oil", "sesame oil", "ghee", "lard", "margarine", "shortening", "cooking spray",
        // Baking and sweets.
        "brown sugar", "powdered sugar", "agave", "molasses", "corn syrup", "all purpose flour", "cornstarch",
        "baking soda", "baking powder", "vanilla extract", "cocoa powder", "chocolate chips", "yeast", "bread crumbs", "gelatin", "frosting",
        "whipped topping", "custard", "pudding", "frozen yogurt",
        // Spices and seeds.
        "salt", "black pepper", "garlic powder", "onion powder", "chili powder", "curry powder", "paprika", "cumin", "cinnamon", "oregano",
        "turmeric", "nutmeg", "ground ginger", "cayenne pepper", "red pepper flakes", "taco seasoning", "sesame seeds", "hemp seeds",
        // Dishes, as they're cooked and ordered.
        "turkey sandwich", "ham sandwich", "tuna melt", "club sandwich", "fish sandwich", "egg sandwich", "veggie burger", "turkey burger",
        "chili dog", "corn dog", "french dip", "sloppy joe", "chicken quesadilla", "bean burrito", "fish taco", "chicken taco",
        "chicken enchilada", "tamale", "fajitas", "chicken fajitas", "chimichanga", "spaghetti and meatballs", "fettuccine alfredo",
        "chicken alfredo", "chow mein", "chicken fried rice", "general tso chicken", "kung pao chicken", "sweet and sour chicken",
        "beef and broccoli", "sesame chicken", "spring roll", "potstickers", "wonton soup", "california roll", "miso soup", "clam chowder",
        "minestrone", "french onion soup", "chicken pot pie", "shepherds pie", "meatloaf", "pot roast", "chicken parmesan", "eggplant parmesan",
        "chicken tikka masala", "butter chicken", "jambalaya", "paella", "risotto", "stuffed peppers", "beef stroganoff", "chicken and rice",
        "rice and beans", "cobb salad", "garden salad", "chicken caesar salad", "taco salad", "macaroni salad", "macaroni and cheese", "pasta salad",
        "cheese omelet",
        "eggs benedict", "quiche", "crepes", "biscuits and gravy", "home fries", "onion rings", "scalloped potatoes", "mozzarella sticks",
        "buffalo wings", "cheese pizza", "calzone", "garlic bread", "chocolate cake", "carrot cake", "pumpkin pie", "pecan pie", "key lime pie",
        "chocolate chip cookie", "oatmeal cookie", "sugar cookie", "glazed donut", "cinnamon roll", "tiramisu", "ice cream sandwich",
        "banana split", "bread pudding", "rice pudding", "chocolate pudding", "peach cobbler", "pound cake", "angel food cake", "coffee cake",
        "vegetable soup", "lentil soup", "split pea soup", "potato soup", "tortilla soup", "egg drop soup", "hot and sour soup",
        "teriyaki chicken", "chicken stir fry", "beef stir fry", "fish and chips", "chicken and waffles", "fish sticks", "crab cake", "shrimp scampi",
        "fried shrimp",
        "stuffed cabbage", "pierogi", "samosa", "empanada", "spinach dip", "deviled eggs", "creamed spinach", "green bean casserole",
        "baked ziti", "stuffed shells", "manicotti", "tuna casserole", "huevos rancheros", "philly cheesesteak", "pulled pork sandwich",
        "meatball sub", "reuben", "gumbo", "stromboli", "churro", "baklava",
        // Dishes known by their own names.
        "pho", "bibimbap", "tikka masala", "palak paneer", "saag paneer", "biryani", "chicken biryani", "roti", "chapati", "dosa", "idli",
        "pakora", "raita", "chai", "masala chai", "gyro", "shawarma", "tabbouleh", "tzatziki", "dolmas", "spanakopita", "kebab", "gnocchi",
        "carbonara", "bruschetta", "borscht", "gazpacho", "ratatouille", "ceviche", "arepa", "pupusa", "pozole", "menudo", "carnitas",
        "chilaquiles", "chile relleno", "mole", "horchata", "pan dulce", "flan", "tres leches", "gelato", "cubano", "plantains", "congee",
        "bao", "gyoza", "mapo tofu", "egg foo young", "sweet and sour pork", "tteokbokki", "bulgogi", "sashimi", "udon", "tempura",
        // Sweets and snacks.
        "milk chocolate", "white chocolate", "chocolate bar", "candy bar", "peanut butter cup", "fudge", "truffles", "gummy bears", "jelly beans",
        "licorice", "lollipop", "marshmallows", "caramels", "toffee", "cotton candy", "hard candy", "mints", "gum", "kettle corn", "caramel corn",
        "corn chips", "cheese puffs", "pork rinds", "plantain chips", "pita chips", "veggie straws", "energy bar", "cereal bar", "fruit snacks",
        "shredded wheat", "new york strip", "strip steak", "filet mignon", "chicken strips", "graham crackers", "animal crackers", "saltines",
        "biscotti", "shortbread",
        "macaron", "macarons", "macaroon", "smores", "donut holes",
        "scone", "danish", "eclair", "cream puff", "funnel cake", "cobbler", "creme brulee", "tapioca pudding", "popsicle", "sorbet", "jello",
        "cookie dough", "lemon bar", "peanut brittle", "soft pretzel", "snack mix",
        // Supplements.
        "whey protein", "fish oil",
    ]

    /// Everyday foods as they're said with how they're cooked, kept, trimmed or made: what
    /// "grilled", "fat free" or "baby" most often goes on to, the likeliest first. Each is a
    /// search that finds its food, mostly the plain one the ranking reads it as (see `Ease`):
    /// "grilled salmon" is USDA's salmon cooked in dry heat. Only suggestions use them.
    static let ways: [(how: String, foods: [String])] = [
        (
            "grilled",
            [
                "chicken", "chicken breast", "salmon", "shrimp", "steak", "cheese", "vegetables", "chicken thigh", "asparagus", "zucchini",
                "pork chop", "tilapia", "corn", "onions",
            ]
        ),
        ("baked", ["potato", "chicken", "chicken breast", "salmon", "beans", "sweet potato", "cod", "chicken thigh", "tilapia", "ziti"]),
        (
            "roasted",
            [
                "chicken", "vegetables", "potatoes", "broccoli", "sweet potato", "turkey", "almonds", "cauliflower", "brussels sprouts",
                "carrots", "turkey breast", "chicken breast", "salmon", "peanuts", "red peppers", "asparagus", "zucchini",
            ]
        ),
        ("steamed", ["broccoli", "rice", "vegetables", "white rice", "cauliflower", "carrots", "spinach", "green beans", "shrimp", "dumplings"]),
        ("boiled", ["eggs", "potatoes", "chicken", "rice", "chicken breast", "peanuts"]),
        ("fried", ["chicken", "rice", "eggs", "fish", "shrimp", "tofu", "potatoes", "onions", "plantains"]),
        ("sauteed", ["spinach", "mushrooms", "onions", "vegetables", "kale", "shrimp", "peppers"]),
        ("poached", ["eggs", "chicken"]),
        ("smoked", ["salmon", "sausage", "ham"]),
        ("raw", ["almonds", "spinach", "broccoli", "carrots", "honey", "salmon", "cashews", "tuna", "onion", "kale"]),
        ("fresh", ["strawberries", "spinach", "blueberries", "mozzarella", "salsa", "pineapple", "tomato"]),
        ("frozen", ["blueberries", "broccoli", "strawberries", "peas", "vegetables", "spinach", "yogurt", "corn", "pizza"]),
        ("canned", ["tuna", "chicken", "corn", "black beans", "salmon", "green beans", "pumpkin", "peaches"]),
        ("dried", ["mango", "cranberries", "apricots", "figs"]),
        ("cooked", ["rice", "chicken", "pasta", "quinoa", "chicken breast", "white rice", "oatmeal", "lentils", "spinach", "ground beef"]),
        ("lean", ["ground beef", "ground turkey"]),
        ("extra lean", ["ground beef"]),
        ("fat free", ["milk", "greek yogurt", "yogurt", "cottage cheese", "cream cheese", "cheese", "sour cream", "half and half"]),
        ("low fat", ["milk", "yogurt", "cottage cheese", "greek yogurt", "cheese"]),
        ("nonfat", ["greek yogurt", "milk", "yogurt"]),
        ("unsalted", ["butter", "almonds", "peanuts", "cashews", "mixed nuts"]),
        ("salted", ["butter", "peanuts", "almonds"]),
        ("boneless skinless", ["chicken breast", "chicken thigh"]),
        ("boneless", ["chicken breast", "chicken thigh", "pork chop", "chicken wings"]),
        ("skinless", ["chicken breast", "chicken thigh", "salmon"]),
        ("baby", ["spinach", "potatoes", "kale", "back ribs", "bella mushrooms"]),
        ("whole wheat", ["bread", "pasta", "tortilla", "bagel", "english muffin"]),
        ("shredded", ["cheese", "chicken", "mozzarella", "lettuce", "wheat"]),
        ("sliced", ["turkey", "almonds", "ham", "cheese"]),
        ("plain", ["greek yogurt", "yogurt", "bagel"]),
        ("vanilla", ["greek yogurt", "ice cream", "yogurt", "protein powder", "almond milk"]),
        ("unsweetened", ["almond milk", "applesauce", "iced tea", "coconut milk"]),
        ("hard boiled", ["eggs"]),
        ("crunchy", ["peanut butter"]),
        ("creamy", ["peanut butter"]),
        ("sugar free", ["jello", "gum", "syrup", "pudding", "ice cream", "cookies", "candy", "energy drink", "jam", "creamer", "popsicle"]),
        ("gluten free", ["bread", "pasta", "pizza", "crackers", "bagel", "tortilla", "oats", "pancakes", "cookies", "brownie"]),
        ("decaf", ["coffee", "tea", "latte", "espresso", "green tea"]),
        ("light", ["beer", "yogurt", "mayo", "cream cheese", "sour cream", "ranch", "ice cream", "tuna"]),
        ("low sodium", ["soy sauce", "chicken broth", "soup", "bacon", "ham"]),
        ("reduced fat", ["milk", "cheese", "peanut butter", "mayo", "sour cream"]),
        ("low carb", ["tortilla", "bread", "wrap"]),
    ]

    /// Those as phrases. They count less than any everyday food, the first a word goes on to
    /// the most, so "gr" is still Greek yogurt and "grilled s" is grilled salmon.
    static let said: [Phrase] = ways.flatMap { way in
        way.foods.enumerated().map { place, food in
            Phrase(words: "\(way.how) \(food)".split(separator: " ").map(String.init), weight: max(2.5, 4.5 - 0.2 * Double(place)))
        }
    }

    /// A phrase with its words, and how much it counts beside what the search's rows suggest: a
    /// row counts one at most, so the first foods outweigh a handful of rows and the rest a few.
    struct Phrase {
        let words: [String]
        let weight: Double
    }

    /// The whole word a search's last word is most likely on its way to, when it isn't one
    /// already: "chees" is cheese, "mil" milk and the "bee" of "ground bee" beef. It's the word
    /// of the first phrase that reads as the words typed before it too (`completing`), else of
    /// the first food that starts with it, else of the first that has it anywhere; nil for a
    /// word that is already one of a food's ("milk" isn't on its way to milkshake, nor "pepper"
    /// to pepperoni).
    static func likely(_ typed: [String]) -> String? {
        guard let last = typed.last, !known.contains(stem(last)), !isAlone(last) else { return nil }
        if let word = completing(typed) { return word }
        guard last.utf8.count >= 2, !last.utf8.contains(where: { $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        // The foods that start as typed come before the ones that have the word later.
        // The foods logged less often only from four letters.
        let often = last.utf8.count >= 4 ? stemmed.count : common
        for leading in [true, false] {
            for phrase in stemmed.prefix(often) {
                if let word = phrase.words.enumerated().first(where: { $1.hasPrefix(last) && ($0 == 0) == leading })?.element { return word }
            }
        }
        return nil
    }

    /// How many of the phrases are the foods most people log: all but `third`.
    private static let common = top.count + first.count + second.count

    /// The same, read only from a food or a brand whose earlier words are the ones typed before:
    /// "chicken b" is chicken breast, "trader j" Trader Joe's. One letter is enough to go on.
    static func completing(_ typed: [String]) -> String? {
        guard typed.count > 1, let last = typed.last, !last.isEmpty, !last.utf8.contains(where: { $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        let whole = stem(last)
        let before = typed.dropLast().map(stem)
        for context in stride(from: min(before.count, 3), through: 1, by: -1) {
            let said = Array(before.suffix(context))
            for phrase in stemmed + brands {
                for (at, word) in phrase.words.enumerated() where at >= context && word.hasPrefix(last) {
                    guard Array(phrase.stems[(at - context)..<at]) == said else { continue }
                    return phrase.stems[at] == whole ? nil : word
                }
            }
        }
        return nil
    }

    /// The everyday food a search is one typo from, as the word that was meant and where it
    /// is among the words: the "fries" of "french fires", the "beans" of "baked bans", the
    /// "sauce" of "hot saue". Every other word is the food's as typed, the word itself is none
    /// of an everyday food's, and it's one letter added, dropped, changed or swapped with its
    /// neighbour from the food's. Of one word typed alone, or the last of several, from four
    /// letters: "appel", "brocoli".
    static func misspelt(_ typed: [String]) -> (at: Int, word: String)? {
        guard !typed.isEmpty else { return nil }
        let said = typed.map(stem)
        var meter = TypoMeter()
        for phrase in content where phrase.words.count == typed.count {
            var off = -1
            var several = false
            for i in said.indices where said[i] != phrase.stems[i] {
                if off >= 0 { several = true }
                off = i
            }
            guard off >= 0, !several else { continue }
            let (was, word) = (typed[off], phrase.words[off])
            guard was.utf8.count >= (typed.count == 1 || off == typed.count - 1 ? 4 : 3), word.utf8.count >= 4, !known.contains(said[off]),
                [word, phrase.stems[off]].contains(where: { meter.distance(Array(was.utf16)[...], Array($0.utf16)[...], limit: 1) == 1 })
            else { continue }
            // Not a word that may still be on its way to a food: alone, the start of any
            // everyday word or of a name typed without its space ("peanutb"); after others, of
            // the word some food has there ("black bea" is on its way to black beans, not black
            // tea, where "hot saue" is no sauerkraut).
            let onItsWay =
                typed.count == 1
                ? begun.contains { $0.hasPrefix(was) } || apart(was) != nil
                : content.contains { other in
                    other.words.count == typed.count && other.words[off].hasPrefix(was)
                        && said.indices.allSatisfy { $0 == off || said[$0] == other.stems[$0] }
                }
            if onItsWay { return nil }
            return (off, word)
        }
        return nil
    }

    /// The phrases by the words a search keeps: "mac and cheese" is "mac cheese".
    private static let content: [(words: [String], stems: [String])] = all.map { phrase in
        let words = phrase.words.filter { !stopWords.contains($0) }
        return (words, words.map(stem))
    }

    /// Every word of the phrases, which a word still being typed may be the start of.
    private static let begun: Set<String> = Set(all.flatMap(\.words))

    /// The words that are foods of their own: every word of the foods most people log, and of
    /// the rest only the ones that are a food alone. The "roma" of a roma tomato may still be
    /// romaine begun, and the "grape" of grape juice a grapefruit.
    private static let own: [String] = all.prefix(common).flatMap(\.words) + all.dropFirst(common).filter { $0.words.count == 1 }.flatMap(\.words)

    /// Those, as searched.
    private static let known: Set<String> = Set(own.map(stem))

    /// Whether a word, as searched, is one of an everyday food's: "bar", "bread", "water".
    static func isWord(_ stem: String) -> Bool { known.contains(stem) }

    /// Whether the words are an everyday food's name, whole, in the singular or the plural:
    /// "raita", "mapo tofu", "peanut butter cups". None of them is a typo then, however few
    /// foods the catalogs have by them.
    static func isName(_ typed: [String]) -> Bool { names.contains(typed.map(stem).joined(separator: " ")) }
    private static let names: Set<String> = Set(all.map { $0.words.map(stem).joined(separator: " ") })

    /// Whether the words are such a name with its last word still being typed: "mac and che".
    static func isBegun(_ typed: [String]) -> Bool {
        guard let last = typed.last, typed.count > 1 else { return false }
        let before = typed.dropLast().map(stem)
        return stemmed.contains { phrase in
            phrase.words.count == typed.count && phrase.words[typed.count - 1].hasPrefix(last) && Array(phrase.stems.dropLast()) == before
        }
    }

    /// Whether a word is one of an everyday food's as it's written, whole: "curry", where "curr"
    /// is searched the same and may still be on its way to currants.
    static func isWritten(_ word: String) -> Bool { written.contains(word) || isAlone(word) }

    /// Whether a word typed alone has a meaning of its own: "meat" is beef, not meatballs begun.
    private static func isAlone(_ word: String) -> Bool { aloneName(word) != nil || aloneFiled[stem(word)] != nil }
    private static let written: Set<String> = Set(own)
    private static let stemmed: [(words: [String], stems: [String])] = all.map { ($0.words, $0.words.map(stem)) }
    private static let brands: [(words: [String], stems: [String])] = PopularBrands.names.map { $0.split(separator: " ").map(String.init) }
        .filter { $0.count > 1 }.map { ($0, $0.map(stem)) }

    /// A word that is the start of a food's or a brand's name written without its spaces, with
    /// them put back: "hotd" is "hot d", "icecr" "ice cr" and "redb" "red b". Nil for a word that
    /// is or could be one of a food's own ("eggs" isn't "egg s", and "blackb" is on its way to
    /// blackberries as much as to black beans), that stops inside the name's first word, or
    /// that is only that word's plural: "fruits" isn't fruit snacks begun, nor "strips" a
    /// strip steak.
    static func apart(_ word: String) -> String? {
        guard word.utf8.count >= 4, !known.contains(stem(word)), likely([word]) == nil else { return nil }
        for name in spaced
        where name.joined.hasPrefix(word) && name.joined != word && word.utf8.count > name.words[0].utf8.count && word != name.words[0] + "s" {
            var parts: [String] = []
            var rest = Substring(word)
            for part in name.words {
                guard rest.hasPrefix(part) else { break }
                parts.append(part)
                rest = rest.dropFirst(part.count)
            }
            if !rest.isEmpty { parts.append(String(rest)) }
            return parts.joined(separator: " ")
        }
        return nil
    }

    /// The foods and brands of two words or more, as their letters and digits alone.
    private static let spaced: [(joined: String, words: [String])] =
        (all.map(\.words) + PopularBrands.names.map { $0.split(separator: " ").map(String.init) })
        .filter { $0.count > 1 }
        .map { words in
            let plain = words.map { String($0.unicodeScalars.filter(isWordScalar)) }.filter { !$0.isEmpty }
            return (plain.joined(), plain)
        }

    static let all: [Phrase] =
        top.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 14) }
        + first.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 11) }
        + second.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 7) }
        + third.map { Phrase(words: $0.split(separator: " ").map(String.init), weight: 4) }
}
