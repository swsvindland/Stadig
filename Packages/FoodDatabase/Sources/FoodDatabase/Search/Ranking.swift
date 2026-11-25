import Foundation

/// What a search or a model names: "chicken breast", or "big mac" from McDonald's.
struct Named {
    var name: String
    var brand: String
}

/// What a typed search or a match knows beyond its words.
struct RankHints {
    var fixes: Fixes = [:]
    /// Among packaged foods, the ones people scan most rank higher (typed searches only).
    var popularity = false
    /// Packaged foods sold only in other countries than the phone's.
    var away: Set<String> = []
    /// The search's words that name a brand: "trader joes" in "trader joes mini wheats".
    var brand: [String] = []
    /// What the food the other words name is usually like.
    var profile: Profile?
    /// The search's words the catalogs barely know as typed, which may be a food's word misspelt.
    var doubted: Set<String> = []
    /// The corrections that are the same words written as one or apart ("redbull", "pop corn").
    var respelt: Set<String> = []
    /// What a model said comes with the food or about it, apart from its name (see `seenName`):
    /// "butter" for toast with butter, "buffalo" for chicken wings (buffalo). `beside` are the
    /// ones that are other foods served with it.
    var sides: [String] = []
    var beside: [String] = []
    /// The food was asked for from a restaurant chain the catalogs have no such food of: the
    /// one "from fast food" or "from restaurant" comes first. The word such a place's foods
    /// say, stemmed (see `Chains.Found.place`).
    var out: String?
}

/// A ranked food.
struct Ranked: Sendable {
    var food: Food
    var score: Double
    var index: Int
    var name: Double
    /// The catalog keeps exactly what was said as another name for the food.
    var called = false
    /// Or keeps a name that is what was said as it's read: with a typo corrected, or its last
    /// word still being typed ("jack and cok" for "Jack and coke").
    var calling = false
    /// The food is the asked brand's and has every other word said, or is a plain food the
    /// catalog keeps that brand's name for; and isn't another kind of food than the words
    /// usually name, where it's a label: Tim Hortons' "donut creamer" isn't its donut.
    var mine = false
}

// MARK: - Word lists

private func stems(_ text: String) -> Set<String> { Set(text.split(separator: " ").map { stem(String($0)) }) }

/// Catalog words that describe how an ordinary food is prepared or measured, not a different food.
private let neutral = stems(
    "raw cooked ripe fresh plain regular original whole prepared commercial average year round all type varieties includes baked "
        + "broiled roasted grilled boiled steamed pan stir fried microwaved heated cured sliced chopped diced shredded mature seeds "
        + "without salt added drained solids liquid enriched unenriched white red yellow green brewed tap water ready serve "
        + "made broilers fluid fryers meat only flesh separable fish beverages alcoholic nuts crustaceans mollusks spices "
        // How it's sold, and what's added to an ordinary food to keep or fortify it: bagels "with
        // calcium propionate", tofu "prepared with calcium sulfate", juice "with added ascorbic acid".
        + "commercially bottled shelf stable unsweetened salted unsalted vitamin calcium propionate ca prop sulfate nigari "
        + "ascorbic acid potassium sodium magnesium chloride iron "
        // How a cut of meat is graded and trimmed. Not its fat, which USDA also lists as a food
        // ("Pork, fresh, separable fat").
        + "trimmed lean choice select prime grades boneless composite retail "
        // How a canned soup is made up, what a canned dish is called and how corn comes.
        + "equal volume entree kernel no")

/// Where a dish is from, which says nothing more of what it is: a burger is a burger "from fast
/// food" or a restaurant. A plain food from one is cooked their way: green beans "from
/// restaurant" have the butter.
private let fromWords = stems("restaurant fast food")

/// The ones that say it by themselves: "food" is also in "(Includes foods for USDA's Food
/// Distribution Program)", which the whole-wheat pasta and brown rice end with.
private let placeWords = stems("restaurant fast")

/// A cuisine's restaurant isn't any restaurant: the wonton soup of a "Chinese restaurant"
/// isn't the soup of a chain typed with "soup", nor its steamed rice Nando's. Its food named
/// by just what was said is: "Restaurant, Chinese, orange chicken".
private let cuisineWords = stems("chinese latino mexican italian")

/// Words that mark a less common form or part; the model should name these if it means them.
private let variationWords = stems(
    "powder dehydrated dried canned frozen unprepared imitation meatless substitute low reduced nonfat free fortified mix "
        + "flake concentrate baby infant toddler stick oil seed juice paste puree soup dry lite light diet sugar sweetened "
        + "blend spread flavored feet giblets liver gizzard heart neck back skin kidney tongue tripe glutinous "
        + "sprouted instant parboiled precooked turkey stewed babyfood product brain evaporated condensed melba rusk candied "
        + "vegetarian vegan veggie")

/// Words for a food made of something else or for a baby, a further step from the food than a
/// form of it: meatless meatballs aren't meatballs the way frozen ones are, nor a vegetarian
/// meatloaf a meatloaf, nor strained banana with mixed berries a bowl of mixed berries.
private let insteadWords = stems("meatless imitation substitute babyfood vegetarian vegan veggie")

/// Words a food is never just filed under.
private let notFiled = insteadWords.union(stems("baby infant toddler"))

/// Kinds of food named after what they're made with or taste of, which follow it in a packaged
/// food's name: cake pretzels, peanut butter cups, cheese crackers, chocolate milk. Forms already
/// in `variationWords` (oil, juice, powder) aren't repeated; words that also say what a food is like
/// ("thin", "strips", "balls") are left out.
private let formWords = stems(
    "bar bite chip crisp cracker pretzel fries fry cup pop puff roll muffin cookie cake bread sandwich wafer cluster "
        + "nugget crumb snack tender pie dip sauce dressing seasoning candy cereal granola drink shake smoothie creamer "
        + "popcorn ice gelato frosting filling pudding jam jelly butter batter yogurt milk water flour syrup bagel waffle "
        + "pancake biscuit brownie donut doughnut tart latte tea coffee salad burger wrap burrito taco pizza crust dough "
        + "noodle pasta broth sausage meatball dumpling bowl kit shell shot")

/// Words after which a name goes on to another part of the food: "cake with chocolate filling".
private let partWords: Set<String> = ["with", "and", "or", "in", "on", "filled", "topped", "dipped", "covered", "coated", "stuffed"]

/// How the catalog words the fat level a search names with a number: "2%" is reduced fat.
private let fatWords = stems("fat milkfat lowfat low reduced nonfat lean")

/// USDA's own markers for the typical entry among varieties: "Tomatoes, red, ripe, raw, year round
/// average", "Soymilk, original and vanilla".
private let typicalWords = stems("average varieties regular ripe original composite")

/// Words in a name's first part that say nothing of another food.
private let leadFillers = stems("made from ready eat")

/// The groups USDA files foods under, as words: no word a food of the group lacks, but one a
/// search can ask for.
private let groupWords = stems("fish nuts beverages crustaceans mollusks spices")

/// The most scanned brands of one word, as a typed word is compared with a brand's.
private let popularBrands = Set(PopularBrands.names.filter { !$0.contains(" ") }.map { bare(String($0.unicodeScalars.filter(isWordScalar))) })

/// And of more than one, as their words.
private let popularNames = Set(PopularBrands.names.filter { $0.contains(" ") }.map { words($0).map(bare).joined(separator: " ") })

/// What a label says of how a food was grown or made, which a plain food needn't say to be it.
private let fluffWords = stems("organic natural homemade fresh")

/// How a food is kept, which is how some foods always come: tomato paste is canned.
private let keptWords = stems("canned frozen dried dehydrated")

/// The peoples whose traditional foods USDA lists beside the everyday ones, in a note: "Corn,
/// white, steamed (Navajo)", "Blueberries, wild, raw (Alaska Native)".
private let traditionWords = stems("navajo hopi apache alaska shoshone bannock plains")

/// Names that only labels are, where the plain foods with the words are other foods: USDA's
/// "Rice, brown, with vegetables, soy-based sauce" isn't brown sauce, its poppyseed dressing
/// that says "creamy" isn't salad cream, nor its "Honey roll sausage" a sausage roll. Those
/// come after the labels named so. A list, not a rule: nothing in a name tells such a food
/// from "Tomato products, canned, paste", which is tomato paste.
private let onlyLabelled: Set<[String]> = Set(["brown sauce", "salad cream", "sausage roll"].map { words($0).map(stem) })

/// The everyday variety when a food doesn't name one ("rice" is usually long-grain).
private struct Usual {
    let marks: [String]
    let others: [String]
    let markStems: [String]
    let otherStems: [String]

    init(_ marks: [String], _ others: [String]) {
        self.marks = marks
        self.others = others
        markStems = marks.map(stem)
        otherStems = others.map(stem)
    }
}

private let breadKinds =
    ("rye egg oatmeal raisin cinnamon french italian vienna multigrain sourdough pumpernickel potato cheese "
    + "banana corn pita naan garlic gluten protein rice oat muffin muffins sprouted reduced calorie pumpkin irish soda "
    + "boston brown mixed grain cracked crust stuffing crumb crumbs").split(separator: " ").map(String.init)

/// The meats a steak or a cut can be of, when it isn't beef.
private let meats =
    "bison deer elk veal pork lamb ham salmon tuna fish game buffalo venison moose caribou turkey chicken salisbury emu ostrich goat"
    .split(separator: " ").map(String.init)

/// By the stem a word is searched by: "whiskey" is looked up as "whiske".
private let usualVarieties: [String: Usual] = Dictionary(uniqueKeysWithValues: everydayVarieties.map { (stem($0.key), $0.value) })

private let everydayVarieties: [String: Usual] = [
    "rice": Usual(["long"], ["short", "medium", "brown", "wild", "basmati", "jasmine"]),
    "cheese": Usual(
        ["cheddar", "american"],
        "mozzarella parmesan swiss feta provolone cottage cream goat blue ricotta monterey brie gouda"
            .split(separator: " ").map(String.init)),
    "milk": Usual(
        ["whole"],
        ("skim nonfat reduced lowfat almond soy oat chocolate buttermilk coconut rice cashew hemp pea goat sheep condensed "
            + "evaporated powder powdered dry shake human malted").split(separator: " ").map(String.init)),
    "egg": Usual(["whole"], ["white", "yolk"]),
    // Mint is the herb, which USDA lists fresh; the sweet is asked for as mints.
    "mint": Usual(["fresh"], ["candy", "julep", "chocolate", "sauce", "jelly", "tea", "gum"]),
    // Clam chowder is the New England one.
    "chowder": Usual(["england"], ["manhattan", "corn", "fish", "potato", "seafood"]),
    // A pizza is a cheese pizza, where no more is said.
    "pizza": Usual(
        ["cheese"],
        "pepperoni meat sausage vegetable veggie fruit bean white extra no stuffed topping roll breakfast dessert mexican school frozen"
            .split(separator: " ").map(String.init)),
    // Toast and a slice of bread are white or wheat; any other kind named is that kind.
    "toast": Usual(["white", "wheat"], breadKinds),
    "bread": Usual(["white", "wheat"], breadKinds),
    // Beans in a bowl or a burrito are black or pinto; any kind named is that kind.
    "bean": Usual(
        ["black", "pinto"],
        ("snap green yellow wax string baked refried lima fava broad navy kidney northern great white cannellini "
            + "garbanzo chickpea mung adzuki soy soybean edamame coffee cocoa vanilla jelly french yardlong hyacinth "
            + "winged moth cranberry shellie lupini mothbean").split(separator: " ").map(String.init)),
    // Sugar in a recipe or a coffee is granulated, tea is black, wine is table wine, chips are
    // potato chips and popcorn is popped, not pressed into cakes or coated.
    "sugar": Usual(["granulated"], "brown powdered maple turbinado coconut cane date palm raw free".split(separator: " ").map(String.init)),
    "tea": Usual(
        ["black"], "green herb herbal hibiscus oolong chamomile instant white iced chai matcha".split(separator: " ").map(String.init)),
    "wine": Usual(["table"], "cooking dessert rose light sparkling rice non".split(separator: " ").map(String.init)),
    "chip": Usual(
        ["potato"],
        "banana taro bagel tortilla corn pita apple plantain kale veggie vegetable sweet chocolate rice pea lentil bean"
            .split(separator: " ").map(String.init)),
    "popcorn": Usual(["popped"], "cake caramel cheese microwave kettle chicken".split(separator: " ").map(String.init)),
    // A pepper is a bell pepper, red, green or yellow; the spice and the hot ones are asked
    // for by name.
    "pepper": Usual(
        ["sweet"],
        ("black white cayenne ground cracked hot chili chile jalapeno banana serrano hungarian poblano habanero ancho pasilla pimiento bell "
            + "stuffed jack lemon sauce steak roasted pickled spice flake crushed").split(separator: " ").map(String.init)),
    // Fries are french fries, whatever else is cut and fried like them.
    "fries": Usual(["french"], "sweet yuca cassava home cottage cheese chili zucchini avocado plantain stir".split(separator: " ").map(String.init)),
    // Water is still water, from a bottle or the tap.
    "water": Usual(
        ["bottled", "tap"],
        "tonic carbonated flavored coconut sparkling seltzer enhanced vitamin rose fruit sweetened".split(separator: " ").map(String.init)),
    // Pretzels from a bag are the hard ones.
    "pretzel": Usual(["hard"], "soft chocolate yogurt coating coated filled combos gluten bun roll".split(separator: " ").map(String.init)),
    // Bacon is cured pork and a steak is beef, which USDA files under "Pork" and "Beef"; the kinds
    // filed under the word itself are the unusual ones ("Bacon, turkey", "Game meat, bison, steak").
    "bacon": Usual(["pork"], "turkey canadian beef meatless bits vegetarian chicken".split(separator: " ").map(String.init)),
    "steak": Usual(["beef"], meats),
    "ribeye": Usual(["beef"], meats),
    "sirloin": Usual(["beef"], meats),
    "mayonnaise": Usual(["regular"], "tofu light imitation reduced low diet free olive vegan".split(separator: " ").map(String.init)),
    "mayo": Usual(["regular"], "tofu light imitation reduced low diet free olive vegan".split(separator: " ").map(String.init)),
    "whiskey": Usual(["distilled"], ["sour", "mix"]),
    "pita": Usual(["bread"], ["chip", "pitanga"]),
    "cottage": Usual(["creamed", "lowfat"], "vegetable fruit nonfat uncreamed dry lactose sodium".split(separator: " ").map(String.init)),
    "zucchini": Usual(["summer"], ["baby", "italian", "canned"]),
    "granola": Usual(["cereal"], ["bar", "bite"]),
    // Typed alone, a meat is the cut most logged: ground beef, fresh pork and not ham, pork ribs.
    "beef": Usual(
        ["ground"],
        ("steak roast jerky stew corned liver broth stock rib ribs brisket tenderloin sirloin ribeye chuck round burger "
            + "frank frankfurter sausage bologna pot pie taco burrito soup noodle chili stroganoff tongue heart kidney tripe "
            + "tallow bouillon gravy").split(separator: " ").map(String.init)),
    "pork": Usual(
        ["fresh"],
        ("cured ham bacon sausage chop chops loin tenderloin rib ribs sparerib spareribs shoulder belly rind rinds skin skins "
            + "ground pulled barbecue bbq sweet sour bean beans").split(separator: " ").map(String.init)),
    "rib": Usual(["pork"], "beef short shortrib prime veal lamb eye bison".split(separator: " ").map(String.init)),
    // Cereal is the kind poured from a box, nuts are mixed nuts, pickles are dill and chili is
    // the dish with beans, not the pepper.
    "cereal": Usual(["ready"], "hot cooked bar oat oats oatmeal grits farina cream baby infant".split(separator: " ").map(String.init)),
    "nut": Usual(
        ["mixed"],
        ("butter almond walnut pecan cashew pistachio macadamia brazil hazelnut pine coconut chestnut ginkgo hickory "
            + "acorn beechnut butternut pili honey bar granola cereal trail").split(separator: " ").map(String.init)),
    "pickle": Usual(["dill"], "sweet sour relish bread butter beet egg herring pepper ginger okra onion".split(separator: " ").map(String.init)),
    "chili": Usual(
        ["bean", "carne"],
        "pepper peppers powder sauce hot sweet paste flake flakes oil dog fries cheese seasoning lime green red verde"
            .split(separator: " ").map(String.init)),
    // Tuna, sardines and anchovies come out of a can; soup and stew mostly do.
    "tuna": Usual(
        ["canned"],
        "fresh steak bluefin yellowfin skipjack ahi salad seared raw sushi sashimi roll melt casserole noodle helper"
            .split(separator: " ").map(String.init)),
    "sardine": Usual(["canned"], ["fresh", "raw"]),
    // Raisins are the dark seedless ones, not USDA's seeded.
    "raisin": Usual(["dark"], ["golden", "seeded"]),
    // Curry with no more said is chicken curry; the survey's fish curry came first.
    "curry": Usual(["chicken"], ["fish", "beef", "lentil", "vegetable", "powder", "paste", "sauce", "goat", "lamb", "shrimp", "leaf", "leaves"]),
    // Stock with no more said is chicken stock.
    "stock": Usual(["chicken"], ["fish", "beef", "vegetable", "cube"]),
    "anchov": Usual(["canned"], ["fresh", "raw", "paste"]),
    "soup": Usual(["canned"], "dry mix dehydrated homemade home stock broth bouillon cube powder ramen".split(separator: " ").map(String.init)),
    "stew": Usual(["canned"], ["chuck", "meat", "raw"]),
    // A dish by its usual filling, not the sauce, shell or chips named after it.
    "lasagna": Usual(
        ["meat"], "vegetable cheese spinach noodle noodles sheets meatless chicken turkey whole".split(separator: " ").map(String.init)),
    "enchilada": Usual(["cheese"], ["sauce", "seasoning", "kit"]),
    "taco": Usual(["beef"], "shell shells salad seasoning sauce kit chip chips flavor".split(separator: " ").map(String.init)),
    "nacho": Usual(["fast"], "chip chips flavor tortilla sauce dip".split(separator: " ").map(String.init)),
    // Liver is beef liver, pastrami beef, mackerel the Atlantic one, frosting vanilla, custard
    // the egg custard, shortening the household kind and gravy beef gravy.
    "liver": Usual(["beef"], "chicken goose duck pork lamb veal turkey cod calf pate".split(separator: " ").map(String.init)),
    "pastrami": Usual(["beef"], ["turkey"]),
    "mackerel": Usual(["atlantic"], "salted canned king spanish jack pacific smoked".split(separator: " ").map(String.init)),
    "frosting": Usual(["vanilla"], "chocolate cheese coconut glaze white fluffy".split(separator: " ").map(String.init)),
    "custard": Usual(["egg"], "apple pie filled puff flan frozen pudding mix".split(separator: " ").map(String.init)),
    "shortening": Usual(["household"], "frying industrial confectionery bread cake special".split(separator: " ").map(String.init)),
    "gravy": Usual(["beef"], "chicken turkey mushroom pork onion au jus sausage country white brown".split(separator: " ").map(String.init)),
    // Spirits are 80 proof unless a number says otherwise.
    "distilled": Usual(["80"], []),
    // Ginger typed alone is the root; ground, it's the spice.
    "ginger": Usual(
        ["root"], "ground ale beer snap snaps bread candied crystallized pickled tea powder spice".split(separator: " ").map(String.init)),
    "nugget": Usual(
        ["chicken"], "fish salmon cod tuna pork turkey veggie vegan plant tofu cauliflower chocolate ice".split(separator: " ").map(String.init)),
    "cornbread": Usual(["recipe"], ["mix", "stuffing"]),
    "lettuce": Usual(["iceberg"], "romaine cos butterhead bibb boston leaf salad wrap wraps".split(separator: " ").map(String.init)),
    // Goat cheese is the soft kind; goat's milk and meat are themselves.
    "goat": Usual(["soft"], ["milk", "meat", "roasted", "raw"]),
    // A kind of food typed alone is the one of its kind most logged: orange juice, olive oil,
    // heavy cream, maple syrup, a white fish, a green salad, a turkey sandwich, mixed
    // vegetables, apple pie, chocolate chip cookies, saltines, ranch dressing, pasta sauce.
    "juice": Usual(
        ["orange"],
        "apple grape cranberry lemon lime tomato carrot pineapple grapefruit prune vegetable pomegranate cherry clam pickle".split(separator: " ")
            .map(String.init)),
    "oil": Usual(
        ["olive"],
        "canola vegetable coconut corn peanut sesame avocado sunflower safflower soybean palm fish cod flaxseed mct".split(separator: " ").map(
            String.init)),
    "cream": Usual(["heavy"], "ice sour whipped cheese light half coffee table coconut soup pie puff soda".split(separator: " ").map(String.init)),
    "syrup": Usual(["maple"], "chocolate corn pancake agave simple cane sorghum malt rice date fruit".split(separator: " ").map(String.init)),
    "salad": Usual(
        ["lettuce"],
        "tuna chicken egg potato pasta macaroni fruit caesar greek cobb taco bean dressing seafood crab shrimp ham turkey kit".split(separator: " ")
            .map(String.init)),
    "sandwich": Usual(
        ["turkey"],
        "ham chicken club tuna egg cheese ice cream cookie cookies breakfast fish steak beef pork peanut butter bread spread cracker crackers".split(
            separator: " "
        ).map(String.init)),
    "vegetable": Usual(
        ["mixed"], "oil juice soup broth stock shortening spread burger burgers chips beef protein".split(separator: " ").map(String.init)),
    "pie": Usual(
        ["apple"],
        "pumpkin cherry pecan chicken pot shepherd shepherds crust filling blueberry lemon peach cream chocolate lime pizza".split(separator: " ")
            .map(String.init)),
    "cookie": Usual(
        ["chocolate"],
        "sandwich oatmeal sugar peanut butter fortune ginger gingersnap shortbread wafer dough mix".split(separator: " ").map(String.init)),
    "cracker": Usual(
        ["saltine"], "cheese graham animal rice wheat whole rye oyster sandwich peanut butter matzo".split(separator: " ").map(String.init)),
    "dressing": Usual(
        ["ranch"],
        "italian caesar french thousand island blue cheese vinaigrette honey mustard russian sesame mayonnaise mayo balsamic oil vinegar bacon".split(
            separator: " "
        ).map(String.init)),
    "sauce": Usual(
        ["pasta"],
        "soy hot bbq barbecue tomato alfredo cheese fish oyster teriyaki worcestershire tartar cocktail hoisin chili pepper cranberry apple steak pizza enchilada taco sweet sour duck plum peanut hollandaise white brown meat buffalo"
            .split(separator: " ").map(String.init)),
]

