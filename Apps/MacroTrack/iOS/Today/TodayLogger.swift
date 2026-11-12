import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Today on a phone is the logger: what's left at the top, the day's food as a thread grouped by
/// meal (the newest nearest the field), the usual foods for now one tap away, and one field at the
/// bottom that takes "chick 200" or "2 eggs, toast, coffee" and logs it on Return. Nothing opens to
/// confirm. The rest of the day (the weigh-in, the plan's asks, meal timing, supplements, drinks)
/// is below the thread.
struct TodayLogger: View {
    @Environment(AppModel.self) private var model
    @State private var composer = TodayComposer()
    @FocusState private var typing: Bool
    @State private var editing: FoodEntry?

    static let threadEnd = "today.threadEnd"

    var body: some View {
        let entries = model.allEntries(on: model.today)
        let moments = Timeline.moments(entries)
        let fresh = freshIDs
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    thread(moments, fresh: fresh)
                    Group {
                        if let analysis = model.analysis, !analysis.targets.note.isEmpty {
                            Section {
                                ModeLine(targets: analysis.targets, assessment: analysis.assessment)
                            }
                        }
                        ActionsSection()
                        WeightSection(day: model.today)
                        PlannedMealsSection(day: model.today)
                        if model.usualNow != nil || !model.usualMeals.isEmpty { LogAgainSection(foods: false) }
                        DayStateSection(day: model.today)
                        TodayMore(day: model.today)
                    }
                    .listRowBackground(Color.cardBackground)
                }
                .insetGroupedList()
                .sectionSpacing(14)
                .inkGround()
                .sensoryFeedback(.impact(weight: .light), trigger: entries.count)
                .dismissesKeyboardOnScroll()
                .safeAreaInset(edge: .top, spacing: 0) { header(entries: entries, fresh: fresh) }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
                .onAppear {
                    composer.attach(model)
                    composer.refreshTiles()
                    proxy.scrollTo(Self.threadEnd, anchor: .bottom)
                }
                .onChange(of: entries.count) { _, _ in
                    composer.refreshTiles()
                    withAnimation(.snappy) { proxy.scrollTo(Self.threadEnd, anchor: .bottom) }
                }
                .onChange(of: model.personalVersion) { _, _ in composer.attach(model) }
                .onChange(of: model.analysisVersion) { _, _ in composer.refreshTiles() }
                // A reminder can be tapped with Today not built yet: the request waits for it.
                .onChange(of: model.pendingSupplementsScroll, initial: true) { _, pending in
                    guard pending else { return }
                    model.pendingSupplementsScroll = false
                    withAnimation { proxy.scrollTo(SupplementsSection.scrollID, anchor: .top) }
                }
            }
            .hidesNavigationBar()
            .refreshable { await model.refreshHealth() }
        }
        .task(id: composer.text) { await composer.search() }
        // The fresh meal's Undo is in its header here, for a while longer than a toast's.
        .task(id: model.toast?.id) {
            guard let toast = model.toast, !fresh.isEmpty else { return }
            await model.expire(toast, after: .seconds(6))
        }
        .sheet(item: $editing) { entry in EntryEditor(entry: entry) }
        .notesWork(editing != nil)
        .animation(.snappy, value: typing)
    }

    /// What was just logged, while its Undo lasts: only food on today's thread.
    var freshIDs: Set<UUID> {
        guard let toast = model.toast, !toast.failed, !toast.undo.isEmpty else { return [] }
        let ids = Set(toast.undo)
        return model.allEntries(on: model.today).contains { ids.contains($0.id) } ? ids : []
    }

    // MARK: Header

    @ViewBuilder
    func header(entries: [FoodEntry], fresh: Set<UUID>) -> some View {
        let targets = model.analysis?.targets
        let eaten = model.dayIntake(on: model.today).eaten
        VStack(alignment: .leading, spacing: 10) {
            if typing {
                TypingHeader(targets: targets, eaten: eaten, adding: composer.adding)
            } else {
                HStack {
                    Text(eyebrow).eyebrow()
                    Spacer()
                    SettingsButton(identifier: "today.settings")
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.text2)
                        .frame(width: 36, height: 36)
                        .background(Ink.raised, in: .circle)
                }
                LeftHeader(
                    targets: targets, eaten: eaten, showAllMacros: model.settings.showAllMacros,
                    justLogged: fresh.isEmpty ? nil : entries.filter { fresh.contains($0.id) }.map(\.nutrients.kcal).reduce(0, +))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Ink.ground)
    }

    /// "Wed, Nov 11 · Cut, week 1 of 4": the day, and where the plan is.
    var eyebrow: String {
        let day = Format.day(model.today)
        guard let analysis = model.analysis else { return day }
        switch analysis.targets.mode {
        case .assessment:
            return analysis.assessment.map { "\(day) · Assessment, day \($0.day) of \($0.totalDays)" } ?? "\(day) · Assessment"
        case .phase:
            guard let phase = analysis.phase else { return day }
            return "\(day) · \(phase.kind.label), week \(phase.week(on: model.today)) of \(phase.weeks)"
        case .dietBreak: return "\(day) · Diet break"
        case .crunch: return "\(day) · Crunch"
        case .illness: return "\(day) · Ill"
        case .vacation: return "\(day) · Vacation"
        }
    }

    // MARK: Thread

    @ViewBuilder
    func thread(_ moments: [Moment], fresh: Set<UUID>) -> some View {
        if moments.isEmpty {
            Section {
                Text("Nothing logged yet today. Type what you ate, or tap a usual food.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.text2)
                    .listRowBackground(Color.clear)
                    .id(Self.threadEnd)
            }
        }
        ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
            let isFresh = moment.entries.contains { fresh.contains($0.id) }
            Section {
                ForEach(moment.entries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        ThreadRow(entry: entry, later: model.foodLog.isUpcoming(entry))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(fresh.contains(entry.id) ? Color.accentColor.opacity(0.14) : Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                    }
                    .contextMenu {
                        Button("Change Amount", systemImage: "slider.horizontal.3") { editing = entry }
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
                    }
                    .accessibilityIdentifier("today.entry")
                    .accessibilityHint("Changes the amount")
                }
                if index == moments.count - 1 {
                    Color.clear.frame(height: 1).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).id(Self.threadEnd)
                }
            } header: {
                ThreadHeader(moment: moment, fresh: isFresh) {
                    if let toast = model.toast { model.undo(toast) }
                }
            }
        }
    }

    // MARK: Bottom

    var bottom: some View {
        let active = composer.parts.last
        let showsMatches = !composer.text.trimmingCharacters(in: .whitespaces).isEmpty && !composer.matches.isEmpty
        let showsTiles = !composer.tiles.isEmpty && (composer.text.trimmingCharacters(in: .whitespaces).isEmpty || active?.kind == .typing)
        return VStack(alignment: .leading, spacing: 8) {
            if model.toast != nil, freshIDs.isEmpty { ToastSlot().padding(.horizontal, -16) }
            if showsMatches {
                ComposerMatches(composer: composer)
            } else if showsTiles {
                UsualTiles(composer: composer)
            }
            if !composer.earlier.isEmpty { ComposerChips(parts: composer.earlier, typed: composer.parts) }
            ComposerField(composer: composer, typing: $typing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // Solid down to the screen's foot: the thread scrolls under the composer and the tab bar,
        // not out below them.
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground], startPoint: .top, endPoint: .bottom).frame(height: 14)
                Ink.ground
            }
            .padding(.top, -14)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy(duration: 0.25), value: composer.matches)
        .animation(.snappy(duration: 0.25), value: composer.tiles)
    }
}

