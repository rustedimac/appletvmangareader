#!/usr/bin/env python3
"""Fails when a view uses a value the design guide says comes from a token.

Rules for App/Sources (see docs/DESIGN_GUIDE.md and docs/CONSISTENCY_AUDIT.md):

1. radius: no literal corner radius (`cornerRadius: 12`, `.cornerRadius(8)`).
   Use a `Radius` token, `Capsule()`, or the system shape.
2. font-size: no `.font(.system(size: N))` on text. Use a text style so Dynamic
   Type and Bold Text keep working. SF Symbol images may use a fixed size
   (the check skips a line within three lines of `Image(systemName:`).
3. text-style: no `.footnote`, `.subheadline` or `.title` (Title 1) on text.
   They aren't in the tvOS type table the guide uses; use `.caption`, `.body`
   or `.title2`. Symbol images are skipped as in rule 2.
4. section-header: no `Section("Title")` in a form. Use
   `Section(settingsHeader:)` so every settings header looks the same.
5. retry-label: a retry button says "Try Again", not "Retry".

To allow one line anyway, end it with `// design-ok: <reason>`.

Existing problems in files that open pull requests are still changing are
listed in BASELINE with how many each file may have. A file may never have
more than its baseline; when you fix one, lower (or delete) its entry so it
can't come back. New files start at zero.

Run: python3 tools/check_design_tokens.py   (CI runs it on every PR)
"""
import collections
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ROOT = REPO / "App" / "Sources"

RULES = {
    "radius": (re.compile(r"cornerRadius:\s*\d|\.cornerRadius\(\s*\d"),
               "literal corner radius; use a Radius token, Capsule() or the system shape"),
    "font-size": (re.compile(r"\.font\(\.system\(size:"),
                  "fixed font size on text; use a text style (.body, .caption, ...)"),
    "text-style": (re.compile(r"\.font\(\.(footnote|subheadline|title)\b(?!2|3)"),
                   "text style outside the tvOS table; use .caption, .body or .title2"),
    "section-header": (re.compile(r"\bSection\(\s*\""),
                       "Section(\"…\") header; use Section(settingsHeader:)"),
    "retry-label": (re.compile(r"Button\(\s*\"Retry\""),
                    "retry buttons say \"Try Again\""),
}

# (file, rule) -> problems allowed. Only for files open PRs are changing;
# fix them once those PRs merge. Keep this list shrinking.
BASELINE = {
    ("App/Sources/Reader/Paged/PagedReaderView.swift", "radius"): 3,  # +2 from the page-retry overlay (#23)
    ("App/Sources/Reader/ReaderView.swift", "radius"): 1,
    ("App/Sources/Reader/ReaderView.swift", "retry-label"): 1,
    ("App/Sources/Reader/Book/BookReaderView.swift", "radius"): 1,
    ("App/Sources/Reader/Book/BookReaderView.swift", "retry-label"): 1,
    ("App/Sources/Series/SeriesPoster.swift", "radius"): 1,
    ("App/Sources/Reader/Menu/ReaderMenu.swift", "text-style"): 3,
}

counts = collections.Counter()
lines_by_key = collections.defaultdict(list)
for path in sorted(ROOT.rglob("*.swift")):
    rel = str(path.relative_to(REPO))
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if "design-ok:" in line:
            continue
        code = line.split("//", 1)[0]
        for rule, (pattern, _) in RULES.items():
            if not pattern.search(code):
                continue
            if rule in ("font-size", "text-style") and any("Image(systemName" in l for l in lines[max(0, i - 3):i + 1]):
                continue
            counts[(rel, rule)] += 1
            lines_by_key[(rel, rule)].append(i + 1)

errors = []
for key, n in sorted(counts.items()):
    allowed = BASELINE.get(key, 0)
    if n > allowed:
        rel, rule = key
        where = ", ".join(str(l) for l in lines_by_key[key])
        errors.append(f"{rel}:{lines_by_key[key][0]}: [{rule}] {RULES[rule][1]} "
                      f"({n} in this file at lines {where}; {allowed} allowed)")

stale = [key for key, allowed in BASELINE.items() if counts.get(key, 0) < allowed]

for e in errors:
    print(f"error: {e}")
for rel, rule in stale:
    print(f"note: {rel} now has {counts.get((rel, rule), 0)} [{rule}] problems; "
          f"lower its BASELINE entry ({BASELINE[(rel, rule)]}) in tools/check_design_tokens.py")
if errors:
    print(f"\n{len(errors)} design-token problem(s). See tools/check_design_tokens.py for the rules.")
    sys.exit(1)
print("Design tokens OK.")
