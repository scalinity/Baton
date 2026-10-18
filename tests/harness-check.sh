#!/bin/sh
# tests/harness-check.sh — check the standing check's own guard paths, which no scenario reaches.
#
# tests/run.sh is proved by its scenarios, but its abandons, its signal handling and its ownership of
# what it starts are not: no scenario runs the runner. Run this after changing tests/run.sh. Each run
# under test gets a TMPDIR of its own, so a temporary root left behind can only be that run's, and
# every signal goes to a pid this script started. One line per check; exit 1 if any fails.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
run=$here/tests/run.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/baton-harness.XXXXXX")
trap 'rm -rf "$work"' EXIT
failed=0

pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; failed=1; }

# clean <dir>: the run whose TMPDIR is <dir>/tmp left no temporary root.
clean() { [ -z "$(ls -A "$1/tmp")" ]; }

# start <dir> [VAR=value...]: the suite in the background, its TMPDIR inside <dir> and its output
# in <dir>; its pid is $started (`env` execs it, so the pid is the runner's own).
start() {
  st_dir=$1; shift
  mkdir -p "$st_dir/tmp"
  env TMPDIR="$st_dir/tmp/" "$@" sh "$run" > "$st_dir/out" 2> "$st_dir/err" &
  started=$!
}

# until_line <dir> <text>: wait, at most thirty seconds, for <text> in the run's output.
until_line() {
  ul_n=0
  until grep -q -E -e "$2" "$1/out" 2>/dev/null || [ "$ul_n" -ge 300 ]; do ul_n=$((ul_n + 1)); sleep 0.1; done
}

# groups_of <pid>: the process groups the run's workers lead.
groups_of() { ps -A -o pid=,ppid=,pgid= | awk -v p="$1" '$2 == p && $1 == $3 { print $1 }' | tr '\n' ' '; }

# left_in <groups>: how many processes are still in those groups, after up to six seconds.
left_in() {
  li_n=0
  while :; do
    li_left=$(ps -A -o pgid= | awk -v g=" $1" 'index(g, " " $1 " ")' | wc -l | tr -d ' ')
    [ "$li_left" = 0 ] || [ "$li_n" -ge 60 ] && break
    li_n=$((li_n + 1)); sleep 0.1
  done
  echo "$li_left"
}

echo "harness-check: controlling terminal $(ps -o tty= -p $$ | tr -d ' ')"

for mode in parallel serial; do
  d=$work/deadline-$mode
  if [ "$mode" = serial ]; then start "$d" BATON_TESTS_JOBS=1 BATON_TESTS_DEADLINE=0 BATON_TESTS_ONLY='agent-*'
  else start "$d" BATON_TESTS_DEADLINE=0 BATON_TESTS_ONLY='agent-*'; fi
  st=0; { wait "$started"; } 2>/dev/null || st=$?
  if [ "$st" = 3 ] && grep -q 'reached 0s' "$d/err" && clean "$d"; then pass "a deadline abandons a $mode run with 3"
  else fail "a deadline abandons a $mode run with 3 (exit $st)"; fi
done

d=$work/owner
sh -c 'exit 0' & gone=$!; wait "$gone"
start "$d" BATON_TESTS_OWNER="$gone" BATON_TESTS_ONLY='agent-*'
st=0; { wait "$started"; } 2>/dev/null || st=$?
if [ "$st" = 3 ] && grep -q 'has gone' "$d/err" && clean "$d"; then pass "a gone owner abandons the run with 3"
else fail "a gone owner abandons the run with 3 (exit $st)"; fi

d=$work/parallel
start "$d" BATON_TESTS_ONLY='agent-*'
st=0; { wait "$started"; } 2>/dev/null || st=$?
if [ "$st" = 0 ] && ! grep -q 'does not lead a process group' "$d/err" && clean "$d"; then pass "jobs lead their own groups, so the run is parallel"
else fail "jobs lead their own groups, so the run is parallel (exit $st)"; fi

# A shell with job control makes the run the leader of its pipeline's group; the reader beside it in
# that group is not the run's to stop.
d=$work/pipeline
mkdir -p "$d/tmp"
st=0
sh -c 'set -m; env TMPDIR="$1/tmp/" BATON_TESTS_ONLY="agent-*" sh "$2" | cat > "$1/out"' _ "$d" "$run" 2> "$d/err" || st=$?
if [ "$st" = 0 ] && grep -q ' scenarios, 0 failed' "$d/out" && clean "$d"; then pass "a pipeline's reader outlives the run"
else fail "a pipeline's reader outlives the run (reader exit $st)"; fi

d=$work/term
start "$d" BATON_TESTS_JOBS=4 BATON_TESTS_ONLY='completion-*'
until_line "$d" '^(ok|FAIL)  '
groups=$(groups_of "$started")
kill -TERM "$started"
st=0; { wait "$started"; } 2>/dev/null || st=$?
left=$(left_in "$groups")
if [ "$st" = 143 ] && [ -n "$groups" ] && [ "$left" = 0 ] && clean "$d"; then pass "a TERM mid-run stops every worker group and removes the root"
else fail "a TERM mid-run stops every worker group and removes the root (exit $st, groups [$groups], $left left)"; fi

d=$work/term-exit
start "$d" BATON_TESTS_ONLY='agent-*'
until_line "$d" ' scenarios, '
kill -TERM "$started"
st=0; { wait "$started"; } 2>/dev/null || st=$?
if [ "$st" = 143 ] && clean "$d"; then pass "a TERM during the exit cleanup lets it finish"
else fail "a TERM during the exit cleanup lets it finish (exit $st)"; fi

exit "$failed"
