#!/usr/bin/env python3
"""Secure fields keep the system tvOS look (docs/DESIGN_GUIDE.md, Text fields).

A plain SwiftUI SecureField already draws the same dots as Apple's own
Settings app (measured 2026-11-26: 33-34 px dots at 4K, same as Settings).
A font modifier shrinks them (.font(.body) gave 25 px) and a UIKit wrapper
greys them out, so neither is allowed on a SecureField. Exceptions take a
`// design-ok: <reason>` comment on the SecureField line.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FORBIDDEN = re.compile(r"^\s*\.(font|fontDesign|fontWidth|dynamicTypeSize|scaleEffect)\(")


def check(path: pathlib.Path) -> list[str]:
    errors = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if "SecureField(" not in line or "design-ok" in line:
            continue
        depth = line.count("(") - line.count(")")
        j = i + 1
        # Walk the SecureField's argument lines, then its modifier chain.
        while j < len(lines) and depth > 0:
            depth += lines[j].count("(") - lines[j].count(")")
            j += 1
        while j < len(lines) and lines[j].lstrip().startswith("."):
            if FORBIDDEN.match(lines[j]):
                errors.append(f"{path.relative_to(ROOT)}:{j + 1}: {lines[j].strip()} on a SecureField "
                              "changes the system dots; use a plain SecureField")
            j += 1
    if "isSecureTextEntry" in path.read_text(encoding="utf-8"):
        errors.append(f"{path.relative_to(ROOT)}: UIKit isSecureTextEntry field; use SwiftUI SecureField")
    return errors


def main() -> int:
    errors = [e for p in sorted((ROOT / "App").rglob("*.swift")) if "UITests" not in p.parts for e in check(p)]
    for e in errors:
        print(e)
    if errors:
        return 1
    print("Secure fields use the system look.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
