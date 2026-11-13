import NutritionEngine
import SwiftUI
import SystemCore

/// The menu bar on the Mac (and the iPad's, with a keyboard): every way to log, the day, and the
/// destinations, each with its shortcut. There's one window, so they act on the shared model.
struct MacroCommands: Commands {
    /// Nil while XCTest hosts the unit tests.
    let model: AppModel?

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        ToolbarCommands()
        // A single window: no New Window. Opening a photo of a meal is this app's Open.
        CommandGroup(replacing: .newItem) {
            Button("Open a Meal Photo…") { log(.photoLibrary) }
                .keyboardShortcut("o")
                .disabled(!ready)
        }
        CommandMenu("Log") {
            Group {
                Button("Log Food…") { model?.openLogger(.search) }
                    .keyboardShortcut("l")
                Button("Describe a Meal…") { log(.describe) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Log a Photo…") { log(Camera.isAvailable ? .camera : .photoLibrary) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(LiveScan.isAvailable ? "Scan a Barcode…" : "Type a Barcode…") { log(.scan) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Quick Add…") { log(.quickAdd) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Weigh In…") {
                    model?.dismissSheets()
                    model?.showWeighIn = true
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(onADayAhead)
            }
            .disabled(!ready)
        }
        CommandMenu("Day") {
            Group {
                Button("Previous Day") { step(-1) }
                    .keyboardShortcut("[")
                Button("Next Day") { step(1) }
                    .keyboardShortcut("]")
                Divider()
                Button("Today") {
                    model?.showToday()
                    model?.go(to: .log)
                }
                .keyboardShortcut("t")
            }
            .disabled(!ready)
        }
        CommandMenu("Go") {
            Group {
                ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.title) { model?.go(to: tab) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Divider()
                Button("Search Foods") { model?.go(to: .foods) }
                    .keyboardShortcut("f")
            }
            .disabled(!ready)
        }
    }

    /// Set up, so there's a Today to log to.
    var ready: Bool { model?.onboarded ?? false }

    /// A day to come, which has nothing to weigh yet: the sheet would save a weight only to drop it.
    var onADayAhead: Bool { model.map { $0.selectedDay > $0.today } ?? false }

    /// A logger, in place of any sheet up, on the day being looked at.
    func log(_ mode: LogMode) {
        guard let model else { return }
        model.dismissSheets()
        model.openLogger(mode)
    }

    /// The day before or after, on the Log tab, where the change shows.
    func step(_ days: Int) {
        guard let model else { return }
        model.show(day: model.selectedDay.adding(days: days))
    }
}

#if os(macOS)
/// The Mac's Settings window (⌘,): the settings in panes, as Mac apps have them.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { SettingsView(pane: .general) }
            Tab("Intelligence", systemImage: "sparkles") { SettingsView(pane: .intelligence) }
            Tab("Health & Life", systemImage: "heart") { SettingsView(pane: .health) }
            Tab("Data", systemImage: "externaldrive") { SettingsView(pane: .data) }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .frame(minHeight: 440, idealHeight: 560)
    }
}
#endif
