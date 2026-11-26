import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

struct DayCardsTests {
    let calendar = Calendar.gregorian(.newYork)
    let day = Day(year: 2027, month: 6, day: 15)

    func food(_ hour: Int, _ minute: Int = 0, kcal: Double = 300, fluid: Double? = nil) -> FoodEntry {
        let date = day.at(hour: hour, minute: minute, calendar: calendar)
        return FoodEntry(
            date: date, day: day, name: "Food", amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: 10, carbs: 1, fat: 1), fluid: fluid,
            source: .search, updatedAt: date)
    }

    func time(_ hour: Int, _ minute: Int = 0) -> Date { day.at(hour: hour, minute: minute, calendar: calendar) }

    func items(_ entries: [FoodEntry], held: [Date] = [], now: Date? = nil) -> [DayItem] {
        DayCards.items(DayHours.groups(on: day, entries: entries, calendar: calendar), held: held, now: now)
    }

    /// The day as a line: M for a meal, H for what's held, N for now, a number for open hours.
    func shape(_ items: [DayItem]) -> String {
        items.map { item in
            switch item {
            case .meal: "M"
            case .held: "H"
            case .now: "N"
            case .hours(let groups): "\(groups.count)"
            }
        }.joined(separator: " ")
    }

    @Test func anEmptyDayIsAllOpenHours() {
        #expect(shape(items([])) == "24")
    }

    @Test func mealsSitBetweenTheOpenHours() {
        #expect(shape(items([food(9), food(12), food(17)])) == "9 M 2 M 4 M 6")
    }

    @Test func aMealAcrossAnHourIsOneCardAndTakesBothHours() {
        let list = items([food(8, 50), food(9, 20)])
        #expect(shape(list) == "8 M 14")
        if case .meal(let meal) = list[1] { #expect(meal.entries.count == 2) } else { Issue.record("Not a meal") }
    }

    @Test func aHeldTimeTakesItsHour() {
        #expect(shape(items([], held: [time(9), time(12, 30), time(17)])) == "9 H 2 H 4 H 6")
    }

    @Test func todayHasItsHourEvenWithAMealInIt() {
        #expect(shape(items([food(16, 5)], now: time(16, 30))) == "16 M N 7")
    }

    @Test func foodLaterInTheHourComesAfterNow() {
        #expect(shape(items([food(16, 45)], now: time(16, 30))) == "16 N M 7")
    }

    @Test func aDayOpensOnNowThenItsFirstMealThenWhatsHeld() {
        #expect(DayCards.opening(items([food(9)], now: time(16))).map { if case .now = $0 { true } else { false } } == true)
        #expect(DayCards.opening(items([food(9)], held: [time(7)])).map { if case .meal = $0 { true } else { false } } == true)
        #expect(DayCards.opening(items([], held: [time(7)])).map { if case .held = $0 { true } else { false } } == true)
        #expect(DayCards.opening(items([])).map { if case .hours = $0 { true } else { false } } == true)
    }

    @Test func aMealsPlusJoinsTheMealOnAnotherDay() {
        let meal = Moment(entries: [food(12), food(12, 10)])
        #expect(DayCards.addTime(to: meal, now: time(20), calendar: calendar) == time(12, 11))
    }

    @Test func aMealsPlusLogsAtNowWhileItsStillThatMeal() {
        let meal = Moment(entries: [food(12)])
        #expect(DayCards.addTime(to: meal, now: time(12, 30), calendar: calendar) == time(12, 30))
    }

    @Test func aMealsPlusStaysOnItsDay() {
        let meal = Moment(entries: [food(23, 59)])
        let added = DayCards.addTime(to: meal, now: time(23, 59).addingTimeInterval(86400), calendar: calendar)
        #expect(Day(added, calendar: calendar) == day)
    }

    @Test(arguments: [
        (7, 400.0, "Breakfast"), (10, 400, "Breakfast"), (11, 400, "Lunch"), (14, 400, "Lunch"), (15, 400, "Snack"), (16, 400, "Dinner"),
        (21, 400, "Dinner"), (23, 400, "Snack"), (2, 400, "Snack"), (8, 150, "Snack"), (19, 150, "Snack"),
    ])
    func aMealIsNamedFromItsTimeAndSize(hour: Int, kcal: Double, name: String) {
        #expect(MealName.of(Moment(entries: [food(hour, kcal: kcal)]), calendar: calendar) == name)
    }

    @Test func onlyDrinksAreADrink() {
        #expect(MealName.of(Moment(entries: [food(9, kcal: 5, fluid: 250)]), calendar: calendar) == "Drink")
        #expect(MealName.of(Moment(entries: [food(9, kcal: 5, fluid: 250), food(9, 5)]), calendar: calendar) == "Breakfast")
    }
}

