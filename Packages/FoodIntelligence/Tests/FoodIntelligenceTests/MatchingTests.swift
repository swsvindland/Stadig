import FoodDatabase
import Foundation
import FoundationModels
import Synchronization
import SystemCore
import Testing

@testable import FoodIntelligence

@Suite("Matching")
struct MatchingTests {
    let romaine = food("Egg, whole, cooked, scrambled", kcal: 149)
    let iceberg = food("Egg, whole, cooked, fried", kcal: 196)
    let leaf = food("Egg, whole, raw, fresh", kcal: 143)
    let salad = food("Salad, egg", kcal: 300)

    @Test func aClearWinnerIsSureAndNeedsNoSecondOpinion() {
        let found = Matching.rank([match(romaine, 4), match(iceberg, 2.5), match(salad, 1)], branded: false)
        #expect(found.sure)
        #expect(found.tied == 1)
        #expect(Matching.asked([found]).isEmpty)
    }

    @Test func nearTiesWithinAPointAreAskedAboutAtMostSix() {
        let found = Matching.rank([match(romaine, 3), match(iceberg, 2.6), match(leaf, 2.1), match(salad, 1.9)], branded: false)
        #expect(found.tied == 3)
        #expect(Matching.asked([found]) == [0])
        let many = Matching.rank((0..<10).map { match(food("Lettuce \($0)"), 3 - Double($0) * 0.01) }, branded: false)
        #expect(many.tied == 6)
        #expect(many.matches.count == 8)
    }

    @Test func tiesThatDontChangeTheNutritionArentAskedAbout() {
        let butter = Matching.rank(
            [
                match(food("Butter, without salt", kcal: 717), 3.5), match(food("Butter, salted", kcal: 717), 3.25),
                match(food("Butter, whipped", kcal: 718), 3.2),
            ], branded: false)
        #expect(butter.tied == 3)
        #expect(Matching.asked([butter]).isEmpty)
        let coffee = [food("Coffee, brewed", kcal: 1), food("Coffee, decaffeinated", kcal: 0)]
        #expect(Matching.alike(coffee.map { match($0, 3) }))
        #expect(!Matching.alike([match(food("Rice, raw", kcal: 365), 3), match(food("Rice, cooked", kcal: 130), 3)]))
        #expect(!Matching.alike([match(food("Milk", basis: .ml), 3), match(food("Milk", basis: .g), 3)]))
    }

    @Test func aFoodWhoseNumbersCantBeRightIsNeverSure() {
        // A powder's values on a bottled flat white, and kilojoules entered as calories.
        let powder = Food(
            id: "off:07613036675680", name: "Flat White", brand: "Nestlé", basis: .ml,
            nutrients: Nutrients(kcal: 452, protein: 21.8, carbs: 43.6, fat: 19.2), source: .off)
        let poured = Food(
            id: "off:00000000000001", name: "Flat White", brand: "Costa", basis: .ml,
            nutrients: Nutrients(kcal: 37, protein: 2, carbs: 4, fat: 1.2), source: .off)
        #expect(!powder.isPlausible && poured.isPlausible)
        #expect(!Matching.fits("flat white", powder))
        let found = Matching.rank([match(powder, 3), match(poured, 2.5)], branded: true, seen: "flat white")
        #expect(found.matches.first?.food == poured, "a plausible match close behind is promoted")
        let alone = Matching.rank([match(powder, 3)], branded: true, seen: "flat white")
        #expect(alone.matches.first?.food == powder && !alone.sure, "offered, not logged without a look")
        let kilojoules = Food(
            id: "off:00000000000002", name: "Cream cheese", brand: "St Môret", basis: .g,
            nutrients: Nutrients(kcal: 765, protein: 10, carbs: 5, fat: 8), source: .off)
        #expect(!Matching.rank([match(kilojoules, 4)], branded: true).sure)
    }