/// The same for foods of two words, read before either word's own: tomato sauce, tomato paste
/// and condensed milk come canned, and an egg roll is the filled one, not a dinner roll with egg.
private let usualPhrases: [(words: [String], usual: Usual)] = [
    ("tomato sauce", Usual(["canned"], ["chili", "pasta", "spaghetti", "marinara"])),
    ("tomato paste", Usual(["canned"], [])),
    ("condensed milk", Usual(["canned", "sweetened"], [])),
    ("peanut butter", Usual(["smooth"], ["chunk", "chunky", "crunchy", "reduced", "powder", "powdered", "cup", "cups", "cookie", "cookies"])),
    // Ground meat sold as lean is 93% lean, and as extra lean 95% or more; every kind USDA
    // lists says how lean it is.
    ("extra lean", Usual(["95", "96", "97"], [])),
    ("lean ground", Usual(["93"], [])),
    ("egg roll", Usual(["pork", "vegetable", "chicken", "assorted"], ["dinner"])),
    // Soy sauce is the kind brewed from soy and wheat, and cocoa powder the unsweetened one,
    // not a cocoa mix.
    ("soy sauce", Usual(["shoyu"], ["tamari", "low", "reduced", "less", "lite", "light", "hydrolyzed"])),
    ("cocoa powder", Usual(["unsweetened"], ["mix", "hot", "sweetened"])),
    ("corn syrup", Usual(["light"], ["dark", "high", "fructose"])),
    // Iced tea is brewed black tea, unsweetened, unless it's said to be bottled or sweet.
    ("iced tea", Usual(["black"], "bottled instant green sweetened diet decaffeinated lemonade herbal light".split(separator: " ").map(String.init))),
    // Chocolate chips are its semisweet chocolate, where most foods with the words are cookies.
    (
        "chocolate chip",
        Usual(
            ["semisweet"],
            "cookie cookies bar bars muffin muffins pancake pancakes waffle waffles granola ice cream".split(separator: " ").map(String.init))
    ),
].map { ($0.0.split(separator: " ").map { stem(String($0)) }, $0.1) }

/// Searches and seen foods naming these mean the cooked food unless they say "raw": "salmon",
/// "rice", "chicken", the beans in a burrito bowl, a bowl of oatmeal.
private let eatenCooked = stems(
    "rice pasta noodle spaghetti macaroni quinoa lentil oatmeal porridge chicken beef pork turkey lamb steak bacon sausage "
        + "salmon fish tuna cod tilapia shrimp egg potato bean chickpea barley couscous bulgur farro millet grits polenta "
        + "duck goose veal bison venison ribeye sirloin brisket tenderloin crab lobster scallop trout halibut catfish haddock "
        + "rib sparerib backrib roast clam mussel calamari squid octopus crayfish")
/// Cuts and kinds of fish that mean the cooked food too, once typed whole: half typed they're
/// other foods ("brea" is bread, "flou" flour, "whit" white rice, "snap" snap peas).
private let eatenCookedWhole = stems(
    "wing thigh drumstick breast leg chop loin cutlet fillet tripe flounder sole snapper grouper mackerel perch pollock swordfish mahi "
        + "mahimahi bass herring whiting pike walleye carp eel mullet croaker pompano shark monkfish sturgeon rockfish roughy yellowtail "
        + "smelt turbot whitefish bluefish butterfish sablefish lingcod milkfish tilefish wolffish shad seatrout sheepshead abalone cuttlefish")
private let cookedWords = stems("cooked roasted baked boiled broiled grilled steamed poached scrambled fried braised microwaved")
private let plainlyCooked = stem("cooked")

/// How a food is cooked: with dry heat, in water or steam, or in fat.
enum Heat: Sendable { case dry, moist, fat }

/// The ways of cooking, by kind. USDA lists a cooked food one or two ways ("Broccoli, cooked,
/// boiled", "Fish, salmon, …, cooked, dry heat"), so a way it doesn't list for a food is read as
/// the nearest way it does (see `Ease`).
let heats: [String: Heat] = {
    var kinds: [String: Heat] = [:]
    // Smoked is a way too, where no plain food is named so: smoked brisket is the brisket, and
    // smoked salmon still its own.
    for word in stems(
        "roasted roast baked broiled grilled seared blackened charred rotisserie barbecued chargrilled charbroiled toasted browned smoked")
    {
        kinds[word] = .dry
    }
    for word in stems("boiled steamed poached braised stewed simmered microwaved blanched") { kinds[word] = .moist }
    for word in stems("fried sauteed") { kinds[word] = .fat }
    return kinds
}()

/// Foods that cooking dries into another food, weight for weight: roasted seaweed and coffee.
private let driedByHeat = stems("seaweed nori kelp laver wakame coffee cocoa cacao")

/// How a food is cut, or how young it was picked, which USDA mostly leaves unsaid: a salmon
/// fillet is its salmon, broccoli florets its broccoli, baby spinach its spinach and shredded
/// chicken its cooked chicken. Not "diced" or "sliced", which more often name what's sold in a
/// can, nor "pulled", which names a dish of its own.
private let cutWords = stems("fillet filet slice piece chunk floret spear halves stalk clove cutlet baby shredded")

/// What a food said to be trimmed mustn't have: "skinless" chicken is USDA's "meat only", not its
/// "meat and skin".
private let trimWords = ["skinless": "skin", "boneless": "bone"]

/// Said of a food that isn't cooked, which USDA often leaves unsaid too: raw almonds are its
/// "Nuts, almonds".
private let rawWords = stems("raw fresh uncooked")

/// How a food on a plate is cut, which is no kind of the food, said by a model or typed:
/// chopped onion is an onion, where the words found USDA's frozen chopped ones, "minced
/// onion" ground beef with onion, "sliced apple" its canned sweetened slices and "chopped
/// walnuts" a row of labels. A can's "diced tomatoes" come right after the tomato.
private let plateCuts = stems("sliced diced chopped shredded crumbled grated minced cubed halved quartered torn")

/// Whether a word says how a food is cooked or cut, not what it is. `seen` with the ways a
/// food on a plate is cut, which a search eases and the words that name a food keep.
func isEasable(_ word: String, seen: Bool = false) -> Bool {
    let said = stem(word)
    return heats[said] != nil || cutWords.contains(said) || trimWords[said] != nil || rawWords.contains(said) || labelWords.contains(said)
        || (seen && plateCuts.contains(said))
}

/// Whether a word says how a food is cooked.
func isHeat(_ word: String) -> Bool { heats[stem(word)] != nil }

/// Whether a word only says how a food comes: cooked or raw, how it's cooked, cut or trimmed,
/// or a label's word for how it was made.
func saysHow(_ word: String) -> Bool { isEasable(word) || cookedWords.contains(stem(word)) }

/// Words for the form a food comes in, beyond how it's cooked or kept: how fat, sweet or salted,
/// which colour, with its skin or bone.
private let formsSaid = stems(
    "plain whole skim unsweetened sweetened salted unsalted light lite diet free reduced instant skin skinless bone boneless red green white "
        + "yellow brown black dark extra virgin ground lean")

/// Whether a word a model put in brackets or after "with" says which form of the food it is,
/// and so belongs to its name: "(canned)", "(nonfat)", "(93% lean)", "with skin".
func isFormSaid(_ word: String) -> Bool {
    let said = stem(word)
    return isNumber(word) || heats[said] != nil || keptWords.contains(said) || cookedWords.contains(said) || rawWords.contains(said)
        || fatWords.contains(said) || formsSaid.contains(said)
}

/// A word said that a food needn't have to be the food asked for, because no plain food with
/// the other words has it: "steamed" where USDA's broccoli is only "cooked, boiled", "fillet"
/// where its salmon is just salmon.
struct Ease {
    /// For a way of cooking, its kind: any cooked food will do, the same kind first. Fried food
    /// is only ever what "fried" or "sauteed" means, and "fried" means nothing else.
    var heat: Heat?
    var fried = false
    /// A word the food mustn't have.
    var unless: String?
    /// The word says the food isn't cooked.
    var raw = false
    /// A way a model says the food on the plate is cut, or a label's word for how it was grown
    /// or made: any food is spared it, one that says it a little ahead.
    var plate = false
    /// The word is a label's, which puts a food that says it only just ahead: a plain
    /// hamburger is still the hamburger, not the bun that's listed as plain.
    var label = false
    /// No food is spared the word: some plain food lists it, or none comes near it. Then it
    /// says which food is meant, and a food without it lacks it, though it's a word for how a
    /// food comes: fried rice isn't USDA's plain cooked rice, nor fresh mozzarella its block.
    var listed = false
    /// The catalog has the food only uncooked, so that is the one cooked this way: roasted
    /// garlic is its "Garlic, raw", as a cooked egg white is its raw one.
    var uncooked = false

    init(_ said: String, listed: Bool = false) {
        heat = heats[said]
        fried = said == "fried"
        unless = trimWords[said]
        raw = rawWords.contains(said)
        self.listed = listed
    }

    /// Whether a food is one the word needn't be said of.
    func fits(_ text: FoodText) -> Bool {
        if listed { return false }
        // Not where the food says it's without it: a thigh "without skin" is the skinless one.
        if let unless, text.all.indices.contains(where: { text.all[$0] == unless && ($0 == 0 || text.all[$0 - 1] != "without") }) {
            return false
        }
        if raw { return !text.cooking.cooked && !text.titled.contains(where: keptWords.contains) }
        guard let heat else { return true }
        let cooking = text.cooking
        guard cooking.cooked else { return uncooked }
        return heat == .fat ? !fried || cooking.kinds.contains(.fat) : cooking.kinds != [.fat]
    }

    /// How much nearer a food cooked the same kind of way is than one cooked another way, and
    /// that than one that only says "cooked": USDA's own cooked entry says how, and one that
    /// doesn't is a variety's or a restaurant's.
    func nearness(_ text: FoodText) -> Double {
        guard let heat else { return label ? -0.1 : plate ? -0.3 : 0 }
        let kinds = text.cooking.kinds
        return kinds.contains(heat) ? 0.3 : kinds.isEmpty ? 0 : 0.1
    }
}

/// The cooked words in the catalog's full-text syntax, as prefixes.
private let cookedTerm =
    "("
    + "cooked roasted baked boiled broiled grilled steamed poached scrambled braised microwaved"
    .split(separator: " ").map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"

/// The same for a search that says how the food is cooked, which a fried food may answer too.
let heatedTerm =
    "("
    + "cooked roasted baked boiled broiled grilled steamed poached braised stewed microwaved toasted fried sauteed"
    .split(separator: " ").map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"

/// Extra catalog queries for the everyday form of a plain seen food, run beside the usual ones so
/// a long USDA name for it is in the pool at all: the cooked form of what's eaten cooked
/// ("Cereals, oats, …, cooked with water" for oatmeal), and the everyday variety ("black" or
/// "pinto" beans for beans). A form the `pool` already has a food filed under isn't searched again.
func everydayQueries(_ seen: Named, pool: [Entry] = []) -> [String] {
    guard seen.brand.isEmpty else { return [] }
    let name = nameWords(seen.name)
    let said = name.map(stem)
    guard !name.isEmpty, !said.contains("raw") else { return [] }
    let base = name.map(term).joined(separator: " AND ")
    var variety: String?
    if let usual = said.lazy.compactMap({ usualVarieties[$0] }).first,
        !said.contains(where: { usual.otherStems.contains($0) || usual.markStems.contains($0) })
    {
        variety = "(" + usual.marks.map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
    }
    let cooked = said.contains(where: { eatenCooked.contains($0) || eatenCookedWhole.contains($0) }) && !said.contains(where: cookedWords.contains)
    // Foods filed under what was said: "Fish, salmon, …" for salmon.
    let filed = pool.lazy.filter { entry in
        !entry.text.lead.isEmpty && entry.text.lead.allSatisfy { w in said.contains { same(w, $0) || starts(w, $0) } }
    }
    let haveCooked = filed.contains { $0.text.all.contains(where: cookedWords.contains) }
    let marks = variety == nil ? [] : (said.lazy.compactMap { usualVarieties[$0] }.first?.markStems ?? [])
    let haveVariety = filed.contains { entry in
        entry.text.all.contains(where: marks.contains) && (!cooked || entry.text.all.contains(where: cookedWords.contains))
    }
    var queries: [String] = []
    if let variety, !haveVariety { queries.append(([base, variety] + (cooked ? [cookedTerm] : [])).joined(separator: " AND ")) }
    if cooked, !haveCooked { queries.append("\(base) AND \(cookedTerm)") }
    return queries
}

/// USDA files some foods under a group: "Fish, salmon", "Beverages, coffee", "Nuts, almonds".
private let groups: Set<String> = [
    "fish", "beverage", "beverages", "alcoholic beverage", "alcoholic beverages", "nuts", "crustaceans", "mollusks", "spices",
    "cereals",
]

// MARK: - A food's words

