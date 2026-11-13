import NutritionEngine
import SwiftUI
import SystemCore
import WidgetKit

// The complications' views, compiled into the complications and into the Watch app, whose DEBUG
// gallery (`-complications`) draws them with the app's own numbers. They wear Stadig's look
// (docs/design.md): numbers heavy and tabular, small uppercase eyebrows in the accent, and the ruler
// in place of rings. A face tints what it draws, keeping only opacity, so the ruler's track is
// translucent and its ticks are gaps, and only the eyebrows, symbols and fills are accentable.

/// Which macro a complication shows, and how it's worded.
enum ComplicationMacro {
    case kcal, protein

    /// The phone's protein colour in dark mode, which the Watch always is.
    static let proteinColor = Color(red: 1, green: 0x7A / 255, blue: 0x70 / 255)

    var symbol: String { self == .kcal ? "flame.fill" : "p.circle.fill" }
    var color: Color { self == .kcal ? .accentColor : Self.proteinColor }
    var name: String { self == .kcal ? "Calories" : "Protein" }
    /// The unit after a number: "1,060 kcal", "74 g".
    var unit: String { self == .kcal ? "kcal" : "g" }

    func progress(_ snapshot: WristSnapshot) -> MacroProgress { self == .kcal ? snapshot.kcal : snapshot.protein }
}

/// What's left: "1,060" and "left", "120" and "over", or before targets, "1,240" and "eaten".
struct ComplicationText {
    var value: String
    var word: String

    init(_ progress: MacroProgress) {
        let number = progress.left.map(abs) ?? progress.eaten
        value = Int(number.rounded()).formatted()
        word = progress.left == nil ? "eaten" : progress.isOver ? "over" : "left"
    }

    /// "1,060 kcal left", for VoiceOver and the inline family.
    func sentence(_ macro: ComplicationMacro) -> String { "\(value) \(macro.unit) \(macro == .protein ? "protein " : "")\(word)" }

    /// Under the number on the circular face: "kcal" and "g P" when it's what's left, else the word.
    func short(_ macro: ComplicationMacro) -> String {
        switch (macro, word) {
        case (.kcal, "left"): "kcal"
        case (.protein, "left"): "g P"
        case (.kcal, _): word
        case (.protein, _): "g \(word)"
        }
    }
}

extension View {
    /// A number set as the hero: heavy, tabular, tightly tracked, shrinking to fit the complication.
    func complicationNumeral(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .tracking(-size * 0.04)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// The small uppercase label over a number: "KCAL LEFT TODAY", "FAT BURNING".
    func complicationEyebrow() -> some View {
        font(.system(size: 11, weight: .semibold)).textCase(.uppercase).tracking(0.7).lineLimit(1)
    }
}

/// The phone's ruler on the watch face: a fill on a translucent track, ticked every tenth by gaps so
/// it reads the same when the face tints it. Rulers under 6 points aren't ticked.
struct ComplicationRuler: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 8

    private var value: Double { fraction.isFinite ? min(1, max(0, fraction)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.25))
                Rectangle()
                    .fill(color)
                    .frame(width: value > 0 ? max(height * 0.5, size.width * value) : 0)
                    .widgetAccentable()
            }
            .mask {
                Path { path in
                    let radius = min(3, size.height * 0.4)
                    path.addRoundedRect(in: CGRect(origin: .zero, size: size), cornerSize: CGSize(width: radius, height: radius), style: .continuous)
                    guard size.height >= 6 else { return }
                    for index in 1..<10 {
                        let x = (size.width * Double(index) / 10).rounded()
                        path.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: size.height))
                    }
                }
                .fill(style: FillStyle(eoFill: true))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// One macro on the watch face, in the family given (the widget passes the face's; the Watch app's
/// DEBUG gallery passes each in turn).
struct MacroComplication: View {
    let macro: ComplicationMacro
    let snapshot: WristSnapshot
    let family: WidgetFamily

