import MindEngine
import SwiftUI
import SystemCore

/// Reading on the Plan tab: the tested level, focus, the next tier and block, and the book on the go.
struct ReadingPlanCard: View {
    @Environment(AppModel.self) private var model
    let analysis: MindAnalysis

    var body: some View {
        let reading = analysis.reading
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DomainBadge(domain: .reading)
                Text("Reading").font(.headline)
                Spacer()
                Text("Tier \(reading.targetTier) next").font(.subheadline).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Level").foregroundStyle(.secondary)
                    Text(reading.level.map { "Tier \(ReadingPlan.format($0))" } ?? "Placed by the reading test")
                    if let tested = reading.testedLevel { Text("tested \(ReadingPlan.format(tested))").foregroundStyle(.secondary) }
                }
                GridRow {
                    Text("Focus").foregroundStyle(.secondary)
                    Text(reading.stamina.map { "About \(Int($0)) min" } ?? "Measured as you read")
                    Text("next block \(reading.nextBlock) min").foregroundStyle(.secondary)
                }
            }
            if let book = reading.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.headline)
                    Text("\(book.author) · tier \(book.tier)\(book.format == .audiobook ? " · audiobook" : "")").foregroundStyle(.secondary)
                    ProgressView(value: book.progress).tint(.teal)
                    Text("Page \(book.page) of \(book.pages)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else {
                Text("No book on the go. The ladder suggests tier \(reading.targetTier) next.").foregroundStyle(.secondary)
            }
            Button("Your shelf", systemImage: "books.vertical") { model.showShelf = true }
                .accessibilityIdentifier("plan.shelf")
        }
        .font(.subheadline)
        .card()
    }
}
