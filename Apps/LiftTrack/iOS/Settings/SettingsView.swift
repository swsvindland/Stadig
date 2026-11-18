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
    #if DEBUG
    @State private var debugPage: String?
    #endif

    var body: some View {
        Form {
            FormHeading(eyebrow: "Stadig Lift", title: "Settings")
            Group {
                if let profile = model.profile {
                    Section {
                        NavigationLink {
                            ProfileEditor(profile: profile)
                        } label: {
                            SettingsRowLabel(title: "Goals, schedule and experience", caption: profileLine(profile))
                        }
                        .accessibilityIdentifier("settings.profile")
                        NavigationLink {
                            RecurringScreen(profile: profile)
                        } label: {
                            SettingsRowLabel(title: "Training outside the gym", caption: outsideLine(profile))
                        }
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
                        SettingsRowLabel(
                            title: "Equipment and plates",
                            caption: "\(model.gym.name) · \(model.gym.equipment.count) kinds of equipment · plates in \(model.gym.unit.symbol)")
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
        #if DEBUG
        // `-settingsPage profile|outside|gym|focus` opens that page of Settings.
        .navigationDestination(item: $debugPage) { page in
            switch page {
            case "profile": if let profile = model.profile { ProfileEditor(profile: profile) }
            case "outside": if let profile = model.profile { RecurringScreen(profile: profile) }
            case "gym": GymEditor(gym: model.gym)
            default: FocusScreen()
            }
        }
        .onAppear { debugPage = LaunchOptions.current.value(after: "-settingsPage") }
        #endif
        .accessibilityIdentifier("settings.screen")
        .navigationTitle("Settings")
        .inkSheet {
            SheetBar(label: "Done", identifier: "settings.done") { dismiss() }
        }
    }

    /// "Stronger, leaner · 4 days · 60 min".
    private func profileLine(_ profile: SharedProfile) -> String {
        let goals = OutcomeGoal.cardOrder.filter(profile.goals.contains).map(\.label)
        let named = goals.isEmpty ? "No goals" : ([goals[0]] + goals.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
        return "\(named) · \(profile.schedule.daysPerWeek) days · \(profile.schedule.minutesPerSession) min"
    }

    /// "BJJ Tue, Thu · Yoga Sat", or that there's none.
    private func outsideLine(_ profile: SharedProfile) -> String {
        guard !profile.recurring.isEmpty else { return "None yet. Health brings in what your watch records." }
        return profile.recurring.map { "\($0.activity.label) \($0.weekdays.map(\.short).joined(separator: ", "))" }.joined(separator: " · ")
    }
}

/// A Settings row that opens a page: what it is, and what's set there now under it.
private struct SettingsRowLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Ink.text)
            // Whole at the accessibility sizes, where two lines hold a few words.
            Text(caption).font(.caption).foregroundStyle(Ink.text3).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
        .padding(.vertical, 2)
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
            Picker("Benchmark", selection: model.setting(\.benchmark)) {
                ForEach(EnduranceBenchmark.allCases) { Text($0.label).tag($0) }
            }
            .valueTint()
            if model.nutrition?.phase == nil {
                Picker("Right now I'm", selection: model.setting(\.selfReportedPhase)) {
                    Text("Not set").tag(SelfReportedPhase?.none)
                    ForEach(SelfReportedPhase.allCases) { Text($0.label).tag(SelfReportedPhase?.some($0)) }
                }
                .valueTint()
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
                LabeledContent("Focus") { Text(model.settings.focusSummary).foregroundStyle(Ink.text2) }
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
            .valueTint()
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
/// The same questions as onboarding, asked the same way: goals as chips, the schedule and experience
/// on the segmented control, the basics as rows.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @State private var edit: EditedCopy<SharedProfile>

    init(profile: SharedProfile) {
        _edit = State(initialValue: EditedCopy(profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !Platform.isMac {
                    SheetHeading(eyebrow: "Settings", title: "About you", detail: "Shared with the other apps in the family, so it's asked once.")
                }
                goals
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle("Days a week", detail: "\(edit.value.schedule.daysPerWeek) sessions")
                    InkSegmented(options: (1...6).map { (value: $0, label: "\($0)") }, selection: $edit.value.schedule.daysPerWeek)
                        .accessibilityLabel("Days a week")
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    CardTitle("Minutes per session")
                    InkSegmented(options: Self.minutes.map { (value: $0, label: "\($0)") }, selection: $edit.value.schedule.minutesPerSession)
                        .accessibilityLabel("Minutes per session")
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    CardTitle("Preferred days", detail: "Optional")
                    WeekdayPicker(selection: $edit.value.schedule.preferredDays)
                }
                .card()
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle("Lifting for")
                    InkSegmented(options: TrainingExperience.allCases.map { (value: $0, label: $0.label) }, selection: $edit.value.experience)
                        .accessibilityLabel("Lifting for")
                }
                .card()
                RowCard(title: "Basics") {
                    HStack {
                        Text("Standards for")
                        Spacer(minLength: 8)
                        Picker("Standards for", selection: $edit.value.sex) {
                            ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .valueTint()
                    }
                    BirthYearField(year: $edit.value.birthYear)
                    MeasureField(label: "Height", value: $edit.value.heightCm, unit: edit.value.units.length)
                    UnitRow(
                        title: "Weight", options: [(value: WeightUnit.kg, label: "kg"), (value: .lb, label: "lb")],
                        selection: $edit.value.units.weight)
                    UnitRow(
                        title: "Length", options: [(value: LengthUnit.cm, label: "cm"), (value: .inch, label: "in")],
                        selection: $edit.value.units.length)
                }
                .font(.callout)
                .foregroundStyle(Ink.text)
                Text("Schedule and goal changes shape the next block. The current block keeps its days.")
                    .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Platform.isMac ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth(620)
        }
        .background(.pageBackground)
        .formPage("About you")
        .editing($edit, of: model.profile) { edited, original in model.save(profileEdits: edited, from: original) }
    }

    private static let minutes = [30, 45, 60, 75, 90]

    /// The goals as onboarding's six, in its order, each a chip.
    private var goals: some View {
        let picked = OutcomeGoal.cardOrder.filter(edit.value.goals.contains)
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Goals", detail: picked.isEmpty ? "Pick at least one" : "\(picked.count) picked")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(OutcomeGoal.cardOrder) { goal in
                    let on = edit.value.goals.contains(goal)
                    ChoiceChip(title: goal.label, isOn: on, identifier: "settings.goal\(goal.rawValue.identifierSuffix)") {
                        if on { edit.value.goals.removeAll { $0 == goal } } else { edit.value.goals.append(goal) }
                    }
                }
            }
        }
        .card()
    }
}

