import SwiftUI
import MangaCore

/// Add or edit a server, and the active profile's login and sync setting
/// for it.
struct ServerEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let editing: ServerConfig?
    @State private var draft = ServerDraft()
    @State private var loaded = false
    @State private var test: TestState = .idle
    @State private var confirmingRemove = false

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        Form {
            if editing == nil {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ServerKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("serverEditor.kind")
                }
            }

            Section {
                TextField("Name (optional)", text: $draft.name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("serverEditor.name")
                TextField(draft.kind == .kavita ? "OPDS URL or address" : "Address, e.g. suwayomi.local:4567",
                          text: $draft.address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { draft.absorbOPDS() }
                    .accessibilityIdentifier("serverEditor.address")
            } header: {
                Text("\(draft.kind.displayName) Server")
            } footer: {
                if draft.kind == .kavita {
                    Text("Paste the OPDS URL from Kavita → User Settings → 3rd Party Clients. It fills in the API key for you.")
                }
            }

            Section {
                switch draft.kind {
                case .kavita:
                    TextField("API key", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.apiKey")
                case .suwayomi:
                    TextField("Username (optional)", text: $draft.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.username")
                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("serverEditor.password")
                }
            } header: {
                Text("Login for \(model.activeProfile.name)")
            } footer: {
                Text(draft.kind == .kavita
                     ? "Each profile can sign in as its own Kavita user."
                     : "Only needed if basic authentication is turned on in Suwayomi.")
            }

            Section {
                Toggle("Sync reading progress to this server", isOn: $draft.syncProgress)
                    .accessibilityIdentifier("serverEditor.sync")
            } footer: {
                Text(syncFooter)
            }

            Section {
                Button {
                    runTest()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        testStatus
                    }
                }
                .disabled(!draft.isValid || test == .running)
                .accessibilityIdentifier("serverEditor.test")

                Button(editing == nil ? "Add Server" : "Save") { save() }
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("serverEditor.save")

                if editing != nil {
                    Button("Remove Server", role: .destructive) { confirmingRemove = true }
                        .accessibilityIdentifier("serverEditor.remove")
                }
            } footer: {
                if let message = draft.validationMessage, !draft.address.isEmpty {
                    Text(message)
                } else if case .failure(let message) = test {
                    Text(message).foregroundStyle(.red)
                } else if case .success(let message) = test {
                    Text(message)
                }
            }
        }
        .navigationTitle(editing?.name ?? "Add Server")
        .onAppear(perform: load)
        .onChange(of: draft.address) { _, _ in
            // A pasted OPDS URL (Continuity Keyboard) splits right away.
            if draft.kind == .kavita, KavitaOPDS.parse(draft.address) != nil { draft.absorbOPDS() }
            test = .idle
        }
        .onChange(of: draft.kind) { _, _ in test = .idle }
        .onChange(of: draft.apiKey) { _, _ in test = .idle }
        .onChange(of: draft.username) { _, _ in test = .idle }
        .onChange(of: draft.password) { _, _ in test = .idle }
        .confirmationDialog("Remove \(editing?.name ?? "server")?", isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let editing { model.removeServer(editing) }
                dismiss()
            }
            .accessibilityIdentifier("serverEditor.confirmRemove")
        } message: {
            Text("Every profile's favorites, local progress and logins for this server are removed. Nothing on the server changes.")
        }
    }

    @ViewBuilder private var testStatus: some View {
        switch test {
        case .idle: EmptyView()
        case .running: ProgressView()
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var syncFooter: String {
        switch draft.kind {
        case .kavita:
            return "Kavita keeps progress per user, so this is normally on."
        case .suwayomi:
            let others = otherSyncingProfiles
            let base = "Suwayomi keeps one reading progress for the whole server. Turn this on for one profile; the others keep their progress on this Apple TV."
            guard draft.syncProgress, !others.isEmpty else { return base }
            return base + " Also syncing: " + others.map(\.name).joined(separator: ", ") + "."
        }
    }

    private var otherSyncingProfiles: [Profile] {
        guard let editing else { return [] }
        return model.state.profilesSyncing(to: editing.id).filter { $0.id != model.activeProfile.id }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            draft = ServerDraft(editing: editing, credential: model.credential(for: editing),
                                syncProgress: model.syncsProgress(to: editing.id))
        }
    }

    private func runTest() {
        guard let config = draft.config(id: editing?.id ?? UUID()) else { return }
        let credential = draft.credential
        test = .running
        Task {
            do {
                let message = try await model.testConnection(config, credential: credential)
                test = .success(message)
            } catch {
                test = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let config = draft.config(id: editing?.id ?? UUID()) else { return }
        model.saveServer(config, credential: draft.credential)
        model.setServerSettings(ProfileServerSettings(syncProgressToServer: draft.syncProgress), for: config)
        dismiss()
    }
}
