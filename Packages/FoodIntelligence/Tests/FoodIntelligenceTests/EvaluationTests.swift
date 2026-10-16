import CoreGraphics
import CoreText
import FoodDatabase
import Foundation
import ImageIO
import SystemCore
import Testing
@testable import FoodIntelligence

/// The real pipeline on this Mac: Apple's model, the real catalogs. Prints what it found and how
/// long it took. Run with `MEAL_AI_EVAL=1 swift test --filter Evaluation`.
@Suite("Evaluation", .enabled(if: ProcessInfo.processInfo.environment["MEAL_AI_EVAL"] == "1"), .serialized)
struct EvaluationTests {
    /// A description, regexes each of which some matched food should satisfy, and a plausible kcal range.
    static let meals: [(String, [String], ClosedRange<Double>)] = [
        ("two eggs, toast with butter and a flat white", ["egg", "bread|toast", "butter", "latte|milk|coffee|flat white"], 350...750),
        ("big mac and medium fries", ["big mac", "fries|french fr"], 750...1100),
        ("chicken caesar salad", ["chicken", "caesar|salad|lettuce|romaine"], 250...800),
        ("greek yogurt with blueberries and honey", ["yogurt", "blueberr", "honey"], 150...450),
        ("a protein shake with a banana", ["protein|shake|whey", "banana"], 150...500),
        ("spaghetti bolognese, about a plate", ["spaghetti|pasta|bolognese"], 400...1000),
        ("two slices of pepperoni pizza", ["pizza"], 450...800),
        ("oatmeal with peanut butter", ["oat", "peanut butter"], 250...650),
        ("a can of diet coke", ["cola|coke|carbonated"], 0...20),
        ("chipotle burrito bowl with chicken, rice, beans and guac", ["chipotle|chicken", "rice|bowl"], 600...1300),
        ("a handful of almonds", ["almond"], 100...260),
        ("salmon, rice and broccoli", ["salmon", "rice", "broccoli"], 450...950),
        ("a large oat milk latte", ["espresso|coffee", "oat"], 100...300),
        ("a cappuccino and a croissant", ["espresso|coffee", "milk", "croissant"], 300...520),
        ("a double espresso", ["espresso|coffee"], 0...20),
    ]

