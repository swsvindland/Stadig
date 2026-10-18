import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore
import SystemStore
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var exportURLs: [URL] = []
    @State private var backupURL: URL?
    @State private var importing = false
    /// A backup or restore is running: it covers every record, photos included.
    @State private var working = false
    @State private var message: String?
    /// Presented from here: Settings is a sheet already, and a second sheet from the root can't show over it.
    @State private var showPaywall = false

    var body: some View {
        Form {
            if let profile = model.profile {
                Section {
                    NavigationLink("Goals, schedule and experience") { ProfileEditor(profile: profile) }
                        .accessibilityIdentifier("settings.profile")
                    NavigationLink("Training outside the gym") { RecurringScreen(profile: profile) }
                        .accessibilityIdentifier("settings.outside")
                } header: {
                    Text("About you")
                } footer: {
                    Text("Shared with the other apps in the family, so it's asked once.")
                }
            }
            Section("Gym") {
                NavigationLink {
                    GymEditor(gym: model.gym)
                } label: {
                    LabeledContent("Equipment and plates", value: model.gym.name)
                }
                .accessibilityIdentifier("settings.gym")
            }
            Section {
                toggle("Heart-rate guided rest", \.heartRateGuidedRest)
                toggle("Conditioning after lifting", \.includeConditioning)
                toggle("Stretching cool-down", \.includeCooldown)
                toggle("Prioritise automatically", \.autoPrioritise)
                Picker("Conditioning benchmark", selection: model.setting(\.benchmark)) {
                    ForEach(EnduranceBenchmark.allCases) { Text($0.label).tag($0) }
                }
                if model.nutrition?.phase == nil {
                    Picker("Right now I'm", selection: model.setting(\.selfReportedPhase)) {
                        Text("Not set").tag(SelfReportedPhase?.none)
                        ForEach(SelfReportedPhase.allCases) { Text($0.label).tag(SelfReportedPhase?.some($0)) }
                    }
                } else if let phase = model.nutrition?.phase {
                    LabeledContent("Phase from Macro Track", value: phase.kind.label)
                }
            } header: {
                Text("Training")
            } footer: {
                Text(
                    "With your Watch running the session, rest can end early once your heart rate has recovered (accessories only; heavy lifts keep their minimum rest)."
                )
            }
            Section {
                NavigationLink {
                    FocusScreen()
                } label: {
                    LabeledContent("Focus", value: model.settings.focusSummary)
                }
                .accessibilityIdentifier("settings.focus")
                Picker(
                    "Proportion targets",
                    selection: Binding(
                        get: { proportionTargets },
                        set: { targets in
                            var s = model.settings
                            s.proportionTargets = targets
                            model.save(settings: s)
                        })
                ) {
                    ForEach(ProportionTargets.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Physique")
            } footer: {
                Text("\(proportionTargets.detail) Focus areas come first, and nothing asks for fat loss once you're lean.")
            }
            Section("Apple Health") {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .disabled(!HealthBridge.shared.isAvailable)
                toggle("Save sessions to Health", \.saveToHealth)
            }
            Section {
                Button("Export CSV", systemImage: "tablecells") {
                    do { exportURLs = try model.exportCSV() } catch { message = error.localizedDescription }
                }
                .disabled(working)
                .accessibilityIdentifier("settings.exportCSV")
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) { Label("Share \(exportURLs.count) CSV files", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareCSV")
                }
                Button("Make a backup file", systemImage: "externaldrive") { Task { await makeBackup() } }
                    .disabled(working)
                    .accessibilityIdentifier("settings.backup")
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Save or share the backup", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareBackup")
                }
                Button("Restore from a backup", systemImage: "arrow.counterclockwise") { importing = true }
                    .disabled(working)
                    .accessibilityIdentifier("settings.restore")
                if working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Working through your records…").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Sync", value: model.store.syncStatus)
            } header: {
                Text("Your data")
            } footer: {
                Text(
                    "Everything is yours and portable. iCloud keeps your devices in step; a backup file restores everything without it. Restoring merges: the newest copy of each record wins."
                )
            }
            if Purchases.enabled {
                Section("Lift Track") {
                    if purchases.unlocked {
                        Label("Unlocked. Thank you.", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Unlock Lift Track") { showPaywall = true }
                        Button("Restore purchase") { Task { await purchases.restore() } }
                    }
                }
            }
            Section {
                Text(
                    "Lift Track is one of The System's apps: \(AppID.macroTrack.displayName) for nutrition, \(AppID.knowledge.displayName) for skills, and the hub that ties them together. Each works on its own; together they share setup, life modes and deloads."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
            #if DEBUG
            Section("Debug") {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
            }
            #endif
        }
        .accessibilityIdentifier("settings.screen")
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.backupTypes) { result in
            switch result {
            case .success(let url):
                Task { await restore(from: url) }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Data", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }.accessibilityIdentifier("settings.messageOK")
        } message: {
            Text(message ?? "")
        }
    }

    /// Lift Track's backups (Info.plist exports the type), and plain JSON for one renamed on the way.
    /// Another app's backup is refused when it's read.
    private static let backupTypes = [UTType(exportedAs: "dev.svindland.stadig.lift-backup"), .json]

    private func makeBackup() async {
        working = true
        defer { working = false }
        do { backupURL = try await model.exportBackup() } catch { message = error.localizedDescription }
    }

    private func restore(from url: URL) async {
        working = true
        defer { working = false }
        do {
            let summary = try await model.importBackup(from: url)
            message = "Restored \(summary.records) records."
        } catch {
            message = error.localizedDescription
        }
    }

    /// The chosen set, or the one for the person's standards.
    private var proportionTargets: ProportionTargets {
        model.settings.proportionTargets ?? .standard(for: model.profile?.sex ?? .unspecified)
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<LiftSettings, Bool>) -> some View {
        Toggle(title, isOn: model.setting(keyPath))
    }
}

extension AppModel {
    /// One setting, saved on every change.
    func setting<T>(_ keyPath: WritableKeyPath<LiftSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                var s = self.settings
                s[keyPath: keyPath] = value
                self.save(settings: s)
            })
    }
}

