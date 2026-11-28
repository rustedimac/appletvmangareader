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
                        // The panel's full size, for layout UI tests.
                        .background {
                            Color.clear
                                .accessibilityElement()
                                .accessibilityIdentifier("reader.options.panel")
                        }
                        // No Done button (John, 2026-11-28): drag the sheet down
                        // or tap outside it / the popover to close.
                        .padding(.top, Space.s)
                        .foregroundStyle(.primary)
                        // The popover's size on iPad. Only ideal sizes: a
                        // minimum wider than an iPhone sheet pushed the
                        // rows past its left edge.
                        .frame(idealWidth: 420, idealHeight: 640)
                        // Solid, so the page behind doesn't show through the rows.
                        .presentationBackground(Color(uiColor: .systemGroupedBackground))
                        // The reader is dark-backed whatever the system
                        // setting; a popover doesn't inherit the chrome's
                        // scheme, so set it on the presentation.
                        .preferredColorScheme(.dark)
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
        // While the slider moves, the page it would open.
        .overlay(alignment: .top) {
            if let dragging {
                PageThumbnail(session: session, index: Int(dragging.rounded()))
                    .offset(y: -(PageThumbnail.height + Space.m))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dragging == nil)
        .opacity(session.loadState == .loaded && session.edge == nil ? 1 : 0)
    }

    private var playing: Bool { session.isAutoScrolling || session.isAutoTurning }
}

/// A small preview of one page, above the page slider.
private struct PageThumbnail: View {
    static let height: CGFloat = 150
    let session: ReaderSession
    let index: Int
    @Environment(\.imagePipeline) private var pipeline
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.small).fill(.black.opacity(0.6))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: Self.height * 0.7, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.small))
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(Space.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityIdentifier("reader.chrome.thumbnail")
        .task(id: index) {
            image = nil
            guard let url = session.page(index)?.url else { return }
            let images = PageImages(pipeline: pipeline, server: session.server,
                                    targetSize: CGSize(width: 300, height: 450))
            if let cached = images.cached(url) { image = UIImage(cgImage: cached.cgImage); return }
            // Wait a moment so a fast drag doesn't load every page it passes.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let loaded = try? await images.load(url), !Task.isCancelled else { return }
            image = UIImage(cgImage: loaded.cgImage)
        }
    }
}
