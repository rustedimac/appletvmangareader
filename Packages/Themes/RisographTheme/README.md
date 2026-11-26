# Risograph for Apple platforms

Generated from theme-lab `themes/risograph/` by `scripts/export_apple.py`. Don't edit; re-export.

## SwiftUI

Add this folder as a local Swift package (File > Add Package Dependencies > Add Local), then:

```swift
import RisographTheme

struct ContentView: View {
    @Environment(\.colorScheme) private var appearance
    let palette = RisographTheme.palette()             // default scheme: Risograph
    var body: some View {
        let platform = RisographTheme.currentPlatform
        let m = RisographTheme.metrics(platform)
        VStack(alignment: .leading, spacing: 8 * m.spaceScale) {
            Text("Portfolio").risographText(.display, platform: platform)
        }
        .padding(.horizontal, m.gutter)
        .foregroundStyle(palette.ink)
        .tint(palette.tint)
    }
}
```

- **Appearance**: every `Palette` color switches between the scheme's light and dark variant with the system. Schemes with one appearance: `RisographTheme.lockedAppearance(scheme)` returns it; apply `.preferredColorScheme(...)`.
- **Type**: `RisographTheme.font(_:_:)` uses `Font.custom(_:size:relativeTo:)`, so it follows Dynamic Type. Bundle the font files listed in `tokens.apple.json` (`families`) and register them; otherwise the system face is used.
- **Metrics**: `RisographTheme.metrics(RisographTheme.currentPlatform)` gives targets, gutters, bar heights, focus scale, blur and motion for iOS, iPadOS, macOS, tvOS and watchOS.
- **Material**: `.risographMaterial(palette, blur: m.materialBlur)` on bars and sheets; it turns opaque under Reduce Transparency.
- **tvOS focus**: on focus, scale by `m.focusScale`, fill `palette.focusSurface`, text `palette.onFocusSurface`, animate over `m.motion` seconds (skip the animation under Reduce Motion).

## Other toolkits

`tokens.apple.json` has everything resolved: `colors[variant][token]` as `#rrggbbaa`, `schemes` (light/dark variant ids), `platforms[platform][key]` (CSS-style strings: px = points, ms), `type[platform][style]` (family, size, lineHeight, weight, tracking, Apple textStyle), and the spacing, radius and shadow scales.
