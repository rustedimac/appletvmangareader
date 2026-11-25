import Foundation

public extension ServerKind {
    /// SF Symbol shown next to a server of this kind.
    var symbolName: String {
        switch self {
        case .suwayomi: return "square.stack.3d.up.fill"
        case .opds: return "antenna.radiowaves.left.and.right"
        default: return "books.vertical.fill"
        }
    }

    /// "library" or "category", for counts of one.
    var singularCategoryNoun: String {
        switch self {
        case .kavita, .komga: return "library"
        case .opds: return "section"
        case .suwayomi: return "category"
        }
    }

    /// Whether the server can keep reading progress. OPDS is read-only, so
    /// progress for it always stays on the Apple TV.
    var canSyncProgress: Bool { self != .opds }

    /// Whether the server can't be used without a login (Suwayomi's and
    /// OPDS's are optional).
    var requiresLogin: Bool {
        self == .kavita || self == .komga
    }
}
