import Foundation
import Testing

@testable import MacroTrack

/// A toast's few seconds. A view's task runs them, and a view leaving the screen cancels it, which
/// isn't them running out.
@MainActor
struct ToastTests {
    func model(showing message: String = "Deleted Soup") -> (AppModel, Toast) {
        let model = TestEnvironment().model()
        let toast = Toast(message: message, undo: [UUID()])
        model.toast = toast
        return (model, toast)
    }

    @Test func aToastGoesWhenItsSecondsAreUp() async {
        let (model, toast) = model()
        model.toastTime = .zero
        await model.expire(toast)
        #expect(model.toast == nil)
    }

    @Test func aSlotLeavingTheScreenLeavesTheToastForTheNextOne() async {
        let (model, toast) = model()
        let slot = Task { await model.expire(toast) }

        slot.cancel()
        await slot.value

        #expect(model.toast == toast)
    }

    @Test func aToastThatsBeenReplacedLeavesTheNewOne() async {
        let (model, toast) = model()
        let next = Toast(message: "Logged Soup")
        model.toast = next
        model.toastTime = .zero
        await model.expire(toast)
        #expect(model.toast == next)
    }
}
