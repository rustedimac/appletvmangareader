import SwiftUI
import UniformTypeIdentifiers
import MangaCore

/// iPhone and iPad backup (docs/IOS.md §1): export a backup file to Files
/// (or AirDrop, Mail…) and import one. Same `MangaBackup` JSON as the Apple
/// TV's Wi-Fi backup page, so a backup made on either restores on the other.
struct FilesBackupView: View {
    @Environment(AppModel.self) private var model
    @State private var exporting: BackupDocument?
    @State private var importing = false
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Button {
                    exporting = BackupDocument(data: model.exportBackup())
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("backup.export")
                Button {
                    importing = true
                } label: {
                    Label("Restore from a Backup File", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("backup.import")
            } footer: {
                Text("Saves a file with your profiles, servers, favorites, reading progress, bookmarks and settings. Logins and API keys aren't included. Restoring merges: nothing is deleted, the furthest reading position wins, and settings take the backup's values. Backups from the Apple TV app work here too.")
            }
            if let result {
                Section {
                    Label(result, systemImage: "checkmark.circle")
                        .accessibilityIdentifier("backup.restored")
                }
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backup.problem")
                }
            }
        }
        .navigationTitle("Back Up and Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .json,
                      defaultFilename: "Manga Reader Backup \(Date().formatted(.iso8601.year().month().day()))") { outcome in
            if case .failure(let error) = outcome { problem = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { outcome in
            restore(outcome)
        }
    }

    private func restore(_ outcome: Result<URL, Error>) {
        problem = nil
        result = nil
        do {
            let url = try outcome.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            result = "Restored: " + (try model.restoreBackup(Data(contentsOf: url)))
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The backup JSON as a document for `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
