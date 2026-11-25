import UIKit
import MangaCore

/// Runs the webtoon strip: lays out chapters as one continuous column with
/// `WebtoonLayout` (whole device pixels, so pages join with no seam), keeps
/// only the views near the screen alive, loads the next and previous
/// chapters into the strip as the reader nears either end, and reports the
/// reading position to the session.
///
/// Positions are kept as a `WebtoonAnchor` across every re-layout, so when
/// a page's real height arrives or a chapter is added or dropped above, what
/// is on screen stays exactly where it was.
@MainActor
final class WebtoonStripController: NSObject, UIScrollViewDelegate {
    let container = WebtoonContainerView()
    private var scrollView: WebtoonScrollView { container.scrollView }
    private let session: ReaderSession
    private let loader: WebtoonImageLoader
    private let driver = WebtoonScrollDriver()

    private(set) var strip = WebtoonStrip()
    private(set) var layout = WebtoonLayout(segments: [], columnPixels: 0, breakHeight: 0)
    /// The chapter the session is on, as far as the strip knows.
    private var currentChapterID: String?
    private var settings: ReaderSettings
    private var scale: CGFloat = 1
    private var viewport: CGSize = .zero
    private var columnX = 0
    /// Page to put at the top once the strip has a size.
    private var pendingScroll: (segment: String, page: Int)?
    private var relayoutScheduled = false

    private var pageViews: [WebtoonItemKind: WebtoonPageView] = [:]
    private var pagePool: [WebtoonPageView] = []
    private var breakViews: [String: WebtoonBreakView] = [:]
    private var endView: WebtoonEndView?

    private var fetchingChapters: Set<String> = []
    private var failedFetch: [String: Date] = [:]
    private var userHasScrolled = false

    /// Opens the reader menu.
    var onMenu: (() -> Void)?

    /// Divider and footer heights, in points.
    private let breakHeightPoints: CGFloat = 220
    private let endHeightPoints: CGFloat = 260

    init(session: ReaderSession) {
        self.session = session
        self.loader = WebtoonImageLoader(server: session.server)
        self.settings = session.settings
        super.init()
        let sv = scrollView
        sv.delegate = self
        sv.contentInsetAdjustmentBehavior = .never
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceVertical = true
        sv.clipsToBounds = true
        sv.backgroundColor = .clear
        sv.decelerationRate = .normal
        sv.accessibilityIdentifier = "reader.webtoon.strip"
        sv.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        sv.onPress = { [weak self] type, began in self?.handlePress(type, began: began) ?? false }
        driver.scrollView = sv
        driver.maxOffset = { [weak self] in self?.maxOffsetPoints ?? 0 }
        driver.onMove = { [weak self] in self?.userHasScrolled = true }
        container.onLayout = { [weak self] in self?.containerDidLayout() }
    }

    /// Stops the scroll driver and pending loads. Call when the view goes away.
    func teardown() {
        driver.stop()
        loader.cancelAll()
        for view in pageViews.values { view.recycle() }
    }

    // MARK: Session sync

    /// Called whenever the session's state may have changed.
    func sync() {
        let newSettings = session.settings
        if newSettings != settings {
            let widthChanged = newSettings.clampedWebtoonWidth != settings.clampedWebtoonWidth
            settings = newSettings
            if widthChanged { relayout(preserve: true) }
        }
        switch session.loadState {
        case .loading, .failed:
            // The session is opening another chapter (e.g. a jump from the
            // menu). Clear the strip; it is rebuilt once the pages load.
            if session.chapter.id != currentChapterID, !strip.isEmpty { clear() }
        case .loaded:
            if strip.isEmpty || session.chapter.id != currentChapterID || !strip.contains(session.chapter.id) {
                rebuildFromSession()
            }
        }
    }

    private func rebuildFromSession() {
        guard session.pageCount > 0 else { return }
        clear()
        let segment = WebtoonStrip.Segment(chapter: session.chapter, pages: session.pages, sizes: session.sizes)
        strip.reset(segment)
        currentChapterID = segment.id
        pendingScroll = (segment.id, min(session.currentPage, max(0, segment.pages.count - 1)))
        relayout(preserve: false)
    }

