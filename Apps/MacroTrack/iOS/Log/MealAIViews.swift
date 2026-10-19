import FoodDatabase
import FoodIntelligence
import NutritionEngine
import PhotosUI
import SwiftUI
import SystemCore

/// What the person reads when the model can't help.
enum MealAIMessages {
    static func text(for error: Error) -> String {
        guard let error = error as? MealAIError else { return error.localizedDescription }
        switch error {
        case .unavailable(let reason): return reason
        case .notFood(let scene): return scene.isEmpty ? "That doesn't look like food." : "That looks like \(scene), not food."
        case .busy: return "The model is busy. Try again in a moment."
        case .refused: return "Apple's model declined that one. Try describing it, or search."
        case .tooLong: return "That's a lot at once. Try one meal at a time."
        case .quotaReached(let until):
            return until.map { "Private Cloud Compute's limit is reached until \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "Private Cloud Compute's limit is reached for now."
        case .network: return "Private Cloud Compute needs a connection. On-device logging still works for descriptions."
        case .failed(let reason): return reason
        }
    }
}

/// A photo of a meal: take it, pick it, choose a file or drop it on the window, then confirm what
/// was seen.
struct PhotoLogView: View {
    @Environment(AppModel.self) private var model
    let useCamera: Bool
    @Binding var mode: LogMode
    @Binding var query: String
    let close: () -> Void
    @State private var showCamera = false
    @State private var image: CGImage?
    @State private var note = ""
    @State private var guess: MealGuess?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Group {
            if let guess {
                MealReviewView(
                    guess: guess, source: .photo,
                    search: { text in
                        query = text
                        mode = .search
                    }, close: close)
            } else if working {
                AnalyzingView(
                    image: image, engine: model.ai.availability.onDeviceVision ? "on your \(Platform.deviceName)" : "with Private Cloud Compute")
            } else {
                chooser
            }
        }
        .navigationTitle("Photo")
        .cameraCapture(isPresented: $showCamera) { photo in
            if let photo { analyze { await photo.prepared(maxDimension: 1280) } }
        }
        // A photo dropped on the window, or on this screen, is read like one chosen.
        .dropDestination(for: DroppedImage.self, isEnabled: guess == nil && !working && model.ai.canSeePhotos) { images, _ in
            guard let data = images.first?.data else { return }
            analyze { await PhotoInput.prepare(data, maxDimension: 1280) }
        }
        .onAppear {
            if let dropped = model.takeDroppedPhoto(), guess == nil, model.ai.canSeePhotos {
                analyze { await PhotoInput.prepare(dropped, maxDimension: 1280) }
            } else if useCamera, Camera.isAvailable, guess == nil, image == nil, model.ai.canSeePhotos {
                showCamera = true
            }
        }
        #if DEBUG
        .task {
            // -photo meal.jpg reads a picture from the app's Documents the way the photo library's are,
            // since a simulator can't be made to pick one.
            if let name = LaunchOptions.current.value(after: "-photo"), guess == nil, image == nil, model.ai.canSeePhotos {
                let url = URL.documentsDirectory.appending(path: name)
                analyze { await PhotoInput.prepare(try Data(contentsOf: url), maxDimension: 1280) }
            }
        }
        #endif
    }

