import SwiftUI
import MangaCore

/// The page-turner reader. Shows one spread at a time: two pages joined edge
/// to edge at a common height, or one page alone (cover, wide spread, or
/// single-page layout).
///
/// Siri Remote: left/right (click or swipe) turns the page, following the
/// reading direction. Swipe down or Play/Pause opens the reader menu; swipe
/// or click up bookmarks the page (again removes it) unless there is more
/// of the page above to pan to. Going
/// past the first or last spread shows a chapter transition card; pressing
/// again opens the previous or next chapter.
///
/// Fit and zoom: with Fit Width (or Fit Height on a wide spread) the spread
/// is bigger than the screen and the remote pans over it before turning
/// (`PagedRemote` has the rules). Clicking zooms in to `zoomScale` around
/// the middle of the screen; click again or press Menu to zoom out. Turning
/// the page resets the zoom.
///
/// Crop Borders: each page's white or black margins are detected once
/// (`BorderCropDetector`, cached in `PageCropCache`) and trimmed. In a
/// two-page spread the pages share their top and bottom crop and the
/// inner edges are kept, so the halves still meet seamlessly.
struct PagedReaderView: View {
    let session: ReaderSession

    @State private var preloading: Set<URL> = []
    @State private var cropTasks: [URL: Task<Void, Never>] = [:]
    @State private var viewport = PagedViewport()
    /// Whether the last turn went forward, so the next spread opens at its
    /// start (top) or, reading backward, at its end (bottom).
    @State private var arrivedForward = true
    @State private var container: CGSize = .zero
    @FocusState private var focused: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imagePipeline) private var pipeline

    init(session: ReaderSession) {
        self.session = session
        _viewport = State(initialValue: .start(session.settings.direction))
    }

    private var settings: ReaderSettings { session.settings }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let edge = session.edge {
                    ChapterTransitionCard(session: session, edge: edge)
                } else if let spread = session.currentSpread {
                    let layout = spreadLayout(spread, in: geo.size)
                    SpreadView(session: session, layout: layout, images: images(for: geo.size),
                               viewport: viewport, container: geo.size, scale: displayScale)
                        .id(spread)
                }
                if session.loadState == .loaded, session.pageCount > 0 {
                    PageIndicator(session: session, viewport: viewport)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onChange(of: geo.size, initial: true) { _, size in container = size }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.paged")
        .onMoveCommand(perform: handleMove)
        .onPlayPauseCommand { session.isMenuPresented = true }
        // Select retries failed pages on screen first, otherwise zooms.
        .onTapGesture { if !session.retryVisibleFailedPages() { toggleZoom() } }
        // Menu zooms out first; when not zoomed it falls through to
        // ReaderView, which closes the reader.
        .onExitCommand(perform: exitAction)
        .onAppear {
            focused = true
        }
        .onChange(of: session.isMenuPresented) { _, presented in
            if !presented { focused = true }
        }
        .onChange(of: session.currentSpread) { _, _ in
            viewport = arrivedForward ? .start(settings.direction) : .end(settings.direction)
        }
        .onChange(of: settings.fit) { _, _ in viewport = .start(settings.direction) }
        .task(id: PreloadKey(chapterID: session.chapter.id, spread: session.currentSpread,
                             count: session.pageCount, loaded: session.loadState == .loaded,
                             target: targetPixels(container), crop: settings.cropBorders)) {
            preload()
        }
        .onDisappear {
            pipeline.cancelPrefetch(Array(preloading))
            preloading = []
            cropTasks.values.forEach { $0.cancel() }
            cropTasks = [:]
        }
    }

    private var exitAction: (() -> Void)? {
        guard viewport.isZoomed else { return nil }
        return { setZoom(1) }
    }

    // MARK: Layout

    /// Frames for the spread under the current fit and crop settings. A
    /// split wide page is laid out as half its width.
    private func spreadLayout(_ spread: Spread, in size: CGSize) -> SpreadLayoutInfo {
        let order = spread.screenOrder(settings.direction)
        let half = spread.half
        let crops: [CropInsets]
        if !settings.cropBorders {
            crops = order.map { _ in .zero }
        } else if let half {
            crops = order.map { SpreadCrop.half(session.crop(ofPage: $0), half) }
        } else {
            crops = SpreadCrop.insets(order.map { session.crop(ofPage: $0) })
        }
        let sizes: [PageSize?] = zip(order, crops).map { page, crop in
            session.size(ofPage: page).map { size in
                crop.cropped(half == nil ? size : PageSize(width: size.width / 2, height: size.height))
            }
        }
        let canvas = SpreadGeometry.canvas(for: sizes, in: Double(size.width), Double(size.height),
                                           fit: settings.fit, scale: Double(displayScale))
        return SpreadLayoutInfo(pages: order, crops: crops, half: half, canvas: canvas)
    }

    private var screen: Extent { Extent(width: Double(container.width), height: Double(container.height)) }

    private var currentCanvas: Extent {
        guard let spread = session.currentSpread, container != .zero else { return screen }
        return spreadLayout(spread, in: container).canvas.size
    }

    // MARK: Images

    /// Pages are decoded for how they're shown: to fit the screen, or wide
    /// (Fit Width) or tall (Fit Height) enough for the bigger canvas, with
    /// a little headroom when margins are cropped. The same target for
    /// preloads and on-screen loads means preloaded pages are cache hits.
    private func images(for container: CGSize) -> PageImages {
        PageImages(pipeline: pipeline, server: session.server, targetSize: targetPixels(container))
    }

    private func targetPixels(_ container: CGSize) -> CGSize {
        let w = (container.width * displayScale).rounded()
        let h = (container.height * displayScale).rounded()
        let headroom: CGFloat = settings.cropBorders ? 1.2 : 1
        switch settings.fit {
        case .screen: return CGSize(width: (w * headroom).rounded(), height: (h * headroom).rounded())
        case .width: return CGSize(width: (w * headroom).rounded(), height: (h * 3).rounded())
        case .height: return CGSize(width: (w * 3).rounded(), height: (h * headroom).rounded())
        }
    }

    // MARK: Remote

    private func handleMove(_ direction: MoveCommandDirection) {
        let press: PanDirection
        switch direction {
        case .left: press = .left
        case .right: press = .right
        case .up: press = .up
        case .down: press = .down
        @unknown default: return
        }
        // The transition card has nothing to pan.
        if session.edge != nil {
            if press == .left || press == .right { turn(press == .left ? .left : .right) }
            else if press == .down { session.isMenuPresented = true }
            return
        }
        switch PagedRemote.action(for: press, viewport: viewport, canvas: currentCanvas,
                                  screen: screen, direction: settings.direction) {
        case .pan(let next):
            withAnimation(.easeInOut(duration: 0.25)) { viewport = next }
        case .turn(let screenDirection):
            turn(screenDirection)
        case .openMenu:
            session.isMenuPresented = true
        case .none:
            // Up with nothing above to pan to bookmarks the page (again
            // removes it).
            if press == .up { session.toggleBookmark() }
        }
    }

    private func turn(_ direction: ScreenDirection) {
        arrivedForward = settings.direction.isForward(direction)
        session.turn(direction)
    }

    private func toggleZoom() {
        guard session.edge == nil, session.currentSpread != nil else { return }
        setZoom(viewport.isZoomed ? 1 : settings.clampedZoomScale)
    }

    private func setZoom(_ zoom: Double) {
        let next = viewport.zoomed(to: zoom, canvas: currentCanvas, screen: screen)
        withAnimation(.easeInOut(duration: 0.25)) { viewport = next }
    }

    // MARK: Preloading

    /// Loads ±2 spreads around the current one, nearest first, and records
    /// sizes as they arrive so later spreads pair correctly before they are
    /// shown. With Crop Borders on, margins are detected for those pages
    /// too, so a page's crop is known before it comes on screen.
    private func preload() {
        let target = targetPixels(container)
        guard session.loadState == .loaded, container != .zero else { return }
        // Pages on screen are loaded by their own views at full priority.
        let visible = Set(session.visiblePages)
        let indices = session.navigator.pagesToPreload(radius: 2).filter { !visible.contains($0) }
        let urls = indices.compactMap { session.page($0)?.url }
        let byURL = Dictionary(indices.compactMap { i in session.page(i).map { ($0.url, i) } },
                               uniquingKeysWith: { a, _ in a })
        // Drop preloads that fell out of the ±2 spread window.
        let wanted = Set(urls)
        pipeline.cancelPrefetch(Array(preloading.subtracting(wanted)))
        preloading = wanted
        for (url, task) in cropTasks where !wanted.contains(url) { task.cancel(); cropTasks[url] = nil }
        let chapterID = session.chapter.id
        let reader = session
        let onSize: @Sendable (URL, PageSize) -> Void = { url, size in
            Task { @MainActor in
                guard reader.chapter.id == chapterID, let index = byURL[url] else { return }
                reader.reportSize(size, forPage: index)
            }
        }
        // Split wide pages decode at twice the width (see
        // `PageImages.forHalves`), so preload them at that size.
        let split = Set(session.navigator.layout.spreads.compactMap { $0.half == nil ? nil : $0.first })
        let halfURLs = Set(indices.filter { split.contains($0) }.compactMap { session.page($0)?.url })
        let wholeURLs = urls.filter { !halfURLs.contains($0) }
        let whole = PageImages(pipeline: pipeline, server: reader.server, targetSize: target)
        let halves = whole.forHalves()
        pipeline.prefetch(wholeURLs, server: reader.server, targetSize: whole.targetSize, onPixelSize: onSize)
        if !halfURLs.isEmpty {
            pipeline.prefetch(Array(halfURLs), server: reader.server, targetSize: halves.targetSize,
                              onPixelSize: onSize)
        }
        guard settings.cropBorders else { return }
        for url in urls where cropTasks[url] == nil {
            guard let index = byURL[url], reader.crop(ofPage: index) == nil else { continue }
            if let hit = PageCropCache.shared.cached(url) {
                reader.reportCrop(hit, forPage: index)
                continue
            }
            let images = halfURLs.contains(url) ? halves : whole
            cropTasks[url] = Task {
                defer { cropTasks[url] = nil }
                guard let page = try? await images.load(url), !Task.isCancelled else { return }
                let crop = await PageCropCache.shared.crop(for: url, image: page.cgImage)
                guard reader.chapter.id == chapterID else { return }
                reader.reportCrop(crop, forPage: index)
            }
        }
    }

    private struct PreloadKey: Hashable {
        var chapterID: String
        var spread: Spread?
        var count: Int
        var loaded: Bool
        var target: CGSize
        var crop: Bool
    }
}

