#!/bin/sh
# macOS lockf locks the open file description inherited through fd 9. Never unlink it:
# existence is not ownership, and the kernel releases the lock after abrupt process death.
set -eu
lock_take() {
  mkdir -p "$BATON_HOME"
  exec 9>"$BATON_HOME/mutation.lock"
  /usr/bin/lockf -s -t 0 9 || { echo 'baton: another mutation is running; status remains available' >&2; exit 75; }
  BATON_LOCK_OWNER=$$
  trap lock_release EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}
lock_require() {
  [ "${BATON_LOCK_OWNER:-}" = "$$" ] || { echo 'baton: mutation requires the lock' >&2; return 1; }
}
lock_release() {
  unset BATON_LOCK_OWNER
  exec 9>&-
}