struct LogHoursTests {
    @Test func nothingKnownIsSevenToEight() {
        #expect(LogHours.window() == 7...20)
    }

    @Test func sleepSetsTheWindow() {
        #expect(LogHours.window(wake: 6 * 60, bed: 22 * 60 + 30) == 6...22)
        #expect(LogHours.window(wake: 6 * 60 + 45, bed: 22 * 60) == 6...21)
    }

    @Test func aBedtimeAfterMidnightRunsToTheEndOfTheDay() {
        #expect(LogHours.window(wake: 9 * 60, bed: 25 * 60) == 9...23)
    }

    @Test func thePersonsOwnHoursWinOverSleep() {
        #expect(LogHours.window(first: 8, wake: 6 * 60, bed: 22 * 60) == 8...21)
        #expect(LogHours.window(last: 19, wake: 6 * 60, bed: 22 * 60) == 6...19)
    }

    @Test func hoursSetTheWrongWayRoundAreSwapped() {
        #expect(LogHours.window(first: 20, last: 7) == 7...20)
    }

    @Test func openHoursSplitAroundTheWindow() {
        let hours = DayHours.groups(on: Day(year: 2027, month: 6, day: 15), entries: [], calendar: .gregorian(.newYork))
        let split = LogHours.split(hours, window: 7...20)
        #expect(split.earlier.map(\.hour) == Array(0...6))
        #expect(split.shown.map(\.hour) == Array(7...20))
        #expect(split.later.map(\.hour) == [21, 22, 23])
    }

    let day = Day(year: 2027, month: 6, day: 15)
    let calendar = Calendar.gregorian(.newYork)

    func open(_ range: ClosedRange<Int>) -> [HourGroup] {
        DayHours.groups(on: day, entries: [], calendar: calendar).filter { range.contains($0.hour) }
    }

    @Test func anEmptyDayOffersBreakfastLunchAndDinner() {
        #expect(LogHours.offered(open(0...23), window: 7...20).map(\.hour) == [8, 12, 18])
    }

    @Test func aRunWithoutMealtimesOffersItsFirstHours() {
        #expect(LogHours.offered(open(14...17), window: 7...20).map(\.hour) == [14, 15, 16])
    }

    @Test func aRunKeepsItsMealtimeAmongItsFirstHours() {
        #expect(LogHours.offered(open(9...14), window: 7...20).map(\.hour) == [9, 10, 12])
    }

    @Test func aShortRunOffersEveryHour() {
        #expect(LogHours.offered(open(10...11), window: 7...20).map(\.hour) == [10, 11])
    }

    @Test func todayOffersTheNextHoursAfterNow() {
        let now = day.at(hour: 9, minute: 41, calendar: calendar)
        #expect(LogHours.offered(open(10...23), window: 7...20, now: now).map(\.hour) == [10, 11, 12])
    }

    @Test func todayBeforeNowOffersTheLatestHours() {
        let now = day.at(hour: 13, minute: 5, calendar: calendar)
        #expect(LogHours.offered(open(0...12), window: 7...20, now: now).map(\.hour) == [10, 11, 12])
    }

    @Test func hoursOutsideTheWindowAreNeverOffered() {
        #expect(LogHours.offered(open(21...23), window: 7...20).isEmpty)
        #expect(LogHours.offered(open(0...7), window: 7...20).map(\.hour) == [7])
    }
}

