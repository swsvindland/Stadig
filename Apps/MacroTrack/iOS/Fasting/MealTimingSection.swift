import NutritionEngine
import SwiftUI
import SystemCore

/// Today's clock, for people who turned meal timing on: the running fast as a ring toward its
/// goal with its phase, or the time since the last meal against the 3–5 hour band, with the night's
/// fast below it.
struct MealTimingSection: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        if model.tracksMealTiming, let analysis = model.analysis {
            if day == model.today {
                Section {
                    if let status = analysis.fast {
                        FastRow(status: status)
                    } else {
                        SinceLastMealRow(lastMeal: analysis.lastMeal)
                    }
                    if let overnight = analysis.eatingToday?.overnight {
                        OvernightLine(gap: overnight)
                    }
                } header: {
                    Text(analysis.fast == nil ? "Meal timing" : "Fasting")
                }
            } else if let overnight = model.eating(on: day)?.overnight {
                Section {
                    OvernightLine(gap: overnight)
                }
            }
        }
    }
}

/// The running fast: a ring toward the goal, how long, the phase and what comes next.
struct FastRow: View {
    @Environment(AppModel.self) private var model
    let status: FastStatus

    var body: some View {
        TimelineView(.periodic(from: status.fast.start, by: 60)) { context in
            let now = Fasting.status(status.fast, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(value: now.hours, target: status.fast.goalHours, color: .teal, lineWidth: 11)
                        VStack(spacing: 0) {
                            Text(Format.duration(now.elapsed)).font(.headline.monospacedDigit()).minimumScaleFactor(0.6)
                            Text("of \(Format.goal(status.fast.goalHours))").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(now.phase.title, systemImage: now.phase.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                        Text(now.phase.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)
                        if now.goalReached {
                            Pill(text: "Goal reached", symbol: "checkmark", color: .green)
                        } else if let next = now.phase.next, let at = now.nextPhaseAt, at < status.fast.goalEnd.addingTimeInterval(1) {
                            Text("\(next.title) from \(Format.moment(at, now: context.date))").font(.caption.weight(.medium))
                        } else {
                            Text("Goal at \(Format.moment(status.fast.goalEnd, now: context.date))").font(.caption.weight(.medium))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.fast")
                HStack(spacing: 8) {
                    Button("End fast") { model.endFast() }
                        .buttonStyle(.borderedProminent).tint(.teal).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("today.endFast")
                    Button("Details") { model.showFast = true }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("today.fastDetails")
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Since the last meal, against the 3–5 hour band; past 12 hours, the fast it's become.
struct SinceLastMealRow: View {
    @Environment(AppModel.self) private var model
    let lastMeal: Moment?

    var body: some View {
        HStack(spacing: 12) {
            if let lastMeal {
                TimelineView(.periodic(from: lastMeal.end, by: 60)) { context in
                    let elapsed = context.date.timeIntervalSince(lastMeal.end)
                    let band = GapBand.of(elapsed)
                    HStack(spacing: 12) {
                        ProgressRing(value: elapsed / 3600, target: 5, color: band.color, lineWidth: 5)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Format.duration(elapsed)) since your last \(elapsed >= Self.unconfirmed ? "logged " : "")meal")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(caption(elapsed, band: band)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.sinceLastMeal")
                }
            } else {
                Image(systemName: "timer").foregroundStyle(.teal).frame(width: 34)
                Text("Log a meal and the time since it shows here.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Start fast") { model.showFast = true }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.teal).font(.subheadline)
                .fixedSize()
                .accessibilityLabel("Start a fast")
                .accessibilityIdentifier("today.startFast")
        }
    }

    /// Past this with no fast started, the gap may only be meals not logged: no phase is named for it.
    static let unconfirmed: TimeInterval = 12 * 3600

    func caption(_ elapsed: TimeInterval, band: GapBand) -> String {
        guard let lastMeal else { return "" }
        let at = Format.moment(lastMeal.end)
        if elapsed >= Self.unconfirmed { return "Nothing logged since \(at). Fasting? Start a fast to follow its phases." }
        switch band {
        case .close, .short: return "Ended \(at) · 3–5 hours between meals lets things settle"
        case .spaced: return "Ended \(at) · in the 3–5 hour band"
        case .long: return "Ended \(at) · past 5 hours"
        }
    }
}

/// "Overnight fast 13 h · 8:05 PM to 9:10 AM".
struct OvernightLine: View {
    let gap: MealGap

    var body: some View {
        Label {
            Text("Overnight fast \(Format.duration(gap.duration)) · \(Format.moment(gap.from, now: gap.to)) to \(Format.time(gap.to))")
                .font(.subheadline)
        } icon: {
            Image(systemName: "moon.stars").foregroundStyle(.indigo)
        }
        .accessibilityIdentifier("today.overnight")
    }
}

/// "+3 h 20 m" before a meal, coloured by its band: grazing in orange, 3–5 hours in green.
struct GapBadge: View {
    let gap: MealGap

    var body: some View {
        Text("+\(Format.duration(gap.duration))")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(gap.band.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(gap.band.color.opacity(0.14), in: .capsule)
            .accessibilityLabel("\(Format.duration(gap.duration)) after the meal before, \(gap.band.label)")
            .help(gap.band.label)
    }
}

extension GapBand {
    var color: Color {
        switch self {
        case .close: .orange
        case .short, .long: .secondary
        case .spaced: .green
        }
    }

    /// The same, solid enough to fill a bar.
    var barColor: Color {
        switch self {
        case .close: .orange
        case .short: .gray.opacity(0.45)
        case .spaced: .green
        case .long: .gray.opacity(0.7)
        }
    }
}

extension AppModel {
    /// The gap before each of a day's meals that follows another that day, by the meal's moment
    /// id; empty while meal timing is off or the day's log isn't trusted.
    func gapsBefore(on day: Day) -> [UUID: MealGap] {
        guard tracksMealTiming, let eating = eating(on: day) else { return [:] }
        var gaps: [UUID: MealGap] = [:]
        for (meal, gap) in zip(eating.meals.dropFirst(), eating.gaps) { gaps[meal.id] = gap }
        return gaps
    }
}
