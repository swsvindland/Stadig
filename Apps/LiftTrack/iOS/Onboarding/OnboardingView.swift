import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

/// Day 0: about five minutes, once. Goals as outcomes, schedule, equipment, experience, outside
/// training, the basics, then straight into the assessment. Answers go to the shared core, so
/// another app in the family never asks again.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable {
        case welcome, goals, focus, schedule, equipment, experience, outside, body, phase, health, ready
    }

    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var step: Step = .welcome
    @State private var profile = SharedProfile(createdBy: .liftTrack)
    @State private var settings = LiftSettings()
    @State private var bodyweight: Double?
    @State private var waist: Double?
    @State private var shoulders: Double?
    @State private var reusedProfile = false
    /// A sauna or steam room where they train: no preset assumes one.
    @State private var rooms: Set<Apparatus> = []

    private var steps: [Step] {
        Step.allCases.filter { step in
            if step == .phase { return model.nutrition == nil }
            // The focus is Stadig Lift's own, so it's asked even when the shared setup is reused.
            if reusedProfile { return [.welcome, .focus, .equipment, .phase, .health, .ready].contains(step) }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { topBar }
            ScrollView {
                content
                    .padding()
                    .readableWidth(620)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(.pageBackground)
        .animation(.default, value: step)
        .onAppear {
            if let shared = model.sharedProfile {
                profile = shared
                reusedProfile = true
            } else {
                profile.units = .regional
            }
            #if DEBUG
            // `-onboardingStep goals` opens on that step, to check it without tapping through.
            if let name = LaunchOptions.current.value(after: "-onboardingStep"), let shown = Step.allCases.first(where: { "\($0)" == name }) {
                step = shown
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .goals: goals
        case .focus: focus
        case .schedule: schedule
        case .equipment: equipment
        case .experience: experience
        case .outside:
            OutsideActivitiesEditor(
                recurring: $profile.recurring, title: "Training outside the gym",
                detail: "Classes and sport you do regularly. Stadig Lift plans around them, because they spend the same recovery.")
        case .body: bodyBasics
        case .phase: phase
        case .health: health
        case .ready: ready
        }
    }

    /// Back, and how far along: "2 of 9". The welcome isn't counted.
    private var topBar: some View {
        // By order, so a step that dropped out of the list (Stadig Macro took the phase) still has a place.
        let position = steps.lastIndex { $0.rawValue <= step.rawValue } ?? 0
        let count = steps.count - 1
        return StepBar(step: position, count: count) { move(-1) }
            .padding(.horizontal)
            .padding(.top, 8)
            .readableWidth(620)
    }

    /// The one way on, full width at the foot, on the ground, under what the answers add up to.
    private var footer: some View {
        VStack(spacing: 12) {
            if step == .goals, let summary = goalsSummary {
                summary.font(.subheadline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.goalsSummary")
            }
            continueButton
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .readableWidth(620)
    }

    /// "Stronger and leaner. Your plan will balance both."
    private var goalsSummary: Text? {
        let picked = OutcomeGoal.cardOrder.filter(profile.goals.contains).map(\.label)
        guard let first = picked.first else { return nil }
        let rest = picked.dropFirst().map { $0.lowercased() }
        let names = rest.isEmpty ? first : "\(([first] + rest.dropLast()).joined(separator: ", ")) and \(rest.last ?? "")"
        let lead = Text("\(names).").foregroundStyle(Ink.text).fontWeight(.semibold)
        let plan = Text(
            picked.count == 1
                ? " Your plan is built around it." : (picked.count == 2 ? " Your plan will balance both." : " Your plan will balance them.")
        )
        .foregroundStyle(Ink.text2)
        return Text("\(lead)\(plan)")
    }

    private var continueButton: some View {
        Button {
            if step == .ready { finish() } else { move(1) }
        } label: {
            Text(step == .ready ? "Start the assessment" : (step == .welcome ? "Get started" : "Continue")).frame(maxWidth: .infinity)
        }
        .primaryAction()
        .controlSize(.large)
        .disabled(!canContinue)
        // One identifier for every step, so a test can walk through them.
        .accessibilityIdentifier("onboarding.next")
    }

    private var canContinue: Bool {
        switch step {
        case .goals: !profile.goals.isEmpty
        default: true
        }
    }

    /// By step order, not position in the list: the list can change under the current step (Stadig
    /// Macro set up meanwhile drops the phase question), and that step still needs a way on.
    private func move(_ direction: Int) {
        let next = direction > 0 ? steps.first { $0.rawValue > step.rawValue } : steps.last { $0.rawValue < step.rawValue }
        if let next { step = next }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 40)
                .accessibilityHidden(true)
            PageTitle("Stadig Lift", size: 36)
            Text("Every session prescribed, every set adjusted to how it went, and a plan that tells you what to do next.")
                .font(.title3).foregroundStyle(Ink.text)
            VStack(alignment: .leading, spacing: 14) {
                Label("Rate each set Easy, Just right or Missed. That's all.", systemImage: "hand.tap")
                Label("The first weeks find your working weights and how well your ratings match what you can do.", systemImage: "scope")
                Label("Then real blocks, built around your weakest lifts, your schedule and your recovery.", systemImage: "calendar")
                Label("Free and open source. Your data stays yours.", systemImage: "lock.open")
            }
            .font(.body)
            .foregroundStyle(Ink.text2)
            .labelStyle(AccentIconLabelStyle())
            if reusedProfile {
                Label("Your setup from another app in the family is already here. Nothing to re-enter.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Ink.good)
                    .card()
            }
        }
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("What are you training for?", "Pick any that matter. You can change them later.")
            let goals = OutcomeGoal.cardOrder
            if dynamicType.isAccessibilitySize {
                ForEach(goals) { goal in goalCard(goal, stacked: false) }
            } else {
                // Two by two, as the design has them, each row's cards as tall as each other.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: goals.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(goals[start..<min(start + 2, goals.count)]) { goal in goalCard(goal, stacked: true) }
                        }
                    }
                }
            }
        }
    }

    private func goalCard(_ goal: OutcomeGoal, stacked: Bool) -> some View {
        let selected = profile.goals.contains(goal)
        return ChoiceCard(
            title: goal.label, detail: stacked ? goal.shortDetail : goal.detail, symbol: goal.cardSymbol, selected: selected, stacked: stacked,
            identifier: "onboarding.goal\(goal.rawValue.identifierSuffix)"
        ) {
            if selected { profile.goals.removeAll { $0 == goal } } else { profile.goals.append(goal) }
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Anything to bring up?", "Optional. Pick up to two areas and they get extra sets every block. Everything else is still trained.")
            ForEach(PhysiqueRegion.allCases) { region in
                let selected = settings.focus.contains(region)
                let full = !selected && settings.focus.count >= LiftSettings.focusLimit
                ChoiceCard(
                    title: region.label, detail: region.focusDetail, selected: selected,
                    identifier: "onboarding.focus\(region.rawValue.identifierSuffix)"
                ) {
                    // Checked here too: quick taps can land before the row shows as full.
                    if selected {
                        settings.focus.remove(region)
                    } else if settings.focus.count < LiftSettings.focusLimit {
                        settings.focus.insert(region)
                    }
                }
                .disabled(full)
                .opacity(full ? 0.5 : 1)
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("When can you train?", "Stadig Lift fits every session into the time you have.")
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Days a week", detail: "\(profile.schedule.daysPerWeek) sessions")
                InkSegmented(options: (1...6).map { (value: $0, label: "\($0)") }, selection: $profile.schedule.daysPerWeek)
                    .accessibilityLabel("Days a week")
            }
            .card()
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Minutes per session")
                InkSegmented(options: [30, 45, 60, 75, 90].map { (value: $0, label: "\($0)") }, selection: $profile.schedule.minutesPerSession)
                    .accessibilityLabel("Minutes per session")
                Text(minutesHint).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            .card()
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Preferred days", detail: "Optional")
                WeekdayPicker(selection: $profile.schedule.preferredDays)
                Text("Missed a day? The next session just waits for you.").font(.caption).foregroundStyle(Ink.text3)
            }
            .card()
        }
    }

    private var minutesHint: String {
        switch profile.schedule.minutesPerSession {
        case ...35: "Short: ramp-up sets are the warm-up, mobility happens in the rests, two big lifts."
        case ..<70: "A short warm-up, a mobility slot, the main lifts, a few accessories and brief conditioning."
        default: "A full warm-up, the lifting, and a proper conditioning finisher."
        }
    }

    private var equipment: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Where do you train?", "Exercises are chosen from what's there.")
            ForEach(EquipmentAccess.allCases) { access in
                ChoiceCard(
                    title: access.label, detail: access.detail, selected: profile.equipment == access,
                    identifier: "onboarding.equipment\(access.rawValue.identifierSuffix)"
                ) { profile.equipment = access }
            }
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("Units")
                UnitRow(title: "Weight", options: [(value: WeightUnit.kg, label: "kg"), (value: .lb, label: "lb")], selection: $profile.units.weight)
                    .font(.subheadline).foregroundStyle(Ink.text2)
                UnitRow(
                    title: "Length", options: [(value: LengthUnit.cm, label: "cm"), (value: .inch, label: "in")], selection: $profile.units.length
                )
                .font(.subheadline).foregroundStyle(Ink.text2)
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("After training")
                ForEach(Apparatus.allCases.filter(\.isRecovery), id: \.self) { room in
                    Toggle(
                        room.label,
                        isOn: Binding(
                            get: { rooms.contains(room) },
                            set: { on in
                                if on { rooms.insert(room) } else { rooms.remove(room) }
                            }))
                }
                Text("Sessions end with an optional sauna or steam room, timed from its thermometer.")
                    .font(.caption).foregroundStyle(Ink.text3)
            }
            .card()
        }
    }

    private var experience: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                "How long have you been lifting?",
                "Newer lifters tend to underestimate how many reps they have left, so Stadig Lift checks more often at first. Accurate ratings earn trust, whatever your experience."
            )
            ForEach(TrainingExperience.allCases) { level in
                ChoiceCard(
                    title: level.label, selected: profile.experience == level,
                    identifier: "onboarding.experience\(level.rawValue.identifierSuffix)"
                ) { profile.experience = level }
            }
        }
    }

    private var bodyBasics: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                "A few basics",
                "Strength is scored against bodyweight-relative standards. Measurements are optional and only for your own comparison.")
            RowCard(title: "You") {
                HStack {
                    Text("Standards for")
                    Spacer(minLength: 8)
                    Picker("Standards for", selection: $profile.sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                BirthYearField(year: $profile.birthYear, placeholder: "1990")
                MeasureField(label: "Height", value: $profile.heightCm, unit: profile.units.length)
                WeightField(label: "Body weight", kg: $bodyweight, unit: profile.units.weight)
            }
            RowCard(title: "Measurements", detail: "Optional") {
                MeasureField(label: "Waist", value: $waist, unit: profile.units.length)
                MeasureField(label: "Shoulders", value: $shoulders, unit: profile.units.length)
            }
            Text("Daily weigh-ins to Apple Health help Stadig Macro later, if you add it.").font(.caption).foregroundStyle(Ink.text3)
                .padding(.horizontal, 4)
        }
    }

    private var phase: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Right now, are you…", "One tap. With Stadig Macro this is decided from your data instead.")
            ForEach(SelfReportedPhase.allCases) { answer in
                ChoiceCard(
                    title: answer.label, selected: settings.selfReportedPhase == answer,
                    identifier: "onboarding.phase\(answer.rawValue.identifierSuffix)"
                ) { settings.selfReportedPhase = answer }
            }
            Text("A stall during a cut is expected, not a plateau. Knowing the phase keeps the advice honest.").font(.caption).foregroundStyle(
                Ink.text3
            )
            .padding(.horizontal, 4)
        }
    }

    @State private var healthAsked = false

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                "Apple Health",
                "Sleep, HRV and resting heart rate shape your recovery budget. Runs and classes other apps record are counted automatically. Sessions are saved as workouts."
            )
            if Platform.isMac {
                Text(
                    "Apple Health lives on your iPhone, iPad, Apple Watch and Vision Pro, not this Mac. Connect it from Stadig Lift on one of those; what it brings in reaches this Mac through iCloud."
                )
                .font(.caption).foregroundStyle(Ink.text3)
            } else {
                Button {
                    Task {
                        await model.connectHealth()
                        healthAsked = true
                    }
                } label: {
                    Label(healthAsked ? "Connected" : "Connect Apple Health", systemImage: healthAsked ? "checkmark.circle.fill" : "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                // Continue is the step's one filled button; connecting is the choice on it.
                .secondaryAction()
                .controlSize(.large)
                .disabled(healthAsked || !HealthBridge.shared.isAvailable)
                .accessibilityIdentifier("onboarding.connectHealth")
                if !HealthBridge.shared.isAvailable {
                    Text("Health isn't available on this device.").font(.caption).foregroundStyle(Ink.text3).padding(.horizontal, 4)
                }
                RowCard {
                    Toggle("Save sessions to Health", isOn: $settings.saveToHealth)
                        .accessibilityIdentifier("onboarding.saveToHealth")
                }
            }
        }
    }

    private var ready: some View {
        let weeks = profile.experience.assessmentWeeks
        return VStack(alignment: .leading, spacing: 12) {
            header("Your first \(weeks) weeks", "Useful from day one: good workouts and fast logging while Stadig Lift learns.")
            RowCard(title: "The assessment") {
                stage(1, "Find working weights", "Weeks 1–2. For anything new, pick a weight you think you can do for the reps shown, and rate it.")
                stage(
                    2, "Check your ratings",
                    "Machines get the occasional all-out set. They're safe to fail, and they show how well your ratings match reality.")
                stage(3, "Spot imbalances", "Weeks 3–4: progressive sets that spot strength imbalances.")
                stage(4, "Your first block", "Then your first real block, with a plain \"Why?\" behind it.")
            }
            Text("No deficit or surplus is needed during the assessment.").font(.caption).foregroundStyle(Ink.text3).padding(.horizontal, 4)
        }
    }

    /// One stage of the first weeks, numbered as the session numbers its sets.
    private func stage(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(number == 1 ? Ink.onAccent : Ink.text2)
                .frame(width: 26, height: 26)
                .background(number == 1 ? Color.accentColor : .clear, in: .circle)
                .overlay { Circle().strokeBorder(number == 1 ? .clear : Ink.track, lineWidth: 1.5) }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text(detail).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func header(_ title: String, _ detail: String) -> some View {
        StepHeading(title, detail: detail)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private func finish() {
        var gym = Gym.preset(profile.equipment, unit: profile.units.weight)
        gym.name = profile.equipment.label
        gym.apparatus.formUnion(rooms)
        var measurements: BodyMeasurements?
        if bodyweight != nil || waist != nil || shoulders != nil {
            measurements = BodyMeasurements(day: .today, weightKg: bodyweight, shouldersCm: shoulders, waistCm: waist)
        }
        model.completeOnboarding(profile: profile, settings: settings, gym: gym, measurements: measurements)
    }
}

// MARK: - Shared editors

/// One answer to a one-tap question, with its check: picked, it's outlined in the accent.
struct ChoiceCard: View {
    let title: String
    var detail: String?
    var symbol: String?
    let selected: Bool
    /// The symbol and check over the words, for a card in a grid.
    var stacked = false
    /// Required, so no card is left out of the UI tests.
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            if let symbol { icon(symbol) }
                            Spacer()
                            check
                        }
                        Spacer(minLength: 0)
                        words
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HStack(spacing: 14) {
                        if let symbol { icon(symbol).frame(width: 36) }
                        words
                        Spacer(minLength: 4)
                        check
                    }
                }
            }
            .padding(stacked ? 14 : 16)
            .frame(maxWidth: .infinity, minHeight: stacked ? 138 : nil, alignment: .leading)
            .background(
                selected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.cardBackground),
                in: .rect(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(selected ? Color.accentColor : Ink.text2).frame(height: 26)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(stacked ? .system(size: 18, weight: .bold) : .headline).tracking(stacked ? -0.3 : 0).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(stacked ? .caption : .subheadline).foregroundStyle(selected || !stacked ? Ink.text2 : Ink.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The design's check: a filled accent circle with a tick when picked, an empty ring when not.
    private var check: some View {
        ZStack {
            if selected {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Ink.onAccent)
            } else {
                Circle().strokeBorder(Ink.track, lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// A label whose icon is in the accent and whose words keep the text's colour.
struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.foregroundStyle(.tint).frame(width: 24)
            configuration.title
        }
    }
}

/// A birth year that only reaches the profile when it's a plausible one. A two-digit or future year
/// would otherwise become an age of 1936 or -4, which the heart-rate zones, the step floor and Stadig
/// Macro's energy estimate all take at face value; out of range, the age stays unknown.
struct BirthYearField: View {
    @Binding var year: Int?
    let placeholder: String
    @State private var typed: Int?

    init(year: Binding<Int?>, placeholder: String = "—") {
        _year = year
        self.placeholder = placeholder
        _typed = State(initialValue: year.wrappedValue)
    }

    var body: some View {
        let range = SharedProfile.plausibleBirthYears(on: .today)
        let invalid = typed.map { !range.contains($0) } ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Birth year")
                Spacer()
                TextField(placeholder, value: $typed, format: .number.grouping(.never))
                    .fieldKeyboard(.number).multilineTextAlignment(.trailing).frame(width: 90)
                    .foregroundStyle(invalid ? Ink.bad : Color.primary)
                    .accessibilityLabel("Birth year")
            }
            if invalid {
                Text("Enter the full year, \(String(range.lowerBound)) to \(String(range.upperBound)).").font(.caption).foregroundStyle(Ink.bad)
            }
        }
        .onChange(of: typed) { _, value in year = value.flatMap { range.contains($0) ? $0 : nil } }
        // A year that changed under the field (Settings catching up with one synced in) shows; a
        // typo still being typed, which leaves the year unknown, stays.
        .onChange(of: year) { _, year in
            if year != typed.flatMap({ range.contains($0) ? $0 : nil }) { typed = year }
        }
    }
}

