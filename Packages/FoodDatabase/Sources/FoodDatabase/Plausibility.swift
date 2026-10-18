import Foundation

/// Why a packaged food's numbers can't be right. Open Food Facts is entered by hand, and about one
/// row in fifty has kilojoules as calories, per-serving calories beside per-100 g macros, or a
/// powder's values on the drink it makes.
public enum FoodProblem: String, Hashable, Sendable {
    /// Protein, carbs and fat weigh more than the food: 120 g of macros in 100 g.
    case macrosOverWeight
    /// More energy than pure fat: over 905 kcal per 100 g.
    case tooDense
    /// Calories far from what the protein, carbs and fat make, or none when they make plenty.
    case caloriesDontAddUp
    /// A drink as poured with a powder's energy: a flat white at 452 kcal per 100 ml.
    case drinkTooDense
}

extension Food {
    /// The problem with the food's numbers, when they can't be right. Only packaged foods are
    /// checked: USDA's are curated, and a person's own are theirs.
    public var problem: FoodProblem? { source == .off ? Plausibility.problem(self) : nil }

    /// Whether the numbers hang together well enough to log without a second look.
    public var isPlausible: Bool { problem == nil }
}

enum Plausibility {
    /// Above this per 100 ml, a drink as poured is a powder's or a concentrate's numbers.
    static let drinkLimit = 160.0

    /// Words of drinks as poured. Their syrups, creamers, bases and concentrates are another thing.
    private static let drinkWords: Set<String> = Set(
        ("coffee cafe latte cappuccino espresso americano macchiato cortado "
            + "tea juice jus smoothie soda cola coke pepsi lemonade limonade kombucha water eau").split(separator: " ")
            .map(String.init))
    private static let notDrinkAsPoured: Set<String> = Set(
        ("syrup sirop concentrate concentre concentree creamer mate "
            + "base liqueur cream creme condensed powder poudre instant soluble capsule capsules pods dosette dosettes oil huile "
            + "chocolate chocolat ice glace candy bonbon").split(separator: " ").map(String.init))

    /// Alcohol has energy that isn't protein, carbs or fat.
    private static let alcoholWords: Set<String> = Set(
        ("beer biere bier wine vin wein vodka whisky whiskey gin rum rhum tequila "
            + "liqueur likor cider cidre sake brandy cognac champagne prosecco cava lager ale stout porter mead sherry vermouth "
            + "schnapps bourbon scotch aperitif spritz cocktail mojito sangria alcohol alcool armagnac calvados grappa ouzo pastis "
            + "absinthe martini baileys amaretto limoncello extract").split(separator: " ").map(String.init))
    /// Sugar alcohols and sweeteners count as carbs but bring few calories.
    private static let sweetenerWords: Set<String> = Set(
        ("stevia erythritol xylitol sweetener sweeteners edulcorant "
            + "sucralose aspartame polyol polyols maltitol sorbitol isomalt sukrin monkfruit truvia splenda canderel")
            .split(separator: " ").map(String.init))

    static func problem(_ food: Food) -> FoodProblem? {
        guard food.basis != .serving else { return nil }
        let n = food.nutrients
        let p = max(0, n.protein)
        let c = max(0, n.carbs)
        let f = max(0, n.fat)
        let fiber = max(0, n.fiber ?? 0)
        if p + c + f > 105 { return .macrosOverWeight }
        if n.kcal > 905 { return .tooDense }
        let name = Set(tokens(food.name))
        let drink = !name.isDisjoint(with: drinkWords) || (name.contains("flat") && name.contains("white"))
        // Carbs on US labels include fibre, and EU labels count fibre at 2 kcal/g: the range
        // between the two readings is what the macros can make.
        let least = 4 * p + 4 * max(0, c - fiber) + 9 * f
        let most = 4 * p + 4 * c + 9 * f + 2 * fiber
        let alcohol = !name.isDisjoint(with: alcoholWords)
        let sweetener = !name.isDisjoint(with: sweetenerWords)
        if n.kcal <= 0 && least >= 80 { return .caloriesDontAddUp }
        if least >= 50, n.kcal > 0, n.kcal < 0.6 * least, !sweetener { return .caloriesDontAddUp }
        if most >= 20, n.kcal > 1.4 * most + 40, !alcohol { return .caloriesDontAddUp }
        if n.kcal >= 80, most < 5, !alcohol, !sweetener { return .caloriesDontAddUp }
        if food.basis == .ml, n.kcal > drinkLimit, drink, name.isDisjoint(with: notDrinkAsPoured), !alcohol {
            return .drinkTooDense
        }
        return nil
    }
}
