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
    private static let littles: Set<String> = ["bite", "bites", "sip", "sips", "nibble", "swig", "gulp", "forkful", "mouthful", "bit", "touch"]

    /// Words said before a food that say only that it was eaten or when, the longest first:
    /// "i had 2 eggs", "for breakfast oatmeal", "plus a coffee". Not a bare "breakfast", which
    /// names a burrito and a sandwich.
    private static let said: [[String]] = [
        "for breakfast i had", "for lunch i had", "for dinner i had", "today i had", "i just had", "i just ate", "i just drank", "i am having",
        "i also had", "then i had", "and i had", "i'm having", "im having", "i had", "i ate", "i drank", "just had", "just ate", "just drank",
        "also had", "for breakfast", "for lunch", "for dinner", "for dessert", "for a snack", "breakfast was", "lunch was", "dinner was",
        "and then", "and also", "breakfast:", "lunch:", "dinner:", "snack:", "had", "ate", "drank", "having", "also", "plus", "then",
    ].map { $0.split(separator: " ").map(String.init) }

    /// The same said after it: "eggs for breakfast", "coffee this morning", "wine with
    /// dinner", "protein shake after workout".
    private static let after: [[String]] = [
        "for breakfast", "for lunch", "for dinner", "for dessert", "for a snack", "for snack", "with breakfast", "with lunch", "with dinner",
        "at breakfast", "at lunch", "at dinner", "at home", "at work", "this morning", "this afternoon", "this evening", "last night",
        "before bed", "before breakfast", "before lunch", "before dinner", "after breakfast", "after lunch", "after dinner",
        "after my workout", "after the gym", "after workout", "on the side", "tonight", "today", "yesterday",
    ].map { $0.split(separator: " ").map(String.init) }

    /// The words those start with that begin no food's name: typed last, one is on its way.
    private static let starting: Set<String> = ["this", "last", "before", "after", "at"]

    /// How much, said too loosely to be an amount: "a lot of rice", "some more rice", "a
    /// little butter". "A little" is left before the brands that start with it.
    private static let loosely: [[String]] = [
        "a little bit of", "a tiny bit of", "little bit of", "tiny bit of", "a bit of", "a lot of", "a ton of", "lots of", "plenty of",
        "tons of", "loads of", "some more", "a little", "another", "more",
    ].map { $0.split(separator: " ").map(String.init) }
    private static let littleBrands: Set<String> = ["debbie", "debbies", "caesars", "caesar", "bites", "smokies", "potato", "potatoes", "bit"]

    /// What "my" starts a brand's name before, and what "extra" says the kind of: extra
    /// virgin oil, extra lean beef, Extra gum.
    private static let mine: Set<String> = ["protein", "muesli", "mochi", "mo"]
    private static let extras: Set<String> = [
        "virgin", "lean", "sharp", "firm", "large", "long", "light", "dry", "thick", "thin", "crispy", "crunchy", "hot", "spicy", "creamy",
        "dark", "strong", "mild", "old", "fine", "small", "sweet", "soft", "hard", "mature", "wide", "gum", "spearmint", "peppermint",
    ]

    /// A size said of what a food is in or cut into, as the sizes the amounts know.
    private static let roughSizes: [String: String] = ["big": "large", "huge": "large", "giant": "large", "tiny": "small", "little": "small"]
    private static let held: Set<String> = [
        "bowl", "glass", "cup", "plate", "slice", "piece", "handful", "scoop", "serving", "portion", "helping", "mug", "spoonful", "bag",
    ]

    /// What's said for a meal with no food named: "lunch at chipotle" is the chain's.
    private static let meals: Set<String> = ["breakfast", "lunch", "dinner", "food", "meal", "takeout", "something"]

    /// The words without what only says a food was eaten, when, or loosely how much, and
    /// with a chain said after "from" or "at" said first: "i had 2 eggs for breakfast" is 2
    /// eggs, "a lot of rice" rice, "big glass of milk" a large glass of milk and "fries from
    /// mcdonalds" mcdonalds fries. Something is always left: "had" alone is a word begun.
    ///
    /// With `typing` the last word may be part of one: "eggs for br" is still eggs, on its
    /// way to "for breakfast", where the search went to an egg bread and back.
    static func plainly(_ words: [String], typing: Bool = false) -> [String] {
        var words = words
        let lower = { (slice: ArraySlice<String>) in slice.map { $0.lowercased() } }
        var changed = true
        while changed {
            changed = false
            for phrase in said + loosely where words.count > phrase.count && lower(words.prefix(phrase.count)) == phrase {
                // "A little debbie" is the brand, whole or on its way.
                let next = words[phrase.count].lowercased()
                let begun = typing && words.count == phrase.count + 1 && littleBrands.contains { $0.hasPrefix(next) }
                if phrase.last == "little", begun || littleBrands.contains(next) { continue }
                words.removeFirst(phrase.count)
                changed = true
                break
            }
            for phrase in after where words.count > phrase.count && lower(words.suffix(phrase.count)) == phrase {
                // A chain's "at home" is what it sells in shops: IHOP at Home.
                if phrase == ["at", "home"], Chains.isName(words.dropLast(2).joined(separator: " ")) { continue }
                words.removeLast(phrase.count)
                changed = true
                break
            }
            guard words.count > 1 else { break }
            let first = words[0].lowercased()
            let next = words[1].lowercased()
            // "My coffee", "extra rice": the everyday food, where the word starts no name.
            if (first == "my" && !mine.contains(next)) || (first == "extra" && !extras.contains(next)),
                EverydayPhrases.isName(lower(words.dropFirst()))
            {
                words.removeFirst()
                changed = true
            } else if words.count > 2, next == "more", Double(first) != nil || numberWords.contains(first) {
                // "Two more cookies" are two.
                words.remove(at: 1)
                changed = true
            }
        }
        if words.count > 1, let last = words.last?.lowercased() {
            if starting.contains(last) {
                // "Eggs this", with the morning or the night still to come.
                words.removeLast()
            } else if typing, let begun = begunAfter(words.map { $0.lowercased() }) {
                words.removeLast(begun)
            }
        }
        // "Big bowl of", "tiny piece of": the size as an amount knows it.
        if words.count > 2, let size = roughSizes[words[0].lowercased()], held.contains(words[1].lowercased()) { words[0] = size }
        // A chain said after "from" or "at" is the chain's: its name first, as its foods are
        // found.
        if let from = words.lastIndex(where: { ["from", "at"].contains($0.lowercased()) }), from > 0, from < words.count - 1 {
            var place = words[(from + 1)...]
            if place.count > 1, place.first?.lowercased() == "the" { place = place.dropFirst() }
            let name = place.joined(separator: " ")
            let food = Array(words[..<from])
            if Chains.isName(name) {
                words = Array(place) + (food.count == 1 && meals.contains(food[0].lowercased()) ? Chains.usual(at: name) : food)
            } else if typing, Chains.isBegun(name) {
                // On its way to one: "fries from mc" is fries until the chain is named.
                words = food
            }
        }
        return words
    }

    /// How many words at the end are one of the phrases said after a food, still being typed:
    /// the two of "eggs for br". Only after a word that begins no food's name, or "for".
    private static func begunAfter(_ words: [String]) -> Int? {
        guard let last = words.last else { return nil }
        for phrase in after where phrase.count > 1 && (phrase[0] == "for" || starting.contains(phrase[0])) {
            // The longest first: "for a s" before "for a".
            for count in (2...phrase.count).reversed() where words.count > count {
                let whole = count == phrase.count && phrase[count - 1] == last
                if !whole, phrase[count - 1].hasPrefix(last), Array(words.suffix(count).dropLast()) == Array(phrase[..<(count - 1)]) { return count }
            }
        }
        return nil
    }

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
        words = plainly(words, typing: typing)
        guard words.count > 1 else { return words.joined() + (typing ? "" : " ") }
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
