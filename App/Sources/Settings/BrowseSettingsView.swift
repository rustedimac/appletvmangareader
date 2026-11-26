import SwiftUI
import MangaCore

/// "Customize Home": the order of Home rows, which are shown, whether
/// server rows are merged, where posters name their server, the poster
/// size for grids, and what posters show under the title. Opened from the
/// bottom of Home and from Settings.
struct BrowseSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.homeLayout
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Home Rows")
                    .sectionLabelStyle()
                Text("Click a row to show or hide it. Use the arrows to move it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(layout.rows) { kind in
                    HomeRowEditor(kind: kind, layout: layout) { change in
                        model.updateBrowse { change(&$0.home) }
                    }
                }
                Button("Reset Home Rows") {
                    model.updateBrowse { $0.home.resetRows() }
                }
                .disabled(layout.rowsAreDefault)
                .accessibilityIdentifier("homeLayout.reset")

                Text("Servers on Home")
                    .sectionLabelStyle()
                    .padding(.top, Space.m)
                SettingsPicker("Server Rows", selection: binding(\.home.serverRows),
                               options: HomeServerRows.allCases, systemImage: "server.rack") { $0.title }
                    .accessibilityIdentifier("homeLayout.serverRows")
                PanelFootnote(layout.serverRows == .merged
                              ? "Continue Reading, Recently Updated and Newly Added each show every server's series in one row, newest first."
                              : "Continue Reading, Recently Updated and Newly Added get a row for each server.")

                Text("Posters")
                    .sectionLabelStyle()
                    .padding(.top, Space.m)
                SettingsPicker("Server Name", selection: binding(\.home.serverLabel),
                               options: PosterServerLabel.allCases, systemImage: "tag",
                               footnote: "Shows which server a series is from in rows and grids that mix servers.") { $0.title }
                    .accessibilityIdentifier("homeLayout.serverLabel")
                SettingsPicker("Poster Size", selection: binding(\.gridDensity),
                               options: GridDensity.allCases, systemImage: "square.grid.3x2",
                               footnote: "Small fits more series on screen.") { $0.title }
                    .accessibilityIdentifier("browse.density")
                SettingsPicker("Under Each Poster", selection: binding(\.posterCaption),
                               options: PosterCaption.allCases, systemImage: "text.below.photo",
                               footnote: PosterCaption.footnote) { $0.title }
                    .accessibilityIdentifier("browse.caption")
                let showsPercent = model.browsePreferences.showsProgressPercent
                PanelValueRow(title: "Show Percentage Read", isOn: showsPercent) {
                    model.updateBrowse { $0.showsProgressPercent.toggle() }
                }
                .accessibilityIdentifier("browse.showsPercent")
                PanelFootnote("Server Name shows which server a series is from where servers mix. Poster Size and Under Each Poster apply everywhere posters appear. Show Percentage Read puts \"40%\" next to every poster progress bar, and \"40% read\" on series pages.")

                Text("Libraries")
                    .sectionLabelStyle()
                    .padding(.top, Space.m)
                NavigationLink {
                    LibraryDefaultsView()
                } label: {
                    SettingsValueRow(title: "Library Defaults",
                                     value: "\(model.libraryDefaults.sort.title), \(model.libraryDefaults.filter.summary)")
                        .padding(.vertical, RowMetrics.textInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("browse.libraryDefaults")
                PanelFootnote("The sort, filters and grid order for libraries that don't set their own in Sort & View.")
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsRowsOutsideForm()
        .settingsPage("Customize Home", systemImage: "house")
    }

    /// A binding to one browse preference; writes go through
    /// `updateBrowse`, so they're saved and synced like every other change.
    private func binding<V>(_ keyPath: WritableKeyPath<BrowsePreferences, V>) -> Binding<V> {
        Binding(get: { model.browsePreferences[keyPath: keyPath] },
                set: { value in model.updateBrowse { $0[keyPath: keyPath] = value } })
    }
}

/// One Home row: a show/hide button and up/down arrows.
private struct HomeRowEditor: View {
    let kind: HomeRowKind
    let layout: HomeLayout
    let change: ((inout HomeLayout) -> Void) -> Void

    var body: some View {
        let hidden = layout.isHidden(kind)
        HStack(spacing: 24) {
            Button {
                change { $0.setHidden(kind, !hidden) }
            } label: {
                HStack(spacing: 20) {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                        .frame(width: 44)
                    Text(kind.title)
                        .lineLimit(1)
                        .foregroundStyle(hidden ? Color.secondary : Color.primary)
                    Spacer(minLength: Space.m)
                    Text(hidden ? "Hidden" : "Shown")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, RowMetrics.textInset)
                .frame(width: 560)
            }
            .accessibilityIdentifier("homeLayout.toggle.\(kind.rawValue)")
            .accessibilityValue(hidden ? "hidden" : "shown")

            Button {
                change { $0.move(kind, by: -1) }
            } label: {
                Image(systemName: "arrow.up")
                    .lineHeightLabel()
            }
            .disabled(!layout.canMove(kind, by: -1))
            .accessibilityLabel("Move \(kind.title) Up")
            .accessibilityIdentifier("homeLayout.up.\(kind.rawValue)")

            Button {
                change { $0.move(kind, by: 1) }
            } label: {
                Image(systemName: "arrow.down")
                    .lineHeightLabel()
            }
            .disabled(!layout.canMove(kind, by: 1))
            .accessibilityLabel("Move \(kind.title) Down")
            .accessibilityIdentifier("homeLayout.down.\(kind.rawValue)")
        }
        .focusSection()
    }
}
