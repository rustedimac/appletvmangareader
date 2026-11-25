import SwiftUI
import MangaCore

/// Add or edit a server, and the active profile's login, sync setting and
/// which libraries/categories to import from it. The checklist appears once
/// a connection test succeeds (and right away when editing).
struct ServerEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let editing: ServerConfig?
    @State private var draft = ServerDraft(kavitaMethod: .password)
    @State private var loaded = false
    @State private var test: TestState = .idle
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingRemove = false
    @State private var categories: CategoryLoad = .idle

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        Form {
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
                    // Tidy the address only when typing is done, never per keystroke.
                    .onSubmit { draft.absorbOPDS() }
                    .accessibilityIdentifier("serverEditor.address")
                    .settingsTextFieldRow()
            } header: {
                SettingsHeader("\(draft.kind.displayName) Server")
            } footer: {
                Text(ServerDraft.addressHelp(for: draft.kind))
                    .accessibilityIdentifier("serverEditor.addressHelp")
            }

            Section {
                switch draft.kind {
                case .kavita:
<<<<<<< HEAD
                    SecureField("API key", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .onSubmit { draft.absorbOPDS() }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverEditor.apiKey")
                        .settingsTextFieldRow()
=======
                    Picker("Sign in with", selection: $draft.kavitaMethod) {
                        ForEach(ServerDraft.KavitaSignInMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("serverEditor.kavitaMethod")
                    if draft.kavitaMethod == .password {
                        TextField("Kavita username", text: $draft.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("serverEditor.username")
                            .settingsTextFieldRow()
                        SecureField(draft.existing?.username == nil ? "Password" : "Password (to sign in again)",
                                    text: $draft.password)
                            .textContentType(.password)
                            .accessibilityIdentifier("serverEditor.password")
                            .settingsTextFieldRow()
                    } else {
                        SecureField("API key", text: $draft.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("serverEditor.apiKey")
                            .settingsTextFieldRow()
                    }
>>>>>>> origin/main
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
                    .accessibilityIdentifier("serverEditor.loginFooter")
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
                // Enabled once there's an address, so focus can always move
                // down to Save and Remove; a missing login shows its message.
                .disabled(draft.resolvedURL == nil || test == .running || saving)
                .accessibilityIdentifier("serverEditor.test")

                Button {
                    save()
                } label: {
                    HStack {
                        Text(editing == nil ? "Add Server" : "Save")
                        if saving { Spacer(); ProgressView() }
                    }
                }
                .disabled(!draft.isValid || saving || categories.selection?.canSave == false)
                .accessibilityIdentifier("serverEditor.save")

                if editing != nil {
                    Button("Remove Server", role: .destructive) { confirmingRemove = true }
                        .accessibilityIdentifier("serverEditor.remove")
                }
            } footer: {
                if let message = draft.validationMessage, !draft.address.isEmpty {
                    Text(message)
                } else if let saveError {
                    Text(saveError).foregroundStyle(.red)
                        .accessibilityIdentifier("serverEditor.error")
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
            // Never rewrite the field here: this runs on every keystroke, and
            // splitting an OPDS URL mid-typing ate "/api/opds/" (John, 2026-11-25).
            // `resolvedURL`/`resolvedAPIKey` read a full OPDS URL as it is.
            connectionChanged()
        }
        .onChange(of: draft.kind) { _, _ in connectionChanged() }
        .onChange(of: draft.apiKey) { _, _ in connectionChanged() }
        .onChange(of: draft.username) { _, _ in connectionChanged() }
        .onChange(of: draft.password) { _, _ in connectionChanged() }
        .onChange(of: draft.kavitaMethod) { _, _ in connectionChanged() }
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

    private var loginFooter: String {
        switch draft.kind {
        case .kavita:
            if let user = draft.existing?.username, draft.keepsExistingLogin || draft.kavitaMethod == .apiKey {
                return "Signed in as \(user). Each profile can sign in as its own Kavita user."
            }
            return draft.kavitaMethod == .password
                ? "Sign in as an existing Kavita user. Progress, read state and Continue Reading follow that user. The password isn't saved; the app keeps an \"\(KavitaClient.authKeyName)\" auth key, which you can revoke in Kavita."
                : "Each profile can sign in as its own Kavita user."
        case .komga:
            return "Make an API key in Komga → Account Settings → API Keys, or use the email and password you sign in to Komga with. Each profile can use its own Komga user."
        case .suwayomi:
            return "Only needed if the server asks for a login."
        case .opds:
            return "Only needed if the catalog asks for a login. Works with Calibre-Web, Ubooquity, Codex, Stump and other OPDS servers; only the host is needed for the usual catalog paths."
        case .freeLibrary:
            return "The Free Library needs no login."
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
        case .kavita: return "Address, e.g. kavita.local:5000"
        case .komga: return "Address, e.g. komga.local:25600"
        case .suwayomi: return "Address, e.g. suwayomi.local:4567"
        case .opds: return "Catalog URL or address, e.g. books.local:8083/opds"
        case .freeLibrary: return ""
        }
    }

    private var otherSyncingProfiles: [Profile] {
        guard let editing else { return [] }
        return model.state.profilesSyncing(to: editing.id).filter { $0.id != model.activeProfile.id }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if editing == nil, let prefill = UITestingSeed.serverEditorPrefill {
            // Stands in for a paste, which the simulator can't do.
            draft.kind = prefill.kind
            draft.address = prefill.address
            draft.apiKey = prefill.apiKey
        }
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
<<<<<<< HEAD
        // Tidying the fields (absorbOPDS) changes the text but not where it
        // connects, so it keeps the test result.
        if connectionKey != testedKey { test = .idle }
=======
        test = .idle
        saveError = nil
        resolvedCredential = nil
>>>>>>> origin/main
        guard categoriesKey != connectionKey else { return }
        categoryTask?.cancel()
        if let selection = categories.selection { pendingSelection = .some(selection.storedValue) }
        categories = .idle
        categoriesKey = nil
    }

    /// The login a successful test signed in with (for a Kavita password,
    /// the auth key it got), reused by the checklist and Save.
    @State private var resolvedCredential: ServerCredential?
    @State private var categoryTask: Task<Void, Never>?
    /// The server and login the last Test Connection ran against.
    @State private var testedKey: String?
    /// The server and login the checklist was loaded for.
    @State private var categoriesKey: String?
    /// Ticks made before the address or login changed, applied when the
    /// checklist loads again. `.none` until then.
    @State private var pendingSelection: Set<String>??

    private var connectionKey: String {
        [draft.kind.rawValue, draft.resolvedURL?.absoluteString ?? "", draft.resolvedAPIKey,
         draft.username, draft.password, draft.kavitaMethod.rawValue].joined(separator: "|")
    }

    private func loadCategories() {
        guard let config = draft.config(id: editing?.id ?? UUID()) else { return }
        // A Kavita password login has nothing to list with until a test signs in.
        if draft.needsKavitaSignIn && resolvedCredential == nil { return }
        let credential = resolvedCredential ?? draft.credential
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
                categories = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func runTest() {
        if let message = draft.validationMessage {
            test = .failure(message)
            return
        }
        guard let config = draft.config(id: editing?.id ?? UUID()) else { return }
<<<<<<< HEAD
        let credential = draft.credential
        draft.absorbOPDS()
        testedKey = connectionKey
=======
        let draft = self.draft
>>>>>>> origin/main
        test = .running
        Task {
            do {
                let credential = try await model.resolveCredential(draft, for: config)
                var message = try await model.testConnection(config, credential: credential)
                if let user = await model.suwayomiUser(config, credential: credential) {
                    message += ". Signed in as \(user), with progress of your own."
                }
                guard draft == self.draft else { return } // Edited meanwhile.
                resolvedCredential = credential
                test = .success(message)
                loadCategories()
            } catch {
                test = .failure(ConnectionErrorMessage.describe(error, kind: config.kind, url: config.baseURL))
            }
        }
    }

    private func save() {
        draft.absorbOPDS()
        guard let config = draft.config(id: editing?.id ?? UUID()) else { return }
        let draft = self.draft
        // Without a loaded checklist, keep what was saved (all, for a new server).
        let selected = categories.selection.map(\.storedValue)
            ?? editing.flatMap { model.selectedCategories(for: $0) }
        saving = true
        saveError = nil
        Task {
            defer { saving = false }
            do {
                // Reuse what a test just signed in with, rather than signing in twice.
                let credential: ServerCredential?
                if draft == self.draft, let tested = resolvedCredential {
                    credential = tested
                } else {
                    credential = try await model.resolveCredential(draft, for: config)
                }
                var sync = draft.syncProgress
                // A Suwayomi server with user accounts keeps this login's
                // progress apart from everyone else's, so it can sync.
                if credential != draft.existing, await model.suwayomiUser(config, credential: credential) != nil {
                    sync = true
                }
                model.saveServer(config, credential: credential)
                model.setServerSettings(ProfileServerSettings(syncProgressToServer: draft.kind.canSyncProgress && sync,
                                                              selectedCategoryIDs: selected), for: config)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
