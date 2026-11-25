import Foundation
import SystemCore
import Testing

@testable import FoodDatabase

@Suite("Search completions")
struct CompletionTests {
    func food(_ name: String, brand: String? = nil) -> FoodMatch {
        FoodMatch(
            food: Food(
                id: name, name: name, brand: brand, basis: .serving, nutrients: Nutrients(kcal: 1, protein: 0, carbs: 0, fat: 0), source: .custom),
            score: 1, personal: false)
    }

    func mine(_ name: String) -> FoodMatch {
        var match = food(name)
        match.personal = true
        return match
    }

    /// A packaged food, scanned as much as `popularity` says.
    func label(_ name: String, brand: String, popularity: Double = 0, away: Bool = false) -> FoodMatch {
        FoodMatch(
            food: Food(
                id: "\(name)|\(brand)", name: name, brand: brand, basis: .g, nutrients: Nutrients(kcal: 1, protein: 0, carbs: 0, fat: 0),
                source: .off, popularity: popularity),
            score: 1, personal: false, away: away)
    }

    @Test func aWordIsFinishedAndTakenOneWordOn() {
        let found = ["Chicken breast", "Chicken breast strips", "Chicken soup"].map { food($0) }
        let phrases = FoodCompletions.suggest("chick", from: found)
        #expect(phrases.first == "chicken")
        #expect(phrases.contains("chicken breast"))
        #expect(phrases.contains("chicken soup"))
    }

    @Test func whatsAlreadyTypedIsNotOffered() {
        #expect(!FoodCompletions.suggest("chicken", from: [food("Chicken"), food("Chicken soup")]).contains("chicken"))
        let phrases = FoodCompletions.suggest("banana", from: [food("Bananas")])
        #expect(!phrases.contains("banana") && !phrases.contains("bananas"))
        // Nor the same name written as one word: "hotdog" is a hot dog already.
        #expect(!FoodCompletions.suggest("hotdog", from: []).contains("hot dog"))
    }

    @Test func aWordCanMatchPartWayThroughAName() {
        #expect(FoodCompletions.suggest("yog", from: [food("Greek yogurt")]).contains("greek yogurt"))
    }

    @Test func aBrandTypedStaysInThePhrase() {
        #expect(FoodCompletions.suggest("fage yog", from: [food("Greek yogurt", brand: "Fage")]).contains("fage greek yogurt"))
    }

    @Test func theSameFoodSaidTwoWaysIsOnePhrase() {
        let phrases = FoodCompletions.suggest("ban", from: [food("Banana"), food("Bananas")])
        #expect(phrases.filter { $0 == "banana" || $0 == "bananas" }.count == 1)
        // Nor a brand with and without its apostrophe.
        let chains = FoodCompletions.suggest("mcd", from: [food("McDonald's"), food("McDonalds"), food("Mcdonald’s")])
        #expect(chains.filter { $0.hasPrefix("mcdonald") }.count == 1)
    }

    @Test func thePersonsOwnFoodsComeBeforeWhatsCommon() {
        let found = [mine("Chicken thigh")] + ["Chicken soup", "Chicken soup broth", "Chicken soup cream"].map { food($0) }
        let phrases = FoodCompletions.suggest("chicken", from: found)
        #expect(phrases.first == "chicken thigh")
    }

    @Test func phrasesDontStopOnAConnector() {
        // A food with few everyday phrases of its own, so the row's is among those offered.
        let phrases = FoodCompletions.suggest("quinoa", from: [food("Quinoa with beans and peppers")])
        #expect(phrases.contains("quinoa with beans"))
        #expect(!phrases.contains("quinoa with"))
    }

    @Test func bracketsAndCommasStayOut() {
        #expect(FoodCompletions.phraseWords("Oats, rolled (dry)") == ["oats", "rolled"])
    }

    @Test func aLabelNamesThePhrase() {
        let found = [food("Chicken, broilers or fryers, breast")]
        let phrases = FoodCompletions.suggest("chick", from: found) { _ in "Chicken breast" }
        #expect(phrases.contains("chicken breast"))
    }

