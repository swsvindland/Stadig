import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Search as you type: saved meals and personal foods first, the last portion pre-filled, + logs in
/// one tap. While the AI's review is finding a food, what's picked goes there instead. The rows are
/// the composer's matches (`MatchRow`): a food's marker on the surface, its name and what it would
/// log, and the best match of what's typed on a card outlined in the accent, with the key that
/// logs it. On a phone the list rises from the field at the foot, as the composer's matches do: the
/// likeliest nearest the field, each group's best at its foot. In the pane, under its field, it
/// reads down from the top.
struct SearchLogView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    /// The phone's: anchored to the field below it, rather than to the field above.
    var fromBottom = false

    var query: String { session.query }
    var results: [FoodMatch] { session.results }
    var typed: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let quick = session.finding == nil ? session.quickAddPart : nil
        let groups = typed ? typedGroups(quick: quick) : suggestionGroups
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                // The pane's: the phone has it under the header, in sight while the list scrolls.
                if !fromBottom, session.finding != nil { LoggerReviewBanner(session: session).padding(.bottom, 6) }
                if typed, groups.isEmpty, !session.searching { noMatches }
                ForEach(Self.order(groups, fromBottom: fromBottom)) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, fromBottom ? 8 : 0)
            // Clear of the foot's fade, so the best one nearest the field reads whole.
            .padding(.bottom, fromBottom ? 22 : 12)
        }
        .defaultScrollAnchor(fromBottom ? .bottom : .top)
        .environment(\.fieldLogsBest, fromBottom)
        .scrollIndicators(.hidden)
        .dismissesKeyboardOnScroll()
        .accessibilityIdentifier("logger.results")
    }

    // MARK: What's listed

    /// A group of rows under its eyebrow, the likeliest first.
    struct Group {
        var title: String?
        var items: [Item]
    }

    enum Item: Identifiable {
        case section(String)
        case quickAdd(kcal: Double)
        case usual(Moment)
        case meal(SavedMeal)
        case food(Food, best: Bool)
        case again(LogAgainItem)
        case favorite(PersonalFood)
        case mine(Food)

        var id: String {
            switch self {
            case .section(let title): "section.\(title)"
            case .quickAdd: "quickAdd"
            case .usual(let moment): "usual.\(moment.id)"
            case .meal(let meal): "meal.\(meal.id)"
            case .food(let food, _): "food.\(food.id)"
            case .again(let item): "again.\(item.id)"
            case .favorite(let p): "favorite.\(p.food.id)"
            case .mine(let food): "mine.\(food.id)"
            }
        }
    }

    /// The groups as they're laid out: down from the top, or up from the field with the likeliest
    /// nearest it, group by group and row by row, each group under its eyebrow either way.
    static func order(_ groups: [Group], fromBottom: Bool) -> [Item] {
        let laid = fromBottom ? groups.reversed().map { Group(title: $0.title, items: $0.items.reversed()) } : groups
        return laid.flatMap { group in (group.title.map { [Item.section($0)] } ?? []) + group.items }
    }

    /// Something typed: calories typed as calories, the foods found (the first is what Return logs,
    /// so it's on the card with the key) and the saved meals that match. On a phone the foods are
    /// nearest the field, so the best of them sits on it; the pane keeps the meals over them.
    func typedGroups(quick: (part: AddFoodPart, kcal: Double)?) -> [Group] {
        var groups: [Group] = []
        if let quick { groups.append(Group(items: [.quickAdd(kcal: quick.kcal)])) }
        let meals = meals
        let foods = Group(
            title: meals.isEmpty || results.isEmpty ? nil : "Foods",
            items: results.enumerated().map { index, match in .food(match.food, best: index == 0 && session.finding == nil && quick == nil) })
        let mealGroup = Group(title: "My meals", items: meals.map(Item.meal))
        if fromBottom {
            if !foods.items.isEmpty { groups.append(foods) }
            if !meals.isEmpty { groups.append(mealGroup) }
        } else {
            if !meals.isEmpty { groups.append(mealGroup) }
            if !foods.items.isEmpty { groups.append(foods) }
        }
        return groups
    }

    /// Nothing typed: what's usual for the time being logged at. Saved meals and Log Again follow
    /// the time being logged at: lunch for noon, even when it's caught up at 9 PM. A usual moment
    /// that is a saved meal is in My Meals. Finding a food for a review, only what's one food can
    /// be its answer.
    var suggestionGroups: [Group] {
        var groups: [Group] = []
        if session.finding == nil, let usual = model.loggerUsual, SavedMeals.meal(for: usual.entries, in: model.savedMeals) == nil {
            groups.append(Group(title: "Same as \(Format.relative(Day(usual.start), today: model.today))", items: [.usual(usual)]))
        }
        let suggested = session.finding == nil ? model.loggerMeals : []
        if !suggested.isEmpty { groups.append(Group(title: "My meals", items: suggested.prefix(20).map { .meal($0.meal) })) }
        let again = session.again(model.loggerLogAgain)
        if !again.isEmpty {
            groups.append(
                Group(
                    title: model.timedSuggestions == nil ? "Log again" : "Log again for \(LogTime.time(model))",
                    items: again.prefix(12).map(Item.again)))
        }
        let favorites = model.personal.filter(\.favorite)
        if !favorites.isEmpty { groups.append(Group(title: "Favorites", items: favorites.prefix(20).map(Item.favorite))) }
        let mine = model.customFoods.map(\.food)
        if !mine.isEmpty { groups.append(Group(title: "My foods", items: mine.prefix(30).map(Item.mine))) }
        return groups
    }

    /// Saved meals with what's typed: the person's own handful, so no need to wait for the catalog,
    /// and read afresh each time, so a meal changed or deleted on its screen isn't logged as it was.
    var meals: [SavedMeal] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || session.finding != nil ? [] : SavedMeals.matching(text, in: model.loggerMeals.map(\.meal))
    }

    // MARK: Rows

    @ViewBuilder
    func row(_ item: Item) -> some View {
        switch item {
        case .section(let title):
            SectionEyebrow(title).padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 4)
        case .quickAdd(let kcal):
            QuickAddRow(kcal: kcal, add: { session.logQuickAdd(model) }, open: { session.openQuickAdd() })
        case .usual(let moment):
            UsualMomentRow(moment: moment)
        case .meal(let meal):
            mealRow(meal)
        case .food(let food, let best):
            FoodRow(food: food, personal: model.personalFood(food.id), best: best, add: { quickAdd(food) }, open: { open(food) })
        case .again(let item):
            RecentRow(item: item, add: { session.addAgain(item, model: model) }, open: { open(item) })
        case .favorite(let p):
            FoodRow(food: p.food, personal: p, add: { quickAdd(p.food) }, open: { open(p.food) })
        case .mine(let food):
            FoodRow(food: food, personal: model.personalFood(food.id), add: { quickAdd(food) }, open: { open(food) })
        }
    }

    var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(Ink.text3)
            Text("No matches").font(.headline).foregroundStyle(Ink.text)
            Text("Try fewer words, scan the barcode, or describe it.").font(.subheadline).foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Describe “\(query)”") { session.mode = .describe }
                    .lineLimit(1)
                Button("Quick add") { session.openQuickAdd() }
                    .accessibilityIdentifier("logger.noMatchesQuickAdd")
            }
            .buttonStyle(.ghost)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
        .padding(.top, 8)
    }

    func mealRow(_ meal: SavedMeal) -> some View {
        SavedMealRow(
            meal: meal,
            add: {
                model.log(meal)
                session.query = ""
                session.focusSearch()
            },
            open: {
                session.blurSearch()
                session.openMeal = meal.id
            })
    }

    /// The + button.
    func quickAdd(_ food: Food) { session.add(food, model) }

    func open(_ food: Food) {
        guard session.finding == nil else {
            session.use(food)
            return
        }
        session.blurSearch()
        session.portion = .add(food, source: .search)
    }

    func open(_ item: LogAgainItem) {
        if let id = item.template.foodID, let food = model.food(id: id) {
            open(food)
        } else if session.finding == nil {
            model.logAgain(item)
        }
    }
}

