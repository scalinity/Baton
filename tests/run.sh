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
# first), now (the clock), optional shim/ (the claude shim's knobs, and the pmset shim's pmset.log —
# the host's sleep history — and pmset.status), optional project/ (a fixture
# project; tests/project/ otherwise), optional other/ (a second fixture project at $tmp/Other, its
# commit @OTHERCOMMIT@), optional transcripts/ (the tree BATON_TRANSCRIPTS points at), optional
# jobs/ (the tree BATON_JOBS points at), optional
# mtimes (one "<path under transcripts/ or home/> <seconds before now>" per line, for the rules that
# stat a file rather than read it; every transcript starts at the scenario's now), and expected/. install.sh needs codesign, which the Command Line Tools carry, for the install scenario.
#
# A scenario whose cmd builds commits of its own — tests/completion-fixture.sh does, because a
# completion chain needs a baseline, a candidate and a merge that the fixture commit alone cannot
# supply — writes "<NAME> <value>" per line to $tmp/subs and replaces @NAME@ in its own home/ with
# the value. Those values are turned back into @NAME@ in got/ before the diff, so an expectation
# holds the names rather than hashes that would move whenever tests/project/ changed.
#
# BATON_TESTS_FREEZE=<name> rewrites that one scenario's expected/ from the run, for output that
# has been read and judged right; BATON_TESTS_FREEZE=all does it for every scenario and is for a
# harness change that moves every expectation at once. BATON_TESTS_ONLY=<glob> runs the scenarios
# whose names match it and no others; the standing check is the run without it.
# The scenarios share nothing, so BATON_TESTS_JOBS=<n> of them run at once while the lines are still
# printed one scenario at a time in name order. The default is a third of the cores: three suites at
# once is the relay's steady state (D-187), and together they then take every core and no more.
# BATON_TESTS_JOBS=1 and BATON_TESTS_FREEZE run the scenarios one after another in this shell.
# A run whose BATON_TESTS_OWNER=<pid> has gone stops on its own, and so does one that has reached the
# BATON_TESTS_DEADLINE=<seconds> a caller named, of which there is none by default; both exit 3,
# before the next scenario begins. The run sets LC_ALL=en_US.UTF-8 for itself and refuses, exit 3,
# where that locale is not installed, and unsets NO_COLOR and FORCE_COLOR.
set -eu

# A run is abandoned when the caller that wanted its result has gone, and only that caller can say
# who it is: BATON_TESTS_OWNER names a process that lives exactly as long as the caller wants the
# run, and once `kill -0` says it is gone the run stops before its next scenario. No owner named
# means no such stop, so a run detached on purpose is never at risk, because nothing claims to own
# it. Parentage cannot stand in for this: a parent of launchd (ppid 1) says the starter has gone and
# not that nobody is reading, and a live session reads a detached run's output from a file.
# A run with BATON_TESTS_FREEZE set ignores the owner altogether, because stopping it midway leaves
# the expectations frozen so far, which running it again does not repair.
# The owner is a pid of the same user. `kill -0` also fails on another user's live process, and a
# pid handed to a new process after its owner died reads as alive, which is the safe direction.
# The deadline is the harness measuring itself: it reads the real clock with a bare `date` and
# writes no event, so BATON_DATE, which governs the timestamps the log holds, has no part in it.
# There is no default deadline. A constant cannot track a suite that has grown from 246 scenarios to
# 405 during this project, and a deadline that fires on a healthy run is read downstream as evidence
# about the code: the abort is a status other than 0, which the relay records as a failed check. A
# caller that wants a bound names one.
# Both stops exit 3, never 0 and never the 1 of a failed scenario, so an abort is not a pass and is
# told apart from a scenario that failed.
run_owner=${BATON_TESTS_OWNER:-}
case "$run_owner" in
  '') ;;
  *[!0-9]*) echo "run: BATON_TESTS_OWNER is not a pid ($run_owner); running without an owner" >&2
            run_owner= ;;
esac
if [ -n "$run_owner" ] && [ -n "${BATON_TESTS_FREEZE:-}" ]; then
  echo "run: BATON_TESTS_FREEZE is set, so BATON_TESTS_OWNER is not enforced" >&2
  run_owner=
