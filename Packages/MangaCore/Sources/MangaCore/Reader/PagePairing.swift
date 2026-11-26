import Foundation

/// Two-page pairing has one user-facing control: First Page Alone.
///
/// Earlier builds also had "Pages paired wrong? Shift by one". It flipped the
/// same thing (whether page 1 stands alone), because `SpreadLayout` only
/// ever looked at `firstPageAlone != shift`, and both were saved per series.
/// So the two controls could cancel each other out ("On" + "Shifted" looked
/// like Off). `shiftPairing` stays in the saved format for older builds and
/// iCloud peers, but it is folded into `firstPageAlone` on read and write and
/// is always `false` in anything this build saves.
public extension ReaderSettings {
    /// Whether the chapter's first page is shown alone, counting a shift
    /// saved by an older build.
    var showsFirstPageAlone: Bool { firstPageAlone != shiftPairing }

    /// A copy with First Page Alone set and the old shift flag cleared.
    func withFirstPageAlone(_ alone: Bool) -> ReaderSettings {
        var copy = self
        copy.firstPageAlone = alone
        copy.shiftPairing = false
        return copy
    }

    /// The same layout, with any old shift folded into `firstPageAlone`.
    var normalizedPairing: ReaderSettings { withFirstPageAlone(showsFirstPageAlone) }
}
