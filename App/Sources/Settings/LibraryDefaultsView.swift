import SwiftUI
import MangaCore

/// "Library Defaults": the sort, filters and grid order every library uses
/// until its own Sort & View sets something else. Opened from Settings,
/// Customize Home and each library's Sort & View.
struct LibraryDefaultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let defaults = model.libraryDefaults
        Form {
            Section(settingsHeader: "Sort By") {
                ForEach(LibrarySort.allCases) { sort in
                    ChoiceRow(title: sort.title, isSelected: defaults.sort == sort,
                              identifier: "libraryDefaults.sort.\(sort.rawValue)") {
                        model.updateLibraryDefaults { $0.sort = sort }
                    }
                }
            }

            // Genres are per library, so the default has none.
            LibraryFilterSections<EmptyView>(filter: defaults.filter, support: [.status, .readProgress],
                                             change: { change in model.updateLibraryDefaults { change(&$0.filter) } })

            Section {
                ForEach(GridOrder.allCases) { order in
                    ChoiceRow(title: order.title, isSelected: defaults.gridOrder == order,
                              identifier: "libraryDefaults.gridOrder.\(order.rawValue)") {
                        model.updateLibraryDefaults { $0.gridOrder = order }
                    }
                }
            } header: {
                SettingsHeader("Grid Order")
            } footer: {
                Text("Right to left puts the first series at the top right, the way manga shelves read.")
            }

            Section {
                Button("Reset to Defaults") {
                    model.updateLibraryDefaults { $0 = .default }
                }
                .disabled(defaults.isDefault)
                .accessibilityIdentifier("libraryDefaults.reset")
            } footer: {
                Text("A library's own Sort & View choices override these. Filters apply on Kavita, Komga and Suwayomi; genres are picked per library.")
            }
        }
        .settingsPage("Library Defaults", systemImage: "square.grid.3x3")
    }
}