// MARK: - Header

/// What's left: calories as the hero numeral over a tall ruler, then protein, carbs and fat in grams.
private struct LeftHeader: View {
    let targets: DailyTargets?
    let eaten: Nutrients
    let showAllMacros: Bool
    /// What the meal just logged added, said beside the numeral while its Undo lasts.
    let justLogged: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            calories
            if let kcal = targets?.kcal, kcal > 0 {
                VStack(spacing: 5) {
                    Ruler(value: eaten.kcal / kcal, height: 18)
                    HStack {
                        Text("\(Format.whole(eaten.kcal)) eaten").eyebrow()
                        Spacer()
                        Text("\(Format.whole(kcal)) target").eyebrow()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.eatenOfTarget")
                }
            }
            HStack(alignment: .top, spacing: 14) {
                MacroLeft(macro: .protein, eaten: eaten.protein, target: targets?.protein)
                if showAllMacros {
                    MacroLeft(macro: .carbs, eaten: eaten.carbs, target: targets?.carbs)
                    MacroLeft(macro: .fat, eaten: eaten.fat, target: targets?.fat)
                } else {
                    Spacer()
                    Spacer()
                }
            }
        }
    }

    var calories: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let kcal = targets?.kcal {
                let left = kcal - eaten.kcal
                Text(Format.whole(abs(left))).numeral(64).foregroundStyle(Ink.text).contentTransition(.numericText())
                Text(left >= 0 ? "kcal left" : "kcal over").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
            } else {
                Text(Format.whole(eaten.kcal)).numeral(64).foregroundStyle(Ink.text).contentTransition(.numericText())
                Text("kcal eaten").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
            }
            Spacer(minLength: 0)
            if let justLogged, justLogged >= 1 {
                Text("−\(Format.whole(justLogged))").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Color.accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.snappy, value: eaten.kcal)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.calories")
    }
}