/// The words of a food's name and brand that ranking reads, read once per ranking.
struct FoodText {
    /// The name's words, stemmed; "dry heat" is how USDA says cooked.
    let titled: [String]
    /// The name's and brand's words, stemmed.
    let all: [String]
    /// The brand's words as written, including a restaurant USDA writes first ("McDONALD'S, BIG MAC").
    let ownWords: [String]
    /// The same, stemmed.
    let own: [String]
    /// The name's words outside brackets and the brand, stemmed.
    let said: [String]
    /// Which run of `said` each word is in: a comma, "&" or "with" starts another.
    let runs: [Int]
    /// The runs that start with "with": what the food comes with, not what it is.
    let served: Set<Int>
    /// The runs that start after "or": the "tostada salad" of "Taco or tostada salad".
    let alternate: Set<Int>
    /// The runs that start after "and": the onions of "Liver and onions".
    let joint: Set<Int>
    /// Words in brackets, stemmed, except "(Includes …)".
    let noted: [String]
    /// The words of an "(Includes …)" note, stemmed: other foods the entry stands for.
    let included: [String]
    /// What the food is canned or packed in, stemmed: the "tomato juice" of tomatoes packed in it.
    let packed: [String]
    /// The word each word is joined to by a hyphen, both stemmed: "apple" for the "custard" of
    /// "Custard-apple", "flavor" for the "taco" of "taco-flavor".
    let joined: [String: String]
    /// The words before the name's first comma, after a USDA group ("Fish, salmon"), stemmed.
    let lead: [String]
    /// The words of the name's first two comma-separated parts, after a group, stemmed: "Oil" and
    /// "olive" in "Oil, olive, salad or cooking".
    let heads: [[String]]
    /// The name's words written in capitals, stemmed: the brands USDA names wherever in a name
    /// ("Yogurt, Greek, plain, CHOBANI").
    let shouted: [String]
    /// The group USDA files it under, when it does, stemmed: "nut" for "Nuts, almonds".
    let group: [String]
    /// Its brand is a chain or a maker USDA writes first in capitals, not a label's brand field.
    let chain: Bool
    /// A restaurant or packaged food.
    let branded: Bool
    /// The food is the skin alone: "Chicken, skin only", KFC's "Skin and Breading", a baked
    /// potato's "skin". Not one that includes its skin, or has had it removed.
    let skinAlone: Bool
    /// USDA's "dry heat" or "moist heat", which the words read as "cooked".
    let heat: Heat?

    /// How the name says the food was cooked, and whether it says it was cooked at all.
    var cooking: (kinds: Set<Heat>, cooked: Bool) {
        var kinds = Set<Heat>()
        if let heat { kinds.insert(heat) }
        var cooked = heat != nil
        for word in titled {
            if let kind = heats[word] {
                kinds.insert(kind)
                cooked = true
            } else if !cooked, cookedWords.contains(word) {
                cooked = true
            }
        }
        return (kinds, cooked)
    }

    init(_ food: Food) { self.init(name: food.name, brand: food.brand ?? "", source: food.source) }

    /// Reads the name once: its words, which are in brackets, and which comma-separated part each is in.
    init(name original: String, brand: String, source: FoodSource) {
        let heated = mentionsHeat(original)
        let name = heated ? cookedHeat(original) : original
        heat = !heated ? nil : original.range(of: "dry heat", options: .caseInsensitive) != nil ? .dry : name != original ? .moist : nil
        let scalars = plainScalars(name)
        let found = scanTokens(scalars)
        let close = scalars.lastIndex(of: ")") ?? -1
        // Each token's bracket (none, a note, or an "(Includes …)" note), comma-separated part and run.
        var placed: [(bracket: Int, part: Int, run: Int)] = []
        placed.reserveCapacity(found.count)
        var bracket = 0
        var part = 0
        var run = 0
        var served = Set<Int>()
        var alternate = Set<Int>()
        var joint = Set<Int>()
        var next = 0
        var commas: [Int] = []
        for (i, scalar) in scalars.enumerated() {
            if scalar == "(" && bracket == 0 && i < close {
                bracket = startsWithIncludes(scalars, i + 1) ? 2 : 1
            } else if scalar == ")" && bracket != 0 {
                bracket = 0
            } else if scalar == "," {
                part += 1
                run += 1
                commas.append(i)
            } else if scalar == "&" || scalar == "+" || scalar == "/" {
                run += 1
                if scalar != "/" { joint.insert(run) }
            }
            while next < found.count && found[next].start == i {
                if partWords.contains(found[next].word) {
                    run += 1
                    if found[next].word == "with" { served.insert(run) }
                    if found[next].word == "or" { alternate.insert(run) }
                    if found[next].word == "and" { joint.insert(run) }
                }
                placed.append((bracket, part, run))
                next += 1
            }
        }
        let stems = found.map { stopWords.contains($0.word) ? "" : stem($0.word) }
        // Plain ASCII text keeps its letters' places, so a word's capitals can be read back.
        var shouted: [String] = []
        if source == .usda, name.utf8.allSatisfy({ $0 < 0x80 }) {
            let bytes = Array(name.utf8)
            // Not in a note of what the entry includes: "(Includes foods for USDA's Food Distribution Program)".
            for (i, token) in found.enumerated() where !stems[i].isEmpty && token.end - token.start > 1 && placed[i].bracket != 2 {
                if bytes[token.start..<token.end].allSatisfy({ $0 >= 0x41 && $0 <= 0x5A }) { shouted.append(stems[i]) }
            }
        }
        self.shouted = shouted
        var titled: [String] = []
        var said: [String] = []
        var runs: [Int] = []
        var noted: [String] = []
        var included: [String] = []
        var parts: [[String]] = [[], [], []]
        var packedRun = -1
        var packed: [String] = []
        var joined: [String: String] = [:]
        for (i, token) in found.enumerated() where !stems[i].isEmpty {
            titled.append(stems[i])
            if i + 1 < found.count, !stems[i + 1].isEmpty, token.end < scalars.count, scalars[token.end] == "-", found[i + 1].start == token.end + 1 {
                joined[stems[i]] = stems[i + 1]
            }
            // "With skin", "without skin" and "baked in skin" say how a fruit or a potato comes,
            // not that the food is its skin, as "Chicken, skin only" is.
            if stems[i] == "skin", i > 0, ["with", "without", "in"].contains(found[i - 1].word) { continue }
            // Nor is a potato's "flesh and skin" a part of it: it's the whole potato, which
            // "raw potatoes" came after a scalloped one for.
            if stems[i] == "skin", i > 1, found[i - 1].word == "and", found[i - 2].word == "flesh" { continue }
            // "Dry roasted" is how nuts are cooked, not a dried food.
            if stems[i] == "dry", i + 1 < found.count, found[i + 1].word == "roasted" { continue }
            // Nor is what a food is packed in what it is: sardines "canned in oil" aren't an oil,
            // nor tomatoes "packed in tomato juice" a tomato juice.
            if i > 1, found[i - 1].word == "in", found[i - 2].word == "canned" || found[i - 2].word == "packed" { packedRun = placed[i].run }
            if placed[i].run == packedRun, placed[i].bracket == 0 {
                packed.append(stems[i])
                continue
            }
            if placed[i].bracket == 0 {
                said.append(stems[i])
                runs.append(placed[i].run)
            } else if placed[i].bracket == 1 {
                noted.append(stems[i])
            } else {
                included.append(stems[i])
            }
            // A note in brackets isn't what the food is filed under: "Chickpeas (garbanzo beans,
            // bengal gram), …" leads with chickpeas.
            if !isNumber(token.word) && placed[i].bracket == 0 {
                if placed[i].part < 3 { parts[placed[i].part].append(stems[i]) }
            }
        }
        let brandWords = words(brand)
        let ownWords: [String]
        if !brand.isEmpty {
            ownWords = brandWords
        } else if !shoutingStart(original, word: true) {
            ownWords = []
        } else {
            ownWords = FoodDatabase.brandWords(name: original, brand: "")
        }
        let own = ownWords.map(stem)
        self.titled = titled
        all = titled + brandWords.map(stem)
        self.ownWords = ownWords
        self.own = own
        chain = brand.isEmpty && !ownWords.isEmpty
        // The brand's words are left out once each: the second "taco" of "TACO BELL, Soft Taco"
        // is the food.
        var owned = own
        let kept = said.indices.filter { i in
            guard let at = owned.firstIndex(of: said[i]) else { return true }
            owned.remove(at: at)
            return false
        }
        self.said = kept.map { said[$0] }
        self.runs = kept.map { runs[$0] }
        self.served = served
        self.alternate = alternate
        self.joint = joint
        self.noted = noted
        self.included = included
        self.packed = packed
        self.joined = joined
        // USDA files some foods under a group: "Fish, salmon".
        let head = makeString(scalars[..<(commas.first ?? scalars.count)]).trimmingCharacters(in: .whitespaces)
        let secondPart = commas.isEmpty ? 0 : (commas.count > 1 ? commas[1] : scalars.count) - commas[0] - 1
        // Not where what follows only says how it comes: "Fish, cooked" and "Fish, baked or
        // broiled" are fish, of no one kind.
        let grouped = groups.contains(head) && secondPart > 0 && !parts[1].allSatisfy { saysHow($0) || partWords.contains($0) }
        // A chain USDA writes before the food leads with the food: pepperoni pizza in
        // `PAPA JOHN'S 14" Pepperoni Pizza`. "McDONALD'S, BIG MAC" keeps the chain, its whole first part.
        var first = parts[0]
        if brand.isEmpty && !own.isEmpty && first.count > own.count && first.starts(with: own) { first.removeFirst(own.count) }
        lead = grouped ? parts[1] : first
        group = grouped ? parts[0] : []
        heads = Array(parts[(grouped ? 1 : 0)...].prefix(commas.count + (grouped ? 0 : 1)).prefix(2))
        branded = !brand.isEmpty || source == .off || (shoutingStart(original, word: true) && shouting(dropMc(firstWord(original))))
        skinAlone =
            source == .usda
            && original.lowercased().split(separator: ",").contains { part in
                let words = part.split(separator: " ")
                guard words.first == "skin", words.last != "removed" else { return false }
                return words.count == 1 || ["only", "and", "from", "with"].contains(words[1]) || words[1].hasPrefix("(")
            }
    }
}

/// A food with its words read, so a ranking reads each food's name once and a catalog can keep it.
struct Entry: Sendable {
    let food: Food
    let text: FoodText
    /// Other names the catalog files the food under: the chains' items FNDDS counts as it
    /// ("McDonald's Chicken McNuggets" for chicken nuggets from fast food).
    let also: [OtherName]
    /// Catalogs repeat products, so listed foods are kept one per name and brand; others by id.
    let key: String
    /// The numbers hang together (see `Food.problem`); worked out once, as catalogs keep entries.
    let plausible: Bool
    /// The catalog files it as a dish of several foods: a sandwich, a casserole, a stir-fry.
    let dish: Bool

    /// `also` is the catalog's other names for the food, one a line.
    init(_ food: Food, also: String = "", dish: Bool = false) {
        self.food = food
        text = FoodText(food)
        self.also = also.isEmpty ? [] : also.split(separator: "\n").map { OtherName(String($0), source: food.source) }
        self.dish = dish
        plausible = food.isPlausible
        key = food.source == .usda || food.source == .off ? "\(food.name)|\(food.brand ?? "")".lowercased() : food.id
    }
}

/// One of a catalog's other names for a food, its words read like a name's.
struct OtherName: Sendable {
    let text: FoodText
    /// The word naming what it is, stemmed: the last, or the last before "with" ("McGriddle" in
    /// "McDonald's McGriddle with Egg"). A search finds the food by this name only when it asks for
    /// that, so "big mac" isn't "McDonald's Big Mac sauce".
    let head: String
    /// The words that join its foods: the "with" of "Spaghetti with meatballs". A search that
    /// joins its words another way names something else by them: "nachos with cheese" isn't
    /// the dip also called "Nacho cheese".
    let joins: Set<String>

    init(_ name: String, source: FoodSource) {
        text = FoodText(name: name, brand: "", source: source)
        joins = joining(name)
        let main = name.range(of: " with ", options: .caseInsensitive).map { String(name[..<$0.lowerBound]) } ?? name
        head = words(main).last.map(stem) ?? ""
    }
}

/// Whether a food is named as the foods typed together. One ends the words the name opens
/// with and each other ends a run after "and" or "with": "Beans and white rice", "Biscuit
/// with gravy", "Beans, baked, canned, with pork". Or its last two runs are just the two:
/// "Salad dressing, home recipe, vinegar and oil". Not a food only named after them:
/// "Crackers, cheese" is no cheese and crackers, nor a "Milk and cereal bar" cereal and
/// milk. Nor one of more foods than those ("Chicken or turkey, rice, corn, and cheese, with
/// gravy" for turkey and cheese), nor is salt joined to a food USDA lists "with salt". The
/// last word may still be on its way: "chicken and ri".
func isJoint(_ text: FoodText, _ foods: [[String]]) -> Bool {
    var runs: [(run: Int, words: [String])] = []
    for (i, word) in text.said.enumerated() {
        if let last = runs.indices.last, runs[last].run == text.runs[i] {
            runs[last].words.append(word)
        } else {
            runs.append((text.runs[i], [word]))
        }
    }
    let joins = { (run: Int) in text.served.contains(run) || text.joint.contains(run) }
    let reads = { (word: String, typed: String) in same(word, stem(typed)) || (alternatives[typed] ?? []).contains { same(word, stem($0)) } }
    let begun = foods.last?.last
    // A note that is just the foods names them together: "Arroz con habichuelas colorados
    // (Rice And Red Beans)".
    let all = Array(foods.joined())
    let noted = { (typed: String) in text.noted.contains { reads($0, typed) || (typed == begun && starts($0, stem(typed))) } }
    if text.noted.count == all.count, all.allSatisfy(noted) { return true }
    let ends = { (said: [String], food: [String]) in
        guard said.count >= food.count else { return false }
        let named = Array(said.suffix(food.count))
        return food.indices.allSatisfy { i in reads(named[i], food[i]) || (i == food.count - 1 && food[i] == begun && starts(named[i], stem(food[i])))
        }
    }
    // The name opens with its first run and the others it gives for that: the turkey of
    // "Chicken or turkey with stuffing".
    let opening = runs.indices.prefix { $0 == 0 || text.alternate.contains(runs[$0].run) }
    for first in foods.indices where opening.contains(where: { ends(runs[$0].words, foods[first]) }) {
        // Where each other food ends a run after "and" or "with".
        var places: [Int] = []
        for other in foods.indices where other != first {
            guard foods[other] != ["salt"],
                let place = runs.indices.first(where: { !opening.contains($0) && joins(runs[$0].run) && ends(runs[$0].words, foods[other]) })
            else { break }
            places.append(place)
        }
        guard places.count == foods.count - 1, let last = places.max() else { continue }
        // What other foods the name has, between those or joined after them: no more than a
        // word. How the food comes, after a comma, is no other food.
        let more = runs.indices.filter { i in
            !opening.contains(i) && !places.contains(i) && !text.alternate.contains(runs[i].run) && (i < last || joins(runs[i].run))
        }.flatMap { runs[$0].words }.filter { !neutral.contains($0) }
        if more.count < 2 { return true }
    }
    guard foods.count == 2 else { return false }
    // The name's last two runs: the lettuce and tomato of a "bacon, lettuce, and tomato"
    // sandwich are two of three. Not both after a "with": a biscuit "with egg and bacon" is
    // a biscuit.
    let whole = runs.filter { !text.alternate.contains($0.run) }
    guard whole.count > 1, joins(whole[whole.count - 1].run), !joins(whole[whole.count - 2].run) else { return false }
    let only = { (said: [String], food: [String]) in said.count == food.count && ends(said, food) }
    let (one, other) = (whole[whole.count - 2].words, whole[whole.count - 1].words)
    return (only(one, foods[0]) && only(other, foods[1])) || (only(one, foods[1]) && only(other, foods[0]))
}

/// What a name says the food comes without, up to the next comma or "with": the sauce and
/// the dressing of "Pasta with vegetables, no sauce or dressing".
func wordsWithout(_ text: FoodText) -> [String] {
    var lacked: [String] = []
    var without = -1
    for (i, w) in text.said.enumerated() {
        if w == "no" || w == "without" {
            without = text.runs[i]
        } else if without >= 0 {
            let run = text.runs[i]
            if run == without || (run == without + 1 && (text.alternate.contains(run) || text.joint.contains(run))) {
                lacked.append(w)
                without = run
            } else {
                without = -1
            }
        }
    }
    return lacked
}

extension FoodText {
    /// The words that can say what kind of food it is: all but what it comes with. An egg
    /// sandwich "on bagel, with bacon" is a sandwich and a bagel, not bacon.
    var kindWords: [String] { said.indices.filter { !served.contains(runs[$0]) }.map { said[$0] } }
}

/// Whether a name has a word of each of the foods typed together.
func hasEach(_ text: FoodText, _ foods: [[String]]) -> Bool {
    foods.allSatisfy { food in
        food.contains { typed in
            text.said.contains { word in same(word, stem(typed)) || (alternatives[typed] ?? []).contains { same(word, stem($0)) } }
        }
    }
}

/// The words of a name that join one food to another.
func joining(_ name: String) -> Set<String> { Set(tokens(name).filter(joinWords.contains)) }

private let joinWords: Set<String> = ["with", "and", "or", "in", "on", "without"]

/// Whether a name may mention "dry heat" or "moist heat", checked without Foundation.
private func mentionsHeat(_ name: String) -> Bool {
    var matched = 0
    let word: [UInt8] = Array("heat".utf8)
    for byte in name.utf8 {
        let lower = byte >= 0x41 && byte <= 0x5A ? byte + 32 : byte
        matched = lower == word[matched] ? matched + 1 : (lower == word[0] ? 1 : 0)
        if matched == word.count { return true }
    }
    return false
}

/// Whether a bracket's note starts with "includes" as a word.
private func startsWithIncludes(_ scalars: [Unicode.Scalar], _ start: Int) -> Bool {
    let word = "includes".unicodeScalars
    guard start + word.count <= scalars.count else { return false }
    for (i, scalar) in word.enumerated() where scalars[start + i] != scalar { return false }
    let after = start + word.count
    guard after < scalars.count else { return true }
    let next = scalars[after].value
    return !((next >= 0x30 && next <= 0x39) || (next >= 0x61 && next <= 0x7A) || (next >= 0x41 && next <= 0x5A) || next == 0x5F)
}

/// A quick test that a name's first part (or first word) could be all capitals: no lower-case
/// ASCII letter except the c of a "Mc". Most names fail at once.
private func shoutingStart(_ name: String, word: Bool = false) -> Bool {
    var previous: UInt8 = 0x20
    var beforePrevious: UInt8 = 0x20
    for byte in name.utf8 {
        if byte == UInt8(ascii: ",") || (word && (byte == 0x20 || (byte >= 0x09 && byte <= 0x0D))) { return true }
        if byte >= 0x61 && byte <= 0x7A {
            let afterM = byte == UInt8(ascii: "c") && previous == UInt8(ascii: "M")
            let wordStart =
                !(beforePrevious >= 0x41 && beforePrevious <= 0x5A || beforePrevious >= 0x61 && beforePrevious <= 0x7A
                || beforePrevious >= 0x30 && beforePrevious <= 0x39 || beforePrevious == 0x5F)
            if !(afterM && wordStart) { return false }
        }
        beforePrevious = previous
        previous = byte
    }
    return true
}

