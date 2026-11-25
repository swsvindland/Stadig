import Foundation

// Foods typed in Spanish, and by their Hindi and Indian-English names, read as the English the
// catalogs' plain foods are named in. A dish the catalogs have under its own name ("huevos
// rancheros", "pozole", "dosa", "palak paneer") is found by it as typed; these are the words
// for foods they have only in English: "pollo" was pollock, "leche" dulce de leche, "papas"
// papayas and "aloo" almonds.

/// A Spanish word for a food, as the English word or words the catalogs use. Singular; a plural
/// in "s" or "es" is read by it.
private let spanishWords: [String: String] = [
    // Meat, poultry, fish and eggs.
    "pollo": "chicken", "pechuga": "chicken breast", "muslo": "chicken thigh", "alitas": "chicken wings", "carne": "meat", "res": "beef",
    "cerdo": "pork", "puerco": "pork", "cordero": "lamb", "pavo": "turkey", "jamon": "ham", "tocino": "bacon", "tocineta": "bacon",
    "salchicha": "sausage", "chuleta": "pork chop", "costilla": "ribs", "bistec": "steak", "higado": "liver", "pescado": "fish",
    "atun": "tuna", "camaron": "shrimp", "langosta": "lobster", "cangrejo": "crab", "pulpo": "octopus", "calamar": "squid",
    "sardina": "sardines", "huevo": "egg", "lengua": "beef tongue",
    // Dairy.
    "leche": "milk", "queso": "cheese", "mantequilla": "butter", "crema": "cream", "yogur": "yogurt", "helado": "ice cream",
    // Grains, beans and the pantry.
    "arroz": "rice", "frijol": "beans", "habichuela": "beans", "lenteja": "lentils", "avena": "oatmeal", "pan": "bread",
    "harina": "flour", "azucar": "sugar", "sal": "salt", "pimienta": "black pepper", "aceite": "oil", "vinagre": "vinegar",
    "miel": "honey", "mermelada": "jam", "mayonesa": "mayonnaise", "mostaza": "mustard", "bolillo": "french roll",
    // Vegetables.
    "papa": "potato", "papas": "potato", "patata": "potato", "camote": "sweet potato", "batata": "sweet potato", "tomate": "tomato",
    "jitomate": "tomato",
    "cebolla": "onion", "ajo": "garlic", "zanahoria": "carrot", "lechuga": "lettuce", "espinaca": "spinach", "brocoli": "broccoli",
    "coliflor": "cauliflower", "repollo": "cabbage", "pepino": "cucumber", "calabaza": "squash",
    "calabacita": "zucchini", "calabacin": "zucchini", "ejote": "green beans", "chicharo": "peas", "guisante": "peas", "maiz": "corn",
    "champinon": "mushrooms", "hongo": "mushrooms", "aguacate": "avocado", "palta": "avocado", "apio": "celery", "betabel": "beets",
    "remolacha": "beets", "berenjena": "eggplant", "esparrago": "asparagus", "rabano": "radish", "verdura": "vegetables",
    // Fruit and nuts.
    "manzana": "apple", "naranja": "orange", "mandarina": "tangerine", "toronja": "grapefruit", "fresa": "strawberries",
    "frambuesa": "raspberries", "arandano": "blueberries", "uva": "grapes", "pina": "pineapple", "sandia": "watermelon",
    "durazno": "peach", "melocoton": "peach", "pera": "pear", "ciruela": "plum", "cereza": "cherries", "guayaba": "guava",
    "nuez": "walnuts", "nueces": "walnuts", "almendra": "almonds", "cacahuate": "peanuts", "cacahuete": "peanuts", "mani": "peanuts",
    "pistache": "pistachios", "pistacho": "pistachios", "fruta": "fruit",
    // Drinks, sweets and dishes by a plain word.
    "agua": "water", "jugo": "juice", "zumo": "juice", "cerveza": "beer", "vino": "wine", "refresco": "soda", "cafe": "coffee",
    "te": "tea", "galleta": "cookies", "pastel": "cake", "palomitas": "popcorn", "papitas": "potato chips", "gelatina": "gelatin dessert",
    "sopa": "soup", "caldo": "broth", "ensalada": "salad", "hamburguesa": "hamburger", "coco": "coconut",
]

/// Spanish words for a colour or for how a food is cooked or comes, which say which food only
/// beside its name: "blanco" alone is no food.
private let spanishKinds: [String: String] = [
    "blanco": "white", "blanca": "white", "negro": "black", "negra": "black", "rojo": "red", "roja": "red", "verde": "green",
    "amarillo": "yellow", "amarilla": "yellow", "frito": "fried", "frita": "fried", "asado": "grilled", "asada": "grilled",
    "cocido": "cooked", "cocida": "cooked", "hervido": "boiled", "hervida": "boiled", "horneado": "baked", "horneada": "baked",
    "revuelto": "scrambled", "molido": "ground", "molida": "ground", "crudo": "raw", "cruda": "raw", "fresco": "fresh",
    "fresca": "fresh", "entero": "whole", "entera": "whole", "descremada": "skim", "rallado": "shredded", "enlatado": "canned", "congelado": "frozen",
    "congelada": "frozen", "refrito": "refried", "pinto": "pinto",
]

