import SwiftUI

/// Every way to log, in the toolbar where there's no bar of them above the tabs.
struct LogToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.openLogger(.search)
            } label: {
                Label("Log Food", systemImage: "magnifyingglass")
            }
            .help("Find a food to log (⌘L)")
            .accessibilityIdentifier("toolbar.logFood")
            Button {
                model.openLogger(.describe)
            } label: {
                Label("Describe a Meal", systemImage: "text.bubble")
            }
            .help("Describe a meal in words")
            .accessibilityIdentifier("toolbar.describe")
            Button {
                model.openLogger(Camera.isAvailable ? .camera : .photoLibrary)
            } label: {
                Label("Log a Photo", systemImage: Camera.isAvailable ? "camera" : "photo.on.rectangle")
            }
            .help(Camera.isAvailable ? "Take a photo of a meal" : "Choose a photo of a meal, or drop one on the window")
            .accessibilityIdentifier("toolbar.photo")
            Button {
                model.openLogger(.quickAdd)
            } label: {
                Label("Quick Add", systemImage: "plus.forwardslash.minus")
            }
            .help("Add calories and protein")
            .accessibilityIdentifier("toolbar.quickAdd")
            Button {
                model.showWeighIn = true
            } label: {
                Label("Weigh In", systemImage: "scalemass")
            }
            .help("Record a weigh-in")
            .disabled(model.selectedDay > model.today)
            .accessibilityIdentifier("toolbar.weighIn")
            SettingsButton(identifier: "today.settings")
        }
    }
}
