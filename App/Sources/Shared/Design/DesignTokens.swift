import SwiftUI

// Design tokens for the tvOS app. See docs/DESIGN_GUIDE.md for when to use
// each one. Values are points on the 1920 × 1080 tvOS canvas.

/// Screen margins. SwiftUI already applies the safe area; use these only in
/// views that call `.ignoresSafeArea()`.
enum Layout {
    /// HIG: inset primary content 60 pt from the top and bottom.
    static let safeTop: CGFloat = 60
    static let safeBottom: CGFloat = 60
    /// HIG: inset primary content 80 pt from the sides.
    static let safeSide: CGFloat = 80
    /// The width left for content inside the side margins.
    static let safeWidth: CGFloat = 1920 - 2 * safeSide
}

/// Spacing scale on an 8 pt grid.
enum Space {
    /// Title to its subtitle inside one row.
    static let xxs: CGFloat = 4
    /// Icon to badge, tight label pairs.
    static let xs: CGFloat = 8
    /// Items inside one control.
    static let s: CGFloat = 16
    /// Rows in a custom list; a label and its control.
    static let m: CGFloat = 24
    /// Focusable items side by side (HIG grid spacing); buttons in a row.
    static let l: CGFloat = 40
    /// Sections of a page.
    static let xl: CGFloat = 60
    /// Major regions, e.g. the hero column and the form column.
    static let xxl: CGFloat = 80
}

/// Corner radii for custom shapes. System controls keep their own shape.
enum Radius {
    /// Small highlights inside a control: a focused jump-bar letter, a
    /// format badge on a poster.
    static let small: CGFloat = 8
    static let poster: CGFloat = 12
    static let card: CGFloat = 20
    static let panel: CGFloat = 32
}

enum Size {
    /// Minimum height of anything focusable.
    static let minTarget: CGFloat = 66
    /// Text buttons stay at least this wide so short labels aren't stubby.
    static let buttonMinWidth: CGFloat = 240
    /// …and no wider than this, so long labels don't turn into bars.
    static let buttonMaxWidth: CGFloat = 760
    /// Max width of a settings form column.
    static let formColumn: CGFloat = 1000
    /// Width of the icon column beside a settings form.
    static let heroColumn: CGFloat = 600
    /// Hero symbol size in that column.
    static let heroSymbol: CGFloat = 240
    /// Max width of a free-standing text field.
    static let textField: CGFloat = 800
    /// Max line length for long text (about 80 characters of body text).
    static let readableText: CGFloat = 1100
    /// Max width of empty-state and error messages.
    static let messageText: CGFloat = 900
    /// Width reserved for a leading row icon so labels line up.
    static let icon: CGFloat = 50
    /// Profile avatar and icon column inside a row. Small enough that a row
    /// with an avatar is no taller than a two-line text row.
    static let avatarRow: CGFloat = 52
}

/// The HIG seven-column grid: 217 pt items, 40 pt apart, across the
/// 1,760 pt safe width.
enum Grid {
    static let posterWidth: CGFloat = 217
    static var posterHeight: CGFloat { posterWidth * 1.5 }
    static let columnSpacing: CGFloat = 40
    /// Poster bottom to the next poster's top, caption included (HIG: ≥ 100).
    static let rowSpacing: CGFloat = 100
}
