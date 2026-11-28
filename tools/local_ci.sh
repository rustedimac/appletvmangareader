#!/bin/bash
# Run a PR's CI on this Mac and report the result to the PR.
#
#   tools/local_ci.sh [options] <PR number>...     e.g. tools/local_ci.sh 17 45
#
# For each PR, in order: fetch it, merge it into the current main (as GitHub's
# merge commit would), run the UI lint and MangaCore `swift test`, build once,
# then run the UI smoke set (the classes CI picks, tools/select_ui_tests.py) and
# after it the rest of the UI suite. Results go on the PR's head commit as two
# commit statuses, next to the GitHub Actions checks:
#
#   local-mac / smoke   lint + core tests + build + UI smoke set
#   local-mac / full    the above + every other UI test class
#
# plus one PR comment (edited on every run) with times and failures.
#
# A UI test that fails is re-run once on main, built the same way. If it fails
# on main too it is listed as "also fails on main" and doesn't turn the PR red:
# it is main's problem (or this Mac's Xcode differs from CI's), not the PR's.
#
# Options:
#   --smoke-only     stop after the smoke set (no "local-mac / full" status)
#   --no-post        print the result, post nothing to GitHub
#   --workers N      UI tests on N simulator clones at once (default 3)
#
# State lives in $MR_LOCAL_CI_DIR (default ~/Library/Caches/MangaReaderLocalCI):
# its own clones (work/, main/), DerivedData, logs/<PR>-<time>/, a cache of
# tests known to fail on each main commit, and a lock so two runs never share
# a simulator. Your own checkout is never touched. Tests run on a simulator of
# their own, "MangaReader Local CI", erased before each PR.
set -uo pipefail

REPO=rustedimac/appletvmangareader
STATE=${MR_LOCAL_CI_DIR:-$HOME/Library/Caches/MangaReaderLocalCI}
SIM_NAME="MangaReader Local CI"
TARGET=MangaReaderUITests
MARKER="<!-- local-mac-ci -->"

args=("$@")
smoke_only=0; post=1; workers=3; prs=()
usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case $1 in
    --smoke-only) smoke_only=1 ;;
    --no-post) post=0 ;;
    --workers) workers=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *[!0-9]*|"") echo "unknown option: $1" >&2; exit 2 ;;
    *) prs+=("$1") ;;
  esac
  shift
done
[ ${#prs[@]} -gt 0 ] || { usage; exit 2; }

# Each PR is checked out over the clone the script may have been started from;
# run from a copy so a checkout never rewrites the file bash is reading.
mkdir -p "$STATE/logs" "$STATE/known"
if [ "${MR_LOCAL_CI_COPY:-}" != 1 ]; then
  cp "$0" "$STATE/local_ci.sh"
  MR_LOCAL_CI_COPY=1 exec /bin/bash "$STATE/local_ci.sh" "${args[@]}"
fi

until mkdir "$STATE/lock" 2>/dev/null; do
  pid=$(cat "$STATE/lock/pid" 2>/dev/null)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$STATE/lock"; continue; fi
  echo "Waiting for the local CI run in process ${pid:-?} to finish..."
  sleep 30
done
echo $$ > "$STATE/lock/pid"
trap 'rm -rf "$STATE/lock"' EXIT

XCODE=$(xcodebuild -version | head -1)
HOST=$(hostname -s)
now() { date +%s; }
mins() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

# --- GitHub ---------------------------------------------------------------

comment_url=""
set_status() { # context state description
  [ $post = 1 ] || { echo "  [status] $1: $2 - $3"; return 0; }
  gh api -X POST "repos/$REPO/statuses/$HEAD_SHA" -f state="$2" -f context="$1" \
    -f description="${3:0:140}" ${comment_url:+-f target_url="$comment_url"} >/dev/null \
    || echo "warning: could not post status $1" >&2
}

post_comment() { # body-file; creates or edits this script's one comment on the PR
  [ $post = 1 ] || { echo "  [comment]"; sed 's/^/    /' "$1"; return 0; }
  local id
  id=$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
        --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | tail -1)
  if [ -n "$id" ]; then
    comment_url=$(gh api -X PATCH "repos/$REPO/issues/comments/$id" -F body=@"$1" --jq .html_url)
  else
    comment_url=$(gh api -X POST "repos/$REPO/issues/$PR/comments" -F body=@"$1" --jq .html_url)
  fi
}

# --- Building and testing ---------------------------------------------------

sync_clone() { # dir ref ; a clean checkout of ref (fetched from GitHub)
  [ -d "$1/.git" ] || git clone -q "https://github.com/$REPO.git" "$1" || return 1
  git -C "$1" checkout -q -f --detach "$2" && git -C "$1" clean -q -fdx
}

build() { # dir derived-data log
  (cd "$1" && xcodegen generate >/dev/null && xcodebuild build-for-testing \
     -project MangaReader.xcodeproj -scheme MangaReader \
     -destination 'generic/platform=tvOS Simulator' -derivedDataPath "$2" \
     ARCHS=arm64 CODE_SIGNING_ALLOWED=NO) >"$3" 2>&1
}

simulator() { # UDID of our own simulator, created on the newest tvOS if missing
  local udid runtime
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
for v in json.load(sys.stdin)["devices"].values():
    for d in v:
        if d["name"] == sys.argv[1]: print(d["udid"])' "$SIM_NAME" | head -1)
  if [ -z "$udid" ]; then
    runtime=$(xcrun simctl list runtimes available -j | python3 -c '
import json,sys
r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="tvOS"]
print(sorted(r,key=lambda x:[int(p) for p in x["version"].split(".")])[-1]["identifier"])')
    udid=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K "$runtime")
  fi
  echo "$udid"
}

