import SwiftUI
import MangaCore

// First touch layer for the readers (docs/IOS.md §3, PR 1): a tap in the
// centre third shows or hides the chrome, a tap in a side third turns the
// page (or scrolls the vertical reader). Swipes, pinch, the page slider and
// the tap-zone setting come with the full touch reader (PR 2).

/// Which third of the reader a tap landed in.
enum ReaderTapZone: Equatable {
    case leading, center, trailing

    init(x: CGFloat, width: CGFloat) {
        guard width > 0 else { self = .center; return }
        switch x / width {
        case ..<(1.0 / 3): self = .leading
        case (2.0 / 3)...: self = .trailing
        default: self = .center
        }
    }
}

extension View {
    /// Reports taps by thirds of the view's width. Buttons inside the view
    /// (menus, chrome) keep their own taps.
    func readerTapZones(_ action: @escaping (ReaderTapZone) -> Void) -> some View {
        modifier(ReaderTapZonesModifier(action: action))
    }
}

private struct ReaderTapZonesModifier: ViewModifier {
    let action: (ReaderTapZone) -> Void
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .onTapGesture(coordinateSpace: .local) { point in
                action(ReaderTapZone(x: point.x, width: width))
            }
    }
}

/// The reader's top bar on touch screens: Close, the title, and the
/// options button. Hides with the status bar and home indicator.
struct ReaderTouchChrome: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let onOptions: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: Size.minTarget, height: Size.minTarget)
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("reader.chrome.close")
                VStack(spacing: Space.xxs) {
                    Text(title).font(.headline).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                Button(action: onOptions) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .frame(width: Size.minTarget, height: Size.minTarget)
                }
                .accessibilityLabel("Reader Options")
                .accessibilityIdentifier("reader.chrome.options")
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.s)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.chrome")
    }
}

extension View {
    /// Status bar and home indicator follow the chrome.
    func readerSystemOverlays(visible: Bool) -> some View {
        statusBarHidden(!visible)
            .persistentSystemOverlays(visible ? .automatic : .hidden)
    }
}
