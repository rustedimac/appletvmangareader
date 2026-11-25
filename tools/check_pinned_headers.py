#!/usr/bin/env python3
"""Fails when a screen could pin a title or header over scrolling content.

tvOS keeps a `.navigationTitle` pinned while a Form or List scrolls, and a
header placed above a ScrollView with `.scrollClipDisabled()` has the rows
slide underneath it. Both drew text over the rows (Settings #26, reader menu
and Free Library #32). Rules for App/Sources:

1. No `.navigationTitle(`. Put `ScreenTitle("...")` first inside the Form or
   List (or as the first view in the ScrollView) so it scrolls with the rows.
2. `.scrollClipDisabled()` only on horizontal ScrollViews (shelves, tab bars),
   where focus growth would otherwise be clipped. A vertical scroll view must
   clip, or hold its header inside its content. To allow one anyway, end the
   line with `// pinned-header-ok: <reason>`.

Run: python3 tools/check_pinned_headers.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Sources"
SCROLL = re.compile(r"\bScrollView\b\s*(\(([^)]*)\))?")

errors = []
for path in sorted(ROOT.rglob("*.swift")):
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = path.relative_to(ROOT.parent.parent)
    for i, line in enumerate(lines):
        code = line.split("//", 1)[0]
        if ".navigationTitle(" in code:
            errors.append(f"{rel}:{i + 1}: .navigationTitle stays pinned over scrolling rows on tvOS; "
                          "use ScreenTitle(...) as the first item of the scrolling content")
        if ".scrollClipDisabled()" in code and "pinned-header-ok:" not in line:
            axis = None
            for j in range(i, -1, -1):
                m = SCROLL.search(lines[j].split("//", 1)[0])
                if m:
                    axis = m.group(2) or ""
                    break
            if axis is None or ".horizontal" not in axis:
                errors.append(f"{rel}:{i + 1}: .scrollClipDisabled() on a vertical ScrollView lets rows draw "
                              "over anything above it; drop it, move the header into the scroll content, "
                              "or add `// pinned-header-ok: <reason>`")

for e in errors:
    print(f"error: {e}")
if errors:
    print(f"\n{len(errors)} pinned-header problem(s). See tools/check_pinned_headers.py for the rules.")
    sys.exit(1)
print("No pinned headers over scrolling content.")
