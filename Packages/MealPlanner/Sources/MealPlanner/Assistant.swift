import Foundation
import FoundationModels
import SystemCore

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@Generable(description: "What a person wants changed in next week's meal plan")
struct PlanRequestOutput {
    @Guide(
        description: "Foods, ingredients or flavours to leave out, one or two words each, e.g. fish, chicken, spicy, dairy. Empty if none.",
        .maximumCount(8))
    var avoid: [String]
    @Guide(
        description: "Foods, ingredients or flavours wanted, one or two words each, e.g. salmon, Mexican, curry, egg muffins. Empty if none.",
        .maximumCount(8))
    var want: [String]
    @Guide(description: "vegetarian, vegan, pescatarian or everything if the request changes the diet, otherwise empty")
    var diet: String
    @Guide(description: "true if they want it cheaper")
    var cheaper: Bool
    @Guide(description: "true if they want less cooking time")
    var quicker: Bool
}

/// Reads a request for next week's plan. Apple's on-device model (or Private Cloud Compute when
/// allowed and entitled) tidies messy wording into short phrases; the word rules map those to the
/// library. Without a model, the word rules read the request directly.
public struct PlanAssistant: Sendable {
    public init() {}

    /// Which model reads a request: the device's when it can answer; Private Cloud Compute only when
    /// the setting allows it and the app has Apple's entitlement, since without it a request would
    /// stop the app (`PrivateCloud`); otherwise none, and the word rules read it alone.
    enum Reader: Equatable { case device, cloud, words }

    static func reader(deviceAvailable: Bool, allowCloud: Bool, entitled: Bool = PrivateCloud.isEntitled) -> Reader {
        if deviceAvailable { return .device }
        return allowCloud && entitled ? .cloud : .words
    }

    static let instructions = """
        You turn a request about a weekly meal-prep plan into lists. The plan is built from chicken, turkey, beef, pork, \
        salmon, cod, shrimp, tofu, lentils, chickpeas, rice, quinoa, pasta, potatoes, sweet potatoes, vegetables, and \
        teriyaki, Tex-Mex, Mediterranean, curry, Italian and peanut-lime flavours, with overnight oats, egg muffins or \
        yogurt for breakfast. Put what they don't want in avoid and what they want more of in want. Keep each entry to \
        one or two words. Leave lists empty when nothing fits.
        """

    public func read(_ request: String, allowCloud: Bool) async -> PlanChange {
        let words = PlanRequests.read(request)
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return words }
        let model: (any LanguageModel)?
        switch Self.reader(deviceAvailable: SystemLanguageModel.default.availability == .available, allowCloud: allowCloud) {
        case .device:
            model = SystemLanguageModel.default
        case .cloud:
            let cloud = PrivateCloudComputeLanguageModel()
            model = cloud.isAvailable && !cloud.quotaUsage.isLimitReached ? cloud : nil
        case .words:
            model = nil
        }
        guard let model else { return words }
        do {
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            let reply = try await session.respond(
                to: request, generating: PlanRequestOutput.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200))
            let output = reply.content
            let change = PlanRequests.read(
                avoid: output.avoid, want: output.want, diet: output.diet, cheaper: output.cheaper,
                quicker: output.quicker)
            return Self.merge(change, words: words)
        } catch {
            return words
        }
    }

    /// The model's reading with the word rules' added: the model can miss a word the rules caught,
    /// never the other way round on purpose. Nothing stays wanted that the merged avoid list or diet
    /// rules out, so "no fish" can't also read as "more cod".
    static func merge(_ model: PlanChange, words: PlanChange) -> PlanChange {
        var change = model
        change.avoid.formUnion(words.avoid)
        change.diet = change.diet ?? words.diet
        change.want = PlanRequests.remaining(change.want.union(words.want), avoiding: change.avoid, diet: change.diet)
        change.cheaper = change.cheaper ?? words.cheaper
        change.quicker = change.quicker ?? words.quicker
        return change.isEmpty ? words : change
    }
}
