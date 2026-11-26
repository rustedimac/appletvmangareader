#!/usr/bin/env python3
"""Keep docs/TESTING_GUIDE.md in step with the tests.

Fails when a UI test class (App/UITests/*UITests.swift) or a MangaCore test
file (Packages/MangaCore/Tests/**/*Tests.swift) isn't named in the guide,
when a check ID is used twice, or when a check row has no pass criterion.
See docs/TESTING_GUIDE.md, "Keeping this guide current".
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs" / "TESTING_GUIDE.md"

ROW = re.compile(r"^\|\s*([A-Z0-9]+-\d{2})\s*\|\s*([ASD])\s*\|(.*)$")


def main() -> int:
    text = GUIDE.read_text(encoding="utf-8")
    errors = []

    tests = sorted(p.stem for p in (ROOT / "App" / "UITests").glob("*UITests.swift"))
    tests += sorted(p.stem for p in (ROOT / "Packages" / "MangaCore" / "Tests").rglob("*Tests.swift"))
    for name in tests:
        if not re.search(rf"`{re.escape(name)}`", text):
            errors.append(f"{name} is not named in docs/TESTING_GUIDE.md (add it to a row's 'Covered by')")

    seen = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        m = ROW.match(line)
        if not m:
            continue
        check_id, _, rest = m.groups()
        if check_id in seen:
            errors.append(f"line {lineno}: {check_id} already used on line {seen[check_id]}")
        seen[check_id] = lineno
        cells = [c.strip() for c in rest.split("|")]
        # cells: check, pass when, covered by, (trailing empty)
        if len(cells) < 3 or not cells[0] or not cells[1] or not cells[2]:
            errors.append(f"line {lineno}: {check_id} needs a check, a 'Pass when' and a 'Covered by'")

    if not seen:
        errors.append("no check rows found in docs/TESTING_GUIDE.md")
    for e in errors:
        print(f"error: {e}")
    if not errors:
        print(f"testing guide OK: {len(seen)} checks, {len(tests)} test classes/files named")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
