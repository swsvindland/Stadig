import NutritionEngine
import SwiftUI
import SystemCore

/// The person's own targets (`OwnTargets`): calories as the big number, and protein, carbs and fat in
/// grams with each one's share of the calories, kept in step: the grams add up to the calories, and
/// the calories move carbs and fat, never protein. It starts from the plan's numbers (or the person's
/// own, once set) and shows the plan's beside them, with the way back to them while the person's own
/// are on. Plan's Adjust, the assessment's "Set my own targets" and onboarding's starting point open it.
struct TargetsSheet: View {
    /// Where it was opened from, over the title.
    let eyebrow: String
    /// The numbers the plan sets, or the assessment's maintenance, or the starting point: shown
    /// beside, and the place to start again from.
    let reference: MacroTargets
    let source: OwnTargets.Source
    /// The foot's words: "Use these targets", or onboarding's "Start logging".
    let action: String
    /// Back to the plan's targets (or the assessment's), while the person's own are on.
    let back: (() -> Void)?
    let save: (MacroTargets) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The calories' and the grams' faces, growing with the text size to half again, as a numeral does.
    @ScaledMetric(relativeTo: .largeTitle) private var kcalSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title2) private var gramsSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var gramsWidth: CGFloat = 58
    @State private var draft: MacroTargets
    /// The numbers as they were when the calories began to change, which each keystroke and step of
    /// the calories works from, so typing "2" on the way to "2400" doesn't lose how carbs and fat split.
    @State private var base: MacroTargets?
    /// What's typed in the field being edited; the others show the numbers.
    @State private var typed: [Field: String] = [:]
    @FocusState private var focus: Field?

    enum Field: String, Hashable { case kcal, protein, carbs, fat }

    init(
        eyebrow: String, initial: MacroTargets, reference: MacroTargets, source: OwnTargets.Source, action: String,
        back: (() -> Void)? = nil, save: @escaping (MacroTargets) -> Void
    ) {
        self.eyebrow = eyebrow
        self.reference = reference
        self.source = source
        self.action = action
        self.back = back
        self.save = save
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                FormHeading(
                    eyebrow: eyebrow, title: "Your targets",
                    detail: "A coach's, a dietitian's or your own. The weekly check-in leaves them as they are.")
                Group { sections }.inkRows()
            }
            .inkForm()
            .inkSheet {
                SheetBar(label: "Cancel", identifier: "targets.cancel") { dismiss() }
            } foot: {
                SheetFoot {
                    Button {
                        save(draft)
                        dismiss()
                    } label: {
                        Text(action).frame(maxWidth: .infinity)
                    }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("targets.save")
                }
            }
            .onChange(of: focus) { old, new in
                // Leaving a field shows its number as the draft has it; entering one, as it's typed.
                if let old { typed[old] = nil }
                if let new { typed[new] = Format.editable(value(new), digits: 0) }
            }
        }
        .macSheetSize(width: 460, height: 660)
    }

    var problem: String? { OwnTargets.problem(draft) }

    @ViewBuilder
    var sections: some View {
        Section {
            VStack(spacing: 16) {
                if typeSize.isAccessibilitySize {
                    // The number on a line of its own and − and + under it, where beside it they'd
                    // push it off the sheet.
                    kcalField
                    HStack {
                        nudge(.kcal, -1, size: 52)
                        Spacer()
                        nudge(.kcal, 1, size: 52)
                    }
                } else {
                    HStack(spacing: 12) {
                        nudge(.kcal, -1, size: 52)
                        kcalField
                        nudge(.kcal, 1, size: 52)
                    }
                }
                MacroSplitBar(targets: draft)
            }
            .padding(.vertical, 8)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } footer: {
            // In step, and saying so, or why these can't be saved yet; and the reference's calories,
            // to set these against before scrolling to the rest of it.
            Text(problem ?? "Protein, carbs and fat add up to this. \(referenceTitle): \(Format.kcal(reference.kcal)).")
                .foregroundStyle(problem == nil ? Ink.text3 : Ink.ok)
                .accessibilityIdentifier("targets.note")
        }
        Section {
            grams(.protein, macro: .protein, grams: draft.protein, share: draft.shares.protein)
            grams(.carbs, macro: .carbs, grams: draft.carbs, share: draft.shares.carbs)
            grams(.fat, macro: .fat, grams: draft.fat, share: draft.shares.fat)
        } header: {
            SectionEyebrow("Grams a day", detail: "Share of calories")
        } footer: {
            Text("Change the calories and carbs and fat move to fit them; protein stays where you put it.")
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Measure(value: Format.whole(reference.kcal), unit: "kcal", size: 24, weight: .heavy).foregroundStyle(Ink.text)
                HStack(spacing: 14) {
                    referenceGrams(.protein, reference.protein)
                    referenceGrams(.carbs, reference.carbs)
                    referenceGrams(.fat, reference.fat)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("targets.reference")
            if draft != reference {
                Button("Start from these") {
                    focus = nil
                    base = nil
                    draft = reference
                }
                .foregroundStyle(Ink.words(.accentColor))
                .accessibilityIdentifier("targets.startFromReference")
            }
        } header: {
            SectionEyebrow(referenceTitle, detail: difference)
        } footer: {
            Text(referenceNote)
        }
        if let back {
            Section {
                FormActionRow(backTitle, identifier: "targets.usePlans") {
                    back()
                    dismiss()
                }
            }
        }
    }

    var kcalField: some View {
        let size = min(kcalSize, 56 * 1.5)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("0", text: text(.kcal))
                .fieldKeyboard(.number)
                .multilineTextAlignment(.center)
                // The numeral's face without its shrinking to fit, which a field sized to the number
                // would take as room to shrink into (as the weigh-in's).
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .tracking(-size * 0.035)
                .foregroundStyle(Ink.text)
                .focused($focus, equals: .kcal)
                .fixedSize()
                .macLabelsHidden()
                .accessibilityLabel("Calories a day")
                .accessibilityIdentifier("targets.kcal")
            Text("kcal").font(.title3.weight(.semibold)).foregroundStyle(Ink.text2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rows

    func grams(_ field: Field, macro: Macro, grams: Double, share: Double) -> some View {
        let name = HStack(spacing: 8) {
            Circle().fill(macro.color).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(macro.label).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text(Format.percent(share)).font(.caption.monospacedDigit()).foregroundStyle(Ink.text3)
            }
        }
        let controls = HStack(spacing: 8) {
            nudge(field, -1, size: 36)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField("0", text: text(field))
                    .fieldKeyboard(.number)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: min(gramsSize, 24 * 1.5), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
                    .focused($focus, equals: field)
                    .frame(width: min(gramsWidth, 58 * 1.5))
                    // A fingertip's height to tap into, as the − and + beside it have.
                    .frame(minHeight: 44)
                    .macLabelsHidden()
                    .accessibilityLabel("\(macro.label), grams a day")
                    .accessibilityValue("\(Format.whole(grams)) grams, \(Format.percent(share)) of calories")
                    .accessibilityIdentifier("targets.\(field.rawValue)")
                Text("g").font(.callout.weight(.semibold)).foregroundStyle(Ink.text2)
            }
            nudge(field, 1, size: 36)
        }
        return Group {
            if typeSize.isAccessibilitySize {
                // The macro's name over its grams, where beside them it's a word a line.
                VStack(alignment: .leading, spacing: 6) {
                    name
                    controls
                }
            } else {
                HStack(spacing: 8) {
                    name
                    Spacer(minLength: 6)
                    controls
                }
            }
        }
        .padding(.vertical, 2)
    }

    func referenceGrams(_ macro: Macro, _ grams: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle().fill(macro.color).frame(width: 6, height: 6)
            Text("\(Format.whole(grams)) g").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
            Text(macro.label.lowercased()).font(.caption).foregroundStyle(Ink.text3)
        }
    }

    /// − or +: 50 kcal, or 5 g, onto round numbers. Calories move carbs and fat from where they
    /// were when the calories began to change.
    func nudge(_ field: Field, _ direction: Double, size: CGFloat) -> some View {
        Button {
            focus = nil
            if field == .kcal {
                let from = base ?? draft
                base = from
                draft = from.calories(OwnTargets.stepped(draft.kcal, by: direction, step: OwnTargets.kcalStep))
            } else {
                set(field, OwnTargets.stepped(value(field), by: direction, step: OwnTargets.gramStep))
            }
        } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(size > 40 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Ink.text)
                .frame(width: size, height: size)
                .background(Ink.raised, in: .circle)
                // A fingertip's room round a smaller disc.
                .frame(width: max(44, size), height: max(44, size))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("\(direction < 0 ? "Less" : "More") \(field == .kcal ? "calories" : field.rawValue)")
        .accessibilityIdentifier("targets.\(field.rawValue).\(direction < 0 ? "less" : "more")")
    }

    // MARK: Numbers

    /// A field's text: as typed while it's being edited, else the draft's number (the calories
    /// grouped, "2,100", which nothing parses back).
    func text(_ field: Field) -> Binding<String> {
        Binding {
            if let typed = typed[field] { return typed }
            return field == .kcal ? Format.whole(draft.kcal) : Format.editable(value(field), digits: 0)
        } set: { text in
            // A field not being edited is only ever showing the draft.
            guard focus == field else { return }
            typed[field] = text
            if field == .kcal {
                // Whole calories: a grouping mark typed or left in is ignored rather than read as a point.
                guard let kcal = Format.parse(text.filter { !",.'\u{00A0}\u{202F} ".contains($0) }) else { return }
                let from = base ?? draft
                base = from
                draft = from.calories(kcal)
            } else if let grams = Format.parse(text) {
                set(field, grams)
            }
        }
    }

    func value(_ field: Field) -> Double {
        switch field {
        case .kcal: draft.kcal
        case .protein: draft.protein
        case .carbs: draft.carbs
        case .fat: draft.fat
        }
    }

    /// A macro's grams, the calories following.
    func set(_ field: Field, _ grams: Double) {
        base = nil
        draft = MacroTargets.grams(
            protein: field == .protein ? grams : draft.protein, carbs: field == .carbs ? grams : draft.carbs,
            fat: field == .fat ? grams : draft.fat)
    }

    // MARK: Words

    var referenceTitle: String {
        switch source {
        case .plan: "The plan's"
        case .maintenance: "Maintenance so far"
        case .startingPoint: "Your starting point"
        }
    }

    var referenceNote: String {
        switch source {
        case .plan:
            "What the plan sets today. Its weekly check-in keeps working these out under yours, so going back picks up where it would be."
        case .maintenance:
            "The assessment sets no calories: this is your maintenance so far, split as the plan would. It keeps learning under your targets."
        case .startingPoint:
            "The formula's first guess at your maintenance. The assessment learns the real one from what you log, whatever you eat to."
        }
    }

    var backTitle: String { source == .plan ? "Use the plan's targets" : "Back to eating as usual" }

    /// "Yours: 150 under", against the reference.
    var difference: String? {
        let gap = (draft.kcal - reference.kcal).rounded()
        guard abs(gap) >= 1 else { return "The same as these" }
        return "Yours: \(Format.whole(abs(gap))) \(gap < 0 ? "under" : "over")"
    }
}

