import NutritionEngine
import SwiftUI
import SystemCore

/// Beside the week: the selected day, its calories as the hero over a tall ruler to maintenance,
/// its protein, carbs and fat against their targets, and its meals. With a meal held over a day,
/// that day as it would be if it were let go there, and what changes, in words.
struct WeekInspector: View {
    let day: WeekDay
    let board: WeekBoard
    let move: WeekMove?
    let open: (Day) -> Void

    var body: some View {
        let before = move.flatMap { $0.before.day(day.day) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow).eyebrow(move != nil || day.timing == .today ? Color.accentColor : Ink.text3)
                    Text(Format.day(day.day, style: .dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(Ink.text)
                        .accessibilityAddTraits(.isHeader)
                }
                DayHero(day: day, before: before, full: full)
                // Today what's eaten, as the hero says; any other day all of it.
                let macros = day.timing == .today && move == nil ? day.eaten : day.total
                HStack(alignment: .top, spacing: 14) {
                    // How far off only says something once there's food on the day.
                    let off = day.hasFood || day.timing == .today
                    MacroCell(macro: .protein, value: macros.protein, target: day.target?.protein, showsOff: off)
                    MacroCell(macro: .carbs, value: macros.carbs, target: day.target?.carbs, showsOff: off)
                    MacroCell(macro: .fat, value: macros.fat, target: day.target?.fat, showsOff: off)
                }
                if let move { WhatChanges(move: move, full: full) }
                DayMeals(day: day, move: move)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .pinnedBar(.bottom) { foot }
        .inkGround()
        .accessibilityIdentifier("week.inspector")
    }

    var eyebrow: String {
        if move != nil { return "If you drop here" }
        switch day.timing {
        case .today: return "Today"
        case .past: return "Eaten"
        case .ahead: return "Planned"
        }
    }

    /// The tall ruler's length: maintenance, unless the day (or the target) goes past it.
    var full: Double {
        let before = move.flatMap { $0.before.day(day.day)?.total.kcal } ?? 0
        let furthest = max(board.maintenance ?? 0, day.target?.kcal ?? 0, day.total.kcal, before)
        return furthest > 0 ? furthest : 2500
    }

    /// How the desk is worked, and the way into the day's log.
    var foot: some View {
        VStack(alignment: .leading, spacing: 9) {
            if move == nil {
                Button("Open in Log") { open(day.day) }
                    .buttonStyle(.ghost)
                    .controlSize(.small)
                    .help("Open this day in Log (Return)")
                    .accessibilityIdentifier("week.openInLog")
            }
            Text(hint).font(.caption).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            if Platform.isMac {
                HStack(spacing: 6) {
                    if move == nil {
                        KeyCap("↩")
                        Text("open in Log").font(.caption).foregroundStyle(Ink.text3).padding(.trailing, 8)
                        KeyCap("⌘Z")
                        Text("undo a move").font(.caption).foregroundStyle(Ink.text3)
                    } else {
                        KeyCap("esc")
                        Text("put it back").font(.caption).foregroundStyle(Ink.text3).padding(.trailing, 8)
                        KeyCap("⌘Z")
                        Text("undo after").font(.caption).foregroundStyle(Ink.text3)
                    }
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.pageBackground)
    }

    var hint: String {
        if move != nil { return "Let go to move it here, each food at its own time of day." }
        return Platform.isMac ? "Drag a meal onto another day to move it there." : "Hold a meal, then drag it onto another day to move it there."
    }
}

/// The day's calories as the hero: what's eaten today (with what's left and what's to come), what
/// was eaten on a day gone, what's planned on one ahead; over a tall ruler in fifths to maintenance,
/// the target marked.
private struct DayHero: View {
    let day: WeekDay
    let before: WeekDay?
    let full: Double

    var body: some View {
        let target = day.target?.kcal
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.whole(hero)).numeral(66, weight: .heavy).foregroundStyle(Ink.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(unit).font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.text2)
                    Text(note).font(.caption).foregroundStyle(Ink.text3)
                }
                .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 5) {
                Ruler(value: shownFill / full, color: .accentColor, height: 28, divisions: 5, marker: target.map { $0 / full })
                    .overlay(alignment: .leading) { span }
                    .accessibilityLabel("\(Format.whole(day.total.kcal)) of \(Format.whole(target ?? full))")
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ScaleLabel("0")
                        ScaleLabel(Format.whole(full)).frame(maxWidth: .infinity, alignment: .trailing)
                        if let target {
                            ScaleLabel("Target \(Format.whole(target))", highlighted: true)
                                .fixedSize()
                                .frame(width: proxy.size.width * min(1, target / full), alignment: .trailing)
                        }
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)
            }
        }
    }

    /// Today, what's eaten, unless a meal's held over it; any other day, all of it.
    var hero: Double { day.timing == .today && before == nil ? day.eaten.kcal : day.total.kcal }

    /// The ruler's full fill: what's eaten today, all of it on any other day.
    var shownFill: Double { hero }

    var unit: String {
        if day.timing == .past { return "kcal eaten" }
        if day.timing == .today && before == nil { return "kcal eaten" }
        return "kcal planned"
    }

    var note: String {
        if let before { return "was \(Format.whole(before.total.kcal))" }
        let standing: String? =
            switch day.standing {
            case .left(let kcal): "\(Format.whole(kcal)) left"
            case .under(let kcal): "\(Format.whole(kcal)) under"
            case .over(let kcal): "\(Format.whole(kcal)) over"
            case nil: nil
            }
        if day.timing == .today, day.ahead.kcal > 0 {
            return [standing, "\(Format.whole(day.ahead.kcal)) to come"].compactMap(\.self).joined(separator: " · ")
        }
        if let standing { return standing }
        if day.hasFood { return day.target?.kcal == nil ? "No calorie target that day" : "" }
        return day.timing == .past ? "Nothing logged" : "Nothing planned yet"
    }

    /// What's to come today, lighter past what's eaten; during a move, what goes (lighter) or a
    /// tick where the day was.
    @ViewBuilder
    var span: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if let before {
                let was = min(1, before.total.kcal / full)
                let now = min(1, day.total.kcal / full)
                if now < was {
                    Rectangle().fill(Color.accentColor.opacity(0.3)).frame(width: width * (was - now)).offset(x: width * now)
                } else {
                    Rectangle().fill(Ink.text.opacity(0.6)).frame(width: 2).offset(x: width * was - 1)
                }
            } else if day.timing == .today, day.ahead.kcal > 0 {
                let eaten = min(1, day.eaten.kcal / full)
                let total = min(1, day.total.kcal / full)
                Rectangle().fill(Color.accentColor.opacity(0.35)).frame(width: width * (total - eaten)).offset(x: width * eaten)
            }
        }
        .clipShape(.rect(cornerRadius: 7, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// One macro under the hero: its grams, a thin ruler to its target, and how far off it is.
private struct MacroCell: View {
    let macro: Macro
    let value: Double
    let target: Double?
    let showsOff: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(macro.label).font(.caption).foregroundStyle(Ink.text3)
            Text(
                "\(Text(Format.whole(value)).font(.system(size: 17, weight: .bold)).foregroundStyle(Ink.text))\(Text(" g").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Ink.text2))"
            )
            .monospacedDigit()
            .lineLimit(1)
            Ruler.thin(target.map { $0 > 0 ? value / $0 : 0 } ?? 0, color: macro.color)
            if let target, showsOff {
                Text("\(Self.signed(value - target)) · of \(Format.whole(target))")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.text3)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.label): \(Format.grams(value))\(target.map { " of \(Format.grams($0))" } ?? "")")
    }

    /// "−11", "+27": how far from the target, in whole grams.
    static func signed(_ grams: Double) -> String {
        let whole = Int(grams.rounded())
        return whole > 0 ? "+\(whole.formatted())" : whole < 0 ? "−\((-whole).formatted())" : "0"
    }
}

