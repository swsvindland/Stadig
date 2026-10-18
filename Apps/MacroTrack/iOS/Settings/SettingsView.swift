import FoodDatabase
import FoodIntelligence
import HealthBridge
import NutritionEngine
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
    /// A backup being made or restored, which takes seconds with years of records.
    @State private var busy: String?
    @State private var message: String?
    @State private var editingLifeMode: LifeModePeriod?
    /// The paywall, from here: the root's sheets can't show while Settings is up.
    @State private var unlocking = false

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Show carbs and fat", isOn: setting(\.showAllMacros))
                    .accessibilityIdentifier("settings.showAllMacros")
                Picker("Lately", selection: setting(\.dietHistory)) {
                    ForEach(DietHistory.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("settings.dietHistory")
            }

            Section {
                NavigationLink {
                    SupplementsList()
                } label: {
                    LabeledContent("Supplements", value: model.activeSupplements.isEmpty ? "None" : "\(model.activeSupplements.count)")
                }
                .accessibilityIdentifier("settings.supplements")
                Toggle("Drinks and caffeine", isOn: Binding(get: { model.tracksDrinks }, set: { model.setTracksDrinks($0) }))
                    .accessibilityIdentifier("settings.drinks")
                if model.tracksDrinks {
                    let ounces = model.fluidOunces
                    let target = model.settings.waterTarget ?? model.profile.map { Hydration.target(sex: $0.sex) } ?? 2600
                    Stepper(
                        value: Binding(
                            get: { target },
                            set: { value in
                                model.updateSettings { $0.waterTarget = value }
                            }), in: 1000...6000, step: ounces ? 236.6 : 250
                    ) {
                        LabeledContent("Water a day", value: Format.volume(target, ounces: ounces))
                    }
                    .accessibilityIdentifier("settings.waterTarget")
                    if model.settings.caffeineCutBack == nil {
                        let limit = model.settings.caffeineLimit ?? Caffeine.defaultLimit
                        Stepper(
                            value: Binding(
                                get: { limit },
                                set: { value in
                                    model.updateSettings { $0.caffeineLimit = value }
                                }), in: 0...600, step: 25
                        ) {
                            LabeledContent("Caffeine limit", value: Format.mg(limit))
                        }
                        .accessibilityIdentifier("settings.caffeineLimit")
                    }
                }
            } header: {
                Text("Tracking")
            } footer: {
                Text(
                    "Drinks puts water and caffeine on Today: a glass or a coffee is one tap, and caffeine is counted against a limit, with what's still active at bedtime. Off, drinks are simply food. Water a day is what to drink; food covers the rest."
                )
            }

            Section {
                LabeledContent(
                    "On this iPhone",
                    value: model.ai.availability.onDevice
                        ? (model.ai.availability.onDeviceVision ? "Photos and descriptions" : "Descriptions") : "Not available")
                // The reload after the save reconfigures the AI engine for the new setting.
                Toggle(
                    "Use Private Cloud Compute",
                    isOn: Binding(
                        get: { model.settings.allowCloudAI },
                        set: { on in
                            model.updateSettings { $0.allowCloudAI = on }
                        })
                )
                .accessibilityIdentifier("settings.allowCloudAI")
                if let reason = model.ai.availability.reason, !model.ai.canDescribe { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Photo and description logging")
            } footer: {
                Text(
                    "Apple's on-device model is used first. Private Cloud Compute steps in for photos when this iPhone can't read them; Apple can't see or keep what's sent. The models only name foods and amounts; nutrients come from the food database."
                )
            }

            Section("Health") {
                Button("Connect Apple Health", systemImage: "heart.fill") { Task { await model.connectHealth() } }
                    .disabled(!HealthBridge.shared.isAvailable)
                    .accessibilityIdentifier("settings.connectHealth")
                Toggle("Save food and weigh-ins to Health", isOn: setting(\.saveToHealth))
                    .accessibilityIdentifier("settings.saveToHealth")
            }

            Section {
                let modes = model.lifeModes.filter { ($0.end ?? model.today) >= model.today }
                ForEach(modes) { period in
                    Button {
                        editingLifeMode = period
                    } label: {
                        LabeledContent {
                            Text(period.end.map { "until \(Format.day($0))" } ?? "ongoing")
                        } label: {
                            Label(period.kind.label, systemImage: period.kind.symbol)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("settings.lifeMode")
                }
                Menu {
                    Button("Vacation", systemImage: "airplane") {
                        editingLifeMode = LifeModePeriod(kind: .vacation, start: model.today, createdBy: .macroTrack).edited(openEnded: false)
                    }
                    .accessibilityIdentifier("settings.lifeMode.vacation")
                    Button("Ill", systemImage: "thermometer.medium") {
                        editingLifeMode = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .macroTrack)
                    }
                    .accessibilityIdentifier("settings.lifeMode.ill")
                    Button("Crunch", systemImage: "briefcase.fill") {
                        editingLifeMode = LifeModePeriod(kind: .crunch(CrunchDials()), start: model.today, createdBy: .macroTrack)
                            .edited(openEnded: false)
                    }
                    .accessibilityIdentifier("settings.lifeMode.crunch")
                } label: {
                    // The whole row opens the menu, not only its words.
                    Label("Start a life mode", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("settings.startLifeMode")
            } header: {
                Text("Life")
            } footer: {
                Text(
                    "Shared with Lift Track. Vacation and illness expect no logging and don't count against you; the first days back aren't read as fat gain. Crunch asks only for protein and maintenance calories."
                )
            }

            Section("Your data") {
                Button("Export CSV files", systemImage: "tablecells") {
                    do { exportURLs = try model.exportCSV() } catch { message = error.localizedDescription }
                }
                .accessibilityIdentifier("settings.exportCSV")
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) { Label("Share \(exportURLs.count) CSV files", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareCSV")
                }
                Button("Make a backup file", systemImage: "externaldrive") {
                    busy = "Making the backup…"
                    Task {
                        defer { busy = nil }
                        do { backupURL = try await model.backupFile() } catch { message = error.localizedDescription }
                    }
                }
                .disabled(busy != nil)
                .accessibilityIdentifier("settings.makeBackup")
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Save or share the backup", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareBackup")
                }
                Button("Restore from a backup", systemImage: "arrow.counterclockwise") { importing = true }
                    .disabled(busy != nil)
                    .accessibilityIdentifier("settings.restoreBackup")
                if let busy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(busy).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Sync", value: model.store.syncStatus)
            }

            Section {
                ForEach(model.catalog.sources, id: \.name) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(.subheadline.weight(.medium))
                        Text("\(source.foods.formatted()) foods · \(source.license)").font(.caption).foregroundStyle(.secondary)
                        Text(source.attribution).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let supplements = model.supplementCatalog {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NIH Dietary Supplement Label Database").font(.subheadline.weight(.medium))
                        Text("\(supplements.count.formatted()) supplement labels · Public domain").font(.caption).foregroundStyle(.secondary)
                        Text(supplements.attribution).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !model.catalog.hasPackagedFoods {
                    Text("Packaged foods and barcodes aren't installed in this build.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Food data")
            } footer: {
                Text(
                    "Open Food Facts data is available under the Open Database License (opendatacommons.org/licenses/odbl). USDA FoodData Central is in the public domain."
                )
            }

            if Purchases.enabled {
                Section("Macro Track") {
                    if purchases.unlocked {
                        Label("Unlocked. Thank you.", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Unlock Macro Track", systemImage: "lock.open") { unlocking = true }
                            .accessibilityIdentifier("settings.unlock")
                        Button("Restore purchase") { Task { await purchases.restore() } }
                            .accessibilityIdentifier("settings.restorePurchase")
                    }
                }
            }

            #if DEBUG
            Section("Debug") {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
                    .accessibilityIdentifier("settings.eraseEverything")
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
        .sheet(item: $editingLifeMode) { period in
            LifeModeEditor(period: period)
        }
        .sheet(isPresented: $unlocking) {
            PaywallView()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "macrobackup") ?? .json, .json]) { result in
            switch result {
            case .success(let url):
                busy = "Restoring…"
                Task {
                    defer { busy = nil }
                    do {
                        let summary = try await model.restore(from: url)
                        message = "Restored \(summary.records) records."
                    } catch {
                        // Another app's backup is refused by name ("This backup is from Mind Track").
                        message = error.localizedDescription
                    }
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Data", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func setting<T>(_ keyPath: WritableKeyPath<MacroSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.updateSettings { $0[keyPath: keyPath] = value }
            })
    }
}

/// Start, adjust or end a vacation, illness or crunch. Works as Lift Track's editor does: only an
/// illness (or injury) can be open-ended, the end shown is the end saved, and it's never before
/// the start.
struct LifeModeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var period: LifeModePeriod
    @State private var openEnded: Bool

    init(period: LifeModePeriod) {
        _period = State(initialValue: period)
        _openEnded = State(initialValue: period.end == nil && period.kind.allowsOpenEnd)
    }

    private var isNew: Bool { !model.lifeModes.contains { $0.id == period.id } }

    /// What Save writes: open-ended only where that's allowed, else with the end the picker shows.
    private var edited: LifeModePeriod { period.edited(openEnded: openEnded) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(period.kind.label, systemImage: period.kind.symbol).font(.headline)
                    DatePicker(
                        "Starts",
                        selection: Binding(
                            get: { period.start.date() },
                            set: { date in
                                // Moving the start past the end takes the end with it.
                                period.moveStart(to: Day(date))
                            }), displayedComponents: .date
                    )
                    .accessibilityIdentifier("lifeMode.start")
                    if period.kind.allowsOpenEnd {
                        Toggle("Until it's better", isOn: $openEnded)
                            .accessibilityIdentifier("lifeMode.openEnded")
                    }
                    if !openEnded {
                        DatePicker(
                            "Ends",
                            selection: Binding(
                                get: { period.editorEnd.date() },
                                set: { period.moveEnd(to: Day($0)) }),
                            in: period.start.date()..., displayedComponents: .date
                        )
                        .accessibilityIdentifier("lifeMode.end")
                    }
                }
                if !isNew {
                    Section {
                        // A period that hasn't started has nothing to end: delete it instead.
                        if period.start <= model.today {
                            Button("End today") {
                                var ended = period
                                ended.moveEnd(to: model.today)
                                if model.save(lifeMode: ended) { dismiss() }
                            }
                            .accessibilityIdentifier("lifeMode.endToday")
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(lifeMode: period.id)
                            dismiss()
                        }
                        .accessibilityIdentifier("lifeMode.delete")
                    }
                }
            }
            .navigationTitle(period.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("lifeMode.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(lifeMode: edited) { dismiss() }
                    }
                    .disabled(!edited.isValid)
                    .accessibilityIdentifier("lifeMode.save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
