import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Pages and pictures brought in from outside the app: a photo or a scanned PDF from the file
/// importer, an image dropped on the window, or what an iPhone's camera sends the Mac through
/// Continuity Camera (a photo, or a document scan as a PDF). Decoded off the main actor, upright and
/// no bigger than text recognition needs, a page at a time so a long scan never sits in memory whole.
enum ImageImport {
    nonisolated private static let log = Logger(subsystem: "dev.svindland.stadig.mind", category: "import")

    /// What the importers and drops accept: pictures, and scans saved as PDFs.
    static let pageTypes: [UTType] = [.image, .pdf]

    /// More pages than a piece of handwriting runs to are left out, counted across every file brought
    /// in together: a whole book scanned by mistake, or a folder of photos, shouldn't take minutes
    /// and a gigabyte to read.
    nonisolated static let maxPages = 12

    /// A file brought in, loaded only when its turn comes: several chosen at once are read one by
    /// one, never all held in memory first.
    typealias File = () async throws -> Data?

    /// Each page of `files` in order, at most `limit` across all of them, handed to `read` one at a
    /// time: a file is loaded only once the pages before it are read, and none after the limit is
    /// loaded at all. Returns how many pages could be drawn.
    @discardableResult
    static func forEachPage(of files: [File], limit: Int = maxPages, _ read: (CGImage) async throws -> Void) async throws -> Int {
        var left = limit
        var drawn = 0
        for load in files {
            guard left > 0 else { break }
            guard let file = try await load() else { continue }
            let count = min(left, await pageCount(file))
            left -= count
            for index in 0..<count {
                guard let page = await page(file, at: index) else { continue }
                drawn += 1
                try await read(page)
            }
        }
        return drawn
    }

    /// How many pages a file's bytes hold: a PDF's pages (up to `maxPages`), or one picture.
    @concurrent nonisolated static func pageCount(_ data: Data) async -> Int {
        guard isPDF(data) else { return 1 }
        return min(maxPages, pdf(data)?.numberOfPages ?? 0)
    }

    /// One page of a file's bytes: a page of a PDF (counting from 0), or the picture.
    @concurrent nonisolated static func page(_ data: Data, at index: Int, maxPixels: Int = 3000) async -> CGImage? {
        guard isPDF(data) else { return ImageData.downsampled(data, maxPixels: maxPixels) }
        guard let page = pdf(data)?.page(at: index + 1) else { return nil }
        return render(page, maxPixels: maxPixels)
    }

    /// A file chosen in the file importer, read while the sandbox allows it, off the main actor (it
    /// may still be downloading from iCloud).
    @concurrent nonisolated static func data(at url: URL) async throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// The bytes an item provider holds: a PDF if it has one (a document scan), else a picture.
    nonisolated static func data(from provider: NSItemProvider) async -> Data? {
        let types = provider.registeredContentTypes
        guard let type = types.first(where: { $0.conforms(to: .pdf) }) ?? types.first(where: { $0.conforms(to: .image) }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let error { log.error("Couldn't load an imported page: \(error.localizedDescription)") }
                continuation.resume(returning: data)
            }
        }
    }

    nonisolated static func isPDF(_ data: Data) -> Bool { data.prefix(5) == Data("%PDF-".utf8) }

    nonisolated private static func pdf(_ data: Data) -> CGPDFDocument? {
        CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init)
    }

    /// A page drawn black on white, at most `maxPixels` on its long side, turned the way its
    /// /Rotate says (a scan saved sideways reads upright).
    nonisolated private static func render(_ page: CGPDFPage, maxPixels: Int) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let size = turned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = Double(maxPixels) / max(1, max(size.width, size.height))
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Scaled first, since the page's own transform (crop box into place, its rotation applied)
        // never scales up.
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
