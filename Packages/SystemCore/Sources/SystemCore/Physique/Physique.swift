import Foundation

/// A limb measured on both sides.
public enum Limb: String, CaseIterable, Codable, Sendable, Identifiable {
    case arm, thigh, calf

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .arm: "Upper arm"
        case .thigh: "Thigh"
        case .calf: "Calf"
        }
    }

    public var region: PhysiqueRegion {
        switch self {
        case .arm: .arms
        case .thigh: .thighs
        case .calf: .calves
        }
    }
}

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
    /// At the navel: waist-to-height, shoulder-to-waist and men's tape body fat.
    public var waistCm: Double?
    /// At its narrowest, between the ribs and the hips: waist-to-hip and women's tape body fat.
    public var naturalWaistCm: Double?
    /// Around the top of the hip bones. Entries from before glutes were measured took the widest
    /// point here; the store moves those to glutes.
    public var hipsCm: Double?
    /// The widest point around the buttocks.
    public var glutesCm: Double?
    /// Flexed, at the biceps peak.
    public var armLeftCm: Double?
    public var armRightCm: Double?
    /// Standing, just below the glute fold.
    public var thighLeftCm: Double?
    public var thighRightCm: Double?
    /// Standing, at the widest point.
    public var calfLeftCm: Double?
    public var calfRightCm: Double?
    /// One reading with no side, from before both sides were measured: it counts for size, never
    /// for symmetry.
    public var armCm: Double?
    public var thighCm: Double?
    public var calfCm: Double?
    public var note: String

    public init(id: UUID = UUID(), day: Day, weightKg: Double? = nil, bodyFatPercent: Double? = nil, neckCm: Double? = nil,
                shouldersCm: Double? = nil, chestCm: Double? = nil, waistCm: Double? = nil, naturalWaistCm: Double? = nil,
                hipsCm: Double? = nil, glutesCm: Double? = nil, armCm: Double? = nil, armLeftCm: Double? = nil, armRightCm: Double? = nil,
                thighCm: Double? = nil, thighLeftCm: Double? = nil, thighRightCm: Double? = nil, calfCm: Double? = nil,
                calfLeftCm: Double? = nil, calfRightCm: Double? = nil, note: String = "") {
        self.id = id
        self.day = day
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.neckCm = neckCm
        self.shouldersCm = shouldersCm
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.naturalWaistCm = naturalWaistCm
        self.hipsCm = hipsCm
        self.glutesCm = glutesCm
        self.armLeftCm = armLeftCm
        self.armRightCm = armRightCm
        self.thighLeftCm = thighLeftCm
        self.thighRightCm = thighRightCm
        self.calfLeftCm = calfLeftCm
        self.calfRightCm = calfRightCm
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

    /// Where a limb's left and right readings live.
    public static func sides(_ limb: Limb) -> (left: WritableKeyPath<BodyMeasurements, Double?>, right: WritableKeyPath<BodyMeasurements, Double?>) {
        switch limb {
        case .arm: (\.armLeftCm, \.armRightCm)
        case .thigh: (\.thighLeftCm, \.thighRightCm)
        case .calf: (\.calfLeftCm, \.calfRightCm)
        }
    }

    /// Where a limb's reading with no side lives.
    public static func unsided(_ limb: Limb) -> WritableKeyPath<BodyMeasurements, Double?> {
        switch limb {
        case .arm: \.armCm
        case .thigh: \.thighCm
        case .calf: \.calfCm
        }
    }

    /// Both sides, when both were measured.
    public func sides(_ limb: Limb) -> (left: Double, right: Double)? {
        let keys = Self.sides(limb)
        guard let left = self[keyPath: keys.left], let right = self[keyPath: keys.right] else { return nil }
        return (left, right)
    }

    /// A limb's size for proportions: the bigger side, so a lagging side isn't also counted as a
    /// small limb, or a reading with no side.
    public func size(_ limb: Limb) -> Double? {
        let keys = Self.sides(limb)
        let sided = [self[keyPath: keys.left], self[keyPath: keys.right]].compactMap { $0 }.max()
        return sided ?? self[keyPath: Self.unsided(limb)]
    }

    static var fields: [WritableKeyPath<BodyMeasurements, Double?>] {
        [\.weightKg, \.bodyFatPercent, \.neckCm, \.shouldersCm, \.chestCm, \.waistCm, \.naturalWaistCm, \.hipsCm, \.glutesCm,
         \.armLeftCm, \.armRightCm, \.thighLeftCm, \.thighRightCm, \.calfLeftCm, \.calfRightCm, \.armCm, \.thighCm, \.calfCm]
    }

    public var isEmpty: Bool { Self.fields.allSatisfy { self[keyPath: $0] == nil } }

    /// Fills each missing field from an older entry, for "latest known" readings.
    public func filled(from older: BodyMeasurements) -> BodyMeasurements {
        var m = self
        for key in Self.fields where m[keyPath: key] == nil { m[keyPath: key] = older[keyPath: key] }
        return m
    }
}