    @Test func accentsAndCapitalsDontMatter() {
        #expect(FoodCompletions.suggest("CREME", from: [food("Crème fraîche")]).contains("crème fraîche"))
    }

    @Test func oneLetterIsTooSoon() {
        #expect(FoodCompletions.suggest("c", from: [food("Chicken")]).isEmpty)
    }

    @Test func theLimitHolds() {
        let found = (0..<30).map { food("Chicken \(["soup", "pie", "salad", "wrap", "curry", "stew", "tikka"][$0 % 7]) \($0)") }
        #expect(FoodCompletions.suggest("chick", from: found, limit: 5).count == 5)
    }

    @Test func everydayFoodsComeBeforeWhatTheRowsHappenToHold() {
        // Sixty rows for "co" are mostly cookies and corn; coffee is what's logged most.
        let rows = ["Cookies, chocolate chip", "Cookies, sugar", "Corn, sweet", "Cocoa mix"].map { food($0) }
        #expect(FoodCompletions.suggest("co", from: rows).first == "coffee")
        let green = FoodCompletions.suggest("gre", from: ["Green plantains", "Dandelion greens"].map { food($0) })
        #expect(Array(green.prefix(2)) == ["greek yogurt", "green beans"])
        // A later word finds one too, after the foods that start as typed.
        let yogurts = FoodCompletions.suggest("yog", from: [])
        #expect(yogurts.first == "yogurt" && yogurts.contains("greek yogurt"))
        // And the next word narrows them: side by side, in the order typed.
        #expect(FoodCompletions.suggest("protein b", from: [label("Protein+ Penne", brand: "Barilla", popularity: 3)]).first == "protein bar")
        #expect(FoodCompletions.suggest("chicken b", from: []).first == "chicken breast")
    }

    @Test func theWaysFoodsAreSaidAreOffered() {
        // What a way of cooking or keeping a food most often goes on to, the likeliest first.
        #expect(Array(FoodCompletions.suggest("grilled s", from: []).prefix(3)) == ["grilled salmon", "grilled shrimp", "grilled steak"])
        #expect(FoodCompletions.suggest("raw", from: []).first == "raw almonds")
        #expect(FoodCompletions.suggest("fat f", from: []).first == "fat free milk")
        #expect(FoodCompletions.suggest("uns", from: []).first == "unsalted butter")
        // After the foods themselves: "gr" is still Greek yogurt, "ste" steak.
        #expect(FoodCompletions.suggest("gr", from: []).first == "greek yogurt")
        #expect(FoodCompletions.suggest("ste", from: []).first == "steak")
        // A food typed out goes on to the ways it comes, each said once: "fried eggs" is the list's "fried egg".
        let salmon = FoodCompletions.suggest("salmon", from: [])
        #expect(salmon.contains("grilled salmon") && salmon.contains("smoked salmon"))
        let eggs = FoodCompletions.suggest("fried e", from: [])
        #expect(eggs.first == "fried egg" && !eggs.contains("fried eggs"))
        // Only by words typed in its order: "chicken b" isn't baked chicken.
        #expect(!FoodCompletions.suggest("chicken b", from: []).contains("baked chicken"))
        // And a few of one kind leave room for whatever else is being typed.
        let whole = FoodCompletions.suggest("who", from: [], limit: 5)
        #expect(whole.first == "whole milk" && whole.filter { $0.hasPrefix("whole wheat") } == ["whole wheat bread", "whole wheat pasta"])
    }

    @Test func theBrandsPeopleScanAreOffered() {
        #expect(FoodCompletions.suggest("starb", from: []).contains("starbucks"))
        #expect(FoodCompletions.suggest("chob", from: []).first == "chobani")
        #expect(FoodCompletions.suggest("trader j", from: []).contains("trader joe's"))
        // After the foods: "ch" is cheese and chicken before Chobani.
        #expect(!FoodCompletions.suggest("ch", from: [], limit: 5).contains("chobani"))
    }

