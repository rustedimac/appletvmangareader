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
                                      credential: model.credential(for: server))
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
            .navigationTitle("Settings")
        }
    }
}

private struct ServerRow: View {
    let server: ServerConfig
    let syncs: Bool
    let credential: ServerCredential?

    var body: some View {
        HStack(spacing: 30) {
            Image(systemName: server.kind == .kavita ? "books.vertical.fill" : "square.stack.3d.up.fill")
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                Text("\(server.kind.displayName) · \(server.baseURL.host ?? server.baseURL.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if server.kind == .kavita && credential == nil {
                    Text("Not signed in").font(.caption).foregroundStyle(.orange)
                } else if let user = credential?.username {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
                if !syncs {
                    Text("Progress saved locally").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.serverStatus.\(server.name)")
        }
    }
}
