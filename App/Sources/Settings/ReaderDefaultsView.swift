import SwiftUI
import MangaCore

/// The active profile's default reader settings. Series that were changed
/// from the in-reader menu keep their own settings.
struct ReaderDefaultsView: View {
    @Environment(AppModel.self) private var model

    private static let widths: [Double] = [0.4, 0.5, 0.6, 0.75, 0.9, 1.0]
    private static let steps: [Double] = [0.5, 0.75, 0.9]

    private var settings: Binding<ReaderSettings> {
        Binding(get: { model.defaultReaderSettings }, set: { model.setDefaultReaderSettings($0) })
    }

    var body: some View {
        Form {
            Section(settingsHeader: "Reading") {
                SettingsPicker("Mode", selection: settings.mode, options: ReadingMode.allCases,
                               systemImage: "book") { $0.title }
                    .accessibilityIdentifier("readerDefaults.mode")
                SettingsPicker("Direction", selection: settings.direction, options: ReadingDirection.allCases,
                               systemImage: "arrow.left.arrow.right") { $0.title }
                    .accessibilityIdentifier("readerDefaults.direction")
                SettingsPicker("Background", selection: settings.background, options: ReaderBackground.allCases,
                               systemImage: "circle.lefthalf.filled") { $0.title }
                    .accessibilityIdentifier("readerDefaults.background")
            }

            Section {
                SettingsPicker("Pages", selection: settings.layout, options: PageLayout.allCases,
                               systemImage: "book.pages") { $0.title }
                    .accessibilityIdentifier("readerDefaults.layout")
                Toggle("Show first page alone", isOn: settings.firstPageAlone)
                    .accessibilityIdentifier("readerDefaults.firstPageAlone")
                SettingsPicker("Page fit", selection: settings.fit, options: PageFit.allCases,
                               systemImage: "arrow.up.left.and.arrow.down.right") { $0.title }
                    .accessibilityIdentifier("readerDefaults.fit")
                Toggle("Crop borders", isOn: settings.cropBorders)
                    .accessibilityIdentifier("readerDefaults.cropBorders")
                SettingsPicker("Click to zoom", selection: settings.zoomScale,
                               options: Self.options(ReaderMenuOptions.zoomScales,
                                                     current: model.defaultReaderSettings.zoomScale),
                               systemImage: "plus.magnifyingglass") { ReaderMenuOptions.zoomLabel($0) }
                    .accessibilityIdentifier("readerDefaults.zoomScale")
            } header: {
                SettingsHeader("Paged")
            } footer: {
                Text("The first page is usually the cover, so showing it alone keeps the spreads that follow paired correctly. Crop borders trims white or black margins. Fit Width fills the screen's width and scrolls with up and down. Click while reading to zoom; press Menu to zoom out.")
            }

            Section(settingsHeader: "Vertical Scroll") {
                SettingsPicker("Column width", selection: settings.webtoonWidth,
                               options: Self.options(Self.widths, current: model.defaultReaderSettings.webtoonWidth),
                               systemImage: "arrow.left.and.right") { Self.percent($0) }
                    .accessibilityIdentifier("readerDefaults.webtoonWidth")
                SettingsPicker("Scroll per click", selection: settings.webtoonScrollStep,
                               options: Self.options(Self.steps, current: model.defaultReaderSettings.webtoonScrollStep),
                               systemImage: "arrow.down.to.line") { "\(Self.percent($0)) of the screen" }
                    .accessibilityIdentifier("readerDefaults.webtoonScrollStep")
            }

            Section {
                Button("Reset to Defaults") { model.setDefaultReaderSettings(.default) }
                    .accessibilityIdentifier("readerDefaults.reset")
            } footer: {
                Text("Changes made while reading are saved for that series and win over these defaults.")
            }
        }
        .settingsPage("Default Reader Settings", systemImage: "book")
    }

    /// Preset values, plus the current one if it isn't a preset, so the
    /// picker always has a matching row.
    private static func options(_ presets: [Double], current: Double) -> [Double] {
        presets.contains(current) ? presets : (presets + [current]).sorted()
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
