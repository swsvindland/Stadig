import Foundation
import FoundationModels
import SystemCore

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@Generable(description: "What a person wants changed in next week's meal plan")
struct PlanRequestOutput {
    @Guide(
        description: "Foods, dishes or flavours the request says to leave out, in its own words, one or two words each. Empty if none.",
        .maximumCount(8))
    var avoid: [String]
    @Guide(
        description: "Foods, dishes or flavours the request asks for, in its own words, one or two words each. Empty if none.",
        .maximumCount(8))
    var want: [String]
}

/// Reads a request for next week's plan. The word rules read it, and Apple's on-device model (or
/// Private Cloud Compute when allowed and entitled) reads it too, for wording the rules get the
/// wrong way round: "anything but chicken". Without a model, the word rules read it alone.
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
        You read a request about next week's meal-prep plan and list only what it asks for. In want, put the foods, \
        dishes, cuisines or flavours the person asks for; in avoid, the ones they don't want or can't eat. Use the \
        person's own words, one or two words each. Never add a food they didn't name. Protein, carbs, portions and how \
        often a meal repeats aren't foods: leave them out. Leave a list empty when nothing fits.
        """

    public func read(_ request: String, allowCloud: Bool) async -> PlanChange {
        let (words, named) = PlanRequests.reading(request)
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
            return Self.merge(PlanRequests.read(avoid: output.avoid, want: output.want), words: words, named: named)
        } catch {
            return words
        }
    }

    /// The word rules' reading, with the model's for the foods and flavours the request names
    /// (`named`): where the two disagree, leaving it out wins, so "anything but chicken" is no
    /// chicken. Nothing the request doesn't name, since the model lists the whole menu or an
    /// allergy from nothing ("high protein" read as no rice, no pasta, no gluten), and no diet,
    /// cost or time, which the word rules read. Nothing stays wanted that the merged avoid list or
    /// diet rules out, so "no fish" can't also read as "more cod".
    static func merge(_ model: PlanChange, words: PlanChange, named: Set<String>) -> PlanChange {
        var change = words
        change.avoid.formUnion(model.avoid.intersection(named))
        change.want = PlanRequests.remaining(
            words.want.union(model.want.intersection(named)), avoiding: change.avoid, diet: change.diet)
        return change
    }
}
