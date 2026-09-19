#!/bin/sh
# Step 2 of the tick, alone, under the same lock. `baton tick` now runs the same call in its own
# order, and this is what lets the consume scenarios assert on consumption and nothing else: run
# through the tick they would also assert the self-check, the row reconciliation, the marker and
# whatever the tick decided to dispatch, and a fixture about a rejected artifact would break when
# an unrelated rule changed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

BATON_CLAUDE=${BATON_CLAUDE:-/Users/danny/.local/bin/claude}
BATON_DATE=${BATON_DATE:-date}
BATON_CAFFEINATE=${BATON_CAFFEINATE:-/usr/bin/caffeinate}
BATON_OSASCRIPT=${BATON_OSASCRIPT:-/usr/bin/osascript}
BATON_HOME=${BATON_HOME:-$HOME/.baton}
BATON_DAEMON_LOG=${BATON_DAEMON_LOG:-$HOME/.claude/daemon.log}
BATON_TRANSCRIPTS=${BATON_TRANSCRIPTS:-$HOME/.claude/projects}
export BATON_CLAUDE BATON_DATE BATON_CAFFEINATE BATON_OSASCRIPT BATON_HOME BATON_DAEMON_LOG \
  BATON_TRANSCRIPTS

. "$root/lib/render.sh"
. "$root/lib/permissions.sh"
. "$root/lib/lock.sh"
. "$root/lib/log.sh"
. "$root/lib/plan.sh"
. "$root/lib/templates.sh"
. "$root/lib/notify.sh"
. "$root/lib/dispatch.sh"
. "$root/lib/derive.sh"
. "$root/lib/completion.sh"
. "$root/lib/inbox.sh"
. "$root/lib/status.sh"
. "$root/lib/escalate.sh"
. "$root/lib/stops.sh"

lock_take
inbox_consume "$(rows_json)"
