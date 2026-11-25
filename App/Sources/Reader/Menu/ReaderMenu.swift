import SwiftUI
import MangaCore

/// In-reader settings menu. A drawer on the right side of the screen, shown
/// over the page while `session.isMenuPresented` is true, so the page stays
/// visible and every change shows up behind it straight away.
///
/// Siri Remote: in the paged reader swipe down or Play/Pause opens it, in
/// the vertical reader a click does (the readers handle that).
/// Up/down moves between rows, left/right between options, click picks.
/// Menu closes it (ReaderView handles that) and so does Play/Pause.
///
/// Changes apply live through `session.updateSettings(_:)`, which saves them
/// for this series. "Set as Default" copies them to the profile default that
/// series without their own settings use.
///
/// Modeled on Mihon's reading-mode sheet (rows change with the mode) and
/// Kavita's reader settings drawer, laid out for the focus engine: one row
/// per setting, options side by side.
struct ReaderMenu: View {
    let session: ReaderSession

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .settings
    @FocusState private var focus: String?

    enum Tab: String, CaseIterable, Identifiable {
        case settings
        case chapters
        case bookmarks

        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "Settings"
            case .chapters: return "Chapters"
            case .bookmarks: return "Bookmarks"
            }
        }
    }

    private var settings: ReaderSettings { session.settings }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            panel
                .frame(width: 900)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.thickMaterial)
        }
        .ignoresSafeArea()
        .focusSection()
        .defaultFocus($focus, initialFocus)
        .onAppear { setFocus(initialFocus) }
        .onPlayPauseCommand { session.isMenuPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.menu")
    }

    private var initialFocus: String { "mode.\(settings.mode.rawValue)" }

    /// Focus changes made in the same pass a view appears are dropped on
    /// tvOS, so set it on the next turn of the run loop.
    private func setFocus(_ key: String) {
        DispatchQueue.main.async { focus = key }
    }

    // MARK: Layout

    /// Header, tabs and the open pane all live in one ScrollView, so the
    /// title and tabs scroll away with the options instead of staying pinned
    /// while the rows slide underneath them. The scroll view clips (no
    /// `.scrollClipDisabled()`); the padding inside it leaves room for
    /// focused buttons to grow.
    private var panel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                        .id(Self.topID)
                        // Up from any tab lands on Bookmark This Page, even
                        // from the right-hand tabs, which have nothing
                        // directly above them inside the scroll view.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusSection()
                    HStack(spacing: 20) {
                        ForEach(Tab.allCases) { t in
                            OptionButton(title: t.title, isSelected: tab == t) { tab = t }
                                .focused($focus, equals: "tab.\(t.rawValue)")
                                .accessibilityIdentifier("reader.menu.tab.\(t.rawValue)")
                        }
                    }
                    switch tab {
                    case .settings:
                        settingsPane
                    case .chapters:
                        ChapterListPane(session: session, focus: $focus, proxy: proxy)
                    case .bookmarks:
                        BookmarkListPane(session: session, focus: $focus)
                    }
                }
                .padding(.leading, Space.xl)
                .padding(.trailing, Layout.safeSide)
                .padding(.vertical, Layout.safeTop)
            }
            .onChange(of: focus) { _, key in
                // Focus moving up onto the tabs only scrolls them into view;
                // bring the title back too.
                guard key?.hasPrefix("tab.") == true else { return }
                withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    private static let topID = "reader.menu.top"

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.series.title)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("reader.menu.title")
            HStack(spacing: 16) {
                Text(session.chapter.title)
                let position = ReaderMenuOptions.positionLabel(visiblePages: session.visiblePages,
                                                               pageCount: session.pageCount)
                if !position.isEmpty {
                    Text("·")
                    Text(position).accessibilityIdentifier("reader.menu.position")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            HStack(spacing: Space.l) {
                bookmarkButton
                browsePagesButton
            }
            .padding(.top, 12)
        }
        // Full width and its own focus section, so pressing up from any tab
        // (even the right-most) reaches the bookmark button.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// Bookmarks the page on screen, or removes its bookmark.
    private var bookmarkButton: some View {
        let on = session.isShowingBookmarkedPage
        return Button {
            session.toggleBookmark()
        } label: {
            Label(on ? "Remove Bookmark" : "Bookmark This Page", systemImage: on ? "bookmark.fill" : "bookmark")
                .font(.callout)
        }
        .disabled(session.loadState != .loaded || session.edge != nil)
        .focused($focus, equals: "bookmark")
        .accessibilityIdentifier("reader.menu.bookmark")
        .accessibilityValue(on ? "on" : "off")
    }

    /// Closes the menu and opens the page scrubber.
    private var browsePagesButton: some View {
        Button {
            session.openScrubber()
        } label: {
            Label("Pages", systemImage: "square.grid.3x1.below.line.grid.1x2")
                .font(.callout)
        }
        .disabled(session.loadState != .loaded || session.pageCount == 0)
        .focused($focus, equals: "browsePages")
        .accessibilityIdentifier("reader.menu.browsePages")
    }

    // MARK: Settings

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(ReaderMenuOptions.items(for: settings)) { item in
                row(item)
            }
            Divider()
            picturePane
            Divider()
            defaultsSection
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func row(_ item: ReaderMenuItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            switch item {
            case .mode:
                choices(item, ReadingMode.allCases.map { ($0, $0.rawValue, $0.title) },
                        selected: settings.mode) { set(\.mode, $0) }
            case .layout:
                choices(item, PageLayout.allCases.map { ($0, $0.rawValue, $0.title) },
                        selected: settings.layout) { set(\.layout, $0) }
            case .direction:
                choices(item, ReadingDirection.allCases.map { ($0, $0.rawValue, $0.title) },
                        selected: settings.direction) { set(\.direction, $0) }
            case .firstPageAlone:
                choices(item, [(true, "on", "On"), (false, "off", "Off")],
                        selected: settings.firstPageAlone) { set(\.firstPageAlone, $0) }
            case .shiftPairing:
                shiftButton
            case .splitWidePages:
                VStack(alignment: .leading, spacing: 10) {
                    choices(item, [(true, "on", "On"), (false, "off", "Off")],
                            selected: settings.splitWidePages) { set(\.splitWidePages, $0) }
                    Text("Shows a scanned two-page spread one half at a time, in reading order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .background:
                choices(item, ReaderBackground.allCases.map { ($0, $0.rawValue, $0.title) },
                        selected: settings.background) { set(\.background, $0) }
            case .webtoonWidth:
                widthStepper
            case .autoScroll:
                autoScrollControls
            }
        }
    }

    private func choices<V: Hashable>(_ item: ReaderMenuItem, _ options: [(V, String, String)],
                                      selected: V, select: @escaping (V) -> Void) -> some View {
        HStack(spacing: 20) {
            ForEach(options, id: \.1) { option in
                let (value, key, title) = option
                OptionButton(title: title, isSelected: value == selected) { select(value) }
                    .focused($focus, equals: "\(item.rawValue).\(key)")
                    .accessibilityIdentifier("reader.menu.\(item.rawValue).\(key)")
            }
        }
    }

    /// One press flips pairing by a page, for chapters whose spreads come
    /// out with the wrong two pages together.
    private var shiftButton: some View {
        Button {
            set(\.shiftPairing, !settings.shiftPairing)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Pages paired wrong? Shift by one")
                if settings.shiftPairing {
                    Text("Shifted").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .focused($focus, equals: "shiftPairing")
        .accessibilityLabel("Pages paired wrong? Shift by one")
        .accessibilityValue(settings.shiftPairing ? "On" : "Off")
        .accessibilityIdentifier("reader.menu.shiftPairing")
    }

    private var widthStepper: some View {
        let width = settings.webtoonWidth
        return HStack(spacing: 28) {
            Button {
                set(\.webtoonWidth, ReaderMenuOptions.steppedWidth(width, by: -1))
            } label: {
                Image(systemName: "minus").frame(width: 50)
            }
            .disabled(!ReaderMenuOptions.canStepWidth(width, by: -1))
            .focused($focus, equals: "webtoonWidth.decrease")
            .accessibilityLabel("Narrower")
            .accessibilityIdentifier("reader.menu.webtoonWidth.decrease")

            Text(ReaderMenuOptions.widthLabel(width))
                .font(.callout.monospacedDigit())
                .frame(minWidth: 110)
                .accessibilityIdentifier("reader.menu.webtoonWidth.value")

            Button {
                set(\.webtoonWidth, ReaderMenuOptions.steppedWidth(width, by: 1))
            } label: {
                Image(systemName: "plus").frame(width: 50)
            }
            .disabled(!ReaderMenuOptions.canStepWidth(width, by: 1))
            .focused($focus, equals: "webtoonWidth.increase")
            .accessibilityLabel("Wider")
            .accessibilityIdentifier("reader.menu.webtoonWidth.increase")
        }
    }

    /// Auto-scroll speed (saved for the profile, not the series) and a
    /// button that closes the menu and starts it.
    private var autoScrollControls: some View {
        let level = session.autoScrollLevel
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                Button {
                    session.isMenuPresented = false
                    session.webtoonInput?.toggleAutoScroll()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .focused($focus, equals: "autoScroll.start")
                .accessibilityIdentifier("reader.menu.autoScroll.start")

                Button {
                    session.setAutoScrollLevel(WebtoonAutoScroll.stepped(level, by: -1))
                } label: {
                    Image(systemName: "tortoise").frame(width: 50)
                }
                .disabled(!WebtoonAutoScroll.canStep(level, by: -1))
                .focused($focus, equals: "autoScroll.slower")
                .accessibilityLabel("Slower")
                .accessibilityIdentifier("reader.menu.autoScroll.slower")

                Text(WebtoonAutoScroll.label(level))
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: 180)
                    .accessibilityIdentifier("reader.menu.autoScroll.value")

                Button {
                    session.setAutoScrollLevel(WebtoonAutoScroll.stepped(level, by: 1))
                } label: {
                    Image(systemName: "hare").frame(width: 50)
                }
                .disabled(!WebtoonAutoScroll.canStep(level, by: 1))
                .focused($focus, equals: "autoScroll.faster")
                .accessibilityLabel("Faster")
                .accessibilityIdentifier("reader.menu.autoScroll.faster")
            }
            .font(.callout)
            Text("Play/Pause starts and stops it. While it runs, swipe up or down to change speed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var defaultsSection: some View {
        let profileDefault = model.libraryDefaultReaderSettings(for: session.series)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Changes are saved for this series. Series you haven't changed use your default.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Button("Set as Default") { model.setMenuDefaultReaderSettings(settings) }
                    .focused($focus, equals: "makeDefault")
                    .accessibilityIdentifier("reader.menu.makeDefault")
                Button("Reset to Default") { session.updateSettings(profileDefault) }
                    .focused($focus, equals: "resetToDefault")
                    .accessibilityIdentifier("reader.menu.resetToDefault")
            }
            .font(.callout)
            if profileDefault == settings {
                Label("Same as your default", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.menu.isDefault")
            }
        }
    }

    // MARK: Picture

    private var picture: PictureSettings { settings.picture }

    /// Brightness, contrast, color, sharpening and upscaling, below the
    /// layout settings in the same pane.
    private var picturePane: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("Picture")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("reader.menu.picture")
            ForEach(ReaderMenuOptions.pictureItems(for: settings)) { item in
                pictureRow(item)
            }
            Button("Reset Picture") { set(\.picture, .default) }
                .disabled(picture.isDefault)
                .font(.callout)
                .focused($focus, equals: "picture.reset")
                .accessibilityIdentifier("reader.menu.picture.reset")
        }
    }

    @ViewBuilder
    private func pictureRow(_ item: PictureMenuItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            switch item {
            case .brightness:
                pictureStepper(item, value: picture.brightness, steps: PictureSettings.brightnessSteps,
                               label: PictureSettings.brightnessLabel(picture.brightness),
                               less: ("sun.min", "Darker"), more: ("sun.max", "Brighter")) {
                    set(\.picture.brightness, $0)
                }
            case .contrast:
                pictureStepper(item, value: picture.contrast, steps: PictureSettings.contrastSteps,
                               label: PictureSettings.contrastLabel(picture.contrast),
                               less: ("minus", "Less Contrast"), more: ("plus", "More Contrast")) {
                    set(\.picture.contrast, $0)
                }
            case .color:
                pictureChoices(item, PictureColorMode.allCases.map { ($0, $0.rawValue, $0.title) },
                               selected: picture.color) { set(\.picture.color, $0) }
            case .sharpen:
                pictureChoices(item, PictureSharpen.allCases.map { ($0, $0.rawValue, $0.title) },
                               selected: picture.sharpen) { set(\.picture.sharpen, $0) }
            case .upscaling:
                VStack(alignment: .leading, spacing: 10) {
                    pictureChoices(item, PictureUpscaling.allCases.map { ($0, $0.rawValue, $0.title) },
                                   selected: picture.upscaling) { set(\.picture.upscaling, $0) }
                    Text("Sharp (Lanczos) enlarges low-resolution scans to fill a 4K screen with crisper line art.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func pictureChoices<V: Hashable>(_ item: PictureMenuItem, _ options: [(V, String, String)],
                                             selected: V, select: @escaping (V) -> Void) -> some View {
        HStack(spacing: 20) {
            ForEach(options, id: \.1) { option in
                let (value, key, title) = option
                OptionButton(title: title, isSelected: value == selected) { select(value) }
                    .focused($focus, equals: "picture.\(item.rawValue).\(key)")
                    .accessibilityIdentifier("reader.menu.picture.\(item.rawValue).\(key)")
            }
        }
    }

    private func pictureStepper(_ item: PictureMenuItem, value: Double, steps: [Double], label: String,
                                less: (String, String), more: (String, String),
                                set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 28) {
            Button {
                set(PictureSettings.stepped(value, in: steps, by: -1))
            } label: {
                Image(systemName: less.0).frame(width: 50)
            }
            .disabled(!PictureSettings.canStep(value, in: steps, by: -1))
            .focused($focus, equals: "picture.\(item.rawValue).decrease")
            .accessibilityLabel(less.1)
            .accessibilityIdentifier("reader.menu.picture.\(item.rawValue).decrease")

            Text(label)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 110)
                .accessibilityIdentifier("reader.menu.picture.\(item.rawValue).value")

            Button {
                set(PictureSettings.stepped(value, in: steps, by: 1))
            } label: {
                Image(systemName: more.0).frame(width: 50)
            }
            .disabled(!PictureSettings.canStep(value, in: steps, by: 1))
            .focused($focus, equals: "picture.\(item.rawValue).increase")
            .accessibilityLabel(more.1)
            .accessibilityIdentifier("reader.menu.picture.\(item.rawValue).increase")
        }
    }

    private func set<V>(_ keyPath: WritableKeyPath<ReaderSettings, V>, _ value: V) {
        session.updateSettings(settings.with(keyPath, value))
    }
}

/// A selectable option: a ring that fills with a check when chosen.
struct OptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.callout)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The series' chapters, with the open one marked and in view. Picking one
/// opens it and closes the menu. Lives inside the menu's ScrollView, below
/// the header and tabs; `proxy` is that scroll view's reader.
private struct ChapterListPane: View {
    let session: ReaderSession
    var focus: FocusState<String?>.Binding
    let proxy: ScrollViewProxy

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(session.chapters) { chapter in
                row(chapter).id(chapter.id)
            }
        }
        .padding(.top, 20)
        .onAppear {
            let current = session.chapter.id
            proxy.scrollTo(current, anchor: .center)
            DispatchQueue.main.async { focus.wrappedValue = "chapter.\(current)" }
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == session.chapter.id
        return Button {
            session.isMenuPresented = false
            guard !isCurrent else { return }
            Task { await session.load(chapter: chapter) }
        } label: {
            HStack(spacing: 20) {
                Text(chapter.title)
                    .lineLimit(1)
                    .foregroundStyle(chapter.isRead && !isCurrent ? .secondary : .primary)
                Spacer(minLength: 20)
                if isCurrent {
                    Text("Reading").foregroundStyle(.secondary)
                } else if chapter.isRead {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focused(focus, equals: "chapter.\(chapter.id)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("reader.menu.chapter.\(chapter.id)")
    }
}

/// This series' bookmarks. Picking one turns to its page (opening its
/// chapter if needed) and closes the menu. Lives inside the menu's
/// ScrollView, below the header and tabs.
private struct BookmarkListPane: View {
    let session: ReaderSession
    var focus: FocusState<String?>.Binding

    var body: some View {
        let bookmarks = session.seriesBookmarks
        LazyVStack(alignment: .leading, spacing: 16) {
            if bookmarks.isEmpty {
                Text("No bookmarks in this series yet. Choose Bookmark This Page, or in the page reader press up on the remote.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reader.menu.bookmarks.empty")
            }
            ForEach(bookmarks) { bookmark in
                row(bookmark)
            }
        }
        .padding(.top, 20)
    }

    private func row(_ bookmark: Bookmark) -> some View {
        let available = session.chapters.contains { $0.id == bookmark.chapterID }
        return Button {
            session.open(bookmark)
        } label: {
            HStack(spacing: 20) {
                Image(systemName: "bookmark.fill").foregroundStyle(.red)
                Text(bookmark.chapterTitle.isEmpty ? "Chapter" : bookmark.chapterTitle).lineLimit(1)
                Spacer(minLength: 20)
                Text(bookmark.pageLabel).foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!available)
        .focused(focus, equals: "bookmark.\(bookmark.id)")
        .accessibilityIdentifier("reader.menu.bookmark.\(bookmark.chapterID).\(bookmark.page)")
        .contextMenu {
            Button("Remove Bookmark", role: .destructive) { session.model.removeBookmark(bookmark) }
        }
    }
}

extension AppModel {
    /// The active profile's reader settings for series that have none of
    /// their own.
    var menuDefaultReaderSettings: ReaderSettings {
        state.profileData[activeProfile.id.uuidString]?.defaultReaderSettings ?? .default
    }

    func setMenuDefaultReaderSettings(_ settings: ReaderSettings) {
        let profile = activeProfile.id
        update { $0.setDefaultReaderSettings(settings, profile: profile) }
    }
}
