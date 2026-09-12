#!/bin/sh
# lib/tick.sh — the tick: the eight steps of docs/ARCHITECTURE.md §4.1, under the lock, for every
# registered project, and then the marker. The tick remembers nothing (REQ-TICK-02): every fact it
# acts on is a derivation over the five inputs — the dispatch log, `claude agents --json`, the
# inbox, the plan file and one git check — so a sleep, a restart or a killed process leaves the
# same inputs for the next run and every tick is a recovery.
#
# Three steps are holes this milestone leaves named rather than filled, so that the milestone which
# fills each one adds a body and does not rewrite the spine:
#   step 4  waits, retries and rulings are M04's; M03 does only the caffeinate re-arm, which writes
#           no event, so the step still logs nothing.
#   step 6  M03 dispatches a `run` disposition and nothing else. `wait`, `held` against a cleared
#           gate, and the two things that escalate — a `run` the plan makes ineligible, and a
#           plan-eligible milestone no handover lists — are M06's.
#   step 7  the holds, the reserve and the cap are M06's. M03 applies neither, which is safe only
#           because the one plan Baton drives before M06 has a single lane.
set -eu

# lock_stale_report: one line when the lock exists and is older than the interval, printed before
# anything else by every verb (REQ-TICK-03). A verb runs for seconds and launchd fires every sixty,
# so a lock past the interval is a tick that died holding it, and the person reads why the verb is
# about to refuse rather than a bare "lock held".
lock_stale_report() {
  [ -d "$BATON_HOME/lock" ] || return 0
  ls_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null) || return 0
  ls_epoch=$(iso_epoch "$ls_at" 2>/dev/null) || return 0
  ls_age=$(( $(now_epoch) - ls_epoch ))
  [ "$ls_age" -ge "$BATON_TICK_SECONDS" ] || return 0
  printf 'stale lock  %s held by pid %s since %s (%s ago)\n' "$BATON_HOME/lock" \
    "$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '?')" "$ls_at" "$(duration "$ls_age")"
}

# lock_stale_break: the tick alone, before it takes the lock. A lock past the interval whose holder
# is gone cannot belong to a live verb, and leaving it would stop the relay entirely until a person
# noticed — the one failure that costs a whole night. So the tick clears it and records what it
# found; a lock whose pid is still alive is left alone, and the tick refuses as any verb does.
# Prints the escalation's carries when it broke one, nothing when it did not.
lock_stale_break() {
  [ -d "$BATON_HOME/lock" ] || return 0
  lb_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null) || return 0
  lb_pid=$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '')
  lb_epoch=$(iso_epoch "$lb_at" 2>/dev/null) || return 0
  lb_age=$(( $(now_epoch) - lb_epoch ))
  [ "$lb_age" -ge "$BATON_TICK_SECONDS" ] || return 0
  if [ -n "$lb_pid" ] && kill -0 "$lb_pid" 2>/dev/null; then return 0; fi
  rm -rf "$BATON_HOME/lock"
  jq -nc --arg p "${lb_pid:-unknown}" --arg at "$lb_at" --argjson age "$lb_age" \
    --arg d "the lock was held by pid ${lb_pid:-unknown} since $lb_at ($(duration "$lb_age")) and its holder is gone; it has been cleared and the tick proceeded" \
    '{pid: $p, held_since: $at, held_seconds: $age, detail: $d}'
}

# marker_write: ~/.baton/last-tick, written last and atomically, after the work and after the lock
# is released, so that it means "a tick completed" and nothing weaker (REQ-TICK-06, INV-11). A tick
# that dies halfway leaves the previous value, which is what makes the gap report honest.
marker_write() {
  printf '%s\n' "$(baton_now)" > "$BATON_HOME/last-tick.tmp"
  mv "$BATON_HOME/last-tick.tmp" "$BATON_HOME/last-tick"
}

