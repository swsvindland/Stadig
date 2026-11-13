import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Search as you type: saved meals and personal foods first, the last portion pre-filled, + logs in
/// one tap. While the AI's review is finding a food, what's picked goes there instead. The rows are
/// Today's: a food's marker on the surface, its name and what it would log, and the best match of
/// what's typed on a card outlined in the accent, with the key that logs it.
struct SearchLogView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession

    var query: String { session.query }
    var results: [FoodMatch] { session.results }
    var typed: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if session.finding != nil { finding }
                if !typed {
                    suggestions
                } else if results.isEmpty && meals.isEmpty && !session.searching {
                    noMatches
                } else {
                    if !meals.isEmpty {
                        section("My meals")
                        ForEach(meals) { mealRow($0) }
                        if !results.isEmpty { section("Foods") }
                    }
                    foodResults
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .dismissesKeyboardOnScroll()
        .accessibilityIdentifier("logger.results")
    }

    /// Picking a food for the review: what that's for, and the way back to it.
    var finding: some View {
        HStack(spacing: 12) {
            Text("Pick a food for your meal").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
            Spacer(minLength: 8)
            Button("Back to the meal") { session.stopFinding() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("logger.backToReview")
        }
        .padding(.horizontal, 14)
        .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
        .padding(.bottom, 6)
    }

    /// Nothing typed: what's usual for the time being logged at.
    @ViewBuilder
    var suggestions: some View {
        // Saved meals and Log Again follow the time being logged at: lunch for noon, even when it's
        // caught up at 9 PM. A usual moment that is a saved meal is in My Meals. Finding a food for
        // a review, only what's one food can be its answer.
        if session.finding == nil, let usual = model.loggerUsual, SavedMeals.meal(for: usual.entries, in: model.savedMeals) == nil {
            section("Same as \(Format.relative(Day(usual.start), today: model.today))")
            UsualMomentRow(moment: usual)
        }
        let suggested = session.finding == nil ? model.loggerMeals : []
        if !suggested.isEmpty {
            section("My meals")
            ForEach(suggested.prefix(20)) { mealRow($0.meal) }
        }
        let again = session.again(model.loggerLogAgain)
        if !again.isEmpty {
            section(model.timedSuggestions == nil ? "Log again" : "Log again for \(LogTime.time(model))")
            ForEach(again.prefix(12)) { item in
                RecentRow(item: item, add: { session.addAgain(item, model: model) }, open: { open(item) })
            }
        }
        let favorites = model.personal.filter(\.favorite)
        if !favorites.isEmpty {
            section("Favorites")
            ForEach(favorites.prefix(20), id: \.food.id) { p in
                FoodRow(food: p.food, personal: p, add: { quickAdd(p.food) }, open: { open(p.food) })
            }
        }
        let mine = model.customFoods.map(\.food)
        if !mine.isEmpty {
            section("My foods")
            ForEach(mine.prefix(30)) { food in
                FoodRow(food: food, personal: model.personalFood(food.id), add: { quickAdd(food) }, open: { open(food) })
            }
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
                Button("Quick add") { session.mode = .quickAdd }
                    .accessibilityIdentifier("logger.noMatchesQuickAdd")
            }
            .buttonStyle(.ghost)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
        .padding(.top, 8)
    }

    func section(_ title: String) -> some View {
        SectionEyebrow(title).padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 4)
    }

    /// Saved meals with what's typed: the person's own handful, so no need to wait for the catalog,
    /// and read afresh each time, so a meal changed or deleted on its screen isn't logged as it was.
    var meals: [SavedMeal] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || session.finding != nil ? [] : SavedMeals.matching(text, in: model.loggerMeals.map(\.meal))
    }

    /// The foods found. The first is what Return logs, so it's the one on a card with the key.
    var foodResults: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, match in
            FoodRow(
                food: match.food, personal: model.personalFood(match.food.id), best: index == 0 && session.finding == nil,
                add: { quickAdd(match.food) }, open: { open(match.food) })
        }
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

/// A row of the logger's lists as Today sets its matches (`.mrow`): the marker, the name over what it
/// would log, and a + that logs it at once. The row itself opens it. The best match of what's typed
/// sits on a card outlined in the accent, with the key that logs it.
struct LoggerRow<Tile: View>: View {
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

    private var nameText: Text {
        let name = Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
        guard let detail else { return name }
        let rest = Text(detail).font(.caption).foregroundStyle(Ink.text3)
        return Text("\(name)  \(rest)")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 12) {
                    tile
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            nameText.lineLimit(2)
                            if starred {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Ink.ok).accessibilityLabel("Favorite")
                            }
                        }
                        Text(caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if best {
                        Text("return")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Ink.text2)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Ink.raised, in: .rect(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.hairline))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityHint(best ? "Return logs it" : "")
            .accessibilityIdentifier(openIdentifier)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(best ? Ink.surface : Ink.raised, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .accessibilityLabel(addLabel)
            .accessibilityIdentifier(addIdentifier)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .frame(minHeight: 56)
        .background(best ? Color.cardBackground : .clear, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            if best { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentColor, lineWidth: 1.5) }
        }
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
                food.brand.flatMap { $0.lowercased() == food.name.lowercased() ? nil : $0 }, amount, "\(Format.whole(n.kcal)) kcal",
                "\(Format.grams(n.protein)) P",
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
            caption: [item.template.brand, item.template.amountLabel, "\(Format.whole(item.template.nutrients.kcal)) kcal"]
                .compactMap { $0 }.joined(separator: " · "),
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
            HStack(spacing: 12) {
                MealTile(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text("\(Format.time(moment.start)) · \(moment.entries.count) foods · \(Format.kcal(moment.nutrients.kcal))")
                        .font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Ink.raised, in: .circle)
                    .padding(4)
            }
            .padding(.leading, 8)
            .padding(.trailing, 2)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("Log \(name) again, \(moment.entries.count) foods, \(Format.kcal(moment.nutrients.kcal))")
        .accessibilityIdentifier("logger.sameAsUsual")
    }
}
