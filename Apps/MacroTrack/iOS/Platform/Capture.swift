import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

/// Taking a photo with the system camera: iPhone and iPad. The Mac and Vision Pro have no camera
/// the app can take a photo with, so they choose one (Photos, Files, or one dropped on the window)
/// and the camera's buttons aren't offered.
enum Camera {
    static var isAvailable: Bool {
        #if os(iOS)
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        return false
        #endif
    }
}

/// A photo the camera just took, made ready for the models off the main thread.
struct CapturedPhoto {
    #if os(iOS)
    let image: UIImage
    #endif

    func prepared(maxDimension: CGFloat) async -> CGImage? {
        #if os(iOS)
        return await PhotoInput.prepare(image, maxDimension: maxDimension)
        #else
        return nil
        #endif
    }
}

extension View {
    /// The system camera over the screen, returning one photo (nil when cancelled). Presents only
    /// where `Camera.isAvailable`; elsewhere it's never asked to.
    func cameraCapture(isPresented: Binding<Bool>, taken: @escaping (CapturedPhoto?) -> Void) -> some View {
        #if os(iOS)
        return fullScreenCover(isPresented: isPresented) {
            CameraPicker { image in
                isPresented.wrappedValue = false
                taken(image.map(CapturedPhoto.init))
            }
            .ignoresSafeArea()
        }
        #else
        return self
        #endif
    }
}

/// Choosing a photo, for a device without a camera or a photo taken earlier: from Photos, or (off
/// the iPhone) a file from Finder or Files. `picked` gets the photo's bytes to load off the main
/// thread; a failed load throws, a missing one is nil.
struct PhotoChoices: View {
    var photosTitle = "Choose a photo"
    var fileTitle = "Choose a file…"
    let picked: (@escaping @Sendable () async throws -> Data?) -> Void
    @State private var item: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(photosTitle, systemImage: "photo.on.rectangle")
        }
        .accessibilityIdentifier("photo.choose")
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            // Cleared, so choosing the same photo again after a failure is a change.
            item = nil
            picked { try await chosen.loadTransferable(type: Data.self) }
        }
        if !Platform.isPhone {
            Button(fileTitle, systemImage: "folder") { importing = true }
                .accessibilityIdentifier("photo.chooseFile")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    picked { try await Task.detached(priority: .userInitiated) { try PhotoChoices.read(url) }.value }
                }
        }
    }

    /// A file the person chose, read inside its sandbox grant.
    nonisolated static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}

/// An image dragged onto the window from Photos, Finder or another app.
struct DroppedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
    }
}

#if os(iOS)
/// The system camera, returning one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let picked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let picked: (UIImage?) -> Void
        init(picked: @escaping (UIImage?) -> Void) { self.picked = picked }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picked(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picked(nil) }
    }
}
#endif
