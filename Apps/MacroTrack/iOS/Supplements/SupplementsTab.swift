import FoodDatabase
import NutritionEngine
import SwiftUI
import SystemCore

/// The supplements as a sidebar destination: the stack in a list, and the selected one's label and
/// doses beside it, edited in place. Adding one (by barcode, name, a photo of the label or typed in)
/// happens in the same pane.
struct SupplementsTab: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var adding: AddSupplementView.Mode?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                list.frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                Divider()
                NavigationStack { detail }
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Supplements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        addButtons
                    } label: {
                        Label("Add a Supplement", systemImage: "plus")
                    }
                    .help("Add a supplement")
                    .accessibilityIdentifier("supplements.add")
                }
            }
        }
        .onChange(of: selection) { _, selected in if selected != nil { adding = nil } }
        // The first one, so the pane beside the list isn't empty.
        .onAppear { if selection == nil, adding == nil { selection = model.activeSupplements.first?.id } }
        // A supplement added: it's selected, in the list where it now is.
        .onChange(of: model.supplements.map(\.id)) { old, new in
            guard adding != nil, let added = new.first(where: { !old.contains($0) }) else { return }
            adding = nil
            selection = added
        }
    }

    var list: some View {
        List(selection: $selection) {
            if model.supplements.isEmpty {
                Section {
                    Text("Nothing in your stack yet. Add one with + to tick it off on Today and count it toward your vitamins and minerals.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section("Taking") {
                    ForEach(model.activeSupplements) { row($0) }
                }
                let paused = model.supplements.filter(\.paused)
                if !paused.isEmpty {
                    Section("Paused") { ForEach(paused) { row($0) } }
                }
                RemindersSection()
            }
        }
        .accessibilityIdentifier("supplements.list")
    }

    func row(_ supplement: Supplement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: supplement.facts.form.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(supplement.name).lineLimit(1)
                Text([supplement.facts.brand, supplement.scheduleLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .tag(supplement.id)
        .contextMenu {
            Button(supplement.paused ? "Resume" : "Pause", systemImage: supplement.paused ? "play" : "pause") {
                model.setPaused(!supplement.paused, supplement: supplement)
            }
            Button("Take One Now", systemImage: "checkmark.circle") { model.takeExtra(supplement) }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                if selection == supplement.id { selection = nil }
                model.delete(supplement: supplement.id)
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if let adding {
            AddSupplementView(mode: adding).id(adding)
        } else if let supplement = model.supplements.first(where: { $0.id == selection }) {
            SupplementEditor(supplement: supplement, isNew: false).id(supplement.id)
        } else {
            ContentUnavailableView {
                Label(model.supplements.isEmpty ? "Your supplements" : "No supplement selected", systemImage: "pills")
            } description: {
                Text(
                    model.supplements.isEmpty
                        ? "Type the bottle's barcode and its label comes from the NIH's database of US supplement labels, or read the Supplement Facts from a photo. Then say when you take it."
                        : "Select one to change its label or when you take it.")
            } actions: {
                addButtons
            }
        }
    }

    @ViewBuilder
    var addButtons: some View {
        Button(LiveLabelScanner.isAvailable ? "Scan the Bottle" : "Type the Barcode", systemImage: "barcode.viewfinder") { add(.scan) }
            .accessibilityIdentifier("supplements.menu.scan")
        Button("Search by Name", systemImage: "magnifyingglass") { add(.search) }
            .accessibilityIdentifier("supplements.menu.search")
        Button("Read a Photo of the Label", systemImage: "photo") { add(.label) }
            .accessibilityIdentifier("supplements.menu.photo")
        Button("Type It In", systemImage: "square.and.pencil") { add(.manual) }
            .accessibilityIdentifier("supplements.menu.manual")
    }

    func add(_ mode: AddSupplementView.Mode) {
        selection = nil
        adding = mode
    }
}
