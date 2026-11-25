import SwiftUI
import MangaCore

/// Add or edit a server, and the active profile's login, sync setting and
/// which libraries/categories to import from it. The checklist appears once
/// a connection test succeeds (and right away when editing).
struct ServerEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let editing: ServerConfig?
    @State private var draft = ServerDraft()
    @State private var loaded = false
    @State private var test: TestState = .idle
    @State private var confirmingRemove = false
    @State private var categories: CategoryLoad = .idle
    /// The id a new server gets, kept for the whole visit so connection
    /// tests and the save use the same one.
    @State private var newServerID = UUID()

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PhoneSetupView(context: PhoneSetupHTTP.Context(draft: draft, kindLocked: editing != nil),
                                   saveLabel: editing == nil ? "Add Server" : "Save",
                                   receive: receiveFromPhone)
                } label: {
                    Label("Set Up from Your Phone", systemImage: "qrcode")
                }
                .accessibilityIdentifier("serverEditor.phoneSetup")
            } footer: {
                Text("Scan a code with your phone and type the address and login there instead of with the remote.")
            }

            if editing == nil {
                Section(settingsHeader: "Server Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ServerKind.userAddable) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("serverEditor.kind")
                }
            }

            Section {
                TextField("Name (optional)", text: $draft.name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("serverEditor.name")
                    .settingsTextFieldRow()
                TextField(addressPrompt,
                          text: $draft.address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { draft.absorbOPDS() }
                    .accessibilityIdentifier("serverEditor.address")
                    .settingsTextFieldRow()
            } header: {
                SettingsHeader("\(draft.kind.displayName) Server")
            } footer: {
                if draft.kind == .kavita {
                    Text("Paste the OPDS URL from Kavita → User Settings → 3rd Party Clients. It fills in the API key for you.")
                }
            }

            Section {
                ForEach(Array(draft.alternateAddresses.indices), id: \.self) { index in
                    TextField("Address \(index + 2), e.g. https://manga.example.com", text: alternateBinding(index))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.altAddress.\(index)")
                        .settingsTextFieldRow()
                }
                if draft.canAddAlternateAddress {
                    Button {
                        draft.alternateAddresses.append("")
                    } label: {
                        Label("Add Another Address", systemImage: "plus")
                    }
                    .accessibilityIdentifier("serverEditor.addAddress")
                }
            } header: {
                SettingsHeader("Other Addresses")
            } footer: {
                Text("For when the first address doesn't answer, such as a remote or reverse-proxy address for when you're away from home. The app uses the first one that answers, in this order. Clear an address to remove it.")
            }

            Section {
                switch draft.kind {
                case .kavita:
                    SecureField("API key", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.apiKey")
                        .settingsTextFieldRow()
                case .komga:
                    TextField("API key (recommended)", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.apiKey")
                        .settingsTextFieldRow()
                    TextField("Email", text: $draft.username)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.username")
                        .settingsTextFieldRow()
                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("serverEditor.password")
                        .settingsTextFieldRow()
                case .suwayomi, .opds:
                    TextField("Username (optional)", text: $draft.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.username")
                        .settingsTextFieldRow()
                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("serverEditor.password")
                        .settingsTextFieldRow()
                case .freeLibrary:
                    EmptyView()
                }
            } header: {
                SettingsHeader("Login for \(model.activeProfile.name)")
            } footer: {
                Text(loginFooter)
            }

            if draft.kind.canSyncProgress {
                Section {
                    Toggle("Sync reading progress to this server", isOn: $draft.syncProgress)
                        .accessibilityIdentifier("serverEditor.sync")
                } footer: {
                    Text(syncFooter)
                }
            }

            if categories != .idle {
                Section {
                    CategoryChecklist(kind: draft.kind, load: $categories, retry: { loadCategories() })
                } header: {
                    SettingsHeader("\(draft.kind.categoryNoun) to Import")
                } footer: {
                    if let footer = CategoryChecklist.footer(kind: draft.kind, load: categories) { Text(footer) }
                }
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
                    .disabled(!draft.isValid || categories.selection?.canSave == false)
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
        .settingsPage(editing?.name ?? "Add Server", systemImage: "server.rack")
        .onAppear(perform: load)
        .onChange(of: draft.address) { _, _ in
            // A pasted OPDS URL (Continuity Keyboard) splits right away.
            if draft.kind == .kavita, KavitaOPDS.parse(draft.address) != nil { draft.absorbOPDS() }
            connectionChanged()
        }
        .onChange(of: draft.kind) { _, _ in connectionChanged() }
        .onChange(of: draft.alternateAddresses) { _, _ in connectionChanged() }
        .onChange(of: draft.apiKey) { _, _ in connectionChanged() }
        .onChange(of: draft.username) { _, _ in connectionChanged() }
        .onChange(of: draft.password) { _, _ in connectionChanged() }
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
        case .komga:
            return "Komga keeps progress per user, so this is normally on."
        case .opds:
            return "OPDS catalogs can't store reading progress, so it's kept on this Apple TV."
        case .suwayomi:
            let others = otherSyncingProfiles
            let base = "Suwayomi keeps one reading progress for the whole server. Turn this on for one profile; the others keep their progress on this Apple TV."
            guard draft.syncProgress, !others.isEmpty else { return base }
            return base + " Also syncing: " + others.map(\.name).joined(separator: ", ") + "."
        case .freeLibrary:
            return "The Free Library keeps progress on this Apple TV."
        }
    }

    private var addressPrompt: String {
        switch draft.kind {
        case .kavita: return "OPDS URL or address"
        case .komga: return "Address, e.g. komga.local:25600"
        case .suwayomi: return "Address, e.g. suwayomi.local:4567"
        case .opds: return "Catalog URL or address, e.g. books.local:8083/opds"
        case .freeLibrary: return ""
        }
    }

    private var loginFooter: String {
        switch draft.kind {
        case .kavita: return "Each profile can sign in as its own Kavita user."
        case .komga: return "Make an API key in Komga → Account Settings → API Keys, or use the email and password you sign in to Komga with. Each profile can use its own Komga user."
        case .suwayomi: return "Only needed if basic authentication is turned on in Suwayomi."
        case .opds: return "Only needed if the catalog asks for a login. Works with Calibre-Web, Ubooquity, Codex, Stump and other OPDS servers; only the host is needed for the usual catalog paths."
        case .freeLibrary: return "The Free Library needs no login."
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
            if draft.isValid { loadCategories() }
        }
    }

    /// A different address or login may see different libraries: hide the
    /// checklist until the next successful test. Ticks the user already
    /// made are kept if the same ids come back.
    private func connectionChanged() {
        test = .idle
        guard categoriesKey != connectionKey else { return }
        categoryTask?.cancel()
        if let selection = categories.selection { pendingSelection = .some(selection.storedValue) }
        categories = .idle
        categoriesKey = nil
    }

    @State private var categoryTask: Task<Void, Never>?
    /// The server and login the checklist was loaded for.
    @State private var categoriesKey: String?
    /// Ticks made before the address or login changed, applied when the
    /// checklist loads again. `.none` until then.
    @State private var pendingSelection: Set<String>??

    private var connectionKey: String {
        [draft.kind.rawValue, draft.resolvedURL?.absoluteString ?? "",
         draft.resolvedAlternateURLs.map(\.absoluteString).joined(separator: ","), draft.resolvedAPIKey,
         draft.username, draft.password].joined(separator: "|")
    }

    private func loadCategories() {
        guard let config = draft.config(id: serverID) else { return }
        let credential = draft.credential
        let saved: Set<String>?
        if let selection = categories.selection {
            saved = selection.storedValue
        } else if let pending = pendingSelection {
            saved = pending
        } else {
            saved = editing.flatMap { model.selectedCategories(for: $0) }
        }
        categoriesKey = connectionKey
        categories = .loading
        categoryTask?.cancel()
        categoryTask = Task {
            do {
                let available = try await model.availableCategories(config, credential: credential)
                guard !Task.isCancelled else { return }
                categories = .loaded(CategorySelection(available: available, saved: saved))
            } catch {
                guard !Task.isCancelled else { return }
                categories = .failed(ConnectionErrorText.message(for: error))
            }
        }
    }

    private func runTest() {
        guard let config = draft.config(id: serverID) else { return }
        let credential = draft.credential
        test = .running
        Task {
            do {
                let message = try await model.testConnection(config, credential: credential)
                test = .success(message)
                loadCategories()
            } catch {
                test = .failure(ConnectionErrorText.message(for: error))
            }
        }
    }

    private var serverID: UUID { editing?.id ?? newServerID }

    /// One "other address" field. Guards the index so a field that's being
    /// removed never reads past the end.
    private func alternateBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < draft.alternateAddresses.count ? draft.alternateAddresses[index] : "" },
            set: { if index < draft.alternateAddresses.count { draft.alternateAddresses[index] = $0 } })
    }

    /// The phone sent the form: fill it in here and test it, so the user
    /// only has to check it and save.
    private func receiveFromPhone(_ submission: PhoneSetupHTTP.Submission) {
        submission.apply(to: &draft, kindLocked: editing != nil)
        Task {
            // After the field changes above have reset the last test.
            try? await Task.sleep(for: .milliseconds(400))
            if draft.isValid { runTest() }
        }
    }

    private func save() {
        guard let config = draft.config(id: serverID) else { return }
        // Without a loaded checklist, keep what was saved (all, for a new server).
        let selected = categories.selection.map(\.storedValue)
            ?? editing.flatMap { model.selectedCategories(for: $0) }
        model.saveServer(config, credential: draft.credential)
        model.setServerSettings(ProfileServerSettings(syncProgressToServer: draft.kind.canSyncProgress && draft.syncProgress,
                                                      selectedCategoryIDs: selected), for: config)
        dismiss()
    }
}