/// Up to two areas the person wants brought up, whatever the analysis says: onboarding's question,
/// its cards and their checks, saved on every tap.
struct FocusScreen: View {
    @Environment(AppModel.self) private var model
    /// Where it was opened from: Settings, or Plan's menu on a phone.
    var from = "Settings"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !Platform.isMac {
                    SheetHeading(
                        eyebrow: from, title: "Focus",
                        detail:
                            "Up to two areas to bring up. They get extra sets from your next block on, and the rest of the program makes room for them."
                    )
                    .padding(.bottom, 4)
                } else {
                    Text("Up to two. They get extra sets from your next block on, and the rest of the program makes room for them.")
                        .font(.subheadline).foregroundStyle(Ink.text2).padding(.horizontal, 4)
                }
                SectionEyebrow("Areas", detail: "\(model.settings.focus.count) of \(LiftSettings.focusLimit)")
                    .padding(.horizontal, 4)
                ForEach(PhysiqueRegion.allCases) { region in
                    let on = model.settings.focus.contains(region)
                    let full = !on && model.settings.focus.count >= LiftSettings.focusLimit
                    ChoiceCard(
                        title: region.label, detail: region.focusDetail, selected: on, identifier: "settings.focus\(region.rawValue.identifierSuffix)"
                    ) {
                        var s = model.settings
                        if on { s.focus.remove(region) } else if s.focus.count < LiftSettings.focusLimit { s.focus.insert(region) }
                        model.save(settings: s)
                    }
                    .disabled(full)
                    .opacity(full ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Platform.isMac ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth(620)
        }
        .background(.pageBackground)
        .formPage("Focus")
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
                detail: "Stadig Lift plans around these; they spend the same recovery.",
                style: Platform.isMac ? .none : .page(eyebrow: "Settings")
            )
            .padding(.horizontal, 16)
            .padding(.vertical, Platform.isMac ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth(620)
        }
        .background(.pageBackground)
        .formPage("Outside the gym")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !Platform.isMac {
                    SheetHeading(eyebrow: "Settings", title: "Gym", detail: "Exercises and loads are chosen from what's here.")
                }
                RowCard(title: "This gym") {
                    HStack(spacing: 12) {
                        Text("Name")
                        TextField("Name", text: $edit.value.name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Ink.text2)
                            .accessibilityIdentifier("gym.name")
                    }
                    UnitRow(
                        title: "Plates in", options: [(value: WeightUnit.kg, label: "kg"), (value: .lb, label: "lb")],
                        selection: Binding(get: { gym.unit }, set: { gym = gym.converted(to: $0) }))
                }
                .font(.callout)
                .foregroundStyle(Ink.text)
                chips("Kind", detail: "Sets the equipment below", single: true, EquipmentAccess.allCases, label: \.label, identifier: "gym.kind") {
                    gym.access == $0
                } toggle: {
                    gym = gym.switched(to: $0)
                }
                chips(
                    "Equipment", detail: "\(gym.equipment.count) of \(Equipment.allCases.count)", Equipment.allCases, label: \.label,
                    identifier: "gym.equipment"
                ) {
                    gym.equipment.contains($0)
                } toggle: {
                    if gym.equipment.contains($0) { gym.equipment.remove($0) } else { gym.equipment.insert($0) }
                }
                chips(
                    "Fixtures", note: "A rack with safeties makes barbell bench and squat safe to take to failure, for lifters who've earned it.",
                    Apparatus.allCases.filter { !$0.isRecovery }, label: \.label, identifier: "gym.fixture"
                ) {
                    gym.apparatus.contains($0)
                } toggle: {
                    if gym.apparatus.contains($0) { gym.apparatus.remove($0) } else { gym.apparatus.insert($0) }
                }
                chips(
                    "Recovery",
                    note:
                        "Sessions end with an optional sauna or steam room, outside the time you train. Read the thermometer and the minutes follow, moved by how the last one felt.",
                    Apparatus.allCases.filter(\.isRecovery), label: \.label, identifier: "gym.recovery"
                ) {
                    gym.apparatus.contains($0)
                } toggle: {
                    if gym.apparatus.contains($0) { gym.apparatus.remove($0) } else { gym.apparatus.insert($0) }
                }
                RowCard(title: "Loads") {
                    ValueRow(title: "Bar", value: "\(Format.number(gym.barWeight)) \(gym.unit.symbol)")
                    ValueRow(title: "Plates", value: gym.plates.map { Format.number($0, digits: 2) }.joined(separator: ", "))
                    Stepper(
                        "Dumbbells up to \(Format.number(gym.dumbbellMax)) \(gym.unit.symbol)", value: $edit.value.dumbbellMax,
                        in: gym.dumbbellStep...200,
                        step: gym.dumbbellStep)
                    Stepper(
                        "Dumbbell steps of \(Format.number(gym.dumbbellStep)) \(gym.unit.symbol)", value: $edit.value.dumbbellStep, in: 0.5...10,
                        step: 0.5)
                    Stepper(
                        "Stack steps of \(Format.number(gym.machineStep)) \(gym.unit.symbol)", value: $edit.value.machineStep, in: 1...20, step: 0.5)
                    // Machines that move by their own amount, set from the exercise's menu in a session.
                    ForEach(exerciseSteps) { entry in
                        HStack(spacing: 12) {
                            Text("\(entry.name) steps of \(Format.number(entry.step, digits: 2)) \(gym.unit.symbol)")
                            Spacer(minLength: 8)
                            Button("Use the gym's steps for \(entry.name)", systemImage: "xmark.circle.fill") { gym.exerciseSteps[entry.id] = nil }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(Ink.text3)
                                .accessibilityIdentifier("gym.exerciseStep.remove")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Ink.text)
                Text("A machine that goes up by its own amount, like a leg press in 20s: set it in a session, from its menu's Weight steps.")
                    .font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Platform.isMac ? 16 : 0)
            .padding(.bottom, 24)
            .readableWidth(620)
        }
        .background(.pageBackground)
        .formPage("Gym")
        .editing($edit, of: model.gym) { edited, original in model.save(gymEdits: edited, from: original) }
    }

    /// An exercise with a step of its own here.
    private struct ExerciseStep: Identifiable {
        let id: String
        let name: String
        let step: Double
    }

    /// The exercises with steps of their own here, by name: a handful at most.
    private var exerciseSteps: [ExerciseStep] {
        gym.exerciseSteps.map { ExerciseStep(id: $0.key, name: model.catalog.resolve($0.key).name, step: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A group of things the gym has, as chips two by two in a card under its eyebrow, the ones it
    /// has filled; what they're for, if anything, under them.
    private func chips<Item: Hashable>(
        _ title: String, detail: String? = nil, note: String? = nil, single: Bool = false, _ items: [Item], label: KeyPath<Item, String>,
        identifier: String, isOn: @escaping (Item) -> Bool, toggle: @escaping (Item) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title, detail: detail)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.self) { item in
                    if single {
                        ChoiceChip(title: item[keyPath: label], isOn: isOn(item), identifier: identifier) { toggle(item) }
                    } else {
                        HaveChip(title: item[keyPath: label], isOn: isOn(item), identifier: identifier) { toggle(item) }
                    }
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// Something the gym has or hasn't, as a chip: what's there on the raised grey with the accent's
/// tick, what isn't only outlined. Quieter than a filled choice, since a full gym has all of them.
private struct HaveChip: View {
    let title: String
    let isOn: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOn ? Color.accentColor : Ink.text3)
                    .accessibilityHidden(true)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Ink.text : Ink.text3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isOn ? ControlFill.track : AnyShapeStyle(Color.clear), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                if !isOn { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1.5) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
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

/// A setting with a couple of choices (kg or lb), its name at the left and the design's segmented
/// control at the right.
struct UnitRow<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            InkSegmented(options: options, selection: $selection)
                .frame(width: 132)
                .accessibilityLabel(title)
        }
    }
}
