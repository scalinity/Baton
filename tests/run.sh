#!/bin/sh
# The standing check. Every scenario under tests/scenarios/<name>/ is run twice against a copy of
# its fixtures with the four seams pointed at the shims, and the state it leaves — BATON_HOME
# without the lock, the two runs' streams and exit codes, and the shims' calls.log — is diffed
# against expected/ with the temporary root written as @TMP@. One line per scenario; the diff on
# a failure. launchd is never in the tests; no scenario starts a process outside the shims.
#
# A scenario holds: cmd (sourced twice; $BATON, $ROOT, $SCENARIO, $SHIM are set), home/ (the
# BATON_HOME to start from; @TMP@ in any file is replaced), rows.json (what agents --json answers
# first), now (the clock), optional shim/ (the claude shim's knobs), optional project/ (a fixture
# project; tests/project/ otherwise), and expected/.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
tmproot=$(mktemp -d "${TMPDIR:-/tmp}/baton-tests.XXXXXX")
tmproot=$(cd "$tmproot" && pwd -P)
trap 'rm -rf "$tmproot"' EXIT
fails=0
count=0
nl='
'

for sc in "$here"/scenarios/*/; do
  sc=${sc%/}
  name=$(basename "$sc")
  count=$((count + 1))
  tmp=$tmproot/$name
  mkdir -p "$tmp/shim" "$tmp/out"

  # The fixture project becomes a git repository with one commit on main, at a fixed date and
  # identity so its hash is the same on every run.
  src=$sc/project; [ -d "$src" ] || src=$here/project
  cp -R "$src" "$tmp/Fixture"
  ( cd "$tmp/Fixture" \
    && git init -q -b main \
    && git add CLAUDE.md docs \
    && GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example GIT_AUTHOR_DATE=2026-09-01T00:00:00+0000 \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example GIT_COMMITTER_DATE=2026-09-01T00:00:00+0000 \
       git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "fixture" )

  cp -R "$sc/home" "$tmp/home"
  find "$tmp/home" -type f -exec sed -i '' "s|@TMP@|$tmp|g" {} +
  cp "$sc/rows.json" "$tmp/shim/rows.json"
  cp "$sc/now" "$tmp/shim/now"
  if [ -d "$sc/shim" ]; then cp "$sc"/shim/* "$tmp/shim/"; fi
  : > "$tmp/shim/calls.log"

  for run in 1 2; do
    ( export BATON_HOME="$tmp/home" BATON_CLAUDE="$here/shim/claude" BATON_DATE="$here/shim/date" \
             BATON_CAFFEINATE="$here/shim/caffeinate" BATON_SHIM="$tmp/shim" \
             BATON="$root/bin/baton" ROOT="$root" SCENARIO="$sc" SHIM="$tmp/shim"
      cd "$tmp"
      set +e
      sh "$sc/cmd" > "$tmp/out/$run.stdout" 2> "$tmp/out/$run.stderr"
      echo $? > "$tmp/out/$run.status" )
    sleep 0.2
  done

  mkdir "$tmp/got"
  cp -R "$tmp/home" "$tmp/got/home"
  cp -R "$tmp/out" "$tmp/got/out"
  cp "$tmp/shim/calls.log" "$tmp/got/calls.log"
  rm -rf "$tmp/got/home/lock"
  # The prompt hash cannot be frozen, because the sidecar carries the temporary path: recompute it
  # from the sidecar under the one rule (strip one trailing newline) and record whether it matched.
  if [ -f "$tmp/got/home/log.jsonl" ]; then
    : > "$tmp/got/home/log.jsonl.checked"
    while IFS= read -r line; do
      pp=$(printf '%s' "$line" | jq -r '.prompt_path // empty')
      if [ -n "$pp" ]; then
        want=$(printf '%s' "$line" | jq -r '.prompt_sha256')
        text=$(cat "$pp"; printf x); text=${text%x}; text=${text%"$nl"}
        have=$(printf '%s' "$text" | shasum -a 256 | awk '{ print $1 }')
        if [ "$want" = "$have" ]; then verdict=sha256-matches-sidecar; else verdict="sha256-mismatch: event $want, sidecar $have"; fi
        line=$(printf '%s' "$line" | jq -c --arg v "$verdict" '.prompt_sha256 = $v')
      fi
      printf '%s\n' "$line" >> "$tmp/got/home/log.jsonl.checked"
    done < "$tmp/got/home/log.jsonl"
    mv "$tmp/got/home/log.jsonl.checked" "$tmp/got/home/log.jsonl"
  fi
  find "$tmp/got" -type f -exec sed -i '' "s|$tmp|@TMP@|g" {} +

  if d=$(diff -r "$sc/expected" "$tmp/got" 2>&1); then
    echo "ok    $name"
  else
    echo "FAIL  $name"
    printf '%s\n' "$d" | sed 's/^/      /'
    fails=$((fails + 1))
  fi
  if [ "${BATON_TESTS_FREEZE:-}" = yes ]; then rm -rf "$sc/expected"; cp -R "$tmp/got" "$sc/expected"; fi
done

echo "$count scenarios, $fails failed"
[ "$fails" -eq 0 ]
