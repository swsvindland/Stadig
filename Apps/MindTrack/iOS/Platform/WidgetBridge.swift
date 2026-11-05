import Foundation
import MindEngine
import OSLog
import SystemCore
import SystemStore
import WidgetKit

/// Keeps the widgets' snapshot current: today's study as Today shows it.
enum WidgetBridge {
    /// Writes the snapshot for the model as it stands and reloads the widgets when it changed. Only
    /// the App Group's copy: a test or an in-memory launch shares nothing with the real widgets.
    static func update(_ model: AppModel) {
        guard model.shared.isAppGroup else { return }
        do {
            if try snapshot(for: model).save() { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            appLog.error("Couldn't write the widgets' snapshot: \(error.localizedDescription)")
        }
    }

    /// What the widgets show: the session waiting today, done, a rest day or a pause, with the
    /// week's count and the reviews due.
    static func snapshot(for model: AppModel) -> MindSnapshot {
        guard model.onboarded, let analysis = model.analysis else { return .empty }
        let today = model.today
        var snapshot = MindSnapshot(status: .rest, headline: "Rest day", phase: analysis.phase.label)
        snapshot.day = today
        snapshot.dayStart = model.dayStart
        snapshot.dueReviews = analysis.dueToday
        let layout = analysis.layout
        snapshot.plannedThisWeek = layout.target
        snapshot.doneThisWeek = layout.counts.keys.map { min(layout.done[$0, default: 0], layout.counts[$0, default: 0]) }.reduce(0, +)
        if analysis.blocks.count > 1 {
            snapshot.blocksToday = analysis.blocks.count
            snapshot.blocksDoneToday = analysis.blocks.filter(\.done).count
        }
        snapshot.nextDay = analysis.week.first { $0.day > today && $0.status == .planned }?.day
        snapshot.phaseLastDay = model.state?.phaseLastDay
        if case .paused(let kind) = analysis.phase {
            snapshot.status = .paused
            snapshot.headline = kind.label
        } else if let plan = analysis.today {
            snapshot.status = .today
            snapshot.headline = plan.headline
            snapshot.symbols = plan.domains.map(\.symbol)
            snapshot.parts = plan.parts.map {
                MindSnapshot.Part(title: $0.title, minutes: $0.minutes, symbol: $0.domain?.symbol ?? "arrow.triangle.2.circlepath")
            }
        } else if let done = analysis.doneToday.last(where: \.planned) ?? analysis.doneToday.last {
            snapshot.status = .done
            snapshot.headline = "Done for today"
            snapshot.symbols = done.domains.map(\.symbol)
        }
        return snapshot
    }
}