/// Spanish foods read as Spanish only beside another word: alone each is an English word, a
/// food by that very name, or as far as another is typed. "Pan" is on its way to pancakes,
/// "queso" is the dip, "pina" a pina colada begun, "res" Reese's and "coco" cocoa, and
/// "pasteles" are the Puerto Rican dish.
private let spanishOnlyBeside: Set<String> = ["pan", "queso", "crema", "sal", "te", "cafe", "papa", "mani", "pina", "res", "coco", "pasteles"]

/// Words that are the same food in both languages, which a Spanish name may have beside its
/// Spanish ones: a "tortilla de maiz" is a corn tortilla.
private let sameInSpanish: Set<String> = [
    "tortilla", "chorizo", "salsa", "mango", "papaya", "melon", "salmon", "tilapia", "chocolate", "cilantro", "jalapeno", "taco", "burrito",
    "quesadilla", "guacamole", "cereal", "pasta", "pizza", "sandwich", "tofu", "quinoa", "granola", "kiwi", "banana", "cheddar",
    "mozzarella", "chile", "yogurt",
]

/// Spanish names that aren't the sum of their words, in English; and the ones the catalogs
/// have under their Spanish name, which stay as typed (nil).
private let spanishPhrases: [String: String?] = [
    "papas fritas": "french fries", "papas a la francesa": "french fries", "pure de papa": "mashed potatoes",
    "pure de papas": "mashed potatoes", "carne molida": "ground beef", "carne de res": "beef", "carne de cerdo": "pork",
    "carne de puerco": "pork", "arroz integral": "brown rice", "pan integral": "whole wheat bread", "pan tostado": "toast",
    "arroz con leche": "rice pudding", "huevo duro": "hard boiled egg", "huevos duros": "hard boiled egg",
    "huevo cocido": "hard boiled egg", "huevos cocidos": "hard boiled egg", "huevo estrellado": "fried egg",
    "huevos estrellados": "fried egg", "clara de huevo": "egg whites", "claras de huevo": "egg whites", "queso crema": "cream cheese",
    "crema de cacahuate": "peanut butter", "crema de mani": "peanut butter", "mantequilla de mani": "peanut butter",
    "mantequilla de cacahuate": "peanut butter", "leche descremada": "skim milk", "leche de soya": "soy milk",
    "agua mineral": "sparkling water", "cafe negro": "black coffee",
    "chuleta de cerdo": "pork chop", "chuleta de puerco": "pork chop", "pechuga de pollo": "chicken breast",
    "pechuga de pavo": "turkey breast", "muslo de pollo": "chicken thigh", "alitas de pollo": "chicken wings",
    "aceite de oliva": "olive oil", "nuez de la india": "cashews", "platano macho": "plantain",
    "leche de avena": "oat milk", "a la plancha": "grilled", "a la parrilla": "grilled", "al horno": "baked", "al vapor": "steamed",
    // As typed: the catalogs' own names.
    "carne asada": nil, "al pastor": nil, "pan dulce": nil, "dulce de leche": nil, "pico de gallo": nil, "arroz con pollo": nil,
    "arroz con gandules": nil, "caldo de pollo": nil, "sopa de pollo": nil, "caldo de res": nil, "sopa de fideo": nil, "agua fresca": nil,
    "queso fresco": nil, "tres leches": nil, "chile relleno": nil, "chile verde": nil, "salsa verde": nil, "salsa roja": nil,
    "chile con queso": nil, "chili con carne": nil, "pollo asado": nil, "caldo verde": nil, "pan de sal": nil, "cafe con leche": nil,
    "queso blanco": nil, "arroz con frijoles": nil, "arroz con frijoles negros": nil, "arroz con habichuelas": nil,
]

/// What joins two foods in a Spanish name, in English.
private let spanishJoins: [String: String] = ["con": "with", "y": "and"]

/// Words of a Spanish name that say nothing in English: "pechuga de pollo", "papas a la francesa".
private let spanishParticles: Set<String> = ["de", "del", "la", "el", "los", "las", "al"]

