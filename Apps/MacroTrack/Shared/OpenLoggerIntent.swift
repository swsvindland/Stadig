import AppIntents
import Foundation

/// Where logging opens.
nonisolated enum LoggerEntryPoint: String, AppEnum {
    case search, camera, scan, describe, weigh

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Logging"
    static let caseDisplayRepresentations: [LoggerEntryPoint: DisplayRepresentation] = [
        .search: DisplayRepresentation(title: "Search", image: .init(systemName: "magnifyingglass")),
        .camera: DisplayRepresentation(title: "Photo", image: .init(systemName: "camera")),
        .scan: DisplayRepresentation(title: "Barcode", image: .init(systemName: "barcode.viewfinder")),
        .describe: DisplayRepresentation(title: "Describe", image: .init(systemName: "text.bubble")),
        .weigh: DisplayRepresentation(title: "Weigh in", image: .init(systemName: "scalemass")),
    ]
}

/// Opens straight on a way to log: for the Action Button, Shortcuts and the Control Center and
/// Lock Screen controls. Built into the widgets too, so a control can name it; it always runs in
/// the app.
struct OpenLoggerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Food Logger"
    static let description = IntentDescription("Opens Stadig Macro on search, the camera, the barcode scanner or a description.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Start with", default: .camera)
    var entry: LoggerEntryPoint

    init() {}

    init(entry: LoggerEntryPoint) {
        self.entry = entry
    }

    static var parameterSummary: some ParameterSummary { Summary("Open logging with \(\.$entry)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        let model = AppModel.shared
        model.refreshDay()
        guard model.onboarded else { return .result() }
        model.selectedDay = model.today
        // In place of whatever sheet was up: only one shows at a time.
        model.dismissSheets()
        switch entry {
        case .search: model.openLogger(.search)
        case .camera: model.openLogger(.camera)
        case .scan: model.openLogger(.scan)
        case .describe: model.openLogger(.describe)
        case .weigh: model.showWeighIn = true
        }
        #endif
        return .result()
    }
}
