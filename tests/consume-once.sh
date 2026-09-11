#!/bin/sh
# The hand-run entry point for step 2 of the tick, which M03 will fold into `baton tick`. It takes
# the same lock every verb takes and runs the consume alone, so that the inbox can be consumed
# before the tick exists without any other step running.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

BATON_CLAUDE=${BATON_CLAUDE:-/Users/danny/.local/bin/claude}
BATON_DATE=${BATON_DATE:-date}
BATON_CAFFEINATE=${BATON_CAFFEINATE:-/usr/bin/caffeinate}
BATON_HOME=${BATON_HOME:-$HOME/.baton}
BATON_DAEMON_LOG=${BATON_DAEMON_LOG:-$HOME/.claude/daemon.log}
BATON_TRANSCRIPTS=${BATON_TRANSCRIPTS:-$HOME/.claude/projects}
export BATON_CLAUDE BATON_DATE BATON_CAFFEINATE BATON_HOME BATON_DAEMON_LOG BATON_TRANSCRIPTS

. "$root/lib/lock.sh"
. "$root/lib/log.sh"
. "$root/lib/plan.sh"
. "$root/lib/templates.sh"
. "$root/lib/dispatch.sh"
. "$root/lib/derive.sh"
. "$root/lib/inbox.sh"

lock_take
inbox_consume "$(rows_json)"