    @Test func aMatchThatDoesntFitWhatWasSeenIsNeverSure() {
        // The catalog's best for a drink was rice; a drink's match must be a drink.
        let rice = food("Rice, white, long-grain, regular, enriched, cooked", kcal: 130)
        let mushrooms = food("Mushrooms, white, raw", kcal: 22)
        let latte = food("Caffè Latte", basis: .ml, kcal: 60, source: .off)
        let drink = Matching.rank([match(rice, 2.5), match(mushrooms, 2), match(latte, 1.2)], branded: false, seen: "latte")
        #expect(drink.matches.first?.food == latte)
        #expect(!drink.sure)
        #expect(!Matching.rank([match(rice, 3)], branded: false, seen: "flat white").sure)
        // A powder is not the drink.
        let powder = food("Cappuccino", kcal: 410, source: .off)
        #expect(!Matching.fits("cappuccino", powder))
        #expect(Matching.fits("cappuccino", food("Cappuccino", basis: .ml, kcal: 45, source: .off)))
        // Every word counts but how it was cooked: "Spices, mace" is no Big Mac.
        let mac = food("McDONALD'S, BIG MAC", kcal: 257)
        let mace = Matching.rank([match(food("Spices, mace, ground", kcal: 475), 2.25), match(mac, 0.75)], branded: false, seen: "Big Mac")
        #expect(mace.matches.first?.food == mac)
        #expect(Matching.covers("grilled chicken breast", food("Chicken, broilers or fryers, breast, meat only, cooked, roasted")))
        #expect(!Matching.covers("black beans", food("Beans, snap, green, raw")))
        #expect(Matching.fits("orange juice", food("Orange juice, raw")))
        #expect(!Matching.fits("oatmeal", food("Beverages, oat milk", kcal: 45)))
        #expect(Drinks.isDrink("chocolate milk") && !Drinks.isDrink("milk chocolate"))
        // What the seen food only describes is another food.
        #expect(!Matching.fits("Caesar salad", food("Salad dressing, caesar dressing, regular", kcal: 542)))
        #expect(!Matching.fits("chicken", food("Chicken salad spread", kcal: 200)))
        #expect(Matching.fits("Caesar salad", food("Chicken caesar salad", source: .off)))
        #expect(Matching.fits("salmon", food("Fish, salmon, Atlantic, farmed, cooked")))
        #expect(Matching.fits("toast", food("Bread, wheat, toasted")))
        #expect(Matching.fits("peanut butter", food("Peanut butter, smooth style")))
    }