# Reads an xcresult. Prints "passed failed skipped"; writes the failed test ids
# (Class/testMethod) to $2.ids and "id<TAB>first message" lines to $2.msgs.
read_results() {
  xcrun xcresulttool get test-results tests --path "$1" 2>/dev/null | python3 -c '
import json,sys
out=sys.argv[1]
try: tree=json.load(sys.stdin)
except Exception: tree={"testNodes":[]}
counts={"Passed":0,"Failed":0,"Skipped":0}
ids=open(out+".ids","w"); msgs=open(out+".msgs","w")
def walk(n):
    if n.get("nodeType")=="Test Case":
        r=n.get("result","")
        counts[r]=counts.get(r,0)+1
        if r=="Failed":
            i=n.get("nodeIdentifier") or n.get("name","?")
            m=[c.get("name","") for c in n.get("children",[]) if c.get("nodeType")=="Failure Message"]
            ids.write(i+"\n")
            msgs.write(i+"\t"+" ".join((m[0] if m else "").split())[:300]+"\n")
        return
    for c in n.get("children",[]): walk(c)
for n in tree.get("testNodes",[]): walk(n)
print(counts["Passed"],counts["Failed"],counts["Skipped"])' "$2"
}

# ui_tests <dir> <derived-data> <name> [xcodebuild test args...]
# Sets ui_exit, ui_secs and ui_counts ("passed failed skipped").
ui_tests() {
  local dir=$1 dd=$2 name=$3; shift 3
  local t; t=$(now)
  local par=()
  [ "$workers" -gt 1 ] && par=(-parallel-testing-enabled YES -parallel-testing-worker-count "$workers")
  rm -rf "$LOG/$name.xcresult"
  (cd "$dir" && xcodebuild test-without-building -project MangaReader.xcodeproj -scheme MangaReader \
     -destination "id=$UDID" -derivedDataPath "$dd" ${par[@]+"${par[@]}"} "$@" \
     -resultBundlePath "$LOG/$name.xcresult" CODE_SIGNING_ALLOWED=NO) >"$LOG/$name.log" 2>&1
  ui_exit=$?
  ui_secs=$(( $(now) - t ))
  ui_counts=$(read_results "$LOG/$name.xcresult" "$LOG/$name")
  echo "  $name: $ui_counts (passed failed skipped) in $(mins $ui_secs), exit $ui_exit"
}

