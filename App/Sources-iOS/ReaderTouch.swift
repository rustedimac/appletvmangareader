import SwiftUI
import MangaCore

// The touch layer for the readers (docs/IOS.md §3). The rules (what a tap
// in each third does, when a swipe turns, zoom limits) are MangaCore's
// `ReaderTouch`; this file maps gestures to them and draws the chrome.

extension View {
    /// Reports taps by thirds of the view's width. Buttons inside the view
    /// keep their own taps.
    func readerTapRegions(_ action: @escaping (TapRegion) -> Void) -> some View {
        modifier(ReaderTapRegionsModifier(action: action))
    }

    /// Status bar and home indicator follow the chrome.
    func readerSystemOverlays(visible: Bool) -> some View {
        statusBarHidden(!visible)
            .persistentSystemOverlays(visible ? .automatic : .hidden)
    }
}

private struct ReaderTapRegionsModifier: ViewModifier {
    let action: (TapRegion) -> Void
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .onTapGesture(coordinateSpace: .local) { point in
                action(TapRegion(x: Double(point.x), width: Double(width)))
            }
    }
}

/// The reader's controls on touch screens: a top bar (Close, title,
/// bookmark, options) and, when `bottom` is given, a bottom bar. Both hide
/// together with the status bar and home indicator.
struct ReaderTouchChrome<Options: View, Bottom: View>: View {
    let title: String
    let subtitle: String?
    var isBookmarked: Bool? = nil
    var onBookmark: () -> Void = {}
    let onClose: () -> Void
    @Binding var optionsPresented: Bool
    @ViewBuilder let options: () -> Options
    @ViewBuilder let bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.xs) {
                barButton("xmark", label: "Close", id: "reader.chrome.close", action: onClose)
                VStack(spacing: Space.xxs) {
                    Text(title).font(.headline).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                if let isBookmarked {
                    barButton(isBookmarked ? "bookmark.fill" : "bookmark",
                              label: isBookmarked ? "Remove Bookmark" : "Bookmark This Page",
                              id: "reader.chrome.bookmark", action: onBookmark)
                }
                barButton("slider.horizontal.3", label: "Reader Options", id: "reader.chrome.options") {
                    optionsPresented.toggle()
                }
                .popover(isPresented: $optionsPresented, arrowEdge: .top) {
                    options()
                        .safeAreaInset(edge: .top, spacing: 0) {
                            HStack {
                                Spacer()
                                Button("Done") { optionsPresented = false }
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("reader.options.done")
                            }
                            .padding(.horizontal, Space.l)
                            .padding(.top, Space.m)
                        }
                        .foregroundStyle(.primary)
                        .frame(minWidth: 380, idealWidth: 420, minHeight: 420, idealHeight: 640)
                        // Solid, so the page behind doesn't show through the rows.
                        .presentationBackground(Color(uiColor: .systemGroupedBackground))
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationCompactAdaptation(.sheet)
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.xs)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reader.chrome")
            Spacer(minLength: 0)
            bottom()
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private func barButton(_ symbol: String, label: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: Size.minTarget, height: Size.minTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Page slider, page number and Play for the image readers.
struct ReaderPageBar: View {
    let session: ReaderSession
    /// The slider's value while a finger is on it; the page jumps on release.
    @State private var dragging: Double?

    var body: some View {
        let count = max(1, session.pageCount)
        let page = dragging.map { Int($0.rounded()) } ?? min(session.currentPage, count - 1)
        HStack(spacing: Space.m) {
            Button {
                session.togglePlay()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .frame(width: Size.minTarget, height: Size.minTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(playing ? "Pause" : (session.settings.mode == .webtoon ? "Auto-Scroll" : "Page Timer"))
            .accessibilityIdentifier("reader.chrome.play")
            if count > 1 {
                Slider(value: Binding(get: { dragging ?? Double(page) }, set: { dragging = $0 }),
                       in: 0...Double(count - 1), step: 1) { editing in
                    if !editing, let value = dragging {
                        session.jump(toPage: Int(value.rounded()))
                        dragging = nil
                    }
                }
                // Right-to-left manga: page 1 sits on the right.
                .environment(\.layoutDirection,
                             session.settings.mode == .paged && session.settings.direction == .rightToLeft
                                ? .rightToLeft : .leftToRight)
                .accessibilityIdentifier("reader.chrome.slider")
                .accessibilityValue("Page \(page + 1) of \(count)")
            } else {
                Spacer()
            }
            Text("\(page + 1) / \(count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("reader.chrome.pageNumber")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(.ultraThinMaterial)
        .opacity(session.loadState == .loaded && session.edge == nil ? 1 : 0)
    }

    private var playing: Bool { session.isAutoScrolling || session.isAutoTurning }
}
