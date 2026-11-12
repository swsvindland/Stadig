import HealthBridge
import NutritionEngine
import SwiftUI
import SystemCore

/// A minute of setup. Answers already given in Stadig Lift are reused, not asked again.
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

    enum Step: Int { case welcome, about, eating, health }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .about: about
                case .eating: eating
                case .health: health
                }
            }
            .animation(.snappy, value: step)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .navigation) {
                        Button("Back", systemImage: "chevron.left", action: back)
                            .accessibilityIdentifier("onboarding.back")
                    }
                    // How far through: a ruler, filling a step at a time.
                    ToolbarItem(placement: .principal) {
                        Ruler.thin(Double(step.rawValue) / 3)
                            .frame(width: 180)
                            .accessibilityLabel("Step \(step.rawValue) of 3")
                    }
                    .withoutSharedBackground()
                }
            }
        }
        .onAppear {
            if let shared = model.sharedProfile ?? model.profile {
                profile = shared
                reused = true
            }
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

    var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Stadig Macro").font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 18) {
                point("bolt.fill", "Log in seconds", "Search, scan, snap a photo or just say what you ate. Usual foods are one tap.")
                point("waveform.path.ecg", "Learns your real maintenance", "Two to three weeks of normal eating and morning weigh-ins. No diet yet.")
                point("map", "Then one clear plan", "A cut, a bulk or maintenance, chosen from your data, with the reasons.")
            }
            if reused {
                Label(
                    "Using your setup from \(model.sharedProfile?.createdBy.displayName ?? "another Stadig app"): goals, height and age.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                step = reused ? .eating : .about
            } label: {
                Text("Get started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .accessibilityIdentifier("onboarding.getStarted")
        }
        .padding(24)
        .readableWidth(560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkGround()
    }

    var about: some View {
        Form {
            Group { aboutSections }.inkRows()
        }
        .inkForm()
        .navigationTitle("About you")
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
        Section("What do you want?") {
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
        }
        Section("About you") {
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
        }
        Section("Training") {
            Stepper("\(profile.schedule.daysPerWeek) days a week", value: $profile.schedule.daysPerWeek, in: 0...7)
                .accessibilityIdentifier("onboarding.trainingDays")
            Picker("Lifting for", selection: $profile.experience) {
                ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("onboarding.experience")
        }
    }

    var eating: some View {
        Form {
            Group { eatingSections }.inkRows()
        }
        .inkForm()
        .navigationTitle("Eating lately")
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
            Text("Lately you've been…")
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
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 56)).foregroundStyle(.pink)
            Text("Connect Apple Health").font(.title.weight(.bold))
            Text(
                "Weigh-ins from a smart scale arrive on their own, and what you log is saved to Health. Stadig Lift's measurements and training come straight from Stadig Lift, not through Health."
            )
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                connecting = true
                Task {
                    await model.connectHealth()
                    finish()
                }
            } label: {
                Text(connecting ? "Connecting…" : "Connect Health").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .disabled(connecting || !HealthBridge.shared.isAvailable)
            .accessibilityIdentifier("onboarding.connectHealth")
            Button("Not now") { finish() }.frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("onboarding.notNow")
        }
        .padding(24)
        .readableWidth(560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkGround()
    }

    /// The Mac has no Health: what reaches it instead, and a way on.
    var healthElsewhere: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 56)).foregroundStyle(.pink)
            Text("Apple Health").font(.title.weight(.bold))
            Text(HealthWords.notOnThisDevice).foregroundStyle(.secondary)
            Spacer()
            Button(action: finish) {
                Text("Start").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding.notNow")
        }
        .padding(24)
        .readableWidth(560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkGround()
    }

    // MARK: Helpers

    /// The step before: a setup reused from another app skipped About you on the way in.
    func back() {
        switch step {
        case .welcome: break
        case .about: step = .welcome
        case .eating: step = reused ? .welcome : .about
        case .health: step = .eating
        }
    }

    func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    func next(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .primaryAction()
        .disabled(!enabled)
        .accessibilityIdentifier("onboarding.continue")
        .padding()
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
