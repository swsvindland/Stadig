import HubEngine
import SwiftUI
import SystemCore

/// A week split between the office and home: where each day is, the hours at the office, and the rest
/// of the working day at home either side of it. The commute comes from the card behind this.
struct HybridEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pattern: WorkPattern
    let monday: Day

    @State private var week: HybridWeek

    init(pattern: Binding<WorkPattern>, monday: Day) {
        _pattern = pattern
        self.monday = monday
        _week = State(initialValue: HybridWeek(pattern.wrappedValue) ?? .standard)
    }

    private var officeDayMinutes: Int { week.officeEnd - week.officeStart + week.homeBefore + week.homeAfter }

    var body: some View {
        Form {
            Section("Where each day is") {
                ForEach(Weekday.allCases) { weekday in
                    LabeledContent(weekday.name) {
                        Picker(weekday.name, selection: $week.days[weekday.rawValue - 1]) {
                            ForEach(HybridWeek.Place.allCases) { place in
                                Text(place.label).tag(place)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)
                    }
                    .accessibilityIdentifier("hybrid.day.\(weekday.short)")
                }
            }
            Section {
                ClockField(title: "At the office from", minutes: $week.officeStart)
                    .accessibilityIdentifier("hybrid.officeStart")
                ClockField(
                    title: "Until",
                    minutes: Binding(get: { week.officeEnd }, set: { week.officeEnd = max($0, week.officeStart + 15) })
                )
                .accessibilityIdentifier("hybrid.officeEnd")
                Stepper("At home before: \(hours(week.homeBefore))", value: $week.homeBefore, in: 0...480, step: 30)
                    .accessibilityIdentifier("hybrid.before")
                Stepper("At home after: \(hours(week.homeAfter))", value: $week.homeAfter, in: 0...480, step: 30)
                    .accessibilityIdentifier("hybrid.after")
            } header: {
                Text("Office days")
            } footer: {
                Text("\(hours(officeDayMinutes)) of work on an office day.")
            }
            Section {
                ClockField(title: "From", minutes: $week.homeStart)
                    .accessibilityIdentifier("hybrid.homeStart")
                ClockField(
                    title: "Until",
                    minutes: Binding(get: { week.homeEnd }, set: { week.homeEnd = max($0, week.homeStart + 15) })
                )
                .accessibilityIdentifier("hybrid.homeEnd")
            } header: {
                Text("Home days")
            } footer: {
                Text("\(hours(week.weeklyMinutes)) of work a week.")
                    .accessibilityIdentifier("hybrid.total")
            }
        }
        .navigationTitle("Hybrid week")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    pattern = week.pattern(anchor: monday, commute: pattern.commuteMinutes)
                    dismiss()
                }
                .disabled(!week.isValid)
                .accessibilityIdentifier("hybrid.done")
            }
        }
    }

    private func hours(_ minutes: Int) -> String { minutes == 0 ? "none" : HubText.length(minutes) }
}
