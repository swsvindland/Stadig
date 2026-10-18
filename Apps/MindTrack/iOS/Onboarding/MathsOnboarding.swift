import MindEngine
import SwiftUI

/// Maths: what it's for. Placement is a short test of each strand, not a question about school, so
/// this only asks which strands matter and which matters most. Numeracy is always kept up.
struct MathsOnboarding: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Maths").font(.title.bold())
                .accessibilityIdentifier("onboarding.mathsTitle")
            Text(
                "Three strands, each with its own level. The first session places each one with a short test that steps up and down, so there's nothing to remember about school."
            )
            .foregroundStyle(.secondary)
            ForEach(MathsStrand.allCases) { strand in
                let on = settings.strands.contains(strand)
                Button {
                    guard strand != .numeracy else { return }
                    settings.mathsStrands = MathsChoices.toggled(strand, in: settings)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(strand.label).font(.headline)
                            Text(strand.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            if strand == .numeracy {
                                Text("Always on: a few timed minutes open every maths session, whatever else you're working on.")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        Image(systemName: strand == .numeracy ? "lock.circle.fill" : on ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(on ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(strand == .numeracy ? "Always on" : "")
                .accessibilityIdentifier("onboarding.strand.\(strand.rawValue)")
            }
            if MathsChoices.both(settings) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Which matters more to you?").font(.headline)
                    MathsChoices.FocusPicker(settings: $settings)
                    Text("It gets two maths sessions in three; the other gets the third.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .onAppear { settings.mathsStrands = settings.strands }
    }

    static func firstSession(_ settings: MindSettings) -> String? {
        let names = settings.strands.map { $0 == .numeracy ? $0.label : $0.short }
        return
            "Maths: about \(MathsPlan.placementProblems(settings)) problems to place \(ListFormatter.localizedString(byJoining: names).lowercased())"
    }
}

/// Which maths strands to work on, and which comes first. Numeracy always stays.
struct MathsSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section {
            ForEach(MathsStrand.allCases) { strand in
                Toggle(
                    strand.label,
                    isOn: Binding(
                        get: { settings.strands.contains(strand) },
                        set: { _ in
                            var s = settings
                            s.mathsStrands = MathsChoices.toggled(strand, in: settings)
                            model.save(settings: s)
                        })
                )
                .disabled(strand == .numeracy)
                .accessibilityIdentifier("settings.strand.\(strand.rawValue)")
            }
            if MathsChoices.both(settings) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Matters more")
                    MathsChoices.FocusPicker(settings: Binding(get: { settings }, set: { model.save(settings: $0) }))
                }
            }
        } header: {
            Text("Maths")
        } footer: {
            Text(
                "Numeracy opens every maths session. The strand that matters more gets two sessions in three; one switched on later is placed in its first session."
            )
        }
    }
}

enum MathsChoices {
    static func both(_ settings: MindSettings) -> Bool { settings.strands.contains(.classic) && settings.strands.contains(.discrete) }

    /// The strands with one switched on (last, so it doesn't jump the queue) or off.
    static func toggled(_ strand: MathsStrand, in settings: MindSettings) -> [MathsStrand] {
        guard strand != .numeracy else { return settings.strands }
        let strands = settings.strands
        return strands.contains(strand) ? strands.filter { $0 != strand } : strands + [strand]
    }

    /// The order with `first` ahead of the other strand.
    static func ordered(first: MathsStrand) -> [MathsStrand] { [.numeracy, first] + [MathsStrand.classic, .discrete].filter { $0 != first } }

    struct FocusPicker: View {
        @Binding var settings: MindSettings

        var body: some View {
            Picker(
                "Matters more",
                selection: Binding(
                    get: { settings.strands.dropFirst().first ?? .classic },
                    set: { settings.mathsStrands = MathsChoices.ordered(first: $0) })
            ) {
                Text(MathsStrand.classic.label).tag(MathsStrand.classic)
                Text(MathsStrand.discrete.label).tag(MathsStrand.discrete)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("maths.mattersMore")
        }
    }
}
