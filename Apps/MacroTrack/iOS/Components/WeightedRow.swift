import SwiftUI

/// A row whose children share its width by weight (`layoutWeight`), as a CSS grid's `3fr 4fr 4fr`
/// does: the year's phases, each as long as it runs.
nonisolated struct WeightedRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let heights = zip(subviews, widths(width, subviews)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }

    private func widths(_ total: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        let weights = subviews.map { $0[LayoutWeight.self] }
        let sum = max(weights.reduce(0, +), 0.0001)
        let room = max(0, total - spacing * CGFloat(max(0, subviews.count - 1)))
        return weights.map { room * $0 / sum }
    }
}

private nonisolated struct LayoutWeight: LayoutValueKey {
    static let defaultValue: Double = 1
}

extension View {
    /// This view's share of a `WeightedRow`.
    func layoutWeight(_ weight: Double) -> some View { layoutValue(key: LayoutWeight.self, value: weight) }
}