/// One macro's grams left over a thin ruler in its colour.
private struct MacroLeft: View {
    let macro: Macro
    let eaten: Double
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(macro.label).font(.caption).foregroundStyle(Ink.text2)
            if let target, target > 0 {
                let left = target - eaten
                Measure(value: Format.whole(abs(left)), unit: left >= 0 ? "g left" : "g over", size: 22)
                Ruler.thin(eaten / target, color: macro.color)
            } else {
                Measure(value: Format.whole(eaten), unit: "g", size: 22)
                Ruler.thin(0, color: macro.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.label)
        .accessibilityValue(target.map { "\(Format.grams(max(0, $0 - eaten))) left of \(Format.grams($0))" } ?? "\(Format.grams(eaten)) eaten")
    }
}

/// While typing: the header in a line, what's left now and after what's typed.
private struct TypingHeader: View {
    let targets: DailyTargets?
    let eaten: Nutrients
    let adding: Nutrients?

    var body: some View {
        let after = eaten + (adding ?? .zero)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let kcal = targets?.kcal {
                    Text(Format.whole(kcal - eaten.kcal)).numeral(30)
                    if adding != nil {
                        Text("→ \(Format.whole(kcal - after.kcal))").numeral(30).foregroundStyle(Color.accentColor)
                    }
                    Text("kcal left").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                } else {
                    Text(Format.whole(eaten.kcal)).numeral(30)
                    if adding != nil { Text("→ \(Format.whole(after.kcal))").numeral(30).foregroundStyle(Color.accentColor) }
                    Text("kcal eaten").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                }
            }
            .contentTransition(.numericText())
            if let kcal = targets?.kcal, kcal > 0 { Ruler.thin(after.kcal / kcal) }
            Text(line(after)).font(.caption).foregroundStyle(Ink.text2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .animation(.snappy, value: adding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.typingHeader")
    }

    /// "Then 82 g protein · 168 g carbs · 54 g fat left".
    func line(_ after: Nutrients) -> String {
        let parts = [("protein", after.protein, targets?.protein), ("carbs", after.carbs, targets?.carbs), ("fat", after.fat, targets?.fat)]
            .compactMap { name, value, target in target.map { "\(Format.whole(max(0, $0 - value))) g \(name)" } }
        guard !parts.isEmpty else { return "" }
        return (adding == nil ? "" : "Then ") + parts.joined(separator: " · ") + " left"
    }
}

// MARK: - Thread

/// A meal's time, its calories, and Undo while it's fresh.
private struct ThreadHeader: View {
    let moment: Moment
    let fresh: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.time(moment.start)).eyebrow()
            Spacer()
            if fresh {
                Button("Undo", action: undo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                    .accessibilityIdentifier("today.undo")
            }
            Text(Format.kcal(moment.nutrients.kcal)).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2)
        }
        .textCase(nil)
        .padding(.horizontal, -6)
    }
}

