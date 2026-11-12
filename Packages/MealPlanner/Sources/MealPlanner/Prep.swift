import Foundation
import SystemCore

/// One step of prep day, timed from the start.
public struct PrepStep: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Minutes from the start.
    public var minute: Int
    public var minutes: Int
    public var title: String
    public var detail: String
    /// The cook is busy (chopping, stirring) rather than waiting on the oven or a pot.
    public var handsOn: Bool
    /// A few words for a rail of steps: "Rice on", "Prep chicken", "Box it up".
    public var label: String
    /// What it's called while it cooks, and where, once it's on: a step that waits on the oven or a pot.
    public var timer: PrepTimer?
    /// What goes on the scale in this step, against what the plan asked for.
    public var weigh: PrepWeigh?
    /// The dishes (recipe ids) a part of is in once this step is done: a pot, a tray in the oven, a sauce.
    public var dishes: [String]
}

/// A step that cooks by itself once it's on: its name on a timer and where it is.
public struct PrepTimer: Hashable, Sendable {
    /// "White rice", "Broccoli and green beans".
    public var name: String
    /// "Hob, lid on", "Oven, 220°C (425°F)".
    public var place: String
}

/// A batch weighed before it cooks: what the plan asked for, raw or dry, for every dish it goes in.
public struct PrepWeigh: Hashable, Sendable {
    public var ingredientID: String
    public var name: String
    /// What's weighed: "dry" for a grain, "raw" for the rest.
    public var form: String
    /// Grams to weigh, as planned.
    public var grams: Double
    /// Water per gram dry, for a pot that absorbs it.
    public var water: Double?
    /// The dishes it goes in (recipe ids).
    public var dishes: [String]

    /// Whether a reading could be this batch: a quarter to four times the plan's amount. Anything
    /// else is a slip of the finger (4120 for 412), not what the cook has.
    public func accepts(_ reading: Double) -> Bool {
        reading.isFinite && reading >= grams / 4 && reading <= grams * 4
    }

    /// Millilitres of water for what's on the scale, to the 50 ml the steps say.
    public func water(for grams: Double) -> Int? {
        water.map { Int((grams * $0 / 50).rounded() * 50) }
    }
}

/// What goes in each container, and where it waits.
public struct Packing: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var servings: Int
    /// Per container, as eaten.
    public var contents: [(name: String, grams: Double)]
    /// Added when eating.
    public var onTheDay: [(name: String, grams: Double)]
    public var fridge: [Day]
    public var freezer: [Day]
    public var madeOnTheDay: Bool

    public static func == (a: Packing, b: Packing) -> Bool { a.id == b.id && a.servings == b.servings }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Prep day: the steps in order, overlapped so the oven and the stove are never idle while the
/// cook waits, and how to pack and store it all.
public struct PrepGuide: Hashable, Sendable {
    public var steps: [PrepStep]
    public var minutes: Int
    public var containers: Int
    public var packing: [Packing]

    static let oven = "220°C (425°F)"
    static let gentleOven = "180°C (350°F)"
    /// Grams of raw food a sheet tray roasts without crowding.
    static let trayGrams = 1200.0

    /// A cooking job: something on a tray, in a pot or pan, or made by hand.
    struct Job {
        enum Place { case tray(trays: Int), stove, pan, hands, bake }
        var title: String
        var detail: String
        var place: Place
        /// Cooking time (or hands time, for hands jobs).
        var minutes: Int
        /// Hands time to get it ready first: chopping, seasoning.
        var prep: Int
        var label: String
        var weigh: PrepWeigh?
        var dishes: [String]
    }