    private var progress: MacroProgress { macro.progress(snapshot) }
    private var text: ComplicationText { ComplicationText(progress) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    /// The number with its unit under it in the macro's colour: "102" over "g P".
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -1) {
                Text(text.value)
                    .complicationNumeral(18)
                Text(text.short(macro))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(macro.color)
                    .widgetAccentable()
            }
            .padding(5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.sentence(macro))
    }

    /// Wrist up, small: the eyebrow, the number as the hero, and the ruler of what's eaten.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(macro == .kcal ? "Kcal \(text.word) today" : "Protein \(text.word)")
                .complicationEyebrow()
                .foregroundStyle(macro.color)
                .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text.value)
                    .complicationNumeral(26)
                Text(macro.unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let target = progress.target {
                    Spacer(minLength: 4)
                    Text("of \(Int(target.rounded()).formatted())")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = progress.fraction {
                ComplicationRuler(fraction: fraction, color: macro.color)
                    .padding(.top, 2)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.sentence(macro))
    }

    private var inline: some View {
        Label(text.sentence(macro), systemImage: macro.symbol)
    }

    /// The number in the corner, curved along it, and the ruler bent along the bezel.
    private var corner: some View {
        Text(text.value)
            .complicationNumeral(16)
            .widgetCurvesContent()
            .widgetLabel {
                if let fraction = progress.fraction {
                    Gauge(value: fraction) {
                        Text(macro.unit)
                    }
                    .tint(macro.color)
                } else {
                    Text(macro.unit)
                }
            }
            .accessibilityLabel(text.sentence(macro))
    }
}

/// Calories and protein left, each over its ruler: the Smart Stack's card.
struct TodayStackView: View {
    let snapshot: WristSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row(.kcal)
            row(.protein)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ComplicationText(snapshot.kcal).sentence(.kcal)), \(ComplicationText(snapshot.protein).sentence(.protein))")
    }

    private func row(_ macro: ComplicationMacro) -> some View {
        let progress = macro.progress(snapshot)
        let text = ComplicationText(progress)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text.value)
                    .complicationNumeral(19)
                Text("\(macro.unit) \(macro == .protein ? "protein " : "")\(text.word)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if let fraction = progress.fraction {
                ComplicationRuler(fraction: fraction, color: macro.color, height: 6)
            }
        }
    }
}

/// The running fast on the watch face: the hours over a ruler toward the goal, or between meals the
/// time since the last one toward the 3–5 hour band's end.
struct FastComplication: View {
    let snapshot: WristSnapshot
    let date: Date
    let family: WidgetFamily

    private var fast: FastStatus? { snapshot.fast(at: date) }
    private var since: Date? { snapshot.fastStart ?? snapshot.lastMealEnd }
    private var hours: Double { since.map { max(0, date.timeIntervalSince($0) / 3600) } ?? 0 }
    private var fraction: Double { min(1, hours / (fast?.fast.goalHours ?? 5)) }
    private var phase: FastPhase { fast?.phase ?? FastPhase.at(hours: hours) }
    /// A phase only for a fast started on purpose: a long gap without one may be meals not logged.
    private var symbol: String { fast == nil ? "fork.knife" : phase.symbol }
    private var short: String { hours < 1 ? "\(Int(hours * 60))m" : "\(Int(hours))h" }
    private var sentence: String {
        guard since != nil else { return "No meal logged to count from" }
        return fast == nil ? "\(short) since you ate" : "\(short) fasting, \(phase.title.lowercased())"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text(since == nil ? "–" : short)
                        .complicationNumeral(18)
                    ComplicationRuler(fraction: since == nil ? 0 : fraction, height: 3)
                        .frame(width: 24)
                }
                .padding(4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
        case .accessoryInline:
            Label(sentence, systemImage: symbol)
        case .accessoryCorner:
            Text(since == nil ? "–" : short)
                .complicationNumeral(16)
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: fraction) {
                        Text(fast == nil ? "since a meal" : phase.title.lowercased())
                    }
                    .tint(.accentColor)
                }
                .accessibilityLabel(sentence)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label(fast == nil ? "Since you ate" : phase.title, systemImage: symbol)
                    .complicationEyebrow()
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                if let since {
                    Text(since, style: .timer)
                        .complicationNumeral(26)
                }
                ComplicationRuler(fraction: since == nil ? 0 : fraction)
                    .padding(.top, 2)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
        }
    }
}

