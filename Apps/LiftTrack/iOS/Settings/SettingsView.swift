import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore
import SystemStore
import UniformTypeIdentifiers

/// Settings as a sheet on iPhone, iPad and Vision Pro. The Mac shows the same parts as panes of its
/// Settings window (`MacSettings`).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var prompts = DataPrompts()

    var body: some View {
        Form {
            Group {
                if let profile = model.profile {
                    Section {
                        NavigationLink("Goals, schedule and experience") { ProfileEditor(profile: profile) }
                            .accessibilityIdentifier("settings.profile")
                        NavigationLink("Training outside the gym") { RecurringScreen(profile: profile) }
                            .accessibilityIdentifier("settings.outside")
                    } header: {
                        Text("About you").eyebrow()
                    } footer: {
                        Text("Shared with the other apps in the family, so it's asked once.")
                    }
                }
                Section {
                    NavigationLink {
                        GymEditor(gym: model.gym)
                    } label: {
                        LabeledContent("Equipment and plates", value: model.gym.name)
                    }
                    .accessibilityIdentifier("settings.gym")
                } header: {
                    Text("Gym").eyebrow()
                }
                TrainingSections()
                DataSections(prompts: $prompts)
            }
            .inkRows()
        }
        .inkList()
        .dataPrompts($prompts)
        .accessibilityIdentifier("settings.screen")
        .navigationTitle("Settings")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
    }
}

/// The Mac's Training pane.
struct TrainingSettings: View {
    var body: some View {
        Form { TrainingSections() }
    }
}

/// The Mac's Data pane.
struct DataSettings: View {
    @State private var prompts = DataPrompts()

    var body: some View {
        Form { DataSections(prompts: $prompts) }
            .dataPrompts($prompts)
    }
}

/// Training, physique and Apple Health.
struct TrainingSections: View {
    @Environment(AppModel.self) private var model
    @AppStorage(FloorMode.automaticKey) private var floorAutomatic = true

    var body: some View {
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
                LabeledContent("Phase from Stadig Macro", value: phase.kind.label)
            }
        } header: {
            Text("Training").eyebrow()
        } footer: {
            Text(
                "With your Watch running the session, rest can end early once your heart rate has recovered (accessories only; heavy lifts keep their minimum rest)."
            )
        }
        if Platform.hasFloorMode {
            Section {
                Toggle("Floor mode when set down", isOn: $floorAutomatic)
                    .accessibilityIdentifier("settings.floorMode")
            } header: {
                Text("Session").eyebrow()
            } footer: {
                Text(
                    "Lay your iPhone flat during a session and the set fills the screen: tap anywhere for Just right, swipe up for Easy, down for Missed. Pick it up to change the weight. The session's menu turns it on at any angle."
                )
            }
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
            Text("Physique").eyebrow()
        } footer: {
            Text("\(proportionTargets.detail) Focus areas come first, and nothing asks for fat loss once you're lean.")
        }
        // Every device but the Mac has Health; there it can still be unavailable (switched off
        // under tests), which leaves the rows in place with Connect off, as before.
        if !Platform.isMac {
            Section {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .disabled(!HealthBridge.shared.isAvailable)
                toggle("Save sessions to Health", \.saveToHealth)
            } header: {
                Text("Apple Health").eyebrow()
            }
        } else {
            Section {
                Text(
                    "Apple Health lives on your iPhone, iPad, Apple Watch and Vision Pro, not this \(Platform.deviceName). What you log here, and the outside workouts your iPhone brings in from Health, reach it through iCloud. Steps, sleep, heart rate and Health's weigh-ins stay on your other devices, and sessions logged here aren't saved to Health."
                )
                .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Apple Health").eyebrow()
            }
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

/// What the data sections ask to show over the whole form: the file picker for a restore and the
/// message a backup or restore ends with. The form presents them, not a section:
/// on a section of a lazy form a presentation is attached to each row, and goes when the rows
/// scroll away.
struct DataPrompts {
    var importing = false
    var message: String?
    /// A backup or restore is running: it covers every record, photos included.
    var working = false
}

extension View {
    /// Presents the data sections' prompts (`DataPrompts`), and runs the restore a picked file starts.
    func dataPrompts(_ prompts: Binding<DataPrompts>) -> some View {
        modifier(DataPromptsPresenter(prompts: prompts))
    }
}

private struct DataPromptsPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var prompts: DataPrompts

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $prompts.importing, allowedContentTypes: DataSections.backupTypes) { result in
                switch result {
                case .success(let url):
                    Task { await restore(from: url) }
                case .failure(let error):
                    prompts.message = error.localizedDescription
                }
            }
            .alert("Data", isPresented: Binding(get: { prompts.message != nil }, set: { if !$0 { prompts.message = nil } })) {
                Button("OK") { prompts.message = nil }.accessibilityIdentifier("settings.messageOK")
            } message: {
                Text(prompts.message ?? "")
            }
    }

    private func restore(from url: URL) async {
        prompts.working = true
        defer { prompts.working = false }
        do {
            let summary = try await model.importBackup(from: url)
            prompts.message = "Restored \(summary.records) records."
        } catch {
            prompts.message = error.localizedDescription
        }
    }
}

