import SwiftUI
import HealthBridge
import NutritionEngine
import SystemCore

/// A minute of setup. Answers already given in Lift Track are reused, not asked again.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var profile = SharedProfile(goals: [], experience: .intermediate, createdBy: .macroTrack)
    @State private var reused = false
    @State private var history = DietHistory.none
    @State private var weightText = ""
    @State private var heightText = ""
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
        }
        .onAppear {
            if let shared = model.sharedProfile ?? model.profile {
                profile = shared
                reused = true
            }
            if let h = profile.heightCm { heightText = Format.number(profile.units.length.fromCentimetres(h), digits: 0) }
        }
        .task {
            if let kg = await model.healthWeight(), weightText.isEmpty {
                weightText = Format.number(profile.units.weight.fromKilograms(kg))
            }
        }
    }

    // MARK: Steps

    var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Macro Track").font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 18) {
                point("bolt.fill", "Log in seconds", "Search, scan, snap a photo or just say what you ate. Usual foods are one tap.")
                point("waveform.path.ecg", "Learns your real maintenance", "Two to three weeks of normal eating and morning weigh-ins. No diet yet.")
                point("map", "Then one clear plan", "A cut, a bulk or maintenance, chosen from your data, with the reasons.")
            }
            if reused {
                Label("Using your setup from \(model.sharedProfile?.createdBy.displayName ?? "the System"): goals, height and age.",
                      systemImage: "checkmark.circle.fill")
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
        }
        .padding(24)
        .readableWidth(560)
    }

    var about: some View {
        Form {
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
                }
            }
            Section("About you") {
                Picker("Sex", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                Picker("Born", selection: Binding(get: { profile.birthYear ?? 1990 }, set: { profile.birthYear = $0 })) {
                    ForEach((1940...(Day.today.year - 14)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                }
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("0", text: $heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text(profile.units.length.symbol).foregroundStyle(.secondary)
                }
                Picker("Units", selection: Binding(get: { profile.units.weight }, set: { w in
                    profile.units = UnitPreference(weight: w, length: w == .kg ? .cm : .inch)
                })) {
                    Text("kg, cm").tag(WeightUnit.kg)
                    Text("lb, in").tag(WeightUnit.lb)
                }
            }
            Section("Training") {
                Stepper("\(profile.schedule.daysPerWeek) days a week", value: $profile.schedule.daysPerWeek, in: 0...7)
                Picker("Lifting for", selection: $profile.experience) {
                    ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .navigationTitle("About you")
        .safeAreaInset(edge: .bottom) {
            next(enabled: !profile.goals.isEmpty) {
                if let h = Double(heightText.replacingOccurrences(of: ",", with: ".")), h > 0 {
                    profile.heightCm = profile.units.length.toCentimetres(h)
                }
                step = .eating
            }
        }
    }

    var eating: some View {
        Form {
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
                    TextField("Optional", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text(profile.units.weight.symbol).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Every morning from here: weigh in first thing. Health fills this in if your scale syncs to it.")
            }
        }
        .navigationTitle("Eating lately")
        .safeAreaInset(edge: .bottom) {
            next(enabled: true) { step = .health }
        }
    }

    var health: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 56)).foregroundStyle(.pink)
            Text("Connect Apple Health").font(.title.weight(.bold))
            Text("Weigh-ins from a smart scale arrive on their own, and what you log is saved to Health. Lift Track's measurements and training are read through the System, not Health.")
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
            Button("Not now") { finish() }.frame(maxWidth: .infinity)
        }
        .padding(24)
        .readableWidth(560)
    }

    // MARK: Helpers

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
        .padding()
    }

    func finish() {
        let kg = Double(weightText.replacingOccurrences(of: ",", with: ".")).map { profile.units.weight.toKilograms($0) }
        if profile.birthYear == nil { profile.birthYear = 1990 }
        model.completeOnboarding(profile: profile, history: history, weightKg: kg)
    }
}
