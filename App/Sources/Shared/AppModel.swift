import Foundation
import Observation
import MangaCore

/// The app-wide model. Owns persisted state, secrets and server clients.
/// Every screen reads it from the SwiftUI environment:
/// `@Environment(AppModel.self) private var model`.
@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    @ObservationIgnored let stateStore: StateStore
    @ObservationIgnored let secrets: SecretStore
    /// Profile PIN hashes (Keychain in the app, in memory for UI tests).
    @ObservationIgnored let pins: PINStore
    /// Which PIN-protected profiles are unlocked this session.
    private(set) var locks = ProfileLocks()
    /// Bumped whenever a PIN is set or removed. The Keychain isn't
    /// observable, so views that read `hasPIN` depend on this instead.
    private(set) var pinRevision = 0
    /// For each server, the series the active profile's content filter
    /// hides there. Used for lists built from local data (Favorites, Top
    /// Shelf). A server missing here hides all of its favorites while a
    /// filter is on. Refreshed by `refreshHiddenSeries()`.
    private(set) var hiddenSeries: [UUID: Set<String>] = [:]
    @ObservationIgnored let transport: HTTPTransport
    @ObservationIgnored private var clientCache: [String: MangaServer] = [:]
    /// True while the "Who's reading?" picker is showing. Set at launch when
    /// there's more than one profile, and by "Switch Profile" in Settings.
    var isPickingProfile = false
    /// True while the first-run welcome has a screen pushed (the server
    /// editor or the backup page), so it stays up until the person comes
    /// back from that screen even if a saved server or a restore means
    /// Home has something now.
    var isBusyInWelcome = false
    /// Builds server clients, limited to a set of library/category ids (nil
    /// for all). UI tests swap in `SampleLibraryServer` (see
    /// `AppModel+Demo.swift`).
    /// Called after every saved change; iCloud sync listens here.
    @ObservationIgnored var onStateChange: (@MainActor () -> Void)?
    @ObservationIgnored var makeClient: (ServerConfig, ServerCredential?, Set<String>?, HTTPTransport) -> MangaServer = {
        MangaServerFactory.make(config: $0, credential: $1, categoryScope: $2, transport: $3)
    }
    /// Signs in to Kavita with a username and password and returns the
    /// login to keep (an auth key, never the password). UI tests swap in a
    /// fake (see `AppModel+Demo.swift`).
    @ObservationIgnored var kavitaSignIn: (ServerConfig, String, String, HTTPTransport) async throws -> ServerCredential = {
        // Through the failover, so sign-in works from whichever address answers.
        try await KavitaClient.signIn(baseURL: $0.baseURL, username: $1, password: $2,
                                      transport: $0.hasAlternateAddresses ? FailoverTransport(inner: $3, config: $0) : $3)
    }

    /// The app runs as the current Apple TV user, so `state` belongs to that
    /// user alone. See `AppleTVUsers/AppleTVUsers.swift`.
    @ObservationIgnored let perAppleTVUser: Bool
    /// Servers shared by every Apple TV user. Nil unless `perAppleTVUser`.
    @ObservationIgnored let sharedServers: SharedServerStore?
    /// Called after every saved change (Top Shelf refresh, shared servers).
    @ObservationIgnored var stateObservers: [(_ old: AppState, _ new: AppState) -> Void] = []

    /// Set while a guest is reading (see `AppModel+Guest.swift`). `state`
    /// is then the guest's in-memory state and `ownerState` holds the
    /// saved one, untouched, until the session ends.
    private(set) var guestSession: GuestSession?
    @ObservationIgnored var ownerState: AppState?
    /// A guest's book positions, in memory only.
    @ObservationIgnored var guestBookPositions = BookPositionStore(backing: InMemoryKeyValueStore())

    init(stateStore: StateStore, secrets: SecretStore, pins: PINStore = InMemoryPINStore(),
         transport: HTTPTransport = URLSessionTransport(),
         identity: DeviceUserIdentity = SingleUserDevice(), sharedServers: SharedServerStore? = nil) {
        self.stateStore = stateStore
        self.pins = pins
        let perAppleTVUser = identity.separatesAppDataPerUser
        self.perAppleTVUser = perAppleTVUser
        self.sharedServers = perAppleTVUser ? sharedServers : nil
        if perAppleTVUser, let sharedServers {
            self.secrets = SharedFallbackSecretStore(local: secrets, shared: sharedServers)
        } else {
            self.secrets = secrets
        }
        self.transport = transport
        self.state = stateStore.load()
        let launch = ProfileLaunch.decide(state, perSystemUser: perAppleTVUser)
        if let id = launch.profileID, id != state.activeProfileID { state.setActiveProfile(id) }
        self.isPickingProfile = launch.showsPicker
        adoptSharedServers()
        // A profile that asks for its PIN never opens straight away.
        if needsPINToOpen(activeProfile.id) { isPickingProfile = true }
    }

    static func live() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let store = StateStore(backing: InMemoryKeyValueStore())
            ServerAddressRouter.shared.reset(store: InMemoryKeyValueStore())
            let pins = InMemoryPINStore()
            if let seeded = UITestingSeed.state() { store.save(seeded) }
            UITestingSeed.seedPINs(store.load(), into: pins)
            let model = AppModel(stateStore: store, secrets: InMemorySecretStore(), pins: pins,
                                 identity: FixedDeviceUserIdentity(separatesAppDataPerUser: UITestingSeed.perAppleTVUser),
                                 sharedServers: InMemorySharedServerStore(UITestingSeed.sharedServers()))
            if ProcessInfo.processInfo.arguments.contains("-demoServers") { model.installDemoServers() }
            if ProcessInfo.processInfo.arguments.contains("-mockKomga") { model.installMockKomga() }
            if ProcessInfo.processInfo.arguments.contains("-mockOPDS") { model.installMockOPDS() }
            if ProcessInfo.processInfo.arguments.contains("-demoFavorites") { model.installDemoFavoritesAndBookmarks() }
            if ProcessInfo.processInfo.arguments.contains("-freeLibrary") {
                model.installFreeLibraryDemo()
            } else if ProcessInfo.processInfo.arguments.contains("-welcome") {
                model.useFreeLibraryDemoTransport()
            }
            if ProcessInfo.processInfo.arguments.contains("-liveServers") { model.installLiveServersFromEnvironment() }
            model.applyUITestingHomeLayout()
            // `-uiTestingTheme celadon` opens the app in that theme (ThemeScreensUITests).
            if let raw = UITestingSeed.value(after: "-uiTestingTheme"), let theme = AppTheme(rawValue: raw) {
                model.updateBrowse { $0.theme = theme }
            }
            return model
        }
        let model = AppModel(stateStore: StateStore(backing: UserDefaultsStore()), secrets: KeychainSecretStore(),
                             pins: KeychainPINStore(),
                             identity: Self.deviceIdentity,
                             sharedServers: KeychainSharedServerStore())
        model.installFreeLibraryIfNeeded()
        return model
    }

    /// tvOS: each Apple TV user can be the profile. iPhone/iPad are
    /// single-user devices, so in-app profiles are the profiles.
    private static var deviceIdentity: DeviceUserIdentity {
        #if os(tvOS)
        AppleTVUserIdentity()
        #else
        SingleUserDevice()
        #endif
    }

    // MARK: State

    /// The only way to change persisted state. Saves after every change.
    func update(_ change: (inout AppState) -> Void) {
        let old = state
        change(&state)
        // A guest's state lives in memory only: never saved, synced to
        // iCloud, shared with other Apple TV users or put on the Top Shelf.
        guard guestSession == nil else { return }
        stateStore.save(state)
        for observer in stateObservers { observer(old, state) }
        onStateChange?()
    }

    /// Drops cached server clients, e.g. after sync changed servers or logins.
    func resetClients() {
        clientCache.removeAll()
        credentialRevision += 1
    }

    /// Starts or ends a guest session. Only `AppModel+Guest.swift` calls it.
    func setGuestSession(_ session: GuestSession?) {
        guestSession = session
        // Every guest session starts fresh, though they share the guest id.
        progressOverrides = progressOverrides.filter { $0.key.profile != GuestSession.profileID }
    }

    /// Whose logins the servers are read with: the active profile's, or
    /// for a guest the profile that started the session.
    var loginProfileID: UUID { guestSession?.hostProfileID ?? activeProfile.id }

    /// Bumped whenever logins change. They live in the keychain, outside
    /// `state`, so screens can't observe them any other way.
    private(set) var credentialRevision = 0

    /// Changes whenever what the browse screens load from servers could:
    /// the active profile, a server added, removed or edited, the
    /// libraries/categories it imports, its progress sync setting, or a
    /// login. Home, Library, Search, Favorites and Bookmarks reload on it
    /// (`.task(id: model.contentKey)`), so changes in Settings show up
    /// right away instead of after a relaunch.
    var contentKey: String {
        ([activeProfile.id.uuidString, String(credentialRevision)] + servers.map(contentKey(for:)))
            .joined(separator: ",")
    }

    /// `contentKey` for one server's screens (Library).
    func contentKey(for server: ServerConfig) -> String {
        "\(server.id)|\(server.hashValue)|\(scopeKey(for: server))|\(syncsProgress(to: server.id))|\(credentialRevision)"
    }

    var activeProfile: Profile { state.activeProfile ?? Profile(name: "Me") }
    var servers: [ServerConfig] { state.servers }

    func switchProfile(_ id: UUID) {
        let previous = activeProfile.id
        update { $0.setActiveProfile(id) }
        resetClients()
        hiddenSeries = [:]
        if previous != id { locks.lock(previous) }
    }

    @discardableResult
    func addProfile(name: String, symbol: String, colorIndex: Int) -> Profile {
        var added: Profile?
        update { added = $0.addProfile(name: name, symbol: symbol, colorIndex: colorIndex) }
        return added!
    }

    func updateProfile(_ profile: Profile) {
        update { $0.updateProfile(profile) }
    }

    /// Removes a profile, its data and its server logins. The last profile
    /// can't be removed.
    func removeProfile(_ id: UUID) {
        guard state.profiles.count > 1 else { return }
        for server in state.servers { secrets.setCredential(nil, profile: id, server: server.id) }
        pins.setPIN(nil, profile: id)
        pinRevision += 1
        locks.lock(id)
        update { $0.removeProfile(id) }
        resetClients()
    }

    // MARK: Servers

    /// A client for a server, signed in as the active profile and limited to
    /// the libraries/categories that profile imports.
    func client(for server: ServerConfig) -> MangaServer {
        let scope = selectedCategories(for: server)
        let filter = contentFilter
        let key = "\(activeProfile.id.uuidString)|\(server.id.uuidString)|\(server.addresses.map(\.absoluteString).joined(separator: ","))|\(Self.scopeKey(scope))|\(filter.cacheKey)"
        if let cached = clientCache[key] { return cached }
        let credential = secrets.credential(profile: loginProfileID, server: server.id)
        // Every screen gets the profile's content filter through the client.
        let client = ContentFilteredServer.wrapping(makeClient(server, credential, scope, transport), filter: filter)
        clientCache[key] = client
        return client
    }

    /// A stable string for a selection, for cache keys and `.task(id:)`.
    static func scopeKey(_ scope: Set<String>?) -> String {
        scope.map { "only:" + $0.sorted().joined(separator: ",") } ?? "all"
    }

    /// Changes whenever the active profile's selection for `server` or its
    /// content filter does.
    func scopeKey(for server: ServerConfig) -> String {
        Self.scopeKey(selectedCategories(for: server)) + "|" + contentFilter.cacheKey
    }

    func client(for ref: SeriesRef) -> MangaServer? {
        state.server(ref.serverID).map(client(for:))
    }

    func credential(for server: ServerConfig) -> ServerCredential? {
        secrets.credential(profile: loginProfileID, server: server.id)
    }

    /// Saves a server and the active profile's login for it. Throws when
    /// the login couldn't be stored (it's read back to check), so the form
    /// stays open with the error rather than closing as if it had saved.
    func saveServer(_ server: ServerConfig, credential: ServerCredential?) throws {
        // Store the login first: a failed write leaves the server list as it was.
        try secrets.saveCredential(credential, profile: activeProfile.id, server: server.id)
        if state.server(server.id) == nil {
            update { $0.addServer(server) }
        } else {
            update { $0.updateServer(server) }
        }
        // Now that a new server is in the shared directory, offer the login
        // as the one other Apple TV users fall back to.
        if let credential, secrets is SharedFallbackSecretStore {
            secrets.setCredential(credential, profile: activeProfile.id, server: server.id)
        }
        resetClients()
    }

    /// Checks a server and login without saving them.
    /// With several addresses, says which one answered.
    func testConnection(_ server: ServerConfig, credential: ServerCredential?) async throws -> String {
        let message = try await makeClient(server, credential, nil, transport).validate()
        guard server.hasAlternateAddresses else { return message }
        let used = ServerAddressRouter.shared.currentAddress(for: server)
        let which = used == server.baseURL ? "the first address" : (used.host ?? used.absoluteString)
        let lead = message.hasSuffix(".") ? String(message.dropLast()) : message
        return lead + ". Connected through \(which)."
    }

    /// Every library/category on a server, selected or not, for the picker.
    /// Works before the server is saved.
    func availableCategories(_ server: ServerConfig, credential: ServerCredential?) async throws -> [MangaCategory] {
        try await makeClient(server, credential, nil, transport).categories()
    }

    /// The library/category ids the active profile imports (nil = all).
    func selectedCategories(for server: ServerConfig) -> Set<String>? {
        state.selectedCategories(profile: activeProfile.id, server: server.id)
    }

    func setSelectedCategories(_ ids: Set<String>?, for server: ServerConfig) {
        let profile = activeProfile.id
        update { $0.setSelectedCategories(ids, profile: profile, server: server.id) }
    }

    /// Turns the server form into the login to save: signs in to Kavita
    /// when a password was typed, names the owner of a pasted Kavita key,
    /// and works out how a Suwayomi server takes a username and password.
    func resolveCredential(_ draft: ServerDraft, for server: ServerConfig) async throws -> ServerCredential? {
        if draft.needsKavitaSignIn {
            return try await kavitaSignIn(server, draft.username, draft.password, transport)
        }
        guard var credential = draft.credential else { return nil }
        switch server.kind {
        case .kavita:
            if credential.username == nil, let kavita = makeClient(server, credential, nil, transport) as? KavitaClient {
                credential.username = try await kavita.username()
            }
        case .suwayomi:
            if credential.suwayomiLogin == nil, let user = credential.username {
                credential.suwayomiLogin = await SuwayomiClient.detectLoginMode(
                    config: server, username: user, password: credential.password ?? "", transport: transport)
            }
        case .komga, .opds, .freeLibrary:
            break
        }
        return credential
    }

    /// The Suwayomi user a login maps to, on servers with user accounts.
    /// Nil when the server keeps one shared progress.
    func suwayomiUser(_ server: ServerConfig, credential: ServerCredential?) async -> String? {
        guard server.kind == .suwayomi, let client = makeClient(server, credential, nil, transport) as? SuwayomiClient else {
            return nil
        }
        return await client.currentUser()
    }

    func serverSettings(for server: ServerConfig) -> ProfileServerSettings {
        state.serverSettings(profile: activeProfile.id, server: server.id)
    }

    func setServerSettings(_ settings: ProfileServerSettings, for server: ServerConfig) {
        let profile = activeProfile.id
        update { $0.setServerSettings(settings, profile: profile, server: server.id) }
    }

    func removeServer(_ server: ServerConfig) {
        ServerAddressRouter.shared.forget(server.id)
        secrets.removeCredentials(server: server.id, profiles: state.profiles.map(\.id))
        if server.kind == .freeLibrary {
            update { $0.removeFreeLibrary() }
        } else {
            update { $0.removeServer(server.id) }
        }
        resetClients()
    }

    // MARK: Favorites

    func isFavorite(_ ref: SeriesRef) -> Bool {
        state.isFavorite(ref, profile: activeProfile.id)
    }

    func toggleFavorite(_ series: SeriesSummary) {
        let profile = activeProfile.id
        update { $0.setFavorite(series, !$0.isFavorite(series.ref, profile: profile), profile: profile) }
    }

    // MARK: Progress

    func syncsProgress(to serverID: UUID) -> Bool {
        // The Free Library has no server progress; it's always kept here.
        if serverID == FreeLibrary.serverID { return false }
        // A guest never writes to a server.
        if guestSession != nil { return false }
        return state.serverSettings(profile: activeProfile.id, server: serverID).syncProgressToServer
    }

    /// Writes the reader's position to this profile's saved state only. The
    /// reader calls it on every page change so a crash or a force quit
    /// never loses the page; `recordProgress` pushes to the server.
    func recordLocalProgress(chapter: Chapter, series: SeriesSummary, page: Int, completed: Bool) {
        let profile = activeProfile.id
        update { $0.recordProgress(chapter.seriesRef, chapterID: chapter.id, page: page, completed: completed,
                                   profile: profile, series: series) }
    }

    /// The page to open `chapter` at when none was asked for.
    func resumePage(for chapter: Chapter, sessionPage: Int?) -> Int {
        ResumePosition.startPage(for: chapter, sessionPage: sessionPage,
                                 local: state.progress(chapter.seriesRef, profile: activeProfile.id),
                                 serverReadAt: chapter.lastReadAt)
    }

    /// Records progress locally, and on the server if this profile syncs
    /// there. A change the server doesn't confirm stays queued on the
    /// series and is retried by `seriesDetail` / `syncPendingProgress`.
    func recordProgress(chapter: Chapter, series: SeriesSummary, page: Int, completed: Bool) async {
        await startRecordingProgress(chapter: chapter, series: series, page: page, completed: completed).value
    }

    /// Like `recordProgress`, but returns at once with the save running.
    /// The save is registered before this returns, so a later
    /// `refreshSeriesProgress` waits for it (the reader closing calls both
    /// back to back).
    @discardableResult
    func startRecordingProgress(chapter: Chapter, series: SeriesSummary, page: Int, completed: Bool) -> Task<Void, Never> {
        let profile = activeProfile.id
        let ref = chapter.seriesRef
        let now = Date()
        let syncs = syncsProgress(to: ref.serverID)
        update {
            $0.recordProgress(ref, chapterID: chapter.id, page: page, completed: completed, profile: profile,
                              now: now, series: series)
            if syncs {
                $0.queuePending(PendingProgress(chapterID: chapter.id, page: page, completed: completed, at: now),
                                for: ref, profile: profile)
            }
        }
        let previous = progressSaves[ref]
        let client = syncs ? client(for: ref) : nil
        let task = Task { [weak self] in
            // Saves for one series go out in order.
            await previous?.value
            guard let client else { return }
            do {
                try await client.saveProgress(chapter: chapter, libraryID: series.libraryID, page: page, completed: completed)
                self?.update { $0.clearPending(ref, chapterIDs: [chapter.id], through: now, profile: profile) }
                self?.pushSucceeded()
            } catch {
                // Stays queued; retried with backoff.
                self?.schedulePendingRetry()
            }
        }
        progressSaves[ref] = task
        return task
    }

    // MARK: Retrying queued pushes

    /// Consecutive failed attempts to push queued progress.
    @ObservationIgnored private var pushFailures = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored var retryBackoff = RetryBackoff()

    private var syncingServerIDs: [UUID] { servers.map(\.id).filter { syncsProgress(to: $0) } }

    var hasPendingProgress: Bool {
        state.hasPending(servers: syncingServerIDs, profile: activeProfile.id)
    }

    private func pushSucceeded() {
        if !hasPendingProgress {
            pushFailures = 0
            retryTask?.cancel()
            retryTask = nil
        }
    }

    /// After a failed push, tries the queue again in 5 s, then 10 s, 20 s,
    /// ... up to every 5 minutes, until the server takes it. One retry is
    /// scheduled at a time; nothing runs once the queue is empty.
    func schedulePendingRetry() {
        guard retryTask == nil, hasPendingProgress else { return }
        pushFailures += 1
        let seconds = retryBackoff.delay(afterFailures: pushFailures)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            // Reschedules itself (with a longer wait) if anything is left.
            await self.syncPendingProgress()
        }
    }

    /// Back in the foreground (or the network is back): push now instead
    /// of waiting out the backoff.
    func retryPendingProgressNow() async {
        retryTask?.cancel()
        retryTask = nil
        pushFailures = 0
        guard hasPendingProgress else { return }
        await syncPendingProgress()
    }


    /// The last progress save started for each series (each waits for the
    /// one before it).
    @ObservationIgnored private var progressSaves: [SeriesRef: Task<Void, Never>] = [:]

    /// Waits until every progress save started so far for `ref` is done.
    func waitForProgressSaves(_ ref: SeriesRef) async {
        await progressSaves[ref]?.value
    }

    /// After reading: waits for the saves, then reloads the series so every
    /// poster of it (Home, Library, Favorites, Search) shows the new badge,
    /// bar and percentage.
    func refreshSeriesProgress(_ ref: SeriesRef) {
        Task { await refreshProgressOverride(ref) }
    }

    /// Read progress changed since the feeds loaded (reading, "Mark as
    /// Unread"), so posters update without reloading every row.
    /// Keyed by profile too, since each profile has its own progress.
    private var progressOverrides: [ProfileSeriesKey: SeriesProgressOverride] = [:]

    struct ProfileSeriesKey: Hashable {
        let profile: UUID
        let series: SeriesRef
    }
    /// Chapter counts for poster captions (see `SeriesCountStore`).
    let seriesCounts = SeriesCountStore()

    /// `series` with any progress changed since it loaded.
    func withCurrentProgress(_ series: SeriesSummary) -> SeriesSummary {
        progressOverrides[ProfileSeriesKey(profile: activeProfile.id, series: series.ref)]?.applied(to: series) ?? series
    }

    /// Marks chapters of one series unread for this profile, and on the
    /// server when this profile syncs there.
    func markUnread(_ chapters: [Chapter], in ref: SeriesRef) async throws {
        guard !chapters.isEmpty else { return }
        let profile = activeProfile.id
        let ids = Set(chapters.map(\.id))
        update {
            $0.markUnread(ref, chapterIDs: ids, profile: profile)
            // A queued push would mark them read again.
            $0.clearPending(ref, chapterIDs: ids, through: .distantFuture, profile: profile)
        }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markUnread(chapters: chapters)
        }
        await refreshUnreadCount(ref)
    }

    /// Marks chapters of one series read for this profile, and on the
    /// server when this profile syncs there. Where Continue resumes stays
    /// the same; it skips read chapters on its own.
    func markRead(_ chapters: [Chapter], in ref: SeriesRef, libraryID: String?) async throws {
        guard !chapters.isEmpty else { return }
        let profile = activeProfile.id
        let ids = Set(chapters.map(\.id))
        update {
            $0.markRead(ref, chapterIDs: ids, profile: profile)
            // A queued partial-page push would undo the read mark.
            $0.clearPending(ref, chapterIDs: ids, through: .distantFuture, profile: profile)
        }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markRead(chapters: chapters, libraryID: libraryID)
        }
        await refreshUnreadCount(ref)
    }

    /// Marks every chapter of a series unread for this profile, and on the
    /// server when this profile syncs there.
    func markSeriesUnread(_ ref: SeriesRef) async throws {
        let profile = activeProfile.id
        // Also drops any queued pushes for the series.
        update { $0.markSeriesUnread(ref, profile: profile) }
        if syncsProgress(to: ref.serverID), let client = client(for: ref) {
            try await client.markSeriesUnread(ref.seriesID)
        }
        await refreshUnreadCount(ref)
    }

    private func refreshUnreadCount(_ ref: SeriesRef) async {
        await refreshProgressOverride(ref)
    }

    /// Reloads `ref` (with this profile's progress resolved) once its
    /// pending saves are done and records it for posters.
    func refreshProgressOverride(_ ref: SeriesRef) async {
        let profile = activeProfile.id
        await waitForProgressSaves(ref)
        guard let detail = try? await seriesDetail(ref), profile == activeProfile.id else { return }
        noteProgress(of: detail, for: ref)
    }

    /// Records fresh progress from a series detail resolved for the active
    /// profile, for its posters.
    func noteProgress(of detail: SeriesDetail, for ref: SeriesRef) {
        let key = ProfileSeriesKey(profile: activeProfile.id, series: ref)
        let override = SeriesProgressOverride(detail: detail)
        if progressOverrides[key] != override { progressOverrides[key] = override }
    }

    /// Series detail with progress resolved for this profile: local
    /// progress on top when it doesn't sync to the server; otherwise the
    /// server's, merged with any queued local changes (latest wins), which
    /// are pushed.
    func seriesDetail(_ ref: SeriesRef) async throws -> SeriesDetail {
        guard let client = client(for: ref) else { throw MangaError.notFound }
        let detail = try await client.seriesDetail(ref.seriesID)
        let profile = activeProfile.id
        guard syncsProgress(to: ref.serverID) else {
            // What the server says is the owner's reading, not the guest's.
            let base = guestSession == nil ? detail : GuestSession.withoutServerProgress(detail)
            return state.applyingLocalProgress(to: base, profile: profile)
        }
        let pending = state.pending(ref, profile: profile)
        guard !pending.isEmpty else { return detail }
        let resolution = ProgressSync.reconcile(detail, pending: pending)
        if !resolution.dropped.isEmpty {
            update { state in
                for p in resolution.dropped {
                    state.clearPending(ref, chapterIDs: [p.chapterID], through: p.at, profile: profile)
                }
            }
        }
        for p in resolution.push {
            guard let chapter = resolution.detail.chapters.first(where: { $0.id == p.chapterID }) else { continue }
            do {
                try await client.saveProgress(chapter: chapter, libraryID: detail.summary.libraryID,
                                              page: p.page, completed: p.completed)
                update { $0.clearPending(ref, chapterIDs: [p.chapterID], through: p.at, profile: profile) }
            } catch {
                schedulePendingRetry()
                break // Still offline; retried with backoff.
            }
        }
        return resolution.detail
    }

    /// Pushes queued progress for every series on servers this profile
    /// syncs to. Home calls it before loading its rows.
    func syncPendingProgress() async {
        let profile = activeProfile.id
        for server in servers where syncsProgress(to: server.id) {
            for ref in state.seriesWithPending(server: server.id, profile: profile) {
                guard activeProfile.id == profile else { return }
                if (try? await seriesDetail(ref)) == nil { break } // Server unreachable.
            }
        }
        if hasPendingProgress { schedulePendingRetry() } else { pushSucceeded() }
    }

    /// This profile's own Continue Reading for a server it doesn't sync to.
    func localContinueReading(for server: ServerConfig) -> [SeriesSummary] {
        // Local like Favorites, so the content filter applies here too.
        visibleSeries(state.localContinueReading(server: server.id, profile: activeProfile.id))
    }

    // MARK: Reader settings

    func readerSettings(for ref: SeriesRef) -> ReaderSettings {
        let settings = state.readerSettings(for: ref, profile: activeProfile.id)
        if ref.serverID == FreeLibrary.serverID, !state.hasReaderOverride(for: ref, profile: activeProfile.id) {
            return FreeLibrary.readerSettings(from: settings)
        }
        return settings
    }

    func setReaderSettings(_ settings: ReaderSettings, for ref: SeriesRef) {
        let profile = activeProfile.id
        update { $0.setReaderSettings(settings, for: ref, profile: profile) }
    }

    /// The active profile's reader settings for series without an override.
    var defaultReaderSettings: ReaderSettings {
        (state.profileData[activeProfile.id.uuidString]?.defaultReaderSettings ?? .default).normalizedPairing
    }

    func setDefaultReaderSettings(_ settings: ReaderSettings) {
        let profile = activeProfile.id
        update { $0.setDefaultReaderSettings(settings, profile: profile) }
    }

    // MARK: Content filter

    /// What the active profile hides (genres, tags, age limit).
    var contentFilter: ContentFilter { state.contentFilter(profile: activeProfile.id) }

    func setContentFilter(_ filter: ContentFilter) {
        let profile = activeProfile.id
        update { $0.setContentFilter(filter, profile: profile) }
        clientCache.removeAll()
        hiddenSeries = [:]
    }

    /// Genres and tags across every server, for the filter checklist.
    /// Servers that can't be reached are skipped.
    func contentFacets() async -> ContentFacets {
        let clients = servers.map { client(for: $0) }
        let all = await withTaskGroup(of: ContentFacets?.self) { group in
            for c in clients { group.addTask { try? await c.contentFacets() } }
            var out: [ContentFacets] = []
            for await f in group { if let f { out.append(f) } }
            return out
        }
        return ContentFacets.merged(all, keeping: contentFilter)
    }

    /// Loads which series each server hides for the active profile, for
    /// `favorites` and Top Shelf. Servers that fail stay missing, so their
    /// favorites stay hidden.
    func refreshHiddenSeries() async {
        let filter = contentFilter
        guard filter.isActive else {
            hiddenSeries = [:]
            return
        }
        let clients = servers.map { client(for: $0) }
        let loaded = await withTaskGroup(of: (UUID, Set<String>?).self) { group in
            for c in clients {
                group.addTask { (c.config.id, try? await c.hiddenSeriesIDs(for: filter)) }
            }
            var out: [UUID: Set<String>] = [:]
            for await (id, ids) in group { if let ids { out[id] = ids } }
            return out
        }
        guard filter == contentFilter else { return }
        hiddenSeries = loaded
    }

    /// Series from local data that the active profile may see. Anything
    /// built from saved series (Favorites, Top Shelf) goes through this.
    func visibleSeries(_ series: [SeriesSummary]) -> [SeriesSummary] {
        ContentVisibility.visible(series, filter: contentFilter, hidden: hiddenSeries)
    }

    /// The active profile's bookmarks, leaving out series its content
    /// filter hides.
    var visibleBookmarks: [Bookmark] {
        let allowed = Set(visibleSeries(bookmarks.map(\.series)).map(\.ref))
        return bookmarks.filter { allowed.contains($0.series.ref) }
    }

    // MARK: Profile PINs

    func hasPIN(_ profile: UUID) -> Bool {
        _ = pinRevision
        return pins.hasPIN(profile: profile)
    }

    /// True when the profile has a PIN that hasn't been entered this session.
    func isLocked(_ profile: UUID) -> Bool { !locks.isUnlocked(profile, store: pins) }

    func requiresPINToOpen(_ profile: UUID) -> Bool { state.requiresPINToOpen(profile: profile) }

    /// Opening this profile asks for its PIN first.
    func needsPINToOpen(_ profile: UUID) -> Bool {
        requiresPINToOpen(profile) && isLocked(profile)
    }

    func setRequiresPINToOpen(_ on: Bool, profile: UUID) {
        update { $0.setRequiresPINToOpen(on, profile: profile) }
    }

    /// Sets a new PIN (the profile stays unlocked) or removes it with nil.
    func setPIN(_ pin: String?, for profile: UUID) {
        pins.setPIN(pin, profile: profile)
        pinRevision += 1
        if pin == nil {
            setRequiresPINToOpen(false, profile: profile)
            locks.lock(profile)
        } else {
            locks.markUnlocked(profile)
        }
    }

    /// Checks a PIN against `candidates`, unlocking the one it matches.
    func attemptPIN(_ pin: String, candidates: [UUID]) -> ProfileLocks.Result {
        locks.attempt(pin, candidates: candidates, store: pins)
    }

    /// Profiles that have a PIN.
    var protectedProfiles: [UUID] { state.profiles.map(\.id).filter { hasPIN($0) } }

    /// Locks every profile again (the app went to the background). Shows
    /// the picker if the active profile needs its PIN to open.
    func lockAll() {
        locks.lockAll()
        if needsPINToOpen(activeProfile.id) { isPickingProfile = true }
    }
}
