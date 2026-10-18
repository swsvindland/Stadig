import OSLog
import PencilKit
import SwiftUI
import VisionKit

/// A page to write on with Apple Pencil (or a finger, unless the system is set to draw only with
/// Pencil): ruled, scrolling, with a pen and an eraser.
struct HandwritingPad: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var erasing: Bool

    static let pageHeight: CGFloat = 2400
    static let ruling: CGFloat = 44

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        let paper = RuledPaper(spacing: Self.ruling)
        paper.frame = CGRect(x: 0, y: 0, width: 3000, height: Self.pageHeight)
        canvas.insertSubview(paper, at: 0)
        canvas.contentSize = CGSize(width: 0, height: Self.pageHeight)
        canvas.accessibilityLabel = "Handwriting page"
        canvas.accessibilityHint = "Write with Apple Pencil. When you're done, read your handwriting into text."
        apply(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
        apply(canvas)
    }

    func apply(_ canvas: PKCanvasView) {
        canvas.tool = erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .label, width: 3)
        canvas.contentSize.width = canvas.bounds.width
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) { drawing.wrappedValue = canvas.drawing }
    }

    /// The drawing as dark ink on white, cropped to what's written, for text recognition. A full
    /// page is two large bitmaps, so it's drawn off the main actor.
    @concurrent nonisolated static func inkImage(of drawing: PKDrawing) async -> CGImage? { image(of: drawing) }

    nonisolated static func image(of drawing: PKDrawing) -> CGImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { ink = drawing.image(from: bounds, scale: 2) }
        guard let ink else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = ink.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: ink.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }.cgImage
    }
}

/// Faint ruled lines behind the ink: one small tile repeated, so a tall page costs no memory.
private final class RuledPaper: UIView {
    init(spacing: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 8, height: spacing)).image { context in
            UIColor.systemGray.withAlphaComponent(0.3).setFill()
            context.fill(CGRect(x: 0, y: spacing - 1, width: 8, height: 1))
        }
        backgroundColor = UIColor(patternImage: tile)
    }

    required init?(coder: NSCoder) { nil }
}

/// VisionKit's document camera: pages photographed flat and cropped, ready to read.
struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([CGImage]) -> Void
    let cancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done, cancel: cancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([CGImage]) -> Void
        let cancel: () -> Void

        init(done: @escaping ([CGImage]) -> Void, cancel: @escaping () -> Void) {
            self.done = done
            self.cancel = cancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { cancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            appLog.error("The document camera failed: \(error.localizedDescription)")
            cancel()
        }
    }
}
