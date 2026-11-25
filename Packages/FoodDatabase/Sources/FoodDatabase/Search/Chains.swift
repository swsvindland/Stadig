/// Restaurant chains people log meals from. USDA has a few items for a dozen of them and the
/// packaged catalog what some sell in shops, so a chain typed with a food neither has is read as
/// that food from a restaurant: "five guys fries" is fries from fast food, not whatever label has
/// "five", "guys" or "fries" in its name.
enum Chains {
    /// A chain found in a search.
    struct Found: Equatable {
        /// Where its words are among the words searched.
        var span: Range<Int>
        /// The word the catalog's foods from such a place say, stemmed: "fast" food or "restaurant".
        var place: String
    }

    static let names: [String] = [
        "mcdonalds", "burger king", "wendys", "taco bell", "subway", "starbucks", "dunkin donuts", "dunkin", "dominos", "papa johns",
        "pizza hut", "chick-fil-a", "popeyes", "kfc", "arbys", "sonic", "jack in the box", "dairy queen", "white castle", "hardees",
        "carls jr", "little caesars", "krispy kreme", "chipotle", "panera", "panera bread", "in-n-out", "five guys", "shake shack", "whataburger",
        "culvers",
        "panda express", "olive garden", "applebees", "chilis", "ihop", "dennys", "red lobster", "outback", "texas roadhouse",
        "cheesecake factory", "buffalo wild wings", "wingstop", "raising canes", "zaxbys", "bojangles", "jimmy johns", "jersey mikes",
        "firehouse subs", "qdoba", "moes", "del taco", "el pollo loco", "sweetgreen", "cava", "tim hortons", "jamba", "smoothie king",
        "auntie annes", "cinnabon", "baskin robbins", "cold stone", "cracker barrel", "waffle house", "steak n shake", "red robin",
        "pf changs", "noodles and company", "portillos", "wawa", "sheetz", "costco food court",
        // As they're also typed.
        "chickfila", "innout", "steak and shake",
        // And more that people log from.
        "dutch bros", "crumbl", "crumbl cookies", "insomnia cookies", "jollibee", "tropical smoothie cafe", "jamba juice", "boston market",
        "churchs chicken", "checkers", "rallys", "freddys", "smashburger", "habit burger", "cook out", "krystal", "hungry jacks", "blaze pizza",
        "mod pizza", "marcos pizza", "papa murphys", "sbarro", "jets pizza", "hungry howies", "round table pizza", "godfathers pizza", "cicis",
        "cicis pizza", "chuck e cheese", "potbelly", "quiznos", "blimpie", "penn station", "which wich", "schlotzskys", "mcalisters",
        "jasons deli", "charleys", "einstein bros", "pret a manger", "nandos", "long john silvers", "captain ds", "slim chickens", "golden chick",
        "huey magoos", "taco cabana", "taco johns", "baja fresh", "chuys", "torchys tacos", "guzman y gomez", "rubios", "pei wei", "wagamama",
        "chopt", "honeygrow", "yogurtland", "menchies", "pinkberry", "wetzels pretzels", "longhorn steakhouse", "golden corral", "tgi fridays",
        "ruby tuesday", "hooters", "benihana", "carrabbas", "maggianos", "macaroni grill", "buca di beppo", "bonefish grill", "first watch",
    ]

    /// The ones with tables and a kitchen, whose food the catalog files as "from restaurant".
    private static let seated: Set<String> = [
        "olive garden", "applebees", "chilis", "ihop", "dennys", "red lobster", "outback", "texas roadhouse", "cheesecake factory",
        "buffalo wild wings", "cracker barrel", "waffle house", "red robin", "pf changs", "longhorn steakhouse", "golden corral", "tgi fridays",
        "ruby tuesday", "hooters", "benihana", "carrabbas", "maggianos", "macaroni grill", "buca di beppo", "bonefish grill", "first watch",
        "wagamama", "nandos", "pei wei",
    ]

    /// The chains named by a word foods have for themselves (a chipotle mayo, green chilis, a
    /// cava brut), with what each sells, stemmed. Such a word is the chain only when typed as a
    /// possessive ("chili's fajitas") or with one of those ("chipotle burrito bowl").
    private static let sells: [String: Set<String>] = [
        "chipotle": Set(["burrito", "bowl", "taco", "quesadilla", "barbacoa", "carnitas", "sofritas", "guac", "guacamole"].map(stem)),
        "chilis": [],
        "cava": Set(["bowl", "pita"].map(stem)),
    ]