fi
run_started=$(date +%s)
run_deadline=${BATON_TESTS_DEADLINE:-}

# The expectations were frozen under en_US.UTF-8, which the launchd job and every dispatched session
# already run in (LC_ALL in the plist and in claude_bg), so the harness sets it itself and does not
# rely on its caller. A shell with no LANG runs in the C locale, where the truncation of a multibyte
# string, the bytes of `·` in an `od` dump and the order `ls` gives all differ, and four scenarios
# fail for a reason that has nothing to do with the code, which a hand-run close-out reads as a
# broken main. Where the locale is not installed the run refuses rather than run in another one and
# report failures that mean nothing.
if ! locale -a 2>/dev/null | grep -qx 'en_US.UTF-8'; then
  echo "run: the en_US.UTF-8 locale is not installed (locale -a does not list it), and the expectations were frozen under it; refusing to run in another locale" >&2
  exit 3
fi
LC_ALL=en_US.UTF-8
export LC_ALL

# Colour is the same kind of inheritance. A layout that renders for a terminal reads NO_COLOR
# (lib/render.sh), and a verb run from inside a Claude Code session inherits FORCE_COLOR
# (lib/answer.sh, lib/dispatch.sh), so a calling shell that has either changes what a scenario is
# handed. render-matrix already scrubs both for its own terminal. Both are unset here and neither is
# set, so every scenario starts from one baseline and a scenario that tests colour chooses its own.
unset NO_COLOR FORCE_COLOR

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
tmproot=$(mktemp -d "${TMPDIR:-/tmp}/baton-tests.XXXXXX")
tmproot=$(cd "$tmproot" && pwd -P)

# Everything the run starts is the run's to stop, and the temporary root goes on every way out: an
# end, an error, an abandon, and a TERM or INT from whoever started it. The relay's deadline kill
# names run.sh alone, and the HUP its launch ignores cannot be trapped. Each worker leads a process
# group of its own, and every process a scenario starts stays in that group, the detached ones
# included. `script -q` is the exception: it puts its child in a session of its own, and with HUP
# ignored that child outlives `script`, so it is found by ancestry before anything is stopped and
# its group is remembered after the child has been handed to launchd. cleanup stops claims and
# releases the workers, which an idle one obeys within 0.2 s; it then TERMs the group of each worker
# still busy, while its leader lives, and every other process the run owns, gives what is left five
# seconds before it KILLs it by pid, and removes the root. Its result counts: a root it could not
# remove fails a run that had passed.
workers=
cleanup_done=
cleanup_status=0
run_signalled=

# cleanup_list: the processes the run owns, other than its live workers, into $cl_pids, and the pty
# session groups seen so far into $cl_sessions. Owned is a descendant of this shell, a member of a
# group of a worker that was alive when cleanup began, or a member of a session group.
cleanup_list() {
  ps -A -o pid=,ppid=,pgid= > "$tmproot/.ps" 2>/dev/null &
  cl_ps=$!
  wait "$cl_ps"
  awk -v main="$$" -v ps="$cl_ps" -v groups="$cl_groups" -v live="$(jobs -rp | tr '\n' ' ')" \
      -v sessions="$cl_sessions" '
    { pid[NR] = $1; ppid[NR] = $2; pgid[NR] = $3 }
    END {
      n = split(groups, a, " "); for (i = 1; i <= n; i++) group[a[i]] = 1
      n = split(live, a, " "); for (i = 1; i <= n; i++) worker[a[i]] = 1
      n = split(sessions, a, " "); for (i = 1; i <= n; i++) session[a[i]] = 1
      desc[main] = 1
      do {
        grew = 0
        for (i = 1; i <= NR; i++) if (!(pid[i] in desc) && (ppid[i] in desc)) { desc[pid[i]] = 1; grew = 1 }
      } while (grew)
      for (i = 1; i <= NR; i++) if ((pid[i] in desc) && pid[i] == pgid[i] && !(pid[i] in group)) session[pid[i]] = 1
      for (s in session) print "s", s
      for (i = 1; i <= NR; i++) {
        if (pid[i] == main || pid[i] == ps || (pid[i] in worker)) continue
        if ((pid[i] in desc) || (pgid[i] in group) || (pgid[i] in session)) print "p", pid[i]
      }
    }' "$tmproot/.ps" > "$tmproot/.owned"
  cl_pids=
  while read -r cl_kind cl_id; do
    case "$cl_kind" in
      s) case " $cl_sessions " in *" $cl_id "*) ;; *) cl_sessions="$cl_sessions $cl_id" ;; esac ;;
      p) cl_pids="$cl_pids $cl_id" ;;
    esac
  done < "$tmproot/.owned"
}

