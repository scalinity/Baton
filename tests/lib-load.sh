#!/bin/sh
# Sources the libraries in the order bin/baton does, for a scenario whose cmd calls a library
# function directly rather than through a verb. The seams are already exported by tests/run.sh.
# A derivation is not a verb and writes nothing, so nothing here takes the lock.
. "$ROOT/lib/lock.sh"
. "$ROOT/lib/log.sh"
. "$ROOT/lib/plan.sh"
. "$ROOT/lib/templates.sh"
. "$ROOT/lib/notify.sh"
. "$ROOT/lib/dispatch.sh"
. "$ROOT/lib/candidates.sh"
. "$ROOT/lib/derive.sh"
. "$ROOT/lib/inbox.sh"
. "$ROOT/lib/rows.sh"
. "$ROOT/lib/status.sh"
. "$ROOT/lib/escalate.sh"
. "$ROOT/lib/answer.sh"
. "$ROOT/lib/stops.sh"
. "$ROOT/lib/declared.sh"
. "$ROOT/lib/waits.sh"
. "$ROOT/lib/tick.sh"
