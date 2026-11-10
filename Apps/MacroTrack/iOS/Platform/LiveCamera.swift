#if os(iOS)
import AVFoundation
import FoodDatabase
import SwiftUI
import Synchronization
import UIKit

/// The back camera for live scanning: portrait frames for reading text, barcodes from the camera's
/// own detector, and the torch. Frames arrive on the camera's queue; a slow reader simply misses
/// the ones that come while it's busy.
nonisolated final class LiveCamera: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureMetadataOutputObjectsDelegate
{
    struct Handlers {
        var frame: (@Sendable (CVPixelBuffer) -> Void)?
        var barcode: (@Sendable (String, Barcode.Symbology?) -> Void)?
    }

    let session = AVCaptureSession()
    /// One queue for every scanner: two sessions setting up the same camera on two queues at once
    /// deadlock inside AVFoundation, and then no camera in the app works until it's quit.
    private static let queue = DispatchQueue(label: "dev.svindland.stadig.macro.camera")
    private var queue: DispatchQueue { Self.queue }
    private let handlers = Mutex(Handlers())
    private var device: AVCaptureDevice?
    private var configured = false

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    /// Asks for the camera if it hasn't been allowed, then starts. False when it's not allowed.
    func start(frame: @escaping @Sendable (CVPixelBuffer) -> Void, barcode: @escaping @Sendable (String, Barcode.Symbology?) -> Void) async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        // Closed while the answer came: its stop has already run, and starting now would leave a
        // session running that nobody stops, holding the camera.
        guard !Task.isCancelled else { return true }
        handlers.withLock { $0 = Handlers(frame: frame, barcode: barcode) }
        queue.async { [self] in
            configure()
            if !session.isRunning { session.startRunning() }
        }
        return true
    }

    func stop() {
        handlers.withLock { $0 = Handlers() }
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    var hasTorch: Bool { device?.hasTorch ?? false }

    func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// The camera that focuses closest: a virtual camera that switches to the ultra-wide for a
    /// label held close, starting zoomed to the wide lens; else the wide lens.
    private func configure() {
        guard !configured else { return }
        configured = true
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back)
        guard let device = discovery.devices.first, let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        if session.canAddInput(input) { session.addInput(input) }

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        video.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(video) { session.addOutput(video) }
        // Portrait frames, so text reads upright and boxes line up with the preview.
        if let connection = video.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        let metadata = AVCaptureMetadataOutput()
        if session.canAddOutput(metadata) {
            session.addOutput(metadata)
            metadata.setMetadataObjectsDelegate(self, queue: queue)
            let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .itf14]
            metadata.metadataObjectTypes = wanted.filter(metadata.availableMetadataObjectTypes.contains)
        }
        session.commitConfiguration()

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first { device.videoZoomFactor = CGFloat(truncating: wide) }
            device.unlockForConfiguration()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer, let handler = handlers.withLock({ $0.frame }) else { return }
        handler(buffer)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let handler = handlers.withLock({ $0.barcode }) else { return }
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            guard let value = code.stringValue, !value.isEmpty else { continue }
            let symbology: Barcode.Symbology? =
                switch code.type {
                case .ean13: .ean13
                case .ean8: .ean8
                case .upce: .upcE
                case .itf14: .itf14
                default: .other
                }
            handler(value, symbology)
        }
    }
}

/// What the camera sees, filling its space.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
