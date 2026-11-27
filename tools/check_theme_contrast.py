#!/usr/bin/env python3
"""Checks that every text color a theme uses passes WCAG contrast on the
fill it is drawn on, in both appearances.

ThemeStyle.of(_:) (App/Sources/Shared/Design/ThemeStyle.swift) picks each
role from a Theme Lab palette as `role: p.token`. This reads those picks,
resolves each token in the generated palette
(Packages/Themes/<Name>Theme/Sources/<Name>Theme/<Name>Theme.swift) for the
light and the dark variant, and checks the pairs below. A role that is a
fill must be opaque: text over a translucent fill can't be checked here.

Run: python3 tools/check_theme_contrast.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
STYLE = REPO / "App" / "Sources" / "Shared" / "Design" / "ThemeStyle.swift"
THEMES = REPO / "Packages" / "Themes"

# (text role, fill role, minimum ratio). Body text 4.5:1; headings are large
# (3:1 would do) but are held to 4.5:1 too.
PAIRS = [
    ("text.primary", "background", 4.5),
    ("text.secondary", "background", 4.5),
    ("heading", "background", 4.5),
    ("sectionLabel", "background", 4.5),
    ("plateText", "plate", 4.5),
    ("plateSecondary", "plate", 4.5),
    ("focusText", "focus", 4.5),
    ("selectedText", "selected", 4.5),
]
# Fills a person must tell apart from the ground (non-text, 3:1 is the
# WCAG bar for UI parts; a focused plate also lifts and grows).
UI_PAIRS = [
    ("focus", "background", 3.0),
]
FILLS = {"background", "plate", "focus", "selected"}


def parse_palette(path):
    """token -> {"light": (r, g, b, a), "dark": (r, g, b, a)}"""
    text = path.read_text()
    num = r"([0-9.]+)"
    tup = rf"\(\s*{num},\s*{num},\s*{num},\s*{num}\s*\)"
    out = {}
    for m in re.finditer(rf"(\w+): dynamic\(light: {tup}, dark: {tup}\)", text):
        vals = [float(v) for v in m.groups()[1:]]
        out.setdefault(m.group(1), {"light": tuple(vals[:4]), "dark": tuple(vals[4:])})
    return out


def luminance(rgb):
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def theme_blocks(source):
    """(cases, module, body) for each themed `case` in ThemeStyle.of."""
    blocks = []
    pattern = re.compile(r"case ((?:\.\w+,?\s*)+):\s*\n(.*?)(?=\n\s*case \.|\n\s*}\n)", re.S)
    for m in pattern.finditer(source):
        body = m.group(2)
        module = re.search(r"(\w+)Theme\.palette\(\)", body)
        if not module:
            continue
        cases = re.findall(r"\.(\w+)", m.group(1))
        blocks.append((cases, module.group(1), body))
    return blocks


def roles(body):
    found = {name: token for name, token in re.findall(r"(\w+): p\.(\w+)", body)}
    text = re.search(r"text: \(p\.(\w+), p\.(\w+)\)", body)
    if text:
        found["text.primary"], found["text.secondary"] = text.groups()
    return found


def light_cases():
    """Theme cases that use the light appearance (AppTheme.isLight)."""
    src = (REPO / "Packages/MangaCore/Sources/MangaCore/Browse/AppTheme.swift").read_text()
    m = re.search(r"var isLight: Bool \{.*?case ([^:]+): return true", src, re.S)
    return set(re.findall(r"\.(\w+)", m.group(1))) if m else set()


def main():
    source = STYLE.read_text()
    light = light_cases()
    problems = []
    checked = 0
    blocks = theme_blocks(source)
    if not blocks:
        problems.append("found no themed cases in ThemeStyle.of(_:)")
    for cases, module, body in blocks:
        palette_file = THEMES / f"{module}Theme" / "Sources" / f"{module}Theme" / f"{module}Theme.swift"
        palette = parse_palette(palette_file)
        picked = roles(body)
        for case in cases:
            variant = "light" if case in light else "dark"
            def color(role):
                token = picked.get(role)
                if token is None:
                    return None
                if token not in palette:
                    problems.append(f"{case}: {role} uses p.{token}, which {module}Theme has no color for")
                    return None
                return palette[token][variant]
            for role in FILLS:
                c = color(role)
                if c is not None and c[3] < 1:
                    problems.append(f"{case}: {role} (p.{picked[role]}) is translucent; text on it can't be checked")
            for fg, bg, minimum in PAIRS + UI_PAIRS:
                a, b = color(fg), color(bg)
                if a is None or b is None:
                    continue
                checked += 1
                r = ratio(a, b)
                if r < minimum:
                    problems.append(f"{case} ({variant}): {fg} p.{picked[fg]} on {bg} p.{picked[bg]} "
                                    f"is {r:.2f}:1, needs {minimum}:1")
    for p in problems:
        print(f"check_theme_contrast: {p}")
    if problems:
        return 1
    print(f"check_theme_contrast: {checked} pairs pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
