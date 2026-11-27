import SwiftUI
import MangaCore

// tvOS-only SwiftUI modifiers under names that also compile on iPhone/iPad.
// On tvOS they forward to the real modifier. On iOS focus sections and the
// remote's Menu/Back and arrow commands don't exist; touch screens get their
// own controls (close buttons, swipes, tap zones), so these are no-ops there.

#if os(tvOS)
typealias RemoteMoveDirection = MoveCommandDirection
#else
enum RemoteMoveDirection { case up, down, left, right }
#endif

extension View {
    /// `focusSection()` on tvOS; nothing on iOS.
    @ViewBuilder func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// `onExitCommand` (remote Menu/Back) on tvOS; nothing on iOS.
    @ViewBuilder func onRemoteExit(perform action: (() -> Void)?) -> some View {
        #if os(tvOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }

    /// `onMoveCommand` (remote arrows) on tvOS; nothing on iOS.
    @ViewBuilder func onRemoteMove(perform action: ((RemoteMoveDirection) -> Void)?) -> some View {
        #if os(tvOS)
        onMoveCommand(perform: action)
        #else
        self
        #endif
    }
}

enum Platform {
    #if os(tvOS)
    static let isTV = true
    #else
    static let isTV = false
    #endif

    /// "Apple TV", "iPhone" or "iPad", for text like "kept on this iPhone".
    static var deviceName: String {
        #if os(tvOS)
        "Apple TV"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// iPhone only: an iPad app that supports Split View can't lock its
    /// orientation, so the reader's Orientation setting isn't offered there.
    static var canLockOrientation: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// How to retry a page that didn't load.
    static var retryHint: String { isTV ? "Press Select to retry" : "Tap to retry" }
}

extension View {
    /// The lifting focus card on tvOS; a plain press-dims button on iOS.
    @ViewBuilder func posterButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(PressDimButtonStyle())
        #endif
    }
}

/// Touch feedback for tiles: dims and shrinks slightly while pressed.
struct PressDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Poster sizes per platform


extension GridDensity {
    /// Poster width on this device. tvOS uses MangaCore's 1080p values
    /// unchanged; iPhone and iPad scale them to a hand-held screen (iPad a
    /// bit larger), see docs/IOS.md §4.
    var points: CGFloat {
        #if os(tvOS)
        CGFloat(posterWidth)
        #else
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        switch self {
        case .compact: return pad ? 120 : 80
        case .standard: return pad ? 150 : 100
        case .large: return pad ? 190 : 150
        }
        #endif
    }

    /// Gap between posters on this device.
    var spacingPoints: CGFloat {
        #if os(tvOS)
        CGFloat(spacing)
        #else
        switch self {
        case .compact: return 10
        case .standard: return 12
        case .large: return 16
        }
        #endif
    }
}

extension View {
    /// Side margins for browse screens (Home, Library, Favorites, …). On
    /// tvOS the safe area already gives 80 pt; an iPhone in portrait has
    /// none, so posters would touch the glass.
    @ViewBuilder func browseMargins() -> some View {
        #if os(tvOS)
        self
        #else
        safeAreaPadding(.horizontal, Space.l)
        #endif
    }
}

/// A spacing that differs between the 1080p TV canvas and a hand-held
/// screen, for places that don't use a design token.
func platformValue(tv: CGFloat, touch: CGFloat) -> CGFloat {
    #if os(tvOS)
    tv
    #else
    touch
    #endif
}

extension View {
    /// The large navigation title a browse tab has on iPhone and iPad. tvOS
    /// tabs have no title (the tab bar names the screen).
    @ViewBuilder func browseTitle(_ title: String) -> some View {
        #if os(tvOS)
        self
        #else
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
