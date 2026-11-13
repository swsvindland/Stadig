import HealthBridge
import NutritionEngine
import SwiftUI
import SystemCore

/// A minute of setup, ending on the starting point: the formula's maintenance for the answers, as
/// calories a day and how they split. Answers already given in Stadig Lift are reused, not asked
/// again. Every step is the same page: a back button and a ruler of how far through, the title on
/// the page, and its one button at the foot.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var profile = SharedProfile(goals: [], experience: .intermediate, createdBy: .macroTrack)
    @State private var reused = false
    @State private var history = DietHistory.none
    @State private var weightText = ""
    @State private var heightText = ""
    /// Health's weight, kept in kg so it reads right in whichever units are chosen.
    @State private var healthKg: Double?
    @State private var connecting = false
    /// Whether Health was connected on the way: its weigh-ins can shorten the assessment.
    @State private var connectedHealth = false

    enum Step: Int { case welcome, about, eating, health, start }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome { progress }
                Group {
                    switch step {
                    case .welcome: welcome
                    case .about: about
                    case .eating: eating
                    case .health: health
                    case .start: start
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .animation(.snappy, value: step)
            .inkGround()
            .hidesNavigationBar(true)
        }
        .onAppear {
            if let shared = model.sharedProfile ?? model.profile {
                profile = shared
                reused = true
            }
            #if DEBUG
            // -onboardingStep about|eating|health|start opens that step, for checking it; the start
            // needs a weight, so it gets 82 kg.
            if let name = LaunchOptions.current.value(after: "-onboardingStep"),
                let open = [Step.about, .eating, .health, .start].first(where: { "\($0)" == name })
            {
                if open == .start, weightText.isEmpty { weightText = healthText(82) }
                step = open
            }
            #endif
            if let h = profile.heightCm { heightText = Format.editable(profile.units.length.fromCentimetres(h), digits: 0) }
        }
        .task {
            if let kg = await model.healthWeight(), weightText.isEmpty {
                healthKg = kg
                weightText = healthText(kg)
            }
        }
    }

    // MARK: Steps

    /// Back, and how far through: a ruler filling a step at a time, nearly full on the last.
    var progress: some View {
        HStack(spacing: 14) {
            CircleIconButton(symbol: "chevron.left", label: "Back", identifier: "onboarding.back", action: back)
            Ruler.thin(step == .start ? 0.92 : Double(step.rawValue) / 4)
                .accessibilityLabel("Step \(step.rawValue) of 4")
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// A step's title on the page, and what it's for.
    func title(_ title: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).pageTitle().lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    /// A form step's title, on the ground at the top of its rows.
    func pageTitle(_ text: String) -> some View {
        Section {
            Text(text).pageTitle()
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 0, trailing: 4))
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text("Stadig Macro").pageTitle()
            VStack(alignment: .leading, spacing: 20) {
                point("bolt.fill", "Log in seconds", "Search, scan, snap a photo or just say what you ate. Usual foods are one tap.")
                point("waveform.path.ecg", "Learns your real maintenance", "Two to three weeks of normal eating and morning weigh-ins. No diet yet.")
                point("flag", "Then one clear plan", "A cut, a bulk or maintenance, chosen from your data, with the reasons.")
            }
            if reused {
                Label(
                    "Using your setup from \(model.sharedProfile?.createdBy.displayName ?? "another Stadig app"): goals, height and age.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(Ink.text2)
            }
            Spacer()
            Button {
                step = reused ? .eating : .about
            } label: {
                Text("Get started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.solid)
            .accessibilityIdentifier("onboarding.getStarted")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .readableWidth(560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var about: some View {
        Form {
            pageTitle("About you")
            Group { aboutSections }.inkRows()
        }
        .inkForm()
        .safeAreaInset(edge: .bottom) {
            next(enabled: !profile.goals.isEmpty) {
                if let h = Format.parse(heightText), h > 0 {
                    profile.heightCm = profile.units.length.toCentimetres(h)
                }
                step = .eating
            }
        }
    }

    @ViewBuilder
    var aboutSections: some View {
        Section {
            ForEach(OutcomeGoal.allCases) { goal in
                Button {
                    if let i = profile.goals.firstIndex(of: goal) { profile.goals.remove(at: i) } else { profile.goals.append(goal) }
                } label: {
                    HStack {
                        Label(goal.label, systemImage: goal.symbol)
                        Spacer()
                        if profile.goals.contains(goal) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
            }
        } header: {
            Text("What do you want?").eyebrow()
        }
        Section {
            // Units first, so numbers are typed in the units already chosen. A number typed
            // before a change is left as typed: it was often typed meaning the new unit.
            Picker(
                "Units",
                selection: Binding(
                    get: { profile.units.weight },
                    set: { w in
                        let untouched = healthKg.map { weightText == healthText($0) } ?? false
                        profile.units = UnitPreference(weight: w, length: w == .kg ? .cm : .inch)
                        if untouched, let healthKg { weightText = healthText(healthKg) }
                    })
            ) {
                Text("kg, cm").tag(WeightUnit.kg)
                Text("lb, in").tag(WeightUnit.lb)
            }
            .accessibilityIdentifier("onboarding.units")
            Picker("Sex", selection: $profile.sex) {
                ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("onboarding.sex")
            Picker("Born", selection: Binding(get: { birthYear }, set: { profile.birthYear = $0 })) {
                ForEach(birthYears.reversed(), id: \.self) { Text(String($0)).tag($0) }
            }
            .accessibilityIdentifier("onboarding.birthYear")
            HStack {
                Text("Height")
                Spacer()
                TextField("0", text: $heightText).fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 80)
                    .accessibilityIdentifier("onboarding.height")
                Text(profile.units.length.symbol).foregroundStyle(.secondary)
            }
        } header: {
            Text("You").eyebrow()
        }
        Section {
            Stepper("\(profile.schedule.daysPerWeek) days a week", value: $profile.schedule.daysPerWeek, in: 0...7)
                .accessibilityIdentifier("onboarding.trainingDays")
            Picker("Lifting for", selection: $profile.experience) {
                ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("onboarding.experience")
        } header: {
            Text("Training").eyebrow()
        }
    }

    var eating: some View {
        Form {
            pageTitle("Eating lately")
            Group { eatingSections }.inkRows()
        }
        .inkForm()
        .safeAreaInset(edge: .bottom) {
            next(enabled: !weightTyped || weightKg != nil) { step = .health }
        }
    }

    @ViewBuilder
    var eatingSections: some View {
        Section {
            ForEach(DietHistory.allCases) { option in
                Button {
                    history = option
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if history == option { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("onboarding.history.\(option.rawValue)")
            }
        } header: {
            Text("Lately you've been…").eyebrow()
        } footer: {
            Text("Months of dieting usually lowers maintenance. Knowing that changes the first recommendation.")
        }
        Section {
            HStack {
                Text("Weight today")
                Spacer()
                TextField("Optional", text: $weightText).fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 90)
                    .accessibilityIdentifier("onboarding.weight")
                Text(profile.units.weight.symbol).foregroundStyle(.secondary)
            }
        } footer: {
            if weightTyped && weightKg == nil {
                Text("That doesn't look like a weight in \(profile.units.weight.symbol). Check the number, or leave it empty.")
            } else {
                Text("Every morning from here: weigh in first thing. Health fills this in if your scale syncs to it.")
            }
        }
    }

    @ViewBuilder
    var health: some View {
        if Platform.isMac { healthElsewhere } else { connectHealth }
    }

    var connectHealth: some View {
        VStack(alignment: .leading, spacing: 0) {
            title(
                "Connect Apple Health",
                "Weigh-ins from a smart scale arrive on their own, and what you log is saved to Health. Stadig Lift's measurements and training come straight from Stadig Lift, not through Health."
            )
            Image(systemName: "heart.text.square.fill").font(.system(size: 56)).foregroundStyle(.pink).padding(.horizontal, 20).padding(.top, 16)
                .accessibilityHidden(true)
            Spacer()
            VStack(spacing: 4) {
                Button {
                    connecting = true
                    Task {
                        await model.connectHealth()
                        connectedHealth = true
                        onward()
                    }
                } label: {
                    Text(connecting ? "Connecting…" : "Connect Health").frame(maxWidth: .infinity)
                }
                .buttonStyle(.solid)
                .disabled(connecting || !HealthBridge.shared.isAvailable)
                .accessibilityIdentifier("onboarding.connectHealth")
                quiet("Not now", identifier: "onboarding.notNow", action: onward)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .readableWidth(560)
    }

    /// The Mac has no Health: what reaches it instead, and a way on.
    var healthElsewhere: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Apple Health", HealthWords.notOnThisDevice)
            Spacer()
            Button(action: onward) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.solid)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding.notNow")
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .readableWidth(560)
    }

    /// The starting point: the formula's maintenance for the answers given, and how it splits. With
    /// no weight to start from there's nothing to show yet, and setup ends at Health.
    @ViewBuilder
    var start: some View {
        if let point = startingPoint {
            let shares = point.shares
            VStack(alignment: .leading, spacing: 0) {
                title("Here's your\nstarting point", "Your maintenance, as a first guess. No diet yet: eat as usual while it learns the real one.")
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Measure(value: Format.whole(point.kcal), unit: "kcal a day", size: 76, weight: .heavy)
                            .foregroundStyle(Ink.text)
                            .accessibilityIdentifier("onboarding.kcal")
                        WeightedRow(spacing: 3) {
                            ForEach([Macro.protein, .carbs, .fat], id: \.self) { macro in
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(macro.color).frame(height: 14)
                                    .layoutWeight(share(macro, shares))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "Calories split: \(Format.percent(shares.protein)) protein, \(Format.percent(shares.carbs)) carbs, \(Format.percent(shares.fat)) fat"
                        )
                    }
                    HStack(alignment: .top, spacing: 14) {
                        grams(.protein, point.protein, shares.protein)
                        grams(.carbs, point.carbs, shares.carbs)
                        grams(.fat, point.fat, shares.fat)
                    }
                }
                .inkCard(padding: 16)
                .padding(.horizontal, 16)
                Text(
                    "\(Text("An early estimate.").fontWeight(.semibold).foregroundStyle(Ink.text)) It sharpens as you log and weigh in over \(connectedHealth ? "the next two or three weeks" : "\(point.assessmentDays) days")."
                )
                .font(.subheadline).foregroundStyle(Ink.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                Spacer()
                Button(action: finish) {
                    Text("Start logging").frame(maxWidth: .infinity)
                }
                .buttonStyle(.solid)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.start")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .readableWidth(560)
        }
    }

    func share(_ macro: Macro, _ shares: (protein: Double, carbs: Double, fat: Double)) -> Double {
        switch macro {
        case .protein: shares.protein
        case .carbs: shares.carbs
        default: shares.fat
        }
    }

    func grams(_ macro: Macro, _ grams: Double, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Measure(value: Format.whole(grams), unit: "g", size: 40, weight: .heavy).foregroundStyle(Ink.text)
            Text("\(Text(macro.label).foregroundStyle(macro.color)) · \(Format.percent(share))").font(.caption).foregroundStyle(Ink.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The numbers the starting point shows, from the answers and today's weight (typed, or Health's).
    var startingPoint: StartingPoint? {
        guard let kg = weightKg ?? healthKg else { return nil }
        var profile = profile
        profile.birthYear = profile.birthYear ?? birthYear
        return StartingPoint.make(profile: profile, weightKg: kg, today: model.today)
    }

    /// On from Health: to the starting point, or done when there's no weight to start from.
    func onward() {
        if startingPoint != nil { step = .start } else { finish() }
    }

    /// A quiet way on beside the main button, as "Not now".
    func quiet(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2).frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Helpers

    /// The step before: a setup reused from another app skipped About you on the way in.
    func back() {
        switch step {
        case .welcome: break
        case .about: step = .welcome
        case .eating: step = reused ? .welcome : .about
        case .health: step = .eating
        case .start: step = .health
        }
    }

    func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func next(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(.solid)
        .disabled(!enabled)
        .accessibilityIdentifier("onboarding.continue")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Ink.ground.ignoresSafeArea(edges: .bottom))
    }

    /// Health's weight as the field shows it in the units chosen.
    func healthText(_ kg: Double) -> String { Format.editable(profile.units.weight.fromKilograms(kg), digits: 1) }

    var weightTyped: Bool { !weightText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The weight typed, while it's one a person could be (the trend's own rule): a weight typed
    /// in the wrong unit, or a typo, isn't the first weigh-in.
    var weightKg: Double? {
        guard let value = Format.parse(weightText) else { return nil }
        let kg = profile.units.weight.toKilograms(value)
        return Weight.isPlausible(kg: kg) ? kg : nil
    }

    /// Years that make someone 10 to 100 today.
    var birthYears: ClosedRange<Int> { SharedProfile.plausibleBirthYears(on: model.today) }

    /// The year the picker shows: the profile's, unless there's none or it's one nobody could be
    /// born in (bad data from another app), then 1990.
    var birthYear: Int { profile.birthYear.flatMap { birthYears.contains($0) ? $0 : nil } ?? 1990 }

    func finish() {
        // What the picker showed is what's saved. A setup reused from another app skips the
        // picker, so its year is kept as it is unless there's none.
        if !reused || profile.birthYear == nil { profile.birthYear = birthYear }
        model.completeOnboarding(profile: profile, history: history, weightKg: weightKg)
    }
}