/// `\b(?:dry|moist) heat\b` → "cooked".
private func cookedHeat(_ name: String) -> String {
    var result = name
    for phrase in ["dry heat", "moist heat"] {
        var search = result.startIndex..<result.endIndex
        while let found = result.range(of: phrase, options: .caseInsensitive, range: search) {
            let before = found.lowerBound == result.startIndex ? nil : result[result.index(before: found.lowerBound)]
            let after = found.upperBound == result.endIndex ? nil : result[found.upperBound]
            let boundary = { (c: Character?) in c.map { !($0.isLetter || $0.isNumber || $0 == "_") } ?? true }
            if boundary(before) && boundary(after) {
                result.replaceSubrange(found, with: "cooked")
                search = result.startIndex..<result.endIndex
            } else {
                search = found.upperBound..<result.endIndex
            }
        }
    }
    return result
}

private func firstWord(_ name: String) -> String {
    String(name.prefix { !($0 == "," || $0.isWhitespace) })
}

private func dropMc(_ word: String) -> String { word.hasPrefix("Mc") ? String(word.dropFirst(2)) : word }

/// All capitals, with at least two capital letters: "DOMINO'S", "T.G.I.".
private func shouting(_ text: String) -> Bool {
    text == text.uppercased() && text.unicodeScalars.filter { $0.value >= 0x41 && $0.value <= 0x5A }.count >= 2
}

/// The brand's words, including a restaurant or brand USDA writes first in capitals: "McDONALD'S,
/// BIG MAC", `PAPA JOHN'S 14" Pepperoni Pizza`, "SILK Chocolate, soymilk".
func brandWords(name: String, brand: String) -> [String] {
    if !brand.isEmpty { return words(brand) }
    var lead: [Substring] = []
    for word in name.prefix(while: { $0 != "," }).split(whereSeparator: \.isWhitespace) {
        guard shouting(dropMc(String(word))) else { break }
        lead.append(word)
    }
    return words(lead.joined(separator: " "))
}

/// Restaurant and packaged foods, which suit a seen food only when its brand is known.
func isBranded(_ food: Food) -> Bool { FoodText(food).branded }

// MARK: - Coverage

/// A word as searched: its forms and its corrections.
private struct WordForms {
    let word: String
    let options: [String]
    let fixes: [String]
    let fixParts: [[String]]
    /// For a word the catalogs barely know: the word, to compare with a food's own.
    let misspelling: Misspelling?
    /// The fixes that are the word written the other way, as one word or apart.
    let respelt: [[String]]
    /// The word is finished and is that word: never the start of a longer one.
    let finished: Bool
    /// The forms of the whole word it's probably on its way to, which is finished as it is.
    let likely: [String]

    /// `likely` is the whole word a half-typed one is probably on its way to: a food that has it
    /// has the word, not just a longer one that starts the same ("chees" is cheese before a
    /// cheeseburger).
    init(
        _ word: String, prefix: Bool, fixes: Fixes, doubted: Bool = false, respelt: Set<String> = [], likely: String? = nil,
        finished: Bool = false
    ) {
        self.word = word
        self.finished = finished
        var options = prefix ? searchForms(word) : forms(word)
        if let likely { for form in searchForms(likely) where !options.contains(form) { options.append(form) } }
        self.options = options
        self.likely = likely.map(searchForms) ?? []
        self.fixes = fixes[word] ?? []
        fixParts = self.fixes.map { $0.split(separator: " ").map(String.init) }
        misspelling = doubted ? Misspelling(word) : nil
        self.respelt = self.fixes.filter(respelt.contains).map { $0.split(separator: " ").map(String.init) }
    }
}

/// How well a food's name covers what was said.
struct Coverage {
    var name: Double
    /// Words said that the food doesn't have, even as corrected, and how many of them say what
    /// the food is.
    var missing: Int
    var lacking: Int
    /// The food's first two parts, inverted as USDA writes them, name exactly what was said:
    /// "Oil, olive" for olive oil.
    var named: Bool
    var partial: Int
    var head: Bool
    /// The word naming the food is in the name only to name another food after it: "cake" in
    /// Celebration Cake Pretzels, "peanut butter" in Peanut Butter Cups.
    var modifies: Bool
    var fixed: Int
    var usual: Bool
    var typical: Bool
    /// Words for a less common form, one made of something else counting half as much again.
    var variations: Double
    /// The words counted in `variations` and `others` that come before the word naming the food:
    /// "pork" in "Pork, cured, bacon", "salad dressing" in "Salad dressing, mayonnaise".
    var filed: [String]
    /// The words counted in `variations`.
    var forms: [String]
    /// Every word said is in one part of the name.
    var together: Bool
    /// What the food is named after instead, where a word said to describe it comes only in a
    /// later part of the name: "potato" for "egg salad" and "Potato salad with egg".
    var added: [String]
    /// The word naming the food is only in what this food comes with: the "cheese" of a chicken
    /// sandwich "with cheese".
    var garnish: Bool
    /// How many of the words said to come with the food or about it this food has.
    var sides: Int
    /// The food leads with what was said to come with the one named.
    var served: Bool
    /// The name says the food comes with everything it was said to, after a "with" of its own,
    /// and little else: "Tea, hot, with milk", not a latte "with non-dairy milk" nor fried rice
    /// "with chicken".
    var comes = false
    /// How near the food's way of cooking is to one said that it doesn't list (see `Ease`).
    var near: Double
    /// The food leads with what was said once what its first part says it comes with is left
    /// out: "Lasagna with meat" leads with lasagna. And by those words whole.
    var heads: Bool
    var headsWhole: Bool
    /// What was said names the kind of thing the food's name opens with: a turkey sandwich is
    /// a sandwich.
    var kind: Bool
    var others: Int
    /// The words counted in `others`, and the ones of them the name adds after "with" or "and":
    /// other foods the dish comes with.
    var extra: [String]
    var mixed: [String]
    /// The name says nothing but what was said.
    var exact: Bool
    /// The name has two words said side by side the other way round, and not also as said:
    /// "Chocolate milk" for "milk chocolate". The last word says what a food is, so that's
    /// another food. A comma between them is USDA's way of filing, which says nothing.
    var backwards: Bool
    /// The name has two words said side by side as they were said: "Candies, milk chocolate".
    var asSaid: Bool
    var notes: Int
    var leads: Bool
    var brand: Bool?
    var cooked: Int
    var fried: Bool
}

/// The words that were said, read once for every food they are compared with. In a search the
/// words may be half typed, so a longer word also counts ("chic" finds chicken), below the word
/// itself, and a word found only in the brand counts half: "wheats" names a cereal, not the brand
/// Wheaty. With `nameOnly`, the words describe the product and only its name is read.
struct CoverageQuery {
    fileprivate let target: [WordForms]
    fileprivate let prefix: Bool
    fileprivate let nameOnly: Bool
    fileprivate let mentioned: [String]
    /// Words a food has whole, never as the start of a longer one: the same words as labels also
    /// write them, as one word or apart, and a size typed with the food.
    fileprivate let entire: [String]
    fileprivate let level: Bool
    fileprivate let brand: [WordForms]
    fileprivate let usual: Usual?
    /// For each word, how a food may do without it; nil for a word every food asked for has.
    fileprivate let ease: [Ease?]
    /// What was said to come with the food or about it, stemmed: words a food has by being
    /// asked for, and none it lacks.
    fileprivate let sides: [String]
    /// The same with the two words of one everyday food together, which count only with each
    /// other: toast with butter isn't toast with peanut butter, nor chocolate ice cream ice
    /// cream with chocolate syrup.
    fileprivate let sideFoods: [[String]]
    /// The ones of those that are other foods served with it.
    fileprivate let beside: [String]

    init(
        seen: Named, target words: [String], prefix: Bool = false, fixes: Fixes = [:], nameOnly: Bool = false,
        doubted: Set<String> = [], respelt: Set<String> = [], eases: [String: Ease] = [:], sides: [String] = [], beside: [String] = []
    ) {
        self.prefix = prefix
        self.nameOnly = nameOnly
        ease = eases.isEmpty ? [] : words.map { eases[$0] }
        self.sides = sides.map(stem)
        var foods: [[String]] = []
        for (i, side) in sides.enumerated() {
            if i > 0, foods[foods.count - 1].count == 1, EverydayPhrases.isName([sides[i - 1], side]) {
                foods[foods.count - 1].append(stem(side))
            } else {
                foods.append([stem(side)])
            }
        }
        sideFoods = foods
        self.beside = beside.map(stem)
        // A typed search's last word may only be begun.
        let likely = prefix ? EverydayPhrases.likely(words) : nil
        target = words.enumerated().map { i, word in
            WordForms(
                word, prefix: prefix, fixes: fixes, doubted: doubted.contains(word), respelt: respelt, likely: i == words.count - 1 ? likely : nil,
                // An everyday food's own word with another typed after it is that word: the
                // "baby" of "baby spinach" isn't babyfood begun, nor the "egg" of "egg salad"
                // eggplant, the "grape" of "grape juice" grapefruit or the "ham" of "ham
                // sandwich" a hamburger. Not "mac", which people type for macaroni.
                // So is one typed alone, once it's whole: "curry" isn't currants begun. After
                // other words the last may still be half of one: the "oat" of "chobani extra
                // creamy oat" is on its way to Oatmilk.
                // And two letters with a word after them are a word: the "dr" of "dr pepper"
                // isn't dried begun. Not "mc", which starts a name typed apart ("mc flurry").
                // A word after only how the food comes is as good as alone: the "corn" of
                // "fresh corn" isn't cornsalad begun, nor the "lamb" of "cooked lamb" lambsquarters.
                finished: prefix && word != "mac"
                    && (i < words.count - 1
                        ? EverydayPhrases.isWord(stem(word)) || isShortWord(word)
                        : words.dropLast().allSatisfy(saysHow) && EverydayPhrases.isWritten(word))
            )
        }
        var mentioned: [String] = []
        var entire: [String] = []
        for word in target {
            // A word as labels also write it is that word and no start of another: the "meat" of
            // "meat balls", for "meatballs", doesn't make "meatless" a word that was asked for.
            let whole =
                word.fixes.filter(respelt.contains).flatMap { $0.split(separator: " ").map(String.init) } + (word.finished ? word.options : [])
            for form in whole where !entire.contains(form) { entire.append(form) }
            let started =
                (word.finished ? [] : word.options)
                + word.fixes.filter { !respelt.contains($0) }.flatMap { $0.split(separator: " ").map(String.init) }
            for form in started where !mentioned.contains(form) { mentioned.append(form) }
        }
        let said = FoodDatabase.words(seen.name)
        // A size typed with a food isn't searched for, but a name that has it was asked for by
        // it: the "small" of "cottage cheese small curd".
        if prefix {
            for word in said where countWords.contains(word) && !words.contains(word) && !entire.contains(stem(word)) { entire.append(stem(word)) }
        }
        for side in self.sides where !entire.contains(side) { entire.append(side) }
        self.mentioned = mentioned
        self.entire = entire
        level = words.contains(where: isNumber)
        brand = FoodDatabase.words(seen.brand).map { WordForms($0, prefix: prefix, fixes: fixes) }
        // A corrected word asks for the same everyday variety as the word it corrects.
        // And a word with another spelling for the same as that one: "yoghurt" is yogurt.
        let asked = said + said.flatMap { alternatives[$0] ?? [] } + fixValues(fixes, order: said) + (likely.map { [$0] } ?? [])
        // A two-word food's, else the first word's that the others don't rule out: "beef stew" is
        // a stew, not ground beef.
        // Read through a word's one correction: "tomao paste" is tomato paste.
        // Not through the same words written as one: "peanut butter" isn't read "peanutbutter".
        var read = said.map { word in
            fixes[word].flatMap { $0.count == 1 && !$0[0].contains(" ") && !respelt.contains($0[0]) ? $0[0] : nil } ?? stem(word)
        }
        if let likely, !read.isEmpty { read[read.count - 1] = stem(likely) }
        let phrased = usualPhrases.first { phrase in
            read.indices.contains { $0 + phrase.words.count <= read.count && Array(read[$0..<($0 + phrase.words.count)]) == phrase.words }
        }
        self.usual =
            phrased.flatMap { asked.contains(where: $0.usual.others.contains) ? nil : $0.usual }
            ?? asked.lazy.compactMap { usualVarieties[stem($0)] }.first { usual in !asked.contains(where: usual.others.contains) }
    }

    init(seen: Named) { self.init(seen: seen, target: nameWords(seen.name)) }

    /// Whether the words name a food with an everyday variety.
    var asksUsual: Bool { usual != nil }

    /// The kinds the everyday variety isn't: beef and veal for ribs.
    var unusual: [String] { usual?.otherStems ?? [] }

    @inline(__always) private func fits(_ w: String, _ form: String) -> Bool {
        isNumber(form) ? w == form : same(w, form) || (prefix && length(form) > 1 && starts(w, form))
    }

    /// Whether one of a food's words is this one, as said or as its correction: the "mayonnaise"
    /// of "Salad dressing, mayonnaise" for "mayonnise".
    @inline(__always) private func reads(_ w: String, as word: WordForms) -> Bool {
        word.options.contains { word.finished ? same(w, $0) : fits(w, $0) } || word.fixParts.contains { $0.count == 1 && starts(w, $0[0]) }
    }

    /// Whether one of a food's words is one the search asked for.
    @inline(__always) private func asked(_ w: String) -> Bool {
        mentioned.contains { fits(w, $0) } || entire.contains { same(w, $0) }
    }

    @inline(__always) private func exact(_ w: String, _ form: String) -> Bool {
        prefix || isNumber(form) ? w == form : same(w, form)
    }

    /// The word itself, or the same word as labels also write it: "redbull" for the "red" and the
    /// "bull" of "red bull", "pop" and "corn" for "popcorn".
    private func whole(_ word: WordForms, _ found: [String]) -> Bool {
        word.options.contains { form in found.contains { word.finished ? same($0, form) : exact($0, form) } }
            // The word it's on its way to in another of its endings, as when it's typed whole:
            // "toas" is toast, and toasted bread is toast.
            || word.likely.contains { form in found.contains { same($0, form) } }
            || word.respelt.contains { parts in parts.allSatisfy { part in found.contains { same($0, part) } } }
    }

    private func literal(_ word: WordForms, _ found: [String], whole: Bool) -> Bool {
        whole || (prefix && !word.finished && word.options.contains { form in found.contains { fits($0, form) } })
    }

    /// A fix is a word's start ("chick") or, for a word typed without its space, a phrase. A word
    /// the catalogs barely know is also one of the food's own words a typo or two from it.
    private func fixed(_ word: WordForms, _ found: [String]) -> Bool {
        word.fixParts.contains { parts in
            parts.indices.allSatisfy { i in
                found.contains { i == parts.count - 1 ? starts($0, parts[i]) : same($0, parts[i]) }
            }
        } || word.misspelling?.reads(found) == true
    }

    private func branded(_ word: WordForms, _ titled: [String]) -> Bool {
        prefix && !nameOnly && !word.options.contains { form in titled.contains { word.finished ? same($0, form) : fits($0, form) } }
            && !word.fixParts.contains { parts in titled.contains { starts($0, parts[0]) } }
    }

    private func has(_ word: WordForms, _ found: [String]) -> Bool {
        literal(word, found, whole: whole(word, found)) || fixed(word, found)
    }

