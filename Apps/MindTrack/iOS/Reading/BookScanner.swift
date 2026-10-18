import AVFoundation
import SwiftUI
import Synchronization
import UIKit
import MindEngine
import SystemCore

/// The back camera watching for a book's barcode: its ISBN, an EAN-13 starting 978 or 979. The
/// same pattern as Macro Track's scanner (the camera's own barcode detector, on its own queue),
/// cut down to books.
nonisolated final class ISBNCamera: NSObject, @unchecked Sendable, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.svindland.stadig.mind.camera")
    private let handler = Mutex<(@Sendable (String) -> Void)?>(nil)
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
    func start(found: @escaping @Sendable (String) -> Void) async -> Bool {
        // No camera prompt under tests or UI tests.
        guard !LaunchOptions.current.isQuiet, await AVCaptureDevice.requestAccess(for: .video) else { return false }
        // The scanner closed while access was asked for: `stop` has run, so don't start after it.
        guard !Task.isCancelled else { return false }
        handler.withLock { $0 = found }
        queue.async { [self] in
            configure()
            if !session.isRunning { session.startRunning() }
        }
        return true
    }

    func stop() {
        handler.withLock { $0 = nil }
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        let metadata = AVCaptureMetadataOutput()
        if session.canAddOutput(metadata) {
            session.addOutput(metadata)
            metadata.setMetadataObjectsDelegate(self, queue: queue)
            metadata.metadataObjectTypes = [.ean13].filter(metadata.availableMetadataObjectTypes.contains)
        }
        session.commitConfiguration()
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
    }

    /// The detector reports a barcode in view on every frame: the first ISBN takes the handler, so
    /// one scan is one answer. `start` sets it again for the next scan.
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            guard let value = code.stringValue, let isbn = ISBN.normalize(value) else { continue }
            let found = handler.withLock { current in
                defer { current = nil }
                return current
            }
            found?(isbn)
            return
        }
    }
}

/// What the camera sees, filling its space.
struct ISBNCameraPreview: UIViewRepresentable {
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

/// Point at the barcode on the back of a book. Other barcodes (a price label, a grocery code) are
/// ignored; the first ISBN ends the scan.
struct BookScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void
    @State private var camera = ISBNCamera()
    @State private var torch = false
    @State private var denied = false
    @State private var typed = ""
    @State private var done = false

    var body: some View {
        NavigationStack {
            Group {
                if ISBNCamera.isAvailable && !denied {
                    ZStack {
                        ISBNCameraPreview(session: camera.session).ignoresSafeArea()
                        RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.85), lineWidth: 2)
                            .frame(width: 280, height: 150)
                            .allowsHitTesting(false)
                        VStack {
                            Text("Point at the barcode on the back")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glassEffect(.regular, in: .capsule)
                            Spacer()
                        }
                        .padding()
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                torch.toggle()
                                camera.setTorch(torch)
                            } label: {
                                Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                            }
                            .accessibilityLabel(torch ? "Turn the light off" : "Turn the light on")
                            .accessibilityIdentifier("bookScanner.torch")
                        }
                    }
                } else {
                    manual
                }
            }
            .navigationTitle("Scan the barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("bookScanner.cancel") } }
        }
        .task {
            guard ISBNCamera.isAvailable else { return }
            let started = await camera.start { isbn in
                Task { @MainActor in finish(isbn) }
            }
            denied = !started
        }
        .onDisappear { camera.stop() }
    }

    /// Without a camera (or with it turned off), the digits under the barcode do the same job.
    var manual: some View {
        Form {
            Section {
                TextField("ISBN", text: $typed)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .onSubmit { if let isbn = ISBN.normalize(typed) { finish(isbn) } }
                    .accessibilityIdentifier("bookScanner.isbn")
                Button("Look up") { if let isbn = ISBN.normalize(typed) { finish(isbn) } }
                    .disabled(ISBN.normalize(typed) == nil)
                    .accessibilityIdentifier("bookScanner.lookUp")
            } footer: {
                Text(denied ? "Camera access is off for Mind Track. Type the 13 digits under the barcode instead, or turn the camera on in Settings."
                     : "Type the 13 digits under the barcode (978 or 979 at the start), or the 10-digit ISBN inside the cover.")
            }
        }
    }

    func finish(_ isbn: String) {
        guard !done else { return }
        done = true
        camera.stop()
        found(isbn)
        dismiss()
    }
}
