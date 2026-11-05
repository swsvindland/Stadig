import MindEngine
import SwiftUI
import SystemCore

/// The week as seven days of six parts, showing the blocks and what the week already holds. Tapping
/// a part opens it for study or closes it, and the blocks move to suit. With no `toggle` it's only
/// to look at: the hub's rhythm is deciding which parts are open.
struct WeekGrid: View {
    let cells: [WeekCell]
    var today: Weekday?
    var toggle: ((WeekCell) -> Void)?

    /// Room for "Afternoon". The seven days share what's left, whatever the width: a `Grid` here sized
    /// its columns from their contents and pushed the whole page past the screen.
    private static let labelWidth = 56.0
    private static let spacing = 3.0

    private var byPart: [DayPart: [WeekCell]] { Dictionary(grouping: cells, by: \.part) }

    var body: some View {
        let rows = byPart
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.short).font(.caption2.weight(.semibold)).foregroundStyle(weekday == today ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(DayPart.allCases) { part in
                HStack(spacing: Self.spacing) {
                    Text(part.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    ForEach(rows[part] ?? []) { cell in
                        if let toggle {
                            Button {
                                toggle(cell)
                            } label: {
                                WeekCellView(cell: cell)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(cell.accessibilityLabel)
                            .accessibilityHint(cell.isOpen ? "Closes this part of the week" : "Opens this part of the week")
                            .accessibilityIdentifier("week.part.\(cell.id)")
                        } else {
                            WeekCellView(cell: cell)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(cell.accessibilityLabel)
                                .accessibilityIdentifier("week.part.\(cell.id)")
                        }
                    }
                }
            }
        }
        .card(padding: 10)
    }
}

private struct WeekCellView: View {
    let cell: WeekCell

    var body: some View {
        ZStack {
            switch cell.content {
            case .block(let domain, let done):
                DomainBadge(domain: domain, size: 24).opacity(done ? 0.4 : 1)
                if done {
                    Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.green)
                }
            case .commitment(_, let symbol):
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.14))
                Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
            case .open:
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            case .closed:
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(.rect)
    }
}

/// Off, reviews only or a number of blocks a week: one control for how much of a course there is.
struct CourseAmount: View {
    let domain: Domain
    let amount: Int
    let identifier: String
    let set: (Int) -> Void

    var body: some View {
        Stepper(value: Binding(get: { amount }, set: { set($0) }), in: WeekSettings.courseOff...WeekSettings.blockRange.upperBound) {
            LabeledContent(domain.label, value: WeekSettings.amountLabel(amount))
        }
        .accessibilityValue(WeekSettings.amountLabel(amount))
        .accessibilityIdentifier(identifier)
    }
}

/// What to change when the blocks won't fit the week. Nothing when they do.
struct LoadWarning: View {
    let warning: String?

    var body: some View {
        if let warning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .symbolRenderingMode(.multicolor)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("week.warning")
        }
    }
}