    private func clear() {
        driver.stop()
        loader.cancelAll()
        for view in pageViews.values { view.recycle(); view.removeFromSuperview(); pagePool.append(view) }
        pageViews.removeAll()
        breakViews.values.forEach { $0.removeFromSuperview() }
        breakViews.removeAll()
        endView?.removeFromSuperview()
        endView = nil
        strip = WebtoonStrip()
        currentChapterID = nil
        layout = WebtoonLayout(segments: [], columnPixels: 0, breakHeight: 0)
        scrollView.contentSize = .zero
        scrollView.contentOffset = .zero
    }

    // MARK: Layout

    private func containerDidLayout() {
        let size = container.bounds.size
        let newScale = max(1, container.window?.screen.scale ?? container.traitCollection.displayScale)
        guard size != viewport || newScale != scale else { return }
        viewport = size
        scale = newScale
        relayout(preserve: true)
    }

    private var viewportPixels: (width: Int, height: Int) {
        (Int((viewport.width * scale).rounded()), Int((viewport.height * scale).rounded()))
    }

    private var offsetPixels: Int { Int((scrollView.contentOffset.y * scale).rounded()) }

    private var maxOffsetPoints: CGFloat {
        CGFloat(layout.maxOffset(viewport: viewportPixels.height)) / scale
    }

    private func points(_ px: Int) -> CGFloat { CGFloat(px) / scale }

