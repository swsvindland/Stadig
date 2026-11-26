import Foundation

/// What's typed in place of words, read as the words: a food's emoji, "w/" for with, a size or
/// a measure said after the food, a count as "x2". A search is read once here, before anything
/// else looks at it, so the rest only ever sees words in the order it knows.
enum Shorthand {
    /// The food an emoji shows, where one food is what it's typed for.
    static let emoji: [String: String] = [
        "🍌": "banana", "🍎": "apple", "🍏": "green apple", "🍐": "pear", "🍊": "orange", "🍋": "lemon", "🍉": "watermelon", "🍇": "grapes",
        "🍓": "strawberries", "🫐": "blueberries", "🍒": "cherries", "🍑": "peach", "🥭": "mango", "🍍": "pineapple", "🥥": "coconut",
        "🥝": "kiwi", "🍅": "tomato", "🥑": "avocado", "🍆": "eggplant", "🥔": "potato", "🥕": "carrot", "🌽": "corn", "🌶": "chili pepper",
        "🫑": "bell pepper", "🥒": "cucumber", "🥬": "lettuce", "🥦": "broccoli", "🧄": "garlic", "🧅": "onion", "🍄": "mushrooms",
        "🥜": "peanuts", "🌰": "chestnuts", "🍞": "bread", "🥐": "croissant", "🥖": "baguette", "🥨": "pretzel", "🥯": "bagel",
        "🥞": "pancakes", "🧇": "waffle", "🧀": "cheese", "🍖": "ribs", "🍗": "chicken drumstick", "🥩": "steak", "🥓": "bacon",
        "🍔": "hamburger", "🍟": "french fries", "🍕": "pizza", "🌭": "hot dog", "🥪": "sandwich", "🌮": "taco", "🌯": "burrito",
        "🥙": "gyro", "🧆": "falafel", "🥚": "egg", "🍳": "fried egg", "🥘": "paella", "🍲": "stew", "🥣": "cereal", "🥗": "salad",
        "🍿": "popcorn", "🧈": "butter", "🧂": "salt", "🥫": "canned soup", "🍱": "bento", "🍘": "rice cracker", "🍙": "rice ball",
        "🍚": "rice", "🍛": "curry", "🍜": "ramen", "🍝": "spaghetti", "🍠": "sweet potato", "🍣": "sushi", "🍤": "fried shrimp",
        "🥟": "dumplings", "🦐": "shrimp", "🦞": "lobster", "🦀": "crab", "🐟": "fish", "🍦": "ice cream", "🍨": "ice cream",
        "🍩": "donut", "🍪": "cookie", "🎂": "cake", "🍰": "cake", "🧁": "cupcake", "🥧": "pie", "🍫": "chocolate", "🍬": "candy",
        "🍭": "lollipop", "🍮": "flan", "🍯": "honey", "🥛": "milk", "☕": "coffee", "🍵": "green tea", "🧃": "juice", "🥤": "soda",
        "🧋": "bubble tea", "🍶": "sake", "🍺": "beer", "🍻": "beer", "🍷": "red wine", "🥂": "champagne", "🍾": "champagne",
        "🍸": "martini", "🍹": "cocktail", "🥃": "whiskey", "💧": "water", "🧊": "ice cubes",
    ]

    /// A size said after the food.
    private static let sizes: Set<String> = ["small", "medium", "large", "jumbo"]

    /// A measure said after the food with no number: "coke can", "almonds handful". Not a cup,
    /// a bowl or a bar, which named last are part of the food: a fruit cup, a rice bowl.
    private static let measures: Set<String> = ["can", "bottle", "glass", "handful", "scoop", "serving", "pinch", "spoonful"]

    /// A measure typed first with no number, which is one of it: "tbsp peanut butter".
    private static let leading: Set<String> = ["tbsp", "tbs", "tsp", "tablespoon", "teaspoon", "oz", "ounce", "handful", "spoonful"]

    /// A little of a food, said before "of": "bite of cake". Without the "of" a bite is a food,
    /// and "taste of" starts a brand's name.
    private static let littles: Set<String> = ["bite", "bites", "sip", "sips", "nibble", "swig", "gulp", "forkful", "mouthful"]

    /// The search as its words. Only whole words are read, so one still being typed is left
    /// alone: "fries l" isn't large fries yet.
    static func spelledOut(_ typed: String) -> String {
        var text = typed
        // An emoji is its food, a word of its own.
        if !text.utf8.allSatisfy({ $0 < 0x80 }) {
            var spelled = ""
            for character in text {
                let key = String(String.UnicodeScalarView(character.unicodeScalars.filter { $0.value != 0xFE0F }))
                guard let word = emoji[key] else {
                    spelled.append(character)
                    continue
                }
                // Not said twice where it follows its own word: "banana 🍌".
                if !spelled.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(word) { spelled += " \(word) " }
            }
            text = spelled.trimmingCharacters(in: .whitespaces)
        }
        let typing = !(text.last?.isWhitespace ?? true)
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }
        let lower = { (i: Int) in words[i].lowercased() }
        // "w/" and "w/o", and a "w" between two foods; not the W of A & W.
        for i in words.indices {
            let word = lower(i)
            if word == "w/o" {
                words[i] = "without"
            } else if word == "w/" || (word == "w" && i > 0 && i < words.count - 1 && !["&", "and", "+", "n"].contains(lower(i - 1))) {
                words[i] = "with"
            } else if word.hasPrefix("w/o"), word.count > 3 {
                words[i] = "without " + words[i].dropFirst(3)
            } else if word.hasPrefix("w/"), word.count > 2 {
                words[i] = "with " + words[i].dropFirst(2)
            }
        }
        // A cup written "c" after its number: "1 c milk", "1 c. milk", "1c milk".
        for i in words.indices.dropLast() {
            let word = lower(i)
            if i > 0, word == "c" || word == "c.", Double(words[i - 1]) != nil {
                words[i] = "cup"
            } else if word.last == "c", word.count > 1, Double(word.dropLast()) != nil {
                words[i] = "\(word.dropLast()) cup"
            }
        }
        // The last word may still be being typed; the rest reads what's typed whole.
        let last = lower(words.count - 1)
        if !typing || last.count > 1 {
            // A count as "x2" after the food.
            if last.first == "x", last.count > 1, Int(last.dropFirst()) != nil {
                words = [String(last.dropFirst())] + words.dropLast()
            } else if sizes.contains(last), Double(words[0]) == nil, !sizes.contains(lower(0)) {
                // A size after the food: "fries large".
                words = [words[words.count - 1]] + words.dropLast()
            } else if measures.contains(last), Double(words[0]) == nil, !words.contains(where: { $0.lowercased() == "of" }) {
                // A measure after the food: "coke can" is a can of coke.
                words = [words[words.count - 1], "of"] + words.dropLast()
            }
        }
        // A measure first with no number is one of it.
        if leading.contains(lower(0)) { words.insert("1", at: 0) }
        // A little of a food is the food.
        if words.count > 2, littles.contains(lower(0)), lower(1) == "of" {
            words.removeFirst(2)
        } else if words.count > 3, ["a", "one"].contains(lower(0)), littles.contains(lower(1)), lower(2) == "of" {
            words.removeFirst(3)
        }
        return words.joined(separator: " ") + (typing ? "" : " ")
    }
}
