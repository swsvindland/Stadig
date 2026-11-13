#if os(macOS)
import AppKit
import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// The Mac's menu bar logger: a compact Today in the panel under "1,601". What's left, the latest
/// foods, the usual foods for now on ⌘1–⌘4, and Today's own composer, so "chick 200" and Return logs
/// it and commas log several, with nothing to confirm and Undo on the fresh meal. It runs on the
/// app's model, so it works with the main window closed. Esc closes it.
struct MenuBarToday: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearsActive) private var appearsActive
    @State private var composer = TodayComposer()
    @FocusState private var typing: Bool
    /// The match ↑ and ↓ have picked, counted from the best (0), which sits nearest the field.
    @State private var picked = 0

    static let width = 448.0
    /// Whether the menu bar has it: on unless turned off in Settings, or dragged out with ⌘.
    static let shownKey = "showsMenuBarExtra"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.onboarded {
                today
            } else {
                notSetUp
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: Self.width)
        .background(Ink.ground)
        .onExitCommand(perform: close)
    }

    private var today: some View {
        let fresh = freshIDs
        let typed = !composer.text.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            MenuBarHeader(
                eyebrow: TodayLogger.eyebrow(model), targets: model.analysis?.targets, eaten: model.dayIntake(on: model.today).eaten,
                adding: composer.adding, showAllMacros: model.settings.showAllMacros, open: showApp)
            Ink.hairline.frame(height: 1).padding(.top, 14).padding(.bottom, 6)
            MenuBarThread(fresh: fresh, estimates: model.estimates)
            if !composer.tiles.isEmpty { MenuBarTiles(composer: composer).padding(.top, 12) }
            if typed, !composer.matches.isEmpty { MenuBarMatches(composer: composer, picked: picked).padding(.top, 10) }
            field.padding(.top, 8)
            keys.padding(.top, 10)
        }
        .animation(.snappy(duration: 0.2), value: composer.matches)
        .task(id: TodayComposer.SearchKey(text: composer.text, foods: model.personalVersion)) { await composer.search() }
        // The fresh meal's Undo, for as long as Today gives it, while the panel is up.
        .task(id: model.toast?.id) {
            guard let toast = model.toast, !fresh.isEmpty else { return }
            await model.expire(toast, after: .seconds(6))
        }
        .onAppear(perform: opened)
        // The panel stays built between clicks on the menu bar: each opening reads the day again.
        .onChange(of: appearsActive) { _, active in if active { opened() } }
        .onChange(of: composer.text) { _, _ in picked = 0 }
        .onChange(of: model.personalVersion) { _, _ in composer.attach(model) }
        .onChange(of: model.analysisVersion) { _, _ in composer.refreshTiles() }
        // The logger lives in the main window: words for it (no Apple Intelligence, or an estimate
        // taken there) open that. Only from the panel: the window's own loggers are its business.
        .onChange(of: model.loggerRequest) { _, _ in if appearsActive { showApp() } }
    }

    private var notSetUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stadig Macro").font(.headline).foregroundStyle(Ink.text)
            Text("Set it up in its window, and what's left today shows here.").font(.subheadline).foregroundStyle(Ink.text2)
            Button("Open Stadig Macro", action: showApp).keyboardShortcut(.defaultAction)
        }
    }

    // MARK: The field

    private var field: some View {
        TextField("Add food, or say what you ate", text: $composer.text)
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundStyle(Ink.text)
            .focused($typing)
            .autocorrectionDisabled()
            .onSubmit(submit)
            // The matches rise from the field, best first: ↑ goes up them, ↓ comes back.
            .onKeyPress(.upArrow) { pick(by: 1) }
            .onKeyPress(.downArrow) { pick(by: -1) }
            .accessibilityIdentifier("menuBar.composer")
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.cardBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(typing ? Color.accentColor : Ink.hairline, lineWidth: typing ? 1.5 : 1)
            }
    }

    private var keys: some View {
        HStack(spacing: 6) {
            KeyCap("↑")
            KeyCap("↓")
            Text("pick").padding(.trailing, 8)
            KeyCap(",")
            Text("next food").padding(.trailing, 8)
            KeyCap("esc")
            Text("close")
        }
        .font(.caption)
        .foregroundStyle(Ink.text2)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Up and down arrows pick a match, a comma starts the next food, Escape closes")
    }

    // MARK: Actions

    /// What was just logged, while its Undo lasts: only food on today's thread, as on Today.
    private var freshIDs: Set<UUID> {
        guard let toast = model.toast, !toast.failed, !toast.undo.isEmpty else { return [] }
        let ids = Set(toast.undo)
        return model.allEntries(on: model.today).contains { ids.contains($0.id) } ? ids : []
    }

    private func opened() {
        model.refreshDay()
        composer.attach(model)
        composer.refreshTiles()
        typing = true
    }

    /// Return: the picked match (the best unless ↑ moved off it), with the foods typed before it, or
    /// every part at once as Today does. The field clears for the next food.
    private func submit() {
        guard !composer.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if picked > 0, composer.matches.indices.contains(picked) {
            composer.log(composer.matches[picked])
        } else {
            Task { await composer.submit() }
        }
        picked = 0
        typing = true
    }

    private func pick(by step: Int) -> KeyPress.Result {
        guard !composer.matches.isEmpty else { return .ignored }
        picked = min(max(0, picked + step), composer.matches.count - 1)
        return .handled
    }

    private func showApp() {
        openWindow(id: MacroTrackApp.mainWindow)
        NSApp.activate()
        close()
    }

    private func close() { dismiss() }
}

