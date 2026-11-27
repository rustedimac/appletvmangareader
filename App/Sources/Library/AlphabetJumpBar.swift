import SwiftUI
import MangaCore

/// A column of letters beside a title-sorted grid. Press right from the
/// grid to reach it, move up and down, and click a letter to jump there.
struct AlphabetJumpBar: View {
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: platformValue(tv: 2, touch: 0)) {
            ForEach(AlphabetIndex.letters, id: \.self) { letter in
                Button {
                    onPick(letter)
                } label: {
                    #if os(tvOS)
                    Text(letter)
                        .font(.system(size: 23, weight: .semibold)) // design-ok: fixed 28 pt rows so 27 letters fit; 23 pt is the HIG minimum
                        .frame(width: 48, height: 28)
                    #else
                    // Like the iOS section index: small letters in a narrow column.
                    Text(letter)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 16)
                    #endif
                }
                .buttonStyle(LetterButtonStyle())
                .accessibilityLabel(letter == "#" ? "Numbers and symbols" : letter)
                .accessibilityIdentifier("library.jump.\(letter)")
            }
        }
        .padding(.vertical, platformValue(tv: 10, touch: Space.xs))
        .padding(.trailing, platformValue(tv: 10, touch: 0))
        .tvFocusSection()
    }
}

/// A small letter that turns into a white chip when focused.
private struct LetterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LetterLabel(configuration: configuration)
    }

    private struct LetterLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.secondary)
                .background(RoundedRectangle(cornerRadius: Radius.small).fill(isFocused ? Color.white : Color.clear))
                .scaleEffect(isFocused ? 1.3 : (configuration.isPressed ? 0.95 : 1))
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }
}