    var chooser: some View {
        Form {
            if !model.ai.canSeePhotos {
                Section {
                    Label(
                        model.ai.availability.reason ?? "Photo logging isn't available on this \(Platform.deviceName).",
                        systemImage: "exclamationmark.triangle")
                    Button("Search instead") { mode = .search }
                }
            } else {
                Section {
                    if Camera.isAvailable {
                        Button("Take a photo", systemImage: "camera") { showCamera = true }
                            .accessibilityIdentifier("photo.take")
                    }
                    PhotoChoices { load in
                        analyze {
                            guard let data = try await load() else { return nil }
                            return await PhotoInput.prepare(data, maxDimension: 1280)
                        }
                    }
                } footer: {
                    Text(
                        "\(Platform.isPhoneOrPad ? "" : "Or drop a photo on the window. ")\(MealAIAvailability.privateCloudEntitled ? "Read on your \(Platform.deviceName), or with Private Cloud Compute when allowed in Settings." : "Read on your \(Platform.deviceName).") Photos aren't kept."
                    )
                }
                Section("Anything the photo can't show?") {
                    TextField("Optional: \"large\", \"no dressing\", \"half eaten\"", text: $note)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.secondary) }
            }
        }
    }

    /// Reads a photo: loaded and downsampled off the main thread, then named by the model.
    func analyze(_ photo: @escaping () async throws -> CGImage?) {
        working = true
        error = nil
        image = nil
        Task {
            defer { working = false }
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
            image = cg
            do {
                let result = try await model.ai.recognize(photo: cg, note: note.isEmpty ? nil : note, personal: model.personal)
                if !result.isFood || result.items.isEmpty {
                    error = result.scene.map { "That looks like \($0), not food." } ?? "Couldn't see any food in that photo."
                } else {
                    guess = result
                }
            } catch {
                self.error = MealAIMessages.text(for: error)
            }
        }
    }
}

/// "Two eggs, toast with butter and a flat white": typed or dictated, then confirmed.
struct DescribeLogView: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: LogMode
    @Binding var query: String
    let close: () -> Void
    @State private var text = ""
    @State private var guess: MealGuess?
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let guess {
                MealReviewView(
                    guess: guess, source: .description,
                    search: { text in
                        query = text
                        mode = .search
                    }, close: close)
            } else if working {
                AnalyzingView(image: nil, engine: model.ai.availability.onDevice ? "on your \(Platform.deviceName)" : "with Private Cloud Compute")
            } else {
                Form {
                    if !model.ai.canDescribe {
                        Section {
                            Label(
                                model.ai.availability.reason ?? "Describing meals isn't available on this \(Platform.deviceName).",
                                systemImage: "exclamationmark.triangle")
                            Button("Search instead") { mode = .search }
                        }
                    }
                    Section {
                        TextField("Two eggs, toast with butter and a flat white", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(analyze)
                    } footer: {
                        Text(
                            "Type or dictate with the keyboard's microphone. Brands and amounts help: \"a Big Mac and medium fries\", \"a plate of spaghetti bolognese\"."
                        )
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.secondary) }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: analyze) {
                        Text("Find foods").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .primaryAction()
                    .padding()
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ai.canDescribe)
                }
                .onAppear { focused = true }
            }
        }
        .navigationTitle("Describe")
    }

    func analyze() {
        let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let result = try await model.ai.recognize(description: description, personal: model.personal)
                if result.items.isEmpty {
                    error = "Couldn't find foods in that. Try naming each one."
                } else {
                    guess = result
                }
            } catch {
                self.error = MealAIMessages.text(for: error)
            }
        }
    }
}

struct AnalyzingView: View {
    let image: CGImage?
    let engine: String

