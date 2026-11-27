import SwiftUI
import UIKit
import MangaCore

/// The reader's Orientation setting (`ReaderSettings.orientationLock`):
/// the app delegate asks this which orientations are allowed, and the
/// reader sets it while it's open and clears it when it closes.
@MainActor
enum OrientationGate {
    private(set) static var mask: UIInterfaceOrientationMask = .all

    static func apply(_ lock: OrientationLock) {
        guard Platform.canLockOrientation else { return }
        let next: UIInterfaceOrientationMask
        switch lock {
        case .auto: next = .all
        case .portrait: next = .portrait
        case .landscape: next = .landscape
        }
        guard next != mask else { return }
        mask = next
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: next)) { _ in }
        }
    }
}

extension View {
    /// Keeps the reader in the series' orientation while it's open.
    func readerOrientationLock(_ lock: OrientationLock?) -> some View {
        onAppear { if let lock { OrientationGate.apply(lock) } }
            .onChange(of: lock) { _, new in if let new { OrientationGate.apply(new) } }
            .onDisappear { OrientationGate.apply(.auto) }
    }
}
