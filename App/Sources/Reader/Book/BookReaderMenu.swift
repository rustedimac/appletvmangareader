import SwiftUI
import MangaCore

/// The book reader's drawer, on the right like the image reader's menu so
/// the page stays in view and changes show behind it as they're made.
///
/// Settings: text size, font, line spacing, theme, columns, justification.
/// They apply live and are saved for the profile. Contents: the book's
/// table of contents (or its sections when it has none); picking one jumps
/// there and closes the drawer.
///
/// Identifiers: `book.menu.<row>.<option>` (for example
/// `book.menu.theme.sepia`, `book.menu.size.larger`) and `book.toc.<n>`.
struct BookReaderMenu: View {
    let session: BookReaderSession

    @State private var tab: Tab = .settings
    @FocusState private var focus: String?

    enum Tab: String, CaseIterable, Identifiable {
        case settings
        case contents

        var id: String { rawValue }
        var title: String { self == .settings ? "Settings" : "Contents" }
    }

    private var settings: BookSettings { session.settings }

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
        .defaultFocus($focus, "size.larger")
        .onAppear { DispatchQueue.main.async { focus = "size.larger" } }
        .onPlayPauseCommand { session.isMenuPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book.menu")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.series.title).font(.headline).lineLimit(1)
                Text(session.manifest?.title ?? session.chapter.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            SectionTabBar(tabs: Tab.allCases, selection: $tab, title: \.title,
                          identifier: { "book.menu.tab.\($0.rawValue)" },
                          focus: $focus, focusKey: { "tab.\($0.rawValue)" },
                          trackIdentifier: "book.menu.tabs")
            switch tab {
            case .settings: settingsPane
            case .contents: BookContentsPane(session: session)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 60)
    }

    private var settingsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                row("Text Size") {
                    Button { set(settings.smaller()) } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .disabled(!settings.canShrink)
                    .focused($focus, equals: "size.smaller")
                    .accessibilityLabel("Smaller text")
                    .accessibilityIdentifier("book.menu.size.smaller")
                    Text("\(Int(settings.fontSize)) pt")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 110)
                        .accessibilityIdentifier("book.menu.size.value")
                    Button { set(settings.larger()) } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .disabled(!settings.canGrow)
                    .focused($focus, equals: "size.larger")
                    .accessibilityLabel("Larger text")
                    .accessibilityIdentifier("book.menu.size.larger")
                }
                choices("Font", "font", BookFont.allCases.map { ($0, $0.rawValue, $0.title) }, selected: settings.font) {
                    var s = settings; s.font = $0; set(s)
                }
                choices("Line Spacing", "spacing", BookLineSpacing.allCases.map { ($0, $0.rawValue, $0.title) },
                        selected: settings.lineSpacing) {
                    var s = settings; s.lineSpacing = $0; set(s)
                }
                choices("Theme", "theme", BookTheme.allCases.map { ($0, $0.rawValue, $0.title) }, selected: settings.theme) {
                    var s = settings; s.theme = $0; set(s)
                }
                choices("Columns", "columns", [(1, "1", "One"), (2, "2", "Two")], selected: settings.clampedColumns) {
                    var s = settings; s.columns = $0; set(s)
                }
                choices("Justify", "justify", [(true, "on", "On"), (false, "off", "Off")], selected: settings.justified) {
                    var s = settings; s.justified = $0; set(s)
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 40)
        }
    }

    private func set(_ s: BookSettings) {
        session.updateSettings(s)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 20) { content() }
        }
        .focusSection()
    }

    private func choices<T: Equatable>(_ title: String, _ key: String, _ options: [(T, String, String)], selected: T,
                                       pick: @escaping (T) -> Void) -> some View {
        row(title) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                OptionButton(title: option.2, isSelected: option.0 == selected) { pick(option.0) }
                    .focused($focus, equals: "\(key).\(option.1)")
                    .accessibilityIdentifier("book.menu.\(key).\(option.1)")
            }
        }
    }
}

/// The table of contents. Books without one list their sections.
private struct BookContentsPane: View {
    let session: BookReaderSession

    private struct Item: Identifiable {
        let id: Int
        let entry: BookTOCEntry
        let level: Int
    }

    private var items: [Item] {
        let toc = BookTOCEntry.flatten(session.manifest?.toc ?? [])
        if !toc.isEmpty {
            return toc.enumerated().map { Item(id: $0.offset, entry: $0.element.entry, level: $0.element.level) }
        }
        return (0..<session.sectionCount).map {
            Item(id: $0, entry: BookTOCEntry(title: "Section \($0 + 1)", section: $0), level: 0)
        }
    }

    private var currentID: Int? {
        let all = items
        return all.last { $0.entry.section <= session.cursor.section }?.id ?? all.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        Button {
                            Task {
                                await session.jump(to: item.entry)
                                session.isMenuPresented = false
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: item.id == currentID ? "bookmark.fill" : "text.alignleft")
                                    .frame(width: 36)
                                Text(item.entry.title).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, CGFloat(item.level) * 36)
                            .font(.callout)
                        }
                        .id(item.id)
                        .accessibilityIdentifier("book.toc.\(item.id)")
                        .accessibilityAddTraits(item.id == currentID ? .isSelected : [])
                    }
                }
                .padding(.vertical, 20)
            }
            .onAppear { if let currentID { proxy.scrollTo(currentID, anchor: .center) } }
        }
    }
}
