#!/bin/sh
# The standing check. Every scenario under tests/scenarios/<name>/ is run twice against a copy of
# its fixtures with the seams pointed at the shims, and the state it leaves — BATON_HOME without
# the lock, the two runs' streams and exit codes, and the shims' calls.log — is diffed against
# expected/ with the temporary root written as @TMP@ and the fixture commit as @COMMIT@. One line
# per scenario; the diff on a failure. launchd is never in the tests; no scenario starts a process
# outside the shims.
#
# A scenario holds: cmd (sourced twice; $BATON, $ROOT, $SCENARIO, $SHIM are set), home/ (the
# BATON_HOME to start from; @TMP@ and @COMMIT@ in any file are replaced), rows.json (what agents --json answers
# first), now (the clock), optional shim/ (the claude shim's knobs), optional project/ (a fixture
# project; tests/project/ otherwise), optional transcripts/ (the tree BATON_TRANSCRIPTS points at),
# optional mtimes (one "<path under transcripts/> <seconds before now>" per line, for the rules
# that stat a transcript rather than read it; every transcript starts at the scenario's now), and
# expected/. install.sh needs codesign, which the Command Line Tools carry, for the install scenario.
#
# BATON_TESTS_FREEZE=<name> rewrites that one scenario's expected/ from the run, for output that
# has been read and judged right; BATON_TESTS_FREEZE=all does it for every scenario and is for a
# harness change that moves every expectation at once.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
tmproot=$(mktemp -d "${TMPDIR:-/tmp}/baton-tests.XXXXXX")
tmproot=$(cd "$tmproot" && pwd -P)
trap 'rm -rf "$tmproot"' EXIT
fails=0
count=0
freeze=${BATON_TESTS_FREEZE:-}