    public static func make(for plan: MealPlan) -> PrepGuide {
        var jobs: [Job] = []
        var packing: [Packing] = []
        var containers = 0
        // Raw grams for each grain or pasta: one pot cooks it for every bowl it's in.
        var pots: [(ingredient: Ingredient, raw: Double, dishes: [String])] = []

        for recipe in plan.recipes where recipe.servings > 0 {
            let n = Double(recipe.servings)
            let meals = plan.meals.filter { $0.recipeID == recipe.id }
            packing.append(
                Packing(
                    id: recipe.id, title: recipe.title, servings: recipe.servings,
                    contents: recipe.items.filter { !$0.onTheDay }.map { ($0.name, $0.grams) },
                    onTheDay: recipe.items.filter(\.onTheDay).map { ($0.name, $0.grams) },
                    fridge: meals.filter { $0.storage == .fridge }.map(\.day),
                    freezer: meals.filter { $0.storage == .freezer }.map(\.day),
                    madeOnTheDay: recipe.madeOnTheDay))
            if recipe.madeOnTheDay { continue }
            switch recipe.kind {
            case .bowl:
                containers += recipe.servings
                let profile = recipe.profileID.flatMap(Library.profile)
                let spices = profile?.spices.filter { !["Garlic", "Fresh ginger"].contains($0) }.map { $0.lowercased() } ?? []
                let season = spices.isEmpty ? "salt and pepper" : "salt, pepper and \(list(spices))"
                for item in recipe.items where !item.onTheDay {
                    guard let ingredient = Library.ingredient(item.ingredientID) else { continue }
                    let raw = item.grams * n / ingredient.yield
                    let amount = Self.amount(raw, ingredient)
                    let weigh = Self.weigh(ingredient, raw: raw, dishes: [recipe.id])
                    switch ingredient.cooking {
                    case .roast(let minutes):
                        let what = "\(amount) \(ingredient.name.lowercased())"
                        let cut =
                            ingredient.role == .protein
                            ? "Pat dry \(what)" : (ingredient.role == .carb ? "Cut \(what) into 2 cm cubes" : "Cut \(what) into bite-size pieces")
                        jobs.append(
                            Job(
                                title: "Roast the \(ingredient.name.lowercased())",
                                detail: "\(cut), toss with some of the olive oil and \(season), and spread on a tray. \(minutes) minutes at \(oven).",
                                place: .tray(trays: max(1, Int((raw / trayGrams).rounded(.up)))), minutes: minutes,
                                prep: ingredient.role == .protein ? 4 : 6, label: ingredient.short, weigh: weigh, dishes: [recipe.id]))
                    case .simmer, .boil:
                        if let i = pots.firstIndex(where: { $0.ingredient.id == ingredient.id }) {
                            pots[i].raw += raw
                            pots[i].dishes.append(recipe.id)
                        } else {
                            pots.append((ingredient, raw, [recipe.id]))
                        }
                    case .pan(let minutes):
                        jobs.append(
                            Job(
                                title: "Cook the \(ingredient.name.lowercased())",
                                detail:
                                    "Brown \(amount) \(ingredient.name.lowercased()) in a large pan with a little oil, \(minutes) minutes, then season with \(season).",
                                place: .pan, minutes: minutes, prep: 1, label: "Brown the \(ingredient.short)", weigh: weigh,
                                dishes: [recipe.id]))
                    case .bake, .none:
                        if ingredient.id == "black-beans" || ingredient.id == "chickpeas" {
                            jobs.append(
                                Job(
                                    title: "Open the \(ingredient.short)", detail: "Drain and rinse \(amount) \(ingredient.short).",
                                    place: .hands, minutes: 2, prep: 0, label: "Open the \(ingredient.short)", weigh: nil,
                                    dishes: [recipe.id]))
                        } else if ingredient.role == .vegetable, profile?.sauce.contains(where: { $0.id == ingredient.id }) != true {
                            jobs.append(
                                Job(
                                    title: "Wash the \(ingredient.short)",
                                    detail:
                                        "Wash \(amount) \(ingredient.name.lowercased()); pack it raw (it wilts into the warm food when reheated).",
                                    place: .hands, minutes: 2, prep: 0, label: "Wash the \(ingredient.short)", weigh: weigh,
                                    dishes: [recipe.id]))
                        }
                    }
                }
                if let step = profile?.sauceStep {
                    let protein = recipe.items.first { Library.ingredient($0.ingredientID)?.role == .protein }?.name.lowercased() ?? "protein"
                    let sauce = recipe.items.filter { item in profile?.sauce.contains { $0.id == item.ingredientID } == true }
                        .map { "\(Self.amount($0.grams * n, Library.ingredient($0.ingredientID)!)) \($0.name.lowercased())" }
                    jobs.append(
                        Job(
                            title: "Make the \(profile!.inSentence) sauce",
                            detail: step.replacingOccurrences(of: "{protein}", with: protein) + (sauce.isEmpty ? "" : " You need \(list(sauce))."),
                            place: .hands, minutes: ["curry", "italian", "japanese-curry"].contains(profile!.id) ? 14 : 5, prep: 0,
                            label: "\(profile!.name) sauce", weigh: nil, dishes: [recipe.id]))
                }
            case .template:
                guard let template = recipe.templateID.flatMap(Library.template) else { continue }
                let parts = recipe.items.filter { !$0.onTheDay }.map { "\(Self.grams($0.grams)) \($0.name.lowercased())" }
                let eggs = Int((recipe.items.filter { $0.ingredientID.contains("eggs") }.map(\.grams).reduce(0, +) * n / 50).rounded(.up))
                let perDay = Int((recipe.items.first { $0.ingredientID == "eggs" }?.grams ?? 0) / 50 + 0.5)
                let text = template.make.replacingOccurrences(of: "{servings}", with: "\(recipe.servings)")
                    .replacingOccurrences(of: "{parts}", with: list(parts))
                    .replacingOccurrences(of: "{eggs}", with: "\(eggs)")
                    .replacingOccurrences(of: "{perDay}", with: perDay == 1 ? "One" : "\(perDay)")
                switch template.cooking {
                case .bake(let minutes):
                    jobs.append(
                        Job(
                            title: "Bake the \(template.name.lowercased())", detail: text, place: .bake, minutes: minutes, prep: 8,
                            label: template.name, weigh: nil, dishes: [recipe.id]))
                case .boil(let minutes):
                    jobs.append(
                        Job(
                            title: "Boil the eggs", detail: text, place: .stove, minutes: minutes + 5, prep: 1, label: "Eggs on", weigh: nil,
                            dishes: [recipe.id]))
                default:
                    jobs.append(
                        Job(
                            title: "Make the \(template.name.lowercased())", detail: text, place: .hands,
                            minutes: 3 + recipe.servings, prep: 0, label: template.name, weigh: nil, dishes: [recipe.id]))
                }
            }
        }
        jobs += pots.compactMap { potJob($0.ingredient, raw: $0.raw, dishes: $0.dishes) }
        var guide = schedule(jobs, containers: containers, plan: plan)
        guide.packing = packing
        return guide
    }

