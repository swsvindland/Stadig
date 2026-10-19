import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device text recognition with Vision: a page written by hand (on paper and scanned or
/// photographed, or with Apple Pencil) or a printed page of a book. Nothing leaves the device.
/// It takes the languages to read, so the same path can read kana and kanji later.
enum TextRecognizer {
    static let english = [Locale.Language(identifier: "en-GB"), Locale.Language(identifier: "en-US")]

    /// The text on one or more pages, in reading order. Lines that wrap are joined into
    /// paragraphs; a wider gap between lines starts a new one.
    static func read(_ pages: [CGImage], languages: [Locale.Language] = english, handwriting: Bool = true) async throws -> String {
        var out: [String] = []
        for page in pages {
            let text = try await read(page, orientation: .up, languages: languages, handwriting: handwriting)
            if !text.isEmpty { out.append(text) }
        }
        return out.joined(separator: "\n\n")
    }

    /// A page brought in that isn't a picture or a PDF that can be drawn.
    enum RecognitionError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "The picture couldn't be opened." }
    }

    static func read(
        _ image: CGImage, orientation: CGImagePropertyOrientation, languages: [Locale.Language],
        handwriting: Bool
    ) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        // Language correction helps handwriting into words; a printed page reads better without it.
        request.usesLanguageCorrection = handwriting
        let observations = try await request.perform(on: image, orientation: orientation)
        return paragraphs(
            observations.compactMap { observation in
                observation.topCandidates(1).first.map {
                    Line(text: $0.string, top: Double(observation.topLeft.y), bottom: Double(observation.bottomLeft.y))
                }
            })
    }

    /// A recognised line; y runs up from the bottom of the page, as Vision gives it.
    struct Line {
        var text: String
        var top: Double
        var bottom: Double
        var height: Double { max(0.001, top - bottom) }
    }

    /// Lines top to bottom, joined with spaces, with a paragraph break where the gap is clearly more
    /// than the page's usual spacing (most of a line more). A word hyphenated across lines is
    /// joined up again.
    static func paragraphs(_ lines: [Line]) -> String {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.sorted { $0.top > $1.top }
        guard !sorted.isEmpty else { return "" }
        func median(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.sorted()[values.count / 2] }
        let lineHeight = median(sorted.map(\.height))
        let spacing = median(zip(sorted, sorted.dropFirst()).map { $0.bottom - $1.top })
        var out = sorted[0].text.trimmingCharacters(in: .whitespaces)
        for (previous, line) in zip(sorted, sorted.dropFirst()) {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let gap = previous.bottom - line.top
            if gap > spacing + lineHeight * 0.8 {
                out += "\n\n" + text
            } else if out.hasSuffix("-"), text.first?.isLowercase == true {
                out.removeLast()
                out += text
            } else {
                out += " " + text
            }
        }
        return out
    }
}