/// Export, backup and restore, and what Stadig Lift is part of. What they show over
/// the form is in `prompts`, which the form presents.
struct DataSections: View {
    @Environment(AppModel.self) private var model
    @Binding var prompts: DataPrompts
    @State private var exportURLs: [URL] = []
    @State private var backupURL: URL?

    private var working: Bool { prompts.working }

    var body: some View {
        Section {
            Button("Export CSV", systemImage: "tablecells") {
                do { exportURLs = try model.exportCSV() } catch { prompts.message = error.localizedDescription }
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
            Button("Restore from a backup", systemImage: "arrow.counterclockwise") { prompts.importing = true }
                .disabled(working)
                .accessibilityIdentifier("settings.restore")
            if working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Working through your records…").foregroundStyle(.secondary)
                }
            }
            SyncStatusRows(records: model.store.syncState, shared: model.family?.syncState)
        } header: {
            Text("Your data").eyebrow()
        } footer: {
            Text(
                "Everything is yours and portable. iCloud keeps your devices in step; a backup file restores everything without it. Restoring merges: the newest copy of each record wins."
            )
        }
        Section {
            Text(
                "Stadig Lift is one of the Stadig apps, with \(AppID.macroTrack.displayName) for nutrition. Both are free and open source. Each works on its own; together they share setup, life modes, deloads and your scores."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }
        #if DEBUG
        Section("Debug") {
            Button("Erase everything", role: .destructive) { model.eraseEverything() }
        }
        #endif
    }

    /// Stadig Lift's backups (Info.plist exports the type), and plain JSON for one renamed on the way.
    /// Another app's backup is refused when it's read.
    static let backupTypes = [UTType(exportedAs: "dev.svindland.stadig.lift-backup"), .json]