    @Test func theCatalogsReadingOfANameCounts() {
        // The catalog matched "toast with butter" to toast and says the match names the food; the
        // words alone would want butter in it.
        let toast = food("Bread, whole-wheat, commercially prepared, toasted")
        #expect(!Matching.covers("Whole wheat toast with butter", toast))
        let read = FoodMatch(food: toast, score: 3.35, personal: false, named: true)
        #expect(Matching.rank([read], branded: false, seen: "Whole wheat toast with butter").sure)
        // By another name the catalog files the food under, which only it knows.
        let frankfurter = food("Frankfurter, beef")
        #expect(Matching.rank([FoodMatch(food: frankfurter, score: 3.75, personal: false, named: true)], branded: false, seen: "hot dog").sure)
        #expect(!Matching.rank([match(frankfurter, 3.75)], branded: false, seen: "hot dog").sure)
        // It is still judged as the kind of thing the food is, not what comes with it: cereal with
        // milk is no drink, and rice isn't a match for a latte whatever a catalog says.
        #expect(Matching.rank([match(food("Cereals ready-to-eat, granola"), 3.8)], branded: false, seen: "Cereal with milk").sure)
        let rice = FoodMatch(food: food("Rice, white, cooked"), score: 3, personal: false, named: true)
        #expect(!Matching.rank([rice], branded: false, seen: "Latte (whole milk)").sure)
        // A brand's product keeps its whole name.
        #expect(!Matching.rank([match(toast, 3.35)], branded: true, seen: "Toast with butter").sure)
        // What kind of food a catalog's name says it is: not a note in brackets, what it comes in
        // or may also be, or how it's sold.
        #expect(Matching.fits("chickpeas", food("Chickpeas (garbanzo beans, bengal gram), mature seeds, cooked, boiled, without salt")))
        #expect(Matching.fits("pulled pork", food("Pulled pork in barbecue sauce")))
        #expect(Matching.fits("ham sandwich", food("Ham sandwich or sub, restaurant")))
        #expect(Matching.fits("cereal", food("Cereals ready-to-eat, granola")))
        #expect(Matching.fits("jam", food("Jams and preserves")))
        #expect(!Matching.fits("beans", food("Beans and rice, from fast food / restaurant")))
        // Spirits are drinks, and over 200 kcal per 100 g as poured.
        #expect(Matching.fits("vodka", food("Alcoholic beverage, distilled, vodka, 80 proof", kcal: 231)))
        #expect(Drinks.isDrink(food("Soymilk, original and vanilla, unfortified")))
        // A cocktail is a drink and baking soda isn't; a powder of a drink is a powder, which
        // USDA files under "Beverages", and no match for the drink.
        #expect(Matching.fits("pina colada", food("Alcoholic beverage, pina colada, prepared-from-recipe", kcal: 174)))
        #expect(Matching.fits("baking soda", food("Leavening agents, baking soda", kcal: 0)))
        #expect(Matching.fits("protein powder", food("Beverages, Whey protein powder isolate", kcal: 359)))
        #expect(!Matching.fits("hot chocolate", food("Beverages, Cocoa mix, powder", kcal: 398)))
        // How a food is made says no other food, and ginger root is ginger.
        #expect(Matching.fits("soy sauce", food("Soy sauce made from soy and wheat (shoyu)")))
        #expect(Matching.fits("ginger", food("Ginger root, raw")))
        #expect(!Matching.fits("celery", food("Celery root, raw")))
        #expect(Matching.fits("taco seasoning", food("Seasoning mix, dry, taco, original")))
        #expect(!Matching.fits("pancakes", food("Pancake mix, dry")))
        #expect(Matching.fits("buttermilk", food("Milk, buttermilk, fluid, whole", kcal: 62)))
        // USDA's spirits and stronger cocktails are over 200 kcal per 100 g as poured, where a
        // label's drink that dense is a powder; its own names say when one is.
        #expect(Matching.fits("vodka", food("Vodka", kcal: 231)))
        #expect(Matching.fits("martini", food("Martini", kcal: 222)))
        #expect(!Matching.fits("cappuccino", food("Cappuccino", brand: "Nescafe", kcal: 429, source: .off)))
        #expect(!Matching.fits("hot chocolate", food("Beverages, Cocoa mix, powder", kcal: 398)))
        // A drink by the name it's ordered by.
        #expect(Drinks.isDrink("cold brew") && Drinks.isDrink("boba") && Drinks.isDrink("cafe con leche"))
        #expect(Matching.fits("frozen coffee", food("Frozen coffee drink", kcal: 70)))
        // A second name after "or" is as long as the first, and what follows is said of both:
        // a taco or tostada salad is a salad, a chicken or turkey salad no chicken, and a ham
        // sandwich or sub still a ham sandwich.
        #expect(Matching.kinds(of: food("Taco or tostada salad with meat")) == [["taco", "salad"], ["tostada", "salad"]])
        #expect(Matching.qualifies("tostada", food("Taco or tostada salad with meat")))
        #expect(Matching.qualifies("chicken", food("Chicken or turkey salad")))
        #expect(!Matching.qualifies("turkey salad", food("Chicken or turkey salad")))
        #expect(!Matching.qualifies("ham sandwich", food("Ham sandwich or sub, restaurant")))
        // Two words for one food: a ramen bowl is ramen, a bao bun bao, mole sauce mole. A
        // burrito bowl is no burrito.
        #expect(!Matching.qualifies("ramen", food("Ramen bowl")) && !Matching.qualifies("bao", food("Bao bun")))
        #expect(!Matching.qualifies("mole", food("Mole sauce")) && Matching.qualifies("burrito", food("Burrito bowl")))
        #expect(!Matching.qualifies("danish", food("Danish pastry, plain or spice")))
        #expect(Matching.fits("mac and cheese", FoodMatch(food: food("Macaroni or noodles with cheese"), score: 4, personal: false, named: true)))
        // What the catalog also calls by exactly the name seen is that, though its own name
        // says more: a grilled cheese sandwich is a grilled cheese, where a tuna salad
        // sandwich isn't tuna salad.
        let grilled = food("Grilled cheese sandwich")
        #expect(!Matching.fits("grilled cheese", FoodMatch(food: grilled, score: 4, personal: false, named: true)))
        #expect(Matching.fits("grilled cheese", FoodMatch(food: grilled, score: 4, personal: false, named: true, called: true)))
        // A bowl named last is a dish, as the catalog reads it.
        #expect(FoodText.nameWords("Poke bowl") == ["poke", "bowl"])
        #expect(FoodText.nameWords("Bowl of rice") == ["rice"])
    }