    /// `own` is how many of the first words said name the food's own brand: found there, they count
    /// in full.
    func cover(_ text: FoodText, own: Int = 0) -> Coverage {
        let found = nameOnly ? text.titled : text.all
        var total = 0.0
        var hits = 0.0
        var partial = 0
        var fixedCount = 0
        var missing = 0
        var lacking = 0
        var head = false
        // The words this food does without: a way of cooking near enough to its own, a cut it
        // leaves unsaid. The rest are read as if they were all that was said.
        // USDA leads with the food itself: "Tomatoes, red, ripe, raw", not "Canadian bacon".
        // "Soy sauce made from soy" leads with soy sauce too: how it's made says no other food.
        // So does "Cereals ready-to-eat" with cereal, and a group typed alone by its own name
        // leads every food in it: "nuts".
        // A food that leads with what was said to come with the one named is that food, not
        // the one named: the sauce of "pasta with marinara sauce", the dressing of a salad.
        // Not where the name goes on to the food named, which the other only says more of: a
        // turkey sandwich is a sandwich with turkey, cheese fries are fries with cheese. Nor
        // where it has both, joined either way: "Pasta with sauce", "Rice and beans". A label
        // that joins two is its own product: a "Grilled cheese & tomato soup" flavour.
        var served = false
        if !beside.isEmpty {
            let first = text.said.indices.filter { !text.served.contains(text.runs[$0]) && text.lead.contains(text.said[$0]) }
            if let last = first.last(where: { i in beside.contains { same(text.said[i], $0) } }) {
                let run = text.runs[last]
                let named = { (i: Int) in asked(text.said[i]) && !beside.contains { same(text.said[i], $0) } }
                served =
                    text.branded
                    || !first.contains { i in
                        named(i)
                            && ((i > last && text.runs[i] == run) || (text.runs[i] == run - 1 && text.joint.contains(run))
                                || (text.runs[i] == run + 1 && text.joint.contains(run + 1)))
                    }
            }
        }
        // Another name for the food said, on the other side of an "or", is no word it wasn't
        // asked by: the "noodles" of "Macaroni or noodles with cheese", the "turkey" of
        // "Chicken or turkey salad" and its "chicken" for a turkey salad. The second name is as
        // long as the first, and what follows it is said of both: the "salad", and the
        // "parmigiana" of "Chicken or turkey parmigiana", which isn't chicken.
        // By the word whole, as said or as corrected: the "cups" of "peanut butter cups"
        // aren't the cupcake of "Cake or cupcake", nor is "cheeese" a cheeseburger.
        let wholly = { (w: String) in
            self.target.contains { word in
                word.options.contains { same(w, $0) } || word.fixParts.contains { $0.contains { same(w, $0) } }
                    || word.respelt.contains { $0.contains { same(w, $0) } }
            } || self.entire.contains { same(w, $0) }
        }
        var spare: [String] = []
        if !text.alternate.isEmpty {
            var words: [Int: [String]] = [:]
            for (i, w) in text.said.enumerated() { words[text.runs[i], default: []].append(w) }
            for run in text.alternate {
                guard let after = words[run], let before = words[run - 1], let first = after.first, let last = before.last else { continue }
                // What comes before the first name is said of both too: a "Rice dessert or
                // salad with fruit" is a rice salad, no fruit salad.
                let length = min(before.count, after.count)
                if wholly(last) {
                    spare += after.prefix(length).filter { !asked($0) }
                } else if wholly(first) {
                    spare += before.suffix(length).filter { !asked($0) }
                }
            }
        }
        let leading = { (word: String) in self.asked(word) || leadFillers.contains(word) || spare.contains(word) }
        let leads =
            !served
            && ((text.lead.contains(where: asked) && text.lead.prefix { $0 != "made" }.allSatisfy(leading))
                || (target.count == 1 && (text.group.first.map(asked) ?? false)))
        var heads = leads
        // What was said is the kind of thing the name opens with: the "sandwich" of "Turkey
        // sandwich on white" and of "Chicken or turkey sandwich", not the "parmesan" of
        // "Eggplant parmesan casserole".
        var kind = false
        if let opening = text.runs.first {
            let named = text.said.indices.prefix { text.runs[$0] == opening || text.alternate.contains(text.runs[$0]) }
            kind = named.last.map { wholly(text.said[$0]) } ?? false
        }
        // And by whole words, which is how a dish is told from a food its name only starts
        // like: "ch" on its way to chicken isn't a chimichanga's.
        var headsWhole = false
        if !served {
            let first = text.said.indices.filter { !text.served.contains(text.runs[$0]) }.map { text.said[$0] }.filter(text.lead.contains)
            if !leads, !text.served.isEmpty { heads = first.contains(where: asked) && first.allSatisfy(leading) }
            headsWhole =
                heads && first.contains(where: wholly) && first.allSatisfy { wholly($0) || leadFillers.contains($0) || spare.contains($0) }
        }
        var spared: [Bool] = []
        var near = 0.0
        // The kinds of heat said that this food is spared the word for.
        var heated = Set<Heat>()
        if !ease.isEmpty {
            let lacks = target.indices.map { ease[$0] != nil && !has(target[$0], found) }
            // "Raw" and "fresh" are only left unsaid by a food filed under what was asked:
            // fresh fruit isn't every raw food that has "fruit" in its name.
            spared = target.indices.map { lacks[$0] && ease[$0]?.fits(text) == true && (ease[$0]?.raw != true || leads) }
            for i in target.indices where spared[i] {
                near += ease[i]?.nearness(text) ?? 0
                if let kind = ease[i]?.heat { heated.insert(kind) }
            }
            // Otherwise it's no word a food lacks, as it only says how the food comes. A cut
            // already is one.
            for i in target.indices where lacks[i] && ease[i]?.listed == true {
                let said = stem(target[i].word)
                if neutral.contains(said) || fluffWords.contains(said) { lacking += 1 }
            }
            if !spared.contains(true) { spared = [] }
        }
        let naming = spared.isEmpty ? target.count - 1 : (spared.lastIndex(of: false) ?? target.count - 1)
        for (i, word) in target.enumerated() where spared.isEmpty || !spared[i] {
            // The last word names the food ("coffee" in "black coffee"); earlier words describe it.
            let weight = i == naming ? 2.0 : 1.0
            total += weight
            let isWhole = whole(word, found)
            let isLiteral = literal(word, found, whole: isWhole)
            let isFixed = !isLiteral && fixed(word, found)
            let has = isLiteral || isFixed
            let inBrand = has && i >= own && branded(word, text.titled)
            // A typed word naming the food that the name has only in what it "(includes …)" names
            // another food: a plain bagel that includes poppy seed ones isn't "pop".
            // Nor does a word that only a note of what's in the food has, while another word
            // said is in its name: "Vegetables, mixed (corn, lima beans, peas, green beans,
            // carrots)" isn't mixed greens. A note that is the whole of what was said is another
            // name for the food ("Chickpeas (garbanzo beans, bengal gram)"), and a word or two
            // in brackets say more of the same food ("Whole Milk (Organic)").
            let listed =
                has && i == naming && text.noted.count > 2 && !self.has(word, text.said + text.own + text.included)
                && target.indices.contains { j in j != i && self.has(target[j], text.said) && !self.has(target[j], text.noted) }
            // Nor one that is only what the food is packed in: tomatoes "packed in tomato
            // juice" aren't tomato juice.
            let aside =
                listed
                || (has && i == naming && (!text.included.isEmpty || !text.packed.isEmpty) && !self.has(word, text.said + text.noted + text.own))
            if has {
                hits += weight * (inBrand || aside ? 0.5 : 1)
                // So it's another food where some food is named by the word: white bread that
                // "(includes soft bread crumbs)" isn't bread crumbs.
                if aside { lacking += 1 }
            } else {
                missing += 1
                // A word that says what the food is, not how it comes ("fresh", "organic"). A
                // group USDA files foods under says what it is when it's said: fish and chips
                // aren't potato chips.
                let said = stem(word.word)
                if (!neutral.contains(said) && !fluffWords.contains(said)) || groupWords.contains(said) { lacking += 1 }
            }
            if !isWhole && isLiteral { partial += 1 }
            if isFixed { fixedCount += 1 }
            // The word that names the food is in its name: "wheats" in "Shredded Bite Size Wheats".
            if i == naming { head = has && !inBrand && !aside }
        }
        let needed = spared.isEmpty ? target : target.indices.filter { !spared[$0] }.map { target[$0] }
        var backwards = false
        var asSaid = false
        if needed.count > 1 {
            // By the words as typed: the "semisweet" that chocolate "chips" are read as isn't one.
            let places = needed.map { word in text.said.indices.filter { same(text.said[$0], stem(word.word)) } }
            for i in places.indices.dropLast() {
                let beside = { (a: Int, b: Int) in a + 1 == b && text.runs[a] == text.runs[b] }
                let inOrder = places[i].contains { a in places[i + 1].contains { beside(a, $0) } }
                asSaid = asSaid || inOrder
                backwards = backwards || (!inOrder && places[i + 1].contains { b in places[i].contains { beside(b, $0) } })
            }
        }
        var variations = 0.0
        var others = 0
        var extra: [String] = []
        var mixed: [String] = []
        // Where the name last has the word naming the food, which is where it says what it is.
        let named = needed.last.flatMap { last in text.said.lastIndex { reads($0, as: last) } }
        var filed: [String] = []
        // The ones of those in the same part of the name as the word naming the food, which
        // name it after another: the "potato" of "Potato salad with egg".
        var alongside: [String] = []
        var forms: [String] = []
        // USDA's "mature seeds" are dried beans and lentils as usually cooked, not the seeds of a plant.
        let legume = text.said.contains("mature") || text.said.contains("immature")
        for (i, w) in text.said.enumerated() where !isNumber(w) && !(level && fatWords.contains(w)) && !asked(w) {
            if w == "seed" && legume { continue }
            if spare.contains(w) { continue }
            // USDA's "composite of trimmed retail cuts" is the meat, whichever cut: no word a
            // search for pork didn't ask for. Cold cuts are another matter.
            if w == "cut", i > 0, text.said[i - 1] == "retail" { continue }
            // Nor is the food's own way of cooking, the same kind as the one said, a less common
            // form of it: stewed chicken for "boiled chicken".
            if variationWords.contains(w), let kind = heats[w], heated.contains(kind) { continue }
            // The usual kind's own word isn't one that wasn't asked for: tuna is canned, nuts are mixed.
            if let usual = self.usual, usual.markStems.contains(w) { continue }
            if variationWords.contains(w) {
                // As far off as a label's food is from a plain one: the real thing by any brand comes first.
                variations += insteadWords.contains(w) ? 3 : 1
                forms.append(w)
            } else if i > 0,
                (text.said[i - 1] == "no" && w != "dressing" && w != "sauce" && !neutral.contains(w))
                    || (w == "white" && text.said[i - 1] == "egg") || (w == "fat" && text.said[i - 1] == "separable")
            {
                // A dish without what it usually has is the less common one: a chili dog with
                // "no bun", a gumbo with "no rice". Not a salad's dressing, which is logged apart.
                // So is one made with egg whites, where "white" says little of bread, and the
                // fat trimmed off a cut, which isn't the meat: "Pork, fresh, separable fat".
                variations += 1
                forms.append(w)
            } else if !neutral.contains(w) {
                others += 1
                extra.append(w)
                if text.served.contains(text.runs[i]) || text.joint.contains(text.runs[i]) { mixed.append(w) }
            } else {
                continue
            }
            if let named, i < named {
                filed.append(w)
                if text.runs[i] == text.runs[named], !variationWords.contains(w) { alongside.append(w) }
            }
        }
        let notes = text.noted.filter { w in !neutral.contains(w) && !asked(w) }.count
        // A people's traditional food, noted as theirs, is a kind of its own.
        if text.noted.contains(where: { traditionWords.contains($0) && !asked($0) }) { variations += 1 }
        // Sunflower seed butter is named after the seeds, though USDA files it under "Seeds".
        var modifies = false
        if let at = named {
            modifies = text.said.indices[(at + 1)...].contains { i in
                let w = text.said[i]
                return text.runs[i] == text.runs[at] && formWords.contains(w) && !asked(w)
            }
            // A word joined to the food's by a hyphen names what it is: a "Custard-apple" is a
            // fruit, "taco-flavor" chips are chips.
            if !modifies, let other = text.joined[text.said[at]], !asked(other) { modifies = true }
            // What follows the food after "or" is said of both: "Taco or tostada salad" is a
            // salad, where "Bagel or roll" is a bagel.
            let other = text.said.indices.filter { text.runs[$0] == text.runs[at] + 1 }
            if !modifies, other.count > 1, let last = other.last, text.alternate.contains(text.runs[last]), at + 1 == other[0] {
                modifies = formWords.contains(text.said[last]) && !asked(text.said[last])
            }
        }
        // Whether the name has the words in one part of it: "Nuts, coconut milk" for "coconut
        // milk", where a coconut cream pudding "prepared with whole milk" has both and is neither.
        var together = false
        var added: [String] = []
        if needed.count > 1, missing == 0 {
            let places = needed.map { word in text.said.indices.filter { reads(text.said[$0], as: word) } }
            if let first = places.first {
                together = first.contains { at in places.allSatisfy { $0.contains { text.runs[$0] == text.runs[at] } } }
            }
            // A word describing the food comes only in a later part than the food's own, which
            // is named after something else: the "egg" of "Potato salad with egg".
            if let named, places.dropLast().contains(where: { found in !found.isEmpty && found.allSatisfy { text.runs[$0] > text.runs[named] } }) {
                added = alongside
            }
        } else if target.count > 1, missing == 0 {
            // One word of several is all this food needs, and it has it.
            together = true
        }
        // The word naming the food is only in what the food comes with, and its first part has
        // nothing that was said: a "Chicken fillet sandwich, grilled, …, with cheese" isn't
        // grilled cheese.
        var garnish = false
        if missing == 0, !text.served.isEmpty, let last = needed.last, let first = text.runs.first {
            let places = text.said.indices.filter { reads(text.said[$0], as: last) }
            garnish =
                !places.isEmpty && places.allSatisfy { text.served.contains(text.runs[$0]) }
                && !text.said.indices.contains { text.runs[$0] == first && asked(text.said[$0]) }
        }
        // USDA's inverted name for exactly what was said: "Oil, olive" for olive oil, "Rice, white"
        // for white rice; not "Oil, corn, peanut, and olive", nor "Chicken breast, roll".
        var inverted = false
        if missing == 0, text.heads.count == 2 {
            let both = text.heads[0] + text.heads[1]
            // Of two words or more, the one naming the food is the one USDA puts first: "Milk,
            // chocolate" is chocolate milk, not milk chocolate.
            // By all the words it has, or by the ones that say what the food is where another
            // says only how it comes: "Carrots, baby" for baby carrots, and "Cheese, parmesan,
            // grated" for grated parmesan cheese as "Cheese, parmesan, shredded" is.
            let inverts = { (words: [WordForms]) in
                !words.isEmpty && !words.allSatisfy { self.has($0, text.heads[0]) } && words.allSatisfy { self.has($0, both) }
                    && (words.count == 1 || (words.last.map { self.has($0, text.heads[0]) } ?? false))
            }
            let what = ease.isEmpty ? needed : target.indices.filter { ease[$0] == nil }.map { target[$0] }
            inverted = both.allSatisfy(asked) && (inverts(needed) || (what.count < needed.count && inverts(what)))
        }
        // By the name's own words, not a note of what else it includes: white bread "(includes
        // soft bread crumbs)" is still white bread.
        let kinds = nameOnly ? text.said + text.noted : text.said + text.noted + text.own
        let usual =
            self.usual.map { usual in
                kinds.contains { w in usual.markStems.contains { same(w, $0) } }
                    && !kinds.contains { w in usual.otherStems.contains { same(w, $0) } }
            } ?? false
        let fried = found.contains("fried") && !mentioned.contains("fried") && !entire.contains("fried")
        let lacked = sides.isEmpty || served ? [] : wordsWithout(text)
        return Coverage(
            name: total > 0 ? hits / total : 0,
            missing: missing,
            lacking: lacking,
            named: inverted,
            partial: partial,
            head: head,
            modifies: modifies,
            fixed: fixedCount,
            usual: usual,
            typical: found.contains(where: typicalWords.contains),
            variations: variations,
            filed: filed,
            forms: forms,
            together: together,
            added: added,
            garnish: garnish,
            sides: sides.isEmpty || served
                ? 0
                : sideFoods.filter { $0.allSatisfy { side in found.contains { same($0, side) } && !lacked.contains { same($0, side) } } }
                    .reduce(0) { $0 + $1.count },
            served: served,
            comes: !sides.isEmpty && !served && variations == 0 && !fried
                && extra.filter { w in !sides.contains { same(w, $0) } }.count < 2
                && sides.allSatisfy { side in
                    !lacked.contains { same($0, side) }
                        && text.said.indices.contains { text.served.contains(text.runs[$0]) && same(text.said[$0], side) }
                },
            near: near,
            heads: heads,
            headsWhole: headsWhole,
            kind: kind,
            others: others,
            extra: extra,
            mixed: mixed,
            exact: missing == 0 && partial == 0 && text.noted.isEmpty && text.said.allSatisfy(wholly),
            backwards: backwards,
            asSaid: asSaid,
            notes: notes,
            leads: leads,
            brand: brand.isEmpty ? nil : brand.allSatisfy { has($0, found) },
            // A food spared a way of cooking is a cooked one, however it says so: "stewed".
            cooked: found.contains(where: cookedWords.contains) || !heated.isEmpty ? 1 : found.contains("raw") ? -1 : 0,
            // Frying adds fat; roasted or boiled is the plainer cooked form.
            fried: fried)
    }
}

/// A fix's values in the order their words were said, then any others.
func fixValues(_ fixes: Fixes, order: [String]) -> [String] {
    guard !fixes.isEmpty else { return [] }
    var keys: [String] = []
    for word in order where fixes[word] != nil && !keys.contains(word) { keys.append(word) }
    keys += fixes.keys.filter { !keys.contains($0) }.sorted()
    return keys.flatMap { fixes[$0]! }
}

func coverage(
    _ seen: Named, _ food: Food, target: [String]? = nil, prefix: Bool = false, fixes: Fixes = [:],
    nameOnly: Bool = false
) -> Coverage {
    CoverageQuery(seen: seen, target: target ?? nameWords(seen.name), prefix: prefix, fixes: fixes, nameOnly: nameOnly)
        .cover(FoodText(food))
}

// MARK: - Profiles

/// A kind of food's usual energy and macros per 100 g or ml: the middle of the foods that name it
/// and how far they stray. Calories are on a log scale, since a kind of food sets its density
/// rather than its exact calories.
struct Profile: Equatable {
    var center: [Double]
    var spread: [Double]

    /// How far another kind of food's middle is from this one's, in the wider of their spreads:
    /// under 2.25, as `likeness` has it, they are the same kind of food.
    func distance(to other: Profile) -> Double {
        var sum = 0.0
        for d in center.indices { sum += pow((center[d] - other.center[d]) / max(spread[d], other.spread[d]), 2) }
        return (sum / Double(center.count)).squareRoot()
    }
}

private func point(_ food: Food) -> [Double]? {
    food.basis == .serving
        ? nil
        : [log(max(0, food.nutrients.kcal) + 10), food.nutrients.protein, food.nutrients.carbs, food.nutrients.fat]
}

/// The least spread a profile allows: labels round, and recipes for one food differ this much.
private let leastSpread = [0.15, 3, 6, 3]

private func middle(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let half = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[half] : (sorted[half - 1] + sorted[half]) / 2
}

/// The profile of some foods, or nil for too few to say what such a food is like.
func profile(_ foods: [Food]) -> Profile? {
    let points = foods.compactMap(point)
    guard points.count >= 4 else { return nil }
    let center = leastSpread.indices.map { d in middle(points.map { $0[d] }) }
    let spread = leastSpread.indices.map { d in max(leastSpread[d], 1.4826 * middle(points.map { abs($0[d] - center[d]) })) }
    return Profile(center: center, spread: spread)
}

/// The profile of what words name, from the foods named little more than them: "peanut butter"
/// is the spread, not the cups and cookies named after it.
func profile(for product: [String], _ entries: [Entry], fixes: Fixes = [:], respelt: Set<String> = []) -> Profile? {
    let query = CoverageQuery(
        seen: Named(name: product.joined(separator: " "), brand: ""), target: product, prefix: true,
        fixes: fixes, nameOnly: true, respelt: respelt)
    var named: [Food] = []
    for entry in entries {
        let match = query.cover(entry.text)
        if match.name == 1 && Double(match.others) + match.variations <= 1 { named.append(entry.food) }
        if named.count == 12 { break }
    }
    return profile(named)
}

