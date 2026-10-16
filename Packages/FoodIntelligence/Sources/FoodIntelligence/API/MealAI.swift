import CoreGraphics
import Foundation
import FoodDatabase
import FoundationModels
import SystemCore

/// Logs a meal from a photo, a typed or dictated description, or a nutrition label, with Apple's
/// models only: the on-device model first, Private Cloud Compute when allowed and the device
/// model can't (unavailable, or no vision for photos). The model names foods and amounts; the
/// catalog supplies every nutrient.
///
/// Call `prewarm()` when logging becomes likely (the app comes to the front, the log sheet opens);
/// it loads the model and caches the instructions at most every ten minutes.
@available(iOS 27.0, macOS 27.0, *)
public actor MealAI {
    private let catalog: any MealCatalog
    private let allowCloud: Bool
    /// Tests pin one engine, with no fallback; nil chooses by availability.
    private let pinned: MealEngine?
    private let devicePool = SessionPool()
    private let cloudPool = SessionPool()
    private var cloudModel: PrivateCloudComputeLanguageModel?
    private var warmedAt: ContinuousClock.Instant?

    static let prewarmInterval = Duration.seconds(600)

    public init(catalog: some MealCatalog, allowCloud: Bool) {
        self.init(catalog: catalog, allowCloud: allowCloud, pinned: nil)
    }

    init(catalog: some MealCatalog, allowCloud: Bool, pinned: MealEngine?) {
        self.catalog = catalog
        self.allowCloud = allowCloud || pinned == .privateCloud
        self.pinned = pinned
    }

    public static func availability(allowCloud: Bool) -> MealAIAvailability {
        MealEngines.availability(allowCloud: allowCloud)
    }

    /// Prepares the sessions the next photo and description would use, cheaply and at most every
    /// ten minutes.
    public func prewarm() {
        let now = ContinuousClock.now
        if let warmedAt, now - warmedAt < Self.prewarmInterval { return }
        warmedAt = now
        // One session per engine: a model caches only its most recently prewarmed instructions, so
        // photos and descriptions share theirs, and the near-tie request isn't prewarmed at all.
        let state = state()
        for engine in Set([true, false].compactMap { MealEngines.engine(photo: $0, in: state) }) { warm(model(engine)) }
    }

    /// A meal photo, with the person's note if they typed or said one ("ate 3 slices"). Returns
    /// `isFood == false` with the scene when the photo shows no food.
    public func recognize(photo: CGImage, note: String?, personal: [PersonalFood]) async throws -> MealGuess {
        let start = ContinuousClock.now
        let note = FoodText.clean(note ?? "", limit: 500)
        let state = state()
        guard let engine = MealEngines.engine(photo: true, in: state) else {
            // No model can see here, but a note can still be read on its own.
            if !note.isEmpty, let engine = MealEngines.engine(photo: false, in: state) {
                return try await run(description: note, image: nil, engine: engine, personal: personal, state: state, start: start)
            }
            throw MealAIError.unavailable(state.reason ?? "Photo recognition isn't available right now.")
        }
        do {
            return try await run(description: note, image: photo, engine: engine, personal: personal, state: state, start: start)
        } catch let error as MealAIError {
            guard pinned == nil,
                  let next = MealEngines.fallback(after: error, from: engine, photo: true, hasNote: !note.isEmpty, in: state) else { throw error }
            return try await run(description: note, image: next.photo ? photo : nil, engine: next.engine, personal: personal, state: state,
                                 start: start)
        }
    }

    /// "two eggs, toast with butter and a flat white". Throws `notFood` when it names no food.
    public func recognize(description: String, personal: [PersonalFood]) async throws -> MealGuess {
        let start = ContinuousClock.now
        let said = FoodText.clean(description, limit: 2000)
        guard !said.isEmpty else { throw MealAIError.notFood("Describe what you ate.") }
        let state = state()
        guard let engine = MealEngines.engine(photo: false, in: state) else {
            throw MealAIError.unavailable(state.reason ?? "Meal recognition isn't available right now.")
        }
        do {
            return try await run(description: said, image: nil, engine: engine, personal: personal, state: state, start: start)
        } catch let error as MealAIError {
            guard pinned == nil, let next = MealEngines.fallback(after: error, from: engine, photo: false, hasNote: true, in: state) else {
                throw error
            }
            return try await run(description: said, image: nil, engine: next.engine, personal: personal, state: state, start: start)
        }
    }

    /// A nutrition label photo → a custom food's values. Vision reads the panel's text boxes and
    /// FoodDatabase's parser reads the values; the model only suggests a name, and fills gaps in a
    /// thin parse with values printed in the text.
    public func readLabel(photo: CGImage) async throws -> LabelResult {
        let boxes = try await LabelOCR.recognize(photo)
        let lines = LabelOCR.rows(boxes)
        // Positions read two-column panels; the lines are the fallback for anything else.
        return try await nameLabel(reading: NutritionLabel.parse(boxes: LabelOCR.level(boxes)) ?? NutritionLabel.parse(lines: lines),
                                   lines: lines)
    }

    /// A panel already read (live, from many frames) → its name and brand from all the text seen,
    /// the package's front included, and gaps in a thin read filled with values printed there.
    public func nameLabel(reading: LabelReading?, lines: [String]) async throws -> LabelResult {
        var reading = reading
        guard !lines.isEmpty, let engine = MealEngines.engine(photo: false, in: state()) else {
            return LabelResult(reading: reading, lines: lines, suggestedName: nil, brand: nil)
        }
        let thin = LabelAssist.isThin(reading)
        let guess: LabelGuess?
        do {
            guess = try await model(engine).readLabel(lines: lines, values: thin)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The parse stands on its own; the name is typed instead.
            guess = nil
        }
        if thin, let guess { reading = LabelAssist.fill(reading, with: guess, lines: lines) }
        return LabelResult(reading: reading, lines: lines, suggestedName: guess?.name, brand: guess?.brand)
    }

    /// A Supplement Facts photo → its serving and lines. Vision reads the text and FoodDatabase's
    /// parser reads the panel; the model only suggests the product's name and brand.
    public func readSupplementLabel(photo: CGImage) async throws -> SupplementLabelResult {
        let lines = LabelOCR.rows(try await LabelOCR.recognize(photo))
        return try await nameSupplement(facts: SupplementLabel.parse(lines: lines), lines: lines)
    }

    /// A Supplement Facts panel already read (live) → the product's name and brand from all the
    /// text seen.
    public func nameSupplement(facts: SupplementFacts?, lines: [String]) async throws -> SupplementLabelResult {
        guard !lines.isEmpty, let engine = MealEngines.engine(photo: false, in: state()) else {
            return SupplementLabelResult(facts: facts, lines: lines, suggestedName: nil, brand: nil)
        }
        let guess: LabelGuess?
        do {
            guess = try await model(engine).readSupplementName(lines: lines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The panel stands on its own; the name is typed instead.
            guess = nil
        }
        return SupplementLabelResult(facts: facts, lines: lines, suggestedName: guess?.name, brand: guess?.brand)
    }

    // MARK: Running

    private func run(description: String, image: CGImage?, engine: MealEngine, personal: [PersonalFood], state: MealAIAvailability,
                     start: ContinuousClock.Instant) async throws -> MealGuess {
        let reader = model(engine)
        // Near-ties are settled on the device when it can: text only, quick, and no cloud quota.
        let picker = state.onDevice && pinned != .privateCloud ? model(.onDevice) : reader
        let draft = try await MealAnalysis.run(description: description, image: image, personal: personal, reader: reader,
                                               picker: picker, catalog: catalog)
        // The next meal starts as warm as this one did.
        if warmedAt != nil { warm(reader) }
        if image == nil && draft.items.isEmpty {
            throw MealAIError.notFood("No food or drink found in “\(FoodText.clean(description, limit: 60))”. Try naming what you ate.")
        }
        let elapsed = ContinuousClock.now - start
        return MealGuess(scene: draft.scene, isFood: draft.isFood, items: draft.items, engine: engine,
                         seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    private func state() -> MealAIAvailability {
        var state = MealEngines.availability(allowCloud: allowCloud)
        switch pinned {
        case .onDevice?:
            state.privateCloud = false
            state.privateCloudVision = false
        case .privateCloud?:
            state.onDevice = false
            state.onDeviceVision = false
        case nil:
            break
        }
        return state
    }

    private func model(_ engine: MealEngine) -> FoundationMealModel {
        switch engine {
        case .onDevice:
            return FoundationMealModel(engine: .onDevice, model: SystemLanguageModel.default, pool: devicePool)
        case .privateCloud:
            let cloud = cloudModel ?? PrivateCloudComputeLanguageModel()
            cloudModel = cloud
            return FoundationMealModel(engine: .privateCloud, model: cloud, pool: cloudPool)
        }
    }

    private func warm(_ model: FoundationMealModel) {
        Task { await model.pool.prewarm(Prompts.mealInstructions, model: model.model) }
    }
}
