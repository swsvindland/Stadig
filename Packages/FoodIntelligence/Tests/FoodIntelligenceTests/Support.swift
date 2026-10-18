import CoreGraphics
import CoreText
import Foundation
import FoodDatabase
import FoundationModels
import Synchronization
import SystemCore
import Testing
@testable import FoodIntelligence

// MARK: Vision

extension Trait where Self == ConditionTrait {
    /// For tests that run real Vision OCR. GitHub's virtual Macs have no Neural Engine, so the text
    /// recognizer can't load there; the package-tests workflow sets NO_VISION_OCR.
    static var needsVisionOCR: Self {
        .disabled(if: ProcessInfo.processInfo.environment["NO_VISION_OCR"] != nil, "Vision's text recognizer can't load without a Neural Engine")
    }
}

// MARK: Foods

func food(_ name: String = "Test", id: String? = nil, brand: String? = nil, basis: FoodBasis = .g, kcal: Double = 100,
          portions: [(String, Double)] = [], source: FoodSource = .usda) -> Food {
    Food(id: id ?? "\(source.rawValue):\(name.lowercased())", name: name, brand: brand, basis: basis,
         nutrients: Nutrients(kcal: kcal, protein: 1, carbs: 1, fat: 1), portions: portions.map { Portion(label: $0.0, amount: $0.1) },
         source: source)
}

func seen(_ name: String, brand: String = "", quantity: Double = 1, unit: String = "piece", grams: Double? = nil) -> SeenFood {
    SeenFood(name: name, brand: brand, quantity: quantity, unit: unit, grams: grams)
}

func item(_ name: String, _ quantity: Double = 1, _ unit: String = "piece", _ grams: Double? = 30, brand: String = "") -> MealReply.Item {
    MealReply.Item(brand: brand, name: name, quantity: quantity, unit: unit, grams: grams)
}

func reply(_ items: [MealReply.Item], scene: String? = nil, food: Bool? = nil) -> MealReply {
    MealReply(scene: scene, food: food, items: items)
}

func match(_ food: Food, _ score: Double, personal: Bool = false) -> FoodMatch { FoodMatch(food: food, score: score, personal: personal) }

// MARK: Catalog

/// An in-memory catalog: scripted candidates per "brand|name" (or name), else a small word-overlap ranker.
final class FakeCatalog: MealCatalog {
    let foods: [Food]
    let scripted: [String: [FoodMatch]]
    let unitTable: [String: [PortionUnit]]
    /// Every (name, brand) asked for, in order.
    let asked = Mutex<[String]>([])

    init(_ foods: [Food] = [], scripted: [String: [FoodMatch]] = [:], units: [String: [PortionUnit]] = [:]) {
        self.foods = foods
        self.scripted = scripted
        self.unitTable = units
    }

    func candidates(name: String, brand: String?, personal: [PersonalFood], limit: Int) -> [FoodMatch] {
        asked.withLock { $0.append([brand, name].compactMap { $0 }.joined(separator: " ")) }
        let key = ([brand?.lowercased()].compactMap { $0 } + [name.lowercased()]).joined(separator: "|")
        if let list = scripted[key] { return Array(list.prefix(limit)) }
        let wanted = FoodText.nameWords(name).map(FoodText.stem)
        func score(_ food: Food) -> Double {
            let have = FoodText.words(food.name).map(FoodText.stem)
            let found = wanted.filter { word in have.contains { FoodText.same($0, word) } }.count
            guard found > 0 else { return 0 }
            var score = 3 * Double(found) / Double(wanted.count) - 0.1 * Double(max(0, have.count - found))
            if let brand { score += food.brand?.lowercased() == brand.lowercased() ? 1 : -0.5 }
            return score
        }
        let own = personal.map { match($0.food, score($0.food) + $0.score, personal: true) }
        let rest = foods.map { match($0, score($0)) }
        return Array((own + rest).filter { $0.score > 0 }.sorted { $0.score > $1.score }.prefix(limit))
    }

