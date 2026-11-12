#if os(macOS)
import AppKit
import NutritionEngine
import SwiftUI
import SystemCore

/// What sits in the Mac's menu bar: a small gauge of the day's calories and what's left ("1,601"),
/// in the menu bar's own colour.
struct MenuBarLabel: View {
    /// Nil while XCTest hosts the app's tests, when the extra isn't inserted anyway.
    let model: AppModel?

    var body: some View {
        if let model, model.onboarded, let kcal = model.analysis?.targets.kcal, kcal > 0 {
            let eaten = model.dayIntake(on: model.today).eaten.kcal
            let left = kcal - eaten
            let text = left >= 0 ? Format.whole(left) : "\(Format.whole(-left)) over"
            Image(nsImage: MenuBarGauge.image(eaten / kcal))
                .accessibilityHidden(true)
            Text(text)
                .accessibilityLabel(left >= 0 ? "Stadig Macro, \(text) kcal left" : "Stadig Macro, \(text) kcal over")
        } else {
            Image(systemName: "fork.knife")
                .accessibilityLabel("Stadig Macro")
        }
    }
}

/// Keeps the app running with its window closed while the menu bar has it, so logging from there
/// needs no window; without it, closing the window quits the app as before.
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let shown = UserDefaults.standard.object(forKey: MenuBarToday.shownKey) as? Bool ?? true
        return !shown || LaunchOptions.current.isHostingTests
    }
}

/// The ruler in the menu bar, drawn as a template image: the menu bar only takes an image and a
/// title, and tints a template one as it does its own items.
enum MenuBarGauge {
    static let size = NSSize(width: 22, height: 8)

    static func image(_ value: Double) -> NSImage {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        let image = NSImage(size: size, flipped: false) { rect in
            let radius = rect.height * 0.32
            NSColor.black.withAlphaComponent(0.32).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            if fraction > 0 {
                let filled = NSRect(x: rect.minX, y: rect.minY, width: max(rect.height * 0.5, rect.width * fraction), height: rect.height)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
