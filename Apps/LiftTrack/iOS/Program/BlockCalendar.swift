import LiftEngine
import SwiftUI
import SystemCore

/// The block's days, a week to a row from its first day: training days, the ones trained, vacations,
/// the deload, the check-in and today.
struct BlockCalendar: View {
    let weeks: [ProgramLayout.CalendarWeek]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(weeks.first?.days ?? []) { day in
                    Text(day.day.weekday.short.prefix(1)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            ForEach(weeks) { week in
                GridRow {
                    Text(label(week.week)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    ForEach(week.days) { day in
                        DayCell(day: day)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Block calendar")
    }

    private func label(_ week: BlockWeek) -> String {
        switch week {
        case .loading(let i): "W\(i + 1)"
        case .deload: "Deload"
        default: ""
        }
    }
}

private struct DayCell: View {
    let day: ProgramLayout.CalendarDay

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(fill)
            .overlay {
                if day.vacation {
                    Image(systemName: "airplane").font(.system(size: 9)).foregroundStyle(.white)
                } else if day.checkIn {
                    Image(systemName: "checklist").font(.system(size: 9, weight: .semibold)).foregroundStyle(.purple)
                } else if day.trained {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
            .overlay {
                if day.training && !day.trained {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.orange, lineWidth: 1.5)
                }
            }
            .overlay {
                if day.isToday { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary, lineWidth: 2) }
            }
            .frame(minWidth: 20, idealWidth: 26, maxWidth: 32, minHeight: 20, idealHeight: 24, maxHeight: 28)
            .opacity(day.inBlock ? 1 : 0.25)
            .accessibilityElement()
            .accessibilityLabel(description)
    }

    private var fill: Color {
        if day.vacation { return .teal }
        if day.trained { return .orange }
        if day.week.isDeload { return .mint.opacity(0.35) }
        return .secondary.opacity(0.12)
    }

    private var description: String {
        var parts = [Format.day(day.day)]
        if day.isToday { parts.append("today") }
        if day.vacation { parts.append("vacation") }
        if day.week.isDeload { parts.append("deload") }
        if day.checkIn { parts.append("check-in") }
        if day.trained { parts.append("trained") } else if day.training { parts.append("training day") }
        return parts.joined(separator: ", ")
    }
}

/// What the calendar's marks mean.
struct BlockCalendarKey: View {
    var body: some View {
        // One row where it fits; two where one would break "Vacation" over two lines (beside the
        // block's summary in Vision Pro's window).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                trained
                trainingDay
                deload
                vacation
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    trained
                    trainingDay
                }
                GridRow {
                    deload
                    vacation
                }
            }
        }
        .lineLimit(1)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var trained: some View { key(Color.orange, "Trained") }
    private var deload: some View { key(Color.mint.opacity(0.35), "Deload") }
    private var vacation: some View { key(Color.teal, "Vacation") }

    private var trainingDay: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.orange, lineWidth: 1.5).frame(width: 12, height: 12)
            Text("Training day")
        }
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title)
        }
    }
}