# Re-runs the failed tests in $LOG/<name>.ids on main; writes those that fail
# there too to $LOG/<name>.known. Results are cached per main commit.
check_on_main() {
  local name=$1 cache=$STATE/known/$MAIN_SHA id todo=()
  mkdir -p "$cache"; : > "$LOG/$name.known"
  while read -r id; do
    [ -n "$id" ] || continue
    local key=${id//[^A-Za-z0-9]/_}
    if [ -f "$cache/$key.fail" ]; then echo "$id" >> "$LOG/$name.known"
    elif [ ! -f "$cache/$key.pass" ]; then todo+=("$id"); fi
  done < "$LOG/$name.ids"
  [ ${#todo[@]} -gt 0 ] || return 0
  echo "  checking ${#todo[@]} failed test(s) on main $MAIN_SHA"
  if [ ! -f "$cache/.built" ]; then
    sync_clone "$STATE/main" "$MAIN_SHA" && build "$STATE/main" "$STATE/DerivedData-main" "$LOG/main-build.log" \
      && touch "$cache/.built" || { echo "  main build failed; treating failures as the PR's"; return 0; }
  fi
  local only=()
  for id in "${todo[@]}"; do only+=("-only-testing:$TARGET/${id%()}"); done
  ui_tests "$STATE/main" "$STATE/DerivedData-main" "$name-on-main" "${only[@]}"
  for id in "${todo[@]}"; do
    local key=${id//[^A-Za-z0-9]/_}
    if grep -qxF "$id" "$LOG/$name-on-main.ids"; then
      touch "$cache/$key.fail"; echo "$id" >> "$LOG/$name.known"
    elif [ "${ui_counts%% *}" -gt 0 ]; then
      touch "$cache/$key.pass"   # only cache a pass when the main run really ran
    fi
  done
}

# --- One PR -------------------------------------------------------------------

# A stage's verdict from its results: sets stage_res and stage_note; appends
# failures to $FAILS.
judge() { # name
  local name=$1 exit_code=$ui_exit; set -- $ui_counts
  check_on_main "$name"
  local new known
  new=$(grep -vxF -f "$LOG/$name.known" "$LOG/$name.ids" | grep -c . || true)
  known=$(grep -c . "$LOG/$name.known" || true)
  while IFS=$'\t' read -r id msg; do
    if grep -qxF "$id" "$LOG/$name.known"; then FAILS+="- \`$id\` (also fails on main): $msg"$'\n'
    else FAILS+="- \`$id\`: $msg"$'\n'; fi
  done < "$LOG/$name.msgs"
  stage_note="$1 passed, $2 failed"
  [ "$known" -gt 0 ] && stage_note="$stage_note ($known also on main)"
  if [ "$new" -gt 0 ]; then stage_res=failure
  elif [ "$exit_code" -ne 0 ] && [ "$2" = 0 ]; then
    stage_res=failure; stage_note="xcodebuild exited $exit_code with no test failures"
    FAILS+="- $name: xcodebuild exited $exit_code (crash or setup error); see $name.log"$'\n'
  else stage_res=success; fi
}

render_comment() { # smoke_res smoke_line smoke_secs full_res full_line full_secs
  local f=$LOG/comment.md
  icon() { case $1 in success) echo "✅";; failure) echo "❌";; *) echo "⏳";; esac; }
  {
    echo "$MARKER"
    echo "### Local Mac CI: ${HEAD_SHA:0:7} merged into main ${MAIN_SHA:0:7}"
    echo
    echo "| | Result | Time |"
    echo "|---|---|---|"
    echo "| $(icon "$1") **local-mac / smoke**: lint, core tests, build, UI smoke set | $2 | ${3:+$(mins "$3")} |"
    [ $smoke_only = 1 ] || echo "| $(icon "$4") **local-mac / full**: smoke + rest of the UI suite | ${5:-waiting} | ${6:+$(mins "$6")} |"
    if [ -n "$FAILS" ]; then echo; echo "**Failures**"; echo; printf '%s' "$FAILS"; fi
    echo
    echo "<sub>$XCODE on $HOST, $workers simulators, $(date '+%Y-%m-%d %H:%M %Z'). GitHub Actions runs as before; CI uses Xcode 16, so a failure marked \"also fails on main\" may be this Mac's Xcode. Logs: \`${LOG/#$HOME/~}\`</sub>"
  } > "$f"
  post_comment "$f"
}

run_pr() {
  PR=$1; comment_url=""; FAILS=""
  local t0; t0=$(now)
  LOG=$STATE/logs/$PR-$(date +%Y%m%d-%H%M%S); mkdir -p "$LOG"
  local info
  info=$(gh pr view "$PR" -R "$REPO" --json headRefOid,state,title) || return 1
  HEAD_SHA=$(jq -r .headRefOid <<<"$info")
  echo "== PR #$PR $(jq -r .title <<<"$info") @ ${HEAD_SHA:0:7}"
  [ "$(jq -r .state <<<"$info")" = OPEN ] || { echo "  not open, skipped"; return 0; }

  local W=$STATE/work DD=$STATE/DerivedData
  sync_clone "$W" HEAD >/dev/null 2>&1 || true
  git -C "$W" fetch -q -f origin main "pull/$PR/head:refs/local-ci/pr" || return 1
  sync_clone "$W" origin/main || return 1
  MAIN_SHA=$(git -C "$W" rev-parse HEAD)
  local S="local-mac / smoke" F="local-mac / full"

  if ! git -C "$W" -c user.name=local-ci -c user.email=local-ci@localhost \
        merge -q --no-ff --no-edit refs/local-ci/pr >"$LOG/merge.log" 2>&1; then
    git -C "$W" merge --abort 2>/dev/null
    set_status "$S" failure "Conflicts with main ${MAIN_SHA:0:7}: merge main into the branch"
    [ $smoke_only = 1 ] || set_status "$F" failure "Conflicts with main ${MAIN_SHA:0:7}"
    echo "  merge conflict with main"; return 0
  fi
  set_status "$S" pending "Running on $HOST"
  [ $smoke_only = 1 ] || set_status "$F" pending "Waiting for the smoke set"

  # Lint and core tests (seconds to a minute).
  local s pre=0
  for s in "$W"/tools/check_*.py; do
    python3 "$s" >>"$LOG/lint.log" 2>&1 || { pre=1; FAILS+="- UI lint: \`tools/${s##*/}\` failed: $(tail -3 "$LOG/lint.log" | tr '\n' ' ' | cut -c1-300)"$'\n'; }
  done
  (cd "$W/Packages/MangaCore" && swift test) >"$LOG/core.log" 2>&1 \
    || { pre=1; FAILS+="- MangaCore \`swift test\` failed: $(grep -m3 -E 'error:|failed' "$LOG/core.log" | tr '\n' ' ' | cut -c1-300)"$'\n'; }

  local t; t=$(now)
  build "$W" "$DD" "$LOG/build.log"; local build_exit=$?
  echo "  build: exit $build_exit in $(mins $(( $(now) - t )))"
  if [ $build_exit -ne 0 ]; then
    FAILS+="- Build failed:"$'\n'"$(grep -m10 'error:' "$LOG/build.log" | sed 's/^/  /')"$'\n'
    render_comment failure "build failed" $(( $(now) - t0 )) failure "build failed" ""
    set_status "$S" failure "Build failed ($XCODE)"
    [ $smoke_only = 1 ] || set_status "$F" failure "Build failed ($XCODE)"
    return 0
  fi

  UDID=$(simulator)
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl erase "$UDID" >/dev/null 2>&1

  local only; only=$(cd "$W" && python3 tools/select_ui_tests.py HEAD^1 2>"$LOG/select.log")
  local smoke_res smoke_line smoke_secs full_res="" full_line="" full_secs=""
  if [ -z "$only" ]; then
    ui_tests "$W" "$DD" all            # the PR changes files every UI test uses
    judge all
    smoke_res=$stage_res; smoke_line="whole suite (PR changes shared test files): $stage_note"
    full_res=$stage_res; full_line=$smoke_line
  else
    # shellcheck disable=SC2086
    ui_tests "$W" "$DD" smoke $only
    judge smoke
    smoke_res=$stage_res; smoke_line="$stage_note"
  fi
  [ $pre = 1 ] && { smoke_res=failure; smoke_line="lint or core tests failed; $smoke_line"; full_res=failure; }
  smoke_secs=$(( $(now) - t0 ))
  [ -n "$full_res" ] && full_secs=$smoke_secs
  render_comment "$smoke_res" "$smoke_line" "$smoke_secs" "$full_res" "$full_line" "$full_secs"
  set_status "$S" "$smoke_res" "$smoke_line in $(mins $smoke_secs)"
  [ $smoke_only = 1 ] && { echo "  total $(mins $smoke_secs); logs in $LOG"; return 0; }

  if [ -z "$full_line" ]; then
    set_status "$F" pending "Smoke $smoke_res; running the rest of the UI suite"
    # shellcheck disable=SC2086
    ui_tests "$W" "$DD" rest ${only//-only-testing:/-skip-testing:}
    judge rest
    full_line="rest: $stage_note"
    [ "$stage_res" = success ] && [ "$smoke_res" = success ] && full_res=success || full_res=failure
    full_secs=$(( $(now) - t0 ))
    render_comment "$smoke_res" "$smoke_line" "$smoke_secs" "$full_res" "$full_line" "$full_secs"
  fi
  set_status "$F" "$full_res" "smoke $smoke_res; $full_line in $(mins "$full_secs")"
  echo "  total $(mins "$full_secs"); logs in $LOG"
}

for pr in "${prs[@]}"; do run_pr "$pr"; done