    private struct Chain {
        var name: String
        /// The words a search keeps of it, stemmed.
        var words: [String]
    }

    /// The longest names first: "dunkin donuts coffee" is Dunkin' Donuts' before Dunkin's donuts.
    private static let chains: [Chain] = names.map { Chain(name: $0, words: words($0).map(stem)) }
        .filter { !$0.words.isEmpty }
        .sorted { $0.words.count > $1.words.count }

    /// Whether a word is a chain's, stemmed. `owning` are the words written as possessives,
    /// which the words have lost: "chili's" is Chili's and "chili" the food.
    private static func isWord(_ word: String, of chain: Chain, _ theirs: String, owning: Set<String>) -> (named: Bool, possessive: Bool) {
        // "Mo" is what the stem of Moe's comes to, not a way of writing it.
        if stem(word) == theirs { return (chain.words.count > 1 || length(word) > 2, false) }
        let possessive = owning.contains(word) && stem(word + "s") == theirs
        return (possessive, possessive)
    }

    /// The words written with "'s" after them.
    private static func possessives(in text: String) -> Set<String> {
        let written = tokens(text)
        return Set(written.indices.dropLast().filter { written[$0 + 1] == "s" }.map { written[$0] })
    }

    private static func place(of chain: Chain) -> String { stem(seated.contains(chain.name) ? "restaurant" : "fast") }

    /// The chain a search starts or ends with, when other words are typed with it. `typed` is
    /// the search as written, which shows a possessive.
    static func chain(in searched: [String], typed: String = "") -> Found? {
        let owning = possessives(in: typed)
        for chain in chains where chain.words.count < searched.count {
            for span in [0..<chain.words.count, (searched.count - chain.words.count)..<searched.count] {
                let read = zip(searched[span], chain.words).map { isWord($0, of: chain, $1, owning: owning) }
                guard read.allSatisfy(\.named) else { continue }
                if let menu = sells[chain.name], !read.contains(where: \.possessive) {
                    let rest = searched.indices.filter { !span.contains($0) }.map { stem(searched[$0]) }
                    guard rest.contains(where: menu.contains) else { return nil }
                }
                return Found(span: span, place: place(of: chain))
            }
        }
        return nil
    }

