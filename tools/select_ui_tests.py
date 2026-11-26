#!/usr/bin/env python3
"""Print the xcodebuild -only-testing arguments for a PR's UI test run.

Usage: select_ui_tests.py <base-commit>   (CI passes HEAD^1 of the PR merge commit)

PRs run the smoke classes in tools/ui_smoke_tests.txt plus every UI test
class whose file the PR changes or adds. Prints nothing (meaning: run the
full suite) when the PR touches something every UI test depends on.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = "MangaReaderUITests"
UITESTS = "App/UITests/"
# Changes here can break any UI test, so they get the full suite.
FULL_SUITE_PATHS = {"App/UITests/UITestHelpers.swift", "project.yml"}


def main() -> int:
    base = sys.argv[1]
    changed = subprocess.run(
        ["git", "diff", "--name-only", base, "HEAD"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.split()
    if FULL_SUITE_PATHS & set(changed):
        print("Full suite: the PR changes " + ", ".join(sorted(FULL_SUITE_PATHS & set(changed))), file=sys.stderr)
        return 0
    classes = [
        line.strip()
        for line in (ROOT / "tools/ui_smoke_tests.txt").read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ]
    for path in changed:
        p = ROOT / path
        if path.startswith(UITESTS) and path.endswith("UITests.swift") and p.exists():
            if p.stem not in classes:
                classes.append(p.stem)
    for name in classes:
        if not (ROOT / UITESTS / f"{name}.swift").exists():
            print(f"error: {name} in tools/ui_smoke_tests.txt has no {UITESTS}{name}.swift", file=sys.stderr)
            return 1
    print("UI test classes: " + ", ".join(classes), file=sys.stderr)
    print(" ".join(f"-only-testing:{TARGET}/{c}" for c in classes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