/// How much a food is like a profile's kind: 1 alike, 0 unsure, -1 another kind of food. A store's
/// shredded wheat cereal is like Mini-Wheats; its wheat bread, with half the carbs, is not.
func likeness(_ food: Food, _ kind: Profile) -> Double {
    guard let p = point(food) else { return 0 }
    var sum = 0.0
    for d in p.indices { sum += pow((p[d] - kind.center[d]) / kind.spread[d], 2) }
    let distance = (sum / Double(p.count)).squareRoot()
    return max(-1, min(1, (2.25 - distance) / 0.75))
}

// MARK: - Scoring

/// The person's own foods rank higher, and more so the more often they eat them.
private func boost(_ known: [String: Double], _ id: String) -> Double {
    guard let count = known[id] else { return 0 }
    return 1.5 + 0.5 * log1p(max(0, count))
}

/// Orders candidates: name match, common form, brand agreement, the person's own foods. A search
/// has no brand of its own unless `hints.brand` says which of its words name one; a food whose
/// brand it names in passing ("oreo", "mcdonalds big mac") is not marked down as branded. With a
/// profile, a food unlike the kind of food the words name ranks lower, and the named brand's food
/// most like it ranks first even under another name: Trader Joe's calls its Mini-Wheats
/// "Shredded Bite Size Wheats". Foods that don't match are left out.
func scoreFoods(
    _ seen: Named, _ foods: [Food], known: [String: Double] = [:], search: Bool = false,
    hints: RankHints = RankHints()
) -> [Ranked] {
    scoreFoods(seen, foods.map { Entry($0) }, known: known, search: search, hints: hints)
}

