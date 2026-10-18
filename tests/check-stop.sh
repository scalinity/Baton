#!/bin/sh
# tests/check-stop.sh <pid> — end a fixture's detached check runner without letting it write its marker.
#
# The runner (completion_check_run in lib/completion.sh) writes output.txt.exit as soon as its child
# exits. Killing the child first and the runner second, as a cmd's cleanup did, leaves the runner a
# moment in which it wakes and writes the marker — the stray output.txt.exit(.tmp) that made
# completion-check-no-restart fail under load. Stopped first, the runner cannot run a line when its
# child dies, and KILL cannot be caught, so it ends with no marker whatever the timing.
set -eu
pid=${1:?the check runner pid}
kill -STOP "$pid" 2>/dev/null || exit 0
n=0
until case "$(ps -o stat= -p "$pid" 2>/dev/null)" in *T*|'') true ;; *) false ;; esac; do
  n=$((n + 1)); [ "$n" -le 250 ] || { echo "check-stop: $pid did not stop" >&2; exit 1; }
  sleep 0.02
done
pkill -TERM -P "$pid" 2>/dev/null || true
kill -KILL "$pid" 2>/dev/null || true
# It is not this shell's child, so it is waited for by asking whether it is still there.
n=0
while kill -0 "$pid" 2>/dev/null; do
  n=$((n + 1)); [ "$n" -le 250 ] || { echo "check-stop: $pid is still alive" >&2; exit 1; }
  sleep 0.02
done