/// Where page images come from: the shared pipeline, at screen size.
struct PageImages {
    let pipeline: any ImageLoading
    let server: MangaServer
    let targetSize: CGSize

    func cached(_ url: URL) -> LoadedImage? {
        pipeline.cachedImage(for: url, targetSize: targetSize, scaling: .fit)
    }

    func load(_ url: URL) async throws -> LoadedImage {
        try await pipeline.load(url, server: server, targetSize: targetSize, scaling: .fit)
    }

    /// For wide pages split in two: each half fills the screen, so the
    /// whole image is decoded at twice the screen's width.
    func forHalves() -> PageImages {
        PageImages(pipeline: pipeline, server: server,
                   targetSize: CGSize(width: targetSize.width * 2, height: targetSize.height))
    }
}

/// A spread's pages in screen order with their crops and frames.
private struct SpreadLayoutInfo {
    var pages: [Int]
    var crops: [CropInsets]
    /// Which half shows, for a split wide page.
    var half: PageHalf?
    var canvas: SpreadCanvas
}

/// One spread, laid out with `SpreadGeometry` so both pages share a height
/// and touch with no seam, then zoomed and panned as one picture.
private struct SpreadView: View {
    let session: ReaderSession
    let layout: SpreadLayoutInfo
    let images: PageImages
    let viewport: PagedViewport
    let container: CGSize
    let scale: CGFloat

