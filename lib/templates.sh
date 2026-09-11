#!/bin/sh
# lib/templates.sh — the texts Baton composes. M01: the slot line. M04 adds continue and finish;
# M05 the ruling label.
set -eu

# slot_line_text <worktree> <branch> <canonical> <also-in-flight> <attempt> <commit>
# The paragraph that replaces part 2 of a kickoff prompt at dispatch. <also-in-flight> is the
# comma-joined list "M28 (worktree Reclaim-M28, brief docs/milestones/M28.md)" or empty. The
# attempt sentence appears from attempt 2 on, naming the commit the branch stands at.
slot_line_text() {
  sl="WHAT ELSE IS IN FLIGHT. You are working in $1 on branch $2; the canonical checkout is $3 — merge there at close-out and refresh there."
  if [ -n "$4" ]; then
    sl="$sl Also in flight: $4."
  else
    sl="$sl Nothing else is in flight."
  fi
  sl="$sl Stage only your own paths; never git add -A."
  if [ "$5" -ge 2 ]; then
    sl="$sl This is attempt $5 at this milestone; a previous attempt left work on this branch at $6, and the brief may hold completion evidence, which the recovery clause covers."
  fi
  sl="$sl Do not start the milestone after this one."
  printf '%s' "$sl"
}
