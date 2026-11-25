import SwiftUI
import MangaCore

/// "Customize Home": the order of Home rows, which are shown, and the
/// poster size for grids. Opened from the bottom of Home and from Settings.
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
                    model.updateBrowse { $0.home = .default }
                }
                .disabled(layout.isDefault)
                .accessibilityIdentifier("homeLayout.reset")

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
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPage("Customize Home", systemImage: "house")
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
