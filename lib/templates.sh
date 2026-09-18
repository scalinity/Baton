#!/bin/sh
# lib/templates.sh — the texts Baton composes. M01: the slot line; M04 the continue and finish
# continuations. M05 adds the ruling label.
set -eu

# session_name <project> <milestone>: the name a dispatched session carries in claude agents and
# the only place a person sees which lane a row belongs to. The "Baton ·" prefix marks the session
# as the relay's; when the project key is Baton itself the prefix has already named the project, so
# the key is not repeated and the name reads "Baton · M02".
session_name() {
  if [ "$1" = Baton ]; then
    printf 'Baton · %s' "$2"
  else
    printf 'Baton · %s · %s' "$1" "$2"
  fi
}

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

# template_continue <class> <milestone> <attempt> <resume>: the text a session receives when the
# work is intact and only the turn ended — a wait, a transient, an unrecoverable error, or a crash.
# <class> is the StopFailure `error` value or `process gone` (docs/ARCHITECTURE.md §4.3), and the
# text is that section's, verbatim.
#
# "not a fault in the work" and "Do not switch model or work around a limit" are load-bearing and
# not padding: a model told only that it was resumed after a stop reads the stop as a signal about
# what it was doing and works around the limit — switching model, shrinking the task, skipping the
# check — which is the one thing a wait must not cause.
template_continue() {
  printf 'Baton resumed this session after a temporary stop (%s), not a fault in the work. %s, attempt %s, resume %s. Continue exactly where the last turn ended. If a tool call was interrupted, its result was not received — check the state before repeating it. Do not switch model or work around a limit. The handover artifact is still owed.' \
    "$1" "$2" "$3" "$4"
}

# template_finish <milestone> <attempt> <resume> <session>: the text after a `no-handover` only.
# It names the artifact's own path because the session is being asked for exactly one thing, and it
# lists the three outcomes because a session that cannot honestly write `complete` must still write
# something rather than end the turn again.
template_finish() {
  printf 'Baton resumed this session because its last turn ended without a handover artifact. %s, attempt %s, resume %s. Finish the close-out now by the method in CLAUDE.md and write %s/inbox/%s-%s.json, printing it last. Write the outcome that is true: complete if the merge is on main, asking if you need a ruling, otherwise stopped with its reason — unfinished carries a split.' \
    "$1" "$2" "$3" "$BATON_HOME" "$1" "$4"
}

# template_ruling <milestone> <attempt> <resume> <time> <question> <ruling>: the label `baton
# answer` delivers, docs/ARCHITECTURE.md §4.3 verbatim. It matches the two continuations so that a
# session meets one voice from Baton whatever the reason it was resumed for.
#
# **The question is quoted** because a session may have compacted since it asked, and a bare ruling
# can land on a question the model no longer holds — a ruling that names its question cannot be
# applied to the wrong one. The time is the escalation's own, so the quote is dated.
#
# **"decided" is the load-bearing word.** A model handed an opinion weighs it; a model handed a
# decision applies it. The three refusals after it — do not re-open, do not ask again, do not weigh
# alternatives — exist because a session that re-opens a ruling asks the same question again, and
# the second ask costs a person a second night.
#
# The ruling sits in its own paragraph so that a person's words are never run together with
# Baton's, and "from the person" is dropped: a ruling has no other source.
template_ruling() {
  printf 'Baton resumed this session to deliver a ruling. %s, attempt %s, resume %s. You asked at %s: %s. The ruling below is decided: do not re-open it, do not ask again, and do not weigh alternatives against it.\n\n%s\n\nContinue from where the last turn ended. The handover artifact is still owed.' \
    "$1" "$2" "$3" "$4" "$5" "$6"
}
