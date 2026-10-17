import CoreGraphics
import Foundation
import FoundationModels

/// Sessions created and prewarmed ahead of a request, by instructions. Each is used once:
/// a session keeps its transcript, and every meal starts fresh.
@available(iOS 27.0, macOS 27.0, *)
actor SessionPool {
    private var warm: [String: LanguageModelSession] = [:]

    func take(_ instructions: String) -> LanguageModelSession? { warm.removeValue(forKey: instructions) }

    /// Loads the model and caches the instructions, so the next request starts generating sooner.
    func prewarm(_ instructions: String, model: any LanguageModel) {
        guard warm[instructions] == nil else { return }
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
        warm[instructions] = session
    }
}

/// One of Apple's models answering the meal requests with guided generation.
@available(iOS 27.0, macOS 27.0, *)
struct FoundationMealModel: MealModel {
    let engine: MealEngine
    let model: any LanguageModel
    let pool: SessionPool

    /// Photos can be 48 MP; the models only need a modest, upright image.
    static let imageSide = 1280
    /// Twelve foods take about 350 tokens; the cap only stops a looping reply early.
    static let mealTokens = 512

    func readMeal(instructions: String, prompt: String, image: CGImage?) async throws -> MealReply {
        try await attempt {
            let (session, warm) = await session(instructions)
            let start = ContinuousClock.now
            guard let image else {
                let reply = try await session.respond(to: prompt, generating: MealOutput.self, options: options(Self.mealTokens),
                                                      contextOptions: context())
                trace("read", session, warm: warm, since: start)
                return MealReply(scene: nil, food: nil, items: reply.content.items.map(\.item))
            }
            guard model.capabilities.contains(.vision) else {
                throw MealAIError.unavailable("This model can't read photos. Describe the meal instead.")
            }
            let picture = ImageScaling.fit(image, maxSide: Self.imageSide)
            // A photo's reply needs the schema in its prompt: without it, the model runs on
            // describing the scene and never closes the reply.
            let reply = try await session.respond(generating: MealPhotoOutput.self, options: options(Self.mealTokens),
                                                  contextOptions: context(schema: true)) {
                Attachment(picture)
                prompt
            }
            trace("read photo", session, warm: warm, since: start)
            return MealReply(scene: reply.content.scene, food: reply.content.food, items: reply.content.items.map(\.item))
        }
    }

    func pick(instructions: String, prompt: String, foods: Int) async throws -> [Pick] {
        try await attempt {
            let (session, warm) = await session(instructions)
            let start = ContinuousClock.now
            let reply = try await session.respond(to: prompt, generating: PicksOutput.self, options: options(16 + foods * 4),
                                                  contextOptions: context())
            trace("pick", session, warm: warm, since: start)
            return reply.content.entries.enumerated().map { Pick(food: $0.offset + 1, entry: $0.element) }
        }
    }

    /// A prewarmed session for these instructions when one is ready, else a new one.
    private func session(_ instructions: String) async -> (LanguageModelSession, warm: Bool) {
        if let session = await pool.take(instructions) { return (session, true) }
        return (LanguageModelSession(model: model, instructions: instructions), false)
    }

    private func trace(_ request: String, _ session: LanguageModelSession, warm: Bool, since start: ContinuousClock.Instant) {
        Trace.note {
            let usage = session.usage
            return "\(engine) \(request) \(warm ? "warm" : "cold"): \(ContinuousClock.now - start), tokens in \(usage.input.totalTokenCount) "
                + "(cached \(usage.input.cachedTokenCount)) out \(usage.output.totalTokenCount)"
        }
    }

    /// A product name from a label's text and, when the parse was thin, the values printed on it.
    func readLabel(lines: [String], values: Bool) async throws -> LabelGuess {
        try await attempt {
            let instructions = values ? Prompts.labelInstructions + "\n" + Prompts.labelValueInstructions : Prompts.labelInstructions
            let session = LanguageModelSession(model: model, instructions: instructions)
            let prompt = Prompts.label(lines: lines)
            if values {
                let reply = try await session.respond(to: prompt, generating: LabelOutput.self, options: options(300), contextOptions: context(schema: true))
                return LabelGuess(reply.content)
            }
            let reply = try await session.respond(to: prompt, generating: LabelNameOutput.self, options: options(60), contextOptions: context(schema: true))
            return LabelGuess(name: reply.content.name, brand: reply.content.brand)
        }
    }