    var body: some View {
        VStack(spacing: 18) {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill().frame(width: 180, height: 180).clipShape(.rect(cornerRadius: 24))
            }
            ProgressView()
            Text("Looking \(engine)…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What the model saw, matched to real foods: check, fix with a tap, log.
struct MealReviewView: View {
    @Environment(AppModel.self) private var model
    let guess: MealGuess
    let source: EntrySource
    let search: (String) -> Void
    let close: () -> Void
    @State private var items: [ReviewItem] = []

    struct ReviewItem: Identifiable {
        var id: UUID
        var seen: GuessedItem
        var food: Food?
        var unit: PortionUnit?
        var count: Double
        var included: Bool

        var nutrients: Nutrients {
            if let food, let unit { return FoodUnits.nutrients(food, count: count, unit: unit) }
            return seen.nutrients.scaled(seen.count > 0 ? count / seen.count : 1)
        }

        var amount: String { unit.map { FoodUnits.label(count: count, unit: $0) } ?? Format.number(count) }
    }

    var body: some View {
        let chosen = items.filter { $0.included && $0.food != nil }
        let total = Nutrients.sum(chosen.map(\.nutrients))
        List {
            if let scene = guess.scene, !scene.isEmpty {
                Section { Text(scene).font(.subheadline).foregroundStyle(.secondary) }
            }
            Section {
                ForEach($items) { $item in
                    ReviewRow(item: $item, search: search)
                }
            } footer: {
                Text(
                    "\(guess.engine == .onDevice ? "On device" : "Private Cloud Compute") · \(Format.number(guess.seconds)) s. Amounts marked ≈ are estimates; nutrients always come from the food database."
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let entries = chosen.compactMap { item -> FoodEntry? in
                    guard let food = item.food, let unit = item.unit else { return nil }
                    return model.entry(
                        for: food, count: item.count, unit: unit, source: source,
                        confidence: item.seen.sure && !item.seen.approximate ? 0.8 : 0.5)
                }
                model.log(entries)
                close()
            } label: {
                Text(chosen.isEmpty ? "Nothing to log" : "Log \(chosen.count) \(chosen.count == 1 ? "food" : "foods") · \(Format.kcal(total.kcal))")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .primaryAction()
            .padding()
            .disabled(chosen.isEmpty)
        }
        .onAppear {
            guard items.isEmpty else { return }
            items = guess.items.map { g in
                ReviewItem(id: g.id, seen: g, food: g.match?.food, unit: g.unit, count: g.count, included: g.match != nil)
            }
        }
    }
}

private struct ReviewRow: View {
    @Binding var item: MealReviewView.ReviewItem
    let search: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                item.included.toggle()
            } label: {
                Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.included ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(item.food == nil)
            .accessibilityLabel(item.included ? "Included" : "Left out")

            VStack(alignment: .leading, spacing: 6) {
                if let food = item.food {
                    Text(food.name).font(.body).lineLimit(2)
                    if food.name.lowercased() != item.seen.seenName.lowercased() {
                        Text("Saw “\(item.seen.seenName)”").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Stepper(value: Binding(get: { item.count }, set: { item.count = max(range.lowerBound, $0) }), in: range, step: step) {
                            Text("\(item.seen.approximate ? "≈ " : "")\(item.amount)").font(.subheadline.monospacedDigit())
                        }
                    }
                    Text("\(Format.kcal(item.nutrients.kcal)) · \(Format.macros(item.nutrients))").font(.caption.monospacedDigit()).foregroundStyle(
                        .secondary)
                } else {
                    Text(item.seen.seenName).font(.body)
                    Text("No good match in the food database").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(item.seen.alternatives.filter { $0.food.id != item.food?.id }) { alt in
                    Button(alt.food.title) { swap(to: alt.food) }
                }
                Divider()
                Button("Search for “\(item.seen.seenName)”", systemImage: "magnifyingglass") { search(item.seen.seenName) }
            } label: {
                Image(systemName: "arrow.left.arrow.right.circle").font(.title3)
            }
            .accessibilityLabel("Change food")
        }
        .opacity(item.included || item.food == nil ? 1 : 0.55)
    }

    /// What ± adds: 10 g, ml or kcal (an estimate is often 350 g), else a quarter, a half or a
    /// whole one of the unit as the count grows.
    var step: Double {
        if let unit = item.unit, FoodUnits.step(for: unit) >= 10 { return FoodUnits.step(for: unit) }
        return item.count < 2 ? 0.25 : item.count < 10 ? 0.5 : 1
    }

    /// From one step up to well past the estimate, so the amount is always inside it.
    var range: ClosedRange<Double> {
        let byTens = item.unit.map { FoodUnits.step(for: $0) >= 10 } ?? false
        return byTens ? step...max(5000, item.count * 4) : 0.25...max(50, item.count * 2)
    }

    func swap(to food: Food) {
        let units = FoodUnits.units(for: food)
        if let current = item.unit, let same = units.first(where: { $0.id == current.id }) {
            item.unit = same
        } else {
            let suggestion = FoodUnits.suggested(for: food)
            item.unit = suggestion.unit
            item.count = suggestion.count
        }
        item.food = food
        item.included = true
    }
}