/// How protein, carbs and fat split the calories, as one bar in their colours: the starting point's,
/// and the targets sheet's as the grams move.
struct MacroSplitBar: View {
    let targets: MacroTargets

    var body: some View {
        let shares = targets.shares
        Group {
            if shares.protein + shares.carbs + shares.fat > 0 {
                WeightedRow(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.protein).frame(height: 14).layoutWeight(shares.protein)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.carbs).frame(height: 14).layoutWeight(shares.carbs)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.fat).frame(height: 14).layoutWeight(shares.fat)
                }
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Ink.track).frame(height: 14)
            }
        }
        .animation(.snappy(duration: 0.25), value: targets)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Calories split: \(Format.percent(shares.protein)) protein, \(Format.percent(shares.carbs)) carbs, \(Format.percent(shares.fat)) fat"
        )
    }
}

/// The targets sheet as Plan opens it: from the person's own numbers once set, else the plan's (or
/// in the assessment, maintenance so far), with the plan's beside them.
struct PlanTargetsSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let analysis = model.analysis {
            TargetsSheet(
                eyebrow: "Plan", initial: analysis.own?.numbers ?? analysis.planNumbers, reference: analysis.planNumbers,
                source: analysis.planSource, action: "Use these targets",
                back: analysis.own == nil ? nil : { model.useThePlansTargets() }
            ) { model.setOwnTargets($0) }
        }
    }
}
