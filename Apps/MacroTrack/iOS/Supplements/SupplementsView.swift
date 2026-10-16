import SwiftUI
import PhotosUI
import FoodDatabase
import FoodIntelligence
import NutritionEngine
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
        List {
            if model.supplements.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your supplements").font(.headline)
                        Text("Scan a bottle's barcode and its label comes from the NIH's database of US supplement labels. Not there? Keep the camera on the Supplement Facts and it's read as you move. Then say when you take it.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    addButtons
                }
            } else {
                Section {
                    ForEach(model.activeSupplements) { row($0) }
                } footer: {
                    Text("Doses you tick off on Today add their vitamins, minerals and caffeine to your day. Skipped or unmarked doses count for nothing.")
                }
                let paused = model.supplements.filter(\.paused)
                if !paused.isEmpty {
                    Section("Paused") { ForEach(paused) { row($0) } }
                }
                RemindersSection()
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            if !model.supplements.isEmpty {
                ToolbarItem(placement: inSheet ? .topBarLeading : .topBarTrailing) {
                    Menu {
                        menuItems
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a supplement")
                }
            }
        }
        .navigationDestination(item: $adding) { mode in
            AddSupplementView(mode: mode)
        }
        // A supplement added: back to the list, where it now is.
        .onChange(of: model.supplements.count) { adding = nil }
    }

    @ViewBuilder
    var menuItems: some View {
        Button("Scan the bottle", systemImage: "barcode.viewfinder") { adding = .scan }
        Button("Search", systemImage: "magnifyingglass") { adding = .search }
        Button("Choose a photo of the label", systemImage: "photo") { adding = .label }
        Button("Type it in", systemImage: "square.and.pencil") { adding = .manual }
    }

    @ViewBuilder
    var addButtons: some View {
        Button { adding = .scan } label: { Label("Scan the bottle: barcode or label", systemImage: "barcode.viewfinder") }
        Button { adding = .search } label: { Label("Search by name", systemImage: "magnifyingglass") }
        Button { adding = .label } label: { Label("Choose a photo of the label", systemImage: "photo") }
        Button { adding = .manual } label: { Label("Type it in", systemImage: "square.and.pencil") }
    }

    func row(_ supplement: Supplement) -> some View {
        NavigationLink {
            SupplementEditor(supplement: supplement, isNew: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: supplement.facts.form.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name).font(.body).lineLimit(1)
                    Text([supplement.facts.brand, supplement.scheduleLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

/// When each part of the day is, and whether to be reminded then.
private struct RemindersSection: View {
    @Environment(AppModel.self) private var model
    @State private var denied = false

    var body: some View {
        let used = DoseTime.allCases.filter { time in model.activeSupplements.contains { $0.doses.contains { $0.time == time } } }
        Section {
            Toggle("Remind me", isOn: Binding(get: { model.settings.supplementReminders == true }, set: { on in
                Task {
                    if on, !(await SupplementReminders.requestPermission()) {
                        denied = true
                        return
                    }
                    var s = model.settings
                    s.supplementReminders = on
                    model.save(settings: s)
                }
            }))
            ForEach(used) { time in
                DatePicker(selection: Binding(get: { date(model.settings.minutes(time)) }, set: { picked in
                    var s = model.settings
                    var times = s.doseTimes ?? [:]
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                    times[time] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    s.doseTimes = times
                    model.save(settings: s)
                }), displayedComponents: .hourAndMinute) {
                    Label(time.label, systemImage: time.symbol)
                }
            }
        } header: {
            Text("Times")
        } footer: {
            Text(denied ? "Notifications are off for Macro Track in Settings."
                 : "One reminder per time of day with doses still open, with a Taken button that ticks them all off without opening the app.")
        }
    }

    func date(_ minutes: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes) * 60)
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
    @State private var found: Supplement?
    @State private var scanning = true
    @State private var manual = ""
    @State private var missing: String?
    @State private var query = ""
    @State private var searching = false
    @State private var results: [SupplementFacts] = []
    @State private var capturing = false
    @State private var picked: PhotosPickerItem?
    @State private var reading = false
    @State private var error: String?
    @State private var scanID = UUID()

    var body: some View {
        Group {
            switch mode {
            case .scan: scan
            case .search: search
            case .label: label
            case .manual: SupplementEditor(supplement: Supplement(facts: blank()), isNew: true)
            }
        }
        .navigationDestination(item: $found) { supplement in
            SupplementEditor(supplement: supplement, isNew: !model.supplements.contains { $0.id == supplement.id })
        }
        // Back from the editor without adding: scan again.
        .onChange(of: found) { _, now in if now == nil { scanID = UUID() } }
        .fullScreenCover(isPresented: $capturing) {
            CameraPicker { image in
                capturing = false
                if let image { read(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { read(image) }
                picked = nil
            }
        }
    }

    func blank(barcode: String? = nil) -> SupplementFacts {
        SupplementFacts(id: "custom:\(UUID().uuidString)", name: "", barcode: barcode.flatMap { Barcode.keys(for: $0).first },
                        servingCount: 1, unit: "capsule", ingredients: [], source: .custom)
    }

    // MARK: Scan

    @ViewBuilder
    var scan: some View {
        if let missing {
            ContentUnavailableView {
                Label("Not in the label database", systemImage: "barcode")
            } description: {
                Text("Photograph the Supplement Facts panel and it's kept with this barcode for next time.")
            } actions: {
                photoButtons
                Button("Type it in") { found = Supplement(facts: blank(barcode: missing)) }
                Button("Scan again") {
                    self.missing = nil
                    scanning = true
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            .overlay { if reading { ProgressView("Reading the label…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        } else if LiveLabelScanner.isAvailable && scanning {
            LiveLabelScanner(kind: .supplement, lookup: lookup) { outcome in
                switch outcome {
                case .supplement(let supplement): found = supplement
                case .supplementLabel(let facts, _): found = Supplement(facts: facts)
                case .food, .label: break
                }
            }
            .id(scanID)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Type the barcode", systemImage: "keyboard") { scanning = false }
                        Button("Choose a photo of the label", systemImage: "photo") { mode = .label }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Other ways")
                }
            }
        } else {
            Form {
                Section {
                    TextField("Barcode number", text: $manual)
                        .keyboardType(.numberPad)
                        .font(.title3.monospacedDigit())
                        .onSubmit { handle(manual) }
                    Button("Look up") { handle(manual) }.disabled(manual.count < 6)
                } footer: {
                    if !LiveCamera.isAvailable { Text("The camera scanner isn't available here, so type the digits under the barcode.") }
                }
            }
            .navigationTitle("Scan")
        }
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
            ForEach(results) { facts in
                Button {
                    found = model.supplements.first { $0.facts.id == facts.id } ?? Supplement(facts: facts)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(facts.name).font(.body).lineLimit(2)
                        Text([facts.brand, facts.servingLabel, highlights(facts)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
            }
            if results.isEmpty, query.count >= 2 {
                Section {
                    Text("No labels match. Photograph the Supplement Facts, or type it in.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Photograph the label") { mode = .label }
                    Button("Type it in") { found = Supplement(facts: { var f = blank(); f.name = query; return f }()) }
                }
            }
        }
        .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Fish oil, Nature Made, magnesium…")
        .onAppear { searching = true }
        .task(id: query) {
            let query = query, catalog = model.supplementCatalog
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let own = model.supplements.map(\.facts).filter { $0.title.localizedCaseInsensitiveContains(query) }
            let found = await Task.detached { catalog?.search(query) ?? [] }.value
            if !Task.isCancelled { results = own + found.filter { f in !own.contains { $0.id == f.id } } }
        }
        .navigationTitle("Search supplements")
        .overlay {
            if model.supplementCatalog == nil {
                ContentUnavailableView("The label database isn't in this build", systemImage: "externaldrive.badge.xmark",
                                       description: Text("Photograph the label or type it in instead."))
            }
        }
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

    var label: some View {
        ContentUnavailableView {
            Label("Photograph the Supplement Facts", systemImage: "doc.text.viewfinder")
        } description: {
            Text("Flat, in good light, with the whole panel in frame. Every line is read for you to check.")
        } actions: {
            photoButtons
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
        .overlay { if reading { ProgressView("Reading the label…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .navigationTitle("Label")
    }

    @ViewBuilder
    var photoButtons: some View {
        if CameraPicker.isAvailable {
            Button("Take a photo") { capturing = true }.primaryAction()
        }
        PhotosPicker(selection: $picked, matching: .images) { Text("Choose a photo") }
    }

    func read(_ image: UIImage) {
        guard let cg = image.prepared(maxDimension: 2000) else { return }
        reading = true
        error = nil
        Task {
            defer { reading = false }
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
