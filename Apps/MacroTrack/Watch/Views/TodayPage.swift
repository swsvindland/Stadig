import NutritionEngine
import SwiftUI
import SystemCore

/// What's left today, at a glance: calories as the outer ring, protein inside it, carbs and fat
/// beneath, the weigh-in until there's been one, and "Day Complete" once something's logged.
struct TodayPage: View {
    @Environment(WristModel.self) private var model
    let today: WristToday

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                MacroRings(kcal: today.kcal, protein: today.protein)
                    .frame(width: 118, height: 118)
                    .accessibilityIdentifier("today.calories")
                proteinLine
                if today.showsAllMacros, today.carbs.target != nil || today.fat.target != nil {
                    HStack(spacing: 10) {
                        MacroLine(name: "Carbs", progress: today.carbs, color: MacroColor.carbs)
                        MacroLine(name: "Fat", progress: today.fat, color: MacroColor.fat)
                    }
                    .accessibilityIdentifier("today.carbsFat")
                }
                if let badge = today.badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2), in: .capsule)
                        .accessibilityIdentifier("today.badge")
                }
                // A life mode changes what the day asks for: say so. A phase's own note is for the phone.
                if today.mode != .phase, today.mode != .assessment {
                    Text(today.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !today.weighedToday {
                    NavigationLink(value: WristRoute.weighIn) {
                        Label("Weigh In", systemImage: "scalemass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("today.weighIn")
                }
                if today.hasEntries { dayComplete }
            }
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        // `-scrollToEnd` opens Today scrolled down, to look at what's below the rings.
        .defaultScrollAnchor(LaunchOptions.current.has("-scrollToEnd") ? .bottom : .top)
        #endif
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: WristRoute.weighIn) {
                    Image(systemName: "scalemass")
                }
                .accessibilityLabel("Weigh in")
                .accessibilityIdentifier("today.weighInButton")
            }
        }
    }

    private var proteinLine: some View {
        let protein = WristFormat.left(today.protein)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle().fill(MacroColor.protein).frame(width: 7, height: 7).accessibilityHidden(true)
            Text("\(protein.value) g")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
            Text("protein \(protein.label)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.protein")
    }

    @ViewBuilder private var dayComplete: some View {
        let complete = today.dayState == .complete
        Button {
            model.setDayComplete(!complete)
        } label: {
            Label(complete ? "Day Complete" : "Mark Day Complete", systemImage: complete ? "checkmark.circle.fill" : "checkmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(complete ? .green : nil)
        .accessibilityIdentifier("today.dayComplete")
        .accessibilityHint(complete ? "Marks today as still in progress." : "Complete days teach your maintenance estimate.")
    }
}

/// Calories as the outer ring and protein inside it, with what's left in the middle.
struct MacroRings: View {
    let kcal: MacroProgress
    let protein: MacroProgress

    var body: some View {
        let left = WristFormat.left(kcal)
        ZStack {
            Ring(fraction: kcal.fraction, color: MacroColor.kcal, lineWidth: 12)
            Ring(fraction: protein.fraction, color: MacroColor.protein, lineWidth: 9)
                .padding(15)
            VStack(spacing: -2) {
                Text(left.value)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("kcal \(left.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(kcal: kcal, protein: protein))
    }

    /// "1,060 kcal left of 2,300. 74 g protein left of 170."
    static func label(kcal: MacroProgress, protein: MacroProgress) -> String {
        "\(sentence(kcal, unit: "kcal")) \(sentence(protein, unit: "g protein"))"
    }

    private static func sentence(_ progress: MacroProgress, unit: String) -> String {
        let left = WristFormat.left(progress)
        guard let target = progress.target else { return "\(left.value) \(unit) eaten." }
        return "\(left.value) \(unit) \(left.label) of \(WristFormat.whole(target))."
    }
}

/// A ring filled to its fraction; an empty track when the day has no target for it.
struct Ring: View {
    let fraction: Double?
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "110 g carbs left", small, with its colour.
struct MacroLine: View {
    let name: String
    let progress: MacroProgress
    let color: Color

    var body: some View {
        let left = WristFormat.left(progress)
        VStack(spacing: 0) {
            Text("\(left.value) g")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text("\(name.lowercased()) \(left.label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
