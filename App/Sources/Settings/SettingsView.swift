import SwiftUI
import MangaCore

/// Settings tab: who's reading, their servers, and their reader defaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    Button {
                        model.isPickingProfile = true
                    } label: {
                        HStack(spacing: 30) {
                            ProfileAvatarView(profile: model.activeProfile, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.activeProfile.name)
                                Text("Switch Profile").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.switchProfile")

                    NavigationLink {
                        ProfilesListView()
                    } label: {
                        Label("Manage Profiles", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("settings.manageProfiles")

                    NavigationLink {
                        ReaderDefaultsView()
                    } label: {
                        Label("Default Reader Settings", systemImage: "book")
                    }
                    .accessibilityIdentifier("settings.readerDefaults")
                }

                Section {
                    ForEach(model.servers) { server in
                        NavigationLink {
                            ServerEditorView(editing: server)
                        } label: {
                            ServerRow(server: server, syncs: model.syncsProgress(to: server.id),
                                      hasLogin: model.credential(for: server) != nil,
                                      pickedCount: model.selectedCategories(for: server)?.count)
                        }
                        .accessibilityIdentifier("settings.server.\(server.name)")
                    }
                    NavigationLink {
                        ServerEditorView(editing: nil)
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                    .accessibilityIdentifier("settings.addServer")
                } header: {
                    Text("Servers")
                } footer: {
                    if model.servers.isEmpty {
                        Text("Add a Kavita or Suwayomi server to start reading.")
                    } else {
                        Text("Logins are saved separately for each profile.")
                    }
                }
            }
            .settingsPage(systemImage: "gearshape")
            .navigationTitle("Settings")
        }
    }
}

private struct ServerRow: View {
    private var subtitle: String {
        var parts = [server.kind.displayName, server.baseURL.host ?? server.baseURL.absoluteString]
        if let pickedCount {
            let noun = pickedCount == 1 ? (server.kind == .kavita ? "library" : "category")
                                        : server.kind.categoryNoun.lowercased()
            parts.append("\(pickedCount) \(noun) picked")
        }
        return parts.joined(separator: " · ")
    }

    let server: ServerConfig
    let syncs: Bool
    let hasLogin: Bool
    /// How many libraries/categories are imported, or nil for all.
    let pickedCount: Int?

    var body: some View {
        HStack(spacing: 30) {
            Image(systemName: server.kind == .kavita ? "books.vertical.fill" : "square.stack.3d.up.fill")
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if server.kind == .kavita && !hasLogin {
                Text("No API key").font(.caption).foregroundStyle(.orange)
            } else if !syncs {
                Text("Progress saved locally").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