    @Test func aDishContainingTheFoodIsNoNearTie() {
        let raw = food("Blueberries, raw", kcal: 57)
        let wild = food("Blueberries, wild, raw", kcal: 57)
        let muffin = food("Muffins, blueberry, commercially prepared", kcal: 377)
        let found = Matching.rank([match(raw, 3.5), match(muffin, 3.4), match(wild, 3.2)], branded: false, seen: "blueberries")
        #expect(found.matches.map(\.food) == [raw, wild, muffin])
        #expect(found.tied == 2)
        #expect(Matching.asked([found]).isEmpty, "raw and wild blueberries are alike")
    }

    @Test func aWeakBestMatchIsOfferedButNotSure() {
        let found = Matching.rank([match(food("Fish, salmon, raw"), 1.2), match(food("Sushi"), 1.0)], branded: false)
        #expect(!found.sure)
        #expect(Matching.asked([found]).isEmpty, "a weak match isn't worth a second request")
        #expect(!Matching.rank([], branded: false).sure)
    }

    @Test func picksSettleNearTiesAndBadAnswersAreIgnored() {
        let found = [
            Matching.rank([match(romaine, 3), match(iceberg, 2.8), match(leaf, 2.7)], branded: false),
            Matching.rank([match(salad, 5)], branded: false),
            Matching.rank([], branded: false),
        ]
        let asked = Matching.asked(found)
        #expect(asked == [0])
        let prompt = Matching.pickPrompt(seen: [seen("lettuce"), seen("salad"), seen("x")], found: found, asked: asked)
        #expect(prompt.contains("Food 1: lettuce\n  1. Egg, whole, cooked, scrambled\n  2. Egg, whole, cooked, fried\n  3. Egg, whole, raw, fresh"))
        #expect(!prompt.contains("Food 2"))
        #expect(Matching.choices([Pick(food: 1, entry: 3)], found: found, asked: asked) == [2, 0, nil])
        for bad in [[Pick(food: 1, entry: 9)], [Pick(food: 2, entry: 1)], [Pick(food: 0, entry: 1)], []] {
            #expect(Matching.choices(bad, found: found, asked: asked) == [0, 0, nil])
        }
    }

    @Test func aBrandedGuessKeepsAPlainFoodOneTapAway() {
        let pizzas = (0..<8).map { food("DOMINO'S 14\" Pizza \($0)", brand: nil) }
        let plain = food("Pizza, cheese topping, regular crust")
        let found = Matching.rank(pizzas.enumerated().map { match($1, 6 - Double($0) * 0.1) } + [match(plain, 1)], branded: true)
        #expect(found.matches.prefix(8).contains { $0.food == plain })
        let others = Matching.alternatives(found.matches, chosen: 0, branded: true)
        #expect(others.count == 5)
        #expect(others.contains { $0.food == plain })
        #expect(!others.contains { $0.food == pizzas[0] })
    }

