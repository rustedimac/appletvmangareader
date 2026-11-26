import Foundation
import Observation
import QuartzCore
import MangaCore

/// The panel over the page while the reader menu is open.
enum ReaderOverlay: Equatable {
    /// Settings, chapters and bookmarks (`ReaderMenu`).
    case menu
    /// Page thumbnails (`PageScrubberView`).
    case scrubber
}

/// What the webtoon strip does for game controller input.
@MainActor
protocol WebtoonInputTarget: AnyObject {
    func jumpPage(forward: Bool)
    func toggleAutoScroll()
    func stickMoved(y: Double)
}

/// State shared by every reader mode for one reading session: the series,
/// its chapters, the open chapter's pages and their sizes, where the reader
/// is, and the reader settings. The paged reader, the webtoon reader and
/// the in-reader menu all read and drive this object.
///
/// Contract for the readers:
/// - Call `start()` once (ReaderView does this).
/// - Paged: call `turn(_:)` for remote presses. Webtoon: call
///   `reportVisiblePage(_:)` as the strip scrolls.
/// - Call `reportSize(_:forPage:)` when an image arrives and its pixel size
///   is known. Spreads re-lay out and the current page stays on screen.
/// - Menu: call `updateSettings(_:)`; it applies live and saves per series.
/// - Progress is written to this profile's saved state on every page
///   change (`AppModel.recordLocalProgress`), so nothing is lost if the app
///   is killed. The server push (`AppModel.recordProgress`) is debounced and
///   also happens on chapter change, `close()` and when the app leaves the
///   foreground (`flushProgress()`).
/// - A chapter opened without a page resumes exactly where it was left
///   (`ResumePosition`); the previous chapter, reached from the start of
///   the next one, opens on its last page.
@MainActor
@Observable
final class ReaderSession {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let series: SeriesSummary
    let chapters: [Chapter]
    /// The client that serves this series. Use it for image requests.
    @ObservationIgnored let server: MangaServer

    private(set) var chapter: Chapter
    private(set) var pages: [PageDescriptor] = []
    /// Known pixel sizes by page index. Kavita gives them up front; Suwayomi
    /// fills them in as images download.
    private(set) var sizes: [Int: PageSize] = [:]
    /// Detected page margins by page index (paged reader, Crop Borders).
    private(set) var crops: [Int: CropInsets] = [:]
    private(set) var settings: ReaderSettings
    private(set) var navigator: ReaderNavigator
    private(set) var loadState: LoadState = .loading
    /// The in-reader menu (workstream G) is showing, or the page scrubber
    /// (`overlay` says which). Either one takes focus from the page.
    var isMenuPresented = false {
        didSet {
            if isMenuPresented {
                if isAutoScrolling { isAutoScrolling = false }
                stopAutoTurn()
                hideHUD()
                if overlay == .menu { note(.openOptions) }
            } else {
                overlay = .menu
                scrubberFromMenu = false
                note(.closeOptions)
            }
        }
    }
    /// What shows while `isMenuPresented` is true. Resets to the menu when
    /// it closes, so every way of opening the menu opens the menu.
    private(set) var overlay: ReaderOverlay = .menu
    /// Webtoon auto-scroll is running. The strip sets this; it stops when
    /// the menu opens or a chapter loads. Setting it false stops the strip.
    var isAutoScrolling = false {
        didSet {
            guard isAutoScrolling != oldValue else { return }
            note(isAutoScrolling ? .startPlay : .stopPlay)
        }
    }
    /// Paged reader: the page-turn timer is running (Play/Pause).
    private(set) var isAutoTurning = false
    /// The page number and reading info are showing (a tap on the touch
    /// surface). They hide on their own after `hudDuration`.
    private(set) var isHUDVisible = false
    /// Whether the scrubber was opened from the menu's Pages button (Back
    /// returns to the menu) or straight from the page (Back closes it).
    @ObservationIgnored private var scrubberFromMenu = false
    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var autoTurnTask: Task<Void, Never>?
    /// When a game controller's ☰ last toggled the options. Some
    /// controllers also send ☰ as a Back press; that echo is ignored.
    @ObservationIgnored private var lastGamepadMenu: CFTimeInterval = 0
    @ObservationIgnored private var lastPlayToggle: CFTimeInterval = 0
    @ObservationIgnored var hudDuration: Duration = .seconds(3)
    /// Set while this session is the controls tutorial on the sample
    /// (`ReaderTutorial`). A tutorial saves nothing: no progress, recent
    /// series, bookmarks or reader settings.
    private(set) var tutorial: ReaderTutorial.Progress?
    var isTutorial: Bool { tutorial != nil }
    /// Tutorial only: pages bookmarked in this run, kept in memory.
    private(set) var tutorialBookmarks: Set<Int> = []
    /// The profile's auto-scroll speed (`WebtoonAutoScroll.levels`).
    private(set) var autoScrollLevel: Int
    /// Paged reader: pages of this chapter whose image didn't load after
    /// the automatic retries, with a short reason. Turning pages still works.
    private(set) var pageFailures: [Int: String] = [:]
    /// Bumped per page by `retryVisibleFailedPages`; page views reload on a change.
    private(set) var pageRetryTokens: [Int: Int] = [:]
    /// A short message shown over the page, such as "Bookmarked".
    var notice: ReaderNotice?
    /// Asks the webtoon strip to scroll to a page (opening a bookmark).
    var pageJump: PageJump?

