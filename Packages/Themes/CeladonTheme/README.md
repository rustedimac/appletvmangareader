# Celadon for Apple platforms

Generated from theme-lab `themes/celadon/` by `scripts/export_apple.py`. Don't edit; re-export.

## SwiftUI

Add this folder as a local Swift package (File > Add Package Dependencies > Add Local), then:

```swift
import CeladonTheme

struct ContentView: View {
    @Environment(\.colorScheme) private var appearance
    let palette = CeladonTheme.palette()             // default scheme: Celadon
    var body: some View {
        let platform = CeladonTheme.currentPlatform
        let m = CeladonTheme.metrics(platform)
        VStack(alignment: .leading, spacing: 8 * m.spaceScale) {
            Text("Portfolio").celadonText(.display, platform: platform)
        }
        .padding(.horizontal, m.gutter)
        .foregroundStyle(palette.ink)
        .tint(palette.tint)
    }
}
```

- **Appearance**: every `Palette` color switches between the scheme's light and dark variant with the system. Schemes with one appearance: `CeladonTheme.lockedAppearance(scheme)` returns it; apply `.preferredColorScheme(...)`.
- **Type**: `CeladonTheme.font(_:_:)` uses `Font.custom(_:size:relativeTo:)`, so it follows Dynamic Type. Bundle the font files listed in `tokens.apple.json` (`families`) and register them; otherwise the system face is used.
- **Metrics**: `CeladonTheme.metrics(CeladonTheme.currentPlatform)` gives targets, gutters, bar heights, focus scale, blur and motion for iOS, iPadOS, macOS, tvOS and watchOS.
- **Material**: `.celadonMaterial(palette, blur: m.materialBlur)` on bars and sheets; it turns opaque under Reduce Transparency.
- **tvOS focus**: on focus, scale by `m.focusScale`, fill `palette.focusSurface`, text `palette.onFocusSurface`, animate over `m.motion` seconds (skip the animation under Reduce Motion).

## Other toolkits

`tokens.apple.json` has everything resolved: `colors[variant][token]` as `#rrggbbaa`, `schemes` (light/dark variant ids), `platforms[platform][key]` (CSS-style strings: px = points, ms), `type[platform][style]` (family, size, lineHeight, weight, tracking, Apple textStyle), and the spacing, radius and shadow scales.
