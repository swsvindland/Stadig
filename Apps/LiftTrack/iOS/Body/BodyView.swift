import Charts
import LiftEngine
import OSLog
import PhotosUI
import SwiftUI
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
    @State private var importFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let physique = model.analysis?.physique {
                        overview(physique)
                        sides(physique)
                        if !physique.gaps.isEmpty || physique.proportions.contains(where: { $0.cause == .fat }) { gaps(physique) }
                    }
                    waistTrend
                    photos
                    history
                }
                .padding()
                .readableWidth()
            }
            .accessibilityIdentifier("body.screen")
            .background(.pageBackground)
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        measuring = true
                    } label: {
                        Image(systemName: "ruler")
                    }.accessibilityLabel("Add measurements")
                        .accessibilityIdentifier("body.addMeasurements")
                }
            }
            .sheet(isPresented: $measuring) { MeasurementEditor(measurements: BodyMeasurements(day: .today)) }
            .sheet(item: $editing) { m in MeasurementEditor(measurements: m) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .alert("Couldn't add that photo", isPresented: $importFailed) {
                Button("OK") {}
            } message: {
                Text("It couldn't be read. Try it again, or another photo.")
            }
        }
    }

    private func overview(_ p: PhysiqueAnalysis) -> some View {
        let length = model.units.length
        let sex = model.profile?.sex ?? .unspecified
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Physique", systemImage: StatKind.physique.symbol).font(.headline).foregroundStyle(StatKind.physique.color)
                Spacer()
                Text(p.targets == .off ? "Proportion targets off" : "\(p.targets.label) targets").font(.caption).foregroundStyle(.secondary)
            }
            if p.latest == nil {
                Text("Measure once a block, at the deload check-in. It takes a few minutes with a tape.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    measuring = true
                } label: {
                    Label("Add measurements", systemImage: "ruler").frame(maxWidth: .infinity)
                }.primaryAction()
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(p.proportions) { reading in
                        GridRow {
                            Text(reading.rule.label).foregroundStyle(.secondary)
                            Text(Format.number(reading.value, digits: 2)).monospacedDigit()
                            Text(caption(reading, sex: sex)).font(.caption).foregroundStyle(.secondary)
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
                        let source =
                            switch p.bodyFatSource {
                            case .health: "from Health"
                            case .entered: "entered"
                            case .tape, nil: "tape estimate, a soft signal"
                            }
                        GridRow {
                            Text("Body fat").foregroundStyle(.secondary)
                            Text("\(Format.number(bf))%").monospacedDigit()
                            Text(source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let ffmi = p.normalizedFFMI, let band = p.ffmiBand {
                        GridRow {
                            Text("FFMI").foregroundStyle(.secondary)
                            Text(Format.number(ffmi, digits: 1)).monospacedDigit()
                            Text(band.label.lowercased() + (p.bodyFatEstimated ? ", about ±1" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let latest = p.latest {
                        GridRow {
                            Text("Waist").foregroundStyle(.secondary)
                            Text(Format.length(latest.waistCm, unit: length))
                            Text(p.waistTrend.map { "\($0 > 0 ? "+" : "")\(Format.length($0, unit: length)) since first" } ?? "").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    /// Left against right for each limb measured on both sides, and any side that's lagging.
    @ViewBuilder
    private func sides(_ p: PhysiqueAnalysis) -> some View {
        let limbs = Limb.allCases.compactMap { limb in p.latest?.sides(limb).map { (limb, $0) } }
        if !limbs.isEmpty {
            let length = model.units.length
            VStack(alignment: .leading, spacing: 10) {
                Text("Left and right").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Left").font(.caption).foregroundStyle(.secondary)
                        Text("Right").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(limbs, id: \.0) { item in
                        let lagging = p.asymmetries.first { $0.limb == item.0 }?.smaller
                        GridRow {
                            Text(item.0.label).foregroundStyle(.secondary)
                            Text(Format.length(item.1.left, unit: length)).monospacedDigit().fontWeight(lagging == .left ? .semibold : nil)
                            Text(Format.length(item.1.right, unit: length)).monospacedDigit().fontWeight(lagging == .right ? .semibold : nil)
                        }
                    }
                }
                .font(.subheadline)
                if p.asymmetries.isEmpty {
                    Text("Even enough: a centimetre or so either way is normal, and tape readings vary that much.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(p.asymmetries) { asymmetry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asymmetry.finding).font(.caption).foregroundStyle(.secondary)
                        Label(asymmetry.action, systemImage: "arrow.right.circle").font(.caption)
                    }
                }
            }
            .card()
        }
    }

    private func caption(_ reading: ProportionReading, sex: BiologicalSex) -> String {
        switch reading.cause {
        case .fat: "fat loss closes it"
        case .build: "target \(reading.rule.targetText(sex: sex))"
        case nil: reading.magnitude == 0 ? "on target" : "target \(reading.rule.targetText(sex: sex))"
        }
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
            // Gaps the waist drives: the nutrition phase closes them, not extra volume.
            ForEach(p.proportions.filter { $0.cause == .fat }) { reading in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.rule.label).font(.subheadline.weight(.semibold))
                    Text(reading.finding).font(.caption).foregroundStyle(.secondary)
                    if let action = reading.action { Label(action, systemImage: "arrow.right.circle").font(.caption) }
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
                        photo(first, maxPixel: 720)
                        photo(last, maxPixel: 720)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(shown) { p in
                            photo(p, maxPixel: 360).frame(width: 90, height: 120)
                                .contextMenu { Button("Delete", role: .destructive) { model.delete(photo: p.id) } }
                        }
                    }
                }
            }
        }
        .card()
    }

    private func photo(_ p: ProgressPhoto, maxPixel: Int) -> some View {
        VStack(spacing: 4) {
            ProgressPhotoImage(photo: p, maxPixel: maxPixel)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 240).clipped()
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("Progress photo, \(Format.day(p.day))")
            Text(Format.day(p.day, style: .dateTime.month(.abbreviated).day().year())).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.measurements.isEmpty { SectionHeader(title: "Measurements") }
            ForEach(model.measurements.reversed()) { m in
                Button {
                    editing = m
                } label: {
                    HStack {
                        Text(Format.day(m.day, style: .dateTime.month(.abbreviated).day().year())).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(
                            [
                                m.waistCm.map { "waist \(Format.length($0, unit: model.units.length))" },
                                m.shouldersCm.map { "shoulders \(Format.length($0, unit: model.units.length))" },
                                m.weightKg.map { Format.weight($0, unit: model.units.weight) },
                            ].compactMap { $0 }.joined(separator: " · ")
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("body.measurement")
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        // The pose it was picked for, even if the person changes it while iCloud downloads it.
        let pose = pose
        // Cleared whatever happens, so picking the same photo again tries again.
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let jpeg = await ProgressPhotos.jpeg(from: data) else {
                importFailed = true
                return
            }
            model.save(photo: ProgressPhoto(day: .today, pose: pose, jpeg: jpeg))
        } catch {
            appLog.error("Couldn't load a progress photo: \(error.localizedDescription)")
            importFailed = true
        }
    }
}

/// Progress photo pixels, off the main actor. ImageIO decodes straight to the size asked for, so
/// a 24 MP original is never held in full; the same on every platform (`ImageData`).
enum ProgressPhotos {
    /// What's stored: at most 1400 pixels on the long side, enough to compare and light to sync.
    @concurrent nonisolated static func jpeg(from data: Data) async -> Data? {
        ImageData.resizedJPEG(data, maxPixels: 1400, quality: 0.7)
    }

    /// For the screen, at about the pixels it's shown at.
    @concurrent nonisolated static func image(from data: Data, maxPixel: Int) async -> CGImage? {
        ImageData.downsampled(data, maxPixels: maxPixel)
    }

    /// Decoded once per photo and size: the Body tab re-renders on every reload.
    static let cache = NSCache<NSString, CGImage>()

    static func key(_ photo: ProgressPhoto, maxPixel: Int) -> NSString { "\(photo.id.uuidString)-\(maxPixel)" as NSString }
}

/// One progress photo, decoded off the main actor at the size it's shown and kept in the cache.
struct ProgressPhotoImage: View {
    let photo: ProgressPhoto
    let maxPixel: Int
    @State private var image: CGImage?

    init(photo: ProgressPhoto, maxPixel: Int) {
        self.photo = photo
        self.maxPixel = maxPixel
        _image = State(initialValue: ProgressPhotos.cache.object(forKey: ProgressPhotos.key(photo, maxPixel: maxPixel)))
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Rectangle().fill(.secondary.opacity(0.12))
            }
        }
        .task(id: photo.id) {
            guard image == nil, let decoded = await ProgressPhotos.image(from: photo.jpeg, maxPixel: maxPixel) else { return }
            ProgressPhotos.cache.setObject(decoded, forKey: ProgressPhotos.key(photo, maxPixel: maxPixel))
            image = decoded
        }
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
                DatePicker(
                    "Day", selection: Binding(get: { measurements.day.date() }, set: { measurements.day = Day($0) }), in: ...Date(),
                    displayedComponents: .date)
                Section {
                    NavigationLink("Where the tape goes") { MeasuringGuide() }
                } footer: {
                    Text("In the morning, before eating or training, the tape snug but not pressing in. Skip any you like.")
                }
                Section {
                    MeasureField(label: "Neck", value: $measurements.neckCm, unit: unit)
                    MeasureField(label: "Shoulders", value: $measurements.shouldersCm, unit: unit)
                    MeasureField(label: "Chest", value: $measurements.chestCm, unit: unit)
                    MeasureField(label: "Waist at the navel", value: $measurements.waistCm, unit: unit, identifier: "measurements.waist")
                    MeasureField(label: "Waist at its narrowest", value: $measurements.naturalWaistCm, unit: unit)
                    MeasureField(label: "Hips, at the hip bones", value: $measurements.hipsCm, unit: unit)
                    MeasureField(label: "Glutes, at the widest", value: $measurements.glutesCm, unit: unit)
                } header: {
                    Text("Torso")
                } footer: {
                    Text("The waist at the navel matters most: leanness and the nutrition phase come from it.")
                }
                Section {
                    ForEach(Limb.allCases) { limb in
                        let keys = BodyMeasurements.sides(limb)
                        SidesField(
                            label: limb == .arm ? "Upper arm, flexed" : limb.label, left: $measurements[dynamicMember: keys.left],
                            right: $measurements[dynamicMember: keys.right], unit: unit)
                    }
                } header: {
                    Text("Arms and legs")
                } footer: {
                    Text("Both sides, so a side that's lagging shows up.")
                }
                let unsided = Limb.allCases.filter { measurements[keyPath: BodyMeasurements.unsided($0)] != nil }
                if !unsided.isEmpty {
                    Section("Before sides were measured") {
                        ForEach(unsided) { limb in
                            MeasureField(label: limb.label, value: $measurements[dynamicMember: BodyMeasurements.unsided(limb)], unit: unit)
                        }
                    }
                }
                Section {
                    WeightField(label: "Body weight", kg: $measurements.weightKg, unit: model.units.weight)
                    HStack {
                        Text("Body fat")
                        Spacer()
                        TextField("—", value: $measurements.bodyFatPercent, format: .number.precision(.fractionLength(0...1)))
                            .fieldKeyboard(.decimal).multilineTextAlignment(.trailing).frame(width: 80)
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
                    .accessibilityIdentifier("measurements.delete")
                }
            }
            .navigationTitle("Measurements")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("measurements.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(measurements: measurements)
                        dismiss()
                    }
                    .disabled(measurements.isEmpty)
                    .accessibilityIdentifier("measurements.save")
                }
            }
        }
    }
}

/// Left and right on one row, in the person's unit, stored in centimetres.
struct SidesField: View {
    let label: String
    @Binding var left: Double?
    @Binding var right: Double?
    let unit: LengthUnit

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer()
            side("L", "Left", $left)
            side("R", "Right", $right)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }

    private func side(_ short: String, _ name: String, _ value: Binding<Double?>) -> some View {
        HStack(spacing: 4) {
            Text(short).font(.caption).foregroundStyle(.secondary)
            TextField(
                "—",
                value: Binding(
                    get: { value.wrappedValue.map { (unit.fromCentimetres($0) * 10).rounded() / 10 } },
                    set: { value.wrappedValue = $0.map(unit.toCentimetres) }),
                format: .number.precision(.fractionLength(0...1))
            )
            .fieldKeyboard(.decimal)
            // Next to its letter, so each value reads as that side's.
            .multilineTextAlignment(.leading)
            .frame(width: 52)
            .accessibilityLabel("\(name) \(label.lowercased())")
        }
    }
}

/// Where each tape measurement goes, so every check-in is taken the same way.
struct MeasuringGuide: View {
    var body: some View {
        List {
            Section {
                Text(
                    "In the morning, before eating or training. Keep the tape level and snug on the skin without pressing in, and breathe out normally before reading it. The same way every time matters more than any one reading."
                )
                .font(.subheadline)
            }
            Section("Torso") {
                site("Neck", "Just below the larynx, the tape sloping slightly down at the front.")
                site("Shoulders", "Around the widest point of the shoulders, arms relaxed at your sides.")
                site("Chest", "Level with the nipples.")
                site("Waist at the navel", "Level with the navel, relaxed, not sucked in.")
                site("Waist at its narrowest", "The narrowest point between the ribs and the hips.")
                site("Hips", "Around the top of the hip bones.")
                site("Glutes", "Around the widest point of the buttocks, feet together.")
            }
            Section("Arms and legs") {
                site("Upper arm", "Flexed, at the peak of the biceps, with the arm raised to shoulder height.")
                site("Thigh", "Standing, just below the fold under the glutes.")
                site("Calf", "Standing, at the widest point.")
            }
            Section {
                Text(
                    "A centimetre between sides is normal, and a reading can vary that much. The program only acts on a difference that shows at two check-ins at least two weeks apart."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Where the tape goes")
        .inlineTitle()
    }

    private func site(_ name: String, _ how: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(how).font(.caption).foregroundStyle(.secondary)
        }
    }
}