    static let root = URL(filePath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static let catalog = FoodCatalog(usda: root.appending(path: "Packages/FoodDatabase/Sources/FoodDatabase/Resources/usda.db"),
                                     off: root.appending(path: "Apps/MacroTrack/Catalogs/off.db"))

    @Test @available(macOS 27.0, iOS 27.0, *)
    func descriptions() async throws {
        let eggs = Self.catalog.search("egg").count
        print("catalog: search(\"egg\") → \(eggs) results; sources \(Self.catalog.sources.map(\.name))")
        let availability = MealAI.availability(allowCloud: false)
        print("availability: \(availability)")
        let ai = MealAI(catalog: Self.catalog, allowCloud: false)
        await ai.prewarm()
        try await Task.sleep(for: .seconds(2))
        var hits = 0, expected = 0, inRange = 0, seconds: [Double] = []
        for (description, wanted, range) in Self.meals {
            do {
                let guess = try await traced { try await ai.recognize(description: description, personal: []) }
                let names = guess.items.compactMap { $0.match.map { "\($0.food.name) \($0.food.brand ?? "")" } }
                let found = wanted.filter { pattern in names.contains { Pattern(pattern).matches($0) } }
                hits += found.count
                expected += wanted.count
                let kcal = guess.nutrients.kcal
                if range.contains(kcal) { inRange += 1 }
                seconds.append(guess.seconds)
                print(report(description, guess) + "  foods \(found.count)/\(wanted.count), kcal \(Int(kcal)) "
                    + (range.contains(kcal) ? "in" : "OUT OF") + " range \(Int(range.lowerBound))–\(Int(range.upperBound))\n")
            } catch {
                expected += wanted.count
                print("“\(description)” failed: \(error)\n")
            }
        }
        let sorted = seconds.sorted()
        print("SUMMARY descriptions: foods \(hits)/\(expected), kcal in range \(inRange)/\(Self.meals.count), "
            + "seconds median \(format(sorted.isEmpty ? 0 : sorted[sorted.count / 2])) max \(format(sorted.last ?? 0))")
    }

    @Test @available(macOS 27.0, iOS 27.0, *)
    func photos() async throws {
        let ai = MealAI(catalog: Self.catalog, allowCloud: false)
        await ai.prewarm()
        try await Task.sleep(for: .seconds(2))
        var photos: [(String, CGImage, String?)] = []
        for name in ["Fun/Fortune Cookie", "Fun/Gingerbread Man", "Animals/Penguin", "Sports/Basketball"] {
            if let image = Self.load(URL(filePath: "/Library/User Pictures/\(name).heic")) { photos.append((name, image, nil)) }
        }
        photos.append(("emoji breakfast", Self.emoji("🍳🥓\n🍞☕️"), nil))
        photos.append(("emoji pizza + note", Self.emoji("🍕"), "ate 2 slices"))
        for (name, image, note) in photos {
            do {
                let guess = try await traced { try await ai.recognize(photo: image, note: note, personal: []) }
                print(report("photo \(name)" + (note.map { " + “\($0)”" } ?? ""), guess) + "\n")
            } catch {
                print("photo \(name) failed: \(error)\n")
            }
        }
    }

    @Test @available(macOS 27.0, iOS 27.0, *)
    func privateCloud() async throws {
        print("availability with cloud: \(MealAI.availability(allowCloud: true))")
        let ai = MealAI(catalog: Self.catalog, allowCloud: true, pinned: .privateCloud)
        for description in ["two eggs, toast with butter and a flat white", "salmon, rice and broccoli"] {
            do {
                print(report(description, try await traced { try await ai.recognize(description: description, personal: []) }) + "\n")
            } catch {
                print("PCC “\(description)” failed: \(error) — \(error.localizedDescription)\n")
            }
        }
    }

    @Test @available(macOS 27.0, iOS 27.0, *)
    func label() async throws {
        let ai = MealAI(catalog: Self.catalog, allowCloud: false)
        for sideways in [false, true] {
            let start = ContinuousClock.now
            let result = try await ai.readLabel(photo: renderLabel(sampleLabel, sideways: sideways))
            let elapsed = ContinuousClock.now - start
            print("label sideways=\(sideways) in \(elapsed): lines \(result.lines)")
            print("  name \(result.suggestedName ?? "-") brand \(result.brand ?? "-")")
            if let reading = result.reading {
                print("  serving \(reading.servingLabel ?? "-") \(reading.servingGrams.map { "\($0) g" } ?? "") · \(reading.nutrients) · fields \(reading.fieldsRead)\n")
            } else {
                print("  no reading\n")
            }
        }
    }

    // MARK: Helpers

    /// Runs with the pipeline's notes printed, when `MEAL_AI_TRACE=1`.
    func traced<T>(_ body: () async throws -> T) async throws -> T {
        guard ProcessInfo.processInfo.environment["MEAL_AI_TRACE"] == "1" else { return try await body() }
        return try await Trace.$receiver.withValue({ print("    … " + $0) }) { try await body() }
    }

    func report(_ title: String, _ guess: MealGuess) -> String {
        var lines = ["\(title) — \(guess.engine.rawValue), \(format(guess.seconds)) s, \(Int(guess.nutrients.kcal)) kcal"
            + (guess.scene.map { ", scene “\($0)”" } ?? "") + (guess.isFood ? "" : ", NOT FOOD")]
        for item in guess.items {
            let seen = [item.seenBrand, item.seenName].compactMap { $0 }.joined(separator: " ")
            guard let match = item.match, let unit = item.unit else {
                lines.append("  · \(seen) → no match")
                continue
            }
            let amount = FoodUnits.label(count: item.count, unit: unit)
            lines.append("  · \(seen) → \(match.food.title) [\(format(match.score))] \(item.approximate ? "≈ " : "")\(amount) "
                + "= \(Int(item.nutrients.kcal)) kcal\(item.sure ? "" : " (unsure)")"
                + (item.alternatives.isEmpty ? "" : " | alt: " + item.alternatives.prefix(2).map(\.food.name).joined(separator: "; ")))
        }
        return lines.joined(separator: "\n")
    }

    func format(_ value: Double) -> String { String(format: "%.2f", value) }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Emoji drawn large on a white plate-coloured background.
    static func emoji(_ text: String) -> CGImage {
        let size = 900
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, 300, nil)
        for (i, row) in text.split(separator: "\n").enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(row), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]))
            context.textPosition = CGPoint(x: 60, y: CGFloat(size - 380 - i * 380))
            CTLineDraw(line, context)
        }
        return context.makeImage()!
    }
}
