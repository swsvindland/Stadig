import FoodDatabase
import NutritionEngine
import SwiftUI

extension AppModel {
    /// What's typed might be heading for these, as a person would say the foods. Pure, for the off-main search.
    nonisolated static func completions(for text: String, in matches: [FoodMatch]) -> [String] {
        FoodCompletions.suggest(text, from: matches) { FoodLabel.parts(of: $0.name).title }
    }

    /// The options ordered by the device's model from what's been logged, or nil when there's no
    /// model to ask or no choice to make. A short wait first: the model is for a pause in the
    /// typing, and every key cancels the task this runs in.
    func rankedCompletions(_ options: [String], for text: String) async -> [String]? {
        guard ai.canRankCompletions, options.count > 1 else { return nil }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return nil }
        let past = loggerLogAgain.prefix(12).map { FoodLabel.parts(of: $0.template.name).title }
        return await ai.rankCompletions(options, typed: text, past: past)
    }
}

/// Where a search might be heading, a tap from being what's typed. One row, and nothing at all
/// without something to offer.
struct SearchCompletionChips: View {
    let options: [String]
    let pick: (String) -> Void

    var body: some View {
        if !options.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options.prefix(FoodCompletions.shown), id: \.self) { option in
                        Button {
                            pick(option)
                        } label: {
                            // The composer's chips: the card colour with a hairline.
                            Text(option)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Ink.text)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Color.cardBackground, in: .capsule)
                                .overlay(Capsule().stroke(Ink.hairline))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight()
                        .accessibilityLabel("Search for \(option)")
                        .accessibilityIdentifier("search.completion")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .animation(.snappy, value: options)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search.completions")
        }
    }
}
