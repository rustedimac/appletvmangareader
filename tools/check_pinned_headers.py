#!/usr/bin/env python3
"""Fails when a screen could pin a title or header over scrolling content.

tvOS keeps a `.navigationTitle` pinned while a Form or List scrolls, and a
header placed above a ScrollView with `.scrollClipDisabled()` has the rows
slide underneath it. Both drew text over the rows (Settings #26, reader menu
and Free Library #32). Rules for App/Sources:

1. No `.navigationTitle(`. Settings screens use `.settingsPage(title, ...)`
   (title in a side column, see docs/DESIGN_GUIDE.md); anything else puts its
   title inside the scrolling content (a plain header view).
2. `.scrollClipDisabled()` only on horizontal ScrollViews (shelves, tab bars),
   where focus growth would otherwise be clipped. A vertical scroll view must
   clip, or hold its header inside its content. To allow one anyway, end the
   line with `// pinned-header-ok: <reason>`.

Rule 1 is about tvOS. Code that only builds for iPhone/iPad, where large
navigation titles collapse into the bar as content scrolls (docs/IOS.md),
may use `.navigationTitle(`: lines inside an `#if os(iOS)` block, inside the
`#else` of an `#if os(tvOS)` block, or anywhere under App/Sources-iOS (which
this check doesn't scan). Rule 2 applies everywhere.

Run: python3 tools/check_pinned_headers.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Sources"
SCROLL = re.compile(r"\bScrollView\b\s*(\(([^)]*)\))?")

IF = re.compile(r"^\s*#if\b(.*)")
ELSEIF = re.compile(r"^\s*#elseif\b(.*)")


def ios_only_lines(lines):
    """Indexes of lines that only compile for iOS: inside `#if os(iOS)`, or
    inside the `#else` of `#if os(tvOS)`. Nested blocks inherit."""
    stack = []  # per open #if: is the current branch iOS-only?
    out = set()
    for i, line in enumerate(lines):
        stripped = line.strip()
        m = IF.match(line)
        if m:
            cond = m.group(1).replace(" ", "")
            parent = bool(stack and stack[-1][0])
            stack.append([parent or cond == "os(iOS)", cond])
            continue
        if ELSEIF.match(line) and stack:
            stack[-1][0] = bool(len(stack) > 1 and stack[-2][0])
            continue
        if stripped.startswith("#else") and stack:
            parent = bool(len(stack) > 1 and stack[-2][0])
            stack[-1][0] = parent or stack[-1][1] == "os(tvOS)"
            continue
        if stripped.startswith("#endif") and stack:
            stack.pop()
            continue
        if stack and stack[-1][0]:
            out.add(i)
    return out


errors = []
for path in sorted(ROOT.rglob("*.swift")):
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = path.relative_to(ROOT.parent.parent)
    ios_only = ios_only_lines(lines)
    for i, line in enumerate(lines):
        code = line.split("//", 1)[0]
        if ".navigationTitle(" in code and i not in ios_only:
            errors.append(f"{rel}:{i + 1}: .navigationTitle stays pinned over scrolling rows on tvOS; "
                          "use .settingsPage(...) or put the title inside the scrolling content")
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