    @Test func aNameTypedAsOneWordIsOnItsWayToTheTwo() {
        #expect(FoodCompletions.suggest("hotd", from: []).contains("hot dog"))
        #expect(FoodCompletions.suggest("redb", from: []).contains("red bull"))
        #expect(FoodCompletions.suggest("peanutb", from: []).first == "peanut butter")
    }

    @Test func oneLabelsWordingIsNotASearch() {
        // A product nobody looks for by name, a typo on a label, a food sold abroad.
        #expect(FoodCompletions.suggest("hot d", from: [label("Hot Dogs Nature", brand: "Auchan")]) == ["hot dog"])
        #expect(!FoodCompletions.suggest("greek y", from: [label("Greek Yougert", brand: "Dairy")]).contains("greek yougert"))
        #expect(!FoodCompletions.suggest("ban", from: [label("Bananes", brand: "Bio", popularity: 4, away: true)]).contains("bananes"))
        // One people scan is.
        #expect(FoodCompletions.suggest("oreo", from: [label("Oreo Thins", brand: "Nabisco", popularity: 3)]).contains("oreo thins"))
        // Nor part of a name that ends on no food: "greek style" only ever goes on to yogurt.
        let styled = ["Greek Style Yogurt", "Greek Style Yoghurt", "Greek Style Plain Yogurt"].map { label($0, brand: "Dairy", popularity: 3) }
        #expect(!FoodCompletions.suggest("greek", from: styled).contains("greek style"))
        #expect(!FoodCompletions.suggest("app", from: [label("Apple Apple", brand: "Juicy", popularity: 3)]).contains("apple apple"))
    }

    @Test func aBrandGoesOnToTheFoodsItMakes() {
        let yogurts = ["Non-Fat Greek Yogurt, Vanilla", "Whole Milk Greek Yogurt Plain", "Less Sugar Greek Yogurt Peach"].map {
            label($0, brand: "Chobani")
        }
        #expect(FoodCompletions.suggest("chobani", from: yogurts).contains("chobani greek yogurt"))
        #expect(FoodCompletions.suggest("chobani g", from: yogurts) == ["chobani greek yogurt"])
        // Only once the brand is what's typed first.
        #expect(!FoodCompletions.suggest("greek", from: yogurts).contains("chobani greek yogurt"))
    }

    @Test func aChainsItemIsReadFromTheCatalogsName() {
        let muffin = FoodMatch(
            food: Food(
                id: "usda:1", name: "McDONALD'S, Egg McMUFFIN", brand: nil, basis: .g, nutrients: Nutrients(kcal: 1, protein: 0, carbs: 0, fat: 0),
                source: .usda),
            score: 1, personal: false)
        // The app says the food by its chain; the item is in the catalog's name.
        #expect(FoodCompletions.suggest("egg mc", from: [muffin]) { _ in "McDONALD'S" } == ["egg mcmuffin"])
        let mac = FoodMatch(
            food: Food(
                id: "usda:2", name: "McDONALD'S, BIG MAC", brand: nil, basis: .g, nutrients: Nutrients(kcal: 1, protein: 0, carbs: 0, fat: 0),
                source: .usda),
            score: 1, personal: false)
        #expect(FoodCompletions.suggest("big m", from: [mac]) == ["big mac"])
    }

