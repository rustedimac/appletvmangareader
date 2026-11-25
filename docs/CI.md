# CI and where tests run

## Full suite: GitHub Actions

Every PR runs `.github/workflows/ci.yml` on GitHub's macOS runners:

- **MangaCore unit tests**: `swift test` in `Packages/MangaCore` (about 1 minute, 15 minute timeout).
- **tvOS app build and UI tests**: `xcodegen generate` and then `xcodebuild test` on a tvOS simulator (about 35 minutes at 80 UI tests, 60 minute timeout). Test results stream into the job log as they finish, and the xcresult is uploaded when a run fails or times out.

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
- The full suite always runs on GitHub. A local pass doesn't replace a green PR run.