    func units(for food: Food) -> [PortionUnit] { unitTable[food.id] ?? [] }
}

// MARK: Model

/// Answers the first request with a reply, and picks with `picks` (or fails like a busy model).
final class ScriptedModel: MealModel {
    let engine = MealEngine.onDevice
    let meal: MealReply
    let picks: (@Sendable (String) -> [Pick])?
    /// (instructions, prompt, had an image) per request.
    let requests = Mutex<[(String, String, Bool)]>([])

    init(_ meal: MealReply, picks: (@Sendable (String) -> [Pick])? = nil) {
        self.meal = meal
        self.picks = picks
    }

    func readMeal(instructions: String, prompt: String, image: CGImage?) async throws -> MealReply {
        requests.withLock { $0.append((instructions, prompt, image != nil)) }
        return meal
    }

    func pick(instructions: String, prompt: String, foods: Int) async throws -> [Pick] {
        requests.withLock { $0.append((instructions, prompt, false)) }
        guard let picks else { throw MealAIError.busy }
        return picks(prompt)
    }
}

/// A language model that answers each request with the next scripted reply (JSON for the
/// requested shape), so `FoundationMealModel` runs without Apple's models.
@available(macOS 27.0, iOS 27.0, *)
struct ScriptedLanguageModel: LanguageModel {
    /// The replies still to give and what was asked; shared by every executor the session makes.
    final class Script: Hashable, Sendable {
        let replies: Mutex<[String]>
        let prewarms = Mutex(0)
        let requests = Mutex(0)

        init(_ replies: [String]) { self.replies = Mutex(replies) }

        static func == (a: Script, b: Script) -> Bool { a === b }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    struct Executor: LanguageModelExecutor {
        let script: Script

        init(configuration: Script) throws { script = configuration }

        func prewarm(model: ScriptedLanguageModel, transcript: Transcript) { script.prewarms.withLock { $0 += 1 } }

        nonisolated(nonsending) func respond(to request: LanguageModelExecutorGenerationRequest, model: ScriptedLanguageModel,
                                             streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
            script.requests.withLock { $0 += 1 }
            let reply = script.replies.withLock { $0.isEmpty ? "{}" : $0.removeFirst() }
            await channel.send(.response(action: .appendText(reply, tokenCount: 10)))
        }
    }

    let script: Script

    init(_ script: Script) { self.script = script }

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.guidedGeneration]) }
    var executorConfiguration: Script { script }
}

/// A small solid image, for code paths that only need one.
func blankImage(width: Int = 64, height: Int = 64) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A granola bar's panel, as plain rows: each row's name, and its value at the far edge.
let sampleLabel: [(String, String?)] = [("Nutrition Facts", nil), ("Serving size 2/3 cup (55g)", nil), ("Calories", "230"),
                                        ("Total Fat 8g", "10%"), ("Sodium 160mg", "7%"), ("Total Carbohydrate 37g", "13%"),
                                        ("Protein 3g", nil), ("INGREDIENTS: OATS, HONEY, ALMONDS", nil)]

/// A plain label: each row's left text, and its right text at the far edge.
func renderLabel(_ rows: [(String, String?)], sideways: Bool) -> CGImage {
    let (width, height) = (900, 120 + rows.count * 70)
    let context = CGContext(data: nil, width: sideways ? height : width, height: sideways ? width : height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
    if sideways {
        // Turned a quarter clockwise, as a phone held the wrong way would take it.
        context.translateBy(x: 0, y: CGFloat(width))
        context.rotate(by: -.pi / 2)
    }
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 40, nil)
    func draw(_ text: String, x: CGFloat, y: CGFloat) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
    for (i, row) in rows.enumerated() {
        let y = CGFloat(height - 90 - i * 70)
        draw(row.0, x: 40, y: y)
        if let right = row.1 { draw(right, x: CGFloat(width - 160), y: y) }
    }
    return context.makeImage()!
}
