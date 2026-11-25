import SwiftUI
import MangaCore

/// Settings tab: who's reading, their servers, and their reader defaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                if model.perAppleTVUser {
                    AppleTVUserSection()
                }

                Section(settingsHeader: model.perAppleTVUser ? "Reading" : "Profile") {
                    if showsInAppProfiles {
                        Button {
                            model.isPickingProfile = true
                        } label: {
                            HStack(spacing: Space.m) {
                                ProfileAvatarView(profile: model.activeProfile, size: Size.avatarRow)
                                VStack(alignment: .leading, spacing: Space.xxs) {
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
                    }

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
                            if server.kind == .freeLibrary {
                                FreeLibrarySettingsView(server: server)
                            } else {
                                ServerEditorView(editing: server)
                            }
                        } label: {
                            ServerRow(server: server, syncs: model.syncsProgress(to: server.id),
                                      credential: model.credential(for: server),
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
                    if !model.state.hasFreeLibrary {
                        Button {
                            model.restoreFreeLibrary()
                        } label: {
                            Label("Add the Free Library", systemImage: FreeLibrarySymbol.name)
                        }
                        .accessibilityIdentifier("settings.addFreeLibrary")
                    }
                } header: {
                    SettingsHeader("Servers")
                } footer: {
                    if model.servers.isEmpty {
                        Text("Add a Kavita or Suwayomi server to start reading.")
                    } else {
                        Text("Logins are saved separately for each profile.")
                    }
                }

                Section(settingsHeader: "Sync and Backup") {
                    NavigationLink {
                        ICloudSyncView()
                    } label: {
                        Label("iCloud Sync and Backup", systemImage: "icloud")
                    }
                    .accessibilityIdentifier("settings.icloud")
                }
            }
            .settingsPage("Settings", systemImage: "gearshape")
        }
    }

    /// In-app profiles are the fallback when there are no Apple TV users.
    /// With Apple TV users they only show for older state that already has
    /// several profiles.
    private var showsInAppProfiles: Bool {
        !model.perAppleTVUser || model.state.profiles.count > 1
    }
}

private struct ServerRow: View {
    private var subtitle: String {
        if server.kind == .freeLibrary { return "Public-domain classics and Pepper&Carrot · No setup" }
        var parts = [server.kind.displayName, server.baseURL.host ?? server.baseURL.absoluteString]
        if let pickedCount {
            let noun = pickedCount == 1 ? server.kind.singularCategoryNoun
                                        : server.kind.categoryNoun.lowercased()
            parts.append("\(pickedCount) \(noun) picked")
        }
        return parts.joined(separator: " · ")
    }

    let server: ServerConfig
    let syncs: Bool
    let credential: ServerCredential?
    /// How many libraries/categories are imported, or nil for all.
    let pickedCount: Int?

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: server.kind.symbolName)
                .frame(width: Size.avatarRow)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if server.kind.requiresLogin && credential == nil {
                    Text(server.kind == .kavita ? "Not signed in" : "No login").font(.caption).foregroundStyle(.orange)
                } else if let user = credential?.username {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
                if !syncs && server.kind != .freeLibrary {
                    Text("Progress saved locally").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.serverStatus.\(server.name)")
        }
    }
}
