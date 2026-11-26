import SwiftUI

/// A screen's title, drawn as the first part of its scrolling content.
///
/// On tvOS a `.navigationTitle` stays pinned while a Form inside a TabView
/// scrolls, so after scrolling down it ends up drawn over the rows. Settings
/// screens put this header in their Form instead, so the title scrolls away
/// with the content and comes back when focus returns to the top.
///
/// ```swift
/// Form {
///     ScreenTitle("Default Reader Settings")
///     Section("Reading") { … }
/// }
/// ```
struct ScreenTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Section {
        } header: {
            Text(text)
                .themedHeading(.title2, fallback: .title2.weight(.semibold))
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.title")
        }
    }
}
