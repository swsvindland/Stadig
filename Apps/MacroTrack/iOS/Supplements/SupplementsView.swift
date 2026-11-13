import FoodDatabase
import FoodIntelligence
import NutritionEngine
import PhotosUI
import SwiftUI
import SystemCore

/// The supplements screen as a sheet of its own.
struct SupplementsView: View {
    var body: some View {
        NavigationStack { SupplementsList(inSheet: true) }
    }
}

/// The stack: what's taken, when, and how much; adding by barcode, search or a photo of the label;
/// and the reminders.
struct SupplementsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var inSheet = false
    @State private var adding: AddSupplementView.Mode?

    var body: some View {
        Group {
            if inSheet {
                list.inkSheet {
                    SheetBar(label: "Done", identifier: "supplements.done") {
                        dismiss()
                    } trailing: {
                        addMenu
                    }
                }
            } else {
                // Pushed in Settings: the bar's back button, and the title on the page.
                list.formPage("Supplements")
                    .toolbar { ToolbarItem(placement: .barTrailing) { addMenu } }
            }
        }
        .navigationTitle("Supplements")
        .navigationDestination(item: $adding) { mode in
            AddSupplementView(mode: mode, place: .pushed)
        }
        // A supplement added: back to the list, where it now is.
        .onChange(of: model.supplements.count) { adding = nil }
    }

    private var list: some View {
        List {
            FormHeading(eyebrow: inSheet ? "Today" : "Settings", title: "Supplements")
            Group { content }.inkRows()
        }
        .inkForm()
    }

    /// Adding one, once there's a stack: with none, the ways to add are the page.
    @ViewBuilder
    private var addMenu: some View {
        if !model.supplements.isEmpty {
            if inSheet {
                // In the sheet's own bar, a round button as the close beside it is.
                addButton { CircleIcon(symbol: "plus") }.buttonStyle(.plain)
            } else {
                addButton { Image(systemName: "plus") }
            }
        }
    }

    private func addButton(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            menuItems
        } label: {
            label()
        }
        .accessibilityLabel("Add a supplement")
        .accessibilityIdentifier("supplements.add")
    }

    @ViewBuilder
    private var content: some View {
        if model.supplements.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your supplements").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                    Text(
                        "Scan a bottle's barcode and its label comes from the NIH's database of US supplement labels. Not there? Keep the camera on the Supplement Facts and it's read as you move. Then say when you take it."
                    )
                    .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                addButtons.actionRows()
            }
        } else {
            Section {
                ForEach(model.activeSupplements) { row($0) }
            } footer: {
                Text(
                    "Doses you tick off on Today add their vitamins, minerals and caffeine to your day. Skipped or unmarked doses count for nothing."
                )
            }
            let paused = model.supplements.filter(\.paused)
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { row($0) }
                } header: {
                    Text("Paused").eyebrow()
                }
            }
            RemindersSection()
        }
    }

    @ViewBuilder
    var menuItems: some View {
        Button(LiveScan.isAvailable ? "Scan the bottle" : "Type the barcode", systemImage: "barcode.viewfinder") { adding = .scan }
            .accessibilityIdentifier("supplements.menu.scan")
        Button("Search", systemImage: "magnifyingglass") { adding = .search }
            .accessibilityIdentifier("supplements.menu.search")
        Button("Choose a photo of the label", systemImage: "photo") { adding = .label }
            .accessibilityIdentifier("supplements.menu.photo")
        Button("Type it in", systemImage: "square.and.pencil") { adding = .manual }
            .accessibilityIdentifier("supplements.menu.manual")
    }

    @ViewBuilder
    var addButtons: some View {
        Button {
            adding = .scan
        } label: {
            Label(LiveScan.isAvailable ? "Scan the bottle: barcode or label" : "Type the bottle's barcode", systemImage: "barcode.viewfinder")
        }
        .accessibilityIdentifier("supplements.addScan")
        Button {
            adding = .search
        } label: {
            Label("Search by name", systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("supplements.addSearch")
        Button {
            adding = .label
        } label: {
            Label("Choose a photo of the label", systemImage: "photo")
        }
        .accessibilityIdentifier("supplements.addPhoto")
        Button {
            adding = .manual
        } label: {
            Label("Type it in", systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("supplements.addManual")
    }

    func row(_ supplement: Supplement) -> some View {
        NavigationLink {
            SupplementEditor(supplement: supplement, isNew: false, place: .pushed)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: supplement.facts.form.symbol).foregroundStyle(Ink.text2).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text([supplement.facts.brand, supplement.scheduleLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Ink.text3).lineLimit(2)
                }
            }
        }
    }
}

/// When each part of the day is, and whether to be reminded then.
struct RemindersSection: View {
    @Environment(AppModel.self) private var model
    @State private var denied = false

    var body: some View {
        let used = DoseTime.allCases.filter { time in model.activeSupplements.contains { $0.doses.contains { $0.time == time } } }
        Section {
            Toggle(
                "Remind me",
                isOn: Binding(
                    get: { model.settings.supplementReminders == true },
                    set: { on in
                        Task {
                            if on, !(await SupplementReminders.requestPermission()) {
                                denied = true
                                return
                            }
                            model.updateSettings { $0.supplementReminders = on }
                        }
                    })
            )
            .accessibilityIdentifier("supplements.reminders")
            ForEach(used) { time in
                DatePicker(
                    selection: Binding(
                        get: { Day.today.at(minutes: model.settings.minutes(time)) },
                        set: { picked in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                            model.updateSettings { s in
                                var times = s.doseTimes ?? [:]
                                times[time] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                                s.doseTimes = times
                            }
                        }), displayedComponents: .hourAndMinute
                ) {
                    Label(time.label, systemImage: time.symbol).actionRows()
                }
            }
            if Platform.isMac { Text(note).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Times").eyebrow()
        } footer: {
            // The Mac's list footers are one line: there the note is a row of the section.
            if !Platform.isMac { Text(note) }
        }
    }

    var note: String {
        denied
            ? "Notifications are off for Stadig Macro in Settings."
            : "One reminder per time of day with doses still open, with a Taken button that ticks them all off without opening the app."
    }
}

/// Finding a supplement's label: by barcode, by name, from a photo, or typed in. Ends in the
/// editor, to say when it's taken.
struct AddSupplementView: View {
    enum Mode: String, Hashable, Identifiable {
        case scan, search, label, manual
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State var mode: Mode
    /// Where the editor it ends in is shown.
    var place: SupplementEditor.Place = .pane
    @State private var found: Supplement?
    @State private var scanning = true
    @State private var manual = ""
    @State private var missing: String?
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var results: [SupplementFacts] = []
    @State private var capturing = false
    @State private var reading = false
    @State private var error: String?
    @State private var scanID = UUID()

    var body: some View {
        Group {
            switch mode {
            case .scan: scan
            case .search: search
            case .label: label
            case .manual: SupplementEditor(supplement: Supplement(facts: blank()), isNew: true, place: place)
            }
        }
        .navigationDestination(item: $found) { supplement in
            SupplementEditor(supplement: supplement, isNew: !model.supplements.contains { $0.id == supplement.id }, place: place)
        }
        // Back from the editor without adding: scan again.
        .onChange(of: found) { _, now in if now == nil { scanID = UUID() } }
        .cameraCapture(isPresented: $capturing) { photo in
            if let photo { read { await photo.prepared(maxDimension: 2000) } }
        }
    }

    func blank(barcode: String? = nil) -> SupplementFacts {
        SupplementFacts(
            id: "custom:\(UUID().uuidString)", name: "", barcode: barcode.flatMap { Barcode.keys(for: $0).first },
            servingCount: 1, unit: "capsule", ingredients: [], source: .custom)
    }

    // MARK: Scan

    @ViewBuilder
    var scan: some View {
        if let missing {
            notFound(missing)
        } else if LiveScan.isAvailable && scanning {
            LiveLabelScanner(
                kind: .supplement, lookup: lookup,
                finish: { outcome in
                    switch outcome {
                    case .supplement(let supplement): found = supplement
                    case .supplementLabel(let facts, _): found = Supplement(facts: facts)
                    case .food, .label: break
                    }
                },
                menu: {
                    // Over the camera, as the food scanner has it, beside its light.
                    Button("Type the barcode", systemImage: "keyboard") { scanning = false }
                    Button("Choose a photo of the label", systemImage: "photo") { mode = .label }
                },
                foot: { _ in EmptyView() }
            )
            .id(scanID)
            .inkGround()
        } else {
            barcode
        }
    }

    /// The bottle's barcode typed in, where there's no camera to scan it (or it's put aside).
    var barcode: some View {
        Form {
            heading("Type the barcode", detail: LiveScan.isAvailable ? nil : ScanWords.typeTheBarcode)
            Section {
                TextField("Barcode number", text: $manual)
                    .fieldKeyboard(.number)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Ink.text)
                    .onSubmit { handle(manual) }
                    .accessibilityIdentifier("supplements.barcode")
            } header: {
                Text("On the bottle").eyebrow()
            }
            .inkRows()
        }
        .inkForm()
        .addStep("Scan", place: place) {
            Button {
                handle(manual)
            } label: {
                Text("Look up").frame(maxWidth: .infinity)
            }
            .primaryAction()
            .keyboardShortcut(.defaultAction)
            .disabled(manual.count < 6)
            .accessibilityIdentifier("supplements.lookUp")
        }
    }

    /// A barcode the labels don't know: a photo of its panel, typed in, or another go.
    func notFound(_ code: String) -> some View {
        Form {
            heading(
                "Not in the label database",
                detail:
                    "\(Camera.isAvailable ? "Photograph" : "Choose a photo of") the Supplement Facts panel and it's kept with this barcode for next time."
            )
            Section {
                ValueRow(title: "Barcode", value: code)
            }
            .inkRows()
            Section {
                photoButtons
                Button("Type it in", systemImage: "square.and.pencil") { found = Supplement(facts: blank(barcode: code)) }
                    .accessibilityIdentifier("supplements.missing.type")
                Button(LiveScan.isAvailable ? "Scan again" : "Type another barcode", systemImage: "barcode.viewfinder") {
                    missing = nil
                    scanning = true
                }
                .accessibilityIdentifier("supplements.missing.again")
            } footer: {
                if let error { Text(error) }
            }
            .inkRows()
            .actionRows()
        }
        .inkForm()
        .overlay { if reading { readingNote } }
        .addStep("Scan", place: place)
    }

    func handle(_ code: String, symbology: Barcode.Symbology? = nil) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        if case .supplement(let supplement)? = lookup(digits, symbology) {
            found = supplement
        } else {
            missing = digits
            scanning = false
        }
    }

    /// A supplement in the stack, or one the NIH labels know.
    func lookup(_ digits: String, _ symbology: Barcode.Symbology?) -> LiveScanOutcome? {
        if let own = model.ownSupplement(barcode: digits, symbology: symbology) { return .supplement(own) }
        return model.supplementFacts(barcode: digits, symbology: symbology).map { .supplement(Supplement(facts: $0)) }
    }

    // MARK: Search

    var search: some View {
        List {
            heading("Search")
            Section {
                searchField
            }
            .groundRow()
            if model.supplementCatalog == nil {
                Section {
                    Text(
                        "The label database isn't in this build. \(Camera.isAvailable ? "Photograph" : "Choose a photo of") the label or type it in instead."
                    )
                    .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                }
                .inkRows()
            }
            if !results.isEmpty {
                Section {
                    ForEach(results) { facts in
                        Button {
                            found = model.supplements.first { $0.facts.id == facts.id } ?? Supplement(facts: facts)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(facts.name).font(.callout.weight(.semibold)).foregroundStyle(Ink.text).lineLimit(2)
                                Text([facts.brand, facts.servingLabel, highlights(facts)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                        .accessibilityIdentifier("supplements.result")
                    }
                } header: {
                    SectionEyebrow("Labels", detail: results.count == 1 ? "1 match" : "\(results.count) matches")
                }
                .inkRows()
            }
            if results.isEmpty, query.count >= 2 {
                Section {
                    Text("No labels match. \(Camera.isAvailable ? "Photograph" : "Choose a photo of") the Supplement Facts, or type it in.")
                        .font(.subheadline).foregroundStyle(Ink.text2)
                    Button(Camera.isAvailable ? "Photograph the label" : "Choose a photo of the label", systemImage: "doc.text.viewfinder") {
                        mode = .label
                    }
                    Button("Type it in", systemImage: "square.and.pencil") {
                        found = Supplement(
                            facts: {
                                var f = blank()
                                f.name = query
                                return f
                            }())
                    }
                }
                .inkRows()
                .actionRows()
            }
        }
        .insetGroupedList()
        .onAppear { searching = true }
        .task(id: query) {
            let query = query
            let catalog = model.supplementCatalog
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let own = model.supplements.map(\.facts).filter { $0.title.localizedCaseInsensitiveContains(query) }
            let found = await Task.detached { catalog?.search(query) ?? [] }.value
            if !Task.isCancelled { results = own + found.filter { f in !own.contains { $0.id == f.id } } }
        }
        .addStep("Search", place: place)
    }

    /// `InkSearchField`'s face, with the keyboard up as the page opens.
    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ink.text3).accessibilityHidden(true)
            TextField("Fish oil, Nature Made, magnesium…", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .accessibilityIdentifier("supplements.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .font(.callout)
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Ink.raised, in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// "300 mg caffeine, 1.1 g omega-3": caffeine first, then what it gives most of a day's need.
    func highlights(_ facts: SupplementFacts) -> String? {
        let amounts = facts.amounts
        let ranked = Micronutrients.all.filter { $0.goal == .atLeast || $0.key == "caffeine" }.compactMap { info -> (String, Double)? in
            guard let value = amounts[info.key], value > 0 else { return nil }
            let target = Micronutrients.target(info.key, sex: .unspecified, age: 35, kcal: 2000) ?? 1
            return ("\(Format.nutrient(value, info.unit)) \(Format.inSentence(info))", info.key == "caffeine" ? .infinity : value / target)
        }
        let list = ranked.sorted { $0.1 > $1.1 }.map(\.0)
        return list.isEmpty ? nil : list.prefix(2).joined(separator: ", ")
    }

    // MARK: Label

    /// With a camera, Take a photo is the one action, at the foot; a photo already taken is a row.
    @ViewBuilder
    var label: some View {
        if Camera.isAvailable {
            labelPage.addStep("Label", place: place) {
                Button {
                    capturing = true
                } label: {
                    Label("Take a photo", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .primaryAction()
                .accessibilityIdentifier("supplements.takePhoto")
            }
        } else {
            labelPage.addStep("Label", place: place)
        }
    }

    var labelPage: some View {
        Form {
            heading(
                Camera.isAvailable ? "Photograph the Supplement Facts" : "A photo of the Supplement Facts",
                detail: "Flat, in good light, with the whole panel in frame. Every line is read for you to check.")
            Section {
                choosePhoto
            } footer: {
                if let error { Text(error) }
            }
            .inkRows()
            .actionRows()
        }
        .inkForm()
        .overlay { if reading { readingNote } }
    }

    /// Every way to a photo of the panel, as rows.
    @ViewBuilder
    var photoButtons: some View {
        if Camera.isAvailable {
            Button("Take a photo", systemImage: "camera") { capturing = true }
                .accessibilityIdentifier("supplements.takePhoto")
        }
        choosePhoto
    }

    var choosePhoto: some View {
        PhotoChoices { load in
            read {
                guard let data = try await load() else { return nil }
                return await PhotoInput.prepare(data, maxDimension: 2000)
            }
        }
    }

    /// While a photo's read, over the page.
    var readingNote: some View {
        ProgressView("Reading the label…")
            .foregroundStyle(Ink.text2)
            .padding(20)
            .background(Ink.raised, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// A step's title on the page, where it's pushed in the supplements sheet; beside the list, the
    /// bar says it.
    @ViewBuilder
    func heading(_ title: String, detail: String? = nil) -> some View {
        if place != .pane { FormHeading(eyebrow: "Supplements · add", title: title, detail: detail) }
    }

    /// Reads a photo of the panel: loaded and downsampled off the main thread, then parsed.
    func read(_ photo: @escaping () async throws -> CGImage?) {
        reading = true
        error = nil
        Task {
            defer { reading = false }
            let prepared: CGImage?
            do {
                prepared = try await photo()
            } catch {
                self.error = "Couldn't load that photo. If it's in iCloud, check your connection and try again."
                return
            }
            guard let cg = prepared else {
                error = "Couldn't open that photo. Try another."
                return
            }
            do {
                let result = try await model.ai.readSupplementLabel(photo: cg)
                guard var facts = result.facts else {
                    error = "Couldn't read a Supplement Facts panel there. Try again flat and in good light, or type it in."
                    return
                }
                facts.name = result.suggestedName ?? ""
                facts.brand = result.brand
                if let missing { facts.barcode = Barcode.keys(for: missing).first }
                found = Supplement(facts: facts)
            } catch {
                self.error = MealAIMessages.text(for: error)
            }
        }
    }
}

extension View {
    /// A step of adding a supplement: pushed in the supplements sheet, the bar keeps its back button
    /// and the title is on the page (`FormHeading`); beside the list, the bar's title.
    fileprivate func addStep(_ title: String, place: SupplementEditor.Place) -> some View {
        Group {
            if place == .pane {
                navigationTitle(title).inlineTitle()
            } else {
                formPage(title)
            }
        }
    }

    /// The same, with the step's one action full width at the foot.
    fileprivate func addStep(_ title: String, place: SupplementEditor.Place, @ViewBuilder foot: () -> some View) -> some View {
        let foot = foot()
        return addStep(title, place: place).safeAreaInset(edge: .bottom, spacing: 0) { SheetFoot { foot } }
    }
}
