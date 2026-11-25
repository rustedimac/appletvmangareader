import UIKit
import MangaCore

/// Where text goes on screen: one or two columns of `columnSize`, starting
/// at `origins`. Computed from the screen size and settings.
struct BookPageGeometry: Equatable {
    var columnSize: CGSize
    var origins: [CGPoint]

    /// TV-safe margins: text never sits in the overscan band, and the
    /// bottom leaves room for the position line.
    static func make(viewport: CGSize, columns: Int) -> BookPageGeometry {
        let horizontal: CGFloat = 130
        let top: CGFloat = 90
        let bottom: CGFloat = 120
        let gap: CGFloat = 120
        let height = max(200, viewport.height - top - bottom)
        let usable = max(400, viewport.width - horizontal * 2)
        if columns >= 2 {
            let width = floor((usable - gap) / 2)
            return BookPageGeometry(columnSize: CGSize(width: width, height: height),
                                    origins: [CGPoint(x: horizontal, y: top),
                                              CGPoint(x: horizontal + width + gap, y: top)])
        }
        // A single column is capped at a comfortable line length and centered.
        let width = min(usable, 1250)
        return BookPageGeometry(columnSize: CGSize(width: width, height: height),
                                origins: [CGPoint(x: floor((viewport.width - width) / 2), y: top)])
    }
}

/// One section laid out into screen pages with TextKit. Each text
/// container is one column; a screen page shows `columns` containers side
/// by side. Drawing goes through the same layout manager, so what is on
/// screen is exactly what was paginated.
@MainActor
final class BookSectionLayout {
    let section: Int
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let containers: [NSTextContainer]
    let geometry: BookPageGeometry
    /// Character offset where each of the section's blocks starts.
    let blockOffsets: [Int]

    init(section: Int, storage: NSTextStorage, layoutManager: NSLayoutManager, containers: [NSTextContainer],
         geometry: BookPageGeometry, blockOffsets: [Int]) {
        self.section = section
        self.storage = storage
        self.layoutManager = layoutManager
        self.containers = containers
        self.geometry = geometry
        self.blockOffsets = blockOffsets
    }

    var columns: Int { geometry.origins.count }

    /// Screen pages. Zero for a section with no text (a blank spine item),
    /// which the reader skips.
    var pageCount: Int {
        guard storage.length > 0 else { return 0 }
        return max(1, (containers.count + columns - 1) / columns)
    }

    func containerIndices(forPage page: Int) -> Range<Int> {
        let start = min(containers.count, max(0, page) * columns)
        return start..<min(containers.count, start + columns)
    }

    /// The screen page that shows a character.
    func page(forCharacter offset: Int) -> Int {
        guard storage.length > 0 else { return 0 }
        let clamped = min(max(0, offset), storage.length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
        guard let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
              let index = containers.firstIndex(where: { $0 === container }) else { return 0 }
        return index / columns
    }

    func page(forBlock block: Int) -> Int {
        guard blockOffsets.indices.contains(block) else { return 0 }
        return page(forCharacter: blockOffsets[block])
    }

    /// The text on a screen page, for VoiceOver.
    func text(onPage page: Int) -> String {
        let indices = containerIndices(forPage: page)
        guard let first = indices.first, let last = indices.last else { return "" }
        let start = layoutManager.glyphRange(for: containers[first]).location
        let end = NSMaxRange(layoutManager.glyphRange(for: containers[last]))
        let chars = layoutManager.characterRange(forGlyphRange: NSRange(location: start, length: end - start),
                                                 actualGlyphRange: nil)
        return (storage.string as NSString).substring(with: chars)
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Draws a screen page into the current graphics context.
    func draw(page: Int) {
        for (k, index) in containerIndices(forPage: page).enumerated() where k < geometry.origins.count {
            let glyphs = layoutManager.glyphRange(for: containers[index])
            guard glyphs.length > 0 else { continue }
            layoutManager.drawBackground(forGlyphRange: glyphs, at: geometry.origins[k])
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: geometry.origins[k])
        }
    }
}

extension BookTheme {
    var backgroundColor: UIColor {
        switch self {
        case .dark: return UIColor(white: 0.07, alpha: 1)
        case .sepia: return UIColor(red: 0.96, green: 0.92, blue: 0.83, alpha: 1)
        case .light: return UIColor(white: 0.98, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .dark: return UIColor(white: 0.86, alpha: 1)
        case .sepia: return UIColor(red: 0.27, green: 0.2, blue: 0.13, alpha: 1)
        case .light: return UIColor(white: 0.1, alpha: 1)
        }
    }

    var secondaryColor: UIColor { textColor.withAlphaComponent(0.6) }
}

/// Builds attributed text from parsed blocks and paginates it.
@MainActor
enum BookLayoutEngine {
    /// Upper bound on columns for one section, so a pathological section
    /// can't loop forever.
    static let maxContainers = 4000

