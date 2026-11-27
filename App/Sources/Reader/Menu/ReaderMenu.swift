import SwiftUI
import MangaCore

/// In-reader settings menu. A drawer on the right side of the screen, shown
/// over the page while `session.isMenuPresented` is true, so the page stays
/// visible and every change shows up behind it straight away.
///
/// Siri Remote: holding Play/Pause opens it in every reader (and closes
/// it), caught by `ReaderRemoteCatcher`; a Play/Pause press also closes it.
/// Every setting is one row (name left, value right). A click on a row with
/// a chevron opens its choices in place of the rows; a click on an On/Off
/// row flips it. Menu closes the choices, then the drawer
/// (`ReaderSession.back()`). The bottom of the settings tab lists every
/// control for the reader on screen (`ReaderControls`).
///
/// Changes apply live through `session.updateSettings(_:)`, which saves them
/// for this series. "Set as Default" copies them to the profile default that
/// series without their own settings use.
///
/// Modeled on Mihon's reading-mode sheet (rows change with the mode) and
/// Kavita's reader settings drawer, laid out like a tvOS settings form.
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
        layout
            .tvFocusSection()
            .defaultFocus($focus, initialFocus)
            .onAppear { setFocus(initialFocus) }
            // Menu closes an open list of choices first, then the drawer
            // (`ReaderSession.back()`). `ReaderRemoteCatcher` takes Menu while
            // the drawer is open, so this works whatever has focus, even none;
            // the handler here is only a fallback. Play/Pause is the catcher's.
            .onRemoteExit { session.back() }
            // However the choices close (Menu, a pick), focus goes back to
            // their row. A tab switch closes them too; focus stays on the tab.
            .onChange(of: session.menuPicker) { old, new in
                guard new == nil, let old, tab == .settings else { return }
                setFocus(pickerSpec(old).key)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reader.menu")
    }

    /// tvOS: a drawer on the right over the page. iPhone/iPad: the content
    /// of the options popover (a sheet on iPhone), see ReaderTouchChrome.
    @ViewBuilder
    private var layout: some View {
        #if os(tvOS)
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            panel
                .frame(width: 900)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.thickMaterial)
        }
        .ignoresSafeArea()
        #else
        panel
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    private var initialFocus: String { ReaderMenuItem.mode.rawValue }

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
                        .tvFocusSection()
                    SectionTabBar(tabs: Tab.allCases, selection: $tab, title: \.title,
                                  identifier: { "reader.menu.tab.\($0.rawValue)" },
                                  focus: $focus, focusKey: { "tab.\($0.rawValue)" },
                                  trackIdentifier: "reader.menu.tabs")
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
            // An open list of choices belongs to the Settings tab.
            .onChange(of: tab) { _, _ in session.menuPicker = nil }
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
        .tvFocusSection()
    }

    /// Bookmarks the page on screen, or removes its bookmark.
    private var bookmarkButton: some View {
        let on = session.isShowingBookmarkedPage
        return Button {
            session.toggleBookmark()
        } label: {
            Label(on ? "Remove Bookmark" : "Bookmark This Page", systemImage: on ? "bookmark.fill" : "bookmark")
                .font(.callout)
                .lineLimit(1)
                .padding(.vertical, RowMetrics.textInset)
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
                .lineLimit(1)
                .padding(.vertical, RowMetrics.textInset)
        }
        .disabled(session.loadState != .loaded || session.pageCount == 0)
        .focused($focus, equals: "browsePages")
        .accessibilityIdentifier("reader.menu.browsePages")
    }

    // MARK: Settings

    /// One row per setting, laid out like a settings form: the setting's
    /// name on the left and its value on the right. A row with a chevron
    /// opens its choices in place of the rows (`PanelChoiceList`); an
    /// On/Off row flips with a click. Steppers (column width, auto-scroll,
    /// brightness, contrast) keep their − value + buttons.
    @ViewBuilder
    private var settingsPane: some View {
        if let picker = session.menuPicker {
            choiceList(picker)
                .padding(.top, 20)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(ReaderMenuOptions.items(for: settings, touch: !Platform.isTV)) { item in
                    row(item)
                }
                if settings.mode == .paged {
                    stepperSection("Page Timer") { playControls }
                }
                Divider().padding(.vertical, Space.s)
                picturePane
                // The tutorial saves no settings, so no Set as Default there.
                if !session.isTutorial {
                    Divider().padding(.vertical, Space.s)
                    defaultsSection
                }
                // Touch screens list nothing here unless a game controller
                // is connected; their controls are on screen.
                if Platform.isTV || GameControllerHub.shared.hasExtendedGamepad {
                    Divider().padding(.vertical, Space.s)
                    ReaderControlsLegend(mode: settings.mode)
                }
            }
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private func row(_ item: ReaderMenuItem) -> some View {
        switch item {
        case .mode, .layout, .direction, .fit, .zoom, .background, .tapZones:
            pickerRow(.setting(item))
        case .firstPageAlone:
            // The one pairing control. It is saved per series, so it also
            // fixes a book whose spreads come out split (the old "Shift by
            // one" did the same thing and was folded into it).
            toggleRow(item, isOn: settings.showsFirstPageAlone) {
                session.updateSettings(settings.withFirstPageAlone(!settings.showsFirstPageAlone))
            }
            PanelFootnote("If the two halves of a spread land on different screens, switch this.")
                .accessibilityIdentifier("reader.menu.firstPageAlone.hint")
        case .cropBorders:
            toggleRow(item, isOn: settings.cropBorders) { set(\.cropBorders, !settings.cropBorders) }
        case .splitWidePages:
            toggleRow(item, isOn: settings.splitWidePages) { set(\.splitWidePages, !settings.splitWidePages) }
            PanelFootnote("Shows a scanned two-page spread one half at a time, in reading order.")
        case .webtoonWidth:
            stepperSection(item.title) { widthStepper }
        case .autoScroll:
            stepperSection(item.title) { playControls }
        }
    }

    private func toggleRow(_ item: ReaderMenuItem, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        PanelValueRow(title: item.title, isOn: isOn, toggle: toggle)
            .focused($focus, equals: item.rawValue)
            .accessibilityIdentifier("reader.menu.\(item.rawValue)")
    }

    /// A row that opens its choices.
    private func pickerRow(_ picker: ReaderMenuPicker) -> some View {
        let spec = pickerSpec(picker)
        let value = spec.choices.first { $0.id == spec.selected }?.title ?? ""
        return PanelValueRow(title: spec.title, value: value) {
            session.menuPicker = picker
            setFocus("\(spec.key).\(spec.selected)")
        }
        .focused($focus, equals: spec.key)
        .accessibilityIdentifier("reader.menu.\(spec.key)")
    }

    /// The open row's choices, in place of the rows.
    private func choiceList(_ picker: ReaderMenuPicker) -> some View {
        let spec = pickerSpec(picker)
        return PanelChoiceList(title: spec.title, choices: spec.choices, selected: spec.selected,
                               identifierPrefix: "reader.menu.\(spec.key)", focusPrefix: spec.key,
                               focus: $focus, footnote: spec.footnote) { key in
            spec.pick(key)
            closePicker()
        }
        .onAppear { setFocus("\(spec.key).\(spec.selected)") }
    }

    /// Back to the rows, with focus on the row that was open.
    private func closePicker() {
        guard let picker = session.menuPicker else { return }
        session.menuPicker = nil
        setFocus(pickerSpec(picker).key)
    }

    private struct PickerSpec {
        /// Focus key of the row; identifiers are `reader.menu.<key>`.
        let key: String
        let title: String
        let choices: [PanelChoice]
        let selected: String
        var footnote: String? = nil
        let pick: (String) -> Void
    }

    private func pickerSpec(_ picker: ReaderMenuPicker) -> PickerSpec {
        switch picker {
        case .setting(let item):
            switch item {
            case .mode:
                return spec(item, ReadingMode.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.mode) { set(\.mode, $0) }
            case .layout:
                return spec(item, PageLayout.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.layout) { set(\.layout, $0) }
            case .direction:
                return spec(item, ReadingDirection.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.direction) { set(\.direction, $0) }
            case .fit:
                return spec(item, PageFit.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.fit) { set(\.fit, $0) }
            case .zoom:
                return spec(item, ReaderMenuOptions.zoomScales.map { z in
                                (z, ReaderMenuOptions.zoomLabel(z).replacingOccurrences(of: "×", with: "x"),
                                 ReaderMenuOptions.zoomLabel(z))
                            },
                            selected: settings.zoomScale) { set(\.zoomScale, $0) }
            case .background:
                return spec(item, ReaderBackground.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.background) { set(\.background, $0) }
            case .tapZones:
                return spec(item, TapZones.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: settings.tapZones) { set(\.tapZones, $0) }
            case .firstPageAlone, .cropBorders, .splitWidePages, .webtoonWidth, .autoScroll:
                // Toggles and steppers never open a list.
                return PickerSpec(key: item.rawValue, title: item.title, choices: [], selected: "", pick: { _ in })
            }
        case .picture(let item):
            let key = "picture.\(item.rawValue)"
            switch item {
            case .color:
                return spec(key, item.title, PictureColorMode.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: picture.color) { set(\.picture.color, $0) }
            case .sharpen:
                return spec(key, item.title, PictureSharpen.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: picture.sharpen) { set(\.picture.sharpen, $0) }
            case .upscaling:
                return spec(key, item.title, PictureUpscaling.allCases.map { ($0, $0.rawValue, $0.title) },
                            selected: picture.upscaling,
                            footnote: "Sharp (Lanczos) enlarges low-resolution scans to fill a 4K screen with crisper line art.") {
                    set(\.picture.upscaling, $0)
                }
            case .brightness, .contrast:
                return PickerSpec(key: key, title: item.title, choices: [], selected: "", pick: { _ in })
            }
        }
    }

    private func spec<V: Hashable>(_ item: ReaderMenuItem, _ options: [(V, String, String)], selected: V,
                                   select: @escaping (V) -> Void) -> PickerSpec {
        spec(item.rawValue, Self.title(item), options, selected: selected, select: select)
    }

    /// The row's name on this device: touch screens zoom with a double-tap.
    static func title(_ item: ReaderMenuItem) -> String {
        if item == .zoom, !Platform.isTV { return "Double-Tap Zoom" }
        return item.title
    }

    private func spec<V: Hashable>(_ key: String, _ title: String, _ options: [(V, String, String)], selected: V,
                                   footnote: String? = nil, select: @escaping (V) -> Void) -> PickerSpec {
        PickerSpec(key: key, title: title,
                   choices: options.map { PanelChoice(id: $0.1, title: $0.2) },
                   selected: options.first { $0.0 == selected }?.1 ?? "",
                   footnote: footnote,
                   pick: { k in if let value = options.first(where: { $0.1 == k })?.0 { select(value) } })
    }

    /// A stepper keeps its title above it, like the Picture steppers.
    private func stepperSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
        }
        .padding(.vertical, Space.xs)
    }

    private var widthStepper: some View {
        let width = settings.webtoonWidth
        return HStack(spacing: 28) {
            Button {
                set(\.webtoonWidth, ReaderMenuOptions.steppedWidth(width, by: -1))
            } label: {
                Image(systemName: "minus").frame(width: 50).lineHeightLabel()
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
                Image(systemName: "plus").frame(width: 50).lineHeightLabel()
            }
            .disabled(!ReaderMenuOptions.canStepWidth(width, by: 1))
            .focused($focus, equals: "webtoonWidth.increase")
            .accessibilityLabel("Wider")
            .accessibilityIdentifier("reader.menu.webtoonWidth.increase")
        }
    }

    /// Auto-scroll (vertical) or page-timer (paged) speed, as a named step
    /// (saved for the profile, not the series), and a button that closes the
    /// menu and starts it. The same speed drives both.
    private var playControls: some View {
        let level = session.autoScrollLevel
        let webtoon = settings.mode == .webtoon
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                Button {
                    session.isMenuPresented = false
                    session.togglePlay()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .lineLimit(1)
                        .padding(.vertical, RowMetrics.textInset)
                }
                .focused($focus, equals: "autoScroll.start")
                .accessibilityIdentifier("reader.menu.autoScroll.start")

                Button {
                    session.setAutoScrollLevel(WebtoonAutoScroll.stepped(level, by: -1))
                } label: {
                    Image(systemName: "tortoise").frame(width: 50).lineHeightLabel()
                }
                .disabled(!WebtoonAutoScroll.canStep(level, by: -1))
                .focused($focus, equals: "autoScroll.slower")
                .accessibilityLabel("Slower")
                .accessibilityIdentifier("reader.menu.autoScroll.slower")

                Text(WebtoonAutoScroll.label(level))
                    .font(.callout)
                    .frame(minWidth: 180)
                    .accessibilityIdentifier("reader.menu.autoScroll.value")

                Button {
                    session.setAutoScrollLevel(WebtoonAutoScroll.stepped(level, by: 1))
                } label: {
                    Image(systemName: "hare").frame(width: 50).lineHeightLabel()
                }
                .disabled(!WebtoonAutoScroll.canStep(level, by: 1))
                .focused($focus, equals: "autoScroll.faster")
                .accessibilityLabel("Faster")
                .accessibilityIdentifier("reader.menu.autoScroll.faster")
            }
            .font(.callout)
            Text(webtoon
                 ? (Platform.isTV ? "Play/Pause starts and stops it. While it runs, swipe up or down to change speed."
                                  : "The Play button starts and stops it. While it runs, tap the sides to change speed.")
                 : (Platform.isTV ? "Play/Pause starts and stops it. It stops at the end of the chapter."
                                  : "The Play button starts and stops it. It stops at the end of the chapter."))
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
                Button { model.setMenuDefaultReaderSettings(settings) } label: {
                    Text("Set as Default").lineLimit(1).padding(.vertical, RowMetrics.textInset)
                }
                    .focused($focus, equals: "makeDefault")
                    .accessibilityIdentifier("reader.menu.makeDefault")
                Button { session.updateSettings(profileDefault) } label: {
                    Text("Reset to Default").lineLimit(1).padding(.vertical, RowMetrics.textInset)
                }
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
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Picture")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("reader.menu.picture")
            ForEach(ReaderMenuOptions.pictureItems(for: settings)) { item in
                pictureRow(item)
            }
            Button { set(\.picture, .default) } label: {
                Text("Reset Picture").lineLimit(1).padding(.vertical, RowMetrics.textInset)
            }
                .disabled(picture.isDefault)
                .font(.callout)
                .focused($focus, equals: "picture.reset")
                .accessibilityIdentifier("reader.menu.picture.reset")
                // A full-width section, so pressing down from any option
                // above (even the right-most) lands here rather than on
                // the defaults buttons further down.
                .frame(maxWidth: .infinity, alignment: .leading)
                .tvFocusSection()
        }
    }

    @ViewBuilder
    private func pictureRow(_ item: PictureMenuItem) -> some View {
        switch item {
        case .brightness:
            stepperSection(item.title) {
                pictureStepper(item, value: picture.brightness, steps: PictureSettings.brightnessSteps,
                               label: PictureSettings.brightnessLabel(picture.brightness),
                               less: ("sun.min", "Darker"), more: ("sun.max", "Brighter")) {
                    set(\.picture.brightness, $0)
                }
            }
        case .contrast:
            stepperSection(item.title) {
                pictureStepper(item, value: picture.contrast, steps: PictureSettings.contrastSteps,
                               label: PictureSettings.contrastLabel(picture.contrast),
                               less: ("minus", "Less Contrast"), more: ("plus", "More Contrast")) {
                    set(\.picture.contrast, $0)
                }
            }
        case .color, .sharpen:
            pickerRow(.picture(item))
        case .upscaling:
            pickerRow(.picture(item))
            PanelFootnote("Sharp (Lanczos) enlarges low-resolution scans to fill a 4K screen with crisper line art.")
        }
    }

    private func pictureStepper(_ item: PictureMenuItem, value: Double, steps: [Double], label: String,
                                less: (String, String), more: (String, String),
                                set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 28) {
            Button {
                set(PictureSettings.stepped(value, in: steps, by: -1))
            } label: {
                Image(systemName: less.0).frame(width: 50).lineHeightLabel()
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
                Image(systemName: more.0).frame(width: 50).lineHeightLabel()
            }
            .disabled(!PictureSettings.canStep(value, in: steps, by: 1))
            .focused($focus, equals: "picture.\(item.rawValue).increase")
            .accessibilityLabel(more.1)
            .accessibilityIdentifier("reader.menu.picture.\(item.rawValue).increase")
        }
    }

    private func set<V>(_ keyPath: WritableKeyPath<ReaderSettings, V>, _ value: V) {
        session.updateSettings(settings.with(keyPath, value).normalizedPairing)
    }
}