/// Saves on the way out, but only what was changed here and onto the latest copy: a visit that
/// changes nothing, or a field left alone, never overwrites a newer edit synced from another device.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @State private var profile: SharedProfile
    @State private var original: SharedProfile

    init(profile: SharedProfile) {
        _profile = State(initialValue: profile)
        _original = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section("Goals") {
                ForEach(OutcomeGoal.allCases) { goal in
                    Toggle(
                        goal.label,
                        isOn: Binding(
                            get: { profile.goals.contains(goal) },
                            set: { on in
                                if on { profile.goals.append(goal) } else { profile.goals.removeAll { $0 == goal } }
                            }))
                }
            }
            Section("Schedule") {
                Stepper("\(profile.schedule.daysPerWeek) days a week", value: $profile.schedule.daysPerWeek, in: 1...6)
                Picker("Minutes per session", selection: $profile.schedule.minutesPerSession) {
                    ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0)").tag($0) }
                }
                WeekdayPicker(selection: $profile.schedule.preferredDays)
            }
            Section("Experience") {
                Picker("Lifting for", selection: $profile.experience) {
                    ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Basics") {
                Picker("Standards for", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                BirthYearField(year: $profile.birthYear)
                MeasureField(label: "Height", value: $profile.heightCm, unit: profile.units.length)
                Picker("Weight unit", selection: $profile.units.weight) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                Picker("Length unit", selection: $profile.units.length) {
                    Text("cm").tag(LengthUnit.cm)
                    Text("in").tag(LengthUnit.inch)
                }
            }
            Section {
                Text("Schedule and goal changes shape the next block. The current block keeps its days.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About you")
        .onDisappear { saveChanges() }
    }

    private func saveChanges() {
        guard profile != original else { return }
        var latest = model.profile ?? original
        func take<T: Equatable>(_ field: WritableKeyPath<SharedProfile, T>) {
            if profile[keyPath: field] != original[keyPath: field] { latest[keyPath: field] = profile[keyPath: field] }
        }
        take(\.goals)
        take(\.schedule)
        take(\.experience)
        take(\.sex)
        take(\.birthYear)
        take(\.heightCm)
        take(\.units)
        model.save(profile: latest)
    }
}

/// Up to two areas the person wants brought up, whatever the analysis says.
struct FocusScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(PhysiqueRegion.allCases) { region in
                    let on = model.settings.focus.contains(region)
                    let full = !on && model.settings.focus.count >= LiftSettings.focusLimit
                    Toggle(
                        isOn: Binding(
                            get: { on },
                            set: { value in
                                var s = model.settings
                                if !value { s.focus.remove(region) } else if s.focus.count < LiftSettings.focusLimit { s.focus.insert(region) }
                                model.save(settings: s)
                            })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.label)
                            Text(region.focusDetail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(full)
                    // A disabled toggle barely looks it in a form.
                    .opacity(full ? 0.5 : 1)
                }
            } footer: {
                Text("Up to two. They get extra sets from your next block on, and the rest of the program makes room for them.")
            }
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension LiftSettings {
    var focusSummary: String {
        focus.isEmpty ? "None" : PhysiqueRegion.allCases.filter(focus.contains).map(\.label).joined(separator: ", ")
    }
}

extension PhysiqueRegion {
    /// What a focus here adds, in a few words.
    var focusDetail: String {
        switch self {
        case .shoulders: "Lateral raises and overhead work"
        case .chest: "Presses and flyes"
        case .back: "Rows and pulldowns"
        case .arms: "Curls and triceps work"
        case .core: "Direct ab work"
        case .glutes: "Hip thrusts and abduction"
        case .thighs: "Quad and hamstring work"
        case .calves: "Calf raises"
        }
    }
}

/// Saves on the way out only when something changed, onto the latest profile (see ProfileEditor).
struct RecurringScreen: View {
    @Environment(AppModel.self) private var model
    @State private var recurring: [RecurringActivity]
    @State private var original: [RecurringActivity]

    init(profile: SharedProfile) {
        _recurring = State(initialValue: profile.recurring)
        _original = State(initialValue: profile.recurring)
    }

    var body: some View {
        ScrollView {
            OutsideActivitiesEditor(
                recurring: $recurring, title: "Outside the gym",
                detail: "Lift Track plans around these; they spend the same recovery."
            )
            .padding()
        }
        .background(.pageBackground)
        .onDisappear {
            guard recurring != original, var latest = model.profile else { return }
            latest.recurring = recurring
            model.save(profile: latest)
        }
    }
}

/// Saves on the way out only when something changed, so a visit never re-stamps an older copy as newest.
struct GymEditor: View {
    @Environment(AppModel.self) private var model
    @State private var gym: Gym
    @State private var original: Gym

    init(gym: Gym) {
        _gym = State(initialValue: gym)
        _original = State(initialValue: gym)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $gym.name)
                Picker("Kind", selection: Binding(get: { gym.access }, set: { gym = gym.switched(to: $0) })) {
                    ForEach(EquipmentAccess.allCases) { Text($0.label).tag($0) }
                }
                Picker("Plates in", selection: Binding(get: { gym.unit }, set: { gym = gym.converted(to: $0) })) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
            }
            Section("Equipment") {
                ForEach(Equipment.allCases) { item in
                    Toggle(
                        item.label,
                        isOn: Binding(
                            get: { gym.equipment.contains(item) },
                            set: { on in
                                if on { gym.equipment.insert(item) } else { gym.equipment.remove(item) }
                            }))
                }
            }
            Section {
                ForEach(Apparatus.allCases.filter { !$0.isRecovery }, id: \.self) { item in
                    Toggle(
                        item.label,
                        isOn: Binding(
                            get: { gym.apparatus.contains(item) },
                            set: { on in
                                if on { gym.apparatus.insert(item) } else { gym.apparatus.remove(item) }
                            }))
                }
            } header: {
                Text("Fixtures")
            } footer: {
                Text("A rack with safeties makes barbell bench and squat safe to take to failure, for lifters who've earned it.")
            }
            Section {
                ForEach(Apparatus.allCases.filter(\.isRecovery), id: \.self) { item in
                    Toggle(
                        item.label,
                        isOn: Binding(
                            get: { gym.apparatus.contains(item) },
                            set: { on in
                                if on { gym.apparatus.insert(item) } else { gym.apparatus.remove(item) }
                            }))
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text(
                    "Sessions end with an optional sauna or steam room, outside the time you train. Read the thermometer and the minutes follow, moved by how the last one felt."
                )
            }
            Section("Loads") {
                LabeledContent("Bar", value: "\(Format.number(gym.barWeight)) \(gym.unit.symbol)")
                LabeledContent("Plates", value: gym.plates.map { Format.number($0, digits: 2) }.joined(separator: ", "))
                Stepper(
                    "Dumbbells up to \(Format.number(gym.dumbbellMax)) \(gym.unit.symbol)", value: $gym.dumbbellMax, in: gym.dumbbellStep...200,
                    step: gym.dumbbellStep)
                Stepper("Dumbbell steps of \(Format.number(gym.dumbbellStep)) \(gym.unit.symbol)", value: $gym.dumbbellStep, in: 0.5...10, step: 0.5)
                Stepper("Stack steps of \(Format.number(gym.machineStep)) \(gym.unit.symbol)", value: $gym.machineStep, in: 1...20, step: 0.5)
            }
        }
        .navigationTitle("Gym")
        .onDisappear { if gym != original { model.save(gym: gym) } }
    }
}