/// Your shape on the watch face: the six scores as one figure over the hexagon and its spokes,
/// clockwise from Strength at the top as the phone draws it, from what both apps publish. A score
/// not measured yet leaves its corner out; before any, the hexagon alone.
struct ShapeComplication: View {
    let shape: [StatKind: Int]?

    /// The phone's order (`ScoreShape.order` in the app's Stadig.swift).
    nonisolated static let order: [StatKind] = [.strength, .endurance, .agility, .vitality, .discipline, .physique]

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ZStack {
                ShapeOutline(scores: nil).stroke(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                ShapeOutline(scores: shape ?? [:], spokes: true).stroke(Color.primary.opacity(0.22), lineWidth: 0.9)
                ShapeOutline(scores: shape ?? [:]).fill(Color.accentColor.opacity(0.2)).widgetAccentable()
                ShapeOutline(scores: shape ?? [:])
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
                    .widgetAccentable()
            }
            .padding(5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your shape")
        .accessibilityValue(
            Self.order.map { "\($0.label) \(shape?[$0].map(String.init) ?? "not measured yet")" }.joined(separator: ", "))
    }
}

/// The hexagon (no scores), its spokes, or the figure through the scores given (three at least).
private nonisolated struct ShapeOutline: Shape {
    let scores: [StatKind: Int]?
    var spokes = false

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let point = { (index: Int, fraction: Double) -> CGPoint in
            let angle = (-90 + 60 * Double(index)) * .pi / 180
            return CGPoint(x: center.x + radius * fraction * cos(angle), y: center.y + radius * fraction * sin(angle))
        }
        var path = Path()
        if spokes {
            for index in 0..<6 {
                path.move(to: center)
                path.addLine(to: point(index, 1))
            }
        } else if let scores {
            let corners = ShapeComplication.order.enumerated().compactMap { index, stat in
                scores[stat].map { point(index, min(100, max(0, Double($0))) / 100) }
            }
            guard corners.count > 2 else { return path }
            path.addLines(corners)
            path.closeSubpath()
        } else {
            path.addLines((0..<6).map { point($0, 1) })
            path.closeSubpath()
        }
        return path
    }
}

/// Water so far on the watch face: the litres (or ounces) over a level that rises from the foot
/// toward the day's aim, as a glass fills.
struct WaterComplication: View {
    let water: MacroProgress?
    var fluidOunces = false
    let family: WidgetFamily

    /// "1.2" and "L", "41" and "oz"; a dash while water isn't tracked.
    private var amount: (value: String, unit: String) {
        guard let ml = water?.eaten else { return ("–", "") }
        if fluidOunces { return ("\(Int((ml / 29.5735).rounded()))", "oz") }
        return ((ml / 1000).formatted(.number.precision(.fractionLength(1))), "L")
    }

    private var sentence: String {
        guard let water else { return "Water isn't tracked" }
        let aim =
            fluidOunces
            ? "\(Int(((water.target ?? 0) / 29.5735).rounded())) oz"
            : "\(((water.target ?? 0) / 1000).formatted(.number.precision(.fractionLength(1)))) L"
        return "\(amount.value) \(amount.unit == "L" ? "litres" : "ounces") of water, of \(aim)"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(water == nil ? "Water isn't tracked" : "\(amount.value) \(amount.unit) water", systemImage: "drop.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.primary.opacity(0.3))
                        .frame(height: geometry.size.height * (water?.fraction ?? 0))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .widgetAccentable()
                }
                .clipShape(.circle)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(amount.value).complicationNumeral(14)
                    Text(amount.unit).font(.system(size: 10, weight: .bold))
                }
                .padding(.bottom, 12)
                .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
        }
    }
}