    @ObservationIgnored let model: AppModel
    @ObservationIgnored private let initialPage: Int?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: SavedProgress?
    /// Last position written to local state.
    @ObservationIgnored private var lastLocal: SavedProgress?
    /// Where each chapter was left during this session, by chapter id.
    @ObservationIgnored private var visitedPages: [String: Int] = [:]
    @ObservationIgnored private var started = false
    /// How long page turns settle before progress is written.
    @ObservationIgnored var saveDelay: Duration = .seconds(2)

    private struct SavedProgress: Equatable {
        var chapterID: String
        var page: Int
        var completed: Bool
    }

    /// - Parameter startPage: page to open at. Nil resumes from the
    ///   chapter's saved progress.
    init(model: AppModel, server: MangaServer, series: SeriesSummary, chapters: [Chapter],
         start: Chapter, startPage: Int? = nil, tutorial: ReadingMode? = nil) {
        self.model = model
        self.server = server
        self.series = series
        self.chapters = chapters.isEmpty ? [start] : chapters
        self.chapter = start
        self.initialPage = startPage
        self.tutorial = tutorial.map { ReaderTutorial.Progress(mode: $0) }
        let settings = tutorial.map(TutorialSample.settings(for:)) ?? model.readerSettings(for: series)
        self.settings = settings
        self.navigator = ReaderNavigator(pageCount: 0, settings: settings)
        self.autoScrollLevel = WebtoonAutoScroll.nearestStep(model.autoScrollLevel)
    }

    // MARK: Derived state

    /// The page anchoring what is on screen (first page of the spread).
    var currentPage: Int { navigator.currentPage }
    var currentSpread: Spread? { navigator.currentSpread }
    var visiblePages: [Int] { navigator.visiblePages }

    // MARK: Page failures

    func reportPageFailure(_ message: String, forPage page: Int) {
        pageFailures[page] = message
    }

    func reportPageLoaded(_ page: Int) {
        if pageFailures[page] != nil { pageFailures[page] = nil }
    }

    /// Failed pages on screen right now.
    var visibleFailedPages: [Int] {
        guard edge == nil else { return [] }
        return visiblePages.filter { pageFailures[$0] != nil }
    }

    /// Reloads the failed pages on screen (Select on a failed page).
    /// Returns false if none had failed, so Select can do its usual job.
    @discardableResult
    func retryVisibleFailedPages() -> Bool {
        let failed = visibleFailedPages
        guard !failed.isEmpty else { return false }
        for page in failed {
            pageFailures[page] = nil
            pageRetryTokens[page, default: 0] += 1
        }
        return true
    }
    /// Non-nil while a chapter transition card is showing.
    var edge: ChapterEdge? { navigator.edge }
    var pageCount: Int { pages.count }

