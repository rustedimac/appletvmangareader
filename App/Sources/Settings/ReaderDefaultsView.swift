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
                Picker("Mode", selection: settings.mode) {
                    ForEach(ReadingMode.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("readerDefaults.mode")
                Picker("Direction", selection: settings.direction) {
                    ForEach(ReadingDirection.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("readerDefaults.direction")
                Picker("Background", selection: settings.background) {
                    ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Picker("Pages", selection: settings.layout) {
                    ForEach(PageLayout.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("readerDefaults.layout")
                Toggle("Show first page alone", isOn: settings.firstPageAlone)
            } header: {
                SettingsHeader("Paged")
            } footer: {
                Text("The first page is usually the cover, so showing it alone keeps the spreads that follow paired correctly.")
            }

            Section(settingsHeader: "Vertical Scroll") {
                Picker("Column width", selection: settings.webtoonWidth) {
                    ForEach(Self.options(Self.widths, current: model.defaultReaderSettings.webtoonWidth), id: \.self) {
                        Text(Self.percent($0)).tag($0)
                    }
                }
                Picker("Scroll per click", selection: settings.webtoonScrollStep) {
                    ForEach(Self.options(Self.steps, current: model.defaultReaderSettings.webtoonScrollStep), id: \.self) {
                        Text("\(Self.percent($0)) of the screen").tag($0)
                    }
                }
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