struct FoodLabelTests {
    @Test(
        arguments: [
            // The staples a catalog files by their head: a cheese, a bread, a sauce, a dressing.
            ("Cheese, cheddar", "Cheddar cheese", nil),
            ("Cheese, cottage, lowfat, 2% milkfat", "Cottage cheese", "lowfat, 2% milkfat"),
            (
                "Cheese, pasteurized process, American, without added vitamin D", "American cheese",
                "pasteurized process, without added vitamin D"
            ),
            ("Bread, zucchini", "Zucchini bread", nil),
            ("Bread, banana, prepared from recipe, made with margarine", "Banana bread", "prepared from recipe, made with margarine"),
            ("Sauce, barbecue", "Barbecue sauce", nil),
            ("Sauce, tomato chili sauce, bottled, with salt", "Tomato chili sauce", "bottled, with salt"),
            ("Salad dressing, ranch dressing, regular", "Ranch dressing", "regular"),
            ("Salad dressing, honey mustard, regular", "Honey mustard dressing", "regular"),
            ("Milk, chocolate, lowfat, with added vitamin A and vitamin D", "Chocolate milk", "lowfat, with added vitamin A and vitamin D"),
            ("Cream, sour, cultured", "Sour cream", "cultured"),
            ("Butter, salted", "Salted butter", nil),
            ("Oil, avocado", "Avocado oil", nil),
            ("Sugars, brown", "Brown sugar", nil),
            ("Syrups, maple", "Maple syrup", nil),
            ("Seeds, chia seeds, dried", "Chia seeds", "dried"),
            ("Rolls, dinner, plain", "Dinner rolls", "plain"),
            ("Bagels, egg", "Egg bagels", nil),
            ("Topping, butterscotch or caramel", "Butterscotch or caramel topping", nil),
            ("Gnocchi, potato", "Potato gnocchi", nil),
            ("Yogurt, vanilla, low fat", "Vanilla yogurt", "low fat"),
            // A part that is the food's own name under that head.
            ("Cheese, paneer", "Paneer", nil),
            ("Cheese, fresh, queso fresco", "Queso fresco", "fresh"),
            ("Bread, cornbread, prepared from recipe, made with low fat (2%) milk", "Cornbread", "prepared from recipe, made with low fat (2%) milk"),
            ("Sauce, salsa, ready-to-serve", "Salsa", "ready-to-serve"),
            ("Salad dressing, mayonnaise, regular", "Mayonnaise", "regular"),
            ("Milk, buttermilk, fluid, whole", "Buttermilk", "fluid, whole"),
            ("Cream, fluid, half and half", "Half and half", "fluid"),
            // Not under another head, nor by how it comes or who makes it.
            ("Pancakes, buttermilk, prepared from recipe", "Pancakes", "buttermilk, prepared from recipe"),
            ("Bread, crumbs, dry, grated, plain", "Bread", "crumbs, dry, grated, plain"),
            ("Oil, PAM cooking spray, original", "Oil", "PAM cooking spray, original"),
            ("Oil, cocoa butter", "Oil", "cocoa butter"),
            ("Cream, fluid, heavy whipping", "Cream", "fluid, heavy whipping"),
            ("Milk, reduced fat, fluid, 2% milkfat", "Milk", "reduced fat, fluid, 2% milkfat"),
            // As before.
            ("Milk, whole, 3.25% milkfat, with added vitamin D", "Whole milk", "3.25% milkfat, with added vitamin D"),
            ("Oil, olive, salad or cooking", "Olive oil", "salad or cooking"),
            ("Cookie dough, raw", "Cookie dough", "raw"),
        ] as [(String, String, String?)])
    func aStapleFiledByItsHeadIsSaidTheOtherWayRound(name: String, title: String, detail: String?) {
        let parts = FoodLabel.parts(of: name)
        #expect(parts.title == title)
        #expect(parts.detail == detail)
    }

