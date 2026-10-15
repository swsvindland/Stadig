import Foundation

/// Tape measurements, owned by Lift Track (weight belongs to Macro Track and Health). All in cm and
/// kg; any field may be missing.
public struct BodyMeasurements: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var day: Day
    public var weightKg: Double?
    public var bodyFatPercent: Double?
    public var neckCm: Double?
    public var shouldersCm: Double?
    public var chestCm: Double?
    public var waistCm: Double?
    public var hipsCm: Double?
    public var armCm: Double?
    public var thighCm: Double?
    public var calfCm: Double?
    public var note: String

    public init(id: UUID = UUID(), day: Day, weightKg: Double? = nil, bodyFatPercent: Double? = nil, neckCm: Double? = nil,
                shouldersCm: Double? = nil, chestCm: Double? = nil, waistCm: Double? = nil, hipsCm: Double? = nil,
                armCm: Double? = nil, thighCm: Double? = nil, calfCm: Double? = nil, note: String = "") {
        self.id = id
        self.day = day
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.neckCm = neckCm
        self.shouldersCm = shouldersCm
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.armCm = armCm
        self.thighCm = thighCm
        self.calfCm = calfCm
        self.note = note
    }

    public var shoulderToWaist: Double? {
        guard let s = shouldersCm, let w = waistCm, w > 0 else { return nil }
        return s / w
    }

    public func waistToHeight(heightCm: Double?) -> Double? {
        guard let w = waistCm, let h = heightCm, h > 0 else { return nil }
        return w / h
    }

    public var isEmpty: Bool {
        [weightKg, bodyFatPercent, neckCm, shouldersCm, chestCm, waistCm, hipsCm, armCm, thighCm, calfCm].allSatisfy { $0 == nil }
    }

    /// Fills each missing field from an older entry, for "latest known" readings.
    public func filled(from older: BodyMeasurements) -> BodyMeasurements {
        var m = self
        m.weightKg = m.weightKg ?? older.weightKg
        m.bodyFatPercent = m.bodyFatPercent ?? older.bodyFatPercent
        m.neckCm = m.neckCm ?? older.neckCm
        m.shouldersCm = m.shouldersCm ?? older.shouldersCm
        m.chestCm = m.chestCm ?? older.chestCm
        m.waistCm = m.waistCm ?? older.waistCm
        m.hipsCm = m.hipsCm ?? older.hipsCm
        m.armCm = m.armCm ?? older.armCm
        m.thighCm = m.thighCm ?? older.thighCm
        m.calfCm = m.calfCm ?? older.calfCm
        return m
    }
}

/// A lagging area and what to do about it. The wording describes proportions and next steps,
/// never appearance.
public struct PhysiqueGap: Hashable, Codable, Sendable, Identifiable {
    public var region: PhysiqueRegion
    /// 0–1: how far behind the target proportion.
    public var magnitude: Double
    public var finding: String
    public var action: String

    public var id: PhysiqueRegion { region }

    public init(region: PhysiqueRegion, magnitude: Double, finding: String, action: String) {
        self.region = region
        self.magnitude = magnitude
        self.finding = finding
        self.action = action
    }
}

public struct PhysiqueAnalysis: Hashable, Sendable {
    public var latest: BodyMeasurements?
    public var shoulderToWaist: Double?
    public var waistToHeight: Double?
    public var bodyFatPercent: Double?
    /// Whether body fat was estimated from the tape (US Navy method) rather than measured.
    public var bodyFatEstimated: Bool
    public var gaps: [PhysiqueGap]
    /// Change in waist over the window, cm; negative is smaller.
    public var waistTrend: Double?

    /// A 0–100 reading for the hub: proportion and leanness, never a judgement of looks.
    public var score: Double?
}

