import Foundation
import Observation
import UIKit
import MangaCore

/// State for reading one text book (EPUB or plain text): which chapter and
/// section is open, the laid-out pages, the settings, and progress saving.
/// The image readers use `ReaderSession`; this is its counterpart for
/// reflowable text.
///
/// - Sections load from the server one at a time (`BookProviding`) and are
///   laid out for the current screen and settings. The next and previous
///   sections are fetched ahead, so turning across a section is instant.
/// - `turn(forward:)` moves one screen. Past the last page of a chapter it
///   shows an end card; another press opens the next text chapter.
/// - Changing a setting or the screen size lays everything out again and
///   keeps the same place in the text.
/// - Progress: the section index goes to the server (Kavita's page number)
///   through `AppModel.recordProgress`; the position inside the section is
///   kept locally in `AppModel.bookPositions`.
@MainActor
@Observable
final class BookReaderSession {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let series: SeriesSummary
    let chapters: [Chapter]
    @ObservationIgnored let server: BookProviding

    private(set) var chapter: Chapter
    private(set) var manifest: BookManifest?
    private(set) var loadState: LoadState = .loading
    private(set) var settings: BookSettings
    private(set) var cursor = BookCursor()
    /// Laid-out sections by index.
    private(set) var layouts: [Int: BookSectionLayout] = [:]
    /// Non-nil while the start or end card is showing.
    private(set) var edge: ChapterEdge?
    var isMenuPresented = false

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let pipeline: any ImageLoading
    @ObservationIgnored private var viewport: CGSize = .zero
    @ObservationIgnored private var sections: [Int: BookSection] = [:]
    @ObservationIgnored private var images: [URL: UIImage] = [:]
    @ObservationIgnored private var fetches: [Int: Task<BookSection?, Never>] = [:]
    @ObservationIgnored private var turning = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastSaved: Saved?
    /// Where to land once the first layout exists (the screen size may not
    /// be known yet when the chapter loads).
    @ObservationIgnored private var pendingStart: (fraction: Double, toEnd: Bool)?
    @ObservationIgnored var saveDelay: Duration = .seconds(2)

    private struct Saved: Equatable {
        var chapterID: String
        var section: Int
        var page: Int
        var completed: Bool
    }

    init(model: AppModel, server: BookProviding, series: SeriesSummary, chapters: [Chapter], start: Chapter,
         pipeline: any ImageLoading = ImagePipeline.shared) {
        self.model = model
        self.server = server
        self.series = series
        self.chapters = chapters.isEmpty ? [start] : chapters
        self.chapter = start
        self.pipeline = pipeline
        self.settings = model.bookSettings
    }

    // MARK: Derived state

    var sectionCount: Int { manifest?.sectionCount ?? 0 }
    var pageCounts: [Int: Int] { layouts.mapValues(\.pageCount) }
    var currentLayout: BookSectionLayout? { layouts[cursor.section] }
    var pageCount: Int { currentLayout?.pageCount ?? 0 }

    /// The table of contents entry the reader is in, if any.
    var currentTOCEntry: BookTOCEntry? {
        BookTOCEntry.flatten(manifest?.toc ?? []).map(\.entry).last { $0.section <= cursor.section }
    }

    /// Rough share of the chapter read, by section, for the position line.
    var percent: Int {
        guard sectionCount > 0 else { return 0 }
        let within = pageCount > 0 ? Double(cursor.page + 1) / Double(pageCount) : 0
        return Int(((Double(cursor.section) + within) / Double(sectionCount) * 100).rounded())
    }

    var isAtEnd: Bool { cursor.isAtEnd(pageCounts: pageCounts, sectionCount: sectionCount) }

    private var chapterIndex: Int? { chapters.firstIndex { $0.id == chapter.id } }

    /// The next or previous chapter that is also text. Image chapters in
    /// the same series open from series detail instead.
    func chapter(across edge: ChapterEdge) -> Chapter? {
        guard let i = chapterIndex else { return nil }
        let candidates = edge == .end ? Array(chapters[(i + 1)...]) : Array(chapters[..<i].reversed())
        guard let next = candidates.first else { return nil }
        return next.format?.isText == true ? next : nil
    }

    // MARK: Loading

    func start() async {
        guard !started else { return }
        started = true
        await load(chapter: chapter, at: nil)
    }

    func retry() async {
        await load(chapter: chapter, at: nil)
    }

