import Foundation

/// Pepper&Carrot, the webcomic by David Revoy, licensed CC BY 4.0.
/// The episode list is `https://www.peppercarrot.com/0_sources/episodes.json`,
/// an array of `{name, total_pages, translated_languages}`. Page files follow
/// one pattern:
/// `0_sources/<name>/low-res/<lang>_Pepper-and-Carrot_by-David-Revoy_E<NN>P<PP>.jpg`,
/// where P00 is the episode's title strip and P01...P<total_pages> the pages,
/// and `..._E<NN>.jpg` is the episode cover.
public enum PepperCarrot {
    public static let episodesURL = URL(string: "https://www.peppercarrot.com/0_sources/episodes.json")!
    static let sourcesBase = "https://www.peppercarrot.com/0_sources/"

    /// The site's own language code for English (it isn't always ISO 639).
    public static let language = "en"

    /// Required attribution, shown in the series description.
    public static let credit = """
        Pepper&Carrot by David Revoy, www.peppercarrot.com. Licensed under Creative Commons Attribution 4.0 \
        (CC BY 4.0, creativecommons.org/licenses/by/4.0). English translation by the Pepper&Carrot community. \
        Shown unchanged.
        """

    /// Episode 1's cover, used as the series poster.
    public static var seriesCoverURL: URL? {
        URL(string: sourcesBase + "ep01_Potion-of-Flight/low-res/\(language)_Pepper-and-Carrot_by-David-Revoy_E01.jpg")
    }

    struct EpisodeDTO: Decodable {
        var name: String
        var total_pages: Int
        var translated_languages: [String]?
    }

    /// Episodes available in English, in order. Entries with unexpected
    /// names are skipped rather than turned into URLs.
    static func parseEpisodes(_ data: Data) throws -> [PepperCarrotEpisode] {
        let list = try HTTPClient.decode([EpisodeDTO].self, from: data)
        return list.compactMap { dto in
            guard dto.translated_languages?.contains(language) ?? false,
                  dto.total_pages > 0, dto.total_pages < 100 else { return nil }
            return PepperCarrotEpisode(name: dto.name, totalPages: dto.total_pages)
        }
        .sorted { $0.number < $1.number }
    }
}

public struct PepperCarrotEpisode: Hashable, Sendable {
    /// Folder name, e.g. "ep08_Pepper-s-Birthday-Party".
    public let name: String
    public let number: Int
    /// Pages, not counting the P00 title strip.
    public let totalPages: Int

    static let chapterPrefix = "pc:"

    init?(name: String, totalPages: Int) {
        guard name.count < 80, name.hasPrefix("ep"), let underscore = name.firstIndex(of: "_"),
              let number = Int(name[name.index(name.startIndex, offsetBy: 2)..<underscore]), number > 0,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
            return nil
        }
        self.name = name
        self.number = number
        self.totalPages = totalPages
    }

    /// "Pepper's Birthday Party" from "ep08_Pepper-s-Birthday-Party".
    public var title: String {
        guard let underscore = name.firstIndex(of: "_") else { return name }
        var words = String(name[name.index(after: underscore)...]).split(separator: "-").map(String.init)
        // The slugs write "Pepper's" as "Pepper-s".
        var i = 1
        while i < words.count {
            if words[i] == "s" { words[i - 1] += "'s"; words.remove(at: i) } else { i += 1 }
        }
        return words.joined(separator: " ")
    }

    static func name(fromChapterID id: String) -> String? {
        id.hasPrefix(chapterPrefix) ? String(id.dropFirst(chapterPrefix.count)) : nil
    }

    private var paddedNumber: String { number < 10 ? "0\(number)" : "\(number)" }

    func pageURL(_ page: Int) -> URL? {
        let p = page < 10 ? "0\(page)" : "\(page)"
        return URL(string: PepperCarrot.sourcesBase +
                   "\(name)/low-res/\(PepperCarrot.language)_Pepper-and-Carrot_by-David-Revoy_E\(paddedNumber)P\(p).jpg")
    }

    /// The title strip (P00) followed by every page. Sizes are learned when
    /// each image loads.
    func pages() -> [PageDescriptor] {
        (0...totalPages).compactMap { pageURL($0) }.enumerated().map { PageDescriptor(index: $0.offset, url: $0.element) }
    }

    func chapter(seriesRef: SeriesRef) -> Chapter {
        Chapter(id: Self.chapterPrefix + name, seriesRef: seriesRef, title: "Episode \(number): \(title)",
                number: Double(number), pageCount: totalPages + 1)
    }
}