    @Test func brandedFoodsAreRecognized() {
        #expect(Matching.isBranded(food("McDONALD'S, french fries")))
        #expect(Matching.isBranded(food("T.G.I. FRIDAY'S, french fries")))
        #expect(Matching.isBranded(food("DOMINO'S 14\" Pepperoni Pizza, Classic Hand-Tossed Crust")))
        #expect(Matching.isBranded(food("Ketchup", source: .off)))
        #expect(Matching.isBranded(food("Cheerios", brand: "General Mills")))
        #expect(!Matching.isBranded(food("Fast foods, potato, french fried in vegetable oil")))
        #expect(!Matching.isBranded(food("Tomatoes, red, ripe, raw, year round average")))
    }
}

@Suite("Engines")
struct EngineTests {
    func state(device: Bool = true, vision: Bool = true, cloud: Bool = false) -> MealAIAvailability {
        MealAIAvailability(onDevice: device, onDeviceVision: device && vision, privateCloud: cloud, reason: nil)
    }

    @Test func onDeviceFirstThenTheCloudWhenAllowed() {
        #expect(MealEngines.engine(photo: true, in: state()) == .onDevice)
        #expect(MealEngines.engine(photo: false, in: state()) == .onDevice)
        // No vision on the device: photos go to the cloud, descriptions stay.
        #expect(MealEngines.engine(photo: true, in: state(vision: false, cloud: true)) == .privateCloud)
        #expect(MealEngines.engine(photo: false, in: state(vision: false, cloud: true)) == .onDevice)
        #expect(MealEngines.engine(photo: true, in: state(vision: false)) == nil)
        #expect(MealEngines.engine(photo: false, in: state(device: false, cloud: true)) == .privateCloud)
        #expect(MealEngines.engine(photo: false, in: state(device: false)) == nil)
        #expect(state(vision: false).descriptions && !state(vision: false).photos)
    }

    @Test func cloudFailuresFallBackToTheDeviceForText() {
        let both = state(vision: false, cloud: true)
        for error in [MealAIError.network, .quotaReached(nil), .unavailable("down"), .busy, .failed("?")] {
            #expect(MealEngines.fallback(after: error, from: .privateCloud, photo: false, hasNote: true, in: both)! == (.onDevice, false))
            // A photo's note is read on its own; a bare photo has nothing to fall back to.
            #expect(MealEngines.fallback(after: error, from: .privateCloud, photo: true, hasNote: true, in: both)! == (.onDevice, false))
            #expect(MealEngines.fallback(after: error, from: .privateCloud, photo: true, hasNote: false, in: both) == nil)
        }
        for error in [MealAIError.refused, .notFood("x"), .tooLong] {
            #expect(MealEngines.fallback(after: error, from: .privateCloud, photo: false, hasNote: true, in: both) == nil)
        }
        #expect(MealEngines.fallback(after: .network, from: .privateCloud, photo: false, hasNote: true, in: state(device: false, cloud: true)) == nil)
    }

    @Test func deviceFailuresTryTheCloudOnlyWhenAllowed() {
        let both = state(cloud: true)
        for error in [MealAIError.tooLong, .busy, .unavailable("not ready"), .failed("?")] {
            #expect(MealEngines.fallback(after: error, from: .onDevice, photo: true, hasNote: false, in: both)! == (.privateCloud, true))
        }
        #expect(MealEngines.fallback(after: .refused, from: .onDevice, photo: false, hasNote: true, in: both) == nil)
        #expect(MealEngines.fallback(after: .notFood("x"), from: .onDevice, photo: false, hasNote: true, in: both) == nil)
        #expect(MealEngines.fallback(after: .busy, from: .onDevice, photo: false, hasNote: true, in: state()) == nil)
    }