    /// Opens a chapter. `at` nil resumes saved progress; `.end` opens on
    /// the last page (going backwards from the next chapter).
    enum Start: Equatable { case beginning, end }

    func load(chapter: Chapter, at start: Start?) async {
        flushProgress()
        for task in fetches.values { task.cancel() }
        fetches = [:]
        sections = [:]
        layouts = [:]
        images = [:]
        edge = nil
        lastSaved = nil
        pendingStart = nil
        self.chapter = chapter
        loadState = .loading
        do {
            let manifest = try await server.bookManifest(for: chapter)
            guard self.chapter.id == chapter.id else { return }
            self.manifest = manifest
            guard manifest.sectionCount > 0 else {
                loadState = .failed("This book has no readable text.")
                return
            }
            let profile = model.activeProfile.id
            var section = 0
            var fraction = 0.0
            switch start {
            case .beginning:
                break
            case .end:
                section = manifest.sectionCount - 1
                fraction = 1
            case nil:
                let resume = BookPositionStore.resume(chapter: chapter,
                                                      saved: AppModel.bookPositions.position(profile: profile, chapter: chapter),
                                                      sectionCount: manifest.sectionCount)
                section = resume.section
                fraction = resume.fraction
            }
            guard await ensureLayout(section) else {
                if self.chapter.id == chapter.id, loadState == .loading {
                    loadState = .failed("Couldn't load this part of the book.")
                }
                return
            }
            guard self.chapter.id == chapter.id else { return }
            loadState = .loaded
            if let count = layouts[section]?.pageCount {
                cursor = BookCursor(section: section,
                                    page: start == .end ? max(0, count - 1) : BookCursor.page(forFraction: fraction, pageCount: count))
                // A blank first section (cover page with no text): move on.
                if count == 0 { await turn(forward: start != .end) }
            } else {
                cursor = BookCursor(section: section, page: 0)
                pendingStart = (fraction, start == .end)
            }
            prefetchNeighbors()
        } catch is CancellationError {
        } catch {
            guard self.chapter.id == chapter.id else { return }
            loadState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Fetches (once) and lays out a section. Returns false if it failed.
    @discardableResult
    private func ensureLayout(_ index: Int) async -> Bool {
        if layouts[index] != nil { return true }
        guard index >= 0, index < sectionCount else { return false }
        let task: Task<BookSection?, Never>
        if let running = fetches[index] {
            task = running
        } else {
            let chapter = self.chapter
            let server = self.server
            let pipeline = self.pipeline
            task = Task { [weak self] in
                guard let section = try? await server.bookSection(index, of: chapter) else { return nil }
                let loaded = await Self.loadImages(section.imageURLs, server: server, pipeline: pipeline)
                self?.store(images: loaded)
                return section
            }
            fetches[index] = task
        }
        let chapterID = chapter.id
        guard let section = await task.value, chapter.id == chapterID else { return false }
        sections[index] = section
        guard viewport.width > 0 else { return true } // Laid out once the size is known.
        if layouts[index] == nil {
            layouts[index] = BookLayoutEngine.layout(section, settings: settings, viewport: viewport, images: images)
        }
        return true
    }

    private func store(images loaded: [URL: UIImage]) {
        images.merge(loaded) { a, _ in a }
    }

    private static func loadImages(_ urls: [URL], server: MangaServer, pipeline: any ImageLoading) async -> [URL: UIImage] {
        guard !urls.isEmpty else { return [:] }
        return await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in Set(urls) {
                group.addTask {
                    let image = try? await pipeline.load(url, server: server, targetSize: CGSize(width: 1600, height: 1600),
                                                         scaling: .fit).image
                    return (url, image)
                }
            }
            var result: [URL: UIImage] = [:]
            for await (url, image) in group { if let image { result[url] = image } }
            return result
        }
    }

    /// Lays out the sections on either side ahead of time.
    private func prefetchNeighbors() {
        let current = cursor.section
        Task { [weak self] in
            guard let self else { return }
            for index in [current + 1, current - 1] where index >= 0 && index < self.sectionCount {
                await self.ensureLayout(index)
            }
            self.trimCache()
        }
    }

    /// Keeps laid-out sections near the reader only; long books have
    /// hundreds of sections.
    private func trimCache() {
        let keep = (cursor.section - 2)...(cursor.section + 2)
        for index in layouts.keys where !keep.contains(index) { layouts[index] = nil }
        for index in sections.keys where !keep.contains(index) { sections[index] = nil }
        for index in fetches.keys where !keep.contains(index) { fetches[index] = nil }
    }

    // MARK: Layout

    /// The reader's size in points. Lays out again when it changes.
    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewport else { return }
        viewport = size
        relayout()
        if loadState == .loaded, layouts[cursor.section] == nil {
            Task { await ensureLayout(cursor.section) }
        }
    }

