import MindEngine
import Observation
import SwiftUI
import SystemCore

#if !os(macOS)
import GameController
#endif

/// Whether there's a keyboard on the desk: always on the Mac, and on iPad and Vision Pro while one
/// is connected. Choices show their keys only then; the keys themselves work whenever one is used.
/// One for the app's lifetime, so its observers live as long as the app does.
@MainActor @Observable
final class HardwareKeyboard {
    static let shared = HardwareKeyboard()

    private(set) var connected: Bool
    @ObservationIgnored private var observers: [NotificationToken] = []

    private init() {
        #if os(macOS)
        connected = true
        #else
        connected = GCKeyboard.coalesced != nil
        observers = [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect].map { name in
            NotificationToken.observe(name) { [weak self] in self?.connected = GCKeyboard.coalesced != nil }
        }
        #endif
        #if DEBUG
        // -keyHints shows them anyway, for screenshots on a simulator without a keyboard attached.
        if LaunchOptions.current.has("-keyHints") { connected = true }
        #endif
    }
}

extension View {
    /// Binds a step's keys (`SessionKeys`) to what they do on it. Each key is a button nobody sees,
    /// so it works whether or not anything has focus, stops with its step, and shows in iPad's list
    /// of shortcuts when ⌘ is held.
    func sessionKeys(_ bindings: [SessionKeyBinding], perform: @escaping (SessionKey) -> Void) -> some View {
        background {
            ZStack {
                ForEach(bindings) { binding in
                    Button(binding.action.title) { perform(binding.action) }
                        .keyboardShortcut(binding.key.equivalent, modifiers: binding.modifiers.eventModifiers)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension SessionKeyBinding.Key {
    var equivalent: KeyEquivalent {
        switch self {
        case .character(let character): KeyEquivalent(character)
        case .return: .return
        case .space: .space
        }
    }
}

extension SessionKeyBinding.Modifiers {
    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.option) { modifiers.insert(.option) }
        return modifiers
    }
}

extension SessionKey {
    /// What the key does, as iPad's shortcut list and the legend under a step say it.
    var title: String {
        switch self {
        case .choose(let index): "Choose \(index + 1)"
        case .submit: "Continue"
        case .handIn: "Hand In"
        case .replay: "Play Again"
        case .replaySlowly: "Play Slower"
        case .dontKnow: "Don't Know"
        case .pick(let index): index == 0 ? "A Is Stronger" : "B Is Stronger"
        }
    }
}

/// A key cap beside a choice or in the legend: "1", "↩", "⌘D".
struct KeyHint: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 22)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
            .accessibilityHidden(true)
    }
}

/// The step's other keys in one quiet line under its buttons, while a keyboard is there: choices
/// carry their own. `titles` names what Return and the rest do on this step.
struct KeyLegend: View {
    let bindings: [SessionKeyBinding]
    var titles: [SessionKey: String] = [:]
    @State private var keyboard = HardwareKeyboard.shared

    var body: some View {
        let shown = legend
        if keyboard.connected {
            HStack(spacing: 14) {
                if let choices = choiceRange {
                    HStack(spacing: 5) {
                        KeyHint(label: choices)
                        Text("Choose").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(shown) { binding in
                    HStack(spacing: 5) {
                        KeyHint(label: binding.label)
                        Text(titles[binding.action] ?? binding.action.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    KeyHint(label: "Esc")
                    Text("End").font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    /// "1–4" when the step's choices have keys: the buttons show which is which.
    var choiceRange: String? {
        let count = bindings.filter { if case .choose = $0.action { true } else { false } }.count
        return count > 1 ? "1–\(count)" : count == 1 ? "1" : nil
    }

    /// One key per action (Space for replay, not R as well), choices left to their buttons.
    var legend: [SessionKeyBinding] {
        var seen: Set<SessionKey> = []
        return bindings.filter { binding in
            switch binding.action {
            case .choose, .pick: return false
            default: return seen.insert(binding.action).inserted
            }
        }
    }
}
