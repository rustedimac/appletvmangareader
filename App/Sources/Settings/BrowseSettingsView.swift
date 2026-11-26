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
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                HomeChoiceRow(options: HomeServerRows.allCases, selected: layout.serverRows, title: \.title,
                          identifier: { "homeLayout.serverRows.\($0.rawValue)" }) { choice in
                    model.updateBrowse { $0.home.serverRows = choice }
                }
                Text(layout.serverRows == .merged
                     ? "Continue Reading, Recently Updated and Newly Added each show every server's series in one row, newest first."
                     : "Continue Reading, Recently Updated and Newly Added get a row for each server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Server Name on Posters")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                HomeChoiceRow(options: PosterServerLabel.allCases, selected: layout.serverLabel, title: \.title,
                          identifier: { "homeLayout.serverLabel.\($0.rawValue)" }) { choice in
                    model.updateBrowse { $0.home.serverLabel = choice }
                }
                Text("Shows which server a series is from in rows and grids that mix servers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Poster Size")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                HStack(spacing: 30) {
                    ForEach(GridDensity.allCases) { density in
                        let isSelected = model.gridDensity == density
                        Button {
                            model.updateBrowse { $0.gridDensity = density }
                        } label: {
                            Label(density.title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        }
                        .accessibilityIdentifier("browse.density.\(density.rawValue)")
                        .accessibilityValue(isSelected ? "selected" : "")
                    }
                }
                .focusSection()
                Text("For library grids and Favorites. Small fits more series on screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Under Each Poster")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                HStack(spacing: 30) {
                    ForEach(PosterCaption.allCases) { caption in
                        let isSelected = model.posterCaption == caption
                        Button {
                            model.updateBrowse { $0.posterCaption = caption }
                        } label: {
                            Label(caption.title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        }
                        .accessibilityIdentifier("browse.caption.\(caption.rawValue)")
                        .accessibilityValue(isSelected ? "selected" : "")
                    }
                }
                .focusSection()
                Text(PosterCaption.footnote)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                let showsPercent = model.browsePreferences.showsProgressPercent
                Button {
                    model.updateBrowse { $0.showsProgressPercent.toggle() }
                } label: {
                    Label("Show Percentage Read", systemImage: showsPercent ? "checkmark.circle.fill" : "circle")
                }
                .accessibilityIdentifier("browse.showsPercent")
                .accessibilityValue(showsPercent ? "on" : "off")
                .padding(.top, 30)
                Text("Puts \"40%\" next to every poster progress bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPage("Customize Home", systemImage: "house")
    }
}

/// A row of radio-style buttons, one per option.
private struct HomeChoiceRow<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let selected: Option
    let title: KeyPath<Option, String>
    let identifier: (Option) -> String
    let choose: (Option) -> Void

    var body: some View {
        HStack(spacing: 30) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    choose(option)
                } label: {
                    Label(option[keyPath: title], systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .lineLimit(1)
                }
                .accessibilityIdentifier(identifier(option))
                .accessibilityValue(isSelected ? "selected" : "")
            }
        }
        .focusSection()
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
                        .foregroundStyle(hidden ? Color.secondary : Color.primary)
                    Spacer()
                    Text(hidden ? "Hidden" : "Shown")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 560)
            }
            .accessibilityIdentifier("homeLayout.toggle.\(kind.rawValue)")
            .accessibilityValue(hidden ? "hidden" : "shown")

            Button {
                change { $0.move(kind, by: -1) }
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!layout.canMove(kind, by: -1))
            .accessibilityLabel("Move \(kind.title) Up")
            .accessibilityIdentifier("homeLayout.up.\(kind.rawValue)")

            Button {
                change { $0.move(kind, by: 1) }
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(!layout.canMove(kind, by: 1))
            .accessibilityLabel("Move \(kind.title) Down")
            .accessibilityIdentifier("homeLayout.down.\(kind.rawValue)")
        }
        .focusSection()
    }
}
