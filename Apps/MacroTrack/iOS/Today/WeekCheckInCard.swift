import NutritionEngine
import SwiftUI
import SystemCore

/// The week's check-in on Today, under what's left: the one moment a week the targets and the plan
/// are looked at, in sight rather than folded under the rest of the day (`CheckIns.shown`). A change
/// to the plan it found, with the way to it on Plan; else what it did to the targets and why, for a
/// couple of days, until it's put away.
struct WeekCheckInCard: View {
    @Environment(AppModel.self) private var model
    let check: WeekCheckIn

    var body: some View {
        Group {
            switch check {
            case .planCheck(let change): planCheck(change)
            case .targets(let checkIn, let previous): targets(checkIn, previous: previous)
            }
        }
        .inkCard(padding: 14, radius: 18)
        .transition(.opacity)
    }

    func planCheck(_ change: PhasePlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan check").eyebrow(Color.accentColor)
                Text(change.headline).font(.subheadline).foregroundStyle(Ink.text)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button("Review") { model.tab = .plan }
                .primaryAction().controlSize(.small)
                .accessibilityLabel("Review the plan change")
                .accessibilityIdentifier("today.planCheck")
        }
    }

    func targets(_ checkIn: CheckIn, previous: CheckIn?) -> some View {
        let change = Self.change(checkIn, previous: previous)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow(checkIn)).eyebrow(Color.accentColor)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.whole(checkIn.kcal)).numeral(24, weight: .heavy).foregroundStyle(Ink.text)
                    Text("kcal a day").font(.subheadline).foregroundStyle(Ink.text2)
                    Text(change.shown).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text2)
                }
                Text(checkIn.reason).font(.caption).foregroundStyle(Ink.text2)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(eyebrow(checkIn)): \(Format.kcal(checkIn.kcal)) a day, \(change.spoken). \(checkIn.reason)")
            .accessibilityIdentifier("today.checkIn")
            Spacer(minLength: 4)
            Button("Got it") { withAnimation(.snappy) { model.putAwayCheckIn() } }
                .secondaryAction().controlSize(.small)
                .accessibilityLabel("Put the check-in away")
                .accessibilityIdentifier("today.checkInPutAway")
        }
    }

    /// "Weekly check-in", and its day once it's not today's.
    func eyebrow(_ checkIn: CheckIn) -> String {
        checkIn.day == model.today ? "Weekly check-in" : "Weekly check-in · \(Format.day(checkIn.day, style: .dateTime.weekday(.wide)))"
    }

    /// What the check-in did to the calories: "−100" ("100 less"), or "holds".
    static func change(_ checkIn: CheckIn, previous: CheckIn?) -> (shown: String, spoken: String) {
        let delta = checkIn.kcal - (previous?.kcal ?? checkIn.kcal)
        guard abs(delta) >= 5 else { return ("holds", "holding") }
        let amount = Format.whole(abs(delta))
        return ("\(delta > 0 ? "+" : "−")\(amount)", "\(amount) \(delta > 0 ? "more" : "less")")
    }
}