/// A food by its Hindi name or its Indian-English one, in English. These mean no other food
/// anywhere, so they're read in every region; "curd" and "lady finger", which do, are read by
/// the phone's region (see `regionalNames`).
private let hindiWords: [String: String] = [
    "brinjal": "eggplant", "baingan": "eggplant", "bhindi": "okra", "maida": "all purpose flour", "atta": "whole wheat flour",
    "dal": "lentil curry", "daal": "lentil curry", "dhal": "lentil curry", "chana": "chickpeas", "chole": "chickpeas", "rajma": "kidney beans",
    "aloo": "potato", "gobi": "cauliflower", "gobhi": "cauliflower", "palak": "spinach", "dahi": "yogurt", "doodh": "milk",
    "anda": "egg", "murgh": "chicken", "keema": "ground meat", "methi": "fenugreek", "jeera": "cumin", "haldi": "turmeric",
    "dhania": "coriander", "adrak": "ginger", "lehsun": "garlic", "pyaz": "onion", "tamatar": "tomato", "kela": "banana",
    "aam": "mango", "seb": "apple", "nimbu": "lemon", "chawal": "rice", "sooji": "semolina", "suji": "semolina", "rava": "semolina",
    "sabudana": "tapioca", "makhan": "butter", "pulao": "rice pilaf", "pulav": "rice pilaf", "kheer": "rice pudding",
    "phulka": "roti", "moong dal": "mung beans", "masoor dal": "red lentils", "toor dal": "pigeon peas", "chana dal": "chickpeas",
    "curd rice": "rice with yogurt", "matar": "peas", "gajar": "carrot", "kaju": "cashews", "badam": "almonds", "shakkar": "sugar",
    "namak": "salt",
]

/// A search typed in Spanish, or one that is a food's Hindi name, as it reads in English: "pollo"
/// is chicken, "pechuga de pollo" chicken breast, "arroz blanco" white rice, "huevos con chorizo"
/// eggs with chorizo and "aloo" potato. Nil where any word isn't one of these, the name is one
/// the catalogs have as typed, or the one word typed is also an English one.
///
/// Spanish says the food first and what kind after ("jugo de naranja", "frijoles negros"), so
/// the words of each food come out the other way round; an amount typed first stays first.
func inEnglish(_ typed: String) -> String? {
    var said = tokens(typed)
    var amount: [String] = []
    while let first = said.first, isNumber(first) { amount.append(said.removeFirst()) }
    guard !said.isEmpty, said.count <= 6 else { return nil }
    let whole = said.joined(separator: " ")
    func counted(_ name: String) -> String { (amount + [name]).joined(separator: " ") }
    if let name = hindiWords[whole] { return counted(name) }
    // A name of its own, also in the plural: "carne asadas" is carne asada, left as typed.
    let singular = said.map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }.joined(separator: " ")
    if let phrase = spanishPhrases[whole] ?? spanishPhrases[singular] { return phrase.map(counted) }
    if said.count == 1, let key = spanishKey(said[0], in: spanishWords), spanishOnlyBeside.contains(key) { return nil }
    // Each food of the name, apart from what joins it to the next.
    var foods: [[String]] = [[]]
    var joins: [String] = []
    for word in said {
        if let join = spanishJoins[word], !(foods.last ?? []).isEmpty {
            joins.append(join)
            foods.append([])
        } else {
            foods[foods.count - 1].append(word)
        }
    }
    // Some word of it names a food in Spanish, and something says it's Spanish: a food's word
    // that is only that, a colour or a way, or what joins the words. "Pan pizza" and "queso
    // burrito" are English.
    var named = false
    var spanish = !joins.isEmpty
    var read: [String] = []
    for (at, food) in foods.enumerated() {
        guard !food.isEmpty else { return nil }
        // The longest names first: "pechuga de pollo" before "pechuga" and "pollo".
        var units: [String] = []
        var i = 0
        while i < food.count {
            var found = false
            for size in stride(from: min(4, food.count - i), through: 2, by: -1) {
                if case .some(.some(let name)) = spanishPhrases[food[i..<(i + size)].joined(separator: " ")] {
                    units.append(name)
                    named = true
                    spanish = true
                    i += size
                    found = true
                    break
                }
            }
            if found { continue }
            let word = food[i]
            i += 1
            if spanishParticles.contains(word) {
                spanish = true
                continue
            }
            if let key = spanishKey(word, in: spanishWords), let name = spanishWords[key] {
                units.append(name)
                named = true
                if !spanishOnlyBeside.contains(key) { spanish = true }
            } else if let key = spanishKey(word, in: spanishKinds), let kind = spanishKinds[key] {
                units.append(kind)
                spanish = true
            } else if sameInSpanish.contains(word) || sameInSpanish.contains(String(word.dropLast())) {
                units.append(word)
            } else {
                return nil
            }
        }
        guard !units.isEmpty else { return nil }
        read += units.reversed()
        if at < joins.count { read.append(joins[at]) }
    }
    return named && spanish ? counted(read.joined(separator: " ")) : nil
}

/// The word a table has a Spanish word under: itself, or its singular.
private func spanishKey(_ word: String, in words: [String: String]) -> String? {
    if words[word] != nil { return word }
    if word.hasSuffix("es"), words[String(word.dropLast(2))] != nil { return String(word.dropLast(2)) }
    if word.hasSuffix("s"), words[String(word.dropLast())] != nil { return String(word.dropLast()) }
    return nil
}
