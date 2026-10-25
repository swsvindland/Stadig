import SwiftUI
import SystemStore

/// Settings' sync rows: how iCloud is going for Stadig Macro's own records, with the reason in words
/// when it isn't, and the setup shared with the other apps when that's the part failing.
struct SyncStatusRows: View {
    let records: SyncState
    let shared: SyncState?

    var body: some View {
        LabeledContent("Sync", value: records.summary)
            .accessibilityIdentifier("settings.sync")
        if let problem = records.problem {
            Label(problem, systemImage: "exclamationmark.icloud")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.syncProblem")
        } else if let synced = records.lastSynced {
            Text("Last synced \(synced, format: .relative(presentation: .named))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let problem = shared?.problem {
            LabeledContent("Shared setup", value: "Not syncing")
            Label(problem, systemImage: "exclamationmark.icloud")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
