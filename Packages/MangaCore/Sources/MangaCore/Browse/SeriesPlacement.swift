import Foundation

/// Where a series lives on its server: the Kavita or Komga library, the
/// Suwayomi categories (a manga can be in several) and the source it comes
/// from, the OPDS catalog section, or the Free Library collection. Shown
/// on series detail next to the server name ("kavita-en.home · Manga").
public struct SeriesPlacement: Codable, Hashable, Sendable {
    /// Library/category names, in the server's order.
    public var categories: [String]
    /// Where the server got the series from (Suwayomi source), if any.
    public var source: String?

    public init(categories: [String], source: String? = nil) {
        var seen = Set<String>()
        self.categories = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = trimmed?.isEmpty == false ? trimmed : nil
    }

    public var isEmpty: Bool { categories.isEmpty && source == nil }

    /// Names of `ids` from `categories`, in the categories' order. Ids
    /// without a known name are left out.
    public static func resolve(ids: [String], in categories: [MangaCategory]) -> SeriesPlacement? {
        let wanted = Set(ids)
        let names = categories.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            .filter { wanted.contains($0.id) }
            .map(\.name)
        let placement = SeriesPlacement(categories: names)
        return placement.isEmpty ? nil : placement
    }

    /// The text after the server name: "Manga", "Reading, Action", or
    /// "Reading · from Example Source".
    public var label: String {
        var parts: [String] = []
        if !categories.isEmpty { parts.append(categories.joined(separator: ", ")) }
        if let source { parts.append("from \(source)") }
        return parts.joined(separator: " · ")
    }

    /// "kavita-en.home · Manga"; just the server name when nothing is known.
    public static func line(server: String?, placement: SeriesPlacement?) -> String? {
        let parts = [server, placement.map(\.label)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public extension MangaServer {
    /// Where `series` lives on this server: what the client put in
    /// `detail`, else the names of its library/category ids (from the
    /// summary the user opened, or from detail) looked up in `categories()`.
    func placement(for series: SeriesSummary, detail: SeriesDetail?) async -> SeriesPlacement? {
        if let known = detail?.placement, !known.isEmpty { return known }
        var ids: [String] = []
        for id in (series.memberCategoryIDs ?? []) + (detail?.summary.memberCategoryIDs ?? []) where !ids.contains(id) {
            ids.append(id)
        }
        guard !ids.isEmpty, let categories = try? await categories() else { return nil }
        return SeriesPlacement.resolve(ids: ids, in: categories)
    }
}