# cleanup: once per run, whichever way it ends; a second call returns the first one's result.
cleanup() {
  if [ -n "$cleanup_done" ]; then return "$cleanup_status"; fi
  cleanup_done=1
  set +e +m
  cl_groups=$(jobs -rp | tr '\n' ' ')
  cl_sessions=
  cleanup_list
  if [ -d "$tmproot/.run" ]; then
    : > "$tmproot/.run/stop"
    for cl_w in $workers; do : > "$tmproot/.run/release.$cl_w"; done
  fi
  cl_n=0
  while [ -n "$(jobs -rp)" ] && [ "$cl_n" -lt 10 ]; do cl_n=$((cl_n + 1)); sleep 0.1; done
  for cl_w in $(jobs -rp); do kill -TERM -- "-$cl_w" 2>/dev/null; done
  cleanup_list
  for cl_p in $cl_pids; do kill -TERM "$cl_p" 2>/dev/null; done
  cl_n=0
  while :; do
    cleanup_list
    cl_live=$(jobs -rp)
    if [ -z "$cl_pids" ] && [ -z "$cl_live" ]; then break; fi
    cl_n=$((cl_n + 1))
    if [ "$cl_n" -ge 50 ]; then
      for cl_p in $cl_pids $cl_live; do kill -KILL "$cl_p" 2>/dev/null; done
      break
    fi
    sleep 0.1
  done
  wait 2>/dev/null
  for cl_log in "$tmproot"/.run/worker-*.log; do
    if [ -s "$cl_log" ]; then cat "$cl_log" >&2; fi
  done
  rm -rf "$tmproot" 2>/dev/null || { sleep 0.2; rm -rf "$tmproot"; }
  if [ -e "$tmproot" ]; then
    echo "run: could not remove $tmproot" >&2
    cleanup_status=1
  fi
  return "$cleanup_status"
}

# The exit status stands unless cleanup failed on a run that had passed. A signal is handled once —
# a second TERM during cleanup changes nothing — and then raised again with its default action, so
# whoever sent it sees the run die of it.
run_exit() {
  re_status=$?
  cleanup || [ "$re_status" -ne 0 ] || re_status=1
  exit "$re_status"
}
run_signal() {
  [ -z "$run_signalled" ] || return 0
  run_signalled=1
  cleanup || :
  trap - "$1" EXIT
  kill -"$1" "$$"
}
trap run_exit EXIT
trap 'run_signal TERM' TERM
trap 'run_signal INT' INT
trap 'run_signal HUP' HUP
fails=0
count=0
freeze=${BATON_TESTS_FREEZE:-}

# The host's git configuration stays out: the fixture commit's hash, the worktree adds and the
# hooks a config could name must be the same on every Mac. The identity and dates a session
# inherits in its environment outrank a fixture's `-c user.name=…`, so they go too.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE

# prompt_normalise, the one rule, for the hash check below; iso_epoch, for the mtimes file.
BATON_DATE=date
. "$root/lib/log.sh"
. "$root/lib/derive.sh"

# run_abandoned: whether the owner has gone or the deadline has passed, saying which on stderr.
run_abandoned() {
  if [ -n "$run_owner" ] && ! kill -0 "$run_owner" 2>/dev/null; then
    echo "run: the owner, pid $run_owner, has gone; this run is abandoned and stops here" >&2
    return 0
  fi
  if [ -n "$run_deadline" ] && [ "$(( $(date +%s) - run_started ))" -ge "$run_deadline" ]; then
    echo "run: reached ${run_deadline}s; stopping rather than running unbounded" >&2
    return 0
  fi
  return 1
}

