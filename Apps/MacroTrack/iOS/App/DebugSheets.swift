import SwiftUI
import SystemCore

extension View {
    /// `-sheet <name>` opens a sheet that hangs off a screen's own state once that screen appears,
    /// for checking it without the taps to reach it: `lifeMode` (with `-showSettings`), `caffeine`
    /// (drinks on, as `-seedSupplements` has them), `phase` (a recommendation ready, no plan),
    /// `meal` (with a logger open on a meal being logged), `day` (`-tab log`), `time` (with a logger
    /// open), `steps` (with `-prepCounter`), `supplement` (Today's supplements) and `mealPlanSetup`
    /// (`-tab plan`, no meal plan). Debug builds only; elsewhere it does nothing.
    func debugSheet(_ name: String, open: @escaping () -> Void) -> some View {
        #if DEBUG
        modifier(DebugSheetOpener(name: name, open: open))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct DebugSheetOpener: ViewModifier {
    /// The sheets already opened, so one closed doesn't open again when its screen comes back.
    private static var opened: Set<String> = []
    let name: String
    let open: () -> Void

    func body(content: Content) -> some View {
        content.task {
            guard LaunchOptions.current.value(after: "-sheet") == name, !Self.opened.contains(name) else { return }
            Self.opened.insert(name)
            // After the screen's own first layout, so the sheet has somewhere to present from.
            try? await Task.sleep(for: .milliseconds(400))
            open()
        }
    }
}
#endif
