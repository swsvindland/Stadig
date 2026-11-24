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
        "carls jr", "little caesars", "krispy kreme", "chipotle", "panera", "in-n-out", "five guys", "shake shack", "whataburger", "culvers",
        "panda express", "olive garden", "applebees", "chilis", "ihop", "dennys", "red lobster", "outback", "texas roadhouse",
        "cheesecake factory", "buffalo wild wings", "wingstop", "raising canes", "zaxbys", "bojangles", "jimmy johns", "jersey mikes",
        "firehouse subs", "qdoba", "moes", "del taco", "el pollo loco", "sweetgreen", "cava", "tim hortons", "jamba", "smoothie king",
        "auntie annes", "cinnabon", "baskin robbins", "cold stone", "cracker barrel", "waffle house", "steak n shake", "red robin",
        "pf changs", "noodles and company", "portillos", "wawa", "sheetz", "costco food court",
        // As they're also typed.
        "chickfila", "innout", "steak and shake",
    ]

    /// The ones with tables and a kitchen, whose food the catalog files as "from restaurant".
    private static let seated: Set<String> = [
        "olive garden", "applebees", "chilis", "ihop", "dennys", "red lobster", "outback", "texas roadhouse", "cheesecake factory",
        "buffalo wild wings", "cracker barrel", "waffle house", "red robin", "pf changs",
    ]

    /// The chains named by a word foods have for themselves (a chipotle mayo, green chilis, a
    /// cava brut), with what each sells, stemmed. Such a word is the chain only when typed as a
    /// possessive ("chili's fajitas") or with one of those ("chipotle burrito bowl").
    private static let sells: [String: Set<String>] = [
        "chipotle": Set(["burrito", "bowl", "taco", "quesadilla", "barbacoa", "carnitas", "sofritas"].map(stem)),
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

    /// The chain a search starts or ends with, when other words are typed with it. `typed` is
    /// the search as written, which shows a possessive the words have lost: "chili's" is the
    /// chain and "chili" the food.
    static func chain(in searched: [String], typed: String = "") -> Found? {
        let written = tokens(typed)
        let owning = Set(written.indices.dropLast().filter { written[$0 + 1] == "s" }.map { written[$0] })
        for chain in chains where chain.words.count < searched.count {
            for span in [0..<chain.words.count, (searched.count - chain.words.count)..<searched.count] {
                var possessive = false
                let named = zip(searched[span], chain.words).allSatisfy { word, theirs in
                    // "Mo" is what the stem of Moe's comes to, not a way of typing it.
                    if stem(word) == theirs { return chain.words.count > 1 || length(word) > 2 }
                    guard owning.contains(word), stem(word + "s") == theirs else { return false }
                    possessive = true
                    return true
                }
                guard named else { continue }
                if let menu = sells[chain.name], !possessive {
                    let rest = searched.indices.filter { !span.contains($0) }.map { stem(searched[$0]) }
                    guard rest.contains(where: menu.contains) else { return nil }
                }
                return Found(span: span, place: stem(seated.contains(chain.name) ? "restaurant" : "fast"))
            }
        }
        return nil
    }
}
