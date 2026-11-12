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

    /// An iPhone: the one device a Watch pairs with, streaming heart rate into a session led from it.
    static var canPairWatch: Bool { isPhone }

    static var isPhone: Bool { isPhoneOrPad && !isPad }

    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    /// Floor mode: an iPhone set down on the gym floor or a bench becomes the session's one big
    /// button. Only the iPhone: an iPad is propped up and read where it stands, the Mac sits on a
    /// desk, and Vision Pro is worn.
    static var hasFloorMode: Bool { isPhone }

    /// The session's scoreboard: an iPad propped against the wall, read from across the gym. Only the
    /// iPad: the Mac's session window sits on a desk, and Vision Pro puts the session where you look.
    static var hasScoreboard: Bool { isPad }

    /// Keeps the screen from dimming and locking while it's read from a metre or two away, or lets
    /// it again. Nothing else in the app holds it awake, so letting go restores the system's default.
    @MainActor
    static func keepScreenAwake(_ awake: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = awake
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

extension Optional where Wrapped == UserInterfaceSizeClass {
    /// Room for the desktop layout, and the sidebar with Program, Library and History: a regular
    /// width (iPad full screen or a wide split, Vision Pro), and always the Mac, whose windows have a
    /// minimum size and may report no size class at all. Never an iPhone, even the largest turned on
    /// its side (a regular width): its tab bar has no sidebar destinations, and it keeps its own design.
    var isWide: Bool {
        #if os(macOS)
        return true
        #else
        return self == .regular && !Platform.isPhone
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

    /// The line under a screen's title (today's date on Today). Vision Pro's window titles have none,
    /// so there it's left out; a screen that needs the line there shows it itself.
    func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
        #if os(visionOS)
        return self
        #else
        return navigationSubtitle(subtitle)
        #endif
    }

    /// A sheet's size on the Mac, where a sheet is only as big as its content asks; the system sizes
    /// sheets everywhere else.
    func sheetFrame(minWidth: CGFloat = 440, idealWidth: CGFloat = 520, minHeight: CGFloat = 420, idealHeight: CGFloat = 620) -> some View {
        #if os(macOS)
        return frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight, idealHeight: idealHeight)
        #else
        return self
        #endif
    }

    /// The trailing inspector column (a sheet in a compact width). Vision Pro has no inspector, so
    /// there it's a panel at the window's trailing edge, the same width.
    func sideInspector<Inspector: View>(
        isPresented: Binding<Bool>, minWidth: CGFloat = 300, idealWidth: CGFloat = 360, maxWidth: CGFloat = 480,
        @ViewBuilder content: () -> Inspector
    ) -> some View {
        #if os(visionOS)
        return HStack(spacing: 0) {
            self.frame(maxWidth: .infinity)
            if isPresented.wrappedValue {
                Divider()
                content().frame(width: idealWidth)
            }
        }
        #else
        return inspector(isPresented: isPresented) {
            content()
                // On the ink ground like the rest of the window, an empty one included, not the system's grey.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.pageBackground)
                .inspectorColumnWidth(min: minWidth, ideal: idealWidth, max: maxWidth)
        }
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
}

extension View {
    /// A screen read from across the room (Floor mode): no status bar and the Home indicator out of
    /// the way. Floor mode is the iPhone's; elsewhere nothing changes.
    func hidesSystemChrome(_ hidden: Bool) -> some View {
        #if os(iOS)
        return statusBarHidden(hidden).persistentSystemOverlays(hidden ? .hidden : .automatic)
        #else
        return self
        #endif
    }

    /// Home and Notification Centre, swiped from the screen's edges, wait for a second swipe, so a
    /// swipe up or down on the glass stays the app's.
    func defersEdgeSwipes() -> some View {
        #if os(iOS)
        return defersSystemGestures(on: .vertical)
        #else
        return self
        #endif
    }
}

extension View {
    /// The highlight a custom tappable view gets under a pointer on iPad and under the eyes on Vision
    /// Pro. The Mac's pointer has no lift effect: rows and buttons there highlight themselves.
    func hoverHighlight() -> some View {
        #if os(macOS)
        return self
        #else
        return hoverEffect(.highlight)
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