    static func layout(_ section: BookSection, settings: BookSettings, viewport: CGSize,
                       images: [URL: UIImage]) -> BookSectionLayout {
        let geometry = BookPageGeometry.make(viewport: viewport, columns: settings.clampedColumns)
        let (text, offsets) = attributedText(section, settings: settings, columnSize: geometry.columnSize, images: images)
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var containers: [NSTextContainer] = []
        var emptyInARow = 0
        while containers.count < maxContainers {
            let container = NSTextContainer(size: geometry.columnSize)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            containers.append(container)
            let range = manager.glyphRange(for: container)
            if NSMaxRange(range) >= manager.numberOfGlyphs { break }
            // Something that can never fit (shouldn't happen: images are
            // sized to the column). Stop rather than spin.
            emptyInARow = range.length == 0 ? emptyInARow + 1 : 0
            if emptyInARow >= 3 { break }
        }
        return BookSectionLayout(section: section.index, storage: storage, layoutManager: manager,
                                 containers: containers, geometry: geometry, blockOffsets: offsets)
    }

    // MARK: Attributed text

    static func baseFont(_ settings: BookSettings, size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
        if settings.font == .serif, let serif = descriptor.withDesign(.serif) { descriptor = serif }
        if italic, let slanted = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) {
            descriptor = slanted
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func attributedText(_ section: BookSection, settings: BookSettings, columnSize: CGSize,
                               images: [URL: UIImage]) -> (NSAttributedString, [Int]) {
        let out = NSMutableAttributedString()
        var offsets: [Int] = []
        let size = CGFloat(settings.fontSize)
        let textColor = settings.theme.textColor

        func paragraphStyle(alignment: NSTextAlignment? = nil, spacingBefore: CGFloat = 0,
                            spacingAfter: CGFloat? = nil, indent: CGFloat = 0, firstIndent: CGFloat? = nil,
                            tail: CGFloat = 0, lineMultiple: Double? = nil) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = CGFloat(lineMultiple ?? settings.lineSpacing.multiple)
            p.paragraphSpacing = spacingAfter ?? size * 0.6
            p.paragraphSpacingBefore = spacingBefore
            p.alignment = alignment ?? (settings.justified ? .justified : .natural)
            p.hyphenationFactor = settings.justified ? 0.9 : 0.3
            p.headIndent = indent
            p.firstLineHeadIndent = firstIndent ?? indent
            p.tailIndent = -tail
            p.lineBreakMode = .byWordWrapping
            return p
        }

        func runs(_ runs: [TextRun], fontSize: CGFloat, bold: Bool = false, italic: Bool = false,
                  paragraph: NSParagraphStyle, color: UIColor? = nil) -> NSAttributedString {
            let color = color ?? textColor
            let result = NSMutableAttributedString()
            for run in runs {
                let s = run.style
                var runSize = fontSize
                var baseline: CGFloat = 0
                if s.contains(.raised) { runSize *= 0.7; baseline = fontSize * 0.33 }
                if s.contains(.lowered) { runSize *= 0.7; baseline = -fontSize * 0.15 }
                let font: UIFont
                if s.contains(.monospace) {
                    font = UIFont.monospacedSystemFont(ofSize: runSize * 0.9, weight: s.contains(.bold) || bold ? .semibold : .regular)
                } else {
                    font = baseFont(settings, size: runSize, bold: bold || s.contains(.bold), italic: italic != s.contains(.italic))
                }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
                ]
                if baseline != 0 { attributes[.baselineOffset] = baseline }
                if s.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if s.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let text = s.contains(.smallCaps) ? run.text.uppercased() : run.text
                result.append(NSAttributedString(string: text, attributes: attributes))
            }
            return result
        }