# The host's git configuration stays out: the fixture commit's hash, the worktree adds and the
# hooks a config could name must be the same on every Mac.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# prompt_normalise, the one rule, for the hash check below; iso_epoch, for the mtimes file.
BATON_DATE=date
. "$root/lib/log.sh"
. "$root/lib/derive.sh"

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
       git commit -q -m "fixture" )
  commit=$(git -C "$tmp/Fixture" rev-parse HEAD)
  # A commit that is a real commit and is not on main, so the merged_as ancestry check can
  # be failed by a claim git can resolve — which is the lie INV-03 exists to catch.
  offmain=$(GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example GIT_AUTHOR_DATE=2026-09-01T00:00:00+0000 \
            GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example GIT_COMMITTER_DATE=2026-09-01T00:00:00+0000 \
            git -C "$tmp/Fixture" commit-tree "$commit^{tree}" -p "$commit" -m off-main)

  cp -R "$sc/home" "$tmp/home"
  # @COMMIT@ as well as @TMP@, because a handover artifact names the commit it merged as and the
  # fixture repository's hash is only known once it has been committed.
  find "$tmp/home" -type f -exec sed -i '' "s|@TMP@|$tmp|g; s|@COMMIT@|$commit|g; s|@OFFMAIN@|$offmain|g" {} +
  cp "$sc/rows.json" "$tmp/shim/rows.json"
  cp "$sc/now" "$tmp/shim/now"
  if [ -d "$sc/shim" ]; then cp "$sc"/shim/* "$tmp/shim/"; fi
  find "$tmp/shim" -type f -exec sed -i '' "s|@TMP@|$tmp|g" {} +
  : > "$tmp/shim/calls.log"

  # The transcripts a derivation reads, as a directory: ~/.claude/projects with one folder per
  # checkout, found by glob and never by a path derived from the project. A scenario without one
  # gets an empty tree, which is a lane with no transcript.
  if [ -d "$sc/transcripts" ]; then cp -R "$sc/transcripts" "$tmp/transcripts"; else mkdir "$tmp/transcripts"; fi
  find "$tmp/transcripts" -type f -exec sed -i '' "s|@TMP@|$tmp|g" {} +
  # The stall rule is a stat and never a read, so a scenario that exercises it has to own the
  # modification times: a copied file carries the time of the copy, which is the machine's real
  # clock, while the scenario's `now` is frozen at whatever date it names. Every copied transcript
  # is therefore set to the scenario's `now` first — so a scenario that forgets its `mtimes` reads
  # "just written" rather than whatever the clock happened to say — and `mtimes` then overrides the
  # ones the scenario means to age, one "<path under transcripts/> <seconds before now>" per line.
  # Both the conversion and the touch are pinned to UTC so they cannot disagree during the hour a
  # fall-back transition repeats.
  if [ -d "$tmp/transcripts" ]; then
    scnow=$(iso_epoch "$(cat "$sc/now")")
    find "$tmp/transcripts" -type f -exec \
      env TZ=UTC touch -t "$(TZ=UTC date -r "$scnow" +%Y%m%d%H%M.%S)" {} +
    if [ -f "$sc/mtimes" ]; then
      while read -r mt_path mt_ago || [ -n "$mt_path" ]; do
        case "$mt_path" in ''|'#'*) continue ;; esac
        if [ ! -f "$tmp/transcripts/$mt_path" ]; then
          echo "FAIL  $name: mtimes names $mt_path, which the scenario does not have"
          fails=$((fails + 1))
          continue
        fi
        env TZ=UTC touch -t "$(TZ=UTC date -r "$((scnow - mt_ago))" +%Y%m%d%H%M.%S)" "$tmp/transcripts/$mt_path"
      done < "$sc/mtimes"
    fi
  fi

  for run in 1 2; do
    ( export BATON_HOME="$tmp/home" BATON_CLAUDE="$here/shim/claude" BATON_DATE="$here/shim/date" \
             BATON_CAFFEINATE="$here/shim/caffeinate" BATON_OSASCRIPT="$here/shim/osascript" \
             BATON_SHIM="$tmp/shim" BATON_DAEMON_LOG="$tmp/shim/daemon.log" \
             BATON_TRANSCRIPTS="$tmp/transcripts" \
             BATON="$root/bin/baton" ROOT="$root" SCENARIO="$sc" SHIM="$tmp/shim"
      cd "$tmp"
      set +e
      sh "$sc/cmd" > "$tmp/out/$run.stdout" 2> "$tmp/out/$run.stderr"
      echo $? > "$tmp/out/$run.status" )
    # The caffeinate shim is started detached by the relay and appends to calls.log on its own
    # time; a beat lets it land before the snapshot.
    sleep 0.1
  done

  mkdir "$tmp/got"
  cp -R "$tmp/home" "$tmp/got/home"
  cp -R "$tmp/out" "$tmp/got/out"
  cp "$tmp/shim/calls.log" "$tmp/got/calls.log"
  rm -rf "$tmp/got/home/lock"
  # The prompt hash cannot be frozen, because the sidecar carries the temporary path: recompute it
  # from the sidecar under the one rule and record whether it matched. A line that is not JSON is
  # left as it is (log-torn-line).
  if [ -f "$tmp/got/home/log.jsonl" ]; then
    : > "$tmp/got/home/log.jsonl.checked"
    while IFS= read -r line || [ -n "$line" ]; do
      pp=$(printf '%s' "$line" | jq -r '.prompt_path // empty' 2>/dev/null || true)
      if [ -n "$pp" ]; then
        want=$(printf '%s' "$line" | jq -r '.prompt_sha256')
        if [ -f "$pp" ]; then
          have=$(prompt_sha256 "$pp")
          if [ "$want" = "$have" ]; then verdict=sha256-matches-sidecar; else verdict="sha256-mismatch: event $want, sidecar $have"; fi
        else
          verdict="sidecar-missing: $pp"
        fi
        line=$(printf '%s' "$line" | jq -c --arg v "$verdict" '.prompt_sha256 = $v')
      fi
      printf '%s\n' "$line" >> "$tmp/got/home/log.jsonl.checked"
    done < "$tmp/got/home/log.jsonl"
    mv "$tmp/got/home/log.jsonl.checked" "$tmp/got/home/log.jsonl"
  fi
  find "$tmp/got" -type f -exec sed -i '' "s|$tmp|@TMP@|g; s|$commit|@COMMIT@|g; s|$offmain|@OFFMAIN@|g" {} +

  # git cannot hold an empty directory, so a scenario whose inbox ends empty would compare
  # against an expected/ that has no inbox at all on a fresh checkout. Neither side may
  # depend on something the repository cannot represent: prune empty directories from both,
  # and diff a pruned copy of expected/ rather than expected/ itself.
  cp -R "$sc/expected" "$tmp/want" 2>/dev/null || mkdir "$tmp/want"
  find "$tmp/want" "$tmp/got" -type d -empty -delete 2>/dev/null || true

  if d=$(diff -r "$tmp/want" "$tmp/got" 2>&1); then
    echo "ok    $name"
  else
    echo "FAIL  $name"
    printf '%s\n' "$d" | sed 's/^/      /'
    fails=$((fails + 1))
  fi
  if [ "$freeze" = "$name" ] || [ "$freeze" = all ]; then
    rm -rf "$sc/expected"; cp -R "$tmp/got" "$sc/expected"; echo "froze $name"
  fi
done

echo "$count scenarios, $fails failed"
[ "$fails" -eq 0 ]
