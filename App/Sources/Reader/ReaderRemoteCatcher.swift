import SwiftUI
import UIKit

/// Siri Remote input the readers need that SwiftUI can't tell apart:
///
/// - **Play/Pause pressed** vs **Play/Pause held** (0.5 s). SwiftUI's
///   `onPlayPauseCommand` has no hold, and holding Play/Pause is how the
///   reader options open (docs/READER_CONTROLS.md section 10).
/// - A **tap** on the touch surface, which is not a click: it shows the
///   page number (the HUD).
/// - **Menu (Back)** while `takesMenu` says a reader layer (the options or
///   the page scrubber) is open. SwiftUI's `onExitCommand` only runs when
///   focus is inside the view that declares it; when focus drops out of
///   the drawer for a moment (a focused row goes away, a tab switch, a
///   reader mode switch), the press falls through to the full-screen cover
///   the reader is in, and tvOS dismisses the cover: Back closed the reader
///   with its options open. Taken here, the press never reaches the views,
///   whatever has focus.
///
/// Put it in the reader's background. While it is in a window it adds
/// gesture recognizers to that window, so they see the remote whichever
/// view has focus (the page, the reader options, the page scrubber), and it
/// removes them when the reader goes away. The readers must not handle
/// Play/Pause anywhere else, or one press would act twice.
struct ReaderRemoteCatcher: UIViewRepresentable {
    /// Play/Pause pressed and let go before the hold time.
    var onPlayPause: () -> Void
    /// Play/Pause held for `holdDuration`. Fires while still held.
    var onPlayPauseHold: () -> Void
    /// A light tap on the touch surface with no click.
    var onTap: () -> Void = {}
    /// True while Menu belongs to the reader (checked when the press
    /// starts). False lets the press through to the views as usual.
    var takesMenu: () -> Bool = { false }
    /// Menu pressed while `takesMenu` was true.
    var onMenu: () -> Void = {}

    static let holdDuration: TimeInterval = 0.5

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        context.coordinator.handlers = self
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(handlers: self) }

    final class CatcherView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: ReaderRemoteCatcher
        private weak var window: UIWindow?
        private var recognizers: [UIGestureRecognizer] = []
        private weak var menuRecognizer: UIGestureRecognizer?
        /// When a click (Select) was last pressed, so a click's touch isn't
        /// also taken as a tap.
        private var lastSelect: CFTimeInterval = 0

        init(handlers: ReaderRemoteCatcher) {
            self.handlers = handlers
        }

        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window

            let playPause = NSNumber(value: UIPress.PressType.playPause.rawValue)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.allowedPressTypes = [playPause]
            hold.allowedTouchTypes = []
            hold.minimumPressDuration = ReaderRemoteCatcher.holdDuration
            hold.delegate = self

            let press = UITapGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.allowedPressTypes = [playPause]
            press.allowedTouchTypes = []
            press.require(toFail: hold)
            press.delegate = self

            // Watches Select without taking it: never recognizes, only notes
            // the time (see `gestureRecognizer(_:shouldReceive:)`).
            let select = UITapGestureRecognizer(target: nil, action: nil)
            select.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            select.allowedTouchTypes = []
            select.cancelsTouchesInView = false
            select.delaysTouchesBegan = false
            select.delaysTouchesEnded = false
            select.delegate = self

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            tap.allowedPressTypes = []
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self

            // Menu, only while `takesMenu` (see `shouldReceive`). Presses
            // are held back from the views until it fails, so a taken press
            // never reaches `onExitCommand` or the cover's own dismissal.
            let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed(_:)))
            menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            menu.allowedTouchTypes = []
            menu.delaysPressesBegan = true
            menu.delegate = self

            menuRecognizer = menu
            recognizers = [hold, press, select, tap, menu]
            recognizers.forEach(window.addGestureRecognizer)
        }

        func detach() {
            recognizers.forEach { $0.view?.removeGestureRecognizer($0) }
            recognizers = []
            window = nil
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            handlers.onPlayPauseHold()
        }

        @objc private func pressed(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            handlers.onPlayPause()
        }

        @objc private func menuPressed(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            handlers.onMenu()
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            // A click lands its press and its touch at about the same time;
            // wait a moment and drop the tap if a click came with it.
            let at = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, abs(self.lastSelect - at) > 0.6 else { return }
                self.handlers.onTap()
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            if press.type == .select {
                lastSelect = CACurrentMediaTime()
                // Only noted; never let these recognizers take a click.
                return false
            }
            if press.type == .menu {
                return gestureRecognizer.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.menu.rawValue))
                    && handlers.takesMenu()
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // A taken Menu is the reader's alone. Otherwise never block the
            // readers' own recognizers (the vertical reader's swipe pan) or
            // the focus engine.
            if gestureRecognizer === menuRecognizer || other === menuRecognizer { return false }
            return !recognizers.contains(other)
        }
    }
}