    @Test func aChainGoesOnToItsItems() {
        let chain = { (name: String) in
            FoodMatch(
                food: Food(
                    id: name, name: name, brand: nil, basis: .g, nutrients: Nutrients(kcal: 1, protein: 0, carbs: 0, fat: 0), source: .usda),
                score: 1, personal: false)
        }
        // The app says each by its chain alone; what the chain sells is in the catalog's name.
        let said = { (food: Food) in String(food.name.prefix { $0 != "," }) }
        let items = ["KFC, biscuit", "KFC, Coleslaw", "KFC, Popcorn Chicken"].map(chain)
        let typed = FoodCompletions.suggest("kfc", from: items, label: said)
        #expect(typed.contains("kfc biscuit") && typed.contains("kfc coleslaw") && !typed.contains("kfc"))
        // The chain alone while it's still being typed, then its items.
        #expect(FoodCompletions.suggest("kf", from: items, label: said).first == "kfc")
        // A chain's own word for an item is one to search by, though the name starts otherwise.
        let nuggets = [chain("McDONALD'S, Chicken McNUGGETS")]
        #expect(FoodCompletions.suggest("mcnug", from: nuggets) { _ in "McDONALD'S" } == ["chicken mcnuggets"])
        // Not a few letters of an everyday word found later in an item's name.
        #expect(FoodCompletions.suggest("chi", from: nuggets) { _ in "McDONALD'S" }.contains("chicken mcnuggets") == false)
    }

    @Test func aNameTypedApartOrInsideAProductsIsOffered() {
        // Typed apart, a name written as one word.
        let sauce = [label("Chick-fil-A Sauce", brand: "Chick-fil-A", popularity: 3), label("Chick-fil-A Polynesian Sauce", brand: "Chick-fil-A")]
        #expect(FoodCompletions.suggest("chick fi", from: sauce).first == "chick-fil-a")
        let cereal = [label("Cap'n Crunch", brand: "Quaker", popularity: 3), label("Cap'n Crunch Berries", brand: "Quaker")]
        #expect(FoodCompletions.suggest("cap n", from: cereal).first == "cap'n crunch")
        // The brand a product's name starts with is a whole thing to search for.
        let crackers = [label("Wheat Thins Original", brand: "Wheat Thins"), label("Wheat Thins Sundried Tomato", brand: "Wheat Thins")]
        #expect(FoodCompletions.suggest("wheat t", from: crackers).contains("wheat thins"))
        // The word the search took a typo for is offered with what reads as typed among the rest.
        let begun = [food("Chou, raw"), label("Hot Sauce", brand: "Cholula"), label("Salsa Verde", brand: "Cholula")]
        #expect(Array(FoodCompletions.suggest("cholu", from: begun).prefix(2)) == ["chou", "cholula"])
    }

    @Test func whatIsTypedBeforeTheFoodStays() {
        // An amount: the food after it is completed, and few are offered.
        #expect(FoodCompletions.suggest("2 eg", from: []).first == "2 eggs" && FoodCompletions.suggest("2 eg", from: []).count <= 3)
        #expect(FoodCompletions.suggest("cup of ri", from: []).first == "cup of rice")
        #expect(FoodCompletions.suggest("slice of pi", from: []).first == "slice of pizza")
        #expect(FoodCompletions.suggest("jar of pea", from: []).first == "jar of peanut butter")
        #expect(FoodCompletions.suggest("200g chi", from: []).first == "200g chicken")
        // A number as a word, where nothing typed so far is a name; a brand that starts so is still offered.
        #expect(FoodCompletions.suggest("two eg", from: []).first == "two eggs")
        let yogurt = [label("Two Good Vanilla Yogurt", brand: "Two Good", popularity: 3), label("Two Good Strawberry Yogurt", brand: "Two Good")]
        #expect(FoodCompletions.suggest("two g", from: yogurt).first?.hasPrefix("two good") == true)
        // A food and what joins the next to it.
        #expect(FoodCompletions.suggest("eggs on to", from: []).first == "eggs on toast")
        #expect(FoodCompletions.suggest("burger and fr", from: []).first == "burger and french fries")
        // After "with", what most often comes with a food leads.
        #expect(FoodCompletions.suggest("toast with bu", from: []).first == "toast with butter")
        #expect(FoodCompletions.suggest("coffee with cr", from: []).first == "coffee with cream")
        #expect(FoodCompletions.suggest("coffee with m", from: []) == ["coffee with milk"])
        // A name with "and" in it goes on as the name.
        #expect(FoodCompletions.suggest("chicken and r", from: []).first == "chicken and rice")
        #expect(FoodCompletions.suggest("mac and ch", from: []).first == "mac and cheese")
        #expect(FoodCompletions.suggest("peanut butter and j", from: []).first == "peanut butter and jelly")
        // One letter after the amount is too few, as it is alone.
        #expect(FoodCompletions.suggest("2 e", from: []).isEmpty && FoodCompletions.suggest("cup of r", from: []).isEmpty)
    }

