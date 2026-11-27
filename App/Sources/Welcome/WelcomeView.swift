import SwiftUI
import MangaCore

/// The first-run welcome, shown instead of the tabs while the active
/// profile has nothing to read (`AppModel.showsWelcome`). It offers the Free
/// Library's collections with a few already ticked, a way to add a server,
/// and a way to restore a backup. As soon as a server is saved, a backup
/// brings something back, or "Start Reading" is pressed, Home takes over.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var catalog = FreeLibraryCatalog.bundled
    /// Nil until the person changes a tick; then their choice.
    @State private var picked: Set<String>?

    enum Route: Hashable { case addServer, backup }

    static let explanation = """
        Read from your own Kavita, Komga, Suwayomi or OPDS server, or start right away with the Free Library: \
        public-domain classics and the Pepper&Carrot webcomic, free to read with no setup.
        """

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Text(Self.explanation)
                        .accessibilityIdentifier("welcome.explanation")
                }

                Section {
                    ForEach(choices) { choice in
                        row(choice)
                    }
                } header: {
                    SettingsHeader(collectionsHeader)
                } footer: {
                    Text(selection.isEmpty
                         ? "Pick at least one collection, or add your own server below."
                         : "Change these any time in Settings → Free Library.")
                }

                Section {
                    Button {
                        model.finishWelcome(collections: selection, allCollections: Set(choices.map(\.id)))
                    } label: {
                        Label("Start Reading", systemImage: "book")
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("welcome.start")
                }

                Section(settingsHeader: "Other Ways to Start") {
                    NavigationLink(value: Route.addServer) {
                        Label("Add a Kavita, Komga, Suwayomi or OPDS Server", systemImage: "server.rack")
                    }
                    .accessibilityIdentifier("welcome.addServer")
                    NavigationLink(value: Route.backup) {
                        Label("Restore from a Backup", systemImage: "arrow.counterclockwise.icloud")
                    }
                    .accessibilityIdentifier("welcome.restore")
                }
            }
            .settingsPage("Welcome to Manga Reader") { WelcomeEmblem() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .addServer: ServerEditorView(editing: nil)
                case .backup:
                    #if os(tvOS)
                    WiFiBackupView()
                    #else
                    FilesBackupView()
                    #endif
                }
            }
        }
        .onChange(of: path.isEmpty) { _, isEmpty in model.isBusyInWelcome = !isEmpty }
        .onDisappear { model.isBusyInWelcome = false }
        .task {
            // UI tests stay on the bundled catalog, offline.
            guard !UITestingSeed.isUITesting else { return }
            catalog = await FreeLibraryStore.shared.catalog(transport: model.transport)
        }
    }

    private var choices: [Welcome.Choice] { Welcome.choices(from: catalog) }

    private var selection: Set<String> {
        picked ?? Welcome.initialSelection(model.state, profile: model.activeProfile.id, choices: choices)
    }

    private var collectionsHeader: String {
        model.state.profiles.count > 1
            ? "Free Library Collections for \(model.activeProfile.name)"
            : "Free Library Collections"
    }

    private func row(_ choice: Welcome.Choice) -> some View {
        let isOn = selection.contains(choice.id)
        return Button {
            var s = selection
            if isOn { s.remove(choice.id) } else { s.insert(choice.id) }
            picked = s
        } label: {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(choice.name)
                    if !choice.summary.isEmpty {
                        Text(choice.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(choice.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.m)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle") // option-chip-ok: full-width checklist row
                    .themedMark(isOn)
            }
            .padding(.vertical, Space.xs)
        }
        .accessibilityIdentifier("welcome.collection.\(choice.id)")
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// The welcome's hero art, drawn in code (no cover art from any real book):
/// three fanned pages in the accent color with a stack of books on the
/// front one.
private struct WelcomeEmblem: View {
    private let height = Size.heroSymbol * 0.75
    private var width: CGFloat { height * 0.7 }

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                let step = CGFloat(i - 1)
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Color.accentColor.opacity(0.35 + 0.3 * Double(i)))
                    .frame(width: width, height: height)
                    .overlay {
                        if i == 2 {
                            Image(systemName: "books.vertical.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: width * 0.55)
                                .foregroundStyle(.white)
                        }
                    }
                    .rotationEffect(.degrees(Double(step) * 12), anchor: .bottom)
                    .offset(x: step * width * 0.45)
            }
        }
        .frame(height: height)
    }
}