    /// One pot of a grain or pasta, for every bowl that uses it.
    static func potJob(_ ingredient: Ingredient, raw: Double, dishes: [String]) -> Job? {
        let amount = Self.amount(raw, ingredient)
        let name = ingredient.name.lowercased()
        var weigh = Self.weigh(ingredient, raw: raw, dishes: dishes)
        let label = "\(ingredient.short.capitalizedFirst) on"
        switch ingredient.cooking {
        case .simmer(let minutes, let water):
            weigh?.water = water
            let ml = weigh?.water(for: raw) ?? Int((raw * water / 50).rounded() * 50)
            return Job(
                title: "Cook the \(name)",
                detail:
                    "Rinse \(amount) \(name); bring to a boil with \(ml) ml water and a pinch of salt, then cover and simmer on low for \(minutes) minutes. Rest 5 minutes and fluff.",
                place: .stove, minutes: minutes + 5, prep: 2, label: label, weigh: weigh, dishes: dishes)
        case .boil(let minutes):
            return Job(
                title: "Boil the \(name)",
                detail:
                    "Boil \(amount) \(name) in plenty of salted water for \(minutes) minutes, a minute less than the packet says (it softens as it sits). Drain and toss with a little oil.",
                place: .stove, minutes: minutes + 8, prep: 1, label: label, weigh: weigh, dishes: dishes)
        default:
            return nil
        }
    }

    /// What to weigh for a batch: raw, or dry for a grain or pasta. Nothing for what's counted (cans,
    /// eggs, a block of tofu), which the steps give as a count.
    static func weigh(_ ingredient: Ingredient, raw: Double, dishes: [String]) -> PrepWeigh? {
        if let unit = ingredient.unit, ["can", "egg", "block"].contains(unit.name) { return nil }
        let dry: Bool
        switch ingredient.cooking {
        case .simmer, .boil: dry = true
        default: dry = false
        }
        return PrepWeigh(
            ingredientID: ingredient.id, name: ingredient.name, form: dry ? "dry" : "raw", grams: raw, water: nil, dishes: dishes)
    }

