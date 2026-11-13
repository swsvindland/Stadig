import LiftEngine
import SwiftUI
import SystemCore

/// The plain, low-key check-in at the end of a deload: tape measurements, mobility tests and a
/// conditioning benchmark. No boss fights.
struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var measuring = false
    @State private var values: [MobilityTest: Double] = [:]
    @State private var painful: Set<MobilityTest> = []
    @State private var benchmark: EnduranceBenchmark = .stairs10min
    @State private var benchmarkValue: Double?
    @State private var minutes = 8
    @State private var seconds = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        measuring = true
                    } label: {
                        if let last = model.measurements.last, last.day >= .today.adding(days: -7) {
                            Label("Measured \(Format.day(last.day))", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Add tape measurements", systemImage: "ruler")
                        }
                    }
                } header: {
                    Text("Tape").eyebrow()
                } footer: {
                    Text("The full set once a block: the next block's physique priorities and the left and right check come from it.")
                }
                Section {
                    Text("Take them fresh, the same way every time. Pain during a test means a physio, not more stretching.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(MobilityTest.allCases) { test in
                    Section(test.label) {
                        Text(test.instructions).font(.caption).foregroundStyle(.secondary)
                        switch test.measure {
                        case .quality:
                            Picker("Result", selection: Binding(get: { Int(values[test] ?? -1) }, set: { values[test] = $0 < 0 ? nil : Double($0) }))
                            {
                                Text("—").tag(-1)
                                ForEach(0..<4) { Text(MobilityTest.qualityLabels[$0]).tag($0) }
                            }
                        case .seconds, .centimetres:
                            HStack {
                                Text(test.measure == .seconds ? "Held" : "Distance")
                                Spacer()
                                TextField(
                                    "—", value: Binding(get: { values[test] }, set: { values[test] = $0 }),
                                    format: .number.precision(.fractionLength(0...1))
                                )
                                .fieldKeyboard(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(width: 80)
                                Text(test.unit).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(
                            "It hurt",
                            isOn: Binding(
                                get: { painful.contains(test) },
                                set: { on in
                                    if on { painful.insert(test) } else { painful.remove(test) }
                                }))
                        // Pain is kept with a result, so it needs one: what was managed, even none.
                        if painful.contains(test) && values[test] == nil {
                            Text(
                                test.measure == .quality
                                    ? "Pick what you managed (Can't counts) so the pain is recorded."
                                    : "Enter what you managed, even 0, so the pain is recorded."
                            )
                            .font(.caption).foregroundStyle(Ink.ok)
                        }
                    }
                }
                Section {
                    Picker("Test", selection: $benchmark) {
                        ForEach(EnduranceBenchmark.allCases) { Text($0.label).tag($0) }
                    }
                    Text(benchmark.instructions).font(.caption).foregroundStyle(.secondary)
                    switch benchmark.measure {
                    case .timeSeconds:
                        HStack {
                            Text("Time")
                            Spacer()
                            Picker("Minutes", selection: $minutes) { ForEach(3..<30) { Text("\($0) min").tag($0) } }.labelsHidden()
                            Picker("Seconds", selection: $seconds) { ForEach(0..<60) { Text("\($0) s").tag($0) } }.labelsHidden()
                        }
                    case .distanceMeters, .floors:
                        HStack {
                            Text(benchmark.measure == .floors ? "Floors" : "Metres")
                            Spacer()
                            TextField("—", value: $benchmarkValue, format: .number).fieldKeyboard(.number).multilineTextAlignment(.trailing).frame(
                                width: 90)
                        }
                    }
                    // Shows exactly what Save will do.
                    Toggle(
                        "Record it",
                        isOn: Binding(
                            get: { hasBenchmark },
                            set: {
                                recordTime = $0
                                if !$0 { benchmarkValue = nil }
                            }))
                } header: {
                    Text("Conditioning benchmark").eyebrow()
                } footer: {
                    Text("Every four weeks or so, the same test. A stalled benchmark puts intervals in the post-lift block.")
                }
            }
            .inkList()
            .navigationTitle("Check-in")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("checkIn.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).accessibilityIdentifier("checkIn.save")
                }
            }
            .onAppear { benchmark = model.settings.benchmark }
            // A value for one test means nothing for another: 80 floors aren't 80 metres.
            .onChange(of: benchmark) {
                benchmarkValue = nil
                recordTime = false
            }
            .sheet(isPresented: $measuring) { MeasurementEditor(measurements: BodyMeasurements(day: .today)) }
        }
        .sheetFrame()
    }

    @State private var recordTime = false

    private var hasBenchmark: Bool { benchmark.measure == .timeSeconds ? recordTime : benchmarkValue != nil }

    /// Something to save, and no pain flag that would be lost for want of a result.
    private var canSave: Bool { (!values.isEmpty || hasBenchmark) && !painful.contains { values[$0] == nil } }

    private func save() {
        let results = values.compactMap { test, value -> MobilityResult? in
            value < 0 ? nil : MobilityResult(test: test, day: .today, value: value, painful: painful.contains(test))
        }
        if !results.isEmpty { model.save(mobility: results) }
        if hasBenchmark {
            let value = benchmark.measure == .timeSeconds ? Double(minutes * 60 + seconds) : (benchmarkValue ?? 0)
            model.save(benchmark: BenchmarkResult(benchmark: benchmark, day: .today, value: value))
            if benchmark != model.settings.benchmark {
                var s = model.settings
                s.benchmark = benchmark
                model.save(settings: s)
            }
        }
        dismiss()
    }
}
