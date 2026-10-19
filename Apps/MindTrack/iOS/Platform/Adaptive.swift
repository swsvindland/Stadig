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

    /// An iPhone, whose tab bar holds three tabs and no sidebar.
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

    /// Whether the key press being handled is the keyboard repeating a key held down. Only the Mac
    /// says (its current event); elsewhere every press counts.
    static var isKeyRepeat: Bool {
        #if os(macOS)
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return event.isARepeat
        #else
        return false
        #endif
    }

    /// UI tests tap faster than animations finish; nothing to wait on is steadier.
    static func disableAnimations() {
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
    }
}

/// Whether scrolling puts the on-screen keyboard away.
enum KeyboardDismissal {
    case never, interactively
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

    /// How a scroll view lets the on-screen keyboard go. Vision Pro's keyboard floats apart from the
    /// window and the Mac's is on the desk, so there it's left alone.
    func dismissesKeyboard(_ mode: KeyboardDismissal) -> some View {
        #if os(iOS)
        return scrollDismissesKeyboard(mode == .never ? .never : .interactively)
        #else
        return self
        #endif
    }

    /// A column of details beside the content (an inspector) on iPad and the Mac; Vision Pro has
    /// none, so there the details come up as a sheet.
    func detailsInspector<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(visionOS)
        return sheet(isPresented: isPresented) {
            NavigationStack {
                content().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isPresented.wrappedValue = false } } }
            }
        }
        #else
        return inspector(isPresented: isPresented) { content().inspectorColumnWidth(min: 280, ideal: 340, max: 420) }
        #endif
    }

    /// A sheet's form at a size it can be read at on the Mac, grouped as on iPhone and iPad: a Mac
    /// sheet sizes itself to its content, and a form has no size of its own.
    func sheetForm(width: CGFloat = 460, height: CGFloat = 420) -> some View {
        #if os(macOS)
        return formStyle(.grouped).frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        return self
        #endif
    }

    /// Its own size on the Mac, where a toolbar's glass or a pull-down menu would otherwise clip or
    /// stretch it; elsewhere it lays out as it always has.
    func macFixedSize() -> some View {
        #if os(macOS)
        return fixedSize()
        #else
        return self
        #endif
    }

    /// A button that's a whole row of a list. iPhone and iPad draw it as the row; the Mac would draw
    /// a push button inside the row, so there it's a plain row, in the accent colour when it's an
    /// action rather than an item.
    func rowButton(tinted: Bool = true) -> some View {
        #if os(macOS)
        return buttonStyle(.plain)
            .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        #else
        return self
        #endif
    }

    /// A search field that's always showing: under the navigation bar's title on iPhone and iPad,
    /// in the toolbar on the Mac and Vision Pro.
    func alwaysSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        return searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        #else
        return searchable(text: text, prompt: Text(prompt))
        #endif
    }

    /// The system's highlight under the pointer on iPad and where the eyes rest on Vision Pro, for a
    /// custom tappable view, in the view's own shape. The Mac's pointer needs none.
    func hoverable(in shape: some Shape = Rectangle()) -> some View {
        #if os(macOS)
        return self
        #else
        return contentShape(.hoverEffect, shape).hoverEffect()
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

    /// A card or grouped row on that page. On the Mac, as its grouped forms draw them: white on the
    /// light window, a shade lighter than the dark one (the control background matches the dark
    /// window exactly, so a card would vanish).
    static var secondaryGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .dynamic(dark: NSColor.white.withAlphaComponent(0.07), light: .controlBackgroundColor))
        #elseif os(visionOS)
        return Color.white.opacity(0.08)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Something set into a card.
    static var tertiaryGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .dynamic(dark: NSColor.white.withAlphaComponent(0.06), light: NSColor.black.withAlphaComponent(0.04)))
        #elseif os(visionOS)
        return Color.white.opacity(0.05)
        #else
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }
}

#if os(macOS)
extension NSColor {
    /// One colour for dark appearances and another for light. AppKit may resolve it on any thread,
    /// so it's made outside the main actor and captures only what's sendable.
    nonisolated static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
#endif

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