# self_check_failed_once <project> <stage> <path> <detail> [<extra json>]: the event, once while the
# condition holds. The event table calls this the project-scope park written every tick; written
# every tick it would be 1,440 identical lines a day through every derivation that reads the log,
# and the second run of a scenario would change the state, which INV-05 forbids. So it is written
# when what failed differs from the newest self_check_failed for the project — a persistent failure
# records once, a changed one records again — and the project is skipped for the rest of every tick
# either way, so nothing Baton does depends on the writing.
self_check_failed_once() {
  sf_fields=$(jq -nc --arg s "$2" --arg p "$3" --arg d "$4" --argjson x "${5:-"{}"}" \
    '{stage: $s, path: $p, detail: $d} + $x')
  sf_log=$(log_json) || { echo "$sf_log" >&2; return 1; }
  sf_prev=$(printf '%s' "$sf_log" | jq -c --arg p "$1" \
    '[ .[] | select(.kind == "self_check_failed" and .project == $p) ] | last
     | if . == null then {} else del(.at, .kind, .project) end')
  [ "$sf_prev" != "$sf_fields" ] || return 0
  log_event self_check_failed "$1" "" "" "" "$sf_fields"
  notify "$(notify_title "$1" "" "self-check")" "$4"
}

# self_check <project>: step 1 for one project — read the plan file in full, parse both tables, ask
# git for main's head. Either failing parks the project and skips it for the rest of the tick
# (REQ-TICK-05). The read is a `cat` and never a `test -r`: under a launchd job metadata succeeds
# while content fails, so a readability guard passes right before the read fails (D-012), and this
# is also how a Full Disk Access grant revoked by a macOS update is heard about within a minute.
# Prints the parsed plan document on success; the failure's detail on stdout with status 1.
self_check() {
  sc_pj=$BATON_HOME/projects/$1/project.json
  if ! sc_path=$(jq -er .path "$sc_pj" 2>/dev/null) || ! sc_plan=$(jq -er .plan "$sc_pj" 2>/dev/null); then
    self_check_failed_once "$1" read "$sc_pj" "the registration names no path and plan"
    echo "$sc_pj lacks path or plan"; return 1
  fi
  sc_file=$sc_path/$sc_plan
  if ! sc_body=$(cat "$sc_file" 2>&1); then
    self_check_failed_once "$1" read "$sc_file" "the plan file cannot be read: $sc_body"
    echo "the plan file $sc_file cannot be read: $sc_body"; return 1
  fi
  if ! sc_tables=$(plan_tables "$sc_file"); then
    sc_detail=$(printf '%s' "$sc_tables" | jq -r '"the \(.table) table, row \(.row), cell \(.cell): \(.detail)"')
    self_check_failed_once "$1" parse "$sc_file" "$sc_detail" \
      "$(printf '%s' "$sc_tables" | jq -c '{table, row, cell}')"
    echo "$sc_file does not parse: $sc_detail"; return 1
  fi
  if ! sc_head=$(git -C "$sc_path" rev-parse HEAD 2>&1); then
    self_check_failed_once "$1" git "$sc_path" "git rev-parse HEAD failed: $sc_head"
    echo "git -C $sc_path rev-parse HEAD failed: $sc_head"; return 1
  fi
  printf '%s\n' "$sc_tables"
}

# caffeinate_armed <pid>: whether a holder is already watching that pid. The whole argv is matched,
# so the seam decides the answer: under the tests it names a shim no live process carries, so the
# answer is always no and a fixture's calls.log is deterministic; in the installed relay it names
# /usr/bin/caffeinate, and only Baton starts one of those. Without the test, re-arming every tick
# would leave one live holder per lane per minute — several hundred processes by morning.
caffeinate_armed() {
  ps -Aww -o args= 2>/dev/null | grep -Fqx "$BATON_CAFFEINATE -i -w $1"
}

# caffeinate_timed <seconds>: the assertion an active wait holds, renewed by each tick, detached.
caffeinate_timed() {
  "$BATON_CAFFEINATE" -i -t "$1" < /dev/null > /dev/null 2>&1 &
}

# caffeinate_rearm <project> <rows json>: derivation 7. One -i -w holder per in-flight lane against
# the pid in the current row — the log stores no pid, because a restart of the background service
# gives the session a new one — and one -i -t for each active wait, renewed per interval and never
# past caffeinateMaxHours from the wait's start. Writes no event; `caffeinate -i` does not prevent
# lid-close sleep, which is the hardware condition `status` states (REQ-SETUP-07).
caffeinate_rearm() {
  cr_doc=$(derive_caffeinate "$1" "$2") || { echo "$cr_doc" >&2; return 1; }
  cr_n=$(printf '%s' "$cr_doc" | jq '.wake | length'); cr_i=0
  while [ "$cr_i" -lt "$cr_n" ]; do
    cr_pid=$(printf '%s' "$cr_doc" | jq -r ".wake[$cr_i].pid // empty"); cr_i=$((cr_i + 1))
    [ -n "$cr_pid" ] || continue
    caffeinate_armed "$cr_pid" || caffeinate_hold "$cr_pid"
  done
  cr_n=$(printf '%s' "$cr_doc" | jq '.timed | length'); cr_i=0
  while [ "$cr_i" -lt "$cr_n" ]; do
    cr_left=$(printf '%s' "$cr_doc" | jq -r ".timed[$cr_i].remaining_seconds"); cr_i=$((cr_i + 1))
    [ "$cr_left" -gt 0 ] || continue
    cr_span=$(( 2 * BATON_TICK_SECONDS ))
    [ "$cr_left" -ge "$cr_span" ] || cr_span=$cr_left
    caffeinate_timed "$cr_span"
  done
}

# tick_dispatchable <project> <plan json> <rows json>: steps 5, 6 and 7 for one project — the ids
# this tick will dispatch, one per line, in plan row order.
#
# Step 5, eligibility, is the plan's alone: every id in `Depends on` reads done, `Status` is blank,
# and no uncleared gate holds it. Step 6 intersects that with the disposition in force, which is
# the one in the newest archived `complete` handover of the project that lists the milestone, and
# in this milestone only `run` dispatches. Step 7 applies neither a hold nor the cap.
#
# One exclusion is not policy and belongs here rather than to M06: a milestone Baton already has an
# open attempt at is not a candidate. The plan reads `Status` blank for a milestone in flight — in
# flight is the log's knowledge, never the column's — so without it the tick would dispatch the
# same milestone again every sixty seconds for as long as its session ran.
tick_dispatchable() {
  td_log=$(log_json) || { echo "$td_log" >&2; return 1; }
  td_open=$(lanes_open "$1" "$td_log") || { echo "$td_open" >&2; return 1; }
  td_open=$(printf '%s' "$td_open" | jq -c '[ .[] | .milestone ]')
  td_consumed=$(derive_consumed "$1") || { echo "$td_consumed" >&2; return 1; }
  td_newest=$(printf '%s' "$td_consumed" | jq -r \
    '[ .consumed[] | select(.outcome == "complete" and .archive_present) ] | last | .archive // empty')
  td_runs='[]'
  if [ -n "$td_newest" ] && [ -f "$td_newest" ]; then
    td_runs=$(jq -c '[ .eligible[]? | select(.disposition == "run") | .milestone ]' "$td_newest" 2>/dev/null) \
      || td_runs='[]'
  fi
  printf '%s' "$2" | plan_eligible | while IFS= read -r td_id; do
    [ -n "$td_id" ] || continue
    printf '%s' "$td_open" | jq -e --arg m "$td_id" 'index($m) == null' > /dev/null || continue
    printf '%s' "$td_runs" | jq -e --arg m "$td_id" 'index($m) != null' > /dev/null || continue
    td_name=$(session_name "$1" "$td_id")
    printf '%s' "$3" | jq -e --arg n "$td_name" 'any(.[]; .name == $n and .pid != null)' > /dev/null && continue
    printf '%s\n' "$td_id"
  done
}

# tick_project <project> <plan json> <rows json> <this tick's clock>: steps 3 to 8 for one project.
# The takeover runs first because its result is the stand-off list the other three checks honour:
# Baton never acts on a lane a person is typing into (INV-04), and a lane whose transcript could not
# be scanned is not evidence that nobody is.
tick_project() {
  tp_over=$(takeover_check "$1" "$3") || return 1
  printf '%s' "$tp_over" | jq -r '.lines[]'
  tp_off=$(printf '%s' "$tp_over" | jq -r '.stand_off[]')
  crash_check "$1" "$3" "$tp_off" "$4" || return 1
  stall_check "$1" "$3" "$tp_off" || return 1
  long_running_check "$1" "$3" || return 1
  question_check "$1" "$3" "$tp_off" || return 1
  caffeinate_rearm "$1" "$3" || return 1
  tp_ids=$(tick_dispatchable "$1" "$2" "$3") || return 1
  printf '%s\n' "$tp_ids" | while IFS= read -r tp_id; do
    [ -n "$tp_id" ] || continue
    dispatch_one "$1" "$tp_id" "$2" "$3" || true
  done
}

# tick_run [<broken lock's carries>]: the eight steps, in order, for every registered project. The
# order is REQ-TICK-04 and it is load-bearing: stall, crash and the dispatch hold all test "no
# artifact in the inbox for this session", which is true only after the inbox has been read in the
# same tick.
tick_run() {
  tr_now=$(baton_now)
  if [ -n "${1:-}" ]; then
    escalation_write "" "" "" "" baton-unhealthy project "$1"
    printf '%s' "$1" | jq -r '"unhealthy   " + .detail'
  fi

  if tr_rows=$(rows_read); then
    tr_rows_ok=yes
  else
    tr_rows_ok=no
    echo "baton: claude agents --json could not be read; no lane is reconciled and nothing is dispatched" >&2
  fi

  # 1. Self-check, per registered project, in directory order. A project that fails is skipped for
  #    the rest of the tick; the others carry on.
  tr_projects=''
  tr_plans='{}'
  for tr_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$tr_pj" ] || continue
    tr_key=$(basename "$(dirname "$tr_pj")")
    if tr_plan=$(self_check "$tr_key"); then
      tr_projects="$tr_projects$tr_key
"
      tr_plans=$(printf '%s' "$tr_plans" | jq -c --arg k "$tr_key" --argjson p "$tr_plan" '. + {($k): $p}')
    else
      echo "self-check  $tr_key · $tr_plan"
    fi
  done

  # 2. Consume the inbox. Moving the call is all this is: inbox_consume is M02's, it takes the lock
  #    and nothing else, and the lock is already held here.
  inbox_consume "$tr_rows"

  # 3 to 8, per project. Nothing is reconciled or dispatched on a tick that could not read the
  # rows: without the listing every in-flight lane reads as a lane with no row, which is the crash
  # rule's whole input, and dispatching over a live session is the one mistake with no undo.
  [ "$tr_rows_ok" = yes ] || return 0
  printf '%s' "$tr_projects" | while IFS= read -r tr_key; do
    [ -n "$tr_key" ] || continue
    tick_project "$tr_key" "$(printf '%s' "$tr_plans" | jq -c --arg k "$tr_key" '.[$k]')" \
      "$tr_rows" "$tr_now" || return 1
  done

  # The gap belongs to Baton and not to a project, so it is read once, after every lane.
  gap_check "$tr_rows"
}

# verb_tick [<broken lock's carries>]: the tick under the lock, then the marker outside it. The
# marker is written after the lock is released and never before the work, so it means "a tick
# completed"; a tick that dies halfway leaves the previous value and the next tick's gap report is
# true (INV-11).
verb_tick() {
  tick_run "${1:-}"
  lock_release
  trap - EXIT
  marker_write
}
