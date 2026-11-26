import Foundation
import MangaCore

extension AppModel {
    /// Applies changes from iCloud or a backup, then moves or deletes
    /// Keychain logins to match.
    @discardableResult
    func applySync(_ patch: SyncPatch) -> SyncApplyEffects {
        guard !patch.isEmpty, !isGuest else { return SyncApplyEffects() }
        let profilesBefore = state.profiles.map(\.id)
        var effects = SyncApplyEffects()
        update { effects = SyncMapper.apply(patch, to: &$0) }
        effects.applyCredentials(to: secrets, servers: state.servers.map(\.id),
                                 profiles: Array(Set(profilesBefore + state.profiles.map(\.id))))
        resetClients()
        if !state.profiles.contains(where: { $0.id == activeProfile.id }), let first = state.profiles.first {
            update { $0.setActiveProfile(first.id) }
        }
        return effects
    }

    // MARK: Backup

    var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func exportBackup() -> Data {
        MangaBackup.export(state: savedState, appVersion: appVersion)
    }

    /// Restores (merges) a backup file. Returns a summary for the person.
    func restoreBackup(_ data: Data) throws -> String {
        let records = try MangaBackup.parse(data)
        let effects = applySync(MangaBackup.restorePatch(state: state, backup: records))
        return MangaBackup.summary(effects)
    }
}
