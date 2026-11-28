import MangaCore

extension ServerKind {
    /// SF Symbol shown next to a server.
    var symbolName: String {
        switch self {
        case .kavita, .komga: return "books.vertical.fill"
        case .suwayomi: return "square.stack.3d.up.fill"
        case .opds: return "antenna.radiowaves.left.and.right"
        case .calibre: return "books.vertical.circle.fill"
        case .freeLibrary: return FreeLibrarySymbol.name
        }
    }
}

enum FreeLibrarySymbol {
    static let name = "building.columns.fill"
}
