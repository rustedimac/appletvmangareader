import Foundation

public extension ServerKind {
    /// SF Symbol shown next to a server of this kind.
    var symbolName: String {
        self == .suwayomi ? "square.stack.3d.up.fill" : "books.vertical.fill"
    }

    /// "library" or "category", for counts of one.
    var singularCategoryNoun: String {
        self == .suwayomi ? "category" : "library"
    }

    /// Whether the server can't be used without a login (Suwayomi's is optional).
    var requiresLogin: Bool {
        self == .kavita || self == .komga
    }
}