# scenario_run <dir>: one scenario, start to verdict — its fixtures built, its cmd run twice, its
# state diffed against expected/ — printing its lines and counting a failure in `fails`.
scenario_run() {
  sc=$1
  sc=${sc%/}
  name=$(basename "$sc")
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

  # A second fixture project, for the rules that are asked across projects — the cap, its order and
  # the holds (INV-07). Committed the same way at $tmp/Other; its commit is @OTHERCOMMIT@.
  othercommit=none-other-project
  if [ -d "$sc/other" ]; then
    cp -R "$sc/other" "$tmp/Other"
    ( cd "$tmp/Other" \
      && git init -q -b main \
      && git add CLAUDE.md docs \
      && GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example GIT_AUTHOR_DATE=2026-09-01T00:00:00+0000 \
         GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example GIT_COMMITTER_DATE=2026-09-01T00:00:00+0000 \
         git commit -q -m "fixture" )
    othercommit=$(git -C "$tmp/Other" rev-parse HEAD)
  fi

  cp -R "$sc/home" "$tmp/home"
  # @COMMIT@ as well as @TMP@, because a handover artifact names the commit it merged as and the
  # fixture repository's hash is only known once it has been committed.
  find "$tmp/home" -type f -exec sed -i '' "s|@TMP@|$tmp|g; s|@COMMIT@|$commit|g; s|@OFFMAIN@|$offmain|g; s|@OTHERCOMMIT@|$othercommit|g" {} +
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
  # The background sessions' job states, as ~/.claude/jobs holds them: jobs/<job>/state.json.
  if [ -d "$sc/jobs" ]; then cp -R "$sc/jobs" "$tmp/jobs"; else mkdir "$tmp/jobs"; fi
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
        # A path under home/ is a file of the Baton home — a status file, whose modification time is
        # what "the freshest" means to the reserve — and anything else is under transcripts/.
        case "$mt_path" in home/*) mt_file=$tmp/$mt_path ;; *) mt_file=$tmp/transcripts/$mt_path ;; esac
        if [ ! -f "$mt_file" ]; then
          echo "FAIL  $name: mtimes names $mt_path, which the scenario does not have"
          fails=$((fails + 1))
          continue
        fi
        env TZ=UTC touch -t "$(TZ=UTC date -r "$((scnow - mt_ago))" +%Y%m%d%H%M.%S)" "$mt_file"
      done < "$sc/mtimes"
    fi
  fi

  for run in 1 2; do
    ( export BATON_HOME="$tmp/home" BATON_CLAUDE="$here/shim/claude" BATON_DATE="$here/shim/date" \
             BATON_CAFFEINATE="$here/shim/caffeinate" BATON_OSASCRIPT="$here/shim/osascript" BATON_OPEN="$here/shim/open" \
             BATON_SHIM="$tmp/shim" BATON_DAEMON_LOG="$tmp/shim/daemon.log" \
             BATON_TRANSCRIPTS="$tmp/transcripts" BATON_JOBS="$tmp/jobs" BATON_INSTALL_TEST=1 \
             BATON_PMSET="$here/shim/pmset" BATON_SYSCTL="$here/shim/sysctl" BATON_LAUNCHCTL="$here/shim/launchctl" \
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
  # The managed worktree root goes the way of the lock: a dispatch creates a whole git worktree of
  # the fixture project under home/worktrees/, hundreds of files whose content is the fixture's own
  # and whose .git pointer carries the temporary path. What a scenario means to assert about a
  # worktree is where it is and whether it was reused, and both are in the `dispatch` event and the
  # dispatch's own stdout line, which are diffed. A scenario that needs a worktree to exist before
  # the run makes one in `cmd`, outside home/, where it is not snapshotted either.
  rm -rf "$tmp/got/home/worktrees"
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
  find "$tmp/got" -type f -exec sed -i '' "s|$tmp|@TMP@|g; s|$commit|@COMMIT@|g; s|$offmain|@OFFMAIN@|g; s|$othercommit|@OTHERCOMMIT@|g" {} +

  # A scenario that builds commits of its own — a completion chain needs a baseline, a candidate and
  # a merge — writes "<NAME> <value>" per line to $tmp/subs and substitutes @NAME@ in its own home/.
  # Those values are put back here, so the expectation holds the names and not the hashes. Without
  # it every completion expectation would be pinned to the fixture project's tree, and adding a line
  # to a brief would move thirteen files that have nothing to do with the change.
  if [ -f "$tmp/subs" ]; then
    while read -r sub_name sub_value || [ -n "$sub_name" ]; do
      [ -n "$sub_name" ] && [ -n "$sub_value" ] || continue
      find "$tmp/got" -type f -exec sed -i '' "s|$sub_value|@$sub_name@|g" {} +
    done < "$tmp/subs"
  fi

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
}

# run_serial: the scenarios one after another, in this shell.
run_serial() {
  for sc in "$here"/scenarios/${BATON_TESTS_ONLY:-*}/; do
    if run_abandoned; then exit 3; fi
    # A glob that matches nothing is left as its own text by the shell; it names no scenario.
    [ -d "$sc" ] || continue
    count=$((count + 1))
    scenario_run "$sc"
  done
}

# worker: one of the run's workers, started as a job that leads its own process group. It takes, in
# name order, each scenario no other worker has claimed and runs it exactly as run_serial does, its
# lines and its failure count going to files under $rundir. It stops claiming when the run says stop,
# when a scenario of its own ended in an error (a serial run would have stopped there), when the
# owner or the deadline abandons the run, and when the shell that started it has gone, which it tells
# by its own parent becoming launchd (pids are reused within a run, so `kill -0` on the shell cannot
# tell). Then it waits to be released, so a group the run signals always has its leader alive; if its
# shell has gone, nothing will release it, and it KILLs its own group instead.
worker() {
  set +e
  wk_self=$(exec sh -c 'echo $PPID')
  wk_stop=
  trap 'wk_stop=1' TERM
  for sc in "$here"/scenarios/${BATON_TESTS_ONLY:-*}/; do
    [ -d "$sc" ] || continue
    sc=${sc%/}
    name=${sc##*/}
    [ ! -e "$rundir/claim/$name" ] || continue
    [ -z "$wk_stop" ] && [ ! -e "$rundir/stop" ] || break
    ! worker_orphaned || break
    if [ -n "$run_owner$run_deadline" ] && wk_message=$(run_abandoned 2>&1); then
      mkdir "$rundir/abandoned" 2>/dev/null && printf '%s\n' "$wk_message" > "$rundir/abandoned/message"
      break
    fi
    mkdir "$rundir/claim/$name" 2>/dev/null || continue
    ( set -e; fails=0; scenario_run "$sc"; echo "$fails" > "$rundir/$name.fails" ) > "$rundir/$name.out" 2> "$rundir/$name.err"
    wk_status=$?
    echo "$wk_status" > "$rundir/$name.status" && mv "$rundir/$name.status" "$rundir/$name.done"
    if [ "$wk_status" -ne 0 ]; then : > "$rundir/stop"; break; fi
  done
  : > "$rundir/idle.$wk_self"
  until [ -e "$rundir/release.$wk_self" ]; do
    if worker_orphaned; then kill -KILL 0; fi
    sleep 0.2
  done
}
worker_orphaned() { [ "$(ps -o ppid= -p "$wk_self" 2>/dev/null | tr -d ' ')" = 1 ]; }

