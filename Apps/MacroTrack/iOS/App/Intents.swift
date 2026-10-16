import AppIntents
import Foundation
import FoodDatabase
import FoodIntelligence
import NutritionEngine
import SystemCore

// Siri, Shortcuts, Spotlight and the Action Button: log without opening the app, or open it
// straight on the camera or scanner.

extension AppModel {
    /// Logs a described meal now: the model names foods and amounts, the catalog supplies the
    /// numbers. Without the model, the best search match at its usual portion. Returns what was
    /// logged, in words.
    func logDescribed(_ text: String) async -> String {
        let now = Date()
        var logged: [FoodEntry] = []
        if ai.canDescribe, let guess = try? await ai.recognize(description: text, personal: personal) {
            for item in guess.items {
                guard let food = item.match?.food, let unit = item.unit else { continue }
                logged.append(FoodEntry(date: now, name: food.name, brand: food.brand, foodID: food.id,
                                        amountLabel: FoodUnits.entryLabel(for: food, count: item.count, unit: unit, estimate: true),
                                        grams: FoodUnits.amount(item.count, unit),
                                        unitID: unit.id, count: item.count, nutrients: FoodUnits.nutrients(food, count: item.count, unit: unit),
                                        micros: FoodUnits.micros(food, count: item.count, unit: unit),
                                        processing: food.processing, fermented: food.fermented, source: .shortcut, confidence: item.sure && !item.approximate ? 0.8 : 0.5))
            }
        }
        if logged.isEmpty {
            let catalog = catalog, personal = personal
            let match = await Task.detached { catalog.search(text, personal: personal, limit: 1).first }.value
            if let food = match?.food {
                let p = personalFood(food.id)
                let s = FoodUnits.suggested(for: food, lastUnitID: p?.lastUnitID, lastCount: p?.lastCount)
                logged.append(FoodEntry(date: now, name: food.name, brand: food.brand, foodID: food.id,
                                        amountLabel: FoodUnits.entryLabel(for: food, count: s.count, unit: s.unit),
                                        grams: FoodUnits.amount(s.count, s.unit),
                                        unitID: s.unit.id, count: s.count, nutrients: FoodUnits.nutrients(food, count: s.count, unit: s.unit),
                                        micros: FoodUnits.micros(food, count: s.count, unit: s.unit),
                                        processing: food.processing, fermented: food.fermented, source: .shortcut))
            }
        }
        guard !logged.isEmpty else { return "Couldn't find “\(text)”. Open Macro Track to search for it." }
        log(logged)
        let kcal = logged.map(\.nutrients.kcal).reduce(0, +)
        let names = logged.map { "\($0.amountLabel) \($0.name)" }.joined(separator: ", ")
        return "Logged \(names): \(Format.kcal(kcal)). \(remainingSentence)"
    }

    /// "1,240 kcal and 62 g protein left today."
    var remainingSentence: String {
        guard let analysis else { return "" }
        let t = analysis.targets, eaten = analysis.todayIntake
        var parts: [String] = []
        if let kcal = t.kcal { parts.append(kcal >= eaten.kcal ? "\(Format.kcal(kcal - eaten.kcal)) left" : "\(Format.kcal(eaten.kcal - kcal)) over") }
        if let protein = t.protein, protein > eaten.protein { parts.append("\(Format.grams(protein - eaten.protein)) protein to go") }
        if parts.isEmpty { return "\(Format.kcal(eaten.kcal)) and \(Format.grams(eaten.protein)) protein so far today." }
        let sentence = parts.joined(separator: ", ")
        return sentence.prefix(1).uppercased() + String(sentence.dropFirst()) + " today."
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Logs what you ate from a description, like “two eggs and toast”.")

    @Parameter(title: "What you ate", requestValueDialog: "What did you eat?")
    var meal: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$meal)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.onboarded else { return .result(dialog: "Open Macro Track to set it up first.") }
        return .result(dialog: IntentDialog(stringLiteral: await model.logDescribed(meal)))
    }
}

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Weight"
    static let description = IntentDescription("Records this morning's weigh-in.")

    @Parameter(title: "Weight", requestValueDialog: "What did you weigh?")
    var weight: Double

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$weight)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.onboarded, weight > 20 else { return .result(dialog: "Open Macro Track to set it up first.") }
        model.weighIn(kg: model.units.weight.toKilograms(weight))
        return .result(dialog: "Logged \(Format.weight(model.units.weight.toKilograms(weight), unit: model.units.weight)).")
    }
}

struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add Calories"
    static let description = IntentDescription("Adds calories and protein without picking a food.")

    @Parameter(title: "Calories")
    var kcal: Int

    @Parameter(title: "Protein (g)", default: 0)
    var protein: Int

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$kcal) kcal and \(\.$protein) g protein") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.onboarded else { return .result(dialog: "Open Macro Track to set it up first.") }
        model.selectedDay = model.today
        model.quickAdd(name: "Quick add", nutrients: Nutrients(kcal: Double(kcal), protein: Double(protein), carbs: 0, fat: 0))
        return .result(dialog: IntentDialog(stringLiteral: "Added \(Format.kcal(Double(kcal))). \(model.remainingSentence)"))
    }
}

struct RemainingIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Left Today"
    static let description = IntentDescription("Says what's left of today's calories and protein.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.recompute()
        return .result(dialog: IntentDialog(stringLiteral: model.remainingSentence))
    }
}

struct MacroShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMealIntent(), phrases: ["Log food in \(.applicationName)", "Log a meal in \(.applicationName)",
                                                       "Add food to \(.applicationName)"],
                    shortTitle: "Log Food", systemImageName: "fork.knife")
        AppShortcut(intent: OpenLoggerIntent(), phrases: ["Snap a meal in \(.applicationName)", "Scan food with \(.applicationName)",
                                                          "Open \(.applicationName) logging"],
                    shortTitle: "Log with Camera", systemImageName: "camera")
        AppShortcut(intent: RemainingIntent(), phrases: ["How many calories are left in \(.applicationName)",
                                                         "What's left today in \(.applicationName)"],
                    shortTitle: "Calories Left", systemImageName: "chart.pie")
        AppShortcut(intent: LogWeightIntent(), phrases: ["Log my weight in \(.applicationName)"],
                    shortTitle: "Log Weight", systemImageName: "scalemass")
    }
}
