import SwiftUI
import MangaCore

/// "Sort & View" for one library or category: sort order, filters, the
/// reading direction its series open in, which way the grid fills, and the
/// profile's poster size and caption. Sort, filters and grid order start
/// from Library Defaults; picking a value here overrides it for this
/// library only, and "Default" rows (or Reset to Defaults) go back.
struct LibraryOptionsView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let category: MangaCategory

    var body: some View {
        let options = model.libraryOptions(server, category)
        let defaults = model.libraryDefaults
        let support = model.client(for: server).libraryFilterSupport
        Form {
            Section(settingsHeader: "Sort By") {
                ChoiceRow(title: "Default (\(defaults.sort.title))", isSelected: options.sort == nil,
                          identifier: "libraryOptions.sort.default") {
                    set(\.sort, nil)
                }
                ForEach(LibrarySort.allCases) { sort in
                    ChoiceRow(title: sort.title, isSelected: options.sort == sort,
                              identifier: "libraryOptions.sort.\(sort.rawValue)") {
                        set(\.sort, sort)
                    }
                }
            }

            if !support.isEmpty {
                LibraryFilterSections<GenreFilterView>(
                    filter: (options.filter ?? defaults.filter).limited(to: support),
                    support: support,
                    defaultRow: .init(summary: defaults.filter.limited(to: support).summary,
                                      isSelected: options.filter == nil) { set(\.filter, nil) },
                    genres: { GenreFilterView(server: server, category: category) },
                    change: { change in
                        var filter = options.filter ?? defaults.filter
                        change(&filter)
                        set(\.filter, filter)
                    })
            } else {
                Section {
                } header: {
                    SettingsHeader("Filters")
                } footer: {
                    Text("\(server.kind.displayName) doesn't send the details filters need, such as status or genre.")
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
                ChoiceRow(title: "Default (\(defaults.gridOrder.title))", isSelected: options.gridOrder == nil,
                          identifier: "libraryOptions.gridOrder.default") {
                    set(\.gridOrder, nil)
                }
                ForEach(GridOrder.allCases) { order in
                    ChoiceRow(title: order.title, isSelected: options.gridOrder == order,
                              identifier: "libraryOptions.gridOrder.\(order.rawValue)") {
                        set(\.gridOrder, order)
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
                Text("Puts \"40%\" next to every poster progress bar, and \"40% read\" on series pages. Applies everywhere posters appear.")
            }

            Section {
                Button("Reset to Defaults") {
                    model.setLibraryOptions(LibraryOptions(), server, category)
                }
                .disabled(options.isEmpty)
                .accessibilityIdentifier("libraryOptions.reset")
                NavigationLink {
                    LibraryDefaultsView()
                } label: {
                    Label("Library Defaults", systemImage: "square.grid.3x3")
                }
                .accessibilityIdentifier("libraryOptions.defaults")
            } footer: {
                Text(options.isEmpty
                     ? "\(category.name) uses your Library Defaults."
                     : "Reset to Defaults clears what you set for \(category.name) and uses your Library Defaults again.")
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

/// The filter rows shared by Sort & View and Library Defaults: publication
/// status, read progress and (per library only) genres.
struct LibraryFilterSections<Genres: View>: View {
    /// A "Default (…)" row that clears the override, on Sort & View.
    struct DefaultRow {
        let summary: String
        let isSelected: Bool
        let action: () -> Void
    }

    let filter: LibraryFilter
    let support: LibraryFilterSupport
    var defaultRow: DefaultRow? = nil
    /// The genre picker; nil hides the genre row (Library Defaults).
    var genres: (() -> Genres)?
    let change: ((inout LibraryFilter) -> Void) -> Void

    var body: some View {
        if let defaultRow {
            Section {
                ChoiceRow(title: "Default (\(defaultRow.summary))", isSelected: defaultRow.isSelected,
                          identifier: "libraryOptions.filter.default", action: defaultRow.action)
            } header: {
                SettingsHeader("Filters")
            } footer: {
                Text("Changing a filter below sets this library's own filters.")
            }
        }

        if support.contains(.status) {
            Section {
                ForEach(PublicationStatus.allCases) { status in
                    ChoiceRow(title: status.title, isSelected: filter.statuses.contains(status),
                              identifier: "libraryFilter.status.\(status.rawValue)") {
                        change { f in
                            if f.statuses.contains(status) { f.statuses.remove(status) } else { f.statuses.insert(status) }
                        }
                    }
                }
            } header: {
                SettingsHeader("Status")
            } footer: {
                Text(filter.statuses.isEmpty
                     ? "Showing every status. Pick one or more to show only those."
                     : "Showing series that are \(PublicationStatus.allCases.filter(filter.statuses.contains).map(\.title).joined(separator: " or ")). Series without a status are hidden.")
            }
        }

        if support.contains(.readProgress) {
            Section {
                ForEach(ReadProgressFilter.allCases) { read in
                    ChoiceRow(title: read.title, isSelected: filter.readProgress == read,
                              identifier: "libraryFilter.read.\(read.rawValue)") {
                        change { $0.readProgress = read }
                    }
                }
            } header: {
                SettingsHeader("Read Progress")
            } footer: {
                Text("Not Finished shows series with chapters left to read, started or not.")
            }
        }

        if support.contains(.genres), let genres {
            Section {
                NavigationLink {
                    genres()
                } label: {
                    HStack {
                        Text("Genres")
                        Spacer()
                        Text(filter.genres.isEmpty ? "Any" : LibraryFilter.genreList(filter.genres).joined(separator: ", "))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("libraryFilter.genres")
            } footer: {
                Text("Show only series in any of the genres you pick.")
            }
        }
    }
}

/// Picks the genres one library shows. Loads the list from the server.
struct GenreFilterView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig
    let category: MangaCategory

    @State private var genres: [String]?
    @State private var errorMessage: String?

    var body: some View {
        let options = model.libraryOptions(server, category)
        let filter = options.filter ?? model.libraryDefaults.filter
        Form {
            if let errorMessage {
                Section {
                    BrowseMessage(title: "Couldn't load genres", message: errorMessage,
                                  systemImage: "exclamationmark.triangle") { Task { await load() } }
                }
            } else if let genres {
                Section {
                    ChoiceRow(title: "Any Genre", isSelected: filter.genres.isEmpty, identifier: "genreFilter.any") {
                        update { $0.genres = [] }
                    }
                    // Picked genres the server no longer lists stay visible so they can be cleared.
                    let picked = Set(genres.map(LibraryFilter.fold))
                    let stale = LibraryFilter.genreList(filter.genres.filter { !picked.contains(LibraryFilter.fold($0)) })
                    ForEach(stale + genres, id: \.self) { genre in
                        let folded = LibraryFilter.fold(genre)
                        let isSelected = filter.genres.contains { LibraryFilter.fold($0) == folded }
                        ChoiceRow(title: genre, isSelected: isSelected, identifier: "genreFilter.\(genre)") {
                            update { f in
                                if isSelected {
                                    f.genres = f.genres.filter { LibraryFilter.fold($0) != folded }
                                } else {
                                    f.genres.insert(genre)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(genres.isEmpty ? "\(category.name) has no genres yet." : "Series in any picked genre are shown.")
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .settingsPage("\(category.name): Genres", systemImage: "tag")
        .task { await load() }
    }

    private func update(_ change: (inout LibraryFilter) -> Void) {
        var options = model.libraryOptions(server, category)
        var filter = options.filter ?? model.libraryDefaults.filter
        change(&filter)
        options.filter = filter
        model.setLibraryOptions(options, server, category)
    }

    private func load() async {
        do {
            genres = try await model.client(for: server).filterGenres(in: category)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
