import SwiftUI

extension View {
    /// Marks a button as the open item of its group (the category on
    /// screen): the system button tints it with the accent color.
    func controlSelected(_ isSelected: Bool) -> some View {
        tint(isSelected ? Color.accentColor : nil)
    }

    /// A check mark or similar "this one is on" glyph: the accent color when
    /// on, secondary when off.
    func checkMarkStyle(_ isOn: Bool) -> some View {
        foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
}