public enum Physique {
    /// Target shoulder-to-waist ratios: around the golden ratio for men, a little lower for women.
    public static func shoulderToWaistTarget(_ sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 1.5
        case .female: 1.35
        case .unspecified: 1.42
        }
    }

    /// US Navy body-fat estimate from tape measurements; a soft signal only.
    public static func navyBodyFat(sex: BiologicalSex, heightCm: Double, neckCm: Double, waistCm: Double, hipsCm: Double?) -> Double? {
        let h = heightCm / 2.54, n = neckCm / 2.54, w = waistCm / 2.54
        switch sex {
        case .female:
            guard let hips = hipsCm else { return nil }
            let hp = hips / 2.54
            guard w + hp - n > 0 else { return nil }
            return 163.205 * log10(w + hp - n) - 97.684 * log10(h) - 78.387
        case .male, .unspecified:
            guard w - n > 0 else { return nil }
            return 86.010 * log10(w - n) - 70.041 * log10(h) + 36.76
        }
    }

    public static func analyse(_ history: [BodyMeasurements], sex: BiologicalSex, heightCm: Double?,
                               weightKg: Double? = nil) -> PhysiqueAnalysis {
        let sorted = history.sorted { $0.day < $1.day }
        var latest: BodyMeasurements?
        for entry in sorted { latest = latest.map { entry.filled(from: $0) } ?? entry }
        if let weightKg, latest?.weightKg == nil { latest?.weightKg = weightKg }

        let ratio = latest?.shoulderToWaist
        let wth = latest?.waistToHeight(heightCm: heightCm)
        var bodyFat = latest?.bodyFatPercent
        var estimated = false
        if bodyFat == nil, let latest, let h = heightCm, let neck = latest.neckCm, let waist = latest.waistCm {
            bodyFat = navyBodyFat(sex: sex, heightCm: h, neckCm: neck, waistCm: waist, hipsCm: latest.hipsCm)
            estimated = bodyFat != nil
        }

        var gaps: [PhysiqueGap] = []
        if let ratio {
            let target = shoulderToWaistTarget(sex)
            if ratio < target - 0.04 {
                let magnitude = clamp((target - ratio) / 0.25, 0, 1)
                gaps.append(PhysiqueGap(
                    region: .shoulders, magnitude: magnitude,
                    finding: String(format: "Shoulder-to-waist ratio is %.2f; the target range starts near %.2f.", ratio, target - 0.04),
                    action: "Add side-delt and overhead volume this block."))
            }
        }
        if let latest, let arm = latest.armCm, let neck = latest.neckCm, arm < neck * 0.95 {
            gaps.append(PhysiqueGap(region: .arms, magnitude: clamp((neck - arm) / neck * 3, 0, 1),
                                    finding: "Upper arms measure smaller than the neck.",
                                    action: "Add direct biceps and triceps work; it costs little recovery."))
        }
        if let latest, let thigh = latest.thighCm, let calf = latest.calfCm, thigh < calf * 1.5 {
            gaps.append(PhysiqueGap(region: .thighs, magnitude: clamp((calf * 1.5 - thigh) / thigh, 0, 1),
                                    finding: "Thighs are small relative to calves.",
                                    action: "Add quad and hamstring volume."))
        }

        var waistTrend: Double?
        let waists = sorted.compactMap { m in m.waistCm.map { (m.day, $0) } }
        if let first = waists.first, let last = waists.last, first.0 != last.0 { waistTrend = last.1 - first.1 }

        var score: Double?
        var parts: [Double] = []
        if let ratio { parts.append(clamp(ratio / shoulderToWaistTarget(sex), 0, 1.1) * 100) }
        if let wth { parts.append(clamp((0.62 - wth) / (0.62 - 0.42), 0, 1) * 100) }
        if !parts.isEmpty { score = parts.reduce(0, +) / Double(parts.count) }

        return PhysiqueAnalysis(latest: latest, shoulderToWaist: ratio, waistToHeight: wth, bodyFatPercent: bodyFat,
                                bodyFatEstimated: estimated, gaps: gaps.sorted { $0.magnitude > $1.magnitude },
                                waistTrend: waistTrend, score: score)
    }
}
