import Foundation
import GameController
import QuartzCore
import MangaCore

/// Listens to connected game controllers (Xbox, PlayStation, MFi, 8BitDo)
/// and hands the buttons tvOS doesn't already map to whoever is on top: the
/// open reader. Mapping: `GamepadMapping`. The d-pad, A and B (and the Siri Remote) keep working through
/// the focus engine as arrow, select and Menu presses, so browsing needs
/// nothing from here.
///
/// Readers register with `push(owner:onButton:onStick:)` while they're on
/// screen and `remove(owner:)` when they go. Handlers run on the main queue.
@MainActor
final class GameControllerHub {
    static let shared = GameControllerHub()

    private struct Handler {
        let owner: ObjectIdentifier
        let onButton: (GamepadButton) -> Void
        let onStick: (_ x: Double, _ y: Double) -> Void
    }

    private var handlers: [Handler] = []
    private var started = false
    private var sticks: [ObjectIdentifier: (left: (Double, Double), right: (Double, Double))] = [:]
    /// When a stick was last pushed past the dead zone.
    private(set) var lastStickActivity: CFTimeInterval = 0
    /// When a controller's d-pad was last pressed.
    fileprivate(set) var lastDpadActivity: CFTimeInterval = 0

    /// Whether any controller with sticks and shoulder buttons is connected.
    var hasExtendedGamepad: Bool { GCController.controllers().contains { $0.extendedGamepad != nil } }

    /// True while a stick is pushed, or was a moment ago. The webtoon
    /// reader ignores arrow presses then, in case tvOS turns the stick into
    /// arrow presses as well as reporting it to us.
    var stickRecentlyActive: Bool { CACurrentMediaTime() - lastStickActivity < 0.2 }

    /// True when the arrow press just received came from a controller's
    /// d-pad, not the Siri Remote. On a controller the d-pad only
    /// navigates (no bookmark or page thumbnails from up/down).
    var dpadRecentlyActive: Bool { CACurrentMediaTime() - lastDpadActivity < 0.3 }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { GameControllerHub.shared.configure(controller) }
        }
        center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { GameControllerHub.shared.disconnected(controller) }
        }
        GCController.controllers().forEach(configure)
    }

    func push(owner: AnyObject, onButton: @escaping (GamepadButton) -> Void,
              onStick: @escaping (_ x: Double, _ y: Double) -> Void) {
        start()
        remove(owner: owner)
        handlers.append(Handler(owner: ObjectIdentifier(owner), onButton: onButton, onStick: onStick))
    }

    func remove(owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        if let top = handlers.last, top.owner == id { top.onStick(0, 0) }
        handlers.removeAll { $0.owner == id }
    }

    // MARK: Controllers

    private func configure(_ controller: GCController) {
        controller.handlerQueue = .main
        guard let pad = controller.extendedGamepad else { return }
        var buttons: [(GCControllerButtonInput, GamepadButton)] = [
            (pad.leftShoulder, .leftShoulder),
            (pad.rightShoulder, .rightShoulder),
            (pad.leftTrigger, .leftTrigger),
            (pad.rightTrigger, .rightTrigger),
            (pad.buttonX, .buttonX),
            (pad.buttonY, .buttonY),
        ]
        buttons.append((pad.buttonMenu, .menu))
        if let options = pad.buttonOptions { buttons.append((options, .options)) }
        for (input, button) in buttons {
            input.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { GameControllerHub.shared.dispatch(button) }
            }
        }
        let id = ObjectIdentifier(controller)
        pad.dpad.valueChangedHandler = { _, x, y in
            guard x != 0 || y != 0 else { return }
            MainActor.assumeIsolated { GameControllerHub.shared.lastDpadActivity = CACurrentMediaTime() }
        }
        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { GameControllerHub.shared.stick(id, left: (Double(x), Double(y))) }
        }
        pad.rightThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { GameControllerHub.shared.stick(id, right: (Double(x), Double(y))) }
        }
    }

    private func disconnected(_ controller: GCController) {
        sticks[ObjectIdentifier(controller)] = nil
        report()
    }

    private func dispatch(_ button: GamepadButton) {
        handlers.last?.onButton(button)
    }

    private func stick(_ id: ObjectIdentifier, left: (Double, Double)? = nil, right: (Double, Double)? = nil) {
        var entry = sticks[id] ?? (left: (0, 0), right: (0, 0))
        if let left { entry.left = left }
        if let right { entry.right = right }
        sticks[id] = entry
        report()
    }

    /// Reports the stick pushed furthest (vertically) across all controllers.
    private func report() {
        var best: (Double, Double) = (0, 0)
        for entry in sticks.values {
            for s in [entry.left, entry.right] where abs(s.1) > abs(best.1) || (abs(s.1) == abs(best.1) && abs(s.0) > abs(best.0)) {
                best = s
            }
        }
        if GamepadStick.isDeflected(x: best.0, y: best.1) { lastStickActivity = CACurrentMediaTime() }
        handlers.last?.onStick(best.0, best.1)
    }
}
