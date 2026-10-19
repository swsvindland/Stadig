import ImageIO
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// The app is one target that runs natively on iPhone, iPad, the Mac and Apple Vision Pro. These are
// the calls whose spelling differs between them, so a screen says what it means once ("an inline
// title", "a number keyboard", "cover the screen") and each platform does its own native thing.
// Layout choices go by size class, not by platform: an iPad in Split View is compact like a phone.

/// The device the app is running on, for wording and for features that need hardware (a camera, a
/// Watch beside it) rather than room.
enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static var isVision: Bool {
        #if os(visionOS)
        return true
        #else
        return false
        #endif
    }

    /// iPhone or iPad: a camera the app can drive, Live Activities and a paired Watch. The Mac and
    /// Vision Pro import photos and files instead.
    static var isPhoneOrPad: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// An iPhone: the one device that keeps to the phone's ways (no file browser, a camera to hand).
    static var isPhone: Bool { isPhoneOrPad && !isPad }

    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    /// What to call this device in a sentence: "Photos are read on your iPad."
    static var deviceName: String {
        #if os(macOS)
        return "Mac"
        #elseif os(visionOS)
        return "Apple Vision Pro"
        #else
        return isPad ? "iPad" : "iPhone"
        #endif
    }

    /// This app's page in the system's Settings, for permissions turned off there (the Mac has no
    /// per-app page: it opens Privacy & Security).
    static var settingsURL: URL? {
        #if os(macOS)
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        #else
        return URL(string: UIApplication.openSettingsURLString)
        #endif
    }

    /// UI tests tap faster than animations finish; nothing to wait on is steadier.
    static func disableAnimations() {
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
    }
}

/// The keyboard a field asks for on iPhone, iPad and Vision Pro. The Mac's keyboard is the one on the desk.
enum FieldKeyboard {
    case decimal, number, numbersAndPunctuation, email, url

    #if !os(macOS)
    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .decimal: .decimalPad
        case .number: .numberPad
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .email: .emailAddress
        case .url: .URL
        }
    }
    #endif
}

extension View {
    /// The small, centred title of a pushed screen or a sheet. The Mac's window or sheet title already is one.
    func inlineTitle() -> some View {
        #if os(macOS)
        return self
        #else
        return navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func fieldKeyboard(_ keyboard: FieldKeyboard) -> some View {
        #if os(macOS)
        return self
        #else
        return keyboardType(keyboard.uiKeyboardType)
        #endif
    }

    /// Covers the whole screen on iPhone, iPad and Vision Pro. The Mac has no full-screen cover:
    /// there it's a large sheet on the window, which the person can still see around.
    func cover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        return sheet(isPresented: isPresented) {
            content().frame(minWidth: 760, idealWidth: 980, minHeight: 600, idealHeight: 780)
        }
        #else
        return fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }

    func cover<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(macOS)
        return sheet(item: item) { value in
            content(value).frame(minWidth: 760, idealWidth: 980, minHeight: 600, idealHeight: 780)
        }
        #else
        return fullScreenCover(item: item, content: content)
        #endif
    }

    /// Liquid Glass behind a floating control. Vision Pro's windows are glass already and its SDK
    /// has no `glassEffect`: a material reads the same there.
    func adaptiveGlass(in shape: some Shape = Capsule(), tint: Color? = nil, interactive: Bool = true) -> some View {
        #if os(visionOS)
        return background(.regularMaterial, in: shape)
        #else
        return glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        #endif
    }

    /// The glass prominent button style, or Vision Pro's bordered prominent one.
    func prominentGlassButtonStyle() -> some View {
        #if os(visionOS)
        return buttonStyle(.borderedProminent)
        #else
        return buttonStyle(.glassProminent)
        #endif
    }

    /// The glass button style, or Vision Pro's bordered one.
    func glassButtonStyle() -> some View {
        #if os(visionOS)
        return buttonStyle(.bordered)
        #else
        return buttonStyle(.glass)
        #endif
    }

    /// A list of grouped sections on a quiet page: inset grouped on iPhone, iPad and Vision Pro,
    /// the Mac's inset list.
    func insetGroupedList() -> some View {
        #if os(macOS)
        return listStyle(.inset)
        #else
        return listStyle(.insetGrouped)
        #endif
    }

    /// Food names and search words aren't sentences: no capital forced on the first letter. The
    /// Mac never forces one.
    func noAutocapitalization() -> some View {
        #if os(macOS)
        return self
        #else
        return textInputAutocapitalization(.never)
        #endif
    }

    /// Details beside the content: an inspector on iPhone, iPad and the Mac (a sheet in a compact
    /// width), and on Vision Pro, which has no inspector, a pane of the window beside it.
    func sideInspector<Content: View>(
        isPresented: Binding<Bool>, min: CGFloat, ideal: CGFloat, max: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(visionOS)
        return HStack(spacing: 0) {
            self
            if isPresented.wrappedValue {
                Divider()
                content().frame(width: ideal)
            }
        }
        #else
        return inspector(isPresented: isPresented) { content().inspectorColumnWidth(min: min, ideal: ideal, max: max) }
        #endif
    }

    /// Fields in a row without their names beside them on the Mac, where a form shows them; on iPhone,
    /// iPad and Vision Pro a field's name is its placeholder already.
    func macLabelsHidden() -> some View {
        #if os(macOS)
        return labelsHidden()
        #else
        return self
        #endif
    }

    /// The system's hover highlight for a custom tappable view: the pointer on iPad, the eyes on
    /// Vision Pro. The Mac's pointer needs none.
    func hoverHighlight() -> some View {
        #if os(macOS)
        return self
        #else
        return hoverEffect()
        #endif
    }

    /// A sheet's size on the Mac, where a sheet is as big as its content asks (a form can ask for
    /// very little). Elsewhere the system sizes sheets.
    func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        // A sheet doesn't take the window's form style: grouped, as on iPhone and iPad.
        return formStyle(.grouped).frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        return self
        #endif
    }

    /// The gap between a list's sections on iPhone, iPad and Vision Pro; the Mac's lists keep their own.
    func sectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(macOS)
        return self
        #else
        return listSectionSpacing(spacing)
        #endif
    }

    /// Picking a time of day: the wheel on iPhone, iPad and Vision Pro, the Mac's clock and field.
    func timeOfDayPickerStyle() -> some View {
        #if os(macOS)
        return datePickerStyle(.graphical)
        #else
        return datePickerStyle(.wheel)
        #endif
    }
}

extension SearchFieldPlacement {
    /// A search field that stays in view under the title on iPhone, iPad and Vision Pro, and sits
    /// in the window's toolbar on the Mac.
    static var alwaysShown: SearchFieldPlacement {
        #if os(macOS)
        return .toolbar
        #else
        return .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The trailing end of the navigation bar; on the Mac, the toolbar's primary spot.
    static var barTrailing: ToolbarItemPlacement {
        #if os(macOS)
        return .primaryAction
        #else
        return .topBarTrailing
        #endif
    }

    /// The leading end of the navigation bar; on the Mac, next to the window's title.
    static var barLeading: ToolbarItemPlacement {
        #if os(macOS)
        return .navigation
        #else
        return .topBarLeading
        #endif
    }
}

extension Color {
    /// A grouped list's page: the system grouped background on iPhone and iPad, the window's on the
    /// Mac, and nothing on Vision Pro, where the window's glass is the page.
    static var groupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #elseif os(visionOS)
        return .clear
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// A card or grouped row on that page.
    static var secondaryGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #elseif os(visionOS)
        return Color.white.opacity(0.08)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Something set into a card.
    static var tertiaryGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #elseif os(visionOS)
        return Color.white.opacity(0.05)
        #else
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Photos as data, through ImageIO, the same on every platform: decoded at the size they're shown
/// (never whole into memory first) and written as JPEG.
enum ImageData {
    /// The image in `data`, at most `maxPixels` on its long side, upright (orientation applied).
    nonisolated static func downsampled(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func jpeg(_ image: CGImage, quality: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A JPEG of `data` at most `maxPixels` on its long side.
    nonisolated static func resizedJPEG(_ data: Data, maxPixels: Int, quality: Double = 0.8) -> Data? {
        downsampled(data, maxPixels: maxPixels).flatMap { jpeg($0, quality: quality) }
    }
}