    /// Lays the jobs on a timeline: pots started first, the oven in rounds of two trays, hands
    /// jobs in the waits, egg muffins after the roasting (the oven drops to a gentler heat), then
    /// cooling and packing.
    static func schedule(_ jobs: [Job], containers: Int, plan: MealPlan) -> PrepGuide {
        var steps: [PrepStep] = []
        func add(
            _ minute: Int, _ minutes: Int, _ title: String, _ detail: String, hands: Bool, label: String, timer: PrepTimer? = nil,
            weigh: PrepWeigh? = nil, dishes: [String] = []
        ) {
            steps.append(
                PrepStep(
                    id: steps.count, minute: minute, minutes: minutes, title: title, detail: detail, handsOn: hands, label: label,
                    timer: timer, weigh: weigh, dishes: dishes))
        }
        let roasts = jobs.filter { if case .tray = $0.place { true } else { false } }.sorted { $0.minutes > $1.minutes }
        let stove = jobs.filter { if case .stove = $0.place { true } else { false } }.sorted { $0.minutes > $1.minutes }
        var handsJobs = jobs.filter {
            switch $0.place {
            case .hands, .pan: true
            default: false
            }
        }
        let bakes = jobs.filter { if case .bake = $0.place { true } else { false } }
        let jars =
            plan.recipes.contains { $0.templateID == "overnight-oats" && !$0.madeOnTheDay }
            ? plan.recipes.first { $0.templateID == "overnight-oats" }!.servings : 0

        var gear = ["\(containers) containers"]
        if jars > 0 { gear.append("\(jars) jars") }
        if !roasts.isEmpty { gear.append("2 trays") }
        // The pots all go at once: rice and eggs are two.
        if !stove.isEmpty { gear.append(stove.count == 1 ? "a large pot" : "\(stove.count) pots") }
        if jobs.contains(where: { if case .pan = $0.place { true } else { false } }) { gear.append("a large pan") }
        if !bakes.isEmpty { gear.append("a muffin tin") }
        let ovenNeeded = !roasts.isEmpty || !bakes.isEmpty
        add(
            0, 3, "Set up", (ovenNeeded ? "Heat the oven to \(roasts.isEmpty ? gentleOven : oven). " : "") + "Get out \(list(gear)).", hands: true,
            label: ovenNeeded ? "Oven on" : "Set up")
        var hands = 3
        var ovenFree = roasts.isEmpty ? 10 : 12
        var stoveDone = 0

        // Long pots first: they look after themselves.
        for job in stove {
            // A pot's name on its timer: "White rice", or "Eggs".
            let name = job.weigh?.name ?? job.title.replacingOccurrences(of: "Boil the ", with: "").capitalizedFirst
            let place = job.title.hasPrefix("Boil") ? "Hob, boiling" : "Hob, lid on"
            add(
                hands, job.minutes, job.title, job.detail, hands: false, label: job.label, timer: PrepTimer(name: name, place: place),
                weigh: job.weigh, dishes: job.dishes)
            stoveDone = max(stoveDone, hands + job.prep + job.minutes)
            hands += job.prep + 1
        }

        // Two trays at a time, the longest roasts first. A job is prepped once however many trays
        // it fills; two bowls roasting the same vegetable are two jobs, each with its own amount
        // and seasoning, so they're told apart by position, not title.
        var trays: [(job: Int, Job)] = []
        for (i, job) in roasts.enumerated() {
            if case .tray(let n) = job.place { trays += Array(repeating: (i, job), count: n) }
        }
        var prepared: Set<Int> = []
        var index = 0
        while index < trays.count {
            let round = Array(trays[index..<min(index + 2, trays.count)])
            index += round.count
            for (i, job) in round where !prepared.contains(i) {
                prepared.insert(i)
                add(
                    hands, job.prep, "Prep for the oven: \(job.title.replacingOccurrences(of: "Roast the ", with: ""))", job.detail, hands: true,
                    label: "Prep \(job.label)", weigh: job.weigh)
                hands += job.prep
            }
            let start = max(hands, ovenFree)
            let length = round.map(\.1.minutes).max() ?? 0
            let names = round.map { $0.1.title.replacingOccurrences(of: "Roast the ", with: "") }
            let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let shorter = round.map(\.1).filter { $0.minutes < length }
                .map { "Take the \($0.title.replacingOccurrences(of: "Roast the ", with: "")) out after \($0.minutes) minutes." }
            let shorts = round.map(\.1.label).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let detail = (["\(length) minutes at \(oven); turn halfway."] + shorter).joined(separator: " ")
            add(
                start, length, "Into the oven: \(list(unique))", detail, hands: false, label: "\(list(shorts).capitalizedFirst) in",
                timer: PrepTimer(name: list(unique).capitalizedFirst, place: "Oven, \(oven)"),
                dishes: round.flatMap(\.1.dishes).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } })
            ovenFree = start + length
            hands = start + 1
            // Hands jobs fill the wait.
            while let job = handsJobs.first, hands + job.minutes <= ovenFree + 3 {
                handsJobs.removeFirst()
                add(hands, job.minutes, job.title, job.detail, hands: true, label: job.label, weigh: job.weigh, dishes: job.dishes)
                hands += job.minutes
            }
        }
        for job in handsJobs {
            add(hands, job.minutes, job.title, job.detail, hands: true, label: job.label, weigh: job.weigh, dishes: job.dishes)
            hands += job.minutes
        }
        var end = max(hands, ovenFree, stoveDone)
        for job in bakes {
            hands = max(hands, roasts.isEmpty ? 0 : ovenFree - job.prep)
            add(
                hands, job.prep, "Mix the \(job.title.replacingOccurrences(of: "Bake the ", with: ""))", job.detail, hands: true,
                label: "Mix the \(job.label.lowercased())")
            let start = max(hands + job.prep, ovenFree + (roasts.isEmpty ? 0 : 3))
            add(
                start, job.minutes, job.title,
                roasts.isEmpty
                    ? "\(job.minutes) minutes at \(gentleOven)."
                    : "Turn the oven down to \(gentleOven); \(job.minutes) minutes.", hands: false, label: "\(job.label) in",
                timer: PrepTimer(name: job.label, place: "Oven, \(gentleOven)"), dishes: job.dishes)
            hands = start + 1
            end = max(end, start + job.minutes)
        }

        add(
            end, 15, "Cool", "Spread rice and grains on a tray so they cool fast. Everything goes in the fridge within 2 hours of cooking.",
            hands: false, label: "Cool", timer: PrepTimer(name: "Cooling", place: "On the counter"))
        let pack = 5 + (containers + 1) / 2
        let packing = "Divide each batch evenly: the container list below has each one's amounts."
        add(end + 15, pack, "Pack \(containers) containers", packing, hands: true, label: "Box it up")
        var store = ["Label each container with its day."]
        // Containers of one kind keep alike, so each kind gets one line.
        var kinds: [(title: String, fridge: Set<Day>, freezer: Set<Day>)] = []
        for recipe in plan.recipes where !recipe.madeOnTheDay {
            let meals = plan.meals.filter { $0.recipeID == recipe.id }
            let fridge = Set(meals.filter { $0.storage == .fridge }.map(\.day))
            let freezer = Set(meals.filter { $0.storage == .freezer }.map(\.day))
            let title = recipe.kind == .bowl ? "Lunches and dinners" : recipe.title
            if let i = kinds.firstIndex(where: { $0.title == title }) {
                kinds[i].fridge.formUnion(fridge)
                kinds[i].freezer.formUnion(freezer)
            } else {
                kinds.append((title, fridge, freezer))
            }
        }
        for kind in kinds {
            var line = "\(kind.title): fridge \(span(kind.fridge))"
            if !kind.freezer.isEmpty { line += ", freezer \(span(kind.freezer))" }
            store.append(line + ".")
        }
        if kinds.contains(where: { !$0.freezer.isEmpty }) { store.append("Each evening, move the next day's from the freezer to the fridge.") }
        add(end + 15 + pack, 3, "Store", store.joined(separator: " "), hands: true, label: "Store")
        return PrepGuide(
            steps: steps.sorted { $0.minute != $1.minute ? $0.minute < $1.minute : $0.id < $1.id }, minutes: end + 15 + pack + 3,
            containers: containers, packing: [])
    }

    /// "Mon–Wed", or "Mon, Wed and Fri".
    static func span(_ days: Set<Day>) -> String {
        let sorted = days.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if first.days(until: last) == sorted.count - 1, sorted.count > 2 { return "\(first.weekday.short)–\(last.weekday.short)" }
        return list(sorted.map(\.weekday.short))
    }

    /// "1.6 kg", "450 g", or a count for things bought whole ("3 cans").
    static func amount(_ grams: Double, _ ingredient: Ingredient) -> String {
        if let unit = ingredient.unit, ["can", "egg", "block"].contains(unit.name) {
            let n = max(1, Int((grams / unit.grams - 0.1).rounded(.up)))
            return "\(n) \(n == 1 ? unit.name : unit.plural) of"
        }
        return self.grams(grams)
    }

    static func grams(_ grams: Double) -> String {
        if grams >= 1000 { return String(format: "%.1f kg", (grams / 100).rounded() / 10) }
        return "\(Int((grams / (grams >= 100 ? 10 : 1)).rounded() * (grams >= 100 ? 10 : 1))) g"
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