    /// A supplement's name and brand from its label's text.
    func readSupplementName(lines: [String]) async throws -> LabelGuess {
        try await attempt {
            let session = LanguageModelSession(model: model, instructions: Prompts.supplementLabelInstructions)
            let reply = try await session.respond(to: Prompts.label(lines: lines), generating: LabelNameOutput.self, options: options(60),
                                                  contextOptions: context(schema: true))
            return LabelGuess(name: reply.content.name, brand: reply.content.brand)
        }
    }

    /// The Nutrition Facts values and the product's name from the text a live scan gathered.
    func checkLabel(text: String) async throws -> LabelGuess {
        try await attempt {
            let (session, warm) = await session(Prompts.liveLabelInstructions)
            let start = ContinuousClock.now
            let reply = try await session.respond(to: text, generating: LabelOutput.self, options: options(300),
                                                  contextOptions: context(schema: true))
            trace("check label", session, warm: warm, since: start)
            return LabelGuess(reply.content)
        }
    }

    /// A supplement's name, serving and nutrient lines from the text a live scan gathered.
    func checkSupplement(text: String) async throws -> SupplementReply {
        try await attempt {
            let (session, warm) = await session(Prompts.liveSupplementInstructions)
            let start = ContinuousClock.now
            let reply = try await session.respond(to: text, generating: SupplementPanelOutput.self, options: options(800),
                                                  contextOptions: context(schema: true))
            trace("check supplement", session, warm: warm, since: start)
            let output = reply.content
            return SupplementReply(name: output.name, brand: output.brand, servingSize: output.servingSize,
                                   lines: output.lines.map { SupplementReply.Line(name: $0.name, amount: $0.amount, unit: $0.unit) })
        }
    }

    /// Loads the model with a live check's instructions ahead of the first check.
    func prewarmCheck(supplement: Bool) async {
        await pool.prewarm(supplement ? Prompts.liveSupplementInstructions : Prompts.liveLabelInstructions, model: model)
    }

    // MARK: Requests

    /// Greedy decoding keeps the same photo producing the same draft; the token cap keeps a
    /// looping reply short.
    private func options(_ tokens: Int) -> GenerationOptions {
        // Reasoning, where the model has it, spends from the same budget.
        let budget = model.capabilities.contains(.reasoning) ? tokens + 512 : tokens
        return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: max(64, min(budget, 2048)))
    }

    /// The least reasoning a reasoning model allows: these are lookups, and speed matters. The meal
    /// and pick instructions describe their reply's fields, so a description's and a near-tie's
    /// schema stay out of the prompt (about a second saved each).
    private func context(schema: Bool = false) -> ContextOptions {
        ContextOptions(includeSchemaInPrompt: schema, reasoningLevel: model.capabilities.contains(.reasoning) ? .light : nil)
    }

    /// Runs a request, retrying a busy model twice; failures come out as `MealAIError`.
    private func attempt<T>(_ request: () async throws -> T) async throws -> T {
        var retries = 0
        while true {
            do {
                return try await request()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let reason = ModelErrors.classify(error)
                guard reason == .busy, retries < 2 else { throw reason }
                retries += 1
                try await Task.sleep(for: .milliseconds(retries == 1 ? 400 : 1000))
            }
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
extension LabelGuess {
    init(_ output: LabelOutput) {
        self.init(name: output.name, brand: output.brand, servingSize: output.servingSize, servingGrams: output.servingGrams,
                  values: [.kcal: output.calories, .fat: output.fat, .saturatedFat: output.saturatedFat, .carbs: output.carbs,
                           .fiber: output.fiber, .sugar: output.sugar, .protein: output.protein, .sodium: output.sodium]
                      .compactMapValues { $0 })
    }
}
