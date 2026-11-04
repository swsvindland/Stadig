import AppIntents
import Foundation
import NutritionEngine
import SystemCore

// Siri and Shortcuts for fasts: start one from the last meal, say how it's going, end it.

extension AppModel {
    /// "18 h 20 m into your 24 h fast: fat burning. Ketosis from 8:05 PM." Or the time since the last meal.
    var fastSentence: String {
        guard tracksMealTiming else { return "Turn on meal timing in Stadig Macro's settings to track fasts." }
        guard let analysis else { return "" }
        let now = Date()
        if let status = analysis.fast {
            let current = Fasting.status(status.fast, now: now)
            var sentence =
                "\(Format.duration(current.elapsed)) into your \(Format.goal(status.fast.goalHours)) fast: \(current.phase.title.lowercased())."
            if current.goalReached {
                sentence += " Goal reached."
            } else {
                sentence += " \(Format.duration(current.remaining)) to go."
            }
            return sentence
        }
        guard let last = analysis.lastMeal else { return "Nothing logged recently to count from." }
        return "\(Format.duration(now.timeIntervalSince(last.end))) since your last meal, at \(Format.moment(last.end, now: now))."
    }
}

struct StartFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Fast"
    static let description = IntentDescription("Starts a fast from the end of your last meal, toward a goal in hours.")

    @Parameter(title: "Goal (hours)", default: 16, inclusiveRange: (12, 24))
    var hours: Int

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$hours) hour fast") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.refreshDay()
        await model.analysisFinished(within: .seconds(3))
        guard model.onboarded else { return .result(dialog: "Open Stadig Macro to set it up first.") }
        // Longer fasts start in the app, where the safety notes are.
        if !model.tracksMealTiming { model.setTracksMealTiming(true) }
        guard model.startFast(goalHours: Double(hours)) else {
            return .result(dialog: IntentDialog(stringLiteral: "You're already fasting. \(model.fastSentence)"))
        }
        return .result(dialog: IntentDialog(stringLiteral: model.fastSentence))
    }
}

struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End Fast"
    static let description = IntentDescription("Ends the fast you're running now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.refreshDay()
        await model.analysisFinished(within: .seconds(3))
        guard let status = model.analysis?.fast else { return .result(dialog: "You're not fasting right now.") }
        let elapsed = Date().timeIntervalSince(status.fast.start)
        model.endFast()
        let refeed = FastSafety.refeed(hours: elapsed / 3600).map { " \($0)" } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: "Ended your fast at \(Format.duration(elapsed)).\(refeed)"))
    }
}

struct FastStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Fast Status"
    static let description = IntentDescription("Says how long you've been fasting and what's likely happening.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.refreshDay()
        await model.analysisFinished(within: .seconds(3))
        return .result(dialog: IntentDialog(stringLiteral: model.fastSentence))
    }
}
