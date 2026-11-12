import SwiftUI
import SystemCore
import WidgetKit

@main
struct LiftTrackWidgets: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
        #if os(iOS)
        SessionLiveActivity()
        #endif
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads timelines when the plan changes. Each entry reads the snapshot for its own
        // day, so the one at midnight turns "Next: Tuesday" into "Today" with the app closed.
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let snapshot = WidgetSnapshot.load()
        completion(
            Timeline(
                entries: [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)],
                policy: .after(midnight)))
    }
}

/// The next session at a glance; tapping it opens Stadig Lift ready to start.
struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-session", provider: SnapshotProvider()) { entry in
            NextSessionView(snapshot: entry.snapshot.reading(on: Day(entry.date)))
                .widgetURL(URL(string: "lifttrack://start"))
                .inkWidgetBackground()
        }
        .configurationDisplayName("Next Session")
        .description("Your next session, one tap from starting.")
        .supportedFamilies(Self.families)
    }

    /// The Lock Screen's accessory families are the iPhone's and iPad's; the Mac's desktop and Vision
    /// Pro's walls take the small and medium ones.
    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View { NextSessionFace(snapshot: snapshot, family: family) }
}

/// The widget in the family given: the widget passes the system's.
struct NextSessionFace: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            Text("\(snapshot.title) · \(snapshot.detail)")
        case .accessoryCircular:
            NextSessionCircular(snapshot: snapshot)
        case .accessoryRectangular:
            NextSessionRectangular(snapshot: snapshot)
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                NextSessionSummary(snapshot: snapshot)
                if !snapshot.exercises.isEmpty {
                    NextSessionExercises(exercises: snapshot.exercises)
                }
            }
        default:
            NextSessionSummary(snapshot: snapshot)
        }
    }
}

extension WidgetSnapshot {
    /// Whether the session shown is today's (`reading(on:)` says so), so its segment of the week is
    /// the one waiting.
    var isToday: Bool { detail == "Today" }

    /// "Today · ~57 min", "Next: Thursday · ~60 min".
    var whenLine: String {
        [detail, minutes.map { "~\($0) min" }].compactMap(\.self).joined(separator: " · ")
    }
}

/// The session's name as the hero, when it is ("Today · ~57 min") under it, and this week's sessions
/// as a strip.
struct NextSessionSummary: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let badge = snapshot.badge {
                Text(badge).eyebrow().minimumScaleFactor(0.8).foregroundStyle(.tint).widgetAccentable()
            } else {
                Text("Next session").eyebrow().ink(.tertiary)
            }
            Text(snapshot.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-1.1)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .ink(.primary)
                .padding(.top, 6)
            Text(snapshot.whenLine)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .ink(.secondary)
                .padding(.top, 3)
            Spacer(minLength: 8)
            if snapshot.plannedThisWeek > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").eyebrow(size: 10).ink(.tertiary)
                    Spacer(minLength: 4)
                    Text("\(snapshot.doneThisWeek) of \(snapshot.plannedThisWeek)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .ink(.secondary)
                }
                WeekStrip(done: snapshot.doneThisWeek, planned: snapshot.plannedThisWeek, today: snapshot.isToday, height: 8)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// What's in the session, numbered, beside the summary on the medium widget.
struct NextSessionExercises: View {
    let exercises: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In it").eyebrow().ink(.tertiary)
                .padding(.bottom, 4)
            ForEach(exercises.prefix(5).enumerated(), id: \.offset) { index, name in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .ink(.tertiary)
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .ink(.primary)
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// The Lock Screen's line under the clock: the session, how long, and the week as a strip.
struct NextSessionRectangular: View {
    let snapshot: WidgetSnapshot

    private var line: String {
        let parts =
            snapshot.isToday ? [snapshot.minutes.map { "\($0) min" }, snapshot.badge] : [snapshot.detail, snapshot.minutes.map { "\($0) min" }]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.isToday ? "\(snapshot.title) today" : snapshot.title)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
            Text(line)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if snapshot.plannedThisWeek > 0 {
                WeekStrip(done: snapshot.doneThisWeek, planned: snapshot.plannedThisWeek, today: snapshot.isToday, color: .primary)
                    .frame(maxWidth: 164)
                    .padding(.top, 5)
            } else if !snapshot.exercises.isEmpty {
                Text(snapshot.exercises.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(snapshot.doneThisWeek) of \(snapshot.plannedThisWeek) sessions this week"))
    }
}

/// Sessions done this week, as a number over the week's strip.
struct NextSessionCircular: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if snapshot.plannedThisWeek > 0 {
                VStack(spacing: 1) {
                    Text("\(snapshot.doneThisWeek)")
                        .numeral(24)
                    Text("of \(snapshot.plannedThisWeek)")
                        .eyebrow(size: 9)
                        .foregroundStyle(.secondary)
                    WeekStrip(
                        done: snapshot.doneThisWeek, planned: snapshot.plannedThisWeek, today: snapshot.isToday, height: 4, color: .primary
                    )
                    .frame(width: 32)
                    .padding(.top, 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(snapshot.doneThisWeek) of \(snapshot.plannedThisWeek) sessions this week"))
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "dumbbell.fill")
                        .font(.body)
                        .widgetAccentable()
                    if let minutes = snapshot.minutes {
                        Text("\(minutes)m").font(.caption2.weight(.semibold)).monospacedDigit()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(snapshot.title), \(snapshot.detail)"))
            }
        }
    }
}
#endif