    @Test func whatAFoodIsLeftWithoutAndAChainsPlateGoOn() {
        let first = { (typed: String) in FoodCompletions.suggest(typed, from: []).first }
        // After "no" and "without", what that kind of food usually has, kept after what's typed.
        #expect(first("burger no b") == "burger no bun" && first("salad no d") == "salad no dressing")
        #expect(first("coffee no s") == "coffee no sugar" && first("toast no b") == "toast no butter")
        #expect(first("chicken breast no s") == "chicken breast no skin" && first("latte no f") == "latte no foam")
        // Before a letter of it is typed, the likeliest three.
        #expect(FoodCompletions.suggest("coffee without", from: []) == ["coffee without sugar", "coffee without milk", "coffee without cream"])
        #expect(Array(FoodCompletions.suggest("burger no", from: []).prefix(2)) == ["burger no bun", "burger no cheese"])
        // And nothing that only starts so: no steak for "peanut butter no st".
        #expect(!FoodCompletions.suggest("peanut butter no st", from: []).contains { $0.hasPrefix("peanut butter no") })
        // With, by the kind of food too: a steak comes with rice and goes without sauce.
        #expect(first("burger with b") == "burger with bacon" && first("pancakes with s") == "pancakes with syrup")
        #expect(FoodCompletions.suggest("coffee with cr", from: []) == ["coffee with cream", "coffee with creamer"])
        #expect(first("steak with") == "steak with rice" && first("steak no") == "steak no skin")
        // A chain's plate goes on to what else the chain is known for, and the "five" of
        // Five Guys counts nothing.
        #expect(first("five guys burger and") == "five guys burger and french fries")
        #expect(first("five guys burger and f") == "five guys burger and french fries")
        #expect(first("mcdonalds big mac and fr") == "mcdonalds big mac and french fries")
        #expect(!FoodCompletions.suggest("five guys burger and", from: []).contains { $0.hasPrefix("five hamburger") })
        // A way of two words goes on by a letter: "sugar free j", "gluten free b".
        #expect(FoodCompletions.suggest("sugar free j", from: []).first == "sugar free jello")
        #expect(FoodCompletions.suggest("gluten free b", from: []).first == "gluten free bread")
        #expect(first("decaf t") == "decaf tea" && first("low sodium s") == "low sodium soy sauce")
        // One that starts with a food's own name waits for its second word.
        #expect(FoodCompletions.suggest("sugar", from: []).allSatisfy { !$0.hasPrefix("sugar free") })
        #expect(first("sugar f") == "sugar free jello")
        // A phrase doesn't end on a title: Diet Dr Pepper isn't cut at "diet dr".
        let pepper = [label("Diet Dr Pepper", brand: "Dr Pepper", popularity: 3), label("Diet Dr Pepper Cherry", brand: "Dr Pepper")]
        let diet = FoodCompletions.suggest("diet d", from: pepper)
        #expect(diet.contains("diet dr pepper") && !diet.contains("diet dr"))
    }

    @Test func theCatalogsResultsComplete() {
        let found = Catalogs.usda.search("chick", limit: 60)
        #expect(FoodCompletions.suggest("chick", from: found).contains("chicken"))
    }

    @Test func aTypoTheSearchCorrectedStillOffersFoods() {
        let found = Catalogs.usda.search("chiken", limit: 60)
        #expect(!found.isEmpty)
        // The word it was taken for, then on from there.
        let phrases = FoodCompletions.suggest("chiken", from: found)
        #expect(phrases.first == "chicken" && phrases.contains("chicken breast"))
    }
}