/// The meal the AI's review read, while the search is finding a food for it or has been gone to
/// from it: what the search is for, and the way back to the review.
struct LoggerReviewBanner: View {
    let session: LoggerSession

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 8)
            Button(session.finding != nil ? "Back to the meal" : "Back to it") { session.stopFinding() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("logger.backToReview")
        }
        .padding(.horizontal, 14)
        .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// "Pick a food for your meal", or the meal waiting: "From your photo · 3 foods".
    var title: String {
        guard session.finding == nil, let review = session.review else { return "Pick a food for your meal" }
        let count = review.items.count
        return "\(review.source == .photo ? "From your photo" : "From your words") · \(count) \(count == 1 ? "food" : "foods")"
    }
}

/// A row of the logger's lists: the composer's match (`MatchRow`), and beside it on the same card a
/// + that logs it at once. The row itself opens it. Where the field below logs the best one (a
/// phone's, with its arrow), the best has the key alone, as the composer's matches have.
struct LoggerRow<Tile: View>: View {
    @Environment(\.fieldLogsBest) private var fieldLogsBest
    let title: String
    /// The rest of a catalog name after the part a person would say ("meat only"), set quieter
    /// beside it: it tells close foods apart.
    var detail: String? = nil
    let caption: String
    var best = false
    var starred = false
    let addLabel: String
    let openIdentifier: String
    let addIdentifier: String
    let add: () -> Void
    let open: () -> Void
    @ViewBuilder let tile: Tile

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                MatchRow(title: Text.matchName(title, rest: detail), detail: caption, best: best, starred: starred) { tile }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityHint(best ? "Return logs it" : "")
            .accessibilityIdentifier(openIdentifier)
            if !(best && fieldLogsBest) {
                Button(action: add) { AddDisc(onCard: best) }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .accessibilityLabel(addLabel)
                    .accessibilityIdentifier(addIdentifier)
            }
        }
        .matchCard(best: best, trailing: best && fieldLogsBest ? 10 : 2)
    }
}