    @Test(
        arguments: [
            ("Cereals, oats, regular and quick, unenriched", "Oats", "regular and quick, unenriched"),
            ("Nuts, almonds", "Almonds", nil),
            ("Fish, salmon, Atlantic, farmed", "Salmon", "Atlantic, farmed"),
            ("Chicken, broilers or fryers, breast, meat only, cooked, roasted", "Chicken breast", "meat only, cooked, roasted"),
            ("Beef, ground, 90% lean meat", "Ground beef", "90% lean meat"),
            ("Rice, white, long-grain, regular, enriched", "White rice", "long-grain, regular, enriched"),
            ("Yogurt, Greek, plain, lowfat", "Greek yogurt", "plain, lowfat"),
            ("Oil, olive, extra virgin", "Olive oil", "extra virgin"),
            ("Apples, raw, without skin", "Apples", "raw, without skin"),
            ("Bananas, raw", "Bananas", "raw"),
        ] as [(String, String, String?)])
    func aCatalogNameReadsAsItsSaid(name: String, title: String, detail: String?) {
        let parts = FoodLabel.parts(of: name)
        #expect(parts.title == title)
        #expect(parts.detail == detail)
    }

    @Test(
        arguments: [
            ("Egg, whole, cooked, fried", "Egg", "cooked, fried"),
            ("Bread, wheat, toasted", "Wheat bread", "toasted"),
            ("Beverages, coffee, brewed, espresso, restaurant-prepared", "Espresso", "restaurant-prepared"),
            ("Chicken, broilers or fryers, meat only, raw", "Chicken", "meat only, raw"),
            ("Apples, raw, with skin (Includes foods for USDA's Food Distribution Program)", "Apples", "raw, with skin"),
            ("Oats (Includes foods for USDA's Food Distribution Program)", "Oats", nil),
            // What's ordered at a coffee shop or a bar, as FNDDS files it.
            ("Coffee, Latte, nonfat", "Latte", "nonfat"),
            ("Coffee, Iced Latte, with non-dairy milk", "Iced Latte", "with non-dairy milk"),
            ("Coffee, Cappuccino", "Cappuccino", nil),
            ("Coffee, espresso", "Espresso", nil),
            ("Tea, iced, brewed, black, unsweetened", "Iced tea", "brewed, black, unsweetened"),
            ("Tea, bubble", "Bubble tea", nil),
            ("Wine, sparkling", "Sparkling wine", nil),
            ("Wine, red", "Red wine", nil),
            ("Beer, light", "Light beer", nil),
            ("Margarita", "Margarita", nil),
            // A dish filed with its kind after it is said the other way round.
            ("Soup, tomato", "Tomato soup", nil),
            ("Soup, chicken noodle, canned", "Chicken noodle soup", "canned"),
            (
                "Soup, tomato, canned, prepared with equal volume water, commercial", "Tomato soup",
                "canned, prepared with equal volume water, commercial"
            ),
            ("Soup, New England clam chowder", "New England clam chowder", nil),
            // The survey's sweets: its kinds of candy, and the ones with names of their own.
            ("Candy, gummy", "Gummy candy", nil),
            ("Candy, cotton", "Cotton candy", nil),
            ("Candy, lollipop", "Lollipop", nil),
            ("Candy, fruit snacks", "Fruit snacks", nil),
            ("Chocolate candy, peanut butter filled", "Chocolate candy", "peanut butter filled"),
            // The survey's plain meats, fish and cereals: a steak by its cut, a fish of no one
            // kind, sliced meat from the deli, a cereal by its kind.
            ("Beef, steak, sirloin, cooked", "Sirloin steak", "cooked"),
            ("Beef, steak, T-bone, cooked, lean only", "T-bone steak", "cooked, lean only"),
            ("Beef, steak, cooked", "Beef steak", "cooked"),
            ("Steak, cooked", "Steak", "cooked"),
            ("Pork, chop, cooked", "Pork chop", "cooked"),
            ("Chicken breast, cooked, without skin", "Chicken breast", "cooked, without skin"),
            ("Fish, cooked", "Fish", "cooked"),
            ("Fish, baked or broiled, coated", "Fish", "baked or broiled, coated"),
            ("Fish, salmon, grilled", "Salmon", "grilled"),
            ("Fish, white fish, grilled", "White fish", "grilled"),
            ("Pork, steak, coated", "Pork steak", "coated"),
            ("Turkey, prepackaged or deli, luncheon meat", "Deli turkey", nil),
            ("Ham, prepackaged or deli, luncheon meat, reduced sodium", "Deli ham", "reduced sodium"),
            ("Cereal, corn flakes, plain", "Corn flakes cereal", "plain"),
            ("Cereal, ready-to-eat", "Cereal", "ready-to-eat"),
            ("Soup, pho, with meat", "Pho", "with meat"),
            ("Pie, apple", "Apple pie", nil),
            ("Pizza, cheese, from restaurant or fast food", "Cheese pizza", "from restaurant or fast food"),
            ("Taco, fish", "Fish taco", nil),
            ("Burrito, chicken, cheese", "Chicken burrito", "cheese"),
            ("Cookie, chocolate chip", "Chocolate chip cookie", nil),
            (
                "Cookies, chocolate chip, commercially prepared, regular, higher fat", "Chocolate chip cookies",
                "commercially prepared, regular, higher fat"
            ),
            ("Ice creams, vanilla", "Vanilla ice cream", nil),
            ("Sushi roll, California", "California roll", nil),
            ("Rice, fried, with chicken", "Fried rice", "with chicken"),
            ("Potato, mashed", "Mashed potato", nil),
            ("Potato, french fries", "French fries", nil),
            ("Cookie, brownie", "Brownie", nil),
            // Not by how it comes, is made or is sold.
            ("Pizza, no cheese, thin crust", "Pizza", "no cheese, thin crust"),
            ("Burrito, with beans, cheese", "Burrito", "with beans, cheese"),
            ("Taco, corn tortilla, beef, cheese", "Taco", "corn tortilla, beef, cheese"),
            ("Pizza, cheese topping, regular crust, frozen, cooked", "Pizza", "cheese topping, regular crust, frozen, cooked"),
            ("Pancakes, plain", "Pancakes", "plain"),
            ("Chicken or turkey parmigiana", "Chicken or turkey parmigiana", nil),
        ] as [(String, String, String?)])
    func everydayCatalogNamesReadAsTheyreSaid(name: String, title: String, detail: String?) {
        let parts = FoodLabel.parts(of: name)
        #expect(parts.title == title)
        #expect(parts.detail == detail)
    }

