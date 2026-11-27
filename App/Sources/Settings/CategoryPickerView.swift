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
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Couldn't load \(kind.categoryNoun.lowercased())")
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button("Try Again", action: retry)
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
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(category.name)
                                if let note = Self.note(for: category, kind: kind) {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle") // option-chip-ok: full-width checklist row
                                .themedMark(isOn)
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

    /// Suwayomi's built-in "Default" category is where series without a
    /// category live. It's an ordinary tick box like the rest, but its name
    /// reads like a "use the default" choice, so it says what it holds.
    static func note(for category: MangaCategory, kind: ServerKind) -> String? {
        kind == .suwayomi && category.id == SuwayomiClient.defaultCategoryID ? "Series not in any category" : nil
    }

    /// Footer text under the checklist. `live`: ticks apply as they change,
    /// so with none ticked the last choice stays in effect.
    static func footer(kind: ServerKind, load: CategoryLoad, live: Bool = false) -> String? {
        guard let selection = load.selection, !selection.available.isEmpty else { return nil }
        let noun = kind.categoryNoun.lowercased()
        if !selection.canSave {
            return live ? "Pick at least one to import. Until you do, the last choice stays." : "Pick at least one to import."
        }
        let base = "\(selection.summary(kind: kind)). Home, Library, Search and Favorites only show what's ticked."
        return selection.allSelected ? base + " New \(noun) on the server are added automatically." : base
    }
}

/// Picks which libraries/categories of a saved server the active profile
/// imports. Opened from the Library tab. Every tick applies right away;
/// there's no Save button (docs/DESIGN_GUIDE.md, "No Save buttons"). With
/// nothing ticked, the last choice that had at least one stays in effect.
struct CategorySelectionView: View {
    @Environment(AppModel.self) private var model
    let server: ServerConfig

    @State private var load: CategoryLoad = .idle

    var body: some View {
        Form {
            Section {
                CategoryChecklist(kind: server.kind, load: $load, retry: { Task { await fetch() } })
            } header: {
                SettingsHeader("\(server.kind.categoryNoun) to Import for \(model.activeProfile.name)")
            } footer: {
                if let footer = CategoryChecklist.footer(kind: server.kind, load: load, live: true) { Text(footer) }
            }
        }
        .settingsPage("\(server.name) \(server.kind.categoryNoun)", systemImage: "checklist")
        .task { if load == .idle { await fetch() } }
        .onChange(of: load) { _, new in apply(new) }
    }

    /// Stores the ticks as soon as they change (skipped while nothing is ticked).
    private func apply(_ load: CategoryLoad) {
        guard let selection = load.selection, selection.canSave,
              selection.storedValue != model.selectedCategories(for: server) else { return }
        model.setSelectedCategories(selection.storedValue, for: server)
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
