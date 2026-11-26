#!/usr/bin/env python3
"""Fails when a setting is drawn as side-by-side option chips, or when a
chip or row label can wrap.

John (2026-11-26): settings must look like settings rows (name on the left,
value on the right, a chevron opening the choices), and buttons side by
side must never have different heights because one label wraps. See
docs/DESIGN_GUIDE.md, "Value rows outside a form". Rules for App/Sources:

1. `OptionButton(` (a radio chip) only in the files allowed below. A
   setting in a menu or settings page uses `PanelValueRow`,
   `SettingsPicker` or a `Toggle`; sections use `SectionTabBar`.
2. The radio glyph pair `"checkmark.circle.fill" : "circle"` only inside
   `OptionButton` itself or on a line marked `// option-chip-ok: <reason>`
   (a full-width checklist row, for example).
3. `OptionButton`, `PanelChoiceList` and `SettingsValueRow` (inside every
   `PanelValueRow` and `SettingsPicker`) keep `lineLimit(1)` on their labels,
   so a label never wraps to a second
   line and grows its platter.

The layout UI test (DesignLayoutUITests, `assertUniformRowHeights`) checks
the rendered result: focusable items side by side share one height.

Run: python3 tools/check_option_chips.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Sources"
# The Favorites sort toggle sits beside the grid, like a toolbar.
CHIP_ALLOWED = {"Favorites/FavoritesView.swift"}
GLYPH = re.compile(r'"checkmark\.circle\.fill"\s*:\s*"circle"')
# Components whose labels must stay on one line, and the file they live in.
ONE_LINE = {
    "Reader/Menu/ReaderMenu.swift": ["struct OptionButton"],
    "Shared/Design/PanelRows.swift": ["struct PanelChoiceList"],
    "Shared/Design/SettingsPicker.swift": ["struct SettingsValueRow"],
}

errors = []


def body_of(text: str, marker: str) -> str:
    """The source of the type that starts at `marker`, by brace matching."""
    start = text.find(marker)
    if start < 0:
        return ""
    open_at = text.find("{", start)
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]


for path in sorted(ROOT.rglob("*.swift")):
    rel = path.relative_to(ROOT).as_posix()
    text = path.read_text(encoding="utf-8")
    option_button = body_of(text, "struct OptionButton")
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split("//")[0] if not line.lstrip().startswith("///") else ""
        if "OptionButton(" in code and rel not in CHIP_ALLOWED:
            errors.append(f"App/Sources/{rel}:{n}: OptionButton chips are only for the Favorites sort; use "
                          "PanelValueRow / SettingsPicker for a setting or SectionTabBar for sections "
                          "(docs/DESIGN_GUIDE.md, \"Value rows outside a form\")")
        if GLYPH.search(code) and "option-chip-ok:" not in line and line.strip() not in option_button:
            errors.append(f"App/Sources/{rel}:{n}: radio-chip glyphs; draw the setting as a value row "
                          "(or mark a full-width checklist row with // option-chip-ok: <reason>)")

for rel, markers in ONE_LINE.items():
    path = ROOT / rel
    if not path.exists():
        errors.append(f"App/Sources/{rel}: missing (tools/check_option_chips.py expects it)")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        body = body_of(text, marker)
        if not body:
            errors.append(f"App/Sources/{rel}: no {marker}")
        elif "lineLimit(1)" not in body:
            errors.append(f"App/Sources/{rel}: {marker} must keep lineLimit(1) on its labels so side-by-side "
                          "platters share one height")

if errors:
    print("\n".join(errors))
    print(f"\n{len(errors)} problem(s). See docs/DESIGN_GUIDE.md, \"Value rows outside a form\".")
    sys.exit(1)
print("Option chips: OK")
