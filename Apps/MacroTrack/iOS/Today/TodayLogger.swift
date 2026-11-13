import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// Today on a phone is the logger: what's left at the top, the day's food as a thread grouped by
/// meal (the newest nearest the field), the usual foods for now one tap away, and one field at the
/// bottom that takes "chick 200" or "2 eggs, toast, coffee" and logs it on Return. Nothing opens to
/// confirm. The rest of the day (the weigh-in, the plan's asks, meal timing, supplements, drinks)
/// is folded under More today, after the thread (`MoreToday`).
struct TodayLogger: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var composer = TodayComposer()
    @FocusState private var typing: Bool
    @State private var editing: FoodEntry?
    /// The food opened in place on the thread, to change its amount.
    @State private var opened: UUID?
    /// The height of what's over the foot of the thread (tiles or matches, and the field).
    @State private var footHeight = 0.0
    /// Counts what's been logged or removed, for the thread's second look at its end.
    @State private var changes = 0
    /// Whether More today is open, kept for the scene.
    @SceneStorage("today.moreOpen") private var moreOpen = false

    static let threadEnd = "today.threadEnd"

    var body: some View {
        let entries = model.allEntries(on: model.today)
        let moments = Timeline.moments(entries)
        let fresh = freshIDs
        let estimates = model.estimates
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    thread(moments, fresh: fresh, estimates: estimates)
                    // Not while typing: there the thread runs straight into the matches.
                    if !typing { MoreToday(open: moreOpen) { toggleMore(proxy) } }
                }
                .insetGroupedList()
                .sectionSpacing(14)
                // The thread's end is a few points, not a row's 44: it's what sits between the
                // newest food and the matches while typing.
                .environment(\.defaultMinListRowHeight, 20)
                .inkGround()
                .sensoryFeedback(.impact(weight: .light), trigger: entries.count)
                .dismissesKeyboardOnScroll()
                // A tap anywhere on the day puts the keyboard away, alongside the row's own tap.
                .simultaneousGesture(TapGesture().onEnded { if typing { typing = false } })
                .safeAreaInset(edge: .top, spacing: 0) { header(entries: entries, fresh: fresh) }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
                .onAppear {
                    composer.attach(model)
                    composer.refreshTiles()
                    proxy.scrollTo(end, anchor: .bottom)
                }
                .onChange(of: entries.count) { _, _ in
                    composer.refreshTiles()
                    withAnimation(.snappy) { proxy.scrollTo(end, anchor: .bottom) }
                    changes &+= 1
                }
                // A row for words being worked out lands at the end of the thread, in sight.
                .onChange(of: estimates.count(where: \.isRow)) { _, _ in changes &+= 1 }
                // Return gives the keyboard back to the field a moment after its food arrives, and
                // the matches give way to the tiles: the list's insets move under the scroll above,
                // which then leaves the newest food behind the foot (or doesn't happen at all).
                // Once they've settled, the thread's end goes above the foot again.
                .task(id: changes) {
                    guard changes > 0 else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { proxy.scrollTo(end, anchor: .bottom) }
                }
                // While typing, the foot grows and shrinks with the matches: the thread keeps its
                // end in sight above them, once the list's inset has caught up with the foot (at
                // once, it scrolled for the foot before the matches rose, leaving the newest food
                // behind them).
                .task(id: typing ? footHeight : -1) {
                    guard typing else { return }
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { proxy.scrollTo(end, anchor: .bottom) }
                }
                // Typing puts More today away and brings the thread's end; done, it's back: either
                // way the end goes over the foot again once the keyboard has moved.
                .onChange(of: typing) { _, _ in changes &+= 1 }
                // A food opened in place comes up into sight, clear of the foot.
                .onChange(of: opened) { _, id in
                    guard let id else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .onChange(of: model.personalVersion) { _, _ in composer.attach(model) }
                .onChange(of: model.analysisVersion) { _, _ in composer.refreshTiles() }
                // A reminder can be tapped with Today not built yet: the request waits for it. The
                // supplements are under More today, which opens for them.
                .onChange(of: model.pendingSupplementsScroll, initial: true) { _, pending in
                    guard pending else { return }
                    model.pendingSupplementsScroll = false
                    moreOpen = true
                    Task {
                        await Task.yield()
                        withAnimation { proxy.scrollTo(SupplementsSection.scrollID, anchor: .top) }
                    }
                }
            }
            .hidesNavigationBar()
            .refreshable { await model.refreshHealth() }
        }
        // Again when the person's own foods change: taking them drops the answers kept so far, and
        // what's typed would show only their own foods until the next key.
        .task(id: TodayComposer.SearchKey(text: composer.text, foods: model.personalVersion)) { await composer.search() }
        // The fresh meal's Undo is in its header here, for a while longer than a toast's.
        // Not while a sheet or the logger is over it: its seconds start again when it's back.
        .task(id: ToastWait(toast: model.toast?.id, covered: covered)) {
            guard let toast = model.toast, !fresh.isEmpty, !covered else { return }
            await model.expire(toast, after: .seconds(6))
        }
        // "Goes with" lasts while a meal's open and "What fits tonight" starts at five: the clock
        // moves them, as well as the log.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                composer.refreshTiles()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { composer.refreshTiles() } }
        .sheet(item: $editing) { entry in EntryEditor(entry: entry) }
        .notesWork(editing != nil)
        // Typing closes a food opened in place, which saves it.
        .onChange(of: typing) { _, typing in if typing { opened = nil } }
        .animation(.snappy, value: typing)
    }

    /// The logger or a sheet is over Today, where a toast's seconds would run out unseen.
    var covered: Bool { model.logger != nil || model.toastCovered }

    struct ToastWait: Equatable {
        var toast: UUID?
        var covered: Bool
    }

    /// More today opened, it comes up into sight under its line; closed, the thread's end goes back
    /// over the foot.
    func toggleMore(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { moreOpen.toggle() }
        let open = moreOpen
        Task {
            await Task.yield()
            withAnimation(.snappy) {
                if open { proxy.scrollTo(MoreToday.id, anchor: .top) } else { proxy.scrollTo(end, anchor: .bottom) }
            }
        }
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
        // The width of the screen, typing or not: the one-line header is narrower than its ground.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
        // The thread fades in under the numbers rather than being cut at them, as at the foot.
        .background {
            VStack(spacing: 0) {
                Ink.ground
                LinearGradient(colors: [Ink.ground, Ink.ground.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
            .padding(.bottom, -22)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        // The header and the foot stay put while the day scrolls between them: at the largest
        // sizes they'd meet and leave the thread no room at all. Their words stop growing at the
        // largest standard size; the thread's go on.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(.rect)
        // Tapping the numbers while typing puts the keyboard away. Not a control of its own:
        // VoiceOver and keyboard users have Return and the composer's close button.
        .onTapGesture { if typing { typing = false } }
    }

    var eyebrow: String { Self.eyebrow(model) }

    /// "Wed, Nov 11 · Cut, week 1 of 4": the day, and where the plan is.
    static func eyebrow(_ model: AppModel) -> String {
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
    func thread(_ moments: [Moment], fresh: Set<UUID>, estimates: [ThreadEstimate]) -> some View {
        let rows = estimates.filter(\.isRow)
        let waiting = ThreadEstimates.unconfirmed(estimates)
        // Words being worked out join the meal they were typed with; after a while, they're a meal
        // of their own.
        let joins = moments.last.map { last in rows.first.map { $0.asked.timeIntervalSince(last.end) < Timeline.gap } ?? false } ?? false
        if moments.isEmpty, rows.isEmpty {
            Section {
                Text(
                    composer.tiles.isEmpty
                        ? "Nothing logged yet today. Type what you ate below." : "Nothing logged yet today. Type what you ate, or tap a usual food."
                )
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
                    if opened == entry.id {
                        InlineAmount(
                            entry: entry, close: { withAnimation(.snappy) { opened = nil } },
                            more: { current in
                                opened = nil
                                editing = current
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    } else {
                        row(entry, fresh: fresh, estimate: waiting.contains(entry.id))
                    }
                }
                // "Looks right" under an estimate's foods, where the thread's end keeps it in sight:
                // a long meal's header is under the numbers by then.
                ForEach(estimates.filter { $0.logs(any: moment.entries) }) { estimate in
                    EstimateConfirmRow(estimate: estimate)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                }
                if index == moments.count - 1 {
                    if joins { estimateRows(rows) }
                    // Only while typing: otherwise More today's line is the end.
                    if typing, joins || rows.isEmpty { threadEnd }
                }
            } header: {
                ThreadHeader(moment: moment, fresh: isFresh) {
                    if let toast = model.toast { model.undo(toast) }
                }
            }
        }
        if let first = rows.first, !joins {
            Section {
                estimateRows(rows)
                if typing { threadEnd }
            } header: {
                Text(Format.time(first.asked)).eyebrow().textCase(nil).padding(.horizontal, -6)
            }
        }
    }

    /// What's kept in sight over the foot: More today's line under the thread, or while typing (when
    /// it's put away) the thread's end.
    var end: String { typing ? Self.threadEnd : MoreToday.id }

    /// Where the thread ends, for scrolling to it.
    var threadEnd: some View {
        // Only there while typing: room under the newest food for the fade over the matches, so it
        // sits clear of them.
        Color.clear.frame(height: 32).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            .id(Self.threadEnd)
    }

    /// Words being worked out, or that couldn't be, where their foods will land.
    func estimateRows(_ rows: [ThreadEstimate]) -> some View {
        ForEach(rows) { estimate in
            EstimateRow(estimate: estimate)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                .swipeActions(edge: .trailing) {
                    Button("Dismiss", systemImage: "xmark", role: .destructive) { model.dismissEstimate(estimate.id) }
                }
        }
    }

    /// A food on the thread: a tap opens its amount in place (the full panel for one that isn't a
    /// catalog food), a swipe or a long press deletes it.
    func row(_ entry: FoodEntry, fresh: Set<UUID>, estimate: Bool) -> some View {
        Button {
            open(entry)
        } label: {
            ThreadRow(entry: entry, later: model.foodLog.isUpcoming(entry), estimate: estimate)
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

    func open(_ entry: FoodEntry) {
        // While typing, a tap on the day only puts the keyboard away (the day's own tap does that);
        // opening a food as well would be two things from one tap.
        guard !typing else { return }
        guard let id = entry.foodID, model.food(id: id) != nil else {
            editing = entry
            return
        }
        withAnimation(.snappy) { opened = entry.id }
    }

    // MARK: Bottom

    var bottom: some View {
        let active = composer.parts.last
        let showsMatches = !composer.text.trimmingCharacters(in: .whitespaces).isEmpty && !composer.matches.isEmpty
        let showsTiles = !composer.tiles.isEmpty && (composer.text.trimmingCharacters(in: .whitespaces).isEmpty || active?.kind == .typing)
        return VStack(alignment: .leading, spacing: 12) {
            if model.toast != nil, freshIDs.isEmpty, !covered { ToastSlot().padding(.horizontal, -16) }
            if showsMatches {
                ComposerMatches(composer: composer)
            } else if showsTiles, !composer.fits.isEmpty, composer.earlier.isEmpty {
                WhatFitsRows(composer: composer, targets: model.analysis?.targets, eaten: model.dayIntake(on: model.today).eaten)
            } else if showsTiles {
                // Two while words are being worked out, as at the accessibility sizes: the thread
                // needs the room for their row.
                UsualTiles(composer: composer, most: typeSize.isAccessibilitySize || model.estimates.contains(where: \.isRow) ? 2 : 4)
            }
            if !composer.earlier.isEmpty { ComposerChips(parts: composer.earlier, typed: composer.parts) }
            ComposerField(composer: composer, typing: $typing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // As the header's: the foot stops growing where the thread would lose its room.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .composerGround()
        .animation(.snappy(duration: 0.25), value: composer.matches)
        .animation(.snappy(duration: 0.25), value: composer.tiles)
        .onGeometryChange(for: Double.self) {
            $0.size.height
        } action: {
            footHeight = $0
        }
    }
}

// MARK: - Header

/// What's left: calories as the hero numeral over a tall ruler, then protein, carbs and fat in grams.
/// The phone's Today header, and the summary card of the wide one.
struct LeftHeader: View {
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
                    Ruler(value: eaten.kcal / kcal, height: 28)
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
                Text(Format.whole(abs(left))).numeral(70, weight: .heavy).foregroundStyle(Ink.text).contentTransition(.numericText())
                Text(left >= 0 ? "kcal left" : "kcal over").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
            } else {
                Text(Format.whole(eaten.kcal)).numeral(70, weight: .heavy).foregroundStyle(Ink.text).contentTransition(.numericText())
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
            Text(macro.label).font(.caption).foregroundStyle(Ink.text3)
            if let target, target > 0 {
                let left = target - eaten
                Measure(value: Format.whole(abs(left)), unit: left >= 0 ? "g left" : "g over", size: 20)
                Ruler.thin(eaten / target, color: macro.color)
            } else {
                Measure(value: Format.whole(eaten), unit: "g", size: 20)
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
struct ThreadHeader: View {
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
            Text(Format.kcal(moment.nutrients.kcal)).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
        }
        .textCase(nil)
        .padding(.horizontal, -6)
    }
}

/// A food on the thread: its marker, name and amount, and its calories with the macro it's most of.
struct ThreadRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: FoodEntry
    var later = false
    /// Estimated from words typed, and not yet confirmed: said in words rather than with a ≈.
    var estimate = false

    var body: some View {
        let lead = Self.lead(entry.nutrients)
        HStack(spacing: 12) {
            if later { LaterMark() }
            FoodTile(name: entry.name, size: 40, fill: Ink.surface)
            VStack(alignment: .leading, spacing: 2) {
                // How someone would say it ("Chicken breast, roasted"); the full name is on its amount.
                // A line each, until the accessibility sizes leave a line a word or two.
                Text(FoodLabel.short(entry.name)).font(.body.weight(.medium)).foregroundStyle(Ink.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(Self.caption(entry, estimate: estimate))
                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
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

    /// "Chobani · 170 g", or for an estimate waiting to be confirmed "1 cup · 158 g · estimate".
    static func caption(_ entry: FoodEntry, estimate: Bool) -> String {
        let amount = estimate && entry.amountLabel.hasPrefix("≈ ") ? String(entry.amountLabel.dropFirst(2)) : entry.amountLabel
        return ([entry.brand, amount].compactMap { $0 }.filter { !$0.isEmpty } + (estimate ? ["estimate"] : [])).joined(separator: " · ")
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
    /// Four, or a row of two at the accessibility sizes, where the thread needs the room.
    let most: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(composer.tilesTitle).eyebrow()
                Spacer()
                Text("One tap logs it").font(.caption).foregroundStyle(Ink.text3)
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(composer.tiles.prefix(most).enumerated()), id: \.element.id) { index, item in
                    Button {
                        composer.log(item)
                    } label: {
                        HStack(spacing: 10) {
                            FoodTile(name: item.template.name, fill: Ink.raised)
                            VStack(alignment: .leading, spacing: 1) {
                                // "Chicken breast" is a few points wider than half a phone's tile.
                                Text(FoodLabel.title(item.template.name)).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                Text("\(item.template.amountLabel) · \(Format.whole(item.template.nutrients.kcal)) kcal")
                                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.usual.\(index)")
                    .accessibilityLabel(
                        "Log \(FoodLabel.short(item.template.name)), \(item.template.amountLabel), \(Format.kcal(item.template.nutrients.kcal))")
                }
            }
        }
    }
}

/// "What fits tonight": one or two of the usual foods that finish the day, each with what it leaves,
/// and the calories and protein after it on thin rulers.
private struct WhatFitsRows: View {
    let composer: TodayComposer
    let targets: DailyTargets?
    let eaten: Nutrients

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("What fits tonight").eyebrow()
                Spacer()
                Text("One tap logs it").font(.caption).foregroundStyle(Ink.text3)
            }
            .padding(.horizontal, 4)
            ForEach(Array(composer.fits.enumerated()), id: \.element.id) { index, option in
                Button {
                    composer.log(option)
                } label: {
                    row(option)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.fits.\(index)")
            }
        }
    }

    func row(_ option: WhatFits.Option) -> some View {
        HStack(spacing: 12) {
            FoodTile(name: option.items.first?.name ?? "", fill: Ink.raised)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.items.map { FoodLabel.title($0.name) }.joined(separator: " + "))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(
                    "\(option.items.map(\.amountLabel).joined(separator: " + ")) · \(Format.kcal(option.nutrients.kcal)) · \(Format.whole(option.nutrients.protein)) P"
                )
                .font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if let kcal = targets?.kcal, kcal > 0 {
                    Ruler.thin((eaten.kcal + option.nutrients.kcal) / kcal).frame(width: 64)
                }
                if let protein = targets?.protein, protein > 0 {
                    Ruler.thin((eaten.protein + option.nutrients.protein) / protein, color: Ink.protein).frame(width: 64)
                }
                if option.onTarget {
                    Label("On target", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(Ink.good)
                } else {
                    Text("leaves \(Format.whole(option.leaves))").font(.caption2).foregroundStyle(Ink.text2)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
        .background(option.onTarget ? Color.accentColor.opacity(0.12) : Color.cardBackground, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            if option.onTarget { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Log \(option.items.map { FoodLabel.short($0.name) }.joined(separator: " and ")), \(Format.kcal(option.nutrients.kcal)), \(option.onTarget ? "on target" : "leaves \(Format.whole(option.leaves)) kcal")"
        )
    }
}
