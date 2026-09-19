#!/bin/sh
# lib/lock.sh — the mkdir lock. Every verb enters through lock_take; the lock is released on EXIT.
# The directory holds pid and at so a stale lock can be reported with its age (M03).
#
# The stale-lock refusal is person-facing and goes through `lib/render.sh`, which anything sourcing
# this file on its own sources first (see `lib/log.sh`).
set -eu

lock_take() {
  mkdir -p "$BATON_HOME"
  if ! mkdir "$BATON_HOME/lock" 2>/dev/null; then
    lk_pid=$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '?')
    lk_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null || echo '?')
    render_failure err "baton: lock held at $BATON_HOME/lock (pid $lk_pid, since $lk_at); nothing done"
    exit 75
  fi
  trap lock_release EXIT
  printf '%s\n' "$$" > "$BATON_HOME/lock/pid"
  printf '%s\n' "$(baton_now)" > "$BATON_HOME/lock/at"
}

lock_release() {
  rm -rf "$BATON_HOME/lock"
}