/// A side that has measured smaller at check-ins at least two weeks apart.
public struct Asymmetry: Hashable, Codable, Sendable, Identifiable {
    public var limb: Limb
    public var smaller: BodySide
    public var differenceCm: Double
    /// Of the bigger side.
    public var percent: Double
    /// 0–1: 4% apart is the threshold, 10% the most.
    public var magnitude: Double

    public var id: Limb { limb }

    public init(limb: Limb, smaller: BodySide, differenceCm: Double, percent: Double, magnitude: Double) {
        self.limb = limb
        self.smaller = smaller
        self.differenceCm = differenceCm
        self.percent = percent
        self.magnitude = magnitude
    }

    var bigger: BodySide { smaller == .left ? .right : .left }

    public var finding: String {
        "Your \(smaller.label.lowercased()) \(limb.label.lowercased()) has measured smaller than the \(bigger.label.lowercased()) "
            + "at two check-ins in a row (\(Int((percent * 100).rounded()))% less)."
    }

    public var action: String {
        let work = switch limb {
        case .arm: "Arm work goes"
        case .thigh: "Leg accessories go"
        case .calf: "Calf raises go"
        }
        return "\(work) one side at a time, \(smaller.label.lowercased()) first; the \(bigger.label.lowercased()) matches its reps."
    }
}

/// Fat-free mass index against what's typical, for how much room is left to build.
public enum FFMIBand: String, Codable, Sendable {
    case lotsOfRoom, someRoom, nearCeiling

    public var label: String {
        switch self {
        case .lotsOfRoom: "Lots of room to build"
        case .someRoom: "Some room to build"
        case .nearCeiling: "Near the natural ceiling"
        }
    }

    /// Normalised FFMI where each band starts.
    public static func thresholds(_ sex: BiologicalSex) -> (some: Double, near: Double) {
        switch sex {
        case .male: (22, 24)
        case .female: (18.5, 20)
        case .unspecified: (20.25, 22)
        }
    }

    public static func of(_ normalized: Double, sex: BiologicalSex) -> FFMIBand {
        let t = thresholds(sex)
        return normalized >= t.near ? .nearCeiling : (normalized >= t.some ? .someRoom : .lotsOfRoom)
    }
}

/// Where a body-fat reading came from, best first.
public enum BodyFatSource: String, Sendable {
    /// A Health sample from the last two weeks: a smart scale or a scan.
    case health
    /// Typed into a measurement entry.
    case entered
    /// The US Navy tape estimate: a soft signal, about ±3–4%.
    case tape
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
    public var bodyFatSource: BodyFatSource?
    /// Lean mass over height squared.
    public var ffmi: Double?
    /// FFMI adjusted to a 1.8 m height, so people of different heights compare.
    public var normalizedFFMI: Double?
    public var ffmiBand: FFMIBand?
    public var targets: ProportionTargets
    /// Every rule in the set, flagged or not.
    public var proportions: [ProportionReading]
    /// Whether fat loss or building would do more, for Macro Track.
    public var direction: PhysiqueDirection
    /// Proportion gaps that training closes.
    public var gaps: [PhysiqueGap]
    public var asymmetries: [Asymmetry]
    /// Change in waist over the window, cm; negative is smaller.
    public var waistTrend: Double?

