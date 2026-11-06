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

    @Test func aWordIsFinishedAndTakenOneWordOn() {
        let found = ["Chicken breast", "Chicken breast strips", "Chicken soup"].map { food($0) }
        let phrases = FoodCompletions.suggest("chick", from: found)
        #expect(phrases.first == "chicken")
        #expect(phrases.contains("chicken breast"))
        #expect(phrases.contains("chicken soup"))
    }

    @Test func whatsAlreadyTypedIsNotOffered() {
        #expect(!FoodCompletions.suggest("chicken", from: [food("Chicken"), food("Chicken soup")]).contains("chicken"))
        #expect(FoodCompletions.suggest("banana", from: [food("Bananas")]).isEmpty)
    }

    @Test func aWordCanMatchPartWayThroughAName() {
        #expect(FoodCompletions.suggest("yog", from: [food("Greek yogurt")]).contains("greek yogurt"))
    }

    @Test func aBrandTypedStaysInThePhrase() {
        #expect(FoodCompletions.suggest("fage yog", from: [food("Greek yogurt", brand: "Fage")]).contains("fage greek yogurt"))
    }

    @Test func theSameFoodSaidTwoWaysIsOnePhrase() {
        let phrases = FoodCompletions.suggest("ban", from: [food("Banana"), food("Bananas")])
        #expect(phrases.count == 1)
    }

    @Test func thePersonsOwnFoodsComeBeforeWhatsCommon() {
        let found = [mine("Chicken thigh")] + ["Chicken soup", "Chicken soup broth", "Chicken soup cream"].map { food($0) }
        let phrases = FoodCompletions.suggest("chicken", from: found)
        #expect(phrases.first == "chicken thigh")
    }

    @Test func phrasesDontStopOnAConnector() {
        let phrases = FoodCompletions.suggest("rice", from: [food("Rice with beans and peppers")])
        #expect(phrases.first == "rice with beans")
        #expect(!phrases.contains("rice with"))
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

    @Test func theCatalogsResultsComplete() {
        let found = Catalogs.usda.search("chick", limit: 60)
        #expect(FoodCompletions.suggest("chick", from: found).contains("chicken"))
    }

    @Test func aTypoTheSearchCorrectedStillOffersFoods() {
        let found = Catalogs.usda.search("chiken", limit: 60)
        #expect(!found.isEmpty)
        #expect(FoodCompletions.suggest("chiken", from: found).contains { $0.contains("chicken") })
    }
}
