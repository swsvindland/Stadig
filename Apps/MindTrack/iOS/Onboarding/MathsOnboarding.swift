import SwiftUI
import MindEngine

/// Maths: what it's for. Placement is a test, not a question about school, so this only asks
/// which strands matter. Numeracy is always kept up.
struct MathsOnboarding: View {
    @Binding var settings: MindSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Maths").font(.title.bold())
            Text("Three strands, each with its own level. A short placement test samples each one, so there's nothing to remember about school.")
                .foregroundStyle(.secondary)
            ForEach(MathsStrand.allCases) { strand in
                let on = settings.mathsStrands.contains(strand)
                Button {
                    guard strand != .numeracy else { return }
                    if on { settings.mathsStrands.removeAll { $0 == strand } } else { settings.mathsStrands.append(strand) }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(strand.label).font(.headline)
                            Text(strand.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            if strand == .numeracy { Text("Always on: a few minutes opens every maths session.").font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(on ? Color.accentColor : .secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .onAppear { if !settings.mathsStrands.contains(.numeracy) { settings.mathsStrands.insert(.numeracy, at: 0) } }
    }

    static func firstSession(_ settings: MindSettings) -> String? { "Maths: about a dozen problems to place you" }
}

/// Which maths strands to work on. Numeracy always stays.
struct MathsSettings: View {
    @Environment(AppModel.self) private var model
    let settings: MindSettings

    var body: some View {
        Section {
            ForEach(MathsStrand.allCases) { strand in
                Toggle(strand.label, isOn: Binding(get: { settings.mathsStrands.contains(strand) }, set: { on in
                    var s = settings
                    s.mathsStrands = on ? s.mathsStrands + [strand] : s.mathsStrands.filter { $0 != strand }
                    model.save(settings: s)
                }))
                .disabled(strand == .numeracy)
            }
        } header: {
            Text("Maths")
        } footer: {
            Text("Numeracy opens every maths session whatever else you're working on.")
        }
    }
}