// MARK: - Header

/// What's left, as on Today but a size down: calories as the numeral over its ruler, with what's
/// typed shown as "→ 1,271" and a lighter span on the ruler, then protein, carbs and fat.
private struct MenuBarHeader: View {
    let eyebrow: String
    let targets: DailyTargets?
    let eaten: Nutrients
    let adding: Nutrients?
    let showAllMacros: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(eyebrow).eyebrow().lineLimit(1)
                Spacer(minLength: 8)
                Button(action: open) {
                    HStack(spacing: 6) {
                        Text("Open Stadig Macro")
                        KeyCap("⌘O")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.text2)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("menuBar.open")
            }
            calories
            if let kcal = targets?.kcal, kcal > 0 { ruler(kcal) }
            HStack(alignment: .top, spacing: 16) {
                MacroLine(macro: .protein, eaten: eaten.protein, adding: adding?.protein, target: targets?.protein)
                if showAllMacros {
                    MacroLine(macro: .carbs, eaten: eaten.carbs, adding: adding?.carbs, target: targets?.carbs)
                    MacroLine(macro: .fat, eaten: eaten.fat, adding: adding?.fat, target: targets?.fat)
                } else {
                    Spacer()
                    Spacer()
                }
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 4)
    }

    private var calories: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let kcal = targets?.kcal {
                let left = kcal - eaten.kcal
                Text(Format.whole(abs(left))).numeral(46)
                if let adding { Text("→ \(Format.whole(left - adding.kcal))").numeral(46).foregroundStyle(Color.accentColor) }
                Text(left >= 0 ? "kcal left" : "kcal over").font(.headline).foregroundStyle(Ink.text2)
            } else {
                Text(Format.whole(eaten.kcal)).numeral(46)
                if let adding { Text("→ \(Format.whole(eaten.kcal + adding.kcal))").numeral(46).foregroundStyle(Color.accentColor) }
                Text("kcal eaten").font(.headline).foregroundStyle(Ink.text2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
        .animation(.snappy, value: eaten.kcal)
        .animation(.snappy, value: adding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menuBar.calories")
    }

    private func ruler(_ kcal: Double) -> some View {
        VStack(spacing: 5) {
            Ruler(value: eaten.kcal / kcal, height: 14)
                .overlay(alignment: .leading) {
                    // What Return would add, lighter, after what's eaten.
                    if let adding, adding.kcal > 0 {
                        GeometryReader { geometry in
                            let start = min(1, max(0, eaten.kcal / kcal))
                            let end = min(1, max(0, (eaten.kcal + adding.kcal) / kcal))
                            Rectangle().fill(Color.accentColor.opacity(0.42))
                                .frame(width: geometry.size.width * (end - start))
                                .offset(x: geometry.size.width * start)
                        }
                        .allowsHitTesting(false)
                    }
                }
            HStack {
                let added = adding.map { Text(" + \(Format.whole($0.kcal))").foregroundStyle(Color.accentColor) } ?? Text("")
                Text("\(Text("\(Format.whole(eaten.kcal)) eaten"))\(added)").eyebrow()
                Spacer()
                Text("\(Format.whole(kcal)) target").eyebrow()
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// One macro's grams left, "102 → 41 g left" while typing, over a thin ruler in its colour.
private struct MacroLine: View {
    let macro: Macro
    let eaten: Double
    let adding: Double?
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(macro.label).font(.caption).foregroundStyle(Ink.text2)
            if let target, target > 0 {
                let left = max(0, target - eaten)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let adding, adding >= 0.5 {
                        Text("\(Format.whole(left)) →").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text3)
                        Text(Format.whole(max(0, left - adding))).font(.subheadline.bold().monospacedDigit())
                    } else {
                        Text(Format.whole(left)).font(.subheadline.bold().monospacedDigit())
                    }
                    Text("g left").font(.caption).foregroundStyle(Ink.text2)
                }
                .lineLimit(1)
                Ruler.thin(eaten / target, color: macro.color).padding(.top, 2)
            } else {
                Measure(value: Format.whole(eaten), unit: "g", size: 15)
                Ruler.thin(0, color: macro.color).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.label)
        .accessibilityValue(target.map { "\(Format.grams(max(0, $0 - eaten))) left of \(Format.grams($0))" } ?? "\(Format.grams(eaten)) eaten")
    }
}

// MARK: - The latest foods

/// The end of today's thread: the newest few foods under their meal's time, with Undo on the fresh
/// one and "Looks right" on an estimate, then any words still being worked out.
private struct MenuBarThread: View {
    @Environment(AppModel.self) private var model
    let fresh: Set<UUID>
    let estimates: [ThreadEstimate]

    /// Foods shown at most: the panel is a glance, and the window has the day.
    static let most = 4

    struct Shown: Identifiable {
        var moment: Moment
        var entries: [FoodEntry]
        var id: Moment.ID { moment.id }
    }

    /// The last `most` foods of the day, newest last, under the meals they're in.
    static func latest(_ moments: [Moment], most: Int) -> [Shown] {
        var left = most
        var shown: [Shown] = []
        for moment in moments.reversed() where left > 0 {
            let entries = Array(moment.entries.suffix(left))
            left -= entries.count
            shown.insert(Shown(moment: moment, entries: entries), at: 0)
        }
        return shown
    }

    var body: some View {
        let shown = Self.latest(Timeline.moments(model.allEntries(on: model.today)), most: Self.most)
        let rows = estimates.filter(\.isRow)
        let waiting = ThreadEstimates.unconfirmed(estimates)
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty, rows.isEmpty {
                Text("Nothing logged yet today.").font(.subheadline).foregroundStyle(Ink.text2).padding(.horizontal, 4).padding(.vertical, 8)
            }
            ForEach(shown) { meal in
                ThreadHeader(moment: meal.moment, fresh: meal.moment.entries.contains { fresh.contains($0.id) }) {
                    if let toast = model.toast { model.undo(toast) }
                }
                // The header's own inset is the list's; here the rows set the edge.
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                ForEach(meal.entries) { entry in
                    FoodLine(entry: entry, fresh: fresh.contains(entry.id), estimate: waiting.contains(entry.id))
                }
                ForEach(estimates.filter { $0.logs(any: meal.entries) }) { estimate in
                    EstimateConfirmRow(estimate: estimate).padding(.leading, 42).padding(.trailing, 4)
                }
            }
            ForEach(rows) { estimate in
                EstimateRow(estimate: estimate, tile: 28).padding(.horizontal, 4).padding(.vertical, 3)
            }
        }
    }
}

/// A food on the panel's thread: marker, name and amount on one line, calories and the macro it's
/// most of.
private struct FoodLine: View {
    @Environment(AppModel.self) private var model
    let entry: FoodEntry
    let fresh: Bool
    let estimate: Bool

    var body: some View {
        let lead = ThreadRow.lead(entry.nutrients)
        let name = Text(FoodLabel.short(entry.name)).fontWeight(.medium).foregroundStyle(Ink.text)
        let amount = Text("· \(ThreadRow.caption(entry, estimate: estimate))").foregroundStyle(Ink.text3)
        HStack(spacing: 10) {
            FoodTile(name: entry.name, size: 28, fill: Ink.raised)
            Text("\(name) \(amount)").lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(entry.isEstimate ? "≈" : "")\(Format.whole(entry.nutrients.kcal))").fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(Ink.text)
            Text(lead.map { "\(Format.whole($0.grams)) \($0.letter)" } ?? "").font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(lead?.color ?? Ink.text3)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.body)
        .frame(minHeight: 34)
        .padding(.horizontal, 4)
        .background(fresh ? Color.accentColor.opacity(0.14) : Color.clear, in: .rect(cornerRadius: 10))
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(entries: [entry.id]) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menuBar.entry")
    }
}

// MARK: - Above the field

/// The usual foods for now (or what goes with the meal being eaten), each on ⌘1–⌘4.
private struct MenuBarTiles: View {
    let composer: TodayComposer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(composer.tilesTitle).eyebrow()
                Spacer()
                Text("One key logs it, even mid-word").font(.caption).foregroundStyle(Ink.text2)
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(composer.tiles.prefix(4).enumerated()), id: \.element.id) { index, item in
                    Button {
                        composer.logAlone(item)
                    } label: {
                        tile(item, key: index + 1)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityIdentifier("menuBar.usual.\(index)")
                    .accessibilityLabel(
                        "Log \(FoodLabel.short(item.template.name)), \(item.template.amountLabel), \(Format.kcal(item.template.nutrients.kcal))")
                }
            }
        }
    }

    private func tile(_ item: LogAgainItem, key: Int) -> some View {
        HStack(spacing: 8) {
            FoodTile(name: item.template.name, size: 30, fill: Ink.raised)
            VStack(alignment: .leading, spacing: 0) {
                Text(FoodLabel.title(item.template.name)).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text("\(item.template.amountLabel) · \(Format.kcal(item.template.nutrients.kcal))").font(.caption).foregroundStyle(Ink.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            KeyCap("⌘\(key)")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.cardBackground, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }
}

/// What the food being typed could be, rising above the field: the picked one (the best, unless ↑
/// moved) outlined, with the key that logs it.
private struct MenuBarMatches: View {
    @Environment(AppModel.self) private var model
    let composer: TodayComposer
    let picked: Int

    var body: some View {
        let count = composer.earlier.compactMap(\.entry).count + 1
        VStack(spacing: 3) {
            ForEach(Array(composer.matches.enumerated().reversed()), id: \.element.id) { index, match in
                Button {
                    composer.log(match)
                } label: {
                    row(match, picked: index == picked, count: count)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menuBar.match.\(index)")
            }
        }
    }

    private func row(_ match: TodayComposer.Candidate, picked: Bool, count: Int) -> some View {
        let name = match.title(canDescribe: model.ai.canDescribe)
        let short = Text(name.short).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
        let title = name.rest.map { Text("\(short)  \(Text($0).font(.caption).foregroundStyle(Ink.text2))") } ?? short
        return HStack(spacing: 10) {
            switch match.kind {
            case .food: FoodTile(name: match.entry.name, size: 32, fill: Ink.raised)
            case .quickAdd, .unmatched:
                Text("≈").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2).frame(width: 32, height: 32)
                    .background(Ink.raised, in: .rect(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 1) {
                title.lineLimit(1)
                Text(match.detail(model.ai)).font(.caption).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Spacer(minLength: 6)
            if picked { KeyCap(count > 1 ? "return · logs \(count)" : "return", prominent: true) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: picked ? 52 : 44)
        .background(picked ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 14))
        .overlay {
            if picked { RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityHint(picked ? "Return logs it" : "")
    }
}

/// A key as it's printed on the keyboard, for the shortcuts the panel answers to.
private struct KeyCap: View {
    let key: String
    var prominent = false

    init(_ key: String, prominent: Bool = false) {
        self.key = key
        self.prominent = prominent
    }

    var body: some View {
        Text(key)
            .font(.caption.weight(.semibold))
            .foregroundStyle(prominent ? Ink.text : Ink.text2)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: prominent ? 24 : 20)
            .background(Ink.raised, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.hairline))
            .accessibilityHidden(true)
    }
}
#endif
