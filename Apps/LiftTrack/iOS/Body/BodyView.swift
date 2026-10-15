import SwiftUI
import PhotosUI
import Charts
import LiftEngine
import SystemCore

/// Physique on a mesocycle cadence: tape measurements, the ratios that matter, gaps and what
/// the program does about them, and progress photos for your own comparison. Trends and next
/// steps, never appearance.
struct BodyView: View {
    @Environment(AppModel.self) private var model
    @State private var measuring = false
    @State private var editing: BodyMeasurements?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pose: ProgressPhoto.Pose = .front

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let physique = model.analysis?.physique {
                        overview(physique)
                        if !physique.gaps.isEmpty { gaps(physique) }
                    }
                    waistTrend
                    photos
                    history
                }
                .padding()
                .readableWidth()
            }
            .background(.pageBackground)
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { measuring = true } label: { Image(systemName: "ruler") }.accessibilityLabel("Add measurements")
                }
            }
            .sheet(isPresented: $measuring) { MeasurementEditor(measurements: BodyMeasurements(day: .today)) }
            .sheet(item: $editing) { m in MeasurementEditor(measurements: m) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
        }
    }

    private func overview(_ p: PhysiqueAnalysis) -> some View {
        let length = model.units.length
        return VStack(alignment: .leading, spacing: 12) {
            Label("Physique", systemImage: StatKind.physique.symbol).font(.headline).foregroundStyle(StatKind.physique.color)
            if p.latest == nil {
                Text("Measure shoulders, waist, arms and thighs once a block. It takes two minutes with a tape.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { measuring = true } label: { Label("Add measurements", systemImage: "ruler").frame(maxWidth: .infinity) }.primaryAction()
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    if let ratio = p.shoulderToWaist {
                        GridRow {
                            Text("Shoulder to waist").foregroundStyle(.secondary)
                            Text(Format.number(ratio, digits: 2)).monospacedDigit()
                            Text("target \(Format.number(Physique.shoulderToWaistTarget(model.profile?.sex ?? .unspecified), digits: 2))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let wth = p.waistToHeight {
                        GridRow {
                            Text("Waist to height").foregroundStyle(.secondary)
                            Text(Format.number(wth, digits: 2)).monospacedDigit()
                            Text("under 0.50 is healthy").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let bf = p.bodyFatPercent {
                        GridRow {
                            Text("Body fat").foregroundStyle(.secondary)
                            Text("\(Format.number(bf))%").monospacedDigit()
                            Text(p.bodyFatEstimated ? "tape estimate, a soft signal" : "measured").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let latest = p.latest {
                        GridRow {
                            Text("Waist").foregroundStyle(.secondary)
                            Text(Format.length(latest.waistCm, unit: length))
                            Text(p.waistTrend.map { "\($0 > 0 ? "+" : "")\(Format.length($0, unit: length)) since first" } ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func gaps(_ p: PhysiqueAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the program does about it").font(.headline)
            ForEach(p.gaps) { gap in
                VStack(alignment: .leading, spacing: 2) {
                    Text(gap.region.label).font(.subheadline.weight(.semibold))
                    Text(gap.finding).font(.caption).foregroundStyle(.secondary)
                    Label(gap.action, systemImage: "arrow.right.circle").font(.caption)
                }
            }
            if model.settings.autoPrioritise == false {
                Text("Auto-prioritisation is off, so the next block won't act on these.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private var waistTrend: some View {
        let points = model.measurements.compactMap { m in m.waistCm.map { (m.day.date(), model.units.length.fromCentimetres($0)) } }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waist").font(.headline)
                Chart(points, id: \.0) { point in
                    LineMark(x: .value("Day", point.0), y: .value("Waist", point.1))
                    PointMark(x: .value("Day", point.0), y: .value("Waist", point.1)).symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(model.units.length.symbol)
                .frame(height: 140)
            }
            .card()
        }
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress photos").font(.headline)
                Spacer()
                Picker("Pose", selection: $pose) {
                    ForEach(ProgressPhoto.Pose.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
                PhotosPicker(selection: $pickerItem, matching: .images) { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Add a progress photo")
            }
            let shown = model.photos.filter { $0.pose == pose }
            if shown.isEmpty {
                Text("For your own comparison only. Photos are never analysed or used as a measure.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                if let first = shown.first, let last = shown.last, first.id != last.id {
                    HStack(spacing: 8) {
                        photo(first)
                        photo(last)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shown) { p in
                            photo(p).frame(width: 90, height: 120)
                                .contextMenu { Button("Delete", role: .destructive) { model.delete(photo: p.id) } }
                        }
                    }
                }
            }
        }
        .card()
    }

    private func photo(_ p: ProgressPhoto) -> some View {
        VStack(spacing: 4) {
            if let image = UIImage(data: p.jpeg) {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, minHeight: 120, maxHeight: 240).clipped()
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("Progress photo, \(Format.day(p.day))")
            }
            Text(Format.day(p.day, style: .dateTime.month(.abbreviated).day().year())).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.measurements.isEmpty { SectionHeader(title: "Measurements") }
            ForEach(model.measurements.reversed()) { m in
                Button { editing = m } label: {
                    HStack {
                        Text(Format.day(m.day, style: .dateTime.month(.abbreviated).day().year())).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text([m.waistCm.map { "waist \(Format.length($0, unit: model.units.length))" },
                              m.shouldersCm.map { "shoulders \(Format.length($0, unit: model.units.length))" },
                              m.weightKg.map { Format.weight($0, unit: model.units.weight) }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        // Downscale: comparison doesn't need full resolution, and it keeps sync light.
        let maxSide: CGFloat = 1400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return }
        model.save(photo: ProgressPhoto(day: .today, pose: pose, jpeg: jpeg))
        pickerItem = nil
    }
}

struct MeasurementEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var measurements: BodyMeasurements

    var body: some View {
        let unit = model.units.length
        NavigationStack {
            Form {
                DatePicker("Day", selection: Binding(get: { measurements.day.date() }, set: { measurements.day = Day($0) }), in: ...Date(),
                           displayedComponents: .date)
                Section {
                    MeasureField(label: "Shoulders", value: $measurements.shouldersCm, unit: unit)
                    MeasureField(label: "Chest", value: $measurements.chestCm, unit: unit)
                    MeasureField(label: "Waist (at the navel)", value: $measurements.waistCm, unit: unit)
                    MeasureField(label: "Hips", value: $measurements.hipsCm, unit: unit)
                    MeasureField(label: "Neck", value: $measurements.neckCm, unit: unit)
                    MeasureField(label: "Upper arm", value: $measurements.armCm, unit: unit)
                    MeasureField(label: "Thigh", value: $measurements.thighCm, unit: unit)
                    MeasureField(label: "Calf", value: $measurements.calfCm, unit: unit)
                } header: {
                    Text("Tape")
                } footer: {
                    Text("Skip any you like. Shoulders and waist give the ratio the program uses; neck and waist give a rough body-fat estimate.")
                }
                Section {
                    WeightField(label: "Body weight", kg: $measurements.weightKg, unit: model.units.weight)
                    HStack {
                        Text("Body fat")
                        Spacer()
                        TextField("—", value: $measurements.bodyFatPercent, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("%").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Weight usually comes from Apple Health or Macro Track.")
                }
                if model.measurements.contains(where: { $0.id == measurements.id }) {
                    Button("Delete", role: .destructive) {
                        model.delete(measurement: measurements.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(measurements: measurements)
                        dismiss()
                    }
                    .disabled(measurements.isEmpty)
                }
            }
        }
    }
}