/// A food on the thread: its marker, name and amount, and its calories with the macro it's most of.
struct ThreadRow: View {
    let entry: FoodEntry
    var later = false

    var body: some View {
        let lead = Self.lead(entry.nutrients)
        HStack(spacing: 12) {
            if later { LaterMark() }
            FoodTile(name: entry.name, fill: Ink.raised)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium)).foregroundStyle(Ink.text).lineLimit(1)
                Text([entry.brand, entry.amountLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Ink.text)
                if let lead {
                    Text("\(Format.whole(lead.grams)) \(lead.letter)").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(lead.color)
                }
            }
        }
        .opacity(later ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The macro giving most of a food's calories: "54 P" for chicken, "60 C" for rice.
    static func lead(_ n: Nutrients) -> (grams: Double, letter: String, color: Color)? {
        let options: [(Double, Double, String, Color)] = [
            (n.protein * 4, n.protein, "P", Ink.protein), (n.carbs * 4, n.carbs, "C", Ink.carbs), (n.fat * 9, n.fat, "F", Ink.fat),
        ]
        guard let best = options.max(by: { $0.0 < $1.0 }), best.0 > 0 else { return nil }
        return (best.1, best.2, best.3)
    }
}

// MARK: - Above the field

/// The usual foods for now, or what goes with the meal being eaten, one tap each.
private struct UsualTiles: View {
    let composer: TodayComposer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(composer.tilesTitle).eyebrow()
                Spacer()
                Text("One tap logs it").font(.caption).foregroundStyle(Ink.text2)
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(composer.tiles.enumerated()), id: \.element.id) { index, item in
                    Button {
                        composer.log(item)
                    } label: {
                        HStack(spacing: 10) {
                            FoodTile(name: item.template.name, fill: Ink.raised)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.template.name).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                Text("\(item.template.amountLabel) · \(Format.whole(item.template.nutrients.kcal)) kcal")
                                    .font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.usual.\(index)")
                    .accessibilityLabel(
                        "Log \(item.template.name), \(item.template.amountLabel), \(Format.kcal(item.template.nutrients.kcal))")
                }
            }
        }
    }
}

/// What the food being typed could be, rising above the field: the best one nearest it, marked
/// with the key that logs it.
private struct ComposerMatches: View {
    let composer: TodayComposer

