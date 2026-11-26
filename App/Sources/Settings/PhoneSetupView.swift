import SwiftUI
import MangaCore

/// "Set Up from Your Phone": serves a small form on the local network while
/// this screen is open and shows its address as a QR code. When the phone
/// sends the form, the server editor is filled in and this screen closes.
/// See `PhoneSetupHTTP`.
struct PhoneSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let context: PhoneSetupHTTP.Context
    /// The editor's save button, named in the phone's confirmation.
    let saveLabel: String
    let receive: @MainActor (PhoneSetupHTTP.Submission) -> Void

    @State private var server: PhoneSetupServer?
    @State private var address: String?
    @State private var problem: String?

    var body: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            Group {
                if let address, let qr = WiFiBackupView.qrImage(address) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 360)
                        .accessibilityLabel("QR code for \(address)")
                        .accessibilityIdentifier("phoneSetup.qr")
                } else {
                    RoundedRectangle(cornerRadius: Radius.card).fill(.quaternary).frame(width: 360, height: 360)
                }
            }

            VStack(alignment: .leading, spacing: Space.m) {
                Text("Set Up from Your Phone").font(.title3)
                if let address {
                    Text("On a phone or computer on the same network, scan the code or open:")
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.headline.monospaced())
                        .accessibilityIdentifier("phoneSetup.address")
                    Text("Type the server's address and login there and press Send. They fill in the form on this Apple TV, which tests the connection; then check it and press \(saveLabel). Nothing leaves your network.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let problem {
                    Text(problem).foregroundStyle(.secondary).accessibilityIdentifier("phoneSetup.problem")
                } else {
                    ProgressView()
                }
                Text("The page stops working when you leave this screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: Size.formColumn, alignment: .leading)
            .focusable()
        }
        .padding(.top, Space.l)
        .task { await start() }
        .onDisappear {
            server?.stop()
            server = nil
        }
    }

    private func start() async {
        guard server == nil else { return }
        let receive = self.receive
        let dismiss = self.dismiss
        let saveLabel = self.saveLabel
        let server = PhoneSetupServer(context: context) { submission in
            await MainActor.run { receive(submission) }
            Task { @MainActor in
                // Leave the phone's request time to finish before the
                // listener goes away with this screen.
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            }
            return .success("Sent. Check the form on the Apple TV and press \(saveLabel).")
        }
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
            problem = "Couldn't start the setup page: \(ConnectionErrorText.message(for: error))"
        }
    }
}