        for block in section.blocks {
            let isFirst = out.length == 0
            let piece: NSAttributedString
            switch block {
            case .heading(let level, let r, _):
                let scale: [CGFloat] = [1.6, 1.4, 1.25, 1.15, 1.05, 1.0]
                let hSize = size * scale[min(max(level, 1), 6) - 1]
                let p = paragraphStyle(alignment: .natural, spacingBefore: isFirst ? 0 : size * 1.2,
                                       spacingAfter: size * 0.8, lineMultiple: 1.15)
                piece = runs(r, fontSize: hSize, bold: true, paragraph: p)
            case .paragraph(let r, let alignment, _):
                let a: NSTextAlignment? = alignment == .center ? .center : alignment == .right ? .right : nil
                piece = runs(r, fontSize: size, paragraph: paragraphStyle(alignment: a))
            case .quote(let r, _):
                piece = runs(r, fontSize: size, paragraph: paragraphStyle(indent: size * 1.5, tail: size * 1.5))
            case .listItem(let marker, let depth, let r):
                let indent = CGFloat(max(1, depth)) * size * 1.6
                let p = NSMutableParagraphStyle()
                p.setParagraphStyle(paragraphStyle(alignment: .natural, spacingAfter: size * 0.3, indent: indent,
                                                   firstIndent: marker.isEmpty ? indent : indent - size * 1.2))
                p.tabStops = [NSTextTab(textAlignment: .natural, location: indent, options: [:])]
                let line = NSMutableAttributedString()
                if !marker.isEmpty {
                    line.append(NSAttributedString(string: marker + "\t", attributes: [
                        .font: baseFont(settings, size: size), .foregroundColor: textColor, .paragraphStyle: p,
                    ]))
                }
                line.append(runs(r, fontSize: size, paragraph: p))
                piece = line
            case .preformatted(let text):
                let p = paragraphStyle(alignment: .natural, lineMultiple: 1.1)
                piece = NSAttributedString(string: text, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: size * 0.8, weight: .regular),
                    .foregroundColor: textColor, .paragraphStyle: p,
                ])
            case .rule:
                piece = NSAttributedString(string: "*   *   *", attributes: [
                    .font: baseFont(settings, size: size), .foregroundColor: settings.theme.secondaryColor,
                    .paragraphStyle: paragraphStyle(alignment: .center, spacingBefore: size * 0.6, spacingAfter: size * 1.2),
                ])
            case .image(let url, let alt):
                if let image = images[url], image.size.width > 0, image.size.height > 0 {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    // Fit inside the column. Illustrations may be enlarged
                    // up to 2x; small ornaments stay their own size.
                    let w = image.size.width, h = image.size.height
                    let s = min(columnSize.width / w, columnSize.height * 0.92 / h, w < 200 ? 1 : 2)
                    attachment.bounds = CGRect(x: 0, y: 0, width: floor(w * s), height: floor(h * s))
                    let text = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                    text.addAttribute(.paragraphStyle,
                                      value: paragraphStyle(alignment: .center, spacingAfter: size * 0.6, lineMultiple: 1.0),
                                      range: NSRange(location: 0, length: text.length))
                    piece = text
                } else if let alt, !alt.isEmpty {
                    piece = runs([TextRun(alt, style: .italic)], fontSize: size * 0.85,
                                 paragraph: paragraphStyle(alignment: .center), color: settings.theme.secondaryColor)
                } else {
                    piece = NSAttributedString(string: "")
                }
            }
            guard piece.length > 0 else {
                offsets.append(out.length)
                continue
            }
            if out.length > 0 {
                // The paragraph break takes the attributes of the text it
                // ends, so it doesn't change that line's height.
                var attributes = out.attributes(at: out.length - 1, effectiveRange: nil)
                attributes.removeValue(forKey: .attachment)
                out.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            offsets.append(out.length)
            out.append(piece)
        }
        return (out, offsets)
    }
}
