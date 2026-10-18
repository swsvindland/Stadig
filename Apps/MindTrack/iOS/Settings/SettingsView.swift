import SwiftUI
import UniformTypeIdentifiers
import MindEngine
import SystemAI
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
            if let settings = model.settings {
                Section {
                    ForEach(Domain.allCases) { domain in
                        Picker(selection: Binding(get: { settings.mode(domain) }, set: { mode in
                            var s = settings
                            s.courses[domain] = mode
                            if !s.focus.isEmpty { model.save(settings: s) }
                        })) {
                            Text("Focus").tag(CourseMode?.some(.focus))
                            Text("Maintenance").tag(CourseMode?.some(.maintenance))
                            Text("Off").tag(CourseMode?.none)
                        } label: {
                            Label(domain.label, systemImage: domain.symbol)
                        }
                    }
                    if let warning = CourseLoad.check(settings).warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.footnote).symbolRenderingMode(.multicolor)
                    }
                } header: {
                    Text("Courses")
                } footer: {
                    Text("Focus courses get full sessions; Maintenance is a few minutes of reviews in each warm-up. Turning one off keeps everything learned; its reviews simply wait until it's back.")
                }
                Section {
                    Stepper(value: Binding(get: { settings.schedule.daysPerWeek }, set: { days in
                        var s = settings
                        s.schedule = StudySchedule(daysPerWeek: days, minutes: s.schedule.minutes)
                        model.save(settings: s)
                    }), in: 1...7) {
                        LabeledContent("Days a week", value: "\(settings.schedule.daysPerWeek)")
                    }
                    Picker("Session length", selection: Binding(get: { settings.schedule.minutes }, set: { minutes in
                        var s = settings
                        s.schedule.minutes = minutes
                        model.save(settings: s)
                    })) {
                        ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Give lagging subjects more days", isOn: Binding(get: { settings.autoPrioritise }, set: { on in
                        var s = settings
                        s.autoPrioritise = on
                        model.save(settings: s)
                    }))
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("A subject that stalls or slips at a check-in gets an extra day in the split until it moves again.")
                }
                if !settings.languages.isEmpty { LanguageSettings(settings: settings) }
                if settings.has(.maths) { MathsSettings(settings: settings) }
                if settings.has(.writing) { WritingSettings(settings: settings) }
                if settings.has(.reading) { ReadingSettings(settings: settings, dismiss: { dismiss() }) }
                AISettings(settings: settings)
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
                        editingLifeMode = LifeModePeriod(kind: .vacation, start: model.today, end: model.today.adding(days: 6), createdBy: .knowledge)
                    }
                    Button("Ill", systemImage: "thermometer.medium") {
                        editingLifeMode = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .knowledge)
                    }
                    Button("Crunch", systemImage: "briefcase.fill") {
                        editingLifeMode = LifeModePeriod(kind: .crunch(CrunchDials()), start: model.today, end: model.today.adding(days: 6), createdBy: .knowledge)
                    }
                } label: {
                    Label("Start a life mode", systemImage: "plus")
                }
            } header: {
                Text("Life")
            } footer: {
                Text("Shared with Lift Track and Macro Track. Vacation, illness and crunch pause Mind Track: nothing is expected and the days never count against you.")
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
                ForEach(Language.allCases, id: \.self) { language in
                    if let deck = model.catalogs.deck(language) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(language.domain.label) words and sentences").font(.subheadline.weight(.medium))
                            Text("\(deck.words.count.formatted()) words").font(.caption).foregroundStyle(.secondary)
                            Text(deck.attribution).font(.caption2).foregroundStyle(.secondary)
                        }
                    } else if settings(language) {
                        Text("The \(language.domain.label) catalog isn't installed in this build.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maths, writing and the reading ladder").font(.subheadline.weight(.medium))
                    Text("\(MathCurriculum.topics.count) maths topics, \(WritingBank.standard.items.count) writing items and \(ReadingLadder.standard.books.count) books, written for Mind Track.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Each catalog's licence is listed with it.")
            }
            if Purchases.enabled {
                Section {
                    if purchases.unlocked {
                        Label("Unlocked. Thank you.", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Unlock Mind Track", systemImage: "lock.open") { model.showPaywall = true }
                        Button("Restore purchase") { Task { await purchases.restore() } }
                    }
                }
            }
            #if DEBUG
            Section("Debug") {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
            }
            #endif
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(exportedAs: "dev.svindland.stadig.mind-backup"), .json]) { result in
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
        .sheet(item: $editingLifeMode) { LifeModeEditor(period: $0) }
    }

    func settings(_ language: Language) -> Bool { model.settings?.has(language.domain) ?? false }
}

/// Private Cloud Compute for heavier jobs. Everything core works without any AI at all.
struct AISettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section {
            Toggle("Use Private Cloud Compute", isOn: Binding(get: { settings.allowCloudAI }, set: { on in
                var s = settings
                s.allowCloudAI = on
                model.save(settings: s)
            }))
            let state = SystemAI.availability(allowCloud: settings.allowCloudAI)
            LabeledContent("Status", value: state.privateCloud ? "On device and Private Cloud Compute" : state.onDevice ? "On device" : "Unavailable")
            if let reason = state.reason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Notes on your writing and reading books from a cover photo use Apple's on-device model. Longer jobs can go to Private Cloud Compute, which Apple can't read or keep. With neither, everything else works the same.")
        }
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
