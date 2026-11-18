import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Asks how far one exercise's machine moves at the gym (`Gym.exerciseSteps`), from any exercise's
/// menu in the session. Always equal to another, like `ShowExerciseAction`: it only sets the session
/// screen's own state.
nonisolated struct EditStepsAction: Equatable {
    let open: @MainActor (String) -> Void

    @MainActor func callAsFunction(_ exerciseID: String) { open(exerciseID) }

    static func == (_: EditStepsAction, _: EditStepsAction) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var editSteps: EditStepsAction? = nil
}

/// "Leg Press steps": what the exercise goes up by at the person's gym, typed in the gym's unit, or
/// back to the gym's usual step. − and + move by it from then on, the Watch's crown too, and the
/// sessions after plan on it.
struct ExerciseStepsAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var exerciseID: String?
    @State private var typed = ""

    func body(content: Content) -> some View {
        let exercise = exerciseID.map { model.catalog.resolve($0) }
        let gym = model.gym
        let unit = gym.unit.symbol
        let own = exercise.flatMap { gym.step(for: $0) }
        let usual = exercise.flatMap { gym.increments(for: $0.equipment).usualStep }
        content
            .alert(
                exercise.map { "\($0.name) steps" } ?? "Steps",
                isPresented: Binding(get: { exerciseID != nil }, set: { if !$0 { exerciseID = nil } })
            ) {
                TextField(unit, text: $typed)
                    .fieldKeyboard(.decimal)
                    .accessibilityIdentifier("steps.field")
                Button("Save") {
                    if let step = Self.typedStep(typed) { save(step, for: exercise) }
                }
                .accessibilityIdentifier("steps.save")
                if own != nil, let usual {
                    Button("Use the gym's \(Format.number(usual, digits: 2)) \(unit)") { save(nil, for: exercise) }
                        .accessibilityIdentifier("steps.reset")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What it goes up by at \(gym.name), in \(unit). − and + move by it, and the sessions after plan on it.")
            }
            .onChange(of: exerciseID) {
                guard exercise != nil else { return }
                typed = (own ?? usual).map { Format.number($0, digits: 2) } ?? ""
            }
    }

    /// A typed step in the gym's unit: a number over nothing and at most 100 (more is a slip). A
    /// decimal comma reads as a point.
    static func typedStep(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0,
            value <= 100
        else { return nil }
        return value
    }

    /// Saved on the person's gym, not crunch mode's stand-in: the machine is the gym's.
    private func save(_ step: Double?, for exercise: Exercise?) {
        guard let exercise else { return }
        let original = model.gym
        _ = model.save(gymEdits: original.setting(step: step, for: exercise), from: original)
    }
}