    /// Today's thread: what it is and how it was cooked, the way the catalog's most found foods
    /// are named.
    @Test(
        arguments: [
            ("Chicken, broilers or fryers, breast, meat only, cooked, roasted", "Chicken breast, roasted", "meat only"),
            ("Chicken, broilers or fryers, breast, meat and skin, cooked, roasted", "Chicken breast, roasted", "meat and skin"),
            ("Chicken, broilers or fryers, meat only, raw", "Chicken, raw", "meat only"),
            ("Rice, white, long-grain, regular, enriched, cooked", "White rice, cooked", "long-grain, regular, enriched"),
            ("Rice, white, long-grain, regular, raw, enriched", "White rice, raw", "long-grain, regular, enriched"),
            ("Beverages, coffee, brewed, prepared with tap water", "Coffee, brewed", "prepared with tap water"),
            ("Beverages, coffee, brewed, prepared with tap water, decaffeinated", "Coffee, decaf", "brewed, prepared with tap water"),
            ("Beverages, coffee, brewed, espresso, restaurant-prepared", "Espresso", "restaurant-prepared"),
            ("Egg, whole, cooked, fried", "Egg, fried", nil),
            ("Egg, whole, cooked, hard-boiled", "Egg, hard-boiled", nil),
            ("Egg, whole, raw, fresh", "Egg, raw", "fresh"),
            ("Yogurt, Greek, plain, lowfat", "Greek yogurt, lowfat", "plain"),
            ("Yogurt, plain, whole milk", "Yogurt, whole milk", "plain"),
            ("Milk, whole, 3.25% milkfat, with added vitamin D", "Whole milk", "3.25% milkfat, with added vitamin D"),
            (
                "Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D", "Milk, reduced fat",
                "fluid, 2% milkfat, with added vitamin A and vitamin D"
            ),
            ("Oil, olive, salad or cooking", "Olive oil", "salad or cooking"),
            ("Broccoli, cooked, boiled, drained, without salt", "Broccoli, boiled", "drained, without salt"),
            ("Bread, white, commercially prepared, toasted", "White bread, toasted", "commercially prepared"),
            (
                "Cereals, oats, regular and quick, unenriched, cooked with water (includes boiling and microwaving), without salt", "Oats, cooked",
                "regular and quick, unenriched, without salt"
            ),
            ("Fish, salmon, Atlantic, farmed, cooked, dry heat", "Salmon, cooked", "Atlantic, farmed, dry heat"),
            ("Sweet potato, cooked, baked in skin, flesh, without salt", "Sweet potato, baked", "flesh, without salt"),
            ("Beef, ground, 90% lean meat / 10% fat, raw", "Ground beef, raw", "90% lean meat / 10% fat"),
        ] as [(String, String, String?)])
    func aFoodOnTheThreadSaysHowItWasCooked(name: String, short: String, rest: String?) {
        let spoken = FoodLabel.spoken(name)
        #expect(spoken.short == short)
        #expect(spoken.rest == rest)
    }