    /// Private Cloud Compute stops an app that lacks Apple's entitlement, so without
    /// `SystemAIPrivateCloud` in the Info.plist it's never offered, even with the setting on.
    @Test @available(macOS 27.0, iOS 27.0, *)
    func theCloudNeedsTheEntitlement() {
        // A cloud that's always there, so the test doesn't depend on this Mac's: without the
        // entitlement it's never asked, let alone used.
        let asked = Mutex(0)
        let up = { () -> (available: Bool, vision: Bool) in
            asked.withLock { $0 += 1 }
            return (true, true)
        }
        for allowCloud in [true, false] {
            let state = MealEngines.availability(allowCloud: allowCloud, entitled: false, cloud: up)
            #expect(!state.privateCloud && !state.privateCloudVision)
            #expect(MealEngines.engine(photo: true, in: state) != .privateCloud)
            #expect(MealEngines.engine(photo: false, in: state) != .privateCloud)
        }
        #expect(asked.withLock { $0 } == 0)
        // Entitled and allowed, the same cloud is offered.
        #expect(MealEngines.availability(allowCloud: true, entitled: true, cloud: up).privateCloudVision)
        #expect(!MealEngines.availability(allowCloud: false, entitled: true, cloud: up).privateCloud)
        // The test runner declares nothing, like the apps until Apple grants the entitlement.
        #expect(!MealAIAvailability.privateCloudEntitled)
        #expect(!MealAI.availability(allowCloud: true).privateCloud)
    }

    @Test func aDeviceThatCantReadPhotosOffersTheCloudOnlyWhereItCanBeUsed() {
        let textOnly = state(vision: false)
        let describe = "Photo recognition isn't available on this device right now. Describe the meal instead."
        let allow = "This device's model can't read photos. Allow Private Cloud Compute to log meals from photos."
        // Entitled and switched off: say the switch would help.
        #expect(MealEngines.reason(textOnly, deviceReason: nil, allowCloud: false, entitled: true) == allow)
        // Not entitled: the switch is hidden, so never point to it.
        #expect(MealEngines.reason(textOnly, deviceReason: nil, allowCloud: false, entitled: false) == describe)
        #expect(MealEngines.reason(textOnly, deviceReason: nil, allowCloud: true, entitled: false) == describe)
        #expect(MealEngines.reason(textOnly, deviceReason: nil, allowCloud: true, entitled: true) == describe)
        // Everything works, or nothing does.
        #expect(MealEngines.reason(state(), deviceReason: nil, allowCloud: false, entitled: false) == nil)
        #expect(MealEngines.reason(state(device: false), deviceReason: "Turn it on", allowCloud: true, entitled: false) == "Turn it on")
    }

    @Test @available(macOS 27.0, iOS 27.0, *)
    func modelErrorsAreClassifiedForThePerson() {
        let busy = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "busy"))
        #expect(ModelErrors.classify(busy) == .busy)
        #expect(ModelErrors.classify(LanguageModelError.timeout(.init(debugDescription: "slow"))) == .busy)
        #expect(ModelErrors.classify(LanguageModelSession.Error.concurrentRequests) == .busy)
        #expect(ModelErrors.classify(LanguageModelError.guardrailViolation(.init(debugDescription: "no"))) == .refused)
        #expect(ModelErrors.classify(LanguageModelError.refusal(.init(explanation: "no", debugDescription: "no"))) == .refused)
        #expect(
            ModelErrors.classify(LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "long")))
                == .tooLong)
        guard
            case .unavailable = ModelErrors.classify(
                LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: "xx", debugDescription: "xx")))
        else {
            Issue.record("language")
            return
        }
        guard case .unavailable = ModelErrors.classify(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "x"))) else {
            Issue.record("assets")
            return
        }
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        typealias Cloud = PrivateCloudComputeLanguageModel.Error
        #expect(ModelErrors.classify(Cloud.quotaLimitReached(.init(resetDate: reset, debugDescription: "quota"))) == .quotaReached(reset))
        #expect(ModelErrors.classify(Cloud.networkFailure(.init(debugDescription: "offline"))) == .network)
        #expect(ModelErrors.classify(MealAIError.refused) == .refused)
        guard case .failed = ModelErrors.classify(CocoaError(.fileNoSuchFile)) else {
            Issue.record("other")
            return
        }
    }
}
