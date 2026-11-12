import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

nonisolated extension ExerciseKind {
    var label: String {
        switch self {
        case .strength: "Strength"
        case .conditioning: "Conditioning"
        case .mobility: "Mobility drills"
        case .warmup: "Warm-ups"
        case .stretch: "Stretches"
        case .recovery: "Recovery"
        }
    }
}

nonisolated extension Exercise {
    /// "Barbell · Squat", the line under a name.
    var kindLine: String {
        kind == .strength ? "\(equipment.label) · \(pattern.label)" : "\(kind.label) · \(equipment.label)"
    }
}

/// What the library knows about an exercise: the cue, muscles, joints, cost and how far it may be
/// pushed, and its default reps and rest. The Library's detail and the Program's inspector show it.
struct ExerciseFacts: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !exercise.cue.isEmpty {
                Label(exercise.cue, systemImage: "lightbulb").font(.subheadline)
            }
            if !exercise.muscles.isEmpty {
                fact("Muscles") {
                    FlowRow(
                        items: exercise.muscles.sorted { $0.weight > $1.weight }.map { share in
                            (share.muscle.label, share.weight >= 1 ? Ink.ok : Color.secondary)
                        })
                }
            }
            if !exercise.joints.isEmpty {
                fact("Joints loaded") {
                    FlowRow(
                        items: exercise.joints.sorted { $0.stress > $1.stress }.map { load in
                            (
                                "\(load.joint.label) · \(load.stress.label.lowercased())",
                                load.stress == .high ? Ink.bad : load.stress == .moderate ? Ink.ok : .secondary
                            )
                        })
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if exercise.kind == .strength {
                    row("Failure", exercise.safetyTier.label)
                    row("Whole-body cost", level(exercise.fatigue.systemic))
                    row("Local cost", level(exercise.fatigue.local))
                    row("Stimulus", level(exercise.fatigue.stimulus))
                    row("Reps", "\(exercise.reps.hypertrophy.label) for size · \(exercise.reps.strength.label) for strength")
                    row("Rest", "\(Format.duration(exercise.rest.hypertrophy)) · \(Format.duration(exercise.rest.strength)) heavy")
                } else if let seconds = exercise.seconds {
                    row("Each set", Format.duration(seconds))
                }
                if exercise.unilateral { row("Sides", "One at a time") }
                if !exercise.mobilityTargets.isEmpty { row("Also helps", exercise.mobilityTargets.map(\.label).joined(separator: ", ")) }
            }
            .font(.subheadline)
        }
    }

    private func fact(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }

    /// A 0–1 tag in a word.
    private func level(_ value: Double) -> String {
        switch value {
        case ..<0.25: "Low"
        case ..<0.5: "Moderate"
        case ..<0.75: "High"
        default: "Very high"
        }
    }
}

/// Pills that wrap onto as many lines as they need.
struct FlowRow: View {
    let items: [(String, Color)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Pill(text: item.0, color: item.1)
            }
        }
    }
}

/// Lays its children out left to right, wrapping at the proposed width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
