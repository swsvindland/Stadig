import NutritionEngine
import SwiftUI
import SystemCore

/// What's left today, at a glance: the face is calories left, huge, over a level that fills from
/// the foot as the day is eaten, with the protein line above it. Scrolled on: carbs and fat, the
/// life mode's note, the weigh-in until there's been one, and "Day Complete" once something's
/// logged.
struct TodayPage: View {
    @Environment(WristModel.self) private var model
    let today: WristToday

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                LevelFace(kcal: today.kcal, protein: today.protein)
                    .containerRelativeFrame(.vertical)
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
            .padding(.bottom, 24)
        }
        // The level reaches the foot of the screen; what's below it is clear of the corners.
        .ignoresSafeArea(edges: .bottom)
        #if DEBUG
        // `-scrollToEnd` opens Today scrolled down, to look at what's below the face.
        .defaultScrollAnchor(LaunchOptions.current.has("-scrollToEnd") ? .bottom : .top)
        #endif
        // The face says what it is; the bar keeps only the weigh-in.
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

/// The face: "kcal left today", the number huge, the protein line, and a level in the accent that
/// rises from the foot as the day's calories are eaten, saying how many of the target. Whatever the
/// level has risen over is drawn again in black on it, so it reads at any level.
struct LevelFace: View {
    let kcal: MacroProgress
    let protein: MacroProgress

    /// The foot's band, there from the first bite, so what's eaten has somewhere to be written.
    static let foot = 40.0

    var body: some View {
        let level = min(1, max(0, kcal.fraction ?? 0))
        GeometryReader { geometry in
            let height = kcal.target == nil ? 0 : Self.foot + (geometry.size.height - Self.foot) * level
            ZStack(alignment: .bottom) {
                content(onLevel: false)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: height)
                    .accessibilityHidden(true)
                content(onLevel: true)
                    .mask(alignment: .bottom) { Rectangle().frame(height: height) }
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeOut(duration: 0.5), value: level)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(kcal: kcal, protein: protein))
        .accessibilityIdentifier("today.calories")
    }

    /// The words and numbers: in their colours over the ground, in black on the level.
    private func content(onLevel: Bool) -> some View {
        let left = WristFormat.left(kcal)
        let ink: Color = onLevel ? .black : .white
        return VStack(alignment: .leading, spacing: 4) {
            Text(kcal.target == nil ? "kcal eaten today" : "kcal \(left.label) today")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(onLevel ? Color.black : Color.accentColor)
            Text(left.value)
                .font(.system(size: 54, weight: .bold).monospacedDigit())
                .tracking(-1.5)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            proteinLine(onLevel: onLevel)
            Spacer(minLength: 0)
            if let target = kcal.target {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(WristFormat.whole(kcal.eaten)) eaten")
                    Spacer(minLength: 4)
                    Text("of \(WristFormat.whole(target))")
                }
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(onLevel ? Color.black : Color.secondary)
                .frame(height: Self.foot - 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
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

    /// "Protein   102 g left" over a thin line in protein's colour, filled as it's eaten.
    private func proteinLine(onLevel: Bool) -> some View {
        let left = WristFormat.left(protein)
        let color = onLevel ? Color.black : MacroColor.protein
        return VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Protein").foregroundStyle(color)
                Spacer(minLength: 4)
                Text("\(left.value) g \(left.label)").monospacedDigit().foregroundStyle(onLevel ? Color.black : Color.white)
            }
            .font(.footnote.weight(.semibold))
            GeometryReader { line in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.3))
                    Capsule().fill(color).frame(width: line.size.width * min(1, max(0, protein.fraction ?? 0)))
                }
            }
            .frame(height: 3)
        }
    }
}

/// The phone's ruler on the wrist: a fill on a track, ticked every tenth so it reads as an
/// instrument. An empty track when there's nothing to fill toward.
struct WristRuler: View {
    let fraction: Double?
    var color: Color = .accentColor
    var height: CGFloat = 10

    var body: some View {
        let value = min(1, max(0, fraction ?? 0))
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.16))
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color)
                    .frame(width: value > 0 ? max(height * 0.5, width * value) : 0)
                Path { path in
                    for index in 1..<10 {
                        let x = (width * Double(index) / 10).rounded()
                        path.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: height))
                    }
                }
                .fill(Color.black.opacity(0.55))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
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