    var body: some View {
        let canvas = layout.canvas
        let screen = Extent(width: Double(container.width), height: Double(container.height))
        let offset = viewport.offset(canvas: canvas.size, screen: screen, scale: Double(scale))
        let halves = layout.half != nil
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(layout.pages.count, canvas.frames.count), id: \.self) { i in
                let frame = canvas.frames[i]
                let crop = layout.crops[i]
                PageImageView(session: session, index: layout.pages[i], images: halves ? images.forHalves() : images,
                              crop: crop, half: layout.half,
                              size: CGSize(width: frame.width, height: frame.height),
                              scale: scale)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.x, y: frame.y)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .scaleEffect(viewport.zoom, anchor: .topLeading)
        .offset(x: -offset.x, y: -offset.y)
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .pictureAdjustments(session.settings.picture)
    }
}

/// A single page image. Drawn to exactly the frame it's given (no aspect
/// fit), because the frame already has the page's (cropped) aspect ratio;
/// this keeps the two halves of a spread flush. A cropped page is drawn
/// larger than its frame and clipped, so only the margins are cut.
private struct PageImageView: View {
    let session: ReaderSession
    let index: Int
    let images: PageImages
    /// Margins trimmed from what this view shows (for a split page, from
    /// its half, as fractions of the half).
    let crop: CropInsets
    /// Which half shows, for a split wide page.
    var half: PageHalf? = nil
    /// The size this view is laid out at.
    let size: CGSize
    let scale: CGFloat

