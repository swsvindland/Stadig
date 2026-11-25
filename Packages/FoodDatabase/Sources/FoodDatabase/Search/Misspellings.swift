/// Food words as they're commonly misspelt, each with the word meant. The catalogs know most
/// of them, because labels carry the same misspellings (a few hundred each say "protien",
/// "mozarella" or "expresso") or are another language's ("taboule", "bolognaise"), so a search
/// for one found those labels and the typo reading left the word alone. None is a word USDA
/// writes or the start of the word meant, so a word still being typed is never read as one.
enum Misspellings {
    /// The word meant by a misspelling, as typed.
    static let meant: [String: String] = {
        var words: [String: String] = [:]
        for (right, wrong) in table { for word in wrong.split(separator: " ") { words[String(word)] = right } }
        return words
    }()

    private static let table: [(right: String, wrong: String)] = [
        ("broccoli", "brocolli brocoli broccolli brocholi"), ("avocado", "avacado avocato advocado avacodo"), ("tomato", "tomatoe"),
        ("tomatoes", "tomatos"), ("potato", "potatoe"), ("potatoes", "potatos"), ("banana", "bannana bananna"), ("bananas", "bannanas banannas"),
        ("strawberry", "strawbery strawberrie"), ("strawberries", "strawberrys strawberies"), ("raspberry", "rasberry razberry"),
        ("raspberries", "rasberries rasberrys"), ("blueberries", "blueberrys bluberries"), ("blackberries", "blackberrys"),
        ("cranberries", "cranberrys"), ("yogurt", "yogert yougurt yogart"), ("omelet", "omlet omlette omelete"),
        ("spaghetti", "spagetti spagheti spagetty"), ("lasagna", "lasanga lasagnia"), ("bolognese", "bolognaise bolognase"),
        ("parmesan", "parmesean parmasean parmesian parmasan"), ("mozzarella", "mozarella mozzerella mozerella mozzarela"),
        ("guacamole", "guacamoli guacomole guacamolie"), ("tortilla", "tortila tortia"), ("jalapeno", "jalepeno jalapino jalopeno"),
        ("chipotle", "chipolte chipotel"), ("sriracha", "siracha sirracha sriacha"), ("worcestershire", "worchestershire worchester"),
        ("cappuccino", "cappucino capuccino cappuchino"), ("macchiato", "machiato macciato"), ("frappuccino", "frappachino frapuccino frappucino"),
        ("espresso", "expresso"), ("smoothie", "smoothy smothie"), ("sherbet", "sherbert"), ("pistachio", "pistacio"),
        ("pistachios", "pistachos pistacios"), ("almond", "almound"), ("cashew", "cashu"), ("margarine", "margerine"),
        ("mayonnaise", "mayonaise mayonnase mayonaisse"), ("ketchup", "ketsup katsup"), ("vinaigrette", "vinagrette vinegarette vinegrette"),
        ("cereal", "ceral cerial"), ("bagel", "bagle"), ("croissant", "crossiant croisant crossant"), ("biscuit", "biscut"), ("waffle", "wafle"),
        ("pancake", "pankcake"), ("sausage", "sausauge sausge sasage"), ("bologna", "bolonga baloney bologne"), ("salami", "salomi"),
        ("prosciutto", "proscuitto prosciuto"), ("tilapia", "tilapa talapia"), ("salmon", "salman samon"), ("shrimp", "shrip"),
        ("cauliflower", "califlower cauliflour colliflower"), ("cucumber", "cucmber cucumer"), ("lettuce", "letuce lettus lettice"),
        ("spinach", "spinich spinnach"), ("asparagus", "asparagas aspargus"), ("eggplant", "egplant"), ("edamame", "edemame edamamme"),
        ("quinoa", "quinua keenwa"), ("barley", "barly"), ("lentils", "lentles"), ("garbanzo", "garbonzo"), ("raisins", "rasins"),
        ("pineapple", "pinapple pineaple"), ("watermelon", "watermellon"), ("cantaloupe", "cantalope cantelope canteloupe"),
        ("grapefruit", "grapefruite"), ("tangerine", "tangarine"), ("breast", "brest"), ("chicken", "chiken chickin"), ("beef", "beaf"),
        ("turkey", "turky"), ("steak", "stake"), ("hamburger", "hamberger hamburgar"), ("cheeseburger", "cheesburger cheseburger"),
        ("scrambled", "scrambeled"), ("butter", "buter"), ("cheddar", "chedder"), ("oatmeal", "oatmeel"), ("protein", "protien"), ("juice", "juce"),
        ("lemonade", "lemonaid"), ("chocolate", "choclate"), ("cheesecake", "cheescake"), ("tiramisu", "tiramasu"), ("noodle", "noodel"),
        ("chowder", "chowda"), ("dressing", "dresing"), ("sauce", "sause"), ("teriyaki", "terriyaki teryaki"),
        ("sandwich", "sandwhich sandwitch sanwich"), ("falafel", "fallafel falafal"), ("tabbouleh", "tabouli tabouleh tabbouli taboule"),
        ("baklava", "baclava"), ("cannoli", "canoli"), ("quesadilla", "quesedilla quesadila quesidilla"), ("burrito", "burito"),
        ("hummus", "humus hummas"), ("fettuccine", "fettucini fettuccini fetuccine"), ("caesar", "ceasar cesar ceaser"),
        ("zucchini", "zuchini zuccini zuchinni"), ("masala", "massala"), ("cheese", "chese"), ("pork chop", "porkchop"),
        ("pork chops", "porkchops"), ("sandwiches", "sandwhiches"), ("boiled", "boild"), ("ground", "grond"), ("thigh", "thight"),
        ("vegetable", "vegtable vegatable vegitable"), ("vegetables", "vegtables vegatables vegitables"), ("restaurant", "resturant restaraunt"),
        ("barbecue", "barbaque"), ("burritos", "buritos"), ("quesadillas", "quesedillas quesadilas"), ("tortillas", "tortilas"),
        ("avocados", "avacados"), ("omelette", "omellete"), ("cinnamon", "cinammon cinamon cinnamin"), ("vanilla", "vanila vannila"),
        ("zucchinis", "zuchinis"), ("broth", "brothe"), ("pasta", "pastta"), ("macaroni", "macoroni maccaroni macarroni"), ("ravioli", "raviolli"),
        ("gnocchi", "gnochi gnocci"), ("bruschetta", "brushetta bruchetta"), ("pepperoni", "peperoni pepporoni"), ("ricotta", "ricota"),
        ("mascarpone", "marscapone"), ("tofu", "tofoo"), ("turmeric", "tumeric"), ("cilantro", "cilentro celantro"), ("basil", "bazil"),
        ("oregano", "oregeno"), ("rosemary", "rosemarry"), ("molasses", "molases"), ("syrup", "sirup syrop"),
    ]
}
