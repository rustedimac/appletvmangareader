import SwiftUI
import MangaCore

/// Full-screen reader. Present it from series detail:
///
///     .fullScreenCover(item: $reading) { r in
///         ReaderView(series: r.series, chapters: r.chapters, start: r.chapter)
///     }
///
/// It switches on `settings.mode` between the paged and webtoon readers and
/// overlays the in-reader menu.
///
/// Controls (docs/READER_CONTROLS.md section 10, `ReaderControls`):
/// Play/Pause plays (auto-scroll or the page-turn timer) and holding it
/// opens the reader options; a tap on the touch surface shows the page
/// number (`ReaderRemoteCatcher` catches both, whatever has focus). Menu
/// closes one layer at a time (`ReaderSession.back()`) and only then saves
/// progress and closes the reader.
///
/// Game controllers (`GameControllerHub`, mapping in `GamepadMapping`):
/// ☰ toggles the options, Y bookmarks, X plays, L1/R1 jump chapters, View
/// shows the page number, either stick scrolls the webtoon. B and the
/// d-pad act like the remote's Menu and arrows.
struct ReaderView: View {
    let series: SeriesSummary
    let chapters: [Chapter]
    let start: Chapter
    /// Page to open at. Nil resumes the chapter's saved progress.
    var startPage: Int? = nil
    /// Overrides the server client (UI tests and previews).
    var server: MangaServer? = nil
    /// Runs the controls tutorial in this mode (`ReaderTutorialView`).
    var tutorial: ReadingMode? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: ReaderSession?
    /// The first-open "Learn the controls?" question is showing.
    @State private var offeringTutorial = false
    /// The tutorial is open over this reader.
    @State private var tutorialMode: ReadingMode?
    #if os(iOS)
    /// The touch chrome (top bar with Close) is showing.
    @State private var chromeVisible = true
    #endif

    var body: some View {
        if start.format?.isText == true {
            // EPUB and plain text reflow, so they get the book reader.
            BookReaderView(series: series, chapters: chapters, start: start, server: server)
        } else {
            imageReader
        }
    }