    /// What each chain is known for, the most ordered first, in the words a search finds them
    /// by. A chain typed with nothing after it leads with these, as that kind of place serves
    /// them: "five guys" was a label called Five, "in-n-out" an emu's outside drum and
    /// "wingstop" nothing at all. Not the chains whose name is a food's word alone (`sells`),
    /// nor Cracker Barrel, Wawa and Sheetz, whose names are on what shops sell.
    static let knownFor: [String: [String]] = [
        "mcdonalds": ["big mac", "cheeseburger", "french fries", "chicken mcnuggets", "egg mcmuffin"],
        "burger king": ["whopper", "cheeseburger", "french fries", "chicken sandwich"],
        "wendys": ["classic single", "chicken nuggets", "french fries", "frosty"],
        "taco bell": ["taco", "burrito", "quesadilla", "nachos"],
        "subway": ["turkey sub", "italian sub", "meatball sub", "tuna sub"],
        "starbucks": ["latte", "cappuccino", "iced coffee", "mocha"],
        "dunkin donuts": ["donut", "iced coffee", "bagel", "latte"],
        "dunkin": ["donut", "iced coffee", "bagel", "latte"],
        "dominos": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "papa johns": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "pizza hut": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "little caesars": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "chick-fil-a": ["chicken sandwich", "chicken nuggets", "french fries", "milkshake"],
        "chickfila": ["chicken sandwich", "chicken nuggets", "french fries", "milkshake"],
        "popeyes": ["fried chicken", "chicken sandwich", "biscuit", "french fries"],
        "kfc": ["fried chicken", "biscuit", "mashed potatoes", "coleslaw"],
        "arbys": ["roast beef sandwich", "curly fries", "milkshake"],
        "sonic": ["cheeseburger", "corn dog", "tater tots", "milkshake"],
        "jack in the box": ["cheeseburger", "taco", "french fries", "chicken sandwich"],
        "dairy queen": ["blizzard", "cheeseburger", "french fries", "ice cream cone"],
        "white castle": ["slider", "french fries"],
        "hardees": ["cheeseburger", "biscuit", "french fries", "chicken tenders"],
        "carls jr": ["cheeseburger", "french fries", "chicken tenders"],
        "krispy kreme": ["glazed donut", "donut"],
        "panera": ["sandwich", "salad", "mac and cheese", "bagel"],
        "panera bread": ["sandwich", "salad", "mac and cheese", "bagel"],
        "in-n-out": ["cheeseburger", "hamburger", "french fries", "milkshake"],
        "innout": ["cheeseburger", "hamburger", "french fries", "milkshake"],
        "five guys": ["cheeseburger", "french fries", "hot dog", "milkshake"],
        "shake shack": ["cheeseburger", "french fries", "milkshake", "hot dog"],
        "whataburger": ["hamburger", "cheeseburger", "french fries", "chicken sandwich"],
        "culvers": ["cheeseburger", "french fries", "chicken tenders", "ice cream"],
        "panda express": ["orange chicken", "chow mein", "fried rice", "beef and broccoli"],
        "olive garden": ["breadsticks", "fettuccine alfredo", "salad", "minestrone"],
        "ihop": ["pancakes", "omelet", "french toast", "hash browns"],
        "red lobster": ["shrimp", "lobster", "biscuit", "fried shrimp"],
        "outback": ["steak", "baked potato", "salad"],
        "texas roadhouse": ["steak", "dinner roll", "ribs", "baked potato"],
        "cheesecake factory": ["cheesecake", "fettuccine alfredo", "salad"],
        "buffalo wild wings": ["wings", "boneless wings", "french fries"],
        "wingstop": ["wings", "boneless wings", "french fries"],
        "raising canes": ["chicken tenders", "french fries", "texas toast", "coleslaw"],
        "zaxbys": ["chicken tenders", "wings", "french fries"],
        "bojangles": ["fried chicken", "biscuit", "french fries"],
        "jimmy johns": ["turkey sub", "italian sub", "ham sub"],
        "jersey mikes": ["turkey sub", "italian sub", "ham sub"],
        "firehouse subs": ["turkey sub", "italian sub", "meatball sub"],
        "qdoba": ["burrito", "burrito bowl", "taco", "quesadilla"],
        "moes": ["burrito", "burrito bowl", "taco", "quesadilla"],
        "del taco": ["taco", "burrito", "french fries", "quesadilla"],
        "el pollo loco": ["grilled chicken", "burrito", "chicken taco"],
        "sweetgreen": ["salad", "chicken salad"],
        "tim hortons": ["donut", "iced coffee", "bagel"],
        "jamba": ["smoothie"],
        "smoothie king": ["smoothie"],
        "auntie annes": ["soft pretzel"],
        "cinnabon": ["cinnamon roll"],
        "baskin robbins": ["ice cream", "milkshake"],
        "cold stone": ["ice cream", "milkshake"],
        "waffle house": ["waffle", "hash browns", "eggs", "bacon"],
        "steak n shake": ["cheeseburger", "milkshake", "french fries"],
        "steak and shake": ["cheeseburger", "milkshake", "french fries"],
        "red robin": ["cheeseburger", "french fries"],
        "pf changs": ["fried rice", "orange chicken", "lo mein"],
        "noodles and company": ["mac and cheese", "pasta with tomato sauce"],
        "portillos": ["hot dog", "french fries"],
        "costco food court": ["hot dog", "pizza"],
        "dutch bros": ["latte", "iced coffee", "mocha"],
        "crumbl": ["cookie", "chocolate chip cookie", "sugar cookie"],
        "crumbl cookies": ["cookie", "chocolate chip cookie", "sugar cookie"],
        "insomnia cookies": ["cookie", "chocolate chip cookie"],
        "jollibee": ["fried chicken", "spaghetti with meat sauce", "cheeseburger", "french fries"],
        "tropical smoothie cafe": ["smoothie", "chicken wrap"],
        "jamba juice": ["smoothie"],
        "boston market": ["rotisserie chicken", "mashed potatoes", "mac and cheese", "cornbread"],
        "churchs chicken": ["fried chicken", "biscuit", "french fries", "mashed potatoes"],
        "checkers": ["cheeseburger", "french fries", "chicken sandwich", "milkshake"],
        "rallys": ["cheeseburger", "french fries", "chicken sandwich", "milkshake"],
        "freddys": ["cheeseburger", "french fries", "ice cream", "hot dog"],
        "smashburger": ["cheeseburger", "french fries", "milkshake"],
        "habit burger": ["cheeseburger", "french fries", "milkshake"],
        "cook out": ["cheeseburger", "french fries", "milkshake", "hot dog"],
        "krystal": ["slider", "french fries"],
        "hungry jacks": ["whopper", "cheeseburger", "french fries"],
        "blaze pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "mod pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "marcos pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "papa murphys": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "sbarro": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "jets pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "hungry howies": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "round table pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "godfathers pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "cicis": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "cicis pizza": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "chuck e cheese": ["pepperoni pizza", "cheese pizza", "breadsticks", "wings"],
        "potbelly": ["turkey sub", "italian sub", "ham sub"],
        "quiznos": ["turkey sub", "italian sub", "ham sub"],
        "blimpie": ["turkey sub", "italian sub", "ham sub"],
        "penn station": ["turkey sub", "italian sub", "ham sub"],
        "which wich": ["turkey sub", "italian sub", "ham sub"],
        "schlotzskys": ["turkey sub", "italian sub", "ham sub"],
        "mcalisters": ["sandwich", "salad", "baked potato"],
        "jasons deli": ["sandwich", "salad", "baked potato"],
        "charleys": ["cheesesteak", "french fries"],
        "einstein bros": ["bagel", "cream cheese", "egg sandwich", "iced coffee"],
        "pret a manger": ["sandwich", "salad", "iced coffee"],
        "nandos": ["grilled chicken", "french fries", "rice"],
        "long john silvers": ["fried fish", "french fries", "hush puppies", "fried shrimp"],
        "captain ds": ["fried fish", "french fries", "hush puppies", "fried shrimp"],
        "slim chickens": ["chicken tenders", "french fries", "texas toast"],
        "golden chick": ["chicken tenders", "french fries", "texas toast"],
        "huey magoos": ["chicken tenders", "french fries", "texas toast"],
        "taco cabana": ["taco", "burrito", "quesadilla", "nachos"],
        "taco johns": ["taco", "burrito", "quesadilla", "nachos"],
        "baja fresh": ["taco", "burrito", "quesadilla", "nachos"],
        "chuys": ["taco", "burrito", "quesadilla", "nachos"],
        "torchys tacos": ["taco", "burrito", "quesadilla", "nachos"],
        "guzman y gomez": ["burrito", "burrito bowl", "nachos", "taco"],
        "rubios": ["fish taco", "burrito", "quesadilla"],
        "pei wei": ["orange chicken", "fried rice", "lo mein"],
        "wagamama": ["ramen", "fried rice", "dumplings"],
        "chopt": ["salad", "chicken salad"],
        "honeygrow": ["salad", "chicken salad"],
        "yogurtland": ["frozen yogurt"],
        "menchies": ["frozen yogurt"],
        "pinkberry": ["frozen yogurt"],
        "wetzels pretzels": ["soft pretzel"],
        "longhorn steakhouse": ["steak", "baked potato", "salad"],
        "golden corral": ["fried chicken", "mashed potatoes", "steak", "dinner roll"],
        "tgi fridays": ["chicken wings", "mozzarella sticks", "ribs", "french fries"],
        "ruby tuesday": ["salad", "cheeseburger", "ribs"],
        "hooters": ["wings", "boneless wings", "french fries"],
        "benihana": ["fried rice", "steak", "shrimp"],
        "carrabbas": ["lasagna", "fettuccine alfredo", "chicken parmesan", "salad"],
        "maggianos": ["lasagna", "fettuccine alfredo", "chicken parmesan", "salad"],
        "macaroni grill": ["lasagna", "fettuccine alfredo", "chicken parmesan", "salad"],
        "buca di beppo": ["lasagna", "fettuccine alfredo", "chicken parmesan", "salad"],
        "bonefish grill": ["fish", "shrimp", "salad"],
        "first watch": ["pancakes", "omelet", "bacon", "hash browns"],
    ]

