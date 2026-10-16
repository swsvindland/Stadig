import SwiftUI
import UniformTypeIdentifiers
import FoodDatabase
import FoodIntelligence
import HealthBridge
import NutritionEngine
import SystemCore
import SystemStore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var exportURLs: [URL] = []
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var editingLifeMode: LifeModePeriod?

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Show carbs and fat", isOn: setting(\.showAllMacros))
                Picker("Lately", selection: setting(\.dietHistory)) {
                    ForEach(DietHistory.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                NavigationLink {
                    SupplementsList()
                } label: {
                    LabeledContent("Supplements", value: model.activeSupplements.isEmpty ? "None" : "\(model.activeSupplements.count)")
                }
                Toggle("Drinks and caffeine", isOn: Binding(get: { model.tracksDrinks }, set: { model.setTracksDrinks($0) }))
                if model.tracksDrinks {
                    let ounces = model.fluidOunces
                    let target = model.settings.waterTarget ?? model.profile.map { Hydration.target(sex: $0.sex) } ?? 2600
                    Stepper(value: Binding(get: { target }, set: { value in
                        var s = model.settings
                        s.waterTarget = value
                        model.save(settings: s)
                    }), in: 1000...6000, step: ounces ? 236.6 : 250) {
                        LabeledContent("Water a day", value: Format.volume(target, ounces: ounces))
                    }
                    if model.settings.caffeineCutBack == nil {
                        let limit = model.settings.caffeineLimit ?? Caffeine.defaultLimit
                        Stepper(value: Binding(get: { limit }, set: { value in
                            var s = model.settings
                            s.caffeineLimit = value
                            model.save(settings: s)
                        }), in: 0...600, step: 25) {
                            LabeledContent("Caffeine limit", value: Format.mg(limit))
                        }
                    }
                }
            } header: {
                Text("Tracking")
            } footer: {
                Text("Drinks puts water and caffeine on Today: a glass or a coffee is one tap, and caffeine is counted against a limit, with what's still active at bedtime. Off, drinks are simply food. Water a day is what to drink; food covers the rest.")
            }

            Section {
                LabeledContent("On this iPhone", value: model.ai.availability.onDevice
                    ? (model.ai.availability.onDeviceVision ? "Photos and descriptions" : "Descriptions") : "Not available")
                Toggle("Use Private Cloud Compute", isOn: Binding(get: { model.settings.allowCloudAI }, set: { on in
                    var s = model.settings
                    s.allowCloudAI = on
                    model.save(settings: s)
                    model.ai.configure(catalog: model.catalog, allowCloud: on)
                }))
                if let reason = model.ai.availability.reason, !model.ai.canDescribe { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Photo and description logging")
            } footer: {
                Text("Apple's on-device model is used first. Private Cloud Compute steps in for photos when this iPhone can't read them; Apple can't see or keep what's sent. The models only name foods and amounts; nutrients come from the food database.")
            }

            Section("Health") {
                Button("Connect Apple Health", systemImage: "heart.fill") { Task { await model.connectHealth() } }
                    .disabled(!HealthBridge.shared.isAvailable)
                Toggle("Save food and weigh-ins to Health", isOn: setting(\.saveToHealth))
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
                }
                Menu {
                    Button("Vacation", systemImage: "airplane") {
                        editingLifeMode = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .macroTrack)
                    }
                    Button("Ill", systemImage: "thermometer.medium") {
                        editingLifeMode = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .macroTrack)
                    }
                    Button("Crunch", systemImage: "briefcase.fill") {
                        editingLifeMode = LifeModePeriod(kind: .crunch(CrunchDials()), start: model.today, end: model.today.adding(days: 6), createdBy: .macroTrack)
                    }
                } label: {
                    Label("Start a life mode", systemImage: "plus")
                }
            } header: {
                Text("Life")
            } footer: {
                Text("Shared with Lift Track. Vacation and illness expect no logging and don't count against you; the first days back aren't read as fat gain. Crunch asks only for protein and maintenance calories.")
            }

            Section("Your data") {
                Button("Export CSV files", systemImage: "tablecells") {
                    do { exportURLs = try model.exportCSV() } catch { message = error.localizedDescription }
                }
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) { Label("Share \(exportURLs.count) CSV files", systemImage: "square.and.arrow.up") }
                }
                Button("Make a backup file", systemImage: "externaldrive") {
                    do { backupURL = try model.backupFile() } catch { message = error.localizedDescription }
                }
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Save or share the backup", systemImage: "square.and.arrow.up") }
                }
                Button("Restore from a backup", systemImage: "arrow.counterclockwise") { importing = true }
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
                Text("Open Food Facts data is available under the Open Database License (opendatacommons.org/licenses/odbl). USDA FoodData Central is in the public domain.")
            }

            if Purchases.enabled {
                Section("Macro Track") {
                    if purchases.unlocked {
                        Label("Unlocked. Thank you.", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Unlock Macro Track", systemImage: "lock.open") { model.showPaywall = true }
                        Button("Restore purchase") { Task { await purchases.restore() } }
                    }
                }
            }

            #if DEBUG
            Section("Debug") {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $editingLifeMode) { period in
            LifeModeEditor(period: period)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "macrobackup") ?? .json, .json]) { result in
            switch result {
            case .success(let url):
                do {
                    let summary = try model.restore(from: url)
                    message = "Restored \(summary.records) records."
                } catch {
                    message = error.localizedDescription
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
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var s = model.settings
            s[keyPath: keyPath] = value
            model.save(settings: s)
        })
    }
}

/// Start, adjust or end a vacation, illness or crunch.
struct LifeModeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var period: LifeModePeriod
    @State private var hasEnd = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(period.kind.label, systemImage: period.kind.symbol).font(.headline)
                    DatePicker("Starts", selection: Binding(get: { period.start.date() }, set: { period.start = Day($0) }), displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: Binding(get: { (period.end ?? period.start).date() }, set: { period.end = Day($0) }),
                                   in: period.start.date()..., displayedComponents: .date)
                    }
                }
                if model.lifeModes.contains(where: { $0.id == period.id }) {
                    Section {
                        Button("End today") {
                            period.end = model.today
                            model.save(lifeMode: period)
                            dismiss()
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(lifeMode: period.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(period.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasEnd { period.end = nil }
                        model.save(lifeMode: period)
                        dismiss()
                    }
                }
            }
            .onAppear { hasEnd = period.end != nil }
        }
        .presentationDetents([.medium])
    }
}
