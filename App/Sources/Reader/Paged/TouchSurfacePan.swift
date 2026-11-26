import SwiftUI
import UIKit

/// Free panning with a finger on the Siri Remote's touch surface.
///
/// SwiftUI on tvOS only reports a swipe as one arrow step
/// (`onMoveCommand`), so the zoomed page couldn't follow the finger. This
/// puts a UIKit pan recognizer for indirect touches on the window (an
/// ancestor of the focused reader, so it sees the remote's touches) while
/// `isEnabled`, and reports the finger's movement since the touch began.
/// Clicks are presses, not touches, so they still reach SwiftUI.
struct TouchSurfacePan: UIViewRepresentable {
    var isEnabled: Bool
    /// Translation in points since the finger went down.
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: HostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class HostView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchSurfacePan
        let recognizer = UIPanGestureRecognizer()
        private weak var host: UIView?

        init(_ parent: TouchSurfacePan) {
            self.parent = parent
            super.init()
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            recognizer.allowedPressTypes = []
            // Don't cancel the touches: the system still turns a quick
            // swipe into a move command, which the reader ignores while
            // the pan is moving the page.
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.isEnabled = parent.isEnabled
        }

        func attach(to view: UIView) {
            guard host !== view else { return }
            detach()
            view.addGestureRecognizer(recognizer)
            host = view
        }

        func detach() {
            host?.removeGestureRecognizer(recognizer)
            host = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed:
                let t = pan.translation(in: pan.view)
                parent.onChanged(CGSize(width: t.x, height: t.y))
            case .ended, .cancelled, .failed:
                parent.onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
