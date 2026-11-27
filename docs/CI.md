# CI and where tests run

What to test and how to judge it: [TESTING_GUIDE.md](TESTING_GUIDE.md). Every
feature PR adds or updates its rows there (`tools/check_testing_guide.py`
runs in the UI lint job).

## GitHub Actions: smoke on PRs, full suite on main

`.github/workflows/ci.yml` runs on GitHub's runners:

| | Every PR push | Merge to main, nightly (3 AM Eastern), manual run |
|---|---|---|
| UI lint (Linux, seconds) | yes | yes |
| MangaCore unit tests (`swift test`, about 1 min) | yes | yes |
| tvOS UI tests | **smoke set** (about 20 min with build) | **full suite** (about 55 min at 125 tests) |

- **Smoke set**: the classes in `tools/ui_smoke_tests.txt`, plus every UI test file the PR adds or changes (so a PR's new tests always run on it). A PR that changes `App/UITests/UITestHelpers.swift` or `project.yml` runs the full suite. `tools/select_ui_tests.py` makes the choice and the job log prints the classes it picked.
- **Full suite on a PR**: start the workflow by hand on the PR's branch (Actions, CI, Run workflow). Do this for changes that reach screens the smoke set doesn't cover, such as settings layout, Home rows, or server editors.
- **Red main**: when a full run fails, the *Report main status* job opens an issue titled "CI is red on main", or comments on the open one. The next green full run closes it. Fixing a red main comes before merging anything else. Every merge runs the full suite, so the first red run points at the merge that broke it.
- The UI job builds once (`build-for-testing`), then runs tests (`test-without-building`) on a tvOS simulator, with a 180 minute timeout (the full suite passed 90 minutes, then 120, on 2026-11-26). Results stream into the job log as they finish, and the xcresult is uploaded when a run fails or times out.

### What limits CI, and what doesn't help

The repository gets at most **5 macOS runners at once** (GitHub free plan). With many open PRs, runs wait in that queue far longer than they run, so what matters is runner minutes per run, not only how long one run takes.

- `simctl list` runs in the background during `build-for-testing`. Its first call starts CoreSimulator, which took 2 to 3 minutes on its own. Build plus simulator start went from about 6 minutes to under 2 (PR #42).
- **Don't run UI tests on parallel simulator clones.** Tried in PR #42 with 3 clones: each test ran 2 to 5 times slower on the 3-core runner (a 10 second reader test took 25 to 40 seconds, CategorySelection tests failed under the load), and the job hit the 60 minute timeout.
- **Don't shard the UI tests across several runners.** Each shard pays for its own build and simulator start, so sharding uses more runner minutes and makes the queue longer.
- The UI tests themselves are the cost: 43 minutes at 91 tests on main (run 280). A few take far longer than the rest, e.g. `CategorySelectionUITests.testServerEditorListsCategoriesAndSavesTicks` (170 s), `DesignLayoutUITests.testSettingsScreens` (127 s), `FreeLibraryUITests.testSettingsShowsCreditsAndCanRemoveAndRestore` (82 s). Speeding those up is where further time comes from. That cost is also why PRs run only the smoke set.


Push runs happen only on `main`. Each PR gets one run per push, and a new push cancels the previous run for that PR.

A run that sits in "queued" for a long time is waiting for a free macOS runner. It has not hung. To check, compare each job's `created_at` with its `started_at`. Don't re-run superseded runs.

A PR with merge conflicts gets no `pull_request` run. Merge `main` into the branch and push.

## Quick tests: the maintainer's Mac

Use the maintainer's MacBook (with Xcode and a tvOS simulator) for quick checks before pushing, so a fix doesn't wait an hour in the runner queue:

- `swift test` in `Packages/MangaCore` (about 1 minute).
- Re-running **one** failing UI test, especially one that is hard to fix from CI logs alone, such as a focus problem. Run just that test, e.g.
  `xcodebuild test -project MangaReader.xcodeproj -scheme MangaReader -destination 'platform=tvOS Simulator,name=Apple TV' -only-testing:MangaReaderUITests/<Class>/<testMethod> CODE_SIGNING_ALLOWED=NO`
- Send back only the failures (failing assertions and the lines around them), not the whole log.
- Only when the Mac is awake and reachable. If it isn't, fix from the CI log and push.
- A local pass doesn't replace a green PR run.
