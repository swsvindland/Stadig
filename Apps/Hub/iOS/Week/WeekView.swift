import HubEngine
import SwiftUI
import SystemCore

/// The shape of a week: a bar for each day. Tap one to see it.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsNext = false

    private var week: HubWeek? { showsNext ? model.nextWeek : model.thisWeek }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Week", selection: $showsNext) {
                        Text("This week").tag(false)
                        Text("Next week").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("week.which")
                    if let week {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeClass == .regular ? 4 : 2), spacing: 8) {
                            Metric(label: "Gym", value: "\(week.gym)")
                            Metric(label: "Study blocks", value: "\(week.study)")
                            Metric(label: "Free time", value: HubText.length(HubText.rough(week.freeMinutes)))
                            Metric(label: "Clear evenings", value: "\(week.clearEvenings)")
                        }
                        VStack(spacing: 0) {
                            ForEach(week.days) { day in
                                DayBar(day: day) {
                                    guard !showsNext else { return }
                                    model.selectedDay = day.day
                                    model.tab = .today
                                }
                            }
                        }
                        .card(padding: 10, radius: 18)
                        Legend()
                        if week.leftovers > 0 {
                            Text(week.leftovers == 1 ? "1 block doesn't fit this week." : "\(week.leftovers) blocks don't fit this week.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("week.leftovers")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .pageWidth(sizeClass)
            }
            .background(.pageBackground)
            .navigationTitle(showsNext ? "Next week" : "This week")
        }
    }
}

struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .card(padding: 12, radius: 16)
        .accessibilityElement(children: .combine)
    }
}

/// A day's bar: what's on it in order, on a track the length of a waking day, so a full day looks
/// full and the rest is plainly room.
struct DayBar: View {
    /// Sixteen waking hours.
    static let track = 16 * 60

    let day: HubDay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(day.day.weekday.short)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, alignment: .leading)
                GeometryReader { proxy in
                    HStack(spacing: 1) {
                        ForEach(Array(day.bar.enumerated()), id: \.offset) { _, segment in
                            segment.kind.color
                                .frame(width: proxy.size.width * Double(segment.minutes) / Double(max(Self.track, total)))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 18)
                .background(.insetBackground)
                .clipShape(.capsule)
                Text(HubText.shortFree(day.freeMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .trailing)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.day.weekday.name), \(HubText.summary(day))")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("week.day.\(day.day.weekday.short)")
    }

    private var total: Int { day.bar.map(\.minutes).reduce(0, +) }
}

struct Legend: View {
    private static let kinds: [HubItem.Kind] = [.lift, .activity, .meal, .study, .work, .commute]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(Self.kinds, id: \.self) { kind in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(kind.color).frame(width: 10, height: 10)
                    Text(kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}