    /// The chains by their names as written with nothing between the letters: "in n out",
    /// "in-n-out" and "innout" are one, as are "wendy's" and "wendys".
    private static let written: [String: String] = Dictionary(names.map { (tokens($0).joined(), $0) }, uniquingKeysWith: { first, _ in first })

    /// Whether a search is a chain's name and nothing else, however it's written.
    static func isName(_ typed: String) -> Bool { written[tokens(typed).joined()] != nil }

    /// What a chain typed with nothing else is known for, and the kind of place it is (as
    /// `Found.place`); nil for any other search, and for a chain with nothing listed. Also
    /// the one chain a name is most of the way to ("five guy", "taco bel", from six letters
    /// and two thirds of the name), and a chain with one letter typed after it ("five guys b"),
    /// which is no food yet.
    static func alone(_ typed: String) -> (name: String, foods: [String], place: String)? {
        let said = tokens(typed)
        let whole = said.joined()
        var name = written[whole]
        if name == nil, whole.count >= 6 {
            let begun = Set(written.filter { $0.key.hasPrefix(whole) && 3 * whole.count >= 2 * $0.key.count }.map { knownFor[$0.value] ?? [] })
            if begun.count == 1 { name = written.first { $0.key.hasPrefix(whole) && 3 * whole.count >= 2 * $0.key.count }?.value }
        }
        if name == nil, said.count > 1, let last = said.last, last.count == 1 { name = written[said.dropLast().joined()] }
        guard let name, let foods = knownFor[name] else { return nil }
        return (name, foods, stem(seated.contains(name) ? "restaurant" : "fast"))
    }

