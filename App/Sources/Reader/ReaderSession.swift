import Foundation
import Observation
import MangaCore

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
/// - Progress is saved through `AppModel.recordProgress`, debounced, on
///   chapter change, and on `close()`.
/// What the webtoon strip does for game controller input.
@MainActor
protocol WebtoonInputTarget: AnyObject {
    func jumpPage(forward: Bool)
    func toggleAutoScroll()
    func stickMoved(y: Double)
}

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
    private(set) var settings: ReaderSettings
    private(set) var navigator: ReaderNavigator
    private(set) var loadState: LoadState = .loading
    /// The in-reader menu (workstream G) is showing.
    var isMenuPresented = false {
        didSet { if isMenuPresented, isAutoScrolling { isAutoScrolling = false } }
    }
    /// Webtoon auto-scroll is running. The strip sets this; it stops when
    /// the menu opens or a chapter loads.
    var isAutoScrolling = false
    /// The profile's auto-scroll speed (`WebtoonAutoScroll.levels`).
    private(set) var autoScrollLevel: Int
    /// A short message shown over the page, such as "Bookmarked".
    var notice: ReaderNotice?
    /// Asks the webtoon strip to scroll to a page (opening a bookmark).
    var pageJump: PageJump?

    @ObservationIgnored let model: AppModel
    @ObservationIgnored private let initialPage: Int?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: SavedProgress?
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
         start: Chapter, startPage: Int? = nil) {
        self.model = model
        self.server = server
        self.series = series
        self.chapters = chapters.isEmpty ? [start] : chapters
        self.chapter = start
        self.initialPage = startPage
        let settings = model.readerSettings(for: series.ref)
        self.settings = settings
        self.navigator = ReaderNavigator(pageCount: 0, settings: settings)
        self.autoScrollLevel = model.autoScrollLevel
    }

    // MARK: Derived state

    /// The page anchoring what is on screen (first page of the spread).
    var currentPage: Int { navigator.currentPage }
    var currentSpread: Spread? { navigator.currentSpread }
    var visiblePages: [Int] { navigator.visiblePages }
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
        await load(chapter: chapter, startPage: initialPage)
    }

    /// Opens a chapter. `startPage` nil resumes saved progress (or page 0 if
    /// the chapter is read). Pass `Int.max` to open on the last page.
    func load(chapter: Chapter, startPage: Int? = nil) async {
        flushProgress()
        loadTask?.cancel()
        self.chapter = chapter
        isAutoScrolling = false
        loadState = .loading
        pages = []
        sizes = [:]
        navigator = ReaderNavigator(pageCount: 0, settings: settings)
        lastSaved = nil
        let task = Task { [server] in
            do {
                let loaded = try await server.pages(for: chapter)
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
        let resume = startPage ?? (chapter.isRead ? 0 : chapter.lastPageRead)
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
        let sizeList: [PageSize?] = (0..<ordered.count).map { known[$0] }
        navigator = ReaderNavigator(sizes: sizeList, settings: settings, startPage: page)
        lastSaved = nil
        loadState = .loaded
        scheduleSave()
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
            scheduleSave()
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
        scheduleSave()
    }

    /// Jumps the paged reader to a page.
    func go(toPage page: Int) {
        navigator.go(toPage: page)
        scheduleSave()
    }

    /// Records a page's pixel size once its image is known.
    func reportSize(_ size: PageSize, forPage page: Int) {
        guard pages.indices.contains(page), sizes[page] != size else { return }
        sizes[page] = size
        navigator.setSize(size, forPage: page)
    }

    // MARK: Settings

    /// Applies settings live and saves them for this series.
    func updateSettings(_ newSettings: ReaderSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        navigator.updateSettings(newSettings)
        model.setReaderSettings(newSettings, for: series.ref)
    }

    /// Sets the auto-scroll speed and saves it for the profile.
    func setAutoScrollLevel(_ level: Int) {
        let level = WebtoonAutoScroll.clamped(level)
        guard level != autoScrollLevel else { return }
        autoScrollLevel = level
        model.setAutoScrollLevel(level)
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
            isMenuPresented.toggle()
        case .jumpChapter(let forward):
            jumpChapter(forward: forward)
        case .turnPage(let direction):
            if settings.mode == .webtoon {
                webtoonInput?.jumpPage(forward: direction == .right)
            } else {
                turn(direction)
            }
        case .toggleAutoScroll:
            webtoonInput?.toggleAutoScroll()
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
        guard let progress = pendingProgress, progress != lastSaved else { return }
        // Never move a finished chapter back to unread.
        if let last = lastSaved, last.chapterID == progress.chapterID, last.completed, !progress.completed { return }
        lastSaved = progress
        let chapter = self.chapter
        let libraryID = series.libraryID
        let model = self.model
        Task { await model.recordProgress(chapter: chapter, libraryID: libraryID,
                                          page: progress.page, completed: progress.completed) }
    }

    /// Call when the reader closes.
    func close() {
        flushProgress()
        loadTask?.cancel()
    }
}
