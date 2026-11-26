import SwiftUI

/// Sends a tab back to its top-level screen once it has been out of sight
/// for a while. Open Settings > Customize Home, switch to Library, and come
/// back within `delay`: Customize Home is still there. Come back later and
/// Settings shows its main list again, like the Apple TV's own apps.
///
/// RootView owns one and reports tab changes. A tab opts in with
/// `.navigationResetTab("settings")` (in RootView) and
/// `.resetsNavigationWhenLeft()` on its NavigationStack (pass the stack's
/// path binding when it has one). Only the stack is rebuilt, so state the
/// tab keeps outside it (Search's query and results, Home's rows) stays.
@MainActor @Observable
final class NavigationReset {
    /// How long a tab can be out of sight and still keep its screens.
    /// `-uiTestingNavigationResetDelay <seconds>` shortens it for tests.
    let delay: Duration
    private(set) var generations: [String: Int] = [:]
    @ObservationIgnored private var pending: [String: Task<Void, Never>] = [:]

    init(delay: Duration = UITestingSeed.navigationResetDelay ?? .seconds(10)) {
        self.delay = delay
    }

    func generation(for tab: String) -> Int { generations[tab, default: 0] }

    /// Call whenever the selected tab changes.
    func tabChanged(from old: String, to new: String) {
        pending[new]?.cancel()
        pending[new] = nil
        guard old != new else { return }
        pending[old]?.cancel()
        pending[old] = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reset(old)
        }
    }

    /// Pops `tab` back to its root now.
    func reset(_ tab: String) {
        pending[tab] = nil
        generations[tab, default: 0] += 1
    }
}

private struct NavigationResetTabKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The tab a view lives in, for `NavigationReset`.
    var navigationResetTab: String? {
        get { self[NavigationResetTabKey.self] }
        set { self[NavigationResetTabKey.self] = newValue }
    }
}

extension View {
    /// Names the tab this view tree belongs to (set in RootView).
    func navigationResetTab(_ tab: String) -> some View {
        environment(\.navigationResetTab, tab)
    }

    /// Put on a tab's NavigationStack: rebuilds it at its root (and empties
    /// `path`) when `NavigationReset` resets the tab.
    func resetsNavigationWhenLeft(path: Binding<NavigationPath>? = nil) -> some View {
        modifier(ResetsNavigationModifier(path: path))
    }
}

private struct ResetsNavigationModifier: ViewModifier {
    @Environment(NavigationReset.self) private var reset: NavigationReset?
    @Environment(\.navigationResetTab) private var tab
    let path: Binding<NavigationPath>?

    func body(content: Content) -> some View {
        let generation = tab.flatMap { reset?.generation(for: $0) } ?? 0
        content
            .id(generation)
            .onChange(of: generation) {
                path?.wrappedValue = NavigationPath()
            }
    }
}