    @Test(arguments: [
        ("Bananas, raw", "Bananas"), ("Apples, raw, without skin", "Apples"), ("Broccoli, raw", "Broccoli"),
        ("Tomatoes, red, ripe, raw, year round average", "Red tomatoes"), ("Coffee, black", "Black coffee"),
    ])
    func fruitAndVegetablesArentSaidToBeRawAndColoursGoFirst(name: String, short: String) {
        #expect(FoodLabel.short(name) == short)
    }

    @Test(arguments: ["Oats, dry", "Egg, raw", "Rice, cooked", "toast, buttered", "KIND bar", "McDONALD'S, BIG MAC", "Protein shake"])
    func aShortNameStaysAsWritten(name: String) {
        #expect(FoodLabel.short(name) == name)
    }

    @Test(arguments: [
        ("Chicken, broilers or fryers, breast, meat only, cooked, roasted", "Chicken breast"), ("Yogurt, Greek, plain, lowfat", "Greek yogurt"),
        ("Bananas, raw", "Bananas"), ("Protein shake", "Protein shake"),
    ])
    func aTileSaysWhatTheFoodIs(name: String, title: String) {
        #expect(FoodLabel.title(name) == title)
    }

    @Test(arguments: ["KIND bar", "McDONALD'S, BIG MAC", "Protein shake"])
    func aNameWithNothingToCutStaysWhole(name: String) {
        #expect(FoodLabel.parts(of: name).title == name)
        #expect(FoodLabel.parts(of: name).detail == nil)
    }

    @Test(arguments: [
        ("Cereals, oats, regular and quick", "🥣"), ("Yogurt, Greek, plain", "🥛"), ("Bananas, raw", "🍌"), ("Chicken, broilers or fryers, breast", "🍗"),
        ("Rice, white, long-grain", "🍚"), ("Broccoli, raw", "🥦"), ("Nuts, almonds", "🌰"), ("Fish, salmon, Atlantic", "🐟"), ("Eggplant, raw", "🍆"),
        ("Eggs, scrambled", "🥚"), ("Pineapple, raw", "🍍"), ("Apples, raw", "🍎"), ("Sweet potato, baked", "🍠"), ("Potatoes, roasted", "🥔"),
        ("Goat curry", "🍽️"), ("Hamburger, single patty", "🍔"),
    ])
    func aFoodsMarkerComesFromItsName(name: String, marker: String) {
        #expect(FoodMarker.of(name) == marker)
    }
}