# run_busy: whether a worker is still running a scenario: alive, a job this shell has not reaped,
# and not yet idle.
run_busy() {
  rb_live=" $(jobs -rp | tr '\n' ' ') "
  for rb_w in $workers; do
    case "$rb_live" in *" $rb_w "*) [ -e "$rundir/idle.$rb_w" ] || return 0 ;; esac
  done
  return 1
}

# run_jobs_probe: whether a job started here leads a process group of its own, which is what the
# workers' ownership rests on.
run_jobs_probe() {
  set -m
  sleep 5 &
  jp_pid=$!
  set +m
  jp_group=$(ps -o pgid= -p "$jp_pid" 2>/dev/null | tr -d ' ')
  kill "$jp_pid" 2>/dev/null || :
  wait "$jp_pid" 2>/dev/null || :
  [ "$jp_group" = "$jp_pid" ]
}

# run_parallel <n>: n workers take the scenarios, and this shell prints each scenario's lines in name
# order once it has finished. A result is believed only if it adds up: one verdict line, and a
# failure count equal to its FAIL lines, the mtimes check's included. A scenario that ended in an
# error ends the run with its status once everything before it has been printed, as the serial loop
# stops there. A name no worker will finish is an abandon when the owner or the deadline said so,
# and a harness error otherwise.
run_parallel() {
  rundir=$tmproot/.run
  mkdir "$rundir" "$rundir/claim"
  rp_k=0
  set -m
  while [ "$rp_k" -lt "$1" ]; do
    rp_k=$((rp_k + 1))
    worker < /dev/null > "$rundir/worker-$rp_k.log" 2>&1 &
    workers="$workers $!"
  done
  set +m
  for sc in "$here"/scenarios/${BATON_TESTS_ONLY:-*}/; do
    [ -d "$sc" ] || continue
    sc=${sc%/}
    name=${sc##*/}
    until [ -e "$rundir/$name.done" ]; do
      if ! run_busy && [ ! -e "$rundir/$name.done" ]; then
        if [ -e "$rundir/abandoned" ]; then cat "$rundir/abandoned/message" >&2; exit 3; fi
        echo "run: no worker finished $name" >&2
        exit 1
      fi
      sleep 0.1
    done
    rp_status=$(cat "$rundir/$name.done")
    case "$rp_status" in
      0) ;;
      ''|*[!0-9]*) echo "run: $name ended with no status" >&2; exit 1 ;;
      *) cat "$rundir/$name.out"; cat "$rundir/$name.err" >&2; exit "$rp_status" ;;
    esac
    rp_fails=$(cat "$rundir/$name.fails" 2>/dev/null || true)
    case "$rp_fails" in ''|*[!0-9]*) rp_fails=none ;; esac
    rp_verdicts=$(grep -c -x -e "ok    $name" -e "FAIL  $name" "$rundir/$name.out" || true)
    rp_failed=$(grep -c '^FAIL  ' "$rundir/$name.out" || true)
    if [ "$rp_verdicts" != 1 ] || [ "$rp_fails" != "$rp_failed" ]; then
      cat "$rundir/$name.out"; cat "$rundir/$name.err" >&2
      echo "run: the result of $name does not add up: $rp_verdicts verdict lines, a failure count of $rp_fails, $rp_failed FAIL lines" >&2
      exit 1
    fi
    cat "$rundir/$name.out"
    if [ -s "$rundir/$name.err" ]; then cat "$rundir/$name.err" >&2; fi
    fails=$((fails + rp_fails))
    count=$((count + 1))
  done
}

run_total=0
for sc in "$here"/scenarios/${BATON_TESTS_ONLY:-*}/; do
  if [ -d "$sc" ]; then run_total=$((run_total + 1)); fi
done
run_jobs=$(( $(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || echo 1) / 3 ))
case "${BATON_TESTS_JOBS:-}" in
  '') ;;
  *[!0-9]*|0*) echo "run: BATON_TESTS_JOBS is not a positive whole number ($BATON_TESTS_JOBS); using $run_jobs" >&2 ;;
  *) run_jobs=$BATON_TESTS_JOBS ;;
esac
if [ -n "$freeze" ] || [ "$run_jobs" -lt 2 ] || [ "$run_total" -lt 2 ]; then
  run_serial
elif run_jobs_probe; then
  if [ "$run_jobs" -gt "$run_total" ]; then run_jobs=$run_total; fi
  run_parallel "$run_jobs"
else
  echo "run: a job started here does not lead a process group of its own, so the scenarios run one after another" >&2
  run_serial
fi

echo "$count scenarios, $fails failed"
[ "$fails" -eq 0 ]
