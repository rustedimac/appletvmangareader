import SwiftUI

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
