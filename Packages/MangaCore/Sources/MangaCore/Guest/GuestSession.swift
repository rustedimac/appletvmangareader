import Foundation

/// A guest reading session: someone visiting reads from this Apple TV's
/// servers without signing in, and without touching the owner's reading
/// progress, favorites, bookmarks, settings or servers.
///
/// The guest gets a state of their own (`makeState(from:)`) that lives only
/// in memory: it is never saved, synced to iCloud, put on the Top Shelf or
/// written back to a server, and it's gone when the session ends or the app
/// quits. Servers are read with the host profile's login (or the login
/// shared between Apple TV users), and nothing is pushed to them.
///
/// Platform-neutral, like the rest of the profile system (see
/// `DeviceUserIdentity`), so an iPhone or Mac app can offer it as well.
public struct GuestSession: Equatable, Sendable {
    /// The guest's profile id, the same in every session so nothing the
    /// guest does can be mistaken for a real profile's data.
    public static let profileID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0E5")!
    public static let profile = Profile(id: profileID, name: "Guest", symbol: "person.crop.circle.dashed",
                                        colorIndex: 7)

    /// Whose logins the guest reads with, and whose settings they start from.
    public var hostProfileID: UUID
    public var startedAt: Date

    public init(hostProfileID: UUID, startedAt: Date = Date()) {
        self.hostProfileID = hostProfileID
        self.startedAt = startedAt
    }

    /// The state a guest session runs on. It has the owner's servers and
    /// one profile, the guest, which starts from the host's library choices
    /// and reader defaults (so the same libraries and page layout show) but
    /// holds none of their favorites, progress, bookmarks, recent series or
    /// Home layout. Progress never syncs to any server.
    public func makeState(from owner: AppState) -> AppState {
        let host = owner.profileData[hostProfileID.uuidString] ?? ProfileData()
        var data = ProfileData()
        for server in owner.servers {
            var settings = host.serverSettings[server.id.uuidString] ?? ProfileServerSettings()
            settings.syncProgressToServer = false
            data.serverSettings[server.id.uuidString] = settings
        }
        data.defaultReaderSettings = host.defaultReaderSettings
        data.bookSettings = host.bookSettings
        data.webtoonAutoScrollLevel = host.webtoonAutoScrollLevel
        // The host's content filter comes along, so a guest session can't
        // be a way around it.
        data.contentFilter = host.contentFilter
        var state = AppState(profiles: [Self.profile], activeProfileID: Self.profileID,
                             servers: owner.servers, profileData: [Self.profileID.uuidString: data])
        state.freeLibraryRemoved = owner.freeLibraryRemoved
        return state
    }

    /// Series detail as a guest sees it: every chapter unread and at its
    /// first page, since what the server reports is the owner's reading.
    /// The guest's own progress goes on top (`AppState.applyingLocalProgress`).
    public static func withoutServerProgress(_ detail: SeriesDetail) -> SeriesDetail {
        var d = detail
        d.summary = withoutServerProgress(d.summary)
        for i in d.chapters.indices {
            d.chapters[i].isRead = false
            d.chapters[i].lastPageRead = 0
            d.chapters[i].lastReadAt = nil
        }
        return d
    }

    /// A poster's series without the owner's unread count and page progress.
    public static func withoutServerProgress(_ series: SeriesSummary) -> SeriesSummary {
        var s = series
        s.unreadCount = nil
        s.pagesRead = nil
        return s
    }
}
