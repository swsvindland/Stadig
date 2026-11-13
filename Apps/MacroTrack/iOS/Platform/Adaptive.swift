import AudioToolbox
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

    /// The Mac's ⌘ or ⇧ held down during a click: nothing to ask anywhere else.
    @MainActor
    static var commandHeld: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.command)
        #else
        return false
        #endif
    }

    @MainActor
    static var shiftHeld: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.shift)
        #else
        return false
        #endif
    }

    /// What a list adds around a row's own insets: the Mac's table keeps a margin, the others none.
    static var listRowMargin: CGFloat { isMac ? 8 : 0 }

    /// Whether an amount is typed on the panel's own keypad. The Mac has a real keyboard and a
    /// focused, selected field instead.
    static var usesAmountKeypad: Bool { !isMac }

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

    /// A kitchen timer running out: the system's alert sound (and a buzz on a device that has one).
    /// The Mac's is its alert sound.
    @MainActor
    static func chime() {
        #if os(macOS)
        NSSound.beep()
        #else
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        #endif
    }

    /// UI tests tap faster than animations finish; nothing to wait on is steadier.
    static func disableAnimations() {
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
    }
}

/// A sidebar section's title. Vision Pro's tab bar is an ornament of icons, with a section in it as
/// one more: without a symbol of its own, a section there is a blank button. The iPad's tab bar and
/// the sidebars show sections by name.
struct TabSectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        #if os(visionOS)
        Label(title, systemImage: systemImage)
        #else
        Text(title)
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
    /// Hides the navigation bar where the screen sets its own title on the page, as the design does
    /// on a phone. The Mac's window has no bar to hide.
    func hidesNavigationBar(_ hidden: Bool) -> some View {
        #if os(macOS)
        return self
        #else
        return toolbarVisibility(hidden ? .hidden : .automatic, for: .navigationBar)
        #endif
    }

    func inlineTitle() -> some View {
        #if os(macOS)
        return self
        #else
        return navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// A drag down the list takes the keyboard with it, on iPhone and iPad. Vision Pro's keyboard
    /// floats apart from the window, and the Mac's isn't on screen.
    func dismissesKeyboardOnScroll() -> some View {
        #if os(iOS)
        return scrollDismissesKeyboard(.interactively)
        #else
        return self
        #endif
    }

    /// No tab bar under a page that has the screen to itself (a phone's meal plan). The tab bar is
    /// iPhone's and iPad's; the Mac's sidebar and Vision Pro's ornament stay.
    func hidesTabBar(_ hidden: Bool) -> some View {
        #if os(iOS)
        return toolbarVisibility(hidden ? .hidden : .automatic, for: .tabBar)
        #else
        return self
        #endif
    }

    /// No navigation bar: a screen with a header of its own (a phone's Today). The Mac has none to hide.
    func hidesNavigationBar() -> some View {
        #if os(macOS)
        return self
        #else
        return toolbar(.hidden, for: .navigationBar)
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

    /// Keeps the display on while this is on screen: counter mode on the counter, with hands too busy
    /// to wake it. The Mac holds off display sleep the same way.
    func keepsScreenAwake() -> some View { modifier(KeepAwake()) }

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
    /// the Mac's inset list. On iPhone and iPad the page is Stadig's ink ground; Vision Pro keeps its
    /// glass, and the Mac its window.
    func insetGroupedList() -> some View {
        #if os(macOS)
        return listStyle(.inset)
        #elseif os(visionOS)
        return listStyle(.insetGrouped)
        #else
        return listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Ink.ground.ignoresSafeArea())
        #endif
    }

    /// A form on Stadig's ink ground on iPhone and iPad, as `insetGroupedList()` puts a list (its rows
    /// take `inkRows()`). Vision Pro keeps its glass, and the Mac its window.
    func inkForm() -> some View {
        #if os(iOS)
        return scrollContentBackground(.hidden).background(Ink.ground.ignoresSafeArea())
        #else
        return self
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
        // At its widest: the window has the room, and at the ideal width the logger's ways of
        // logging ran into each other.
        return HStack(spacing: 0) {
            self
            if isPresented.wrappedValue {
                Divider()
                content().frame(width: max)
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

    /// The highlight under the eyes on Vision Pro alone, for something that's tapped rather than a
    /// button (a week's day), which the iPad's pointer and the Mac's leave as they are.
    func gazeHighlight() -> some View {
        #if os(visionOS)
        return hoverEffect(.highlight)
        #else
        return self
        #endif
    }

    /// A context menu where a click asks for it, and nothing where a hold means something else.
    @ViewBuilder
    func macContextMenu<Menu: View>(@ViewBuilder _ menu: () -> Menu) -> some View {
        #if os(macOS)
        contextMenu(menuItems: menu)
        #else
        self
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

    /// Someone going to something else and coming back, in the ways the scene phase doesn't see,
    /// since a window left in sight stays `.active`: another app in front of it on the Mac, or beside
    /// or over it on an iPad, and the Mac going to sleep with the app in front.
    func onGoingAway(left: @escaping () -> Void, returned: @escaping () -> Void) -> some View {
        modifier(GoingAway(left: left, returned: returned))
    }

    /// The Delete key on a list's selection, on the Mac. A click on a row doesn't give a list the
    /// keyboard, and a field beside it keeps it, so each change to the selection takes it there.
    /// Elsewhere a selection is deleted from its bar.
    func onDeleteKey(selection: Set<UUID>, perform: @escaping () -> Void) -> some View {
        #if os(macOS)
        return modifier(DeleteKey(selection: selection, delete: perform))
        #else
        return self
        #endif
    }
}

private struct KeepAwake: ViewModifier {
    #if os(macOS)
    @State private var activity: (any NSObjectProtocol)?
    #endif

    func body(content: Content) -> some View {
        content
            .onAppear {
                #if os(macOS)
                if activity == nil {
                    activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Prep day")
                }
                #else
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
            }
            .onDisappear {
                #if os(macOS)
                if let activity { ProcessInfo.processInfo.endActivity(activity) }
                activity = nil
                #else
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
            }
    }
}

private struct GoingAway: ViewModifier {
    let left: () -> Void
    let returned: () -> Void
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        #if os(macOS)
        let workspace = NSWorkspace.shared.notificationCenter
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in left() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in returned() }
            // The display too: a Mac on power can stay awake with nobody at it.
            .onReceive(workspace.publisher(for: NSWorkspace.willSleepNotification)) { _ in left() }
            .onReceive(workspace.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in left() }
            .onReceive(workspace.publisher(for: NSWorkspace.didWakeNotification)) { _ in woke() }
            .onReceive(workspace.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in woke() }
        #else
        content.onChange(of: appearsActive) { _, active in if active { returned() } else { left() } }
        #endif
    }

    #if os(macOS)
    /// Waking with another app in front isn't coming back to this one: that's still to come, and
    /// activation will say so.
    private func woke() { if NSApp.isActive { returned() } }
    #endif
}

#if os(macOS)
private struct DeleteKey: ViewModifier {
    let selection: Set<UUID>
    let delete: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onDeleteCommand(perform: delete)
            // On any change, not only the first: a field clicked into since has the keyboard.
            .onChange(of: selection) { _, selection in if !selection.isEmpty { focused = true } }
    }
}
#endif

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

extension Platform {
    /// A sheet's close (`SheetBar`): the round × at the top left on iPhone, iPad and Vision Pro,
    /// where a sheet also swipes down to close; on the Mac, which has no swipe, a button at the top
    /// right that says what it does (Cancel, Done), and Escape.
    static var closesSheetsInWords: Bool { isMac }
}

extension View {
    /// Room over a page that hides the navigation bar for a header of its own (`PageHeader`). The
    /// iPad's status bar and tab bar give it that room; Vision Pro's window has neither, which put
    /// the header and its round buttons in the glass's rounded corner.
    func windowTopRoom() -> some View {
        #if os(visionOS)
        return safeAreaPadding(.top, 20)
        #else
        return self
        #endif
    }

    /// A bar that stays put over a scrolling page: a header, or what sits at its foot. On iPhone,
    /// iPad and the Mac the page scrolls on under it, out of sight behind the ground the bar is drawn
    /// on. Vision Pro's glass has no ground to hide it, so the rows read through the bar's words:
    /// there the page stops at the bar instead.
    @ViewBuilder
    func pinnedBar<Bar: View>(_ edge: VerticalEdge, spacing: CGFloat? = 0, @ViewBuilder bar: () -> Bar) -> some View {
        let bar = bar()
        #if os(visionOS)
        VStack(spacing: 0) {
            if edge == .top { bar }
            self
            if edge == .bottom { bar }
        }
        #else
        safeAreaInset(edge: edge, spacing: spacing) { bar }
        #endif
    }

    /// A sheet's own bar and foot around what scrolls in it (`inkSheet`), in place of the system's
    /// navigation bar. On iPhone, iPad and Vision Pro what scrolls passes under them; on the Mac they
    /// sit above and below it, since a Mac form under an inset bar still started its first lines (the
    /// eyebrow over the title) beneath it.
    @ViewBuilder
    func sheetChrome<Bar: View, Foot: View>(bar: Bar, foot: Foot?) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            bar
            // On the ground the bar and foot stand on, not the window's grey.
            scrollContentBackground(.hidden).frame(maxHeight: .infinity)
            if let foot { foot }
        }
        #else
        if let foot {
            hidesNavigationBar()
                .safeAreaInset(edge: .top, spacing: 0) { bar }
                .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        } else {
            hidesNavigationBar().safeAreaInset(edge: .top, spacing: 0) { bar }
        }
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

extension ToolbarContent {
    /// No glass behind a toolbar item that draws its own (onboarding's ruler). Vision Pro's toolbar
    /// items have no shared background to hide.
    func withoutSharedBackground() -> some ToolbarContent {
        #if os(visionOS)
        return self
        #else
        return sharedBackgroundVisibility(.hidden)
        #endif
    }
}
