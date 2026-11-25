import SwiftUI
import MangaCore

/// A column of letters beside a title-sorted grid. Press right from the
/// grid to reach it, move up and down, and click a letter to jump there.
struct AlphabetJumpBar: View {
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AlphabetIndex.letters, id: \.self) { letter in
                Button {
                    onPick(letter)
                } label: {
                    Text(letter)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 48, height: 28)
                }
                .buttonStyle(LetterButtonStyle())
                .accessibilityLabel(letter == "#" ? "Numbers and symbols" : letter)
                .accessibilityIdentifier("library.jump.\(letter)")
            }
        }
        .padding(.vertical, 10)
        .padding(.trailing, 10)
        .focusSection()
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
                .background(RoundedRectangle(cornerRadius: 8).fill(isFocused ? Color.white : Color.clear))
                .scaleEffect(isFocused ? 1.3 : (configuration.isPressed ? 0.95 : 1))
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }
}
