import NutritionEngine
import SwiftUI
import SystemCore

/// What's left today, at a glance: the face is calories left, huge, over a level that fills from
/// the foot as the day is eaten, with protein's line across it at how much of protein is eaten (it
/// leads the level on a day that's going well). Scrolled on: carbs and fat, the life mode's note,
/// Weigh In, and "Day Complete" once something's logged.
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
                // A life mode changes what the day asks for: say so. A phase's own note is for the
                // phone, and the person's own targets are in the badge.
                if ![.phase, .assessment, .own].contains(today.mode) {
                    Text(today.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NavigationLink(value: WristRoute.weighIn) {
                    Label(today.weighedToday ? "Weighed In" : "Weigh In", systemImage: "scalemass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("today.weighIn")
                if today.hasEntries { dayComplete }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        // The face is the whole screen, the level from its foot, its top line beside the time.
        .ignoresSafeArea()
        #if DEBUG
        // `-scrollToEnd` opens Today scrolled down, to look at what's below the face.
        .defaultScrollAnchor(LaunchOptions.current.has("-scrollToEnd") ? .bottom : .top)
        #endif
        .toolbar(.hidden, for: .navigationBar)
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

/// The face: "kcal left today", the number huge, and a level in the accent rising from the foot as
/// the day's calories are eaten, saying how many of the target; protein's line crosses the face at
/// the height of how much protein is eaten, its words above it. Whatever the level has risen over is
/// drawn again in ink on it, so it reads at any level.
struct LevelFace: View {
    let kcal: MacroProgress
    let protein: MacroProgress

    var body: some View {
        let level = kcal.target == nil ? 0 : min(1, max(0, kcal.fraction ?? 0))
        GeometryReader { geometry in
            let height = geometry.size.height * level
            ZStack(alignment: .bottom) {
                content(geometry.size, level: height, onLevel: false)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: height)
                    .accessibilityHidden(true)
                content(geometry.size, level: height, onLevel: true)
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

    /// The words, numbers and lines: in their colours over the ground, in ink on the level.
    private func content(_ size: CGSize, level: CGFloat, onLevel: Bool) -> some View {
        let left = WristFormat.left(kcal)
        let ink: Color = onLevel ? WristInk.onAccent : WristInk.text
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(kcal.target == nil ? "kcal eaten today" : "kcal \(left.label) today")
                    .faceEyebrow(onLevel ? WristInk.onAccent : Color.accentColor)
                    .faceTopLine()
                BigNumber(value: left.value, points: WristFace.numeralSize(64, fitting: [left.value], besides: WristFace.margin * 2 + 6))
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                    .padding(.top, WristFace.small ? 8 : 12)
                    .padding(.leading, -2)
            }
            .padding(.horizontal, WristFace.margin)
            if protein.target != nil { proteinLine(size, level: level, onLevel: onLevel) }
            if let target = kcal.target {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(WristFormat.whole(kcal.eaten)) eaten").faceFont(14, weight: .bold)
                    Spacer(minLength: 4)
                    Text("of \(WristFormat.whole(target))").faceFont(13, weight: .semibold)
                }
                .monospacedDigit()
                .foregroundStyle(onLevel ? WristInk.onAccent : WristInk.text2)
                .padding(.leading, WristFace.margin + 2)
                .padding(.trailing, WristFace.margin + 6)
                .padding(.bottom, Self.footInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            EdgeTicks(color: onLevel ? WristInk.onAccent.opacity(0.5) : .white.opacity(0.26))
        }
    }

    /// How far the foot's "599 eaten" sits from the bottom of the screen.
    private static let footInset: CGFloat = WristFace.small ? 16 : 21

    /// Protein's line, edge to edge at the height of how much of it is eaten, under "Protein · 102 g
    /// left". It stays below the big number, and its words stay above the foot's and off the level's
    /// edge, where they'd be cut in two.
    private func proteinLine(_ size: CGSize, level: CGFloat, onLevel: Bool) -> some View {
        let left = WristFormat.left(protein)
        let color = onLevel ? WristInk.onAccent : MacroColor.protein
        let top: CGFloat = (WristFace.small ? 100 : 128) * min(1, WristFace.scale)
        let line = min(size.height - top, size.height * min(1, max(0, protein.fraction ?? 0)))
        var words = max(line + 7, Self.footInset + 26)
        if words < level, words + 18 > level { words = min(level + 5, size.height - top + 7) }
        return ZStack(alignment: .bottom) {
            // Nothing eaten yet: no line along the very foot of the screen.
            if line >= 3 {
                Rectangle()
                    .fill(color)
                    .frame(height: 3)
                    .padding(.bottom, line)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Protein").faceFont(13, weight: .semibold).foregroundStyle(color)
                Spacer(minLength: 4)
                Text("\(left.value) g \(left.label)")
                    .faceFont(13, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(onLevel ? WristInk.onAccent : WristInk.text)
            }
            .padding(.leading, WristFace.margin)
            .padding(.trailing, WristFace.margin + 4)
            .padding(.bottom, words)
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
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