extension EnvironmentValues {
    /// The field under the logger's list logs its best match, with its arrow and Return: that row
    /// has the key and no + of its own.
    @Entry var fieldLogsBest = false
}

/// The logger's +: the accent on a disc, the surface's on the best one's card and the raised grey
/// elsewhere, in a 44-point target.
struct AddDisc: View {
    var onCard = false

    var body: some View {
        Image(systemName: "plus")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 36, height: 36)
            .background(onCard ? Ink.surface : Ink.raised, in: .circle)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
    }
}

/// A catalog food: name, the portion it would log, and a one-tap add.
struct FoodRow: View {
    let food: Food
    let personal: PersonalFood?
    var best = false
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        let suggestion = FoodUnits.suggested(
            for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
        let n = FoodUnits.nutrients(food, count: suggestion.count, unit: suggestion.unit)
        let amount = FoodUnits.label(count: suggestion.count, unit: suggestion.unit)
        let spoken = FoodLabel.spoken(food.name)
        LoggerRow(
            title: spoken.short, detail: spoken.rest,
            caption: [
                food.brand.flatMap { $0.lowercased() == food.name.lowercased() ? nil : $0 }, amount, Format.kcal(n.kcal),
                "\(Format.whole(n.protein)) P",
            ].compactMap { $0 }.joined(separator: " · "),
            best: best, starred: personal?.favorite == true,
            addLabel: "Add \(amount) of \(food.name)", openIdentifier: "logger.food", addIdentifier: "logger.addFood", add: add, open: open
        ) {
            FoodTile(name: food.name, size: 40, fill: best ? Ink.raised : Ink.surface)
        }
    }
}

/// A recently logged food, re-logged as it was.
struct RecentRow: View {
    let item: LogAgainItem
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        LoggerRow(
            title: FoodLabel.short(item.template.name),
            caption: [
                item.template.brand, item.template.amountLabel, Format.kcal(item.template.nutrients.kcal),
                "\(Format.whole(item.template.nutrients.protein)) P",
            ].compactMap { $0 }.joined(separator: " · "),
            addLabel: "Log \(item.template.name) again", openIdentifier: "logger.recent", addIdentifier: "logger.logAgain", add: add, open: open
        ) {
            FoodTile(name: item.template.name, size: 40, fill: Ink.surface)
        }
    }
}

/// What was eaten around the logger's time on another recent day, logged again whole with a tap.
struct UsualMomentRow: View {
    @Environment(AppModel.self) private var model
    let moment: Moment

    var body: some View {
        let name = model.name(of: moment)
        Button {
            model.logAgain(moment)
        } label: {
            HStack(spacing: 4) {
                MatchRow(
                    title: Text.matchName(name, rest: nil),
                    detail: "\(Format.time(moment.start)) · \(moment.entries.count) foods · \(Format.kcal(moment.nutrients.kcal))"
                ) {
                    MealTile(size: 40)
                }
                AddDisc()
            }
            .matchCard(best: false, trailing: 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Log \(name) again, \(moment.entries.count) foods, \(Format.kcal(moment.nutrients.kcal))")
        .accessibilityIdentifier("logger.sameAsUsual")
    }
}

/// Calories typed as calories ("300 kcal"), as the composer offers them: the number with no food,
/// logged with + or Return, or opened to add protein and the rest.
struct QuickAddRow: View {
    let kcal: Double
    let add: () -> Void
    let open: () -> Void

    var body: some View {
        LoggerRow(
            title: "Quick add \(Format.kcal(kcal))", caption: "Just the number, no food", best: true,
            addLabel: "Quick add \(Format.kcal(kcal))", openIdentifier: "logger.quickAddRow", addIdentifier: "logger.logQuickAdd", add: add,
            open: open
        ) {
            RoughTile(best: true)
        }
    }
}
