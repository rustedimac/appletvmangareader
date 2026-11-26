#!/usr/bin/env python3
"""Fails when a per-series reader setting has no global default.

Rule (John, 2026-11-25; docs/DESIGN_GUIDE.md "Setting scopes"): every setting
a series can override also has a profile-wide default, and the series value
only overrides it. Reader settings are one struct, `ReaderSettings`, saved
per series from the reader menu, so every stored field of it must be
editable in Default Reader Settings (`ReaderDefaultsView` binds it as
`settings.<field>`).

A field that is a fix for one book rather than a preference (for example
shifting the page pairing by one) may be exempt: list it in EXEMPT with the
reason.

Run: python3 tools/check_setting_scopes.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SETTINGS = REPO / "Packages/MangaCore/Sources/MangaCore/Reader/ReaderSettings.swift"
DEFAULTS_VIEW = REPO / "App/Sources/Settings/ReaderDefaultsView.swift"

EXEMPT = {
    "shiftPairing": "retired: folded into firstPageAlone (PagePairing.swift) and always saved false; kept only so older saves decode",
}


def stored_fields(source: str, struct: str) -> list[str]:
    """Stored `var`s declared directly in `struct` (computed ones skipped)."""
    start = re.search(rf"\bstruct {struct}\b[^{{]*{{", source)
    if not start:
        sys.exit(f"error: struct {struct} not found in {SETTINGS.relative_to(REPO)}")
    depth, i, body_start = 1, start.end(), start.end()
    while depth and i < len(source):
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        i += 1
    body = source[body_start:i - 1]
    fields, depth = [], 0
    for line in body.splitlines():
        code = line.split("//", 1)[0]
        if depth == 0:
            m = re.match(r"\s*(?:public\s+)?var\s+(\w+)\s*:\s*[^{=]+(=.*)?$", code)
            if m and "{" not in code:
                fields.append(m.group(1))
        depth += code.count("{") - code.count("}")
    return fields


fields = stored_fields(SETTINGS.read_text(encoding="utf-8"), "ReaderSettings")
view = DEFAULTS_VIEW.read_text(encoding="utf-8")
missing = [f for f in fields if f not in EXEMPT and not re.search(rf"\bsettings\.{f}\b", view)]
stale = [f for f in EXEMPT if f not in fields]

for f in missing:
    print(f"error: ReaderSettings.{f} can be set per series but has no row in Default Reader Settings "
          f"({DEFAULTS_VIEW.relative_to(REPO)}). Add one, or exempt it in tools/check_setting_scopes.py "
          "with a reason.")
for f in stale:
    print(f"note: EXEMPT lists {f}, which ReaderSettings no longer has; remove it.")
if missing:
    sys.exit(1)
print(f"All {len(fields)} reader settings have a global default ({len(EXEMPT)} exempt).")