    var body: some View {
        let count = composer.earlier.compactMap(\.entry).count + 1
        VStack(spacing: 6) {
            ForEach(Array(composer.matches.enumerated().reversed()), id: \.element.id) { index, match in
                Button {
                    composer.log(match)
                } label: {
                    row(match, best: index == 0, count: count)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.match.\(index)")
            }
        }
    }

    func row(_ match: TodayComposer.Candidate, best: Bool, count: Int) -> some View {
        HStack(spacing: 12) {
            switch match.kind {
            case .food: FoodTile(name: match.entry.name, fill: Ink.raised)
            case .quickAdd, .unmatched:
                Text("≈").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2).frame(width: TileSize.row, height: TileSize.row)
                    .background(Ink.raised, in: .rect(cornerRadius: TileSize.row * 0.3))
            }
            VStack(alignment: .leading, spacing: 2) {
                // Two lines: catalog names differ late ("Chicken, broilers or fryers, breast, meat only…").
                Text(title(match)).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(2)
                Text(detail(match)).font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Spacer(minLength: 6)
            if best {
                Text(count > 1 ? "return · logs \(count)" : "return")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.text2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Ink.raised, in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.hairline))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(best ? Color.accentColor.opacity(0.12) : Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            if best { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(best ? "Return logs it" : "")
    }

    func title(_ match: TodayComposer.Candidate) -> String {
        switch match.kind {
        case .food: match.entry.name
        case .quickAdd: "Quick add \(Format.kcal(match.entry.nutrients.kcal))"
        case .unmatched(let words): "Describe “\(words)”"
        }
    }

    func detail(_ match: TodayComposer.Candidate) -> String {
        switch match.kind {
        case .food:
            "\(match.entry.amountLabel) · \(Format.kcal(match.entry.nutrients.kcal)) · \(Format.whole(match.entry.nutrients.protein)) P"
        case .quickAdd: "Just the number, no food"
        case .unmatched: "Not in your foods or the catalog. Find it in the logger."
        }
    }
}

/// The foods typed before the one being typed, as they'll be logged.
private struct ComposerChips: View {
    let parts: [TodayComposer.Resolved]
    let typed: [AddFoodPart]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(parts) { part in
                    Text(label(part))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.cardBackground, in: .capsule)
                        .overlay(Capsule().stroke(Ink.hairline))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Also logging")
    }

    func label(_ part: TodayComposer.Resolved) -> String {
        if let entry = part.entry {
            if entry.source == .quickAdd { return "≈ \(Format.kcal(entry.nutrients.kcal))" }
            return "\(FoodMarker.of(entry.name)) \(TodayComposer.short(entry.name)) · \(entry.amountLabel)"
        }
        if let words = part.unmatched { return "≈ \(words)" }
        return typed.indices.contains(part.id) ? "\(typed[part.id].text)…" : "…"
    }
}

/// The one field: type or dictate what was eaten; the camera for a barcode, a label or a plate; the
/// microphone to say it.
private struct ComposerField: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: TodayComposer
    var typing: FocusState<Bool>.Binding

    var body: some View {
        let empty = composer.text.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 4) {
            TextField("Add food, or say what you ate", text: $composer.text)
                .font(.body)
                .foregroundStyle(Ink.text)
                .focused(typing)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .submitLabel(.return)
                .onSubmit {
                    Task { await composer.submit() }
                    // Return logs and the keyboard stays for the next food.
                    typing.wrappedValue = true
                }
                .accessibilityIdentifier("today.composer")
                .padding(.leading, 18)
                .frame(maxHeight: .infinity)
            if empty {
                Button {
                    model.openLogger(.scan)
                } label: {
                    Image(systemName: "camera").font(.title3).foregroundStyle(Ink.text2).frame(width: 44, height: 44).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Scan a Barcode or Label", systemImage: "barcode.viewfinder") { model.openLogger(.scan) }
                    if model.ai.canSeePhotos {
                        Button("Photo of Your Plate", systemImage: "camera") { model.openLogger(.camera) }
                        Button("Choose a Photo", systemImage: "photo") { model.openLogger(.photoLibrary) }
                    }
                }
                .accessibilityLabel("Camera: barcode, label or plate")
                .accessibilityIdentifier("today.camera")
                Button {
                    // Said to the model where it can read a sentence; else the keyboard's own dictation.
                    if model.ai.canDescribe { model.openLogger(.describe) } else { typing.wrappedValue = true }
                } label: {
                    Image(systemName: "mic.fill").font(.body.weight(.semibold)).foregroundStyle(Ink.ground)
                        .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Say what you ate")
                .accessibilityIdentifier("today.describe")
            } else {
                Button {
                    Task { await composer.submit() }
                } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(Ink.ground)
                        .frame(width: 40, height: 40).background(Color.accentColor, in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(composer.submitting)
                .accessibilityLabel("Log it")
                .accessibilityIdentifier("today.send")
            }
        }
        .padding(.trailing, 7)
        .frame(height: 56)
        .background(Color.cardBackground, in: .capsule)
        .overlay(Capsule().stroke(typing.wrappedValue ? Color.accentColor : Ink.hairline, lineWidth: typing.wrappedValue ? 1.5 : 1))
    }
}