    /// Coalesces bursts of size updates into one re-layout.
    private func scheduleRelayout() {
        guard !relayoutScheduled else { return }
        relayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.relayoutScheduled = false
            self.relayout(preserve: true)
        }
    }

    private func relayout(preserve: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let vp = viewportPixels
        let oldOffset = scrollView.contentOffset.y
        let anchor = preserve ? WebtoonAnchor.capture(layout, offsetY: offsetPixels) : nil
        let column = WebtoonGeometry.columnPixels(screenPixels: vp.width, fraction: settings.clampedWebtoonWidth)
        columnX = WebtoonGeometry.columnX(screenPixels: vp.width, columnPixels: column)
        let hasNext = strip.last.flatMap { WebtoonStrip.neighbor(of: $0.id, in: session.chapters, offset: 1) } != nil
        layout = WebtoonLayout(segments: strip.layoutSegments, columnPixels: column,
                               breakHeight: Int((breakHeightPoints * scale).rounded()),
                               endHeight: hasNext ? 0 : Int((endHeightPoints * scale).rounded()))
        scrollView.contentSize = CGSize(width: viewport.width, height: points(layout.totalHeight))

        var target: Int?
        if let pending = pendingScroll, let item = layout.item(segment: pending.segment, page: pending.page) {
            target = item.y
            pendingScroll = nil
        } else if let anchor, let y = anchor.resolve(in: layout) {
            target = y
        }
        if let target {
            let clamped = min(max(0, target), layout.maxOffset(viewport: vp.height))
            let y = points(clamped)
            if abs(y - scrollView.contentOffset.y) > 0.01 {
                scrollView.contentOffset = CGPoint(x: 0, y: y)
            }
        }
        driver.shift(by: scrollView.contentOffset.y - oldOffset)
        updateVisible()
    }

    // MARK: Visible views

    private func updateVisible() {
        guard !layout.items.isEmpty, viewport.height > 0 else { return }
        let vp = viewportPixels
        let top = offsetPixels
        let range = layout.itemIndices(from: top - vp.height, to: top + 2 * vp.height)
        var wantedPages = Set<WebtoonItemKind>()
        var wantedBreaks = Set<String>()
        var wantsEnd = false

        for i in range {
            let item = layout.items[i]
            let frame = CGRect(x: points(columnX), y: points(item.y),
                               width: points(layout.columnPixels), height: points(item.height))
            switch item.kind {
            case .page(let segmentID, let page):
                wantedPages.insert(item.kind)
                let view = pageViews[item.kind] ?? dequeuePageView()
                pageViews[item.kind] = view
                let url = strip.segment(segmentID)?.pages[safe: page]?.url
                view.prepare(kind: item.kind, url: url, label: "Page \(page + 1)",
                             identifier: "reader.webtoon.page.\(segmentID).\(page)")
                if view.frame != frame { view.frame = frame }
                loadImage(into: view, segment: segmentID, page: page)
            case .chapterBreak(let before):
                wantedBreaks.insert(before)
                let view = breakViews[before] ?? {
                    let v = WebtoonBreakView()
                    scrollView.addSubview(v)
                    breakViews[before] = v
                    return v
                }()
                let index = strip.index(of: before) ?? 0
                let previous = index > 0 ? strip.segments[index - 1].chapter.title : nil
                view.configure(finished: previous, next: strip.segment(before)?.chapter.title ?? "")
                view.frame = CGRect(x: 0, y: points(item.y), width: viewport.width, height: points(item.height))
            case .end:
                wantsEnd = true
                let view = endView ?? {
                    let v = WebtoonEndView()
                    scrollView.addSubview(v)
                    endView = v
                    return v
                }()
                view.frame = CGRect(x: 0, y: points(item.y), width: viewport.width, height: points(item.height))
            }
        }

        for (kind, view) in pageViews where !wantedPages.contains(kind) {
            view.recycle()
            view.isHidden = true
            pagePool.append(view)
            pageViews[kind] = nil
        }
        for (id, view) in breakViews where !wantedBreaks.contains(id) {
            view.removeFromSuperview()
            breakViews[id] = nil
        }
        if !wantsEnd, let endView {
            endView.removeFromSuperview()
            self.endView = nil
        }

        prefetchSizesAhead(top: top, viewport: vp.height)
        reportPosition(top: top, viewport: vp.height)
        loadNeighborsIfNeeded(top: top, viewport: vp.height)
    }

    private func dequeuePageView() -> WebtoonPageView {
        if let view = pagePool.popLast() {
            view.isHidden = false
            return view
        }
        let view = WebtoonPageView()
        scrollView.addSubview(view)
        return view
    }

    // MARK: Images and sizes

    private func loadImage(into view: WebtoonPageView, segment: String, page: Int) {
        guard let url = view.url else { return }
        let width = layout.columnPixels
        guard view.shownWidth != width, view.loadTask == nil else { return }
        if let hit = loader.cachedImage(url, displayWidth: width) {
            view.show(hit)
            learnSize(hit.pixelSize, segment: segment, page: page)
            return
        }
        let kind = view.kind
        view.loadTask = Task { [weak self, weak view] in
            do {
                guard let self else { return }
                let image = try await self.loader.image(url, displayWidth: width)
                guard let view, view.kind == kind, !Task.isCancelled else { return }
                view.loadTask = nil
                // A width change while decoding: decode again at the new width.
                if width == self.layout.columnPixels {
                    view.show(image)
                } else {
                    self.loadImage(into: view, segment: segment, page: page)
                }
                self.learnSize(image.pixelSize, segment: segment, page: page)
            } catch {
                guard let view, view.kind == kind else { return }
                view.loadTask = nil
            }
        }
    }

    private func learnSize(_ size: PageSize, segment: String, page: Int) {
        guard strip.setSize(size, segment: segment, page: page) else { return }
        if segment == currentChapterID {
            session.reportSize(size, forPage: page)
        }
        scheduleRelayout()
    }

    /// Learns the sizes of pages a few screens ahead so they have their real
    /// height before they come into view (Suwayomi sends no sizes).
    private func prefetchSizesAhead(top: Int, viewport: Int) {
        let range = layout.itemIndices(from: top + viewport + viewport / 2, to: top + viewport * 5)
        var urls: [URL] = []
        var locations: [URL: (segment: String, page: Int)] = [:]
        for i in range {
            guard case .page(let s, let p) = layout.items[i].kind,
                  let segment = strip.segment(s), segment.sizes[safe: p] == .some(nil),
                  let url = segment.pages[safe: p]?.url else { continue }
            urls.append(url)
            locations[url] = (s, p)
        }
        loader.prefetchSizes(urls) { [weak self] url, size in
            guard let self, let location = locations[url] else { return }
            self.learnSize(size, segment: location.segment, page: location.page)
        }
    }

    // MARK: Reading position and chapters

    private func reportPosition(top: Int, viewport: Int) {
        guard session.loadState == .loaded,
              let position = layout.readingPosition(topY: top, bottomY: top + viewport) else { return }
        if position.segment == currentChapterID {
            session.reportVisiblePage(position.page)
            return
        }
        guard let segment = strip.segment(position.segment) else { return }
        // Crossing forward finishes the chapter being left.
        if let current = currentChapterID, let from = strip.index(of: current),
           let to = strip.index(of: position.segment), to > from,
           let leaving = strip.segment(current) {
            session.reportVisiblePage(max(0, leaving.pages.count - 1))
        }
        currentChapterID = segment.id
        session.adopt(chapter: segment.chapter, pages: segment.pages, sizes: segment.knownSizes, page: position.page)
        if !strip.trim(around: segment.id, keep: 1).isEmpty { scheduleRelayout() }
    }

    private func loadNeighborsIfNeeded(top: Int, viewport: Int) {
        if WebtoonScrolling.nearEnd(offset: top, viewport: viewport, totalHeight: layout.totalHeight),
           let last = strip.last,
           let next = WebtoonStrip.neighbor(of: last.id, in: session.chapters, offset: 1) {
            fetch(next, append: true)
        }
        if userHasScrolled, WebtoonScrolling.nearStart(offset: top, viewport: viewport),
           let first = strip.first,
           let previous = WebtoonStrip.neighbor(of: first.id, in: session.chapters, offset: -1) {
            fetch(previous, append: false)
        }
    }

    private func fetch(_ chapter: Chapter, append: Bool) {
        guard !fetchingChapters.contains(chapter.id), !strip.contains(chapter.id) else { return }
        if let failed = failedFetch[chapter.id], Date().timeIntervalSince(failed) < 5 { return }
        fetchingChapters.insert(chapter.id)
        let server = session.server
        Task { [weak self] in
            do {
                let pages = try await server.pages(for: chapter)
                guard let self else { return }
                self.fetchingChapters.remove(chapter.id)
                guard !pages.isEmpty else { return }
                let segment = WebtoonStrip.Segment(chapter: chapter, pages: pages)
                // Only join if it's still adjacent to the strip.
                if append, self.strip.last.flatMap({ WebtoonStrip.neighbor(of: $0.id, in: self.session.chapters, offset: 1) })?.id == chapter.id {
                    self.strip.append(segment)
                } else if !append, self.strip.first.flatMap({ WebtoonStrip.neighbor(of: $0.id, in: self.session.chapters, offset: -1) })?.id == chapter.id {
                    self.strip.prepend(segment)
                } else {
                    return
                }
                self.relayout(preserve: true)
            } catch {
                self?.fetchingChapters.remove(chapter.id)
                self?.failedFetch[chapter.id] = Date()
            }
        }
    }

    // MARK: Remote

    private func handlePress(_ type: UIPress.PressType, began: Bool) -> Bool {
        switch type {
        case .downArrow, .upArrow:
            let forward = type == .downArrow
            if began {
                userHasScrolled = true
                let from = driver.target ?? scrollView.contentOffset.y
                let target = WebtoonScrolling.stepTarget(from: Double(from), forward: forward,
                                                         viewport: Double(viewport.height),
                                                         step: settings.webtoonScrollStep,
                                                         maxOffset: Double(maxOffsetPoints))
                driver.glide(to: CGFloat(target))
                driver.beginHold(forward: forward)
            } else {
                driver.endHold()
            }
            return true
        case .leftArrow, .rightArrow:
            if began { jumpPage(forward: type == .rightArrow) }
            return true
        case .select, .playPause:
            if began {
                driver.stop()
                onMenu?()
            }
            return true
        default:
            return false
        }
    }

    /// Puts the top of the next (or previous) page at the top of the screen.
    private func jumpPage(forward: Bool) {
        userHasScrolled = true
        let current = Int(((driver.target ?? scrollView.contentOffset.y) * scale).rounded())
        guard let i = layout.itemIndex(atY: current) else { return }
        var j = i
        if forward {
            j = min(layout.items.count - 1, i + 1)
        } else if layout.items[i].y >= current, i > 0 {
            j = i - 1
        }
        driver.glide(to: points(layout.items[j].y))
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        driver.stop()
        userHasScrolled = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisible()
    }
}

fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
