#!/usr/bin/env python3
"""Fails when a screen other than the server form has a Save button.

Settings apply as soon as they change (docs/DESIGN_GUIDE.md, "No Save
buttons"). Only the server add/edit form keeps Save, because it tests the
address and login and stores the credential. Rules for App/Sources:

1. No string literal "Save", "Save Changes", "Apply" or "Done" (button
   labels) outside the allowed files.
2. No accessibility identifier ending in ".save" outside the allowed files.

Alert buttons ("OK", "Cancel") are fine. To allow a line anyway, end it with
`// save-button-ok: <reason>`.

Run: python3 tools/check_save_buttons.py   (CI runs it on every PR)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "App" / "Sources"
ALLOWED = {"Settings/ServerEditorView.swift"}
LABEL = re.compile(r'"(Save|Save Changes|Apply|Done)"')
SAVE_ID = re.compile(r'"[A-Za-z0-9_.]*\.save"')


def strip_comment(line: str) -> str:
    """Drops a trailing // comment that isn't inside a string literal."""
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_string:
            i += 2
            continue
        if c == '"':
            in_string = not in_string
        elif not in_string and line.startswith("//", i):
            return line[:i]
        i += 1
    return line


errors = []
for path in sorted(ROOT.rglob("*.swift")):
    rel = path.relative_to(ROOT).as_posix()
    if rel in ALLOWED:
        continue
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "save-button-ok:" in line:
            continue
        code = strip_comment(line)
        if code.lstrip().startswith("///"):
            continue
        m = LABEL.search(code) or SAVE_ID.search(code)
        if m:
            errors.append(f"App/Sources/{rel}:{n}: {m.group(0)}: no Save/Apply/Done buttons outside the server "
                          "form; apply the change as it's made (docs/DESIGN_GUIDE.md, \"No Save buttons\")")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"No Save buttons outside {', '.join(sorted(ALLOWED))}.")
