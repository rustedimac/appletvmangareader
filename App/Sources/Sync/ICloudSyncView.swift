import SwiftUI
import MangaCore

/// Settings → iCloud Sync and Backup.
struct ICloudSyncView: View {
    @Environment(CloudSyncController.self) private var sync

    private var isOn: Binding<Bool> {
        Binding(get: { sync.isAvailableInBuild && sync.isEnabled },
                set: { sync.isEnabled = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: isOn)
                    .disabled(!sync.isAvailableInBuild)
                    .accessibilityIdentifier("icloud.toggle")
                LabeledContent("Status", value: statusText)
                    .accessibilityIdentifier("icloud.status")
                if let last = sync.lastSyncAt {
                    LabeledContent("Last synced", value: last.formatted(date: .abbreviated, time: .shortened))
                        .accessibilityIdentifier("icloud.lastSync")
                }
                if sync.isAvailableInBuild && sync.isEnabled {
                    Button("Sync Now") { sync.syncNow() }
                        .disabled(sync.phase == .syncing)
                        .accessibilityIdentifier("icloud.syncNow")
                }
            } header: {
                SettingsHeader("iCloud")
            } footer: {
                Text(explanation)
                    .accessibilityIdentifier("icloud.explanation")
            }

            Section {
                Text("Profiles, server addresses, favorites, reading progress, library choices and reader settings.")
                Text(Platform.isTV ? "Logins and API keys stay on this Apple TV. Enter them once on each device."
                                   : "Logins and API keys stay on this device. Enter them once on each device.")
                    .foregroundStyle(.secondary)
            } header: {
                SettingsHeader("What Syncs")
            }

            Section {
                NavigationLink {
                    #if os(tvOS)
                    WiFiBackupView()
                    #else
                    FilesBackupView()
                    #endif
                } label: {
                    #if os(tvOS)
                    Label("Back Up and Restore over Wi‑Fi", systemImage: "arrow.up.arrow.down.circle")
                    #else
                    Label("Back Up and Restore", systemImage: "arrow.up.arrow.down.circle")
                    #endif
                }
                .accessibilityIdentifier("icloud.backup")
            } header: {
                SettingsHeader("Backup")
            } footer: {
                #if os(tvOS)
                Text("Works without iCloud. Download a backup file from a phone or computer on the same network, or restore one.")
                #else
                Text("Works without iCloud. Save a backup file to Files, or restore one, including backups from the Apple TV.")
                #endif
            }
        }
        .settingsPage("iCloud Sync and Backup", systemImage: "icloud")
    }

    private var statusText: String {
        switch sync.phase {
        case .notConfigured: return "Not set up in this build"
        case .off: return "Off"
        case .checking: return "Checking…"
        case .noAccount: return "No iCloud account"
        case .restricted: return "Restricted"
        case .syncing: return "Syncing…"
        case .upToDate: return "Up to date"
        case .waiting: return "Waiting"
        case .failed: return "Couldn't sync"
        }
    }

    private var explanation: String {
        switch sync.phase {
        case .notConfigured:
            return "This copy of the app isn't signed with iCloud turned on, so sync is off. It needs an Apple Developer Program membership; until then, use Wi‑Fi backup below."
        case .noAccount:
            return Platform.isTV ? "Sign in to iCloud in the Apple TV's Settings app under Users and Accounts." : "Sign in to iCloud in the Settings app."
        case .restricted:
            return "iCloud is restricted on this \(Platform.deviceName), for example by Screen Time."
        case .waiting(let message), .failed(let message):
            return message
        default:
            return "Keeps everything below the same on every device signed in to your iCloud account.\(Platform.isTV ? " Each Apple TV user syncs with their own iCloud account." : "")"
        }
    }
}