func scoreFoods(
    _ seen: Named, _ entries: [Entry], known: [String: Double] = [:], search: Bool = false,
    hints: RankHints = RankHints()
) -> [Ranked] {
    let read = search ? readQuery(seen.name) : nil
    let target = read.map { searchedWords($0.words) } ?? nameWords(seen.name)
    let brand = hints.brand
    let fixes = hints.fixes
    // With a brand named, the other words describe the product, and only its name is read for them.
    let asked = search && !brand.isEmpty
    // The brand's words once each: the second "taco" of "taco bell taco" names the food.
    var branding = brand
    let named =
        asked
        ? target.filter { word in
            guard let at = branding.firstIndex(of: word) else { return true }
            branding.remove(at: at)
            return false
        } : target
    // A brand alone names none of its foods over another, so how often each is scanned orders them.
    let alone = asked && named.isEmpty
    // A typed search and a food a model saw both mean the cooked form of what's usually eaten
    // cooked; a model asked for raw salmon says so.
    // A word still being typed counts once it's most of one: "chick" for chicken.
    // Not a food named after one: potato chips aren't a potato to bake.
    // Unless how it's cooked was said: "toast", "roasted almonds", "baked beans".
    let saidCooked = (target + hints.sides).contains { cookedWords.contains(stem($0)) || stem($0) == "toast" }
    // The word being typed counts as the food it's most likely on its way to: "ground bee" is beef.
    let likely = search ? EverydayPhrases.likely(target) : nil
    let namedAfter = (likely ?? target.last).map { formWords.contains(stem($0)) && !eatenCooked.contains(stem($0)) } ?? false
    // Nor is one said to be fresh: fresh salmon isn't the smoked one, nor fresh green beans cooked.
    let cooked =
        !target.contains { rawWords.contains(stem($0)) } && !hints.sides.contains("raw") && !namedAfter
        && (target + target.flatMap { alternatives[$0] ?? [] } + fixValues(fixes, order: target) + (likely.map { [$0] } ?? [])).contains { word in
            let s = stem(word)
            // Not a cut at a chain, which cooks it its own way: Wingstop's wings aren't the baked ones.
            return eatenCooked.contains(s) || (hints.out == nil && eatenCookedWhole.contains(s))
                || (search && length(s) >= 4 && eatenCooked.contains { starts($0, s) })
        }
    // Catalogs repeat products; the person's own foods are each kept.
    var keys: [String] = []
    var unique: [String: Entry] = [:]
    for entry in entries {
        if unique[entry.key] == nil { keys.append(entry.key) }
        if unique[entry.key] == nil || known[entry.food.id] != nil { unique[entry.key] = entry }
    }
    // A way of cooking or a cut that no plain food with the other words lists is one the food
    // needn't say: USDA's broccoli is "cooked, boiled", so that is steamed broccoli, and its
    // salmon "cooked, dry heat" is baked salmon and a grilled salmon fillet. Not with a brand,
    // whose product is named as its label names it.
    var eases: [String: Ease] = [:]
    if !asked, seen.brand.isEmpty, target.count > 1 {
        let easable = target.filter { isEasable($0, seen: true) }
        let rest = target.filter { !isEasable($0, seen: true) }
        if !easable.isEmpty, !rest.isEmpty {
            // The other words are whole unless the last of them is the last typed: the "pot" of
            // "pot roast" isn't a potato begun.
            let others = CoverageQuery(
                seen: Named(name: rest.joined(separator: " "), brand: ""), target: rest, prefix: search && target.last == rest.last, fixes: fixes,
                respelt: hints.respelt)
            var having: [(text: FoodText, match: Coverage)] = []
            for entry in unique.values where !entry.text.branded {
                // As typed and whole: "fresh stacks" aren't fresh snacks.
                let match = others.cover(entry.text)
                if match.missing == 0, match.fixed == 0, match.partial == 0, !match.modifies { having.append((entry.text, match)) }
            }
            // The foods filed under those words, by the name's first part or by the word half of
            // them come after ("Squash, summer" for zucchini): a food is spared a word only
            // where one of these is, so grilled cheese isn't a cooked "Pizza, cheese topping".
            var before: [String: Int] = [:]
            for food in having { for word in Set(food.match.filed) { before[word, default: 0] += 1 } }
            let under = having.count >= 5 ? Set(before.filter { 2 * $0.value >= having.count }.keys) : []
            let plain = having.map { food in
                (
                    text: food.text, forms: food.match.forms,
                    leads: food.match.leads || (!food.match.filed.isEmpty && food.match.filed.allSatisfy(under.contains)),
                    // Named by those words and where it's filed, no more: "Cheese, gouda".
                    filed: !food.match.filed.isEmpty && food.match.others == food.match.filed.count
                )
            }
            for word in easable {
                let said = stem(word)
                var ease = Ease(said)
                // How the food was cut says nothing of which food it is, nor does how a label
                // says it was grown or made: organic chicken breast is chicken breast. Typed,
                // a plain food that lists the cut and nothing else is still the one meant:
                // sliced ham is "Ham, sliced", shredded cheese a cheese that says so.
                let listed = plain.contains { food in
                    food.leads && food.forms.allSatisfy { same($0, said) || same(said, $0) }
                        && food.text.said.contains { same($0, said) || same(said, $0) }
                }
                if labelWords.contains(said) || (plateCuts.contains(said) && !(search && listed)) {
                    ease.plate = true
                    ease.label = labelWords.contains(said)
                    eases[word] = ease
                    continue
                }
                // A plain food that lists it is the food meant, unless only a less common form
                // does: apple slices aren't USDA's "Apples, canned, sweetened, sliced", nor
                // roasted potatoes its "Potatoes, roasted, …, frozen, unprepared". Nor one filed
                // under more than was said, where a food filed under it will do: baked chicken
                // isn't a "Chicken wing, baked or broiled, from fast food".
                // The word itself isn't what makes a form less common: "Carrots, baby" lists baby carrots.
                let listing = plain.filter { food in
                    food.forms.allSatisfy { same($0, said) || same(said, $0) } && food.text.all.contains { same($0, said) || same(said, $0) }
                }
                var fits = plain.contains { $0.leads && ease.fits($0.text) }
                // A food the catalog has no entry cooked that way for is the uncooked one there
                // is: grilled pineapple is its raw pineapple, smoked gouda its gouda and baked
                // tofu its tofu, which it otherwise has fried; not a label named so. Not fried,
                // which adds the oil, nor seaweed, which roasting dries: a sheet of it is ten
                // times its raw kelp. Nor where a plain food is named by the way and then the
                // food, as said: "grilled chee" is a grilled cheese sandwich begun, not cheese.
                let namedSo = { (words: [String]) in
                    words.indices.dropLast().contains { i in
                        (same(words[i], said) || same(said, words[i])) && rest.contains { starts(words[i + 1], stem($0)) }
                    }
                }
                if !fits, ease.heat != nil, !ease.fried, !rest.contains(where: { driedByHeat.contains(stem($0)) }),
                    plain.contains(where: { ($0.leads || $0.filed) && !$0.text.cooking.cooked }), !plain.contains(where: { namedSo($0.text.said) })
                {
                    ease.uncooked = true
                    fits = true
                }
                // Where no food is spared the word, it says which food is meant. Nor is any
                // where a plain food is named by exactly the way and the food: "Roasted
                // potatoes" are the ones roasted in fat, not the baked potato.
                // The way as it was said, not another word for it: barbecued chicken is
                // grilled, where "Barbecue chicken" is the dish in its sauce.
                let exactly = plain.contains { food in
                    let words = food.text.said
                    return words.count == target.count
                        && words.indices.dropLast().contains { i in same(words[i], said) && rest.contains { starts(words[i + 1], stem($0)) } }
                }
                eases[word] = fits && !exactly && !listing.contains(where: \.leads) ? ease : Ease(said, listed: true)
            }
        }
    }
    let query = CoverageQuery(
        seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
        nameOnly: asked && !named.isEmpty, respelt: hints.respelt, eases: eases, sides: hints.sides, beside: hints.beside)
    // The same, also reading a word the catalogs barely know as a food's own word misspelt.
    let lenient =
        hints.doubted.isEmpty
        ? nil
        : CoverageQuery(
            seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
            nameOnly: asked && !named.isEmpty, doubted: hints.doubted, respelt: hints.respelt, eases: eases, sides: hints.sides,
            beside: hints.beside)
    // Each brand word's forms, a form being words in a row: "papajohns" is corrected to "papa john".
    let brandForms = brand.map { word in
        isNumber(word) ? [[word]] : (searchForms(word) + (fixes[word] ?? [])).map { $0.split(separator: " ").map(String.init) }
    }
    let brandParts = Array(brandForms.joined().joined())
    let mentionForms = target.map(searchForms)
    // Each word as it would name a brand's word, and as corrected ("sracy" names Stacy's).
    let typedBare = target.map { length($0) > 1 && !isNumber($0) ? bare($0) : "" }
    let last = target.count - 1
    let typedFixes = target.map { word in (fixes[word] ?? []).map { $0.split(separator: " ").map(String.init) } }
    let typedMisspelt = target.map { hints.doubted.contains($0) ? Misspelling($0) : nil }
    // The words said in another order, for a food whose brand some of them name (see `fit`),
    // apart for reading a misspelt word.
    var reordered: [[Int]: CoverageQuery] = [:]
    var reorderedLenient: [[Int]: CoverageQuery] = [:]
    // Whether a plain food has every word said, worked out when a food's brand first asks. Not
    // by a brand USDA names in capitals inside a plain food's name ("Yogurt, Greek, plain, CHOBANI").
    // With `leading`, by a food that leads with them: the mayonnaise that is "cholesterol-free"
    // doesn't make "chol" a food's word rather than Cholula begun, as "her" is herring's.
    var plainlyNamed: [Int: Bool] = [:]
    func isPlainlyNamed(corrected: Bool = false, leading: Bool = false) -> Bool {
        let key = (corrected ? 1 : 0) + (leading ? 2 : 0)
        if let known = plainlyNamed[key] { return known }
        let said = target.map(stem)
        let found = unique.values.contains { entry in
            guard !entry.text.branded, !said.contains(where: { word in entry.text.shouted.contains { starts($0, word) } }) else { return false }
            // In its name, not a note of whose it is: "Cheeseburger (McDonalds)" is McDonald's.
            guard !said.contains(where: { word in entry.text.noted.contains { starts($0, word) } && !entry.text.said.contains { starts($0, word) } })
            else { return false }
            // As typed, not as a typo of it: "hers" isn't herring.
            let match = query.cover(entry.text)
            if match.missing == 0 && (corrected || match.fixed == 0) && (!leading || match.leads) { return true }
            // Or by another name the catalog keeps for it, when that's all that was said.
            return entry.also.contains { query.cover($0.text).exact }
        }
        plainlyNamed[key] = found
        return found
    }

    // The words of the plain foods found as they're written, but for the brands USDA writes in
    // capitals: worked out when a brand's start first asks. By the word and its plural, not
    // its stem: "savor" isn't savory. With `begun`, by a word it's the start of too.
    var plainWords: Set<String>?
    func isPlainWord(_ word: String, begun: Bool = false) -> Bool {
        if plainWords == nil {
            var words = Set<String>()
            for entry in unique.values where !entry.text.branded {
                for token in tokens(entry.food.name) where !entry.text.shouted.contains(stem(token)) { words.insert(token) }
            }
            plainWords = words
        }
        guard let plainWords else { return false }
        if plainWords.contains(word) || plainWords.contains(word + "s") || plainWords.contains(bare(word)) { return true }
        return begun && plainWords.contains { $0.hasPrefix(word) }
    }

    // Whether the catalog keeps exactly what was said as another name for a plain food: "Jello"
    // for gelatin dessert.
    var plainlyCalled: Bool?
    func isPlainlyCalled() -> Bool {
        if let known = plainlyCalled { return known }
        let found = unique.values.contains { entry in !entry.text.branded && entry.also.contains { query.cover($0.text).exact } }
        plainlyCalled = found
        return found
    }

    /// How a food covers what was said, and whether a search with no brand of its own names the
    /// food's brand. A food whose brand the search names word for word reads those words as its
    /// brand wherever they were typed, so the word naming the food is the last of the others:
    /// "cheese", not "cow", in "cottage cheese honest cow" for The Honest Cow's cottage cheese.
    /// With `misspelt`, a word the catalogs barely know is also one of the food's own words a typo
    /// or two from it, which names a brand too: "gali" for Galli's roasted chestnuts.
    func fit(_ text: FoodText, misspelt: Bool) -> (match: Coverage, own: Bool, only: Int) {
        let whole = misspelt ? lenient ?? query : query
        guard search, !asked, last >= 0, !text.own.isEmpty else { return (whole.cover(text), false, 0) }
        // Word for word, a plural or possessive apart: "wheats" isn't the brand Wheaty, though
        // they share a stem. Each of the brand's words takes one word said, so the "eggs" of "egg
        // land best brown eggs" still name the food; two said as one ("membermark") take it
        // together, and after a food the last word may be as far as the brand is typed ("oats
        // kas"; "pop" alone is on its way to popcorn as much as to Popchips).
        var naming: [Int] = []
        var halfTyped = false
        // The letter the search ends with starts the brand's next word: the "d" of "mountain d".
        var continued = false
        // Every word is the brand's as typed, not as corrected.
        var asTyped = true
        for (j, written) in text.ownWords.enumerated() {
            let word = bare(written)
            // A word that stands for two ("membermark", or "blackberries" as some labels write it)
            // names a brand only when both are the brand's: Member's Mark, not Berry Fresh.
            var named = target.indices.first { i in
                (!naming.contains(i) && typedBare[i] == word)
                    || typedFixes[i].contains { parts in
                        parts.contains(text.own[j]) && parts.allSatisfy { length($0) > 2 && text.own.contains($0) }
                    }
            }
            if named == nil, misspelt {
                named = target.indices.first { !naming.contains($0) && typedMisspelt[$0]?.reads([text.own[j]]) == true }
            }
            // Not a word the food's own name has, or an everyday food's: the "bread" of "sourdough
            // bread" isn't Breadsmith begun, nor the "bar" of "protein bar" Barilla, nor the
            // "clove" of "garlic clove" Clover Valley. Unless it was typed twice: "sparkling water
            // water" is on its way to Waterloo.
            // Nor a word some plain food has whole, where none of the brand's was typed before
            // it: "rum" is the spirit, not Rumford's begun, and "conagra bran" is still Conagra
            // Brands.
            if named == nil, !naming.contains(last), length(target[last]) > 2, !typedBare[last].isEmpty, starts(written, target[last]),
                target.dropLast().contains(target[last])
                    || (!text.said.contains(stem(target[last])) && !EverydayPhrases.isWord(stem(target[last])) && !isEasable(target[last])
                        && !(naming.isEmpty && isPlainWord(target[last])))
            {
                named = last
                halfTyped = true
            }
            // A brand of several words is begun by its first, typed alone and whole: "halo" is
            // on its way to Halo Top, as "hal" isn't yet. Not an everyday food's own word
            // ("hot" isn't Hot Pockets'), unless a letter typed after it starts the next.
            // A letter that starts another word says it isn't this brand: "mountain y".
            if named == nil, j > 0, target.count == 1, naming == [0], !halfTyped, asTyped {
                let letter = read.flatMap { $0.letter.count == 2 && $0.letter[0] == target[0] ? $0.letter[1] : nil }
                continued = letter.map { word.hasPrefix($0) } ?? false
                if continued || (letter == nil && !EverydayPhrases.isWord(stem(target[0])) && !isEasable(target[0]) && !isPlainWord(target[0])) {
                    halfTyped = true
                    break
                }
            }
            guard let named else { return (whole.cover(text), false, 0) }
            if !halfTyped, typedBare[named] != word { asTyped = false }
            if !naming.contains(named) { naming.append(named) }
        }
        // A one-word brand isn't one the search names when a plain food has every word typed:
        // chia seeds listed under "Seeds", American cheese under "american" and cherry tomatoes
        // under "Cherry" are no brand's. Typed whole, that is ("water" is on its way to
        // Waterloo), and "high protein supersnack edamame" is still the Supersnack listed under
        // "Edamame", which no plain food is.
        // A brand people scan is one, whatever plain food has its word (Goldfish, Post, Kraft),
        // and so is a chain USDA names: this is about what labels put in their brand field.
        // Nor is an everyday food's own word a brand, whoever lists a food under it: "oat milk"
        // isn't the oat milk of a label that gives "milk" as its brand.
        // By the word itself or one it starts, where it's typed as the brand writes it:
        // Ruffles aren't the "ruffled" of a plain food's potato chips, and "sam" is still on
        // its way to a samosa. Or by a word that only says how a food comes, which a plain
        // food needn't write: "organic" raisins aren't Organics'. Or by a name the catalog
        // keeps for the plain food, as "Jello" is gelatin dessert's.
        let isOwnWord = { (i: Int) in isPlainWord(target[i], begun: true) || isEasable(target[i]) }
        let itsOwn = { naming.allSatisfy(isOwnWord) || isPlainlyCalled() }
        if text.ownWords.count == 1, !halfTyped, !text.chain, !popularBrands.contains(bare(text.ownWords[0])),
            EverydayPhrases.isWord(text.own[0]) || (isPlainlyNamed(corrected: true) && (!asTyped || itsOwn()))
        {
            return (whole.cover(text), false, 0)
        }
        // The same for a brand of several words, where a plain food has them all: chow mein
        // isn't the one a label lists under "Chow Mein".
        if text.ownWords.count > 1, !halfTyped, !text.chain, !popularNames.contains(text.ownWords.map(bare).joined(separator: " ")),
            isPlainlyNamed(corrected: true)
        {
            return (whole.cover(text), false, 0)
        }
        // Nothing typed but the food's brand: it's one of that brand's foods, whatever it's called.
        // Half typed, only when the letters aren't on their way to an everyday food.
        // Not when a plain food has every word: then the search names a food, and a label that
        // lists it under its own name ("Cottage cheese" by "Cottage cheese") is no brand.
        // And only for one word: more are read as a brand from the whole search, or name a
        // product ("belvita snack packs" isn't whatever is listed under "belVita SNACK PACKS").
        if naming.count == target.count {
            // Nor for a word read as the brand misspelt: "yogrt" is yogurt before a label listed under "Yogurt".
            // One of the most scanned brands is as likely as a plain food that starts the
            // same, unless the letters are on their way to an everyday food: "tropic" is
            // Tropicana before a tropical punch, and "cel" is still celery before Celsius.
            let popular =
                text.ownWords.count == 1
                ? popularBrands.contains(bare(text.ownWords[0])) : popularNames.contains(text.ownWords.map(bare).joined(separator: " "))
            let scanned = halfTyped && likely == nil && (popular || continued)
            // Typed whole, a plain food names the word only by the word itself (see above).
            let plainly = isPlainlyNamed(leading: halfTyped) && (halfTyped || itsOwn())
            if target.count > 1 || !asTyped || (halfTyped && likely != nil) || (!scanned && plainly) {
                return (whole.cover(text), !halfTyped, 0)
            }
            return (whole.cover(text, own: target.count), !halfTyped, halfTyped ? 1 : 2)
        }
        naming.sort()
        if let known = misspelt ? reorderedLenient[naming] : reordered[naming] { return (known.cover(text, own: naming.count), true, 0) }
        let order = naming + target.indices.filter { !naming.contains($0) }
        let moved = CoverageQuery(
            seen: seen, target: order.map { target[$0] }, prefix: true, fixes: fixes, doubted: misspelt ? hints.doubted : [],
            respelt: hints.respelt, eases: eases)
        if misspelt { reorderedLenient[naming] = moved } else { reordered[naming] = moved }
        return (moved.cover(text, own: naming.count), true, 0)
    }

    struct Row {
        var food: Food
        var text: FoodText
        var match: Coverage
        /// The catalog's other name for the food that matched, when its own name matched less.
        var other: FoodText?
        /// That name is exactly what was said.
        var called: Bool
        /// That name is what was said as it's read, and no more.
        var calling: Bool
        var mine: Bool
        /// The brand is the one asked for and no longer: Papa John's, not Papa John's Salads & Produce.
        var exact: Bool
        /// With no brand read from the whole search, the search names this food's brand word for word.
        var own: Bool
        /// The search is nothing but this food's brand: 2 typed whole, 1 half typed.
        var only: Int
        /// The brand's food named by exactly the words said.
        var said: Bool
        var name: Double
        var like: Double
        var plausible: Bool
        var dish: Bool
    }
    let isForm = { (word: String, form: String) in isNumber(form) ? word == form : starts(word, form) }
    // What was said, without a label's word for how it was grown or made: "organic manicotti"
    // is still what the catalog calls "Manicotti".
    let saidStems = target.map(stem).filter { !labelWords.contains($0) }
    // The same in every wording the catalogs have: "coke" is also cola.
    let askedForms = Set(target.flatMap { forms($0).map(stem) } + saidStems)
    // The same read through a word's one correction: "americno" is what the catalog calls
    // "Americano", as it is typed right.
    let correctedStems = target.map { word in
        fixes[word].flatMap { $0.count == 1 && !$0[0].contains(" ") && !hints.respelt.contains($0[0]) ? stem($0[0]) : nil } ?? stem(word)
    }.filter { !labelWords.contains($0) }
    let saidJoins = joining(seen.name)
    var rows: [Row] = []
    rows.reserveCapacity(keys.count)
    for key in keys {
        let entry = unique[key]!
        let food = entry.food
        let text = entry.text
        var (match, own, only) = fit(text, misspelt: false)
        // A food is also found by a chain's name for it ("mcnuggets" finds chicken nuggets from
        // fast food), when that name says more of what was asked than its own and names what was asked.
        var other: FoodText?
        // The other name is all that was said, in the order said: "tea with milk" isn't the
        // bubble tea also called "Milk tea".
        var called = false
        var calling = false
        if match.name < 1 {
            for name in entry.also where mentionForms.contains(where: { $0.contains { starts(name.head, $0) } }) {
                var named = query.cover(name.text)
                // Or as much, by the one that is exactly what was said: a "Stir fry chicken"
                // listed after "Chicken stir fry".
                let exactly =
                    named.exact && (name.text.titled == saidStems || name.text.titled == correctedStems) && saidJoins.isSubset(of: name.joins)
                if named.name > match.name || (exactly && !called && named.name == match.name) {
                    // The food is cooked as its own name says, whichever name found it.
                    named.cooked = max(named.cooked, match.cooked)
                    match = named
                    other = name.text
                    called = exactly
                    calling = named.missing == 0 && name.text.titled.count == saidStems.count && saidJoins.isSubset(of: name.joins)
                }
            }
        } else if !match.exact, !entry.also.isEmpty {
            // And by another name that is exactly what was said, though its own has the words
            // too: "manicotti" is the one the catalog also calls "Manicotti", among the four
            // it lists.
            for name in entry.also
            where (name.text.titled == saidStems || name.text.titled == correctedStems) && saidJoins.isSubset(of: name.joins) {
                var named = query.cover(name.text)
                if named.exact {
                    named.cooked = max(named.cooked, match.cooked)
                    match = named
                    other = name.text
                    called = true
                    calling = true
                    break
                }
            }
        }
        // Only then a misspelling of the food's own words, which a typo's usual meaning or a
        // chain's name for the food would otherwise explain: "mcmuffin" isn't a muffin misspelt.
        if match.name < 1, lenient != nil {
            let loose = fit(text, misspelt: true)
            if loose.match.name > match.name {
                (match, own, only) = loose
                other = nil
                calling = false
            }
        }
        let mine: Bool
        var exact = false
        if asked {
            // The brand asked for: each of its words starts a word of the food's brand.
            // Or of the other name the food was found by: the soft serve also called "Dairy
            // Queen Blizzard" is Dairy Queen's.
            let makers = [text.own, text.own.isEmpty ? other?.titled ?? [] : []]
            mine = makers.contains { maker in
                !maker.isEmpty
                    && brandForms.allSatisfy { options in
                        options.contains { form in form.allSatisfy { part in maker.contains { isForm($0, part) } } }
                    }
            }
            // Word for word: "Poptart" starts with "pop", but isn't the brand Pop.
            exact = mine && !text.own.isEmpty && text.own.allSatisfy { word in brandParts.contains { same(word, $0) } }
        } else {
            mine = match.brand == true
        }
        // A search for a brand alone matches all of its foods.
        let name = alone && mine ? 1 : match.name
        // The brand's food named by exactly the words said is the food asked for, whatever foods of
        // that name are usually like: Trader Joe's "Chocolate Bar" for its chocolate bar, though it
        // is darker than most.
        let said = mine && name == 1 && match.others == 0 && match.variations == 0
        rows.append(
            Row(
                food: food, text: text, match: match, other: other, called: called, calling: calling, mine: mine, exact: exact, own: own, only: only,
                said: said,
                name: name,
                like: hints.profile.map { said ? 1 : likeness(food, $0) } ?? 0, plausible: entry.plausible, dish: entry.dish))
    }
    let sold = rows.contains { $0.mine && $0.name == 1 && $0.like > 0 }
    // A brand that makes nothing like what the other words usually name means its own food by
    // them: Papa John's pepperoni is its pizza, not sliced pepperoni, and Tillamook's cheddar is
    // cheese, not crackers. One that does is read by the profile: Trader Joe's Mini-Wheats are its
    // shredded wheat, not its mini wheat pitas.
    let makesKind = rows.contains { $0.mine && $0.like > 0 }
    // What USDA files a food under, when it isn't under its own name: among the plain foods with
    // every word of a search, a word that half of them have before the word naming the food.
    // "Beef" for a steak, "Salad dressing" for mayonnaise, "Squash, summer" for zucchini, "Snacks"
    // for potato chips. It isn't held against a food, and a name with nothing else before the
    // food leads with it as "Fish, salmon" does. For a food a model saw as for a typed search:
    // its "sirloin" is beef before veal.
    // The plain foods that aren't dishes and have every word, as typed, and the dishes named by
    // the words: whether the words name a food more than a dish. "Liver" does, as many plain
    // foods have it as dishes are named by it; "chow mein" and "hamburger" don't.
    let plain = rows.filter { row in
        !row.dish && !row.text.branded && row.match.missing == 0 && row.match.partial == 0 && !row.match.modifies && !row.match.garnish
    }
    let dishes = rows.filter { $0.dish && $0.match.missing == 0 && $0.match.partial == 0 && ($0.match.headsWhole || $0.match.kind) }.count
    let food = plain.count >= dishes
    var shelf = Set<String>()
    do {
        // The foods that have the words whole, where the last is still being typed and enough
        // do: "ch" on its way to chicken is filed as chicken is.
        // Not the dishes a food is in: a taco made with a flour tortilla doesn't file flour
        // tortillas under tacos. Nor, where the words name a dish, the foods named after it:
        // the rolls a hamburger comes in don't file hamburgers under "Rolls".
        let every = rows.filter { $0.match.missing == 0 && !$0.text.branded && $0.dish != food }
        // Of several words, the foods that have them in one part of the name: a coconut cream
        // pudding "prepared with whole milk" isn't a coconut milk.
        let one = every.filter { $0.match.together }
        let having = target.count > 1 && one.count >= 3 ? one : every
        let whole = having.filter { $0.match.partial == 0 }
        let family = whole.count >= 5 ? whole : having
        if family.count >= 5 {
            var foods: [String: Int] = [:]
            // Not a brand USDA has many foods of, which it writes in capitals.
            for row in family { for word in Set(row.match.filed) where !row.text.shouted.contains(word) { foods[word, default: 0] += 1 } }
            // More than half: every other frozen coffee drink is a mocha one, and none is
            // filed under "mocha".
            shelf = Set(foods.filter { 2 * $0.value > family.count }.keys)
        }
        // And the form most of them come in is the form the food comes in: tomato sauce and
        // tomato paste are canned, so "canned" isn't a less common kind of either.
        if family.count >= 3 {
            var foods: [String: Int] = [:]
            for row in family { for word in Set(row.match.forms) where keptWords.contains(word) { foods[word, default: 0] += 1 } }
            shelf.formUnion(foods.filter { 3 * $0.value >= 2 * family.count }.keys)
        }
        // Never a kind the everyday variety isn't: most ribs USDA lists are beef, and ribs are still
        // pork. Nor a food made for babies or of something else, however many of those USDA lists:
        // applesauce isn't filed under "Babyfood".
        shelf.subtract(query.unusual)
        shelf.subtract(notFiled)
    }
    // Some food sold here has every word said, in its name or as its brand read whole: not a
    // word that only happens to be in a brand ("cottage cheese honest" isn't The Honest Cow's yet).
    let complete = rows.contains { $0.match.missing == 0 && $0.match.name == 1 && !hints.away.contains($0.food.id) }
    // A food people look for has every word as typed: a correction of one is then a long shot.
    // "spam" is Spam, though the catalogs know "spa…" better; "brocoli" is still broccoli,
    // which only labels sold elsewhere and scanned by no one spell that way.
    // Only where the correction is a long shot, as the word cut short is: "protien" is still
    // protein, whatever a label or two spell that way. A chain's item USDA lists is such a
    // food: a "mcchicken" is McDonald's, not chicken.
    // A correction of its spelling, that is: another wording of the word (the "hamburger" of
    // "burger") is the word itself.
    let longShots = search ? target.filter { word in (fixes[word] ?? []).contains { !hints.respelt.contains($0) && isLongShot($0, for: word) } } : []
    let cutShort = longShots.allSatisfy { word in (fixes[word] ?? []).contains { $0 != word && word.hasPrefix($0) } }
    // A label spells a word as it likes, so a scanned label's name only shows that a word
    // isn't another cut short: "mozerella" on a few of them is still mozzarella. Otherwise the
    // word is in a name USDA wrote, or is the brand of a food people scan (Skittles, Cholula).
    let isAsTyped = { (row: Row) in
        guard row.match.missing == 0, row.match.fixed == 0, row.match.partial == 0, !hints.away.contains(row.food.id) else { return false }
        if !row.text.branded || row.text.chain { return true }
        return row.food.popularity >= 1.5 && (cutShort || longShots.allSatisfy { word in row.text.own.contains { same($0, stem(word)) } })
    }
    let literal = !longShots.isEmpty && rows.contains(where: isAsTyped)
    // What's eaten cooked is still the raw food where the catalog lists no cooked one: egg
    // whites are USDA's "Egg, white, raw, fresh", which it has no cooked entry for.
    let listsCooked = !cooked || rows.contains { !$0.text.branded && $0.match.lacking == 0 && $0.name > 0 && $0.match.cooked > 0 }
    // A food USDA lists with its brand in capitals is that brand's like any label's when what
    // was said is only its flavour: "Beverages, POWERADE, Zero, Mixed Berry" isn't mixed
    // berries. Not when the search names the brand, the food is filed under what was asked
    // ("Yogurt, Greek, plain, CHOBANI" is Greek yogurt) or the words are the brand's name for
    // it, which come right after the brand: "Candies, REESE'S Peanut Butter Cups".
    let isFlavour = { (text: FoodText) -> Bool in
        guard !text.shouted.isEmpty, let brand = text.said.lastIndex(where: text.shouted.contains) else { return false }
        let wasSaid = { (word: String) in saidStems.contains { starts(word, $0) } }
        if text.shouted.contains(where: wasSaid) { return false }
        // One word names a kind of food, which a brand's is only one of: "smoothie" isn't
        // "Beverages, V8 SPLASH Smoothies, Peach Mango".
        return saidStems.count == 1 || brand + 1 == text.said.count || !wasSaid(text.said[brand + 1])
    }
    // One of the most scanned brands is begun by what was typed.
    let begun = rows.contains { $0.only == 1 && !hints.away.contains($0.food.id) && popularBrands.contains(bare($0.text.ownWords[0])) }
    // A food leads with what was said by its own name or by where it's filed.
    let filedWhole = { (match: Coverage) in match.missing == 0 && !match.filed.isEmpty && match.filed.allSatisfy(shelf.contains) }
    // Some plain food that isn't a dish has every word, as typed: then a dish that doesn't lead
    // with them is a dish made with the food, and one that adds another food to it is that
    // food with more, where the words name a food more than a dish. "Parmesan" is the cheese
    // before an eggplant parmesan casserole, "flour tortilla" the tortilla before a taco in
    // one, "liver" liver before liver and onions; chow mein with noodles is chow mein. Where
    // such a food leads with the words, so is any dish that says more: green beans before
    // Szechuan-style ones.
    let plainly = plain.contains { $0.match.leads || filedWhole($0.match) }
    // What only labels are named by (see `onlyLabelled`).
    let labelled = onlyLabelled.contains(saidStems)
    var ranked: [Ranked] = []
    let maker = seen.brand.isEmpty ? [] : words(seen.brand).map(stem)
    let phrased = rows.contains { !$0.text.branded && $0.match.missing == 0 && $0.match.asSaid }
    for (index, row) in rows.enumerated() where row.name > 0 {
        let match = row.match
        var filedUnder = 0.0
        // A dish leads with what it is, whatever it comes with.
        var leads = row.dish ? match.heads : match.leads
        if !shelf.isEmpty && !row.text.branded {
            for word in match.filed where shelf.contains(word) {
                filedUnder += variationWords.contains(word) ? (insteadWords.contains(word) ? 1.2 : 0.8) : 0.25
            }
            // A form counted wherever it comes in the name, once.
            for word in match.forms where shelf.contains(word) && !match.filed.contains(word) { filedUnder += 0.8 }
            if filedWhole(match) { leads = true }
        }
        let theirs = asked && row.mine && row.name == 1 && !makesKind
        let like = theirs ? max(0, row.like) : row.like
        // A plain food named by nothing but what was said is the usual one, before the kind
        // that usually stands for it: "Soup, tomato" before the canned one. Not where more
        // was said to come with it: mashed potatoes with gravy are the ones that have it.
        let exact = !row.text.branded && match.exact && row.other == nil
        var score =
            3 * row.name + (leads ? 0.75 : 0)
            // A generic food USDA names by exactly the words said, inverted, ranks above a blend or
            // dish that only has them.
            // So does one the catalog keeps exactly those words for as another name.
            // A name the catalog keeps that is exactly what was said counts a little more than
            // a food's own name read into it: a peanut butter cup before a peanut butter cupcake.
            + (row.called && !row.text.branded ? 0.6 : match.named && !row.text.branded ? 0.5 : 0)
            // A food not usually cooked is the raw one, between two that match as well, and its
            // cooked form is a kind of its own: roasted walnuts, cooked apples.
            // A dish is cooked, whether its name says how: chicken and rice as much as fried
            // rice with chicken.
            + (cooked && listsCooked
                ? 0.4 * Double(row.dish ? max(1, match.cooked) : match.cooked) - (match.fried ? 0.2 : 0)
                : match.cooked < 0 ? 0.1 : match.cooked > 0 && !saidCooked ? -0.3 : 0)
            // The brand's food named by exactly the words said is as usual as its kind that says
            // so (Great Value's "Cottage Cheese Small Curd" beside its lowfat one), and "typical"
            // is USDA's word for its own entries: a label's "Original" is another product.
            // Among foods with every word said, that is: plain white rice isn't the usual fried rice.
            // Nor a brand's that USDA names in capitals: "Sauce, barbecue" before "Sauce, barbecue,
            // KRAFT, original".
            + (match.missing > 0
                ? 0
                : (match.usual || (row.said && query.asksUsual) ? 0.6 : exact && query.asksUsual && hints.sides.isEmpty ? 0.65 : 0)
                    + (match.typical && !row.text.branded && row.text.shouted.isEmpty ? 0.3 : 0))
            // A longer word than the one being typed is likely on its way to counts a little more
            // against a food: "sal" is salmon before salsify.
            - (likely == nil ? 0.5 : 0.75) * Double(match.partial) - 0.4 * Double(match.fixed) - 0.8 * match.variations
            // A note in brackets says more about the same food, however long it is.
            - 0.25 * Double(match.others - (row.dish ? match.extra.filter(fromWords.contains).count : 0))
            - min(0.1, 0.05 * Double(match.notes)) + filedUnder + match.near
            // Of two foods that are the food named, the one that has what a model said of it
            // or beside it: the buffalo wings, the mashed potatoes with gravy. No more than
            // that: at 0.75 a word, spaghetti with tomato sauce was a restaurant's whole grain
            // pasta with tomato-based sauce.
            // A little more for the one whose name says it comes with all of it, as said: tea
            // with milk is "Tea, hot, with milk" before the usual black tea.
            + (match.missing == 0 ? 0.5 * Double(match.sides) + (match.comes ? 0.5 : 0) : 0) - (match.served ? 1.5 : 0)
            // And between two that match as well, not the one with none of it.
            - (hints.sides.isEmpty || match.sides > 0 ? 0 : 0.05)
            // A food found by another name ranks a little below one its own name matches as
            // well, unless the other name is all that was said.
            - (row.other == nil || row.called ? 0 : 0.5)
            // A food named after the one asked for: cake pretzels and cake fries for "cake". Not a
            // brand's own food by those words when it makes nothing like the food: Papa John's
            // pepperoni is its pepperoni pizza.
            // A little more for a plain food, so a label named exactly as said comes before it:
            // mixed berries before USDA's "Snack, Mixed Berry Bar".
            - (match.modifies && !theirs ? (row.text.branded ? 1 : 1.05) : 0)
        // A plain food named after another food's word, with a word said only added to it, is
        // that other food with some of this in it: "Potato salad with egg" isn't an egg salad.
        // Not where the word before is only what the food is filed under.
        if !row.text.branded, !leads, match.garnish || match.added.contains(where: { !shelf.contains($0) }) { score -= 1.5 }
        // A dish made with the food, or the food with more (see `plain`). Not one already
        // counted as named after the food ("Gyro sandwich" for "gyro"), nor a chain's own
        // item, which is asked for by the chain, nor one that has what a model said the food
        // comes with: spaghetti and meatballs for "spaghetti with meatballs".
        if row.dish, !row.text.branded, !plain.isEmpty, !match.modifies, match.sides == 0 {
            let more = { (word: String) in !shelf.contains(word) && !row.text.group.contains(word) && !fromWords.contains(word) }
            // It leads by its own words, whole, or by where it's filed, or is a kind of what
            // was said: a turkey sandwich for "sandwich", whatever cookies are sandwiches too.
            let itself = match.headsWhole || (leads && !match.heads) || match.kind
            if !itself || (food && match.mixed.contains(where: more)) || (plainly && match.extra.contains(where: more)) { score -= 1.5 }
        }
        // By enough to follow such a label in a model's candidates too, where a label has no
        // more than its name to go by.
        if labelled, !row.text.branded, !row.called { score -= 1.25 }
        // Every food of a brand searched for alone answers it as well as any other.
        if alone && row.mine { score = 3 }
        // Not half typed for a brand that isn't sold here: "dal" isn't Dallmayr's coffee begun.
        if row.only == 2 || (row.only == 1 && !hints.away.contains(row.food.id)) {
            // The same for a brand of one word, read from the food itself: "chobani" is Chobani's
            // foods, the most scanned first, not the ones that repeat the brand in their name.
            // Half typed, they come with the plain foods that start as typed, by how much
            // they're scanned: "her" is Hershey's and herring.
            // A chain's items as USDA analysed them come before what's sold under its name in shops.
            // A brand no one scans, typed whole, is as likely one of the most scanned begun:
            // "nute" is Nutella before Nutes.
            let unknown = begun && row.food.popularity < 1.5 && !row.text.chain && !popularBrands.contains(bare(row.text.ownWords[0]))
            score = (row.only == 2 ? (unknown ? 3.5 : 5) : 3) + (row.food.source == .usda ? 0.5 : 0)
        } else if asked {
            // The brand asked for; then other brands' products, among them the one the search is
            // usually named after ("Kellogg's Mini-Wheats"); then plain foods.
            if row.mine {
                score += (theirs ? 3 : 1.5) + (row.exact ? 0.5 : 0)
            } else if !row.text.branded {
                score -= 1
            }
        } else if let brand = match.brand {
            score += brand ? 2 : -1
        } else if row.text.branded {
            // A brand's words aren't counted as ones the search didn't ask for, so a packaged
            // food's markdown includes them.
            score -= 2.25
        } else if !leads, isFlavour(row.text) {
            score -= 2.25
        }
        if let read {
            // Only when the food's own name has the word naming the food: Oreo's cookies for "oreo",
            // not the "Flat White" brand's coffee chocolate for "flat white".
            if row.own && match.head && row.only == 0 { score += 2 }
            if !read.counts.isEmpty || !read.sizes.isEmpty || !read.letter.isEmpty {
                let list = tokens("\(row.food.name) \(row.food.brand ?? "")")
                for (count, next) in read.counts where counted(list, count, next) { score += 2 }
                // The letter a search ends with isn't searched for, but a name with it after
                // the word before was asked for by it: "special k", "vitamin c".
                // And a little by a word that starts with it there: "two g" is on its way to
                // Two Good before Twofold.
                if read.letter.count == 2 {
                    let after = list.indices.dropLast().filter { list[$0] == read.letter[0] }.map { list[$0 + 1] }
                    score += after.contains(read.letter[1]) ? 2 : after.contains { $0.hasPrefix(read.letter[1]) } ? 0.5 : 0
                }
                for size in read.sizes where sized(list, size) { score += 2 }
            }
        }
        // Like the kind of food named, and for the brand asked for, more so when it is named the
        // same kind of food: its "wheats" are its Mini-Wheats, its "mini pretzels" are not. A
        // brand that sells the food by the name searched for isn't searched for another name of it.
        let version = row.mine && match.head && (row.name == 1 || !sold)
        score += like + (version ? max(0, like) : 0)
        // A food that lacks a word said is another food where some food has them all: oat milk
        // isn't sheep's milk, nor a breakfast burrito a beef and bean one, nor "dolmas vine leaves
        // stuffed with rice" plain rice.
        // Not the asked brand's own food under another name: Trader Joe's Mini-Wheats are its
        // "Shredded Bite Size Wheats".
        if complete && !(asked && row.mine) { score -= 1.5 * Double(match.lacking) }
        if literal && match.fixed > 0 { score -= 2.5 }
        // The person's own foods move up only among foods that have every word said.
        if match.missing == 0 { score += boost(known, row.food.id) }
        // Among packaged foods, the ones people scan most: Coca-Cola before a store's cola.
        if hints.popularity { score += 0.12 * row.food.popularity }
        // A name with the words said back to front names another food, where some plain food
        // is named by them as said: chocolate milk for "milk chocolate". Typed "juice apple",
        // apple juice is still the food.
        if phrased, match.backwards { score -= 0.75 }
        // Of two that match a word still being typed as well, a plain food that only says it
        // of itself comes after one named by it: "ruff" is Ruffles before potato chips, ruffled.
        if search, !row.text.branded, !match.leads, match.partial > 0, match.missing == 0 { score -= 0.01 }
        // A plain food from a restaurant is cooked their way, which wasn't asked for: cooked
        // green beans are the boiled ones, not the restaurant's with butter. A dish is the
        // same dish wherever it's from, and so is the entry with what a model said the food
        // comes with: mashed potatoes with gravy. Only the vegetables the catalog lists as
        // "cooked, from restaurant": tenders and fries from one are the usual ones.
        if hints.out == nil, !row.dish, !row.text.branded, match.sides == 0, row.text.said.contains("cooked"),
            match.extra.contains(where: placeWords.contains)
        {
            score -= 0.5
        }
        // Of two plain foods that match as well, the one that only says it's cooked, where no
        // way of cooking was asked for: a chicken breast is "Chicken breast, cooked, without
        // skin" before the grilled one.
        if !row.text.branded, match.missing == 0 {
            let said = row.text.titled
            // Where "cooked" isn't the word being typed, which names no food.
            let onlyCooked = !saidCooked && said.contains(plainlyCooked) && !saidStems.contains(where: { starts(plainlyCooked, $0) })
            if onlyCooked, !said.contains(where: { $0 != plainlyCooked && cookedWords.contains($0) }) { score += 0.02 }
            // Skin that wasn't said is left off, and one that doesn't say is the food either way.
            if !saidStems.contains("skin") {
                let name = row.food.name
                score -= name.hasSuffix(", with skin") ? 0.02 : name.hasSuffix(", without skin") ? 0.01 : 0
            }
            // And the one named by nothing but what was said, cooked: "Lamb, cooked" before the
            // composite of its retail cuts.
            if onlyCooked, match.others == 0, said.allSatisfy({ w in w == plainlyCooked || saidStems.contains { same(w, $0) } }) { score += 0.1 }
        }
        // A drink or a dish of two foods isn't the second of them: for "diet cola" the survey's
        // "Whiskey and diet cola" came before the cola, and "Gin and tonic" second for tonic.
        // Where the words say something of what follows the "and" and nothing of what's
        // before it; a name begun ("mac" for macaroni and cheese) is its first food's.
        if !row.text.branded, !row.called, match.missing == 0, let after = row.text.joint.min() {
            let text = row.text
            let said = { (run: Int) in
                text.said.indices.contains { i in text.runs[i] == run && askedForms.contains { same(text.said[i], $0) || starts(text.said[i], $0) } }
            }
            if said(after), !text.said.indices.contains(where: { text.runs[$0] < after && said(text.runs[$0]) }) { score -= 0.75 }
        }
        // The skin alone isn't the food, where skin wasn't asked for: KFC's "Skin and
        // Breading" for its original recipe chicken, a baked potato's "skin" for the potato.
        if !row.called, match.missing == 0, row.text.skinAlone, !askedForms.contains("skin") { score -= 0.5 }
        // Of the sizes a plain food comes in, where none was asked for, the middle one: a
        // burger's medium patty, a pizza's medium crust.
        if !row.text.branded, match.missing == 0, row.text.titled.contains("medium"), !saidStems.contains("medium") { score += 0.03 }
        // From a chain, the food as a restaurant serves it, before the one named by exactly
        // the words said: their fries have the fryer's oil. The words that say so don't count
        // against it, and of two the one from that kind of place is a little ahead.
        // The food itself, not a dish of theirs it's in: a bagel isn't their bagel with egg and sausage.
        // Not the espresso that is only "restaurant-prepared", which isn't a coffee from one.
        if let place = hints.out, !row.text.branded, match.missing == 0, match.mixed.isEmpty, row.text.titled.contains(where: placeWords.contains),
            !row.text.titled.contains(where: { cuisineWords.contains($0) && !saidStems.contains($0) })
                || match.extra.allSatisfy({ fromWords.contains($0) || cuisineWords.contains($0) }),
            !row.food.name.contains("restaurant-prepared")
        {
            score += 1.5 + (row.dish ? 0 : 0.25 * Double(match.extra.filter(fromWords.contains).count)) + (row.text.titled.contains(place) ? 0.1 : 0)
        }
        // Another country's product, as much as four words the search didn't ask for: it still
        // answers a search nothing sold here matches as well ("Domino's" in France or the US).
        if hints.away.contains(row.food.id) { score -= 1 }
        // Numbers that can't be right (kilojoules as calories, a powder's values on a drink) rank
        // below every plausible food that matches as well.
        if !row.plausible { score -= 1.5 }
        // The brand a model named is on the food as its brand, not a word of its name: a label
        // called "Chipotle Mango Burrito Bowl" isn't Chipotle's.
        let made = asked || (!maker.isEmpty && maker.allSatisfy { word in row.text.own.contains { same($0, word) || same(word, $0) } })
        let mine = made && row.mine && row.name >= 1 && (row.food.source == .usda || row.like >= 0)
        ranked.append(
            Ranked(food: row.food, score: score, index: index, name: row.name, called: row.called, calling: row.calling, mine: mine))
    }
    // A label with no calories, protein, carbs or fat was entered without its numbers, where
    // labels named the same have plenty: it ranks with the foods whose numbers can't be right.
    // Not a drink or a sweetener, which may have none; nor where the others have few, as
    // pickles do.
    let blanks = ranked.indices.filter { i in
        let row = rows[ranked[i].index]
        return row.plausible && row.match.missing == 0 && Plausibility.isBlank(row.food)
    }
    if !blanks.isEmpty {
        let named = { (food: Food) in words(food.name).map(stem).sorted() }
        var numbers: [[String]: [Double]] = [:]
        for found in ranked where found.food.source == .off && found.food.nutrients.kcal > 0 {
            numbers[named(found.food), default: []].append(found.food.nutrients.kcal)
        }
        for i in blanks {
            let others = (numbers[named(ranked[i].food)] ?? []).sorted()
            if others.count > 1, others[others.count / 2] >= 50 { ranked[i].score -= 1.5 }
        }
    }
    // A generic food found by a chain's name for it stands in for the chain's item, so the chain's
    // own comes just before it though no brand was typed: SR Legacy's McDonald's McNuggets, then
    // chicken nuggets from fast food; a Starbucks mocha Frappuccino, then a frozen mocha coffee
    // drink. The chain's own has the name's every word outside brackets, so a Big Mac "(without
    // Big Mac Sauce)" isn't Big Mac sauce.
    // A chain's name for an item, that is: a label listed under "Carnita" isn't whose
    // carnitas the catalog's other name "Carnitas" means, nor is a label that shouts "PASTA"
    // with no brand the maker of its "Pasta with chicken".
    // Nor is a label listed under a food's own word the maker of the food by that name: a
    // crisp bar listed under "Cereal" isn't whose "Cereal bar" the catalog means.
    // Nor one listed under words the plain foods found have for themselves: a sausage roll
    // listed under "Patties" isn't whose "Sausage patty" the catalog means.
    let plainSaid = Set(rows.lazy.filter { !$0.text.branded }.flatMap(\.text.said))
    let isTheirs = { (row: Row, other: FoodText) in
        row.other == nil && row.name == 1 && !row.text.own.isEmpty && other.titled.count > row.text.own.count
            && !(row.text.own.count == 1 && EverydayPhrases.isWord(row.text.own[0]))
            && !row.text.own.allSatisfy(plainSaid.contains)
            // A label someone has scanned, or one of a brand people scan: fish fingers
            // aren't the one unscanned label's whose brand was entered as "Fingers", where
            // a Frappuccino is Starbucks' whichever of its labels says only that.
            && (row.food.source == .usda
                || (row.food.brand != nil && (row.food.popularity > 0 || popularBrands.contains(bare(row.text.ownWords[0])))))
            && row.text.own.allSatisfy { w in other.titled.contains { same($0, w) } }
            && other.titled.allSatisfy { w in row.text.own.contains { same(w, $0) } || row.text.said.contains { same(w, $0) } }
    }
    if rows.contains(where: { $0.other != nil }) {
        for i in ranked.indices {
            guard let other = rows[ranked[i].index].other,
                let theirs = ranked.indices.filter({ isTheirs(rows[ranked[$0].index], other) }).max(by: { ranked[$0].score < ranked[$1].score })
            else { continue }
            if ranked[theirs].score <= ranked[i].score { ranked[theirs].score = ranked[i].score + 0.01 }
        }
    }
    // The foods of a long-shot correction come after the best food that has the words as typed,
    // however that one is named: chicken after "McDONALD'S, McCHICKEN Sandwich" for "mcchicken".
    if literal, let best = ranked.filter({ isAsTyped(rows[$0.index]) }).map(\.score).max() {
        for i in ranked.indices where rows[ranked[i].index].match.fixed > 0 && ranked[i].score >= best { ranked[i].score = best - 0.01 }
    }
    ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
    return ranked
}

