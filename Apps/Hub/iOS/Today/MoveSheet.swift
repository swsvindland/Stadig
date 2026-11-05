import HubEngine
import SwiftUI
import SystemCore

/// A class or the gym in another part of the day, this once or every week. What's on stays Stadig
/// Lift's to say; when it sits is the hub's.
struct MoveSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: HubItem
    let day: Day

    @State private var part: DayPart
    @State private var everyWeek = true

    init(item: HubItem, day: Day) {
        self.item = item
        self.day = day
        _part = State(initialValue: item.part)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Which classes you do stays in Stadig Lift.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(DayPart.allCases) { option in
                        Button {
                            part = option
                        } label: {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(option == part ? AnyShapeStyle(Color.strongFill) : AnyShapeStyle(.cardBackground), in: .capsule)
                                .foregroundStyle(option == part ? AnyShapeStyle(Color.onStrongFill) : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                        .hoverable(in: .capsule)
                        .accessibilityAddTraits(option == part ? .isSelected : [])
                        .accessibilityIdentifier("move.part.\(option.rawValue)")
                    }
                }
                Picker("How often", selection: $everyWeek) {
                    Text("Just this \(day.weekday.name)").tag(false)
                    Text("Every \(day.weekday.name)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("move.scope")
                Spacer(minLength: 0)
                if model.isMoved(item, on: day) {
                    Button("Put it back") {
                        model.putBack(item, on: day)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("move.back")
                }
                Button {
                    model.move(item, on: day, to: part, everyWeek: everyWeek)
                    dismiss()
                } label: {
                    Text("Move it").frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryAction()
                .accessibilityIdentifier("move.save")
            }
            .padding(16)
            .navigationTitle(item.title)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        // A solid sheet: on the see-through default, the selected part's ink fades to grey.
        .presentationBackground(Color.groupedBackground)
        .sheetForm(width: 420, height: 380)
    }
}
