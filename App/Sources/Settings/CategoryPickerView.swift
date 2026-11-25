import SwiftUI
import MangaCore

/// Loading the server's libraries/categories for the "import" checklist.
enum CategoryLoad: Equatable {
    case idle
    case loading
    case loaded(CategorySelection)
    case failed(String)

    var selection: CategorySelection? {
        if case .loaded(let s) = self { return s }
        return nil
    }
}

/// Checklist rows for a server's Kavita libraries or Suwayomi categories.
/// Used inline in the server editor and on `CategorySelectionView`.
struct CategoryChecklist: View {
    let kind: ServerKind
    @Binding var load: CategoryLoad
    var retry: () -> Void

    var body: some View {
        switch load {
        case .idle:
            EmptyView()
        case .loading:
            HStack {
                Text("Loading \(kind.categoryNoun.lowercased())…").foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        case .failed(let message):
            Button {
                retry()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load \(kind.categoryNoun.lowercased()). Try Again")
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("categories.retry")
        case .loaded(let selection):
            if selection.available.isEmpty {
                Text("This server has no \(kind.categoryNoun.lowercased()) your account can see.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selection.available) { category in
                    let isOn = selection.isSelected(category.id)
                    Button {
                        var s = selection
                        s.toggle(category.id)
                        load = .loaded(s)
                    } label: {
                        HStack {
                            Text(category.name)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                        }
                    }
                    .accessibilityIdentifier("categories.item.\(category.id)")
                    .accessibilityValue(isOn ? "on" : "off")
                }
                if selection.available.count > 1 {
                    Button(selection.allSelected ? "Select None" : "Select All") {
                        var s = selection
                        if s.allSelected { s.selectNone() } else { s.selectAll() }
                        load = .loaded(s)
                    }
                    .accessibilityIdentifier("categories.toggleAll")
                }
            }
        }
    }

    /// Footer text under the checklist.
    static func footer(kind: ServerKind, load: CategoryLoad) -> String? {
        guard let selection = load.selection, !selection.available.isEmpty else { return nil }
        let noun = kind.categoryNoun.lowercased()
        if !selection.canSave { return "Pick at least one to import." }
        let base = "\(selection.summary(kind: kind)). Home, Library, Search and Favorites only show what's ticked."
        return selection.allSelected ? base + " New \(noun) on the server are added automatically." : base
    }
}

/// Picks which libraries/categories of a saved server the active profile
/// imports. Opened from the Library tab; saves when "Save" is pressed.
struct CategorySelectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig

    @State private var load: CategoryLoad = .idle

    var body: some View {
        Form {
            ScreenTitle("\(server.name) \(server.kind.categoryNoun)")
            Section {
                CategoryChecklist(kind: server.kind, load: $load, retry: { Task { await fetch() } })
            } header: {
                Text("\(server.kind.categoryNoun) to Import for \(model.activeProfile.name)")
            } footer: {
                if let footer = CategoryChecklist.footer(kind: server.kind, load: load) { Text(footer) }
            }
            Section {
                Button("Save") {
                    if let selection = load.selection {
                        model.setSelectedCategories(selection.storedValue, for: server)
                    }
                    dismiss()
                }
                .disabled(!(load.selection?.canSave ?? false))
                .accessibilityIdentifier("categories.save")
            }
        }
        .task { if load == .idle { await fetch() } }
    }

    private func fetch() async {
        load = .loading
        do {
            let available = try await model.availableCategories(server, credential: model.credential(for: server))
            load = .loaded(CategorySelection(available: available, saved: model.selectedCategories(for: server)))
        } catch {
            load = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
