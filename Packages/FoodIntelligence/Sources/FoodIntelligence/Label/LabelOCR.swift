import CoreGraphics
import CoreVideo
import FoodDatabase
import Foundation
import ImageIO
import Vision

/// Text recognition for nutrition labels with Vision. Runs on every supported device, with or
/// without Apple Intelligence, in well under a second.
public enum LabelOCR {
    /// The label's text, top to bottom, with the boxes of each printed row joined left to right
    /// ("Calories" … "230" reads "Calories 230"). Empty when there's no text.
    public static func lines(in image: CGImage) async throws -> [String] {
        rows(try await recognize(image))
    }

    /// The label's text boxes for `NutritionLabel.parse(boxes:)`: normalized, top-left origin, and
    /// levelled, so a tilted photo's printed rows are rows again.
    public static func boxes(in image: CGImage) async throws -> [LabelTextBox] {
        level(try await recognize(image))
    }

    /// A label photo read without a model, from one recognition: Vision's passes are the slow part,
    /// so the boxes and the lines come from the same one. `suggestedName` and `brand` are nil.
    public static func label(in image: CGImage) async throws -> LabelResult {
        parse(try await recognize(image))
    }

    /// Positions read two-column panels; the lines are the fallback for anything else.
    static func parse(_ boxes: [TextBox]) -> LabelResult {
        let lines = rows(boxes)
        return LabelResult(
            reading: NutritionLabel.parse(boxes: level(boxes)) ?? NutritionLabel.parse(lines: lines), lines: lines,
            suggestedName: nil, brand: nil)
    }

