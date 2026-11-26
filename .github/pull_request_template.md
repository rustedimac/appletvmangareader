## What changed

## Why

## Testing

- [ ] `docs/TESTING_GUIDE.md` updated: new or changed behaviour has a row (ID, *Pass when*, *Covered by*), or this PR changes nothing users can see
- [ ] New UI test classes / MangaCore test files are named in the guide (`python3 tools/check_testing_guide.py`)
- [ ] Saved data changed? A new fixture per `docs/UPGRADE_SAFETY.md`
- [ ] New or changed screen follows `docs/DESIGN_GUIDE.md` section 9
- [ ] Reader input changed? `docs/READER_CONTROLS.md` and the legend match
- [ ] No keys, real LAN hostnames, commercial or AI-generated manga, or adult titles in code, fixtures or screenshots

Tests run (smoke set on this PR, full suite by hand if needed per `docs/CI.md`):