    private var imageReader: some View {
        ZStack {
            (session?.settings.background.color ?? .black).ignoresSafeArea()
            if let session {
                ReaderContent(session: session)
                    #if os(iOS)
                    .readerTapRegions { region in handleTap(region, session: session) }
                    .ignoresSafeArea()
                    #endif
            } else {
                ProgressView()
            }
            #if os(iOS)
            if let session, chromeVisible || session.isMenuPresented {
                ReaderTouchChrome(title: session.series.title, subtitle: session.chapter.title,
                                  isBookmarked: session.isTutorial ? nil : session.isShowingBookmarkedPage,
                                  onBookmark: { session.toggleBookmark() },
                                  onClose: closeReader,
                                  optionsPresented: Binding(get: { session.isMenuPresented && session.overlay == .menu },
                                                            set: { session.isMenuPresented = $0 }),
                                  options: { ReaderMenu(session: session).environment(model) },
                                  bottom: { ReaderPageBar(session: session) })
            }
            #endif
        }
        #if os(iOS)
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .readerSystemOverlays(visible: chromeVisible)
        .readerKeyboardShortcuts(session: session, onClose: closeReader)
        // Reading shouldn't dim and lock the screen.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #else
        .ignoresSafeArea()
        #endif
        .background {
            #if os(tvOS)
            if let session {
                // While the tutorial or its question is over this reader,
                // the remote belongs to them.
                ReaderRemoteCatcher(onPlayPause: { if remoteIsOurs { session.playPausePressed() } },
                                    onPlayPauseHold: { if remoteIsOurs { session.playPauseHeld() } },
                                    onTap: { if remoteIsOurs { session.toggleHUD() } },
                                    // Menu with the options or scrubber open
                                    // closes them, never the reader, even
                                    // when focus has dropped out of them.
                                    takesMenu: { remoteIsOurs && session.menuTakesBack },
                                    onMenu: { _ = session.back() })
            }
            #endif
        }
        .onRemoteExit {
            if let session, session.back() { return }
            session?.close()
            dismiss()
        }
        .task {
            guard session == nil else { return }
            guard let client = server ?? model.client(for: series.ref) else { return }
            let s = ReaderSession(model: model, server: client, series: series, chapters: chapters,
                                  start: start, startPage: startPage, tutorial: tutorial)
            session = s
            if tutorial == nil, TutorialRecord.shouldOffer {
                TutorialRecord.markOffered()
                offeringTutorial = true
            }
            GameControllerHub.shared.push(owner: s, onButton: { [weak s] button in
                s?.handleController(button)
            }, onStick: { [weak s] x, y in
                s?.handleControllerStick(x: x, y: y)
            })
            await s.start()
        }
        .onDisappear {
            guard let session else { return }
            session.close()
            GameControllerHub.shared.remove(owner: session)
        }
        // Home button, screen saver or app switcher: save before tvOS may
        // suspend or end the app.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session?.flushProgress() }
        }
        .alert("Learn the Controls?", isPresented: $offeringTutorial) {
            Button("Show Me") { tutorialMode = session?.settings.mode ?? .paged }
                .accessibilityIdentifier("reader.tutorialOffer.start")
            Button("Not Now", role: .cancel) {}
                .accessibilityIdentifier("reader.tutorialOffer.skip")
        } message: {
            Text("Try each button on a short sample comic, in about a minute. You can replay it any time in Settings > Remote and Controller.")
        }
        .fullScreenCover(item: $tutorialMode) { mode in
            ReaderTutorialView(mode: mode)
        }
    }

    private var remoteIsOurs: Bool { !offeringTutorial && tutorialMode == nil }

    #if os(iOS)
    private func closeReader() {
        session?.close()
        dismiss()
    }

    /// Centre: chrome. Sides: page turn (paged) or one screen of scroll
    /// (vertical; finger scrolling works natively there).
    /// Centre: chrome. Sides: by the Tap Zones setting (MangaCore
    /// `ReaderTouch.tap`): turn (paged), scroll a step (vertical).
    private func handleTap(_ region: TapRegion, session: ReaderSession) {
        guard !session.isMenuPresented else { return }
        // A tap on a page that failed to load retries it first.
        if session.retryVisibleFailedPages() { return }
        let action = ReaderTouch.tap(region, zones: session.settings.tapZones, mode: session.settings.mode,
                                     direction: session.settings.direction, zoomed: session.isZoomed)
        switch action {
        case .toggleChrome:
            chromeVisible.toggle()
        case .turn(let direction):
            chromeVisible = false
            session.turn(direction)
        case .scroll(let forward):
            chromeVisible = false
            session.scrollStep(forward: forward)
        case .none:
            break
        }
    }
    #endif
}

private struct ReaderContent: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            Group {
                switch session.settings.mode {
                case .paged:
                    PagedReaderView(session: session)
                case .webtoon:
                    WebtoonReaderView(session: session)
                }
            }
            // Keep focus inside the menu while it's open; the reader takes
            // focus back when it closes.
            .disabled(session.isMenuPresented)
            ReaderLoadStateView(session: session)
            ReaderBookmarkOverlay(session: session)
            ReaderHUD(session: session)
            ReaderPageTimerBadge(session: session)
            if session.isTutorial {
                ReaderTutorialOverlay(session: session)
            } else {
                ReaderControlsHint(session: session)
            }
            if session.isMenuPresented {
                switch session.overlay {
                case .menu:
                    #if os(tvOS)
                    ReaderMenu(session: session)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    #else
                    // iPhone/iPad: the options open from the chrome's button
                    // as a popover (a sheet on iPhone), see ReaderTouchChrome.
                    EmptyView()
                    #endif
                case .scrubber:
                    PageScrubberView(session: session)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isMenuPresented)
        .animation(.easeInOut(duration: 0.2), value: session.overlay)
        .animation(.easeInOut(duration: 0.2), value: session.notice)
        .animation(.easeInOut(duration: 0.2), value: session.isHUDVisible)
        .animation(.easeInOut(duration: 0.2), value: session.isAutoTurning)
    }
}

