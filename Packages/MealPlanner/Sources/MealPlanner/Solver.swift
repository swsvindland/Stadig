import Foundation
import SystemCore

/// Sizes a meal's parts to its share of the targets: the grams of each part, within its range,
/// that come closest to the calories and protein first, then carbs and fat, without straying far
/// from an ordinary portion.
enum PortionSolver {
    struct Part {
        /// Calories, protein, carbs and fat per gram.
        var perGram: [Double]
        var range: ClosedRange<Double>
        var typical: Double
    }

    /// Relative weight of a miss in calories, protein, carbs and fat.
    static let weights = [4.0, 4.0, 1.0, 1.0]
    /// How strongly portions stay near the ordinary amount.
    static let ordinary = 0.04

    /// Grams for each part. `fixed` is what parts that don't scale already add (kcal, P, C, F).
    static func solve(_ parts: [Part], target: PlanTargets, fixed: [Double] = [0, 0, 0, 0]) -> [Double] {
        let goal = [target.kcal, target.protein, target.carbs, target.fat]
        // Relative misses, so 10 g of protein and 100 kcal weigh what they mean.
        let scale = goal.enumerated().map { i, g in max(g, i == 0 ? 50 : 5) }
        var x = parts.map { min(max($0.typical, $0.range.lowerBound), $0.range.upperBound) }
        // Coordinate descent on a convex quadratic, each step clamped to the part's range.
        for _ in 0..<300 {
            var moved = 0.0
            for j in parts.indices {
                var numerator = 0.0
                var denominator = 0.0
                for r in 0..<4 {
                    let others = fixed[r] + parts.indices.filter { $0 != j }.map { parts[$0].perGram[r] * x[$0] }.reduce(0, +)
                    let a = parts[j].perGram[r]
                    let w = weights[r] / (scale[r] * scale[r])
                    numerator += w * a * (goal[r] - others)
                    denominator += w * a * a
                }
                let t = max(parts[j].typical, 1)
                numerator += ordinary * parts[j].typical / (t * t)
                denominator += ordinary / (t * t)
                guard denominator > 0 else { continue }
                let next = min(max(numerator / denominator, parts[j].range.lowerBound), parts[j].range.upperBound)
                moved = max(moved, abs(next - x[j]))
                x[j] = next
            }
            if moved < 0.01 { break }
        }
        return x
    }

    /// Kitchen-scale amounts: 5 g steps, 1 g for small ones (oil, seeds).
    static func round(_ grams: Double) -> Double {
        grams < 25 ? grams.rounded() : (grams / 5).rounded() * 5
    }
}
