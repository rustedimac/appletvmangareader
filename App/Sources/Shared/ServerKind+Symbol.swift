import MangaCore

extension ServerKind {
    /// SF Symbol shown next to a server.
    var symbolName: String {
        switch self {
        case .kavita: return "books.vertical.fill"
        case .suwayomi: return "square.stack.3d.up.fill"
        case .freeLibrary: return FreeLibrarySymbol.name
        }
    }
}

enum FreeLibrarySymbol {
    static let name = "building.columns.fill"
}