    private func makeBackup() async {
        prompts.working = true
        defer { prompts.working = false }
        do { backupURL = try await model.exportBackup() } catch { prompts.message = error.localizedDescription }
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
    @State private var edit: EditedCopy<SharedProfile>

    init(profile: SharedProfile) {
        _edit = State(initialValue: EditedCopy(profile))
    }

    var body: some View {
        Form {
            Section {
                ForEach(OutcomeGoal.allCases) { goal in
                    Toggle(
                        goal.label,
                        isOn: Binding(
                            get: { edit.value.goals.contains(goal) },
                            set: { on in
                                if on { edit.value.goals.append(goal) } else { edit.value.goals.removeAll { $0 == goal } }
                            }))
                }
            } header: {
                Text("Goals").eyebrow()
            }
            Section {
                Stepper("\(edit.value.schedule.daysPerWeek) days a week", value: $edit.value.schedule.daysPerWeek, in: 1...6)
                Picker("Minutes per session", selection: $edit.value.schedule.minutesPerSession) {
                    ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0)").tag($0) }
                }
                WeekdayPicker(selection: $edit.value.schedule.preferredDays)
            } header: {
                Text("Schedule").eyebrow()
            }
            Section {
                Picker("Lifting for", selection: $edit.value.experience) {
                    ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Experience").eyebrow()
            }
            Section {
                Picker("Standards for", selection: $edit.value.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                BirthYearField(year: $edit.value.birthYear)
                MeasureField(label: "Height", value: $edit.value.heightCm, unit: edit.value.units.length)
                Picker("Weight unit", selection: $edit.value.units.weight) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                Picker("Length unit", selection: $edit.value.units.length) {
                    Text("cm").tag(LengthUnit.cm)
                    Text("in").tag(LengthUnit.inch)
                }
            } header: {
                Text("Basics").eyebrow()
            }
            Section {
                Text("Schedule and goal changes shape the next block. The current block keeps its days.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .inkList()
        .navigationTitle("About you")
        .editing($edit, of: model.profile) { edited, original in model.save(profileEdits: edited, from: original) }
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
        .inkList()
        .navigationTitle("Focus")
        .inlineTitle()
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
    @State private var edit: EditedCopy<SharedProfile>

    init(profile: SharedProfile) {
        _edit = State(initialValue: EditedCopy(profile))
    }

    var body: some View {
        ScrollView {
            OutsideActivitiesEditor(
                recurring: $edit.value.recurring, title: "Outside the gym",
                detail: "Stadig Lift plans around these; they spend the same recovery."
            )
            .padding()
        }
        .background(.pageBackground)
        .editing($edit, of: model.profile) { edited, original in model.save(profileEdits: edited, from: original) }
    }
}

/// Saves on the way out only when something changed, and only that, onto the gym as it is then:
/// a visit never re-stamps an older copy as newest.
struct GymEditor: View {
    @Environment(AppModel.self) private var model
    @State private var edit: EditedCopy<Gym>

    init(gym: Gym) {
        _edit = State(initialValue: EditedCopy(gym))
    }

    /// The copy being edited.
    private var gym: Gym {
        get { edit.value }
        nonmutating set { edit.value = newValue }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $edit.value.name)
                Picker("Kind", selection: Binding(get: { gym.access }, set: { gym = gym.switched(to: $0) })) {
                    ForEach(EquipmentAccess.allCases) { Text($0.label).tag($0) }
                }
                Picker("Plates in", selection: Binding(get: { gym.unit }, set: { gym = gym.converted(to: $0) })) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(Equipment.allCases) { item in
                    Toggle(
                        item.label,
                        isOn: Binding(
                            get: { gym.equipment.contains(item) },
                            set: { on in
                                if on { gym.equipment.insert(item) } else { gym.equipment.remove(item) }
                            }))
                }
            } header: {
                Text("Equipment").eyebrow()
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
                Text("Fixtures").eyebrow()
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
                Text("Recovery").eyebrow()
            } footer: {
                Text(
                    "Sessions end with an optional sauna or steam room, outside the time you train. Read the thermometer and the minutes follow, moved by how the last one felt."
                )
            }
            Section {
                LabeledContent("Bar", value: "\(Format.number(gym.barWeight)) \(gym.unit.symbol)")
                LabeledContent("Plates", value: gym.plates.map { Format.number($0, digits: 2) }.joined(separator: ", "))
                Stepper(
                    "Dumbbells up to \(Format.number(gym.dumbbellMax)) \(gym.unit.symbol)", value: $edit.value.dumbbellMax,
                    in: gym.dumbbellStep...200,
                    step: gym.dumbbellStep)
                Stepper(
                    "Dumbbell steps of \(Format.number(gym.dumbbellStep)) \(gym.unit.symbol)", value: $edit.value.dumbbellStep, in: 0.5...10,
                    step: 0.5)
                Stepper("Stack steps of \(Format.number(gym.machineStep)) \(gym.unit.symbol)", value: $edit.value.machineStep, in: 1...20, step: 0.5)
            } header: {
                Text("Loads").eyebrow()
            }
        }
        .inkList()
        .navigationTitle("Gym")
        .editing($edit, of: model.gym) { edited, original in model.save(gymEdits: edited, from: original) }
    }
}

/// A settings screen's copy of a stored record (the profile, the gym), with the record it started
/// from, so leaving saves only what changed in this visit (`AppModel.save(profileEdits:from:)`).
/// It catches up with the stored record whenever nothing here is waiting to be saved: a pane of the
/// Mac's Settings window stays alive between visits, and would otherwise go on editing, and write
/// back, the copy it first opened with.
struct EditedCopy<Record: Equatable>: Equatable {
    var value: Record
    private(set) var original: Record

    init(_ record: Record) {
        value = record
        original = record
    }

    /// Something changed here that isn't saved yet.
    var isPending: Bool { value != original }

    /// The stored record as it is now, synced in or saved elsewhere: taken unless something here is
    /// waiting to be saved, which the save then puts onto it field by field.
    mutating func catchUp(to latest: Record?) {
        guard !isPending, let latest else { return }
        value = latest
        original = latest
    }

    /// The record as just saved from here: the starting point for whatever changes next.
    mutating func saved(_ record: Record) {
        value = record
        original = record
    }
}

extension View {
    /// Keeps a settings screen's copy current (`EditedCopy`): caught up with the stored record when
    /// the screen appears and whenever the record changes, and saved on the way out with `save`,
    /// which is given the edited copy and the original and returns the record as saved (nil when
    /// nothing was).
    func editing<Record: Equatable>(
        _ copy: Binding<EditedCopy<Record>>, of latest: Record?, save: @escaping (Record, Record) -> Record?
    ) -> some View {
        onAppear { copy.wrappedValue.catchUp(to: latest) }
            .onChange(of: latest) { _, latest in copy.wrappedValue.catchUp(to: latest) }
            .onDisappear {
                guard copy.wrappedValue.isPending, let saved = save(copy.wrappedValue.value, copy.wrappedValue.original) else { return }
                copy.wrappedValue.saved(saved)
            }
    }
}