/// During a move: what it does to both days and to the week, in a sentence, with each day's ruler
/// from what it was to what it would be.
private struct WhatChanges: View {
    let move: WeekMove
    let full: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What changes").eyebrow()
            Text(move.changes).font(.system(size: 14)).lineSpacing(3).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 7) {
                ForEach([move.to, move.from], id: \.self) { day in
                    if let before = move.before.day(day), let after = move.after.day(day) {
                        ChangeRow(day: day, was: before.total.kcal, now: after.total.kcal, full: full)
                    }
                }
            }
            .padding(.top, 2)
        }
        .card(padding: 14, radius: 18)
        .accessibilityElement(children: .combine)
    }
}

private struct ChangeRow: View {
    let day: Day
    let was: Double
    let now: Double
    let full: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(Format.day(day, style: .dateTime.weekday(.abbreviated)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.text2)
                .frame(width: 30, alignment: .leading)
            Ruler(value: now / full, color: now < was ? .accentColor : Color.accentColor.opacity(0.45), height: 10, divisions: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        let low = min(was, now) / full
                        let high = min(1, max(was, now) / full)
                        Rectangle()
                            .fill(now < was ? Color.accentColor.opacity(0.3) : Color.accentColor)
                            .frame(width: max(0, proxy.size.width * (high - low)))
                            .offset(x: proxy.size.width * low)
                    }
                    .clipShape(.rect(cornerRadius: 3, style: .continuous))
                }
            Text("\(Format.whole(was)) → \(Text(Format.whole(now)).fontWeight(.bold).foregroundStyle(Ink.text))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Ink.text3)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
    }
}

/// The day's meals, a row each: what it is, when, and its calories; during a move, the one landing
/// in the accent with where it's from.
private struct DayMeals: View {
    let day: WeekDay
    let move: WeekMove?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionEyebrow("\(Format.day(day.day, style: .dateTime.weekday(.wide)))'s meals", detail: day.meals.isEmpty ? nil : "\(day.meals.count)")
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            if day.meals.isEmpty {
                Text(day.timing == .past ? "Nothing logged." : "Nothing planned yet.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.text3)
                    .padding(.horizontal, 6)
            }
            ForEach(day.meals) { meal in
                MealRow(meal: meal, from: move?.holdsMoved(meal) == true ? move?.from : nil)
            }
        }
    }
}

private struct MealRow: View {
    let meal: WeekMeal
    let from: Day?

    var body: some View {
        HStack(spacing: 10) {
            Text(meal.markers.first ?? FoodMarker.unknown)
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .background(Ink.raised, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(meal.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(meal.isAhead ? Ink.text2 : Ink.text)
                Text("\(Format.time(meal.start))\(Text(detail).foregroundStyle(from != nil ? Ink.words(.accentColor) : Ink.text3))")
                    .font(.caption)
                    .foregroundStyle(Ink.text3)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Text(Format.whole(meal.nutrients.kcal))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(meal.isAhead ? Ink.text2 : Ink.text)
        }
        .frame(minHeight: 42)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .background(from != nil ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    var detail: String {
        if let from { return " · from \(Format.day(from, style: .dateTime.weekday(.abbreviated)))" }
        switch meal.kind {
        case .eaten: return ""
        case .later: return " · later"
        case .planned: return " · meal plan"
        }
    }
}

/// A key on the keyboard, as the hints show it (`.key`).
private struct KeyCap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Ink.text2)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Ink.raised, in: .rect(cornerRadius: 7, style: .continuous))
    }
}