/// Monday-first weekday chips.
struct WeekdayPicker: View {
    @Binding var selection: [Weekday]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = selection.contains(day)
                Button {
                    if on {
                        selection.removeAll { $0 == day }
                    } else {
                        selection.append(day)
                        selection.sort()
                    }
                } label: {
                    Text(day.short.prefix(2))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(on ? Ink.onAccent : Ink.text)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A length in the person's unit, stored in centimetres.
struct MeasureField: View {
    let label: String
    @Binding var value: Double?
    let unit: LengthUnit
    var identifier: String?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(
                "—",
                value: Binding(
                    get: { value.map { (unit.fromCentimetres($0) * 10).rounded() / 10 } },
                    set: { value = $0.map(unit.toCentimetres) }),
                format: .number.precision(.fractionLength(0...1))
            )
            .fieldKeyboard(.decimal)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .accessibilityIdentifier(identifier ?? "")
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }
}

/// A body weight in the person's unit, stored in kilograms.
struct WeightField: View {
    let label: String
    @Binding var kg: Double?
    let unit: WeightUnit

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(
                "—",
                value: Binding(
                    get: { kg.map { (unit.fromKilograms($0) * 10).rounded() / 10 } },
                    set: { kg = $0.map(unit.toKilograms) }),
                format: .number.precision(.fractionLength(0...1))
            )
            .fieldKeyboard(.decimal)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }
}

extension OutcomeGoal {
    /// The order the design lays the goals out in, two by two: strength and fitness first.
    static let cardOrder: [OutcomeGoal] = [.stronger, .fitter, .leaner, .biggerAndStronger, .healthier, .moreMobile]

    /// The goal in a few words, for its card in the grid.
    var shortDetail: String {
        switch self {
        case .stronger: "Heavier lifts, steadily"
        case .fitter: "Heart and lungs that last"
        case .leaner: "Lose fat, keep muscle"
        case .biggerAndStronger: "Add muscle and size"
        case .healthier: "Feel good, age well"
        case .moreMobile: "Move freely, without pain"
        }
    }

    /// The goal's symbol on its card, as the design draws them.
    var cardSymbol: String {
        switch self {
        case .stronger: "dumbbell"
        case .fitter: "waveform.path.ecg"
        case .leaner: "arrow.down.right.and.arrow.up.left"
        case .biggerAndStronger: "cellularbars"
        case .healthier: "heart"
        case .moreMobile: "figure.flexibility"
        }
    }
}
