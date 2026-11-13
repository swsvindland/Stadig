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
    let session: LoggerSession
    @State private var showCamera = false
    @State private var image: CGImage?
    @State private var note = ""

    var body: some View {
        Group {
            if session.review != nil {
                MealReviewView(session: session)
            } else if session.reading {
                AnalyzingView(
                    image: image, engine: model.ai.availability.onDeviceVision ? "on your \(Platform.deviceName)" : "with Private Cloud Compute")
            } else {
                chooser
            }
        }
        .cameraCapture(isPresented: $showCamera) { photo in
            if let photo { analyze { await photo.prepared(maxDimension: 1280) } }
        }
        // A photo dropped on the window, or on this screen, is read like one chosen.
        .dropDestination(for: DroppedImage.self, isEnabled: session.review == nil && !session.reading && model.ai.canSeePhotos) { images, _ in
            guard let data = images.first?.data else { return }
            analyze { await PhotoInput.prepare(data, maxDimension: 1280) }
        }
        .onAppear {
            if !readDroppedPhoto(), useCamera, image == nil { openCamera() }
        }
        // Asked again while this is showing, when nothing appears.
        .onChange(of: model.loggerRequest) { _, request in
            if !readDroppedPhoto(), request.mode == .camera { openCamera() }
        }
        #if DEBUG
        .task {
            // -photo meal.jpg reads a picture from the app's Documents the way the photo library's are,
            // since a simulator can't be made to pick one.
            if let name = LaunchOptions.current.value(after: "-photo"), session.review == nil, image == nil, model.ai.canSeePhotos {
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
                    Button("Search instead") { session.backToSearch() }
                }
                .inkRows()
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
                .inkRows()
                Section {
                    TextField("Optional: \"large\", \"no dressing\", \"half eaten\"", text: $note)
                } header: {
                    SectionEyebrow("Anything the photo can't show?")
                }
                .inkRows()
            }
            if let problem = session.readProblem {
                Section { Text(problem).foregroundStyle(Ink.text2) }.inkRows()
            }
        }
        .inkForm()
        .contentMargins(.top, 4, for: .scrollContent)
    }

    /// Reads a photo dropped on the window, if there is one: once, and in place of a review, as it
    /// does on any other way of logging. Not over a read under way, which would race it.
    func readDroppedPhoto() -> Bool {
        guard let dropped = model.takeDroppedPhoto(), model.ai.canSeePhotos, !session.reading else { return false }
        session.review = nil
        analyze { await PhotoInput.prepare(dropped, maxDimension: 1280) }
        return true
    }

    func openCamera() {
        guard Camera.isAvailable, session.review == nil, !session.reading, model.ai.canSeePhotos else { return }
        showCamera = true
    }

    /// Reads a photo: loaded and downsampled off the main thread, then named by the model.
    func analyze(_ photo: @escaping () async throws -> CGImage?) {
        image = nil
        session.startRead(.photo, model) {
            let prepared: CGImage?
            do {
                prepared = try await photo()
            } catch {
                return .nothing("Couldn't load that photo. If it's in iCloud, check your connection and try again.")
            }
            guard let cg = prepared else { return .nothing("Couldn't open that photo. Try another.") }
            image = cg
            do {
                let result = try await model.ai.recognize(photo: cg, note: note.isEmpty ? nil : note, personal: model.personal)
                if !result.isFood || result.items.isEmpty {
                    return .nothing(result.scene.map { "That looks like \($0), not food." } ?? "Couldn't see any food in that photo.")
                }
                return .foods(result)
            } catch {
                return .nothing(MealAIMessages.text(for: error))
            }
        }
    }
}

/// "Two eggs, toast with butter and a flat white": typed or dictated, then confirmed.
struct DescribeLogView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if session.review != nil {
                MealReviewView(session: session)
            } else if session.reading {
                AnalyzingView(image: nil, engine: model.ai.availability.onDevice ? "on your \(Platform.deviceName)" : "with Private Cloud Compute")
            } else {
                Form {
                    if !model.ai.canDescribe {
                        Section {
                            Label(
                                model.ai.availability.reason ?? "Describing meals isn't available on this \(Platform.deviceName).",
                                systemImage: "exclamationmark.triangle")
                            Button("Search instead") { session.backToSearch() }
                        }
                        .inkRows()
                    }
                    Section {
                        TextField("Two eggs, toast with butter and a flat white", text: $text, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(Ink.text)
                            .lineLimit(3...8)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(analyze)
                            .accessibilityIdentifier("describe.text")
                    } footer: {
                        Text(
                            "Type or dictate with the keyboard's microphone. Brands and amounts help: \"a Big Mac and medium fries\", \"a plate of spaghetti bolognese\"."
                        )
                    }
                    .inkRows()
                    if let problem = session.readProblem {
                        Section { Text(problem).foregroundStyle(Ink.text2) }.inkRows()
                    }
                }
                .inkForm()
                .contentMargins(.top, 4, for: .scrollContent)
                .safeAreaInset(edge: .bottom) {
                    Button(action: analyze) {
                        Text("Find foods").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction().controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.pageBackground.ignoresSafeArea(edges: .horizontal))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ai.canDescribe)
                    .accessibilityIdentifier("describe.find")
                }
                .onAppear {
                    // Words typed on Today that matched no food: read straight away.
                    if let typed = model.takeLoggerText() {
                        text = typed
                        analyze()
                    } else {
                        focused = true
                    }
                }
            }
        }
    }

    func analyze() {
        let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        session.startRead(.description, model) {
            do {
                let result = try await model.ai.recognize(description: description, personal: model.personal)
                return result.items.isEmpty ? .nothing("Couldn't find foods in that. Try naming each one.") : .foods(result)
            } catch {
                return .nothing(MealAIMessages.text(for: error))
            }
        }
    }
}

