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
        "maple syrup", "jam", "jelly", "guacamole", "marinara sauce", "tomato sauce", "alfredo sauce", "salad dressing", "italian dressing",
        "caesar dressing",
        // Drinks.
        "iced coffee", "latte", "cappuccino", "espresso", "green tea", "iced tea", "apple juice", "lemonade", "soda", "coke", "diet coke",
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
        guard let last = typed.last, !known.contains(stem(last)) else { return nil }
        if let word = completing(typed) { return word }
        guard last.utf8.count >= 2, !last.utf8.contains(where: { $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        // The foods that start as typed come before the ones that have the word later.
        for leading in [true, false] {
            for phrase in stemmed {
                if let word = phrase.words.enumerated().first(where: { $1.hasPrefix(last) && ($0 == 0) == leading })?.element { return word }
            }
        }
        return nil
    }

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

    /// Every word of the everyday foods, as searched.
    private static let known: Set<String> = Set(all.flatMap { $0.words.map(stem) })
    private static let stemmed: [(words: [String], stems: [String])] = all.map { ($0.words, $0.words.map(stem)) }
    private static let brands: [(words: [String], stems: [String])] = PopularBrands.names.map { $0.split(separator: " ").map(String.init) }
        .filter { $0.count > 1 }.map { ($0, $0.map(stem)) }

    /// A word that is the start of a food's or a brand's name written without its spaces, with
    /// them put back: "hotd" is "hot d", "icecr" "ice cr" and "redb" "red b". Nil for a word that
    /// is or could be one of a food's own ("eggs" isn't "egg s", and "blackb" is on its way to
    /// blackberries as much as to black beans) or that stops inside the name's first word.
    static func apart(_ word: String) -> String? {
        guard word.utf8.count >= 4, !known.contains(stem(word)), likely([word]) == nil else { return nil }
        for name in spaced where name.joined.hasPrefix(word) && name.joined != word && word.utf8.count > name.words[0].utf8.count {
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
}
