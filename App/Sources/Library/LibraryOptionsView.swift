import SwiftUI
import MangaCore

/// "Sort & View" for one library or category: sort order, the reading
/// direction its series open in, which way the grid fills, and the
/// profile's poster size and caption.
struct LibraryOptionsView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let category: MangaCategory

    var body: some View {
        let options = model.libraryOptions(server, category)
        Form {
            Section(settingsHeader: "Sort By") {
                ForEach(LibrarySort.allCases) { sort in
                    ChoiceRow(title: sort.title, isSelected: (options.sort ?? .default) == sort,
                              identifier: "libraryOptions.sort.\(sort.rawValue)") {
                        set(\.sort, sort == .default ? nil : sort)
                    }
                }
            }

            Section {
                ChoiceRow(title: "My Default", isSelected: options.readingStyle == nil,
                          identifier: "libraryOptions.style.default") {
                    set(\.readingStyle, nil)
                }
                ForEach(LibraryReadingStyle.allCases) { style in
                    ChoiceRow(title: style.title, isSelected: options.readingStyle == style,
                              identifier: "libraryOptions.style.\(style.rawValue)") {
                        set(\.readingStyle, style)
                    }
                }
            } header: {
                SettingsHeader("Reading Direction")
            } footer: {
                Text("Series in \(category.name) open this way, unless you change a series' settings in the reader.")
            }

            Section {
                ForEach(GridOrder.allCases) { order in
                    ChoiceRow(title: order.title, isSelected: (options.gridOrder ?? .automatic) == order,
                              identifier: "libraryOptions.gridOrder.\(order.rawValue)") {
                        set(\.gridOrder, order == .automatic ? nil : order)
                    }
                }
            } header: {
                SettingsHeader("Grid Order")
            } footer: {
                Text("Right to left puts the first series at the top right, the way manga shelves read.")
            }

            Section {
                ForEach(GridDensity.allCases) { density in
                    ChoiceRow(title: density.title, isSelected: model.gridDensity == density,
                              identifier: "libraryOptions.density.\(density.rawValue)") {
                        model.updateBrowse { $0.gridDensity = density }
                    }
                }
            } header: {
                SettingsHeader("Poster Size")
            } footer: {
                Text("Small fits more series on screen. Applies to every library and to Favorites.")
            }

            Section {
                ForEach(PosterCaption.allCases) { caption in
                    ChoiceRow(title: caption.title, isSelected: model.posterCaption == caption,
                              identifier: "libraryOptions.caption.\(caption.rawValue)") {
                        model.updateBrowse { $0.posterCaption = caption }
                    }
                }
            } header: {
                SettingsHeader("Under Each Poster")
            } footer: {
                Text(PosterCaption.footnote)
            }

            Section {
                Toggle("Show Percentage Read", isOn: Binding(
                    get: { model.browsePreferences.showsProgressPercent },
                    set: { on in model.updateBrowse { $0.showsProgressPercent = on } }))
                    .accessibilityIdentifier("libraryOptions.showsPercent")
            } footer: {
                Text("Puts \"40%\" next to every poster progress bar. Applies everywhere posters appear.")
            }
        }
        .settingsPage("\(category.name): Sort & View", systemImage: "arrow.up.arrow.down")
    }

    private func set<V>(_ keyPath: WritableKeyPath<LibraryOptions, V>, _ value: V) {
        var options = model.libraryOptions(server, category)
        options[keyPath: keyPath] = value
        model.setLibraryOptions(options, server, category)
    }
}

/// A list row that picks one option, with a check on the picked one.
struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected { Image(systemName: "checkmark") }
            }
        }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isSelected ? "selected" : "")
    }
}
