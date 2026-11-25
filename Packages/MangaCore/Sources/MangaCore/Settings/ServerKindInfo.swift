import Foundation

public extension ServerKind {
    /// "library" or "category", for counts of one.
    var singularCategoryNoun: String {
        switch self {
        case .kavita, .komga: return "library"
        case .opds: return "section"
        case .suwayomi: return "category"
        case .freeLibrary: return "collection"
        }
    }

    /// Whether the server can keep reading progress. OPDS is read-only and
    /// the Free Library has no accounts, so their progress stays on the
    /// Apple TV.
    var canSyncProgress: Bool { self != .opds && self != .freeLibrary }

    /// Whether the server can't be used without a login (Suwayomi's and
    /// OPDS's are optional).
    var requiresLogin: Bool {
        self == .kavita || self == .komga
    }
}
