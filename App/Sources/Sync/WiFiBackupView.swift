import SwiftUI
import CoreImage.CIFilterBuiltins
import Observation
import MangaCore

/// Serves the backup page on the local network while this screen is open.
struct WiFiBackupView: View {
    @Environment(AppModel.self) private var model
    @State private var server: BackupWebServer?
    @State private var address: String?
    @State private var problem: String?
    @State private var restores = RestoreLog()

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            Group {
                if let address, let qr = Self.qrImage(address) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 360)
                        .accessibilityLabel("QR code for \(address)")
                        .accessibilityIdentifier("backup.qr")
                } else {
                    RoundedRectangle(cornerRadius: Radius.card).fill(.quaternary).frame(width: 360, height: 360)
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                Text("Back Up and Restore over Wi‑Fi").font(.title3)
                if let address {
                    Text("On a phone or computer on the same network, scan the code or open:")
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.headline.monospaced())
                        .accessibilityIdentifier("backup.address")
                    Text("You can download a backup file there, or upload one to restore. Restoring merges: nothing is deleted, the furthest reading position wins, and settings take the backup's values. Logins and API keys aren't included.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let problem {
                    Text(problem).foregroundStyle(.secondary).accessibilityIdentifier("backup.problem")
                } else {
                    ProgressView()
                }
                if let lastRestore = restores.last {
                    Label(lastRestore, systemImage: "checkmark.circle")
                        .accessibilityIdentifier("backup.restored")
                }
                Text("The page stops working when you leave this screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .focusable()
        }
        .padding(.top, 40)
        .task { await start() }
        .onDisappear {
            server?.stop()
            server = nil
        }
    }

    private func start() async {
        guard server == nil else { return }
        let model = self.model
        let restores = self.restores
        let server = BackupWebServer(
            export: { await MainActor.run { model.exportBackup() } },
            restore: { data in
                await MainActor.run {
                    let result = Result { try model.restoreBackup(data) }
                    restores.last = (try? result.get()).map { "Restored: \($0)" } ?? restores.last
                    return result
                }
            })
        do {
            let port = try await server.start()
            self.server = server
            guard let ip = LocalNetworkAddress.ipv4().first else {
                problem = "This Apple TV isn't on a network right now."
                server.stop()
                return
            }
            address = "http://\(ip):\(port)/\(server.code)/"
        } catch {
            problem = "Couldn't start the backup page: \(error.localizedDescription)"
        }
    }

    @MainActor @Observable
    final class RestoreLog {
        var last: String?
    }

    static func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
