import SwiftUI
import UIKit

/// Keeps the top tab bar fully on screen when focus goes back up to it.
///
/// On tvOS the tab bar slides up with the content as a screen scrolls down,
/// and slides back as the content scrolls back to the top. When focus jumps
/// from the content straight to the tab bar (because nothing focusable sits
/// above it: a message over the first Home row, the hero column next to a
/// settings form, a row header), nothing scrolls the content back, so the tab
/// bar stays partly off the top of the screen while it has focus.
///
/// This watches focus app-wide. When focus lands on the tab bar, every
/// visible vertical scroll view (SwiftUI `ScrollView`, `List` and `Form` are
/// all backed by one) scrolls back to its top, which brings the tab bar all
/// the way down. Horizontal shelves are left alone. One observer covers
/// every tab and every pushed screen, so new screens get it for free.
@MainActor
enum TabBarScrollReset {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
        ) { note in
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            MainActor.assumeIsolated { focusDidUpdate(context) }
        }
    }

    private static func focusDidUpdate(_ context: UIFocusUpdateContext?) {
        guard let next = context?.nextFocusedView, isInTabBar(next), let window = next.window else { return }
        // Moving between tabs inside the bar needs nothing new.
        if let previous = context?.previouslyFocusedView, isInTabBar(previous) { return }
        scrollToTop(in: window)
    }

    /// Whether `view` is part of the system tab bar.
    static func isInTabBar(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v is UITabBar || String(describing: type(of: v)).contains("TabBar") { return true }
            current = v.superview
        }
        return false
    }

    /// Scrolls every visible, vertically scrolled scroll view in `window`
    /// back to its top.
    static func scrollToTop(in window: UIWindow) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        for scrollView in verticalScrollViews(in: window, window: window) {
            let top = -scrollView.adjustedContentInset.top
            guard scrollView.contentOffset.y > top + 0.5 else { continue }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: animated)
        }
    }

    private static func verticalScrollViews(in view: UIView, window: UIWindow) -> [UIScrollView] {
        guard !view.isHidden, view.alpha > 0.01, !(view is UITabBar) else { return [] }
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView, isOnScreenVertical(scrollView, window: window) {
            found.append(scrollView)
        }
        for subview in view.subviews {
            found += verticalScrollViews(in: subview, window: window)
        }
        return found
    }

    private static func isOnScreenVertical(_ scrollView: UIScrollView, window: UIWindow) -> Bool {
        let frame = scrollView.convert(scrollView.bounds, to: window)
        guard frame.intersects(window.bounds), frame.width > 0, frame.height > 0 else { return false }
        // Shelves scroll sideways; only reset scroll views that scroll up and down.
        let insets = scrollView.adjustedContentInset
        let scrollsVertically = scrollView.contentSize.height + insets.top + insets.bottom > scrollView.bounds.height + 1
        let scrollsSideways = scrollView.contentSize.width + insets.left + insets.right > scrollView.bounds.width + 1
        return scrollsVertically && !scrollsSideways
    }
}