    /// One frame of a live scan, read once as it comes (upright: the camera turns it). Several a
    /// second on a phone; `LiveLabel` and `LiveSupplementLabel` put the frames together.
    public static func frame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) async throws -> FrameText {
        let request = textRequest()
        let observations = try await request.perform(on: pixelBuffer, orientation: orientation)
        let aspect = Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(max(1, CVPixelBufferGetHeight(pixelBuffer)))
        return FrameText(textBoxes(observations, aspect: aspect))
    }

    /// The same for a still frame, as a recorded scan or a test replays it.
    public static func frame(_ image: CGImage) async throws -> FrameText {
        let observations = try await textRequest().perform(on: image, orientation: .up)
        return FrameText(textBoxes(observations, aspect: Double(image.width) / Double(max(1, image.height))))
    }

    private static func textRequest() -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        return request
    }

    private static func textBoxes(_ observations: [RecognizedTextObservation], aspect: Double) -> [TextBox] {
        observations.compactMap { observation -> TextBox? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            func point(_ p: NormalizedPoint) -> (x: Double, y: Double) { (Double(p.x) * aspect, 1 - Double(p.y)) }
            return TextBox(
                text: text, topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                bottomLeft: point(observation.bottomLeft), bottomRight: point(observation.bottomRight), aspect: aspect)
        }
    }

    /// Text boxes in the orientation that reads most like a label: a label photographed sideways
    /// is read again turned each way.
    static func recognize(_ image: CGImage) async throws -> [TextBox] {
        let picture = ImageScaling.fit(image, maxSide: 2400)
        var best: [TextBox] = []
        var bestHits = -1
        for orientation in [CGImagePropertyOrientation.up, .right, .left] {
            let observations = try await textRequest().perform(on: picture, orientation: orientation)
            // Sideways, the upright image is the other way round.
            let sideways = orientation != .up
            let aspect = Double(sideways ? picture.height : picture.width) / Double(max(1, sideways ? picture.width : picture.height))
            let boxes = textBoxes(observations, aspect: aspect)
            let hits = boxes.filter { keywords.matches($0.text) }.count
            if hits > bestHits { (best, bestHits) = (boxes, hits) }
            if bestHits >= 4 { break }
        }
        return best
    }

    private static let keywords = Pattern("calor|total fat|protein|carb|sodium|serving|vitamin|supplement facts")

    /// A recognized box with a top-left origin, in image heights: x is scaled by the aspect ratio
    /// so angles are true.
    struct TextBox: Sendable {
        var text: String
        var topLeft: (x: Double, y: Double)
        var topRight: (x: Double, y: Double)
        var bottomLeft: (x: Double, y: Double)
        var bottomRight: (x: Double, y: Double)
        /// Image width over height.
        var aspect = 1.0

        var center: (x: Double, y: Double) {
            ((topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4, (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4)
        }
        var height: Double { hypot(bottomLeft.x - topLeft.x, bottomLeft.y - topLeft.y) }
        var width: Double { hypot(topRight.x - topLeft.x, topRight.y - topLeft.y) }
        var angle: Double { atan2(topRight.y - topLeft.y, topRight.x - topLeft.x) }

        init(
            text: String, topLeft: (x: Double, y: Double), topRight: (x: Double, y: Double), bottomLeft: (x: Double, y: Double),
            bottomRight: (x: Double, y: Double), aspect: Double = 1
        ) {
            self.text = text
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
            self.aspect = aspect
        }

        init(text: String, x: Double, y: Double, width: Double, height: Double) {
            self.init(text: text, topLeft: (x, y), topRight: (x + width, y), bottomLeft: (x, y + height), bottomRight: (x + width, y + height))
        }
    }

    struct Placed {
        var text: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var left: Double { x - width / 2 }
        var right: Double { x + width / 2 }
    }

    /// Box centres with the photo's tilt taken out, using the median angle of the boxes' own lines.
    static func levelled(_ boxes: [TextBox]) -> [Placed] {
        let long = boxes.filter { $0.width > 2 * $0.height }.map(\.angle).sorted()
        let tilt = long.isEmpty ? 0 : long[long.count / 2]
        let (sine, cosine) = (sin(-tilt), cos(-tilt))
        return boxes.map { box in
            let (cx, cy) = box.center
            return Placed(text: box.text, x: cx * cosine - cy * sine, y: cx * sine + cy * cosine, width: box.width, height: max(box.height, 1e-4))
        }
    }

    /// Levelled boxes as FoodDatabase's parser takes them: 0–1 of the image, top-left origin.
    static func level(_ boxes: [TextBox]) -> [LabelTextBox] {
        zip(boxes, levelled(boxes)).map { box, placed in
            LabelTextBox(
                text: placed.text, x: placed.left / box.aspect, y: placed.y - placed.height / 2, width: placed.width / box.aspect,
                height: placed.height)
        }
    }

    /// Boxes grouped into printed rows: levelled, then boxes whose centres sit within half a line
    /// of each other share a row.
    static func rows(_ boxes: [TextBox]) -> [String] {
        let placed = levelled(boxes).sorted { $0.y < $1.y }
        var rows: [[Placed]] = []
        for box in placed {
            if let row = rows.last {
                let y = row.map(\.y).reduce(0, +) / Double(row.count)
                let height = row.map(\.height).min() ?? box.height
                // Boxes that overlap side by side are stacked lines, not one row.
                let overlaps = row.contains {
                    min($0.right, box.right) - max($0.left, box.left) > 0.5 * min($0.right - $0.left, box.right - box.left)
                }
                if abs(box.y - y) < 0.5 * min(height, box.height) && !overlaps {
                    rows[rows.count - 1].append(box)
                    continue
                }
            }
            rows.append([box])
        }
        return rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }
}

/// Downscaling with Core Graphics, for the models and for OCR.
enum ImageScaling {
    static func fit(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// One live frame's text: levelled boxes for the nutrition panel, printed rows for a Supplement
/// Facts panel and the model, and the frame's largest words, which on a package's front are
/// usually its name.
public struct FrameText: Sendable {
    public var boxes: [LabelTextBox]
    public var lines: [String]
    public var headline: String?
    /// Where each piece of text sits, 0–1 of the frame with a top-left origin, for showing what's
    /// being read.
    public var regions: [CGRect]

    init(_ boxes: [LabelOCR.TextBox]) {
        self.boxes = LabelOCR.level(boxes)
        lines = LabelOCR.rows(boxes)
        // Where the text really is: levelling turns every box about the frame's corner, which keeps
        // the rows for the parser but moves the boxes off the text on screen.
        regions = boxes.map { box in
            let xs = [box.topLeft.x, box.topRight.x, box.bottomLeft.x, box.bottomRight.x].map { $0 / box.aspect }
            let ys = [box.topLeft.y, box.topRight.y, box.bottomLeft.y, box.bottomRight.y]
            let (left, right) = (xs.min() ?? 0, xs.max() ?? 0)
            let (top, bottom) = (ys.min() ?? 0, ys.max() ?? 0)
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        headline = Self.headline(self.boxes)
    }

    private static let panelWords = Pattern(
        "nutrition|facts|serving|calories|daily value|total fat|protein|carb|sodium|sugar|fiber|ingredients|amount per|contains|net wt|vitamin")

    /// The tallest text with a few letters that isn't a panel's or a claim's, when it stands out.
    static func headline(_ boxes: [LabelTextBox]) -> String? {
        let words = boxes.filter { box in
            box.text.unicodeScalars.filter(CharacterSet.letters.contains).count >= 3
                && !panelWords.matches(box.text.lowercased()) && box.text.filter(\.isNumber).count <= 2
        }
        guard let tallest = words.max(by: { $0.height < $1.height }) else { return nil }
        let heights = boxes.map(\.height).sorted()
        let median = heights[heights.count / 2]
        guard tallest.height >= 1.5 * median else { return nil }
        let text = tallest.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.isEmpty ? nil : String(text.prefix(60))
    }
}