    /// A 0–100 reading for the hub: proportion and leanness, never a judgement of looks.
    public var score: Double?

    /// Whether body fat was estimated from the tape (US Navy method) rather than measured.
    public var bodyFatEstimated: Bool { bodyFatSource == .tape }
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

    /// The tape estimate with the sites the Navy method uses: the waist at the navel for men, at its
    /// narrowest and the glutes at their widest for women.
    public static func tapeBodyFat(_ m: BodyMeasurements, sex: BiologicalSex, heightCm: Double?) -> Double? {
        guard let h = heightCm, let neck = m.neckCm else { return nil }
        switch sex {
        case .female:
            guard let waist = m.naturalWaistCm ?? m.waistCm else { return nil }
            return navyBodyFat(sex: sex, heightCm: h, neckCm: neck, waistCm: waist, hipsCm: m.glutesCm)
        case .male, .unspecified:
            guard let waist = m.waistCm else { return nil }
            return navyBodyFat(sex: sex, heightCm: h, neckCm: neck, waistCm: waist, hipsCm: nil)
        }
    }

    /// Lean mass over height squared, and adjusted to a 1.8 m height (Kouri et al., 1995).
    public static func ffmi(weightKg: Double, bodyFatPercent: Double, heightCm: Double) -> (ffmi: Double, normalized: Double)? {
        guard heightCm > 0, weightKg > 0, (2..<70).contains(bodyFatPercent) else { return nil }
        let metres = heightCm / 100
        let ffmi = weightKg * (1 - bodyFatPercent / 100) / (metres * metres)
        return (ffmi, ffmi + 6.1 * (1.8 - metres))
    }

    // Symmetry: tape error is about half a centimetre to a centimetre, and a dominant side around a
    // centimetre bigger is normal, so only a difference that lasts counts.
    static let asymmetryMinimumCm = 1.5
    static let asymmetryMinimumShare = 0.04
    static let asymmetryClearsBelowCm = 1.0
    static let asymmetryDaysApart = 14

    /// Sides that measured apart at two check-ins at least two weeks apart. Once flagged, a side
    /// stays flagged until a check-in shows them within a centimetre.
    public static func asymmetries(_ history: [BodyMeasurements]) -> [Asymmetry] {
        Limb.allCases.compactMap { limb in
            let entries = history.sorted { $0.day < $1.day }.compactMap { m in m.sides(limb).map { (day: m.day, left: $0.left, right: $0.right) } }
            func smaller(_ e: (day: Day, left: Double, right: Double)) -> BodySide { e.left < e.right ? .left : .right }
            func apart(_ e: (day: Day, left: Double, right: Double)) -> Bool {
                abs(e.left - e.right) >= max(asymmetryMinimumCm, max(e.left, e.right) * asymmetryMinimumShare)
            }
            var flagged: BodySide?
            for (i, entry) in entries.enumerated() {
                let side = smaller(entry)
                if let f = flagged, f != side || abs(entry.left - entry.right) < asymmetryClearsBelowCm { flagged = nil }
                guard flagged == nil, apart(entry) else { continue }
                let earlier = entries[..<i].last { $0.day <= entry.day.adding(days: -asymmetryDaysApart) }
                if let earlier, apart(earlier), smaller(earlier) == side { flagged = side }
            }
            guard let side = flagged, let last = entries.last else { return nil }
            let difference = abs(last.left - last.right)
            let share = difference / max(last.left, last.right)
            return Asymmetry(limb: limb, smaller: side, differenceCm: difference, percent: share,
                             magnitude: clamp((share - asymmetryMinimumShare) / 0.06, 0, 1))
        }
    }

