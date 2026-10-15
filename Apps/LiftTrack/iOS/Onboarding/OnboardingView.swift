import SwiftUI
import ExerciseLibrary
import HealthBridge
import LiftEngine
import SystemCore

/// Day 0: about five minutes, once. Goals as outcomes, schedule, equipment, experience, outside
/// training, the basics, then straight into the assessment. Answers go to the shared core, so
/// another app in the family never asks again.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable {
        case welcome, goals, schedule, equipment, experience, outside, body, phase, health, ready
    }

    @State private var step: Step = .welcome
    @State private var profile = SharedProfile(createdBy: .liftTrack)
    @State private var settings = LiftSettings()
    @State private var bodyweight: Double?
    @State private var waist: Double?
    @State private var shoulders: Double?
    @State private var reusedProfile = false

    private var steps: [Step] {
        Step.allCases.filter { step in
            if step == .phase { return model.nutrition == nil }
            if reusedProfile { return [.welcome, .equipment, .phase, .health, .ready].contains(step) }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                ProgressView(value: Double((steps.firstIndex(of: step) ?? 0)), total: Double(steps.count - 1))
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
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
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .goals: goals
        case .schedule: schedule
        case .equipment: equipment
        case .experience: experience
        case .outside: OutsideActivitiesEditor(recurring: $profile.recurring, title: "Training outside the gym",
                                               detail: "Classes and sport you do regularly. Lift Track plans around them, because they spend the same recovery.")
        case .body: bodyBasics
        case .phase: phase
        case .health: health
        case .ready: ready
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(-1) }.secondaryAction()
            }
            Spacer()
            Button(step == .ready ? "Start the assessment" : (step == .welcome ? "Get started" : "Next")) {
                if step == .ready { finish() } else { move(1) }
            }
            .primaryAction()
            .disabled(!canContinue)
        }
        .padding()
        .background(.bar)
    }

    private var canContinue: Bool {
        switch step {
        case .goals: !profile.goals.isEmpty
        default: true
        }
    }

    private func move(_ direction: Int) {
        guard let index = steps.firstIndex(of: step) else { return }
        let next = index + direction
        if steps.indices.contains(next) { step = steps[next] }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 40)
            Text("Lift Track").font(.largeTitle.bold())
            Text("Every session prescribed, every set adjusted to how it went, and a plan that tells you what to do next.")
                .font(.title3)
            VStack(alignment: .leading, spacing: 14) {
                Label("Rate each set Easy, Just right or Missed. That's all.", systemImage: "hand.tap")
                Label("The first weeks find your working weights and how well your ratings match what you can do.", systemImage: "scope")
                Label("Then real blocks, built around your weakest lifts, your schedule and your recovery.", systemImage: "calendar")
                Label("One-time purchase. No subscription. Your data stays yours.", systemImage: "lock.open")
            }
            .font(.body)
            if reusedProfile {
                Label("Your setup from another app in the family is already here. Nothing to re-enter.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .card()
            }
        }
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("What are you after?", "Outcomes only. Lift Track picks the program, and Macro Track (if you use it) picks the diet phase.")
            ForEach(OutcomeGoal.allCases) { goal in
                let selected = profile.goals.contains(goal)
                Button {
                    if selected { profile.goals.removeAll { $0 == goal } } else { profile.goals.append(goal) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: goal.symbol).font(.title2).frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.label).font(.headline)
                            Text(goal.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("When can you train?", "Lift Track fits every session into the time you have.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Days a week").font(.headline)
                Picker("Days a week", selection: $profile.schedule.daysPerWeek) {
                    ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Minutes per session").font(.headline)
                Picker("Minutes", selection: $profile.schedule.minutesPerSession) {
                    ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text(minutesHint).font(.footnote).foregroundStyle(.secondary)
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Preferred days").font(.headline)
                WeekdayPicker(selection: $profile.schedule.preferredDays)
                Text("Optional. Missed a day? The next session just waits for you.").font(.footnote).foregroundStyle(.secondary)
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
                let selected = profile.equipment == access
                Button { profile.equipment = access } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(access.label).font(.headline)
                            Text(access.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Units").font(.headline)
                Picker("Weight", selection: $profile.units.weight) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                Picker("Length", selection: $profile.units.length) {
                    Text("cm").tag(LengthUnit.cm)
                    Text("in").tag(LengthUnit.inch)
                }
                .pickerStyle(.segmented)
            }
            .card()
        }
    }

    private var experience: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("How long have you been lifting?", "Newer lifters tend to underestimate how many reps they have left, so Lift Track checks more often at first. Accurate ratings earn trust, whatever your experience.")
            ForEach(TrainingExperience.allCases) { level in
                let selected = profile.experience == level
                Button { profile.experience = level } label: {
                    HStack {
                        Text(level.label).font(.headline)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var bodyBasics: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("A few basics", "Strength is scored against bodyweight-relative standards. Measurements are optional and only for your own comparison.")
            VStack(spacing: 14) {
                Picker("Standards for", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                HStack {
                    Text("Birth year")
                    Spacer()
                    TextField("1990", value: $profile.birthYear, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                Divider()
                MeasureField(label: "Height", value: $profile.heightCm, unit: profile.units.length)
                Divider()
                WeightField(label: "Body weight", kg: $bodyweight, unit: profile.units.weight)
            }
            .card()
            VStack(spacing: 14) {
                MeasureField(label: "Waist", value: $waist, unit: profile.units.length)
                Divider()
                MeasureField(label: "Shoulders", value: $shoulders, unit: profile.units.length)
            }
            .card()
            Text("Daily weigh-ins to Apple Health help Macro Track later, if you add it.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var phase: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Right now, are you…", "One tap. With Macro Track this is decided from your data instead.")
            ForEach(SelfReportedPhase.allCases) { answer in
                let selected = settings.selfReportedPhase == answer
                Button { settings.selfReportedPhase = answer } label: {
                    HStack {
                        Text(answer.label).font(.headline)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            Text("A stall during a cut is expected, not a plateau. Knowing the phase keeps the advice honest.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @State private var healthAsked = false

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Apple Health", "Sleep, HRV and resting heart rate shape your recovery budget. Runs and classes other apps record are counted automatically. Sessions are saved as workouts.")
            Button {
                Task {
                    await model.connectHealth()
                    healthAsked = true
                }
            } label: {
                Label(healthAsked ? "Connected" : "Connect Apple Health", systemImage: healthAsked ? "checkmark.circle.fill" : "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryAction()
            .disabled(healthAsked || !HealthBridge.shared.isAvailable)
            if !HealthBridge.shared.isAvailable {
                Text("Health isn't available on this device.").font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Save sessions to Health", isOn: $settings.saveToHealth).card()
        }
    }

    private var ready: some View {
        let weeks = profile.experience.assessmentWeeks
        return VStack(alignment: .leading, spacing: 16) {
            header("Your first \(weeks) weeks", "Useful from day one: good workouts and fast logging while Lift Track learns.")
            VStack(alignment: .leading, spacing: 14) {
                Label("Weeks 1–2: find working weights. For anything new, pick a weight you think you can do for 10 and rate it.", systemImage: "1.circle.fill")
                Label("Machines get the occasional all-out set. They're safe to fail, and they show how well your ratings match reality.", systemImage: "2.circle.fill")
                Label("Weeks 3–4: progressive sets that spot strength imbalances.", systemImage: "3.circle.fill")
                Label("Then your first real block, with a plain \"Why?\" behind it.", systemImage: "4.circle.fill")
            }
            .card()
            Text("No deficit or surplus is needed during the assessment.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(detail).font(.body).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func finish() {
        profile.createdBy = reusedProfile ? profile.createdBy : .liftTrack
        var gym = Gym.preset(profile.equipment, unit: profile.units.weight)
        gym.name = profile.equipment.label
        var measurements: BodyMeasurements?
        if bodyweight != nil || waist != nil || shoulders != nil {
            measurements = BodyMeasurements(day: .today, weightKg: bodyweight, shouldersCm: shoulders, waistCm: waist)
        }
        model.completeOnboarding(profile: profile, settings: settings, gym: gym, measurements: measurements)
    }
}

// MARK: - Shared editors

/// Monday-first weekday chips.
struct WeekdayPicker: View {
    @Binding var selection: [Weekday]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.removeAll { $0 == day } } else { selection.append(day); selection.sort() }
                } label: {
                    Text(day.short.prefix(2))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
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

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", value: Binding(get: { value.map { (unit.fromCentimetres($0) * 10).rounded() / 10 } },
                                          set: { value = $0.map(unit.toCentimetres) }),
                      format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
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
            TextField("—", value: Binding(get: { kg.map { (unit.fromKilograms($0) * 10).rounded() / 10 } },
                                          set: { kg = $0.map(unit.toKilograms) }),
                      format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }
}