/// A selectable option: a ring that fills with a check when chosen. Only
/// for a short sort toggle beside a grid (Favorites); a setting in a menu
/// or settings page is a `PanelValueRow`, and sections use `SectionTabBar`.
/// One line, with `RowMetrics.textInset` above and below, so chips side by
/// side always share one height.
struct OptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.callout)
            .padding(.vertical, RowMetrics.textInset)
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
                Text(Platform.isTV ? "No bookmarks in this series yet. Choose Bookmark This Page, or in the page reader press up on the remote."
                                   : "No bookmarks in this series yet. Choose Bookmark This Page, or tap the bookmark at the top of the reader.")
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
        (state.profileData[activeProfile.id.uuidString]?.defaultReaderSettings ?? .default).normalizedPairing
    }

    func setMenuDefaultReaderSettings(_ settings: ReaderSettings) {
        let profile = activeProfile.id
        update { $0.setDefaultReaderSettings(settings, profile: profile) }
    }
}


/// "Controls" at the bottom of the settings tab: every Siri Remote control
/// for the reader on screen, plus the game controller's when one is
/// connected, as the same plain-text legend as Settings > Remote and
/// Controller (`ControlsLegend`), so it always matches the readers. The
/// whole legend is one focus stop with no action, only so the drawer can
/// scroll down to it.
struct ReaderControlsLegend: View {
    let mode: ReadingMode
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Controls")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("reader.menu.controls")
            if Platform.isTV {
                Text("Siri Remote")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ControlsLegend(entries: ReaderControls.remote(for: mode), id: "reader.remote")
            }
            if GameControllerHub.shared.hasExtendedGamepad {
                Text("Game Controller")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ControlsLegend(entries: ReaderControls.gamepad, id: "reader.gamepad")
            }
        }
        .padding(Space.s)
        .background(focused ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: Radius.card))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
    }
}