/// Whether a name has a number the search put before a food: "12 grain" in "12 Grain Bread".
private func counted(_ list: [String], _ count: String, _ next: String) -> Bool {
    let wanted = stem(next)
    return list.indices.contains { i in list[i] == count && starts(stem(i + 1 < list.count ? list[i + 1] : ""), wanted) }
}

/// Whether a name has a size the search asked for in inches: 14 in `PAPA JOHN'S 14" Pepperoni
/// Pizza`, "14 Inch Pepperoni Pizza" or "14in", not in "14 oz".
private func sized(_ list: [String], _ size: String) -> Bool {
    list.indices.contains { i in
        if list[i] == size { return i + 1 == list.count || !unitWords.contains(list[i + 1]) }
        return starts(list[i], size) && inchWords.contains(String(list[i].dropFirst(size.count)))
    }
}

/// Orders foods for a typed search; foods that don't match it are left out.
func rankSearch(_ query: String, _ foods: [Food], known: [String: Double] = [:], hints: RankHints = RankHints()) -> [Ranked] {
    scoreFoods(Named(name: query, brand: ""), foods, known: known, search: true, hints: hints)
}

func rankSearch(_ query: String, _ entries: [Entry], known: [String: Double] = [:], hints: RankHints = RankHints()) -> [Ranked] {
    scoreFoods(Named(name: query, brand: ""), entries, known: known, search: true, hints: hints)
}

/// Whether a food answers a typed search, for the person's own lists; see `QueryMatcher`.
func matchesQuery(_ query: String, _ food: Food, fixes: Fixes = [:]) -> Bool {
    QueryMatcher(query, fixes: fixes).matches(food)
}