    @State private var loaded: LoadedImage?
    @State private var processed: CGImage?

    private var failure: String? { loaded == nil ? session.pageFailures[index] : nil }

    /// Label, value ("loaded" or "cropped", "failed", "loading", with
    /// ", adjusted" when picture controls change the page) and hint for
    /// VoiceOver and UI tests.
    private var accessibilityText: (label: String, value: String, hint: String) {
        let name = half.map { "Page \(index + 1), \($0.rawValue) half" } ?? "Page \(index + 1)"
        let adjusted = session.settings.picture.isDefault ? "" : ", adjusted"
        if loaded != nil { return (name, (crop.isZero ? "loaded" : "cropped") + adjusted, "") }
        if failure != nil { return ("Page \(index + 1) didn't load", "failed", "Press Select to retry") }
        return (name, "loading", "")
    }

    var body: some View {
        // The image is an overlay, so its larger (uncropped, or whole
        // page for a split half) size never changes the page's layout or
        // accessibility frame.
        Rectangle()
            .fill(.clear)
            .frame(width: size.width, height: size.height)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText.label)
            .accessibilityValue(accessibilityText.value)
            .accessibilityHint(accessibilityText.hint)
            .accessibilityIdentifier(half.map { "reader.page.\(index).\($0.rawValue)" } ?? "reader.page.\(index)")
            .overlay(alignment: .topLeading) { content.accessibilityHidden(true) }
            .clipped()
            .task(id: LoadKey(url: session.page(index)?.url, target: images.targetSize,
                              crop: session.settings.cropBorders,
                              retry: session.pageRetryTokens[index] ?? 0)) { await load() }
            .task(id: ProcessKey(loaded: loaded != nil, picture: session.settings.picture, pixels: framePixels)) {
                await process()
            }
    }

    /// The size of what this view shows before cropping (the half, for a
    /// split page).
    private var uncropped: CGSize {
        CGSize(width: size.width / crop.visibleWidth, height: size.height / crop.visibleHeight)
    }

    /// The whole page image as drawn: twice the half's width for a split page.
    private var imageSize: CGSize {
        CGSize(width: uncropped.width * (half == nil ? 1 : 2), height: uncropped.height)
    }

    /// The device pixels the drawn image covers, for Lanczos upscaling.
    private var framePixels: CGSize {
        CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    }

    @ViewBuilder
    private var content: some View {
        if loaded != nil {
            let x = -crop.left * uncropped.width - (half == .right ? uncropped.width : 0)
            pageImage
                .frame(width: imageSize.width, height: imageSize.height)
                .offset(x: x, y: -crop.top * uncropped.height)
        } else if let failure {
            PageFailureCard(page: index + 1, message: failure)
                .frame(width: size.width, height: size.height)
        } else {
            ProgressView()
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var pageImage: some View {
        if let processed {
            Image(decorative: processed, scale: 1)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
        } else if let loaded {
            Image(uiImage: loaded.image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
        }
    }

    private struct LoadKey: Hashable {
        var url: URL?
        var target: CGSize
        var crop: Bool
        var retry: Int
    }

    private struct ProcessKey: Hashable {
        var loaded: Bool
        var picture: PictureSettings
        var pixels: CGSize
    }

    /// Sharpening and Lanczos upscaling (picture controls). Shows the
    /// plain image until the processed one is ready.
    private func process() async {
        guard let loaded, let url = session.page(index)?.url,
              let request = PictureProcessor.request(for: url, image: loaded.cgImage,
                                                     picture: session.settings.picture,
                                                     framePixels: framePixels) else {
            processed = nil
            return
        }
        if let hit = PictureProcessor.shared.cached(request) {
            processed = hit
            return
        }
        let result = await PictureProcessor.shared.process(loaded.cgImage, request)
        guard !Task.isCancelled else { return }
        processed = result
    }

    private func load() async {
        guard let url = session.page(index)?.url else { return }
        if let hit = images.cached(url) {
            session.reportSize(hit.pixelSize, forPage: index)
            await detectCrop(url, hit)
            loaded = hit
            session.reportPageLoaded(index)
            return
        }
        guard loaded == nil else { return }
        do {
            let page = try await images.load(url)
            session.reportSize(page.pixelSize, forPage: index)
            // Find the margins before showing the page, so it appears
            // already cropped instead of jumping.
            await detectCrop(url, page)
            loaded = page
            session.reportPageLoaded(index)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            session.reportPageFailure(PageLoadFailure.message(for: error), forPage: index)
        }
    }

    private func detectCrop(_ url: URL, _ page: LoadedImage) async {
        guard session.settings.cropBorders, session.crop(ofPage: index) == nil else { return }
        let crop = await PageCropCache.shared.crop(for: url, image: page.cgImage)
        session.reportCrop(crop, forPage: index)
    }
}

/// Shown in place of a page that didn't load after automatic retries. The
/// reader keeps focus (left/right still turn pages), so the Retry pill is
/// drawn as the focused control and Select presses it.
struct PageFailureCard: View {
    let page: Int
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Page \(page) didn't load")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text("Retry")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 36)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
            Text("Press Select to retry")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .minimumScaleFactor(0.6)
        .padding(32)
        .background(Color(white: 0.12).opacity(0.92), in: RoundedRectangle(cornerRadius: Radius.card))
        .padding(16)
        .frame(maxWidth: 640)
    }
}

/// Small "12–13 / 40" indicator at the bottom of the screen.
private struct PageIndicator: View {
    let session: ReaderSession
    let viewport: PagedViewport

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                if viewport.isZoomed {
                    Label(ReaderMenuOptions.zoomLabel(viewport.zoom), systemImage: "plus.magnifyingglass")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Zoomed \(ReaderMenuOptions.zoomLabel(viewport.zoom))")
                        .accessibilityIdentifier("reader.zoom")
                }
                Text(text)
                    .accessibilityIdentifier("reader.pageIndicator")
                    .accessibilityLabel(text)
                    // Read by UI tests: zoom and pan position.
                    .accessibilityValue(String(format: "zoom %.2f x %.2f y %.2f", viewport.zoom, viewport.x, viewport.y))
            }
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 24)
        }
    }

    private var text: String {
        let total = session.pageCount
        if let edge = session.edge {
            return edge == .end ? "End of chapter" : "Start of chapter"
        }
        let pages = session.visiblePages.map { $0 + 1 }
        guard let first = pages.first else { return "" }
        if let half = session.currentSpread?.half {
            return "\(first) / \(total) · \(half == .left ? "Left" : "Right") half"
        }
        if let last = pages.last, last != first { return "\(first)–\(last) / \(total)" }
        return "\(first) / \(total)"
    }
}

/// Shown between chapters. Names where the next press goes, Mihon style.
struct ChapterTransitionCard: View {
    let session: ReaderSession
    let edge: ChapterEdge

    var body: some View {
        let other = session.chapter(across: edge)
        let forwardKey = session.settings.direction == .rightToLeft ? "left" : "right"
        let backKey = session.settings.direction == .rightToLeft ? "right" : "left"
        VStack(spacing: 28) {
            Text(edge == .end ? "Finished" : "Current")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(session.chapter.title)
                .font(.title2)
                .lineLimit(2)
            Divider().frame(width: 400)
            if let other {
                Text(edge == .end ? "Next" : "Previous")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(other.title)
                    .font(.title2)
                    .lineLimit(2)
                    .accessibilityIdentifier("reader.transition.target")
                Text("Press \(edge == .end ? forwardKey : backKey) again to continue")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(edge == .end ? "No more chapters" : "This is the first chapter")
                    .font(.title3)
                    .accessibilityIdentifier("reader.transition.none")
                Text("Press Menu to close the reader")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(80)
        .frame(maxWidth: 1240)
        .foregroundStyle(.white)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: Radius.panel))
        .padding(.horizontal, 120)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.transition")
    }
}