/// "Page timer · Slow" at the bottom while the page reader turns pages on
/// its own (Play/Pause), so it's clear why pages move.
struct ReaderPageTimerBadge: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            if session.isAutoTurning, !session.isMenuPresented {
                let text = "Page timer · \(WebtoonAutoScroll.label(session.autoScrollLevel))"
                Label(text, systemImage: "play.fill")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("reader.paged.pageTimer")
                    .accessibilityLabel(text)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// When the page number shows. It hides by default and a tap on the touch
/// surface shows it for a few seconds (John, 2026-11-26). UI tests read the
/// page number constantly, so under `-uiTesting` it stays on unless a test
/// passes `-readerHUDOnTap`.
enum ReaderHUDPolicy {
    static let alwaysShowPageNumber: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiTesting") && !args.contains("-readerHUDOnTap")
    }()

    @MainActor
    static func showsPageNumber(_ session: ReaderSession) -> Bool {
        alwaysShowPageNumber || session.isHUDVisible
    }
}

/// What a tap shows besides the page number: the series and chapter at the
/// top, and in the corner a Play/Pause icon with "Hold for options", so the
/// route to the options is always one glance away.
struct ReaderHUD: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            if session.isHUDVisible, !session.isMenuPresented {
                Text("\(session.series.title) · \(session.chapter.title)")
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                    .padding(.horizontal, 200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .accessibilityIdentifier("reader.hud.title")
                HStack(spacing: 12) {
                    Image(systemName: "playpause.fill")
                    Text(ReaderControls.hudHint)
                }
                .font(.callout)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 24)
                .padding(.trailing, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hold Play/Pause for options")
                .accessibilityIdentifier("reader.hud.hint")
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A ribbon in the corner while a bookmarked page is on screen, and the
/// "Bookmarked" notice after toggling one.
struct ReaderBookmarkOverlay: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            if session.isShowingBookmarkedPage, !session.isMenuPresented {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .shadow(radius: 4)
                    .padding(.top, 30)
                    .padding(.trailing, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityIdentifier("reader.bookmarked")
                    .accessibilityLabel("Bookmarked page")
            }
            if let notice = session.notice {
                Label(notice.text, systemImage: notice.systemImage)
                    .font(.callout)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice.text)
                    .accessibilityIdentifier("reader.notice")
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// "Hold Play/Pause for reader options · …" at the top of the screen the first few
/// times a reader mode opens (`ReaderHintTracker`), so the route to the
/// options is never a secret. It fades after a few seconds and stops
/// showing once the options have been opened in that mode.
struct ReaderControlsHint: View {
    let session: ReaderSession
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible, !session.isMenuPresented, session.notice == nil {
                Label(ReaderControls.hint(for: session.settings.mode), systemImage: "appletvremote.gen4")
                    .font(.callout)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ReaderControls.hint(for: session.settings.mode))
                    .accessibilityIdentifier("reader.hint")
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: visible)
        .task(id: session.settings.mode) {
            let mode = session.settings.mode
            guard let tracker = ReaderHintTracker.app, tracker.takeHint(for: mode) else {
                visible = false
                return
            }
            visible = true
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { visible = false }
        }
        .onChange(of: session.isMenuPresented) { _, presented in
            guard presented else { return }
            visible = false
            ReaderHintTracker.app?.menuOpened(in: session.settings.mode)
        }
    }
}

extension ReaderHintTracker {
    /// The app's tracker. UI tests get no hint (it would sit over what they
    /// check) unless they pass `-readerHints`, which starts from a clean
    /// count each launch.
    @MainActor static let app: ReaderHintTracker? = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting") else { return ReaderHintTracker() }
        guard args.contains("-readerHints"),
              let defaults = UserDefaults(suiteName: "uiTesting.readerHints") else { return nil }
        let tracker = ReaderHintTracker(defaults: defaults)
        tracker.reset()
        return tracker
    }()
}

/// Spinner while a chapter loads, and an error with Retry if it fails.
struct ReaderLoadStateView: View {
    let session: ReaderSession

    var body: some View {
        switch session.loadState {
        case .loading:
            ProgressView()
                .accessibilityIdentifier("reader.loading")
        case .failed(let message):
            VStack(spacing: 24) {
                Text("Couldn't load \(session.chapter.title)").font(.title3)
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { Task { await session.retry() } }
            }
            .padding(60)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("reader.error")
        case .loaded:
            EmptyView()
        }
    }
}

extension ReaderBackground {
    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(white: 0.2)
        case .white: return .white
        }
    }
}
