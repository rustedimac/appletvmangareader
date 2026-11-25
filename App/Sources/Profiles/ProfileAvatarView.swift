import SwiftUI
import MangaCore

/// The app's avatar colors. `Profile.colorIndex` wraps around this list.
enum ProfileColors {
    static let palette: [Color] = [
        Color(red: 0.90, green: 0.30, blue: 0.24), // red
        Color(red: 0.20, green: 0.52, blue: 0.92), // blue
        Color(red: 0.18, green: 0.68, blue: 0.42), // green
        Color(red: 0.96, green: 0.65, blue: 0.14), // amber
        Color(red: 0.58, green: 0.35, blue: 0.85), // purple
        Color(red: 0.10, green: 0.66, blue: 0.70), // teal
        Color(red: 0.93, green: 0.38, blue: 0.62), // pink
        Color(red: 0.45, green: 0.48, blue: 0.53), // slate
    ]

    static func color(_ index: Int) -> Color {
        let n = palette.count
        return palette[((index % n) + n) % n]
    }
}

/// A rounded-square avatar with the profile's symbol on its color.
struct ProfileAvatarView: View {
    let symbol: String
    let colorIndex: Int
    var size: CGFloat = 200

    init(profile: Profile, size: CGFloat = 200) {
        self.symbol = profile.symbol
        self.colorIndex = profile.colorIndex
        self.size = size
    }

    init(symbol: String, colorIndex: Int, size: CGFloat = 200) {
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(ProfileColors.color(colorIndex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Lifts and outlines a profile tile when it has focus, like the tvOS
/// system profile pickers.
struct ProfileTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration)
    }

    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.1 : 1.0))
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 20, y: 12)
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