    /// `weightKg` is the current weight (Health); it beats a typed one, as it does for strength
    /// scoring, since a weight typed at onboarding would otherwise stand as the latest for good.
    /// `measuredBodyFat` is a recent Health sample; it beats a typed reading, which beats the tape.
    /// `targets` defaults to the set for the person's standards.
    public static func analyse(_ history: [BodyMeasurements], sex: BiologicalSex, heightCm: Double?,
                               weightKg: Double? = nil, measuredBodyFat: Double? = nil, targets: ProportionTargets? = nil) -> PhysiqueAnalysis {
        let sorted = history.sorted { $0.day < $1.day }
        var latest: BodyMeasurements?
        for entry in sorted { latest = latest.map { entry.filled(from: $0) } ?? entry }
        if let weightKg { latest?.weightKg = weightKg }

        let ratio = latest?.shoulderToWaist
        let wth = latest?.waistToHeight(heightCm: heightCm)
        let readings: [(Double?, BodyFatSource)] = [(measuredBodyFat, .health), (latest?.bodyFatPercent, .entered),
                                                    (latest.flatMap { tapeBodyFat($0, sex: sex, heightCm: heightCm) }, .tape)]
        let best = readings.first { $0.0 != nil }
        let bodyFat = best?.0
        let source = best?.1
        let lean = bodyFat.flatMap { bf in
            latest?.weightKg.flatMap { kg in heightCm.flatMap { ffmi(weightKg: kg, bodyFatPercent: bf, heightCm: $0) } }
        }

        let targets = targets ?? .standard(for: sex)
        let floor = Proportions.atLeanFloor(bodyFatPercent: bodyFat, waistToHeight: wth, sex: sex)
        let proportions = latest.map { Proportions.read($0, targets: targets, sex: sex, heightCm: heightCm, atLeanFloor: floor) } ?? []
        let gaps = proportions.compactMap { reading -> PhysiqueGap? in
            guard reading.cause == .build, let region = reading.region, let action = reading.action else { return nil }
            return PhysiqueGap(region: region, magnitude: reading.magnitude, finding: reading.finding, action: action)
        }
        let flagged = proportions.filter { $0.cause != nil }
        let builds = flagged.filter { $0.cause == .build }
        let direction = PhysiqueDirection(
            targets: targets, fatLoss: floor ? 0 : flagged.map(\.fatShare).max() ?? 0, build: builds.map(\.magnitude).max() ?? 0,
            buildRegions: builds.compactMap(\.region), atLeanFloor: floor, waistToHeight: wth, bodyFatPercent: bodyFat,
            normalizedFFMI: lean?.normalized, ffmiBand: lean.map { FFMIBand.of($0.normalized, sex: sex) },
            fatLossReasons: floor ? [] : flagged.filter { $0.cause == .fat }.map(\.finding), buildReasons: builds.map(\.finding))

        var waistTrend: Double?
        let waists = sorted.compactMap { m in m.waistCm.map { (m.day, $0) } }
        if let first = waists.first, let last = waists.last, first.0 != last.0 { waistTrend = last.1 - first.1 }

        var score: Double?
        var parts: [Double] = []
        if let wth { parts.append(clamp((0.62 - wth) / (0.62 - 0.42), 0, 1) * 100) }
        // Each active ratio by how close it is to its target now.
        for reading in proportions { parts.append((1 - reading.rule.assess(reading.value, sex: sex).magnitude) * 100) }
        if !parts.isEmpty { score = parts.reduce(0, +) / Double(parts.count) }

        return PhysiqueAnalysis(latest: latest, shoulderToWaist: ratio, waistToHeight: wth, bodyFatPercent: bodyFat, bodyFatSource: source,
                                ffmi: lean?.ffmi, normalizedFFMI: lean?.normalized, ffmiBand: lean.map { FFMIBand.of($0.normalized, sex: sex) },
                                targets: targets, proportions: proportions, direction: direction,
                                gaps: gaps.sorted { $0.magnitude > $1.magnitude }, asymmetries: asymmetries(sorted),
                                waistTrend: waistTrend, score: score)
    }
}
