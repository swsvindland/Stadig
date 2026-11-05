import HubEngine
import SwiftUI
import SystemCore

/// The shape of a normal week. Work and sleep are set here; the rest is each app's own, shown so you
/// can see what the plan is working from.
struct RhythmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let subtitle = "The shape of a normal week. The plan fits around it."

    private var pattern: Binding<WorkPattern> {
        Binding(
            get: { model.rhythm?.pattern ?? SchedulePreset.nothingFixed.pattern(anchor: model.today) },
            set: { pattern in model.updateRhythm { $0.pattern = pattern } })
    }

    private func setting(_ key: WritableKeyPath<Rhythm, Int>, fallback: Int) -> Binding<Int> {
        Binding(get: { model.rhythm?[keyPath: key] ?? fallback }, set: { value in model.updateRhythm { $0[keyPath: key] = value } })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if Platform.isVision {
                        Text(Self.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    // Always the two: a grid would leave a third column empty in a wide window.
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 10) {
                            schedule
                            around
                        }
                    } else {
                        schedule
                        around
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .pageWidth(sizeClass)
            }
            .background(.pageBackground)
            .navigationTitle("Your rhythm")
            .navigationSubtitleIfAvailable(Self.subtitle)
        }
    }

    private var schedule: some View {
        ScheduleCard(pattern: pattern, monday: model.today.startOfWeek)
    }

    private var around: some View {
        VStack(spacing: 10) {
            SleepCard(wake: setting(\.wake, fallback: Rhythm.standardWake), bed: setting(\.bed, fallback: Rhythm.standardBed))
            EveningsCard(evenings: setting(\.clearEvenings, fallback: Rhythm.standardClearEvenings))
            if !model.lines.isEmpty { SourcesCard(lines: model.lines) }
        }
    }
}

/// Wake and bed. A bedtime after midnight belongs to the day before it.
struct SleepCard: View {
    @Binding var wake: Int
    @Binding var bed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeading("Sleep")
            ClockField(title: "Wake", minutes: $wake)
                .accessibilityIdentifier("rhythm.wake")
            ClockField(
                title: "Bed",
                minutes: Binding(get: { bed }, set: { bed = $0 < 12 * 60 ? $0 + 1440 : $0 })
            )
            .accessibilityIdentifier("rhythm.bed")
        }
        .card(padding: 14, radius: 18)
    }
}

struct EveningsCard: View {
    @Binding var evenings: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeading("Free time")
            Stepper(evenings == 1 ? "Keep 1 evening clear" : "Keep \(evenings) evenings clear", value: $evenings, in: 0...5)
                .accessibilityIdentifier("rhythm.evenings")
            Text("Study stays out of them, and they're chosen for you from the end of the week.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card(padding: 14, radius: 18)
    }
}

/// What the plan knows from each app.
struct SourcesCard: View {
    let lines: [RhythmLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(line.source).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(line.value).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card(padding: 14, radius: 18)
    }
}