    /// The foods of those that a word begun after the chain may be on its way to: the ones
    /// with a word that starts so first, then the ones that have it within ("bu" is a
    /// cheeseburger's).
    static func begun(_ part: String, of foods: [String]) -> [String] {
        let starts = foods.filter { food in food.split(separator: " ").contains { $0.hasPrefix(part) } }
        return starts + foods.filter { !starts.contains($0) && $0.contains(part) }
    }

    /// The kind of place a brand is, as a model names one for a food, when it's a chain or
    /// starts with one's name: "Chick-fil-A", "Chili's", "Panera Bread", "Five Guys Burgers and
    /// Fries". The word its foods say in the catalog, as `Found.place`.
    static func place(of brand: String) -> String? { named(by: brand)?.place }

    /// The chain such a brand is, by its name here, and the kind of place.
    static func named(by brand: String) -> (name: String, place: String)? {
        let said = words(brand)
        guard !said.isEmpty else { return nil }
        let owning = possessives(in: brand)
        return chains.first { chain in
            chain.words.count <= said.count && zip(said, chain.words).allSatisfy { isWord($0, of: chain, $1, owning: owning).named }
        }.map { ($0.name, place(of: $0)) }
    }

    /// A search that starts or ends with a chain's name, apart: the chain, and the rest as it
    /// was typed. "five guys burger and fries", "pancakes with syrup from mcdonald's".
    static func apart(_ typed: String) -> (name: String, rest: String)? {
        let said = typed.split(separator: " ").map(String.init)
        guard said.count > 1 else { return nil }
        for count in stride(from: min(4, said.count - 1), through: 1, by: -1) {
            if let name = written[tokens(said.prefix(count).joined(separator: " ")).joined()] {
                return (name, said.dropFirst(count).joined(separator: " "))
            }
            if let name = written[tokens(said.suffix(count).joined(separator: " ")).joined()] {
                var rest = Array(said.dropLast(count))
                if let last = rest.last, ["from", "at"].contains(last.lowercased()) { rest.removeLast() }
                return rest.isEmpty ? nil : (name, rest.joined(separator: " "))
            }
        }
        return nil
    }

    /// Whether a label's brand is a chain's name, word for word and however it's written:
    /// "TGI-Fridays" and "Tgi Friday's" are TGI Fridays, and "Panera Bread" is Panera. A
    /// search's brand is otherwise any brand its words start, since it may be half typed, and a
    /// chain's name isn't: Crumbl isn't "Uncle Crumbles Granola", nor Jamba a jambalaya mix.
    /// A food with no brand is the chain's by its name.
    static func isBrand(_ brand: String?, of chain: String) -> Bool {
        guard let brand else { return true }
        // Without the possessive or the plural, which either may be written with, and the
        // small words a search drops: the "a" of Pret A Manger.
        let whole = { (text: String) in words(text).filter { $0 != "s" }.map { $0.hasSuffix("s") && $0.count > 2 ? String($0.dropLast()) : $0 } }
        let wanted = whole(chain).joined()
        let theirs = whole(brand)
        guard !wanted.isEmpty else { return true }
        return theirs.indices.contains { start in
            var run = ""
            for word in theirs[start...] {
                run += word
                if run == wanted { return true }
                if run.count >= wanted.count { break }
            }
            return false
        }
    }
}