    var chapterIndex: Int? { chapters.firstIndex { $0.id == chapter.id } }

    var nextChapterInList: Chapter? {
        guard let i = chapterIndex, i + 1 < chapters.count else { return nil }
        return chapters[i + 1]
    }

    var previousChapterInList: Chapter? {
        guard let i = chapterIndex, i > 0 else { return nil }
        return chapters[i - 1]
    }

    /// The chapter on the other side of an edge, if there is one.
    func chapter(across edge: ChapterEdge) -> Chapter? {
        edge == .end ? nextChapterInList : previousChapterInList
    }

    func size(ofPage index: Int) -> PageSize? { sizes[index] }

    func page(_ index: Int) -> PageDescriptor? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    // MARK: Loading

    func start() async {
        guard !started else { return }
        started = true
        if !isTutorial { model.noteReading(series) }
        await load(chapter: chapter, startPage: initialPage)
    }

    /// Opens a chapter. `startPage` nil resumes saved progress (or page 0 if
    /// the chapter is read). Pass `Int.max` to open on the last page.
    func load(chapter: Chapter, startPage: Int? = nil) async {
        flushProgress()
        loadTask?.cancel()
        self.chapter = chapter
        isAutoScrolling = false
        stopAutoTurn()
        loadState = .loading
        pages = []
        sizes = [:]
        crops = [:]
        pageFailures = [:]
        navigator = ReaderNavigator(pageCount: 0, settings: settings)
        lastSaved = nil
        lastLocal = nil
        let task = Task { [server] in
            do {
                // A slow or briefly unreachable server gets a few tries
                // before the chapter shows its error card (which has Retry).
                let policy = ReaderDemo.isEnabled ? ReaderDemo.retryPolicy : RetryPolicy.pageLists
                let loaded = try await policy.run { _ in try await server.pages(for: chapter) }
                try Task.checkCancellation()
                self.apply(pages: loaded, chapter: chapter, startPage: startPage)
            } catch is CancellationError {
            } catch {
                guard self.chapter.id == chapter.id else { return }
                self.loadState = .failed(error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
    }

    func retry() async {
        await load(chapter: chapter, startPage: initialPage)
    }

    private func apply(pages loaded: [PageDescriptor], chapter: Chapter, startPage: Int?) {
        guard self.chapter.id == chapter.id else { return }
        let ordered = loaded.sorted { $0.index < $1.index }
        pages = ordered
        var known: [Int: PageSize] = [:]
        for (i, page) in ordered.enumerated() { if let size = page.size { known[i] = size } }
        sizes = known
        let resume = startPage ?? model.resumePage(for: chapter, sessionPage: visitedPages[chapter.id])
        let sizeList: [PageSize?] = (0..<ordered.count).map { known[$0] }
        navigator = ReaderNavigator(sizes: sizeList, settings: settings, startPage: resume)
        loadState = .loaded
    }

    /// Webtoon reader: makes `chapter` current using pages the strip has
    /// already loaded, without a loading state, when the reader scrolls
    /// across a chapter boundary. Saves progress for the chapter it leaves.
    func adopt(chapter: Chapter, pages loaded: [PageDescriptor], sizes known: [Int: PageSize], page: Int) {
        guard chapter.id != self.chapter.id else { return }
        flushProgress()
        loadTask?.cancel()
        self.chapter = chapter
        let ordered = loaded.sorted { $0.index < $1.index }
        pages = ordered
        sizes = known
        crops = [:]
        pageFailures = [:]
        let sizeList: [PageSize?] = (0..<ordered.count).map { known[$0] }
        navigator = ReaderNavigator(sizes: sizeList, settings: settings, startPage: page)
        lastSaved = nil
        lastLocal = nil
        loadState = .loaded
        progressChanged()
    }

    /// Moves to the next chapter in reading order. Returns false at the end.
    @discardableResult
    func nextChapter() async -> Bool {
        guard let next = nextChapterInList else { return false }
        await load(chapter: next, startPage: 0)
        return true
    }

    /// Moves to the previous chapter, opening on its last page.
    @discardableResult
    func previousChapter() async -> Bool {
        guard let previous = previousChapterInList else { return false }
        await load(chapter: previous, startPage: Int.max)
        return true
    }

    /// Opens the next or previous chapter at its first page (a game
    /// controller's triggers). Does nothing past either end of the list.
    func jumpChapter(forward: Bool) {
        guard let target = forward ? nextChapterInList : previousChapterInList else { return }
        Task { await load(chapter: target, startPage: 0) }
    }

    // MARK: Navigation

    /// A remote press in the paged reader. Handles chapter transitions:
    /// the first press past an edge shows the transition card, the second
    /// opens the next (or previous) chapter.
    @discardableResult
    func turn(_ direction: ScreenDirection) -> PageTurnResult {
        guard loadState == .loaded else { return .none }
        let result = navigator.turn(direction)
        handle(result)
        return result
    }

    func forward() { guard loadState == .loaded else { return }; handle(navigator.forward()) }
    func backward() { guard loadState == .loaded else { return }; handle(navigator.backward()) }

    private func handle(_ result: PageTurnResult) {
        switch result {
        case .moved, .showTransition:
            note(.turnPage)
            progressChanged()
        case .leaveChapter(let edge):
            guard chapter(across: edge) != nil else { return }
            Task {
                if edge == .end { await nextChapter() } else { await previousChapter() }
            }
        case .none:
            break
        }
    }

    /// Webtoon reader: the page now at the top of the screen.
    func reportVisiblePage(_ page: Int) {
        guard loadState == .loaded, page != navigator.currentPage || navigator.edge != nil else { return }
        navigator.go(toPage: page)
        progressChanged()
    }

    /// Jumps the paged reader to a page.
    func go(toPage page: Int) {
        navigator.go(toPage: page)
        progressChanged()
    }

    /// Opens the page scrubber: in place of the menu (its Pages button), or
    /// straight from the page (paged reader, Down at the bottom).
    func openScrubber(fromMenu: Bool = true) {
        guard loadState == .loaded, pageCount > 0 else { return }
        scrubberFromMenu = fromMenu && isMenuPresented
        overlay = .scrubber
        isMenuPresented = true
    }

    /// Opens a page of this chapter from the scrubber, in either reader,
    /// and closes the scrubber.
    func jump(toPage page: Int) {
        guard loadState == .loaded, pageCount > 0 else { return }
        let page = min(max(0, page), pageCount - 1)
        isMenuPresented = false
        go(toPage: page)
        if settings.mode == .webtoon {
            pageJump = PageJump(chapterID: chapter.id, page: page)
        }
    }

    /// Records a page's pixel size once its image is known.
    func reportSize(_ size: PageSize, forPage page: Int) {
        guard pages.indices.contains(page), sizes[page] != size else { return }
        sizes[page] = size
        navigator.setSize(size, forPage: page)
    }

    func crop(ofPage index: Int) -> CropInsets? { crops[index] }

    /// Records a page's detected margins. Only changes layout while Crop
    /// Borders is on.
    func reportCrop(_ crop: CropInsets, forPage page: Int) {
        guard pages.indices.contains(page), crops[page] != crop else { return }
        crops[page] = crop
    }

    // MARK: Settings

    /// Applies settings live and saves them for this series.
    func updateSettings(_ newSettings: ReaderSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        navigator.updateSettings(newSettings)
        guard !isTutorial else { return }
        model.setReaderSettings(newSettings, for: series.ref)
    }

    /// Sets the auto-scroll / page-turn speed and saves it for the profile.
    /// Only named steps are used (`WebtoonAutoScroll.steps`).
    func setAutoScrollLevel(_ level: Int) {
        let level = WebtoonAutoScroll.nearestStep(level)
        guard level != autoScrollLevel else { return }
        autoScrollLevel = level
        model.setAutoScrollLevel(level)
        note(.changeSpeed)
    }

    // MARK: Remote: Play/Pause, HUD, Back

    /// Play/Pause pressed (`ReaderRemoteCatcher`): closes the options if
    /// they're open, otherwise plays.
    func playPausePressed() {
        if isMenuPresented {
            isMenuPresented = false
        } else {
            togglePlay()
        }
    }

    /// Play/Pause held: the one route to the reader options.
    func playPauseHeld() {
        guard !(isMenuPresented && overlay == .scrubber && scrubberFromMenu) else {
            overlay = .menu
            scrubberFromMenu = false
            return
        }
        isMenuPresented.toggle()
    }

    /// The reader's "play": auto-scroll in the vertical reader, the
    /// page-turn timer in the page reader.
    func togglePlay() {
        guard loadState == .loaded else { return }
        // One controller press can arrive both as X and as a Play/Pause
        // press; the second toggle is dropped.
        let now = CACurrentMediaTime()
        guard now - lastPlayToggle > 0.3 else { return }
        lastPlayToggle = now
        if settings.mode == .webtoon {
            webtoonInput?.toggleAutoScroll()
        } else if isAutoTurning {
            stopAutoTurn()
        } else {
            startAutoTurn()
        }
    }

    /// Paged reader: turns forward every `WebtoonAutoScroll.secondsPerPage`
    /// at the profile's speed, and stops at the end of the chapter (the
    /// transition card), when the options open, or on Play/Pause.
    func startAutoTurn() {
        guard settings.mode == .paged, loadState == .loaded, edge == nil, !isAutoTurning else { return }
        isAutoTurning = true
        note(.startPlay)
        autoTurnTask = Task { [weak self] in
            while let self, self.isAutoTurning {
                let seconds = WebtoonAutoScroll.secondsPerPage(self.autoScrollLevel)
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, self.isAutoTurning else { return }
                self.forward()
                if self.edge != nil { self.stopAutoTurn() }
            }
        }
    }

    func stopAutoTurn() {
        autoTurnTask?.cancel()
        autoTurnTask = nil
        if isAutoTurning {
            isAutoTurning = false
            note(.stopPlay)
        }
    }

    /// A tap on the touch surface: shows the page number (or hides it).
    func toggleHUD() {
        if isHUDVisible { hideHUD() } else { showHUD() }
    }

    /// Shows the page number and reading info for `hudDuration`.
    func showHUD() {
        guard !isMenuPresented else { return }
        isHUDVisible = true
        note(.showPageNumber)
        hudTask?.cancel()
        let duration = hudDuration
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isHUDVisible = false
        }
    }

    func hideHUD() {
        hudTask?.cancel()
        hudTask = nil
        if isHUDVisible { isHUDVisible = false }
    }

    /// Menu (Back): closes the top layer. Returns false when nothing was
    /// open, so the caller closes the reader. Order (docs/READER_CONTROLS.md
    /// section 5): scrubber (back to the options if it came from them),
    /// options, page number, then auto-scroll or the page-turn timer. The
    /// paged reader zooms out before asking here.
    @discardableResult
    func back() -> Bool {
        if CACurrentMediaTime() - lastGamepadMenu < 0.35 { return true }
        if isMenuPresented {
            if overlay == .scrubber, scrubberFromMenu {
                overlay = .menu
                scrubberFromMenu = false
            } else {
                isMenuPresented = false
            }
            return true
        }
        if isHUDVisible {
            hideHUD()
            return true
        }
        if isAutoScrolling {
            isAutoScrolling = false
            return true
        }
        if isAutoTurning {
            stopAutoTurn()
            return true
        }
        return false
    }

    // MARK: Tutorial

    /// Something the person did, for the tutorial's current step.
    func note(_ goal: ReaderTutorial.Goal) {
        guard tutorial != nil else { return }
        tutorial?.record(goal)
    }

    /// Paged reader: the page was zoomed in or out (the view owns zoom).
    func noteZoom(_ zoomed: Bool) {
        note(zoomed ? .zoomIn : .zoomOut)
    }

    /// Tutorial only: bookmarks the page on screen in memory.
    func toggleTutorialBookmark() {
        let page = min(currentPage, max(0, pageCount - 1))
        if tutorialBookmarks.contains(page) {
            tutorialBookmarks.remove(page)
            show(ReaderNotice(text: "Bookmark removed", systemImage: "bookmark.slash"))
        } else {
            tutorialBookmarks.insert(page)
            show(ReaderNotice(text: "Bookmarked page \(page + 1)", systemImage: "bookmark.fill"))
        }
        note(.bookmark)
    }

    // MARK: Game controller

    /// The webtoon strip, while it's on screen, for controller input that
    /// only it can carry out.
    @ObservationIgnored weak var webtoonInput: WebtoonInputTarget?

    /// A game controller button (see `GamepadMapping`).
    func handleController(_ button: GamepadButton) {
        guard let action = GamepadMapping.action(for: button, mode: settings.mode,
                                                 menuOpen: isMenuPresented) else { return }
        switch action {
        case .toggleMenu:
            lastGamepadMenu = CACurrentMediaTime()
            isMenuPresented.toggle()
        case .jumpChapter(let forward):
            jumpChapter(forward: forward)
        case .turnPage(let direction):
            if settings.mode == .webtoon {
                webtoonInput?.jumpPage(forward: direction == .right)
            } else {
                turn(direction)
            }
        case .togglePlay:
            togglePlay()
        case .toggleBookmark:
            toggleBookmark()
        case .toggleHUD:
            toggleHUD()
        }
    }

    /// A game controller stick moved (GameController axes, -1...1).
    func handleControllerStick(x: Double, y: Double) {
        let active = settings.mode == .webtoon && !isMenuPresented
        webtoonInput?.stickMoved(y: active ? y : 0)
    }

    // MARK: Progress

    private var pendingProgress: SavedProgress? {
        guard loadState == .loaded, pageCount > 0 else { return nil }
        return SavedProgress(chapterID: chapter.id,
                             page: min(navigator.progressPage, pageCount - 1),
                             completed: navigator.isChapterComplete)
    }

    /// Saves the position locally right away and schedules the server push.
    private func progressChanged() {
        writeLocalProgress()
        scheduleSave()
    }

    /// Writes the position to this profile's saved state if it moved. Cheap
    /// enough for every page turn; survives the app being killed.
    private func writeLocalProgress() {
        guard !isTutorial, let progress = pendingProgress else { return }
        visitedPages[progress.chapterID] = progress.page
        guard progress != lastLocal else { return }
        lastLocal = progress
        model.recordLocalProgress(chapter: chapter, series: series, page: progress.page, completed: progress.completed)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushProgress()
        }
    }

    /// Writes progress now if it changed since the last save.
    func flushProgress() {
        saveTask?.cancel()
        saveTask = nil
        writeLocalProgress()
        guard !isTutorial, let progress = pendingProgress, progress != lastSaved else { return }
        // Never move a finished chapter back to unread.
        if let last = lastSaved, last.chapterID == progress.chapterID, last.completed, !progress.completed { return }
        lastSaved = progress
        let chapter = self.chapter
        let series = self.series
        let model = self.model
        model.startRecordingProgress(chapter: chapter, series: series,
                                     page: progress.page, completed: progress.completed)
    }

    @ObservationIgnored private var refreshedOnClose = false

    /// Call when the reader closes. Posters of the series pick up the new
    /// progress once the save lands.
    func close() {
        flushProgress()
        loadTask?.cancel()
        stopAutoTurn()
        hudTask?.cancel()
        // The view closes it on Menu and again on disappear.
        if !refreshedOnClose, !isTutorial {
            refreshedOnClose = true
            model.refreshSeriesProgress(series.ref)
        }
    }
}
