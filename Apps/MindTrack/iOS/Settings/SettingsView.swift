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
    /// A backup being made or restored: the JSON takes a while for years of sessions.
    @State private var working: String?
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
                        .accessibilityIdentifier("settings.course.\(domain.rawValue)")
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
                    .accessibilityIdentifier("settings.daysPerWeek")
                    Picker("Session length", selection: Binding(get: { settings.schedule.minutes }, set: { minutes in
                        var s = settings
                        s.schedule.minutes = minutes
                        model.save(settings: s)
                    })) {
                        ForEach(StudySchedule.sessionOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .accessibilityIdentifier("settings.sessionLength")
                    Toggle("Give lagging subjects more days", isOn: Binding(get: { settings.autoPrioritise }, set: { on in
                        var s = settings
                        s.autoPrioritise = on
                        model.save(settings: s)
                    }))
                    .accessibilityIdentifier("settings.autoPrioritise")
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
                    // The id too: two periods of one kind (an illness now, another booked) are two rows.
                    .accessibilityIdentifier("settings.lifeMode.\(period.kind.identifier).\(period.id)")
                }
                // No end yet: the editor offers the one every app's editor does (a week, or open for an
                // illness) and saves what it shows.
                Menu {
                    Button("Vacation", systemImage: "airplane") {
                        editingLifeMode = LifeModePeriod(kind: .vacation, start: model.today, createdBy: .knowledge)
                    }
                    .accessibilityIdentifier("settings.startVacation")
                    Button("Ill", systemImage: "thermometer.medium") {
                        editingLifeMode = LifeModePeriod(kind: .illness(.systemic), start: model.today, createdBy: .knowledge)
                    }
                    .accessibilityIdentifier("settings.startIllness")
                    Button("Crunch", systemImage: "briefcase.fill") {
                        editingLifeMode = LifeModePeriod(kind: .crunch(CrunchDials()), start: model.today, createdBy: .knowledge)
                    }
                    .accessibilityIdentifier("settings.startCrunch")
                } label: {
                    // The whole row opens it, not just the words.
                    Label("Start a life mode", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("settings.startLifeMode")
            } header: {
                Text("Life")
            } footer: {
                Text("Shared with Lift Track and Macro Track. Vacation, illness and crunch pause Mind Track: nothing is expected and the days never count against you.")
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
                    working = "Making the backup…"
                    Task {
                        defer { working = nil }
                        do { backupURL = try await model.backupFile() } catch { message = error.localizedDescription }
                    }
                }
                .disabled(working != nil)
                .accessibilityIdentifier("settings.makeBackup")
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Save or share the backup", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareBackup")
                }
                Button("Restore from a backup", systemImage: "arrow.counterclockwise") { importing = true }
                    .disabled(working != nil)
                    .accessibilityIdentifier("settings.restore")
                if let working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(working).foregroundStyle(.secondary)
                    }
                }
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
                            .accessibilityIdentifier("settings.unlock")
                        Button("Restore purchase") { Task { await purchases.restore() } }
                            .accessibilityIdentifier("settings.restorePurchase")
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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(exportedAs: "dev.svindland.stadig.mind-backup"), .json]) { result in
            switch result {
            case .success(let url):
                working = "Restoring…"
                Task {
                    defer { working = nil }
                    do {
                        let summary = try await model.restore(from: url)
                        message = "Restored \(summary.records) records."
                    } catch {
                        message = error.localizedDescription
                    }
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
            .accessibilityIdentifier("settings.privateCloud")
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

/// Start, adjust or end a vacation, illness or crunch. Works as Lift Track's editor does, with
/// SystemCore's editing rules: only an illness (or injury) can be open-ended, one without an end
/// yet is offered a week, the end shown is the end saved, and it's never before the start.
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

    private var edited: LifeModePeriod { period.edited(openEnded: openEnded) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(period.kind.label, systemImage: period.kind.symbol).font(.headline)
                    DatePicker(
                        "Starts", selection: Binding(get: { period.start.date() }, set: { period.moveStart(to: Day($0)) }),
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("lifeMode.start")
                    if period.kind.allowsOpenEnd {
                        Toggle("Until it's better", isOn: $openEnded)
                            .accessibilityIdentifier("lifeMode.openEnded")
                    }
                    if !(openEnded && period.kind.allowsOpenEnd) {
                        DatePicker(
                            "Ends", selection: Binding(get: { period.editorEnd.date() }, set: { period.moveEnd(to: Day($0)) }),
                            in: period.start.date()..., displayedComponents: .date
                        )
                        .accessibilityIdentifier("lifeMode.end")
                    }
                }
                if !isNew {
                    Section {
                        if let ended = Self.endedToday(edited, today: model.today) {
                            Button("End today") {
                                model.save(lifeMode: ended)
                                dismiss()
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("lifeMode.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(lifeMode: edited)
                        dismiss()
                    }
                    .disabled(!edited.isValid)
                    .accessibilityIdentifier("lifeMode.save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// What End today writes, or nil for a period that hasn't started: it has nothing to end (delete
    /// it instead), and ending it today would put the end before the start.
    static func endedToday(_ period: LifeModePeriod, today: Day) -> LifeModePeriod? {
        guard period.start <= today else { return nil }
        var ended = period
        ended.end = today
        return ended
    }
}

extension LifeModeKind {
    /// For accessibility identifiers: one word per kind.
    var identifier: String {
        switch self {
        case .vacation: "vacation"
        case .crunch: "crunch"
        case .injury: "injury"
        case .illness: "illness"
        }
    }
}