struct AnalyzingView: View {
    let image: CGImage?
    let engine: String

    /// The photo being read, and under it the row its foods will take the place of, as Today's
    /// thread shows words being worked out.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 220)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
            }
            HStack(spacing: 12) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.text2)
                    .symbolEffect(.pulse)
                    .frame(width: 40, height: 40)
                    .background(Ink.surface, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(image == nil ? "Working out your words" : "Working out your plate").font(.body.weight(.medium)).foregroundStyle(Ink.text)
                    Text("Looking \(engine)…").font(.caption).foregroundStyle(Ink.text3)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// What the model saw, matched to real foods: check, fix with a tap, log. The review is the
/// logger's, so going off to search for one of its foods comes back to it as it was.
struct MealReviewView: View {
    @Environment(AppModel.self) private var model
    let session: LoggerSession

    var items: Binding<[MealReview.Item]> { Binding(get: { session.review?.items ?? [] }, set: { session.review?.items = $0 }) }

    var body: some View {
        let chosen = session.review?.chosen ?? []
        let total = Nutrients.sum(chosen.map(\.nutrients))
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // As the foods will land on Today's thread: under where they came from, with their total.
                SectionEyebrow(session.review?.source == .photo ? "From your photo" : "From your words", detail: Format.kcal(total.kcal))
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                if let scene = session.review?.guess.scene, !scene.isEmpty {
                    Text(scene).font(.subheadline).foregroundStyle(Ink.text2).padding(.horizontal, 4).padding(.bottom, 4)
                }
                ForEach(items) { $item in
                    ReviewRow(item: $item, session: session)
                }
                if let guess = session.review?.guess {
                    Text(
                        "\(guess.engine == .onDevice ? "On device" : "Private Cloud Compute") · \(Format.number(guess.seconds)) s. Amounts marked ≈ are estimates; nutrients always come from the food database."
                    )
                    .font(.caption).foregroundStyle(Ink.text3)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                session.logReview(model)
            } label: {
                Text(chosen.isEmpty ? "Nothing to log" : "Log \(chosen.count) \(chosen.count == 1 ? "food" : "foods") · \(Format.kcal(total.kcal))")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction().controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.pageBackground.ignoresSafeArea(edges: .horizontal))
            .disabled(chosen.isEmpty)
            .accessibilityIdentifier("review.log")
        }
    }
}

private struct ReviewRow: View {
    @Environment(AppModel.self) private var model
    @Binding var item: MealReview.Item
    let session: LoggerSession

    /// A row of Today's thread: the food's marker, its name and amount (± a step, or a tap to
    /// type one), its calories over the macro it's most of, and the foods it might be instead.
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                item.included.toggle()
            } label: {
                Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.included ? Color.accentColor : Ink.text3)
                    .frame(width: 28, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .disabled(item.food == nil)
            .accessibilityLabel(item.included ? "Included" : "Left out")
            .accessibilityIdentifier("review.include")

            if let food = item.food {
                FoodTile(name: food.name, size: 40, fill: Ink.surface)
                VStack(alignment: .leading, spacing: 4) {
                    Text(FoodLabel.short(food.name)).font(.body.weight(.medium)).foregroundStyle(Ink.text).lineLimit(2)
                    HStack(spacing: 6) {
                        nudge("minus", label: "Less") { item.count = max(range.lowerBound, item.count - step) }
                        // A tap types the amount, for one the steps are a long way from.
                        Button("\(item.seen.approximate ? "≈ " : "")\(item.amount)") {
                            guard let unit = item.unit else { return }
                            session.portion = AmountRequest(purpose: .pick(item: item.id, count: item.count, unit: unit), food: food)
                        }
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Ink.text2)
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .accessibilityHint("Type an amount")
                        .accessibilityIdentifier("review.amount")
                        nudge("plus", label: "More") { item.count = min(range.upperBound, item.count + step) }
                    }
                    if food.name.lowercased() != item.seen.seenName.lowercased() {
                        Text("Saw “\(item.seen.seenName)”").font(.caption).foregroundStyle(Ink.text3).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                let lead = ThreadRow.lead(item.nutrients)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.whole(item.nutrients.kcal)).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text)
                    if let lead {
                        Text("\(Format.whole(lead.grams)) \(lead.letter)").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(
                            lead.color)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Ink.ok)
                    .frame(width: 40, height: 40)
                    .background(Ink.surface, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.seen.seenName).font(.body.weight(.medium)).foregroundStyle(Ink.text)
                    Text("No good match in the food database").font(.caption).foregroundStyle(Ink.text3)
                }
                Spacer(minLength: 4)
            }
            Menu {
                ForEach(item.seen.alternatives.filter { $0.food.id != item.food?.id }) { alt in
                    Button(alt.food.title) { session.swap(item.id, to: alt.food, model) }
                }
                Divider()
                Button("Search for “\(item.seen.seenName)”", systemImage: "magnifyingglass") { session.find(item.seen.seenName, for: item.id) }
            } label: {
                Image(systemName: "arrow.left.arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2)
                    .frame(width: 36, height: 36).background(Ink.raised, in: .circle).frame(width: 40, height: 44).contentShape(.rect)
            }
            .accessibilityLabel("Change food")
            .accessibilityIdentifier("review.change")
        }
        .padding(.vertical, 4)
        .opacity(item.included || item.food == nil ? 1 : 0.55)
    }

    func nudge(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(Ink.text)
                .frame(width: 26, height: 26).background(Ink.raised, in: .circle)
                .frame(width: 32, height: 32).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .hoverHighlight()
        .accessibilityLabel(label)
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
}