    func updateSettings(_ newSettings: BookSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        model.setBookSettings(newSettings)
        relayout()
    }

    /// Lays out every cached section again, keeping the reader on the same
    /// text.
    private func relayout() {
        guard viewport.width > 0 else { return }
        let fraction = cursor.fraction(pageCount: pageCount)
        var fresh: [Int: BookSectionLayout] = [:]
        for (index, section) in sections {
            fresh[index] = BookLayoutEngine.layout(section, settings: settings, viewport: viewport, images: images)
        }
        layouts = fresh
        guard let count = fresh[cursor.section]?.pageCount else { return }
        if let start = pendingStart {
            pendingStart = nil
            cursor.page = start.toEnd ? max(0, count - 1) : BookCursor.page(forFraction: start.fraction, pageCount: count)
        } else {
            cursor.page = BookCursor.page(forFraction: fraction, pageCount: count)
        }
    }

    // MARK: Navigation

    /// One screen forward or back. At a chapter's edge the first press
    /// shows a card, the next opens the neighboring text chapter.
    func turn(forward: Bool) async {
        guard loadState == .loaded, !turning else { return }
        turning = true
        defer { turning = false }

        if let edge {
            switch (edge, forward) {
            case (.end, true), (.start, false):
                if let next = chapter(across: edge) {
                    await load(chapter: next, at: edge == .end ? .beginning : .end)
                }
            default:
                self.edge = nil
            }
            return
        }

        for _ in 0..<3 {
            var moved = cursor
            let move = forward ? moved.forward(pageCounts: pageCounts, sectionCount: sectionCount)
                               : moved.backward(pageCounts: pageCounts)
            switch move {
            case .moved:
                cursor = moved
                scheduleSave()
                prefetchNeighbors()
                return
            case .needsSection(let index, _):
                // Usually already prefetched; otherwise wait for it, then
                // try the same move again.
                guard await ensureLayout(index) else { return }
            case .atEnd:
                edge = .end
                scheduleSave()
                return
            case .atStart:
                if chapter(across: .start) != nil { edge = .start }
                return
            }
        }
    }

    /// Opens a table-of-contents entry.
    func jump(to entry: BookTOCEntry) async {
        guard await ensureLayout(entry.section), let layout = layouts[entry.section] else { return }
        pendingStart = nil
        var page = 0
        if let anchor = entry.anchor, let block = sections[entry.section]?.blockIndex(forAnchor: anchor) {
            page = layout.page(forBlock: block)
        }
        edge = nil
        cursor = BookCursor(section: entry.section, page: min(page, max(0, layout.pageCount - 1)))
        scheduleSave()
        prefetchNeighbors()
    }

    // MARK: Progress

    private var pending: Saved? {
        guard loadState == .loaded, sectionCount > 0 else { return nil }
        let completed = edge == .end || isAtEnd
        return Saved(chapterID: chapter.id, section: cursor.section, page: cursor.page, completed: completed)
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

    /// Saves now if anything changed since the last save.
    func flushProgress() {
        saveTask?.cancel()
        saveTask = nil
        guard let progress = pending, progress != lastSaved else { return }
        if let last = lastSaved, last.chapterID == progress.chapterID, last.completed, !progress.completed { return }
        let sectionChanged = lastSaved?.section != progress.section || lastSaved?.completed != progress.completed
        lastSaved = progress
        AppModel.bookPositions.setPosition(BookPosition(section: progress.section,
                                                        fraction: cursor.fraction(pageCount: pageCount)),
                                           profile: model.activeProfile.id, chapter: chapter)
        // The server only knows sections, so only write when that changes.
        guard sectionChanged else { return }
        let chapter = self.chapter
        let series = self.series
        let model = self.model
        Task {
            await model.recordProgress(chapter: chapter, series: series,
                                       page: progress.section, completed: progress.completed)
        }
    }

    func close() {
        flushProgress()
        for task in fetches.values { task.cancel() }
    }
}
