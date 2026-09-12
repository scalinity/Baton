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
  printf 'stale lock  %s held by pid %s since %s (%s ago); if no verb is running, remove it\n' \
    "$BATON_HOME/lock" "$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '?')" \
    "$ls_at" "$(duration "$ls_age")"
}

# lock_stale_break: the tick alone, before it takes the lock. A lock past the interval whose holder
# is gone cannot belong to a live verb, and leaving it would stop the relay entirely until a person
# noticed — the one failure that costs a whole night. So the tick clears it and records what it
# found; a lock whose pid is still alive is left alone, and the tick refuses as any verb does.
# Prints the escalation's carries when it broke one, nothing when it did not.
#
# The break is a rename and not a plain removal. Reading the lock, asking after its pid and removing
# it are three steps with forks between them, and a hand run starting in the same second could take
# the lock in that window — a plain `rm -rf` would then delete a live holder's lock and two ticks
# would run at once, which is the one thing INV-02 exists for. A rename moves the directory out of
# the way in one step, so exactly one process can claim it; what was claimed is then checked against
# what was judged, and a lock somebody else has since taken is put back untouched.
lock_stale_break() {
  [ -d "$BATON_HOME/lock" ] || return 0
  lb_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null) || return 0
  lb_pid=$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '')
  lb_epoch=$(iso_epoch "$lb_at" 2>/dev/null) || return 0
  lb_age=$(( $(now_epoch) - lb_epoch ))
  [ "$lb_age" -ge "$BATON_TICK_SECONDS" ] || return 0
  if [ -n "$lb_pid" ] && kill -0 "$lb_pid" 2>/dev/null; then return 0; fi
  lb_claim=$BATON_HOME/lock.stale.$$
  mv "$BATON_HOME/lock" "$lb_claim" 2>/dev/null || return 0
  if [ "$(cat "$lb_claim/at" 2>/dev/null)" != "$lb_at" ]; then
    mv "$lb_claim" "$BATON_HOME/lock" 2>/dev/null || rm -rf "$lb_claim"
    return 0
  fi
  rm -rf "$lb_claim"
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

# self_check_failed_once <project> <stage> <path> <detail> [<extra json>]: the event and the
# project-scope escalation, once while the condition stands.
#
# The event table called this a park written every tick. Written every tick it would be 1,440
# identical lines a day through every derivation that reads the log whole, and the second run of a
# scenario would change the state, which INV-05 forbids. So the open escalation is the key, exactly
# as it is for a live question: one is raised while none stands, and the first self-check that
# passes resolves it. The class is the log's own — a read or a git failure is `plan-unreadable`,
# a parse failure `plan-unparseable` — which is what makes `status` print the project as held and
# what makes a grant revoked, re-granted and revoked again notify each time (D-041).
self_check_failed_once() {
  sfc_fields=$(jq -nc --arg s "$2" --arg p "$3" --arg d "$4" --argjson x "${5:-"{}"}" \
    '{stage: $s, path: $p, detail: $d} + $x')
  sfc_class=plan-unreadable
  [ "$2" != parse ] || sfc_class=plan-unparseable
  sfc_parked=$(derive_parked "$1") || { echo "$sfc_parked" >&2; return 1; }
  if printf '%s' "$sfc_parked" | jq -e --arg c "$sfc_class" \
       'any(.parked[]; .scope == "project" and .class == $c)' > /dev/null; then
    return 0
  fi
  log_event self_check_failed "$1" "" "" "" "$sfc_fields"
  escalation_write "$1" "" "" "" "$sfc_class" project "$sfc_fields"
}

# park_resolve <project> <class regex> <what cleared it>: the unpark a fixed condition earns.
# REQ-ESC-05 gives a park three ways out, and one of them is a person's edit that the next tick
# re-reads — which only the tick can observe, because only the tick re-reads. So this resolution is
# written here rather than waiting for `baton answer`, which resolves the ruling route and not this
# one. Without it a park outlives the thing it named: `status` would show a plan file as broken
# after it was fixed, and `derive_gap`'s "a gap with nothing to do is not one" would never be true
# again, because a parked lane is a lane.
park_resolve() {
  prs_parked=$(derive_parked "$1") || { echo "$prs_parked" >&2; return 1; }
  prs_open=$(printf '%s' "$prs_parked" | jq -c --arg c "$2" \
    '[ .parked[] | select(.scope == "project" and (.class | test($c))) ]')
  prs_n=$(printf '%s' "$prs_open" | jq length); prs_i=0
  while [ "$prs_i" -lt "$prs_n" ]; do
    prs_e=$(printf '%s' "$prs_open" | jq -c ".[$prs_i]"); prs_i=$((prs_i + 1))
    prs_at=$(printf '%s' "$prs_e" | jq -r .at)
    log_event resolution "$(printf '%s' "$prs_e" | jq -r '.project // ""')" "" "" "" \
      "$(jq -nc --arg a "$prs_at" '{how: "edit", escalation_at: $a}')"
    printf 'resolved  %s · %s · the park raised at %s is closed\n' \
      "$(printf '%s' "$prs_e" | jq -r '.project // "all projects"')" "$3" "$prs_at"
  done
}

# self_check <project>: step 1 for one project — read the plan file in full, parse both tables, ask
# git for the checkout's head. Either failing parks the project and skips it for the rest of the
# tick (REQ-TICK-05). The read is a `cat` and never a `test -r`: under a launchd job metadata
# succeeds while content fails, so a readability guard passes right before the read fails (D-012),
# and that is also how a Full Disk Access grant revoked by a macOS update is heard about in a minute.
# Prints the parsed plan document on success; the failure's detail on stdout with status 1.
self_check() {
  sck_pj=$BATON_HOME/projects/$1/project.json
  if ! sck_path=$(jq -er .path "$sck_pj" 2>/dev/null) || ! sck_plan=$(jq -er .plan "$sck_pj" 2>/dev/null); then
    self_check_failed_once "$1" read "$sck_pj" "the registration names no path and plan"
    echo "$sck_pj lacks path or plan"; return 1
  fi
  sck_file=$sck_path/$sck_plan
  if ! sck_body=$(cat "$sck_file" 2>&1); then
    self_check_failed_once "$1" read "$sck_file" "the plan file cannot be read: $sck_body"
    echo "the plan file $sck_file cannot be read: $sck_body"; return 1
  fi
  if ! sck_tables=$(plan_tables "$sck_file"); then
    sck_detail=$(printf '%s' "$sck_tables" | jq -r '"the \(.table) table, row \(.row), cell \(.cell): \(.detail)"')
    self_check_failed_once "$1" parse "$sck_file" "$sck_detail" \
      "$(printf '%s' "$sck_tables" | jq -c '{table, row, cell}')"
    echo "$sck_file does not parse: $sck_detail"; return 1
  fi
  if ! sck_head=$(git -C "$sck_path" rev-parse HEAD 2>&1); then
    self_check_failed_once "$1" git "$sck_path" "git rev-parse HEAD failed: $sck_head"
    echo "git -C $sck_path rev-parse HEAD failed: $sck_head"; return 1
  fi
  printf '%s\n' "$sck_tables"
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
  td_parked=$(derive_parked "$1") || { echo "$td_parked" >&2; return 1; }
  td_consumed=$(derive_consumed "$1") || { echo "$td_consumed" >&2; return 1; }
  # The disposition in force is the one in the newest archived `complete` handover **that lists the
  # milestone**, not the newest handover full stop: a milestone an older handover named and the
  # newest does not mention is neither `run` nor `omitted`, and taking only the newest would drop it
  # silently. Archives newest first; the first entry naming the id wins.
  td_dispo=$(printf '%s' "$td_consumed" | jq -r \
      '[ .consumed[] | select(.outcome == "complete" and .archive_present) | .archive ] | reverse | .[]' \
    | while IFS= read -r td_a; do
        [ -f "$td_a" ] || continue
        jq -c '[ .eligible[]? | {milestone, disposition} ]' "$td_a" 2>/dev/null || true
      done | jq -sc 'add // []')
  printf '%s' "$2" | plan_eligible | while IFS= read -r td_id; do
    [ -n "$td_id" ] || continue
    printf '%s' "$td_open" | jq -e --arg m "$td_id" 'index($m) == null' > /dev/null || continue
    # A lane a person has to answer is not a candidate. That covers a `dispatch-failed` park, which
    # is what bounds the retry below, and an entry the consume dropped for a brief pointer that is
    # not on `main` — the handover file keeps such an entry, so its `run` would otherwise dispatch a
    # milestone the same tick had just parked.
    printf '%s' "$td_parked" | jq -e --arg m "$td_id" \
      'any(.parked[]; .milestone == $m and .scope == "lane") | not' > /dev/null || continue
    printf '%s' "$td_dispo" | jq -e --arg m "$td_id" \
      'first(.[] | select(.milestone == $m)) | .disposition == "run"' > /dev/null 2>&1 || continue
    # A Remote: yes milestone is M07's two-step dispatch. Skipped here rather than refused inside
    # dispatch_one, which would print to launchd.err every sixty seconds until M07 lands.
    printf '%s' "$2" | plan_row "$td_id" | jq -e '.remote != true' > /dev/null || continue
    td_name=$(session_name "$1" "$td_id")
    printf '%s' "$3" | jq -e --arg n "$td_name" 'any(.[]; .name == $n and .pid != null)' > /dev/null && continue
    printf '%s\n' "$td_id"
  done
}

# dispatch_failed_run <project> <milestone> <plan json> <rows json>: step 8 for one candidate, with
# the bound the retry needs. A dispatch that failed wrote no `dispatch` event, so the lane does not
# open and the milestone is a candidate again on the next tick — which is right for a transient
# cause and wrong for a permanent one, where it would spawn a process and write a line every sixty
# seconds for as long as the cause stood. The event table's rule is the bound: the second
# consecutive failure for the pair escalates, lane scope, and the park is then what stops the retry.
dispatch_try() {
  dt_project=$1; dt_id=$2
  dispatch_one "$dt_project" "$dt_id" "$3" "$4" && return 0
  dt_log=$(log_json) || { echo "$dt_log" >&2; return 0; }
  dt_fails=$(printf '%s' "$dt_log" | jq --arg p "$dt_project" --arg m "$dt_id" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch") ] | last | .i // -1) as $reset
    | [ $ev[] | select(.kind == "dispatch_failed" and .i > $reset) ] | length')
  [ "$dt_fails" -ge 2 ] || return 0
  dt_last=$(printf '%s' "$dt_log" | jq -c --arg p "$dt_project" --arg m "$dt_id" '
    [ .[] | select(.kind == "dispatch_failed" and .project == $p and .milestone == $m) ] | last
    | {stage, detail}')
  dt_carries=$(printf '%s' "$dt_last" | jq -c --argjson n "$dt_fails" \
    '{consecutive: $n, stage: .stage,
      detail: "\($n) dispatches in a row produced no session, the last at the \(.stage) stage: \(.detail)"}')
  escalation_write "$dt_project" "$dt_id" "" "" dispatch-failed lane "$dt_carries"
  printf 'dispatch  %s/%s · %s consecutive failures · the lane is parked\n' "$dt_project" "$dt_id" "$dt_fails"
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
    dispatch_try "$1" "$tp_id" "$2" "$3"
  done
}

# tick_run [<broken lock's carries>]: the eight steps, in order, for every registered project. The
# order is REQ-TICK-04 and it is load-bearing: stall, crash and the dispatch hold all test "no
# artifact in the inbox for this session", which is true only after the inbox has been read in the
# same tick.
tick_run() {
  tr_now=$(baton_now)
  # The stale lock the tick cleared before it took this one. It is a project-scope escalation
  # because REQ-TICK-03 names one, and it is resolved in the same breath because the condition it
  # names is already over: Baton kept working past it, which is what separates a message from a
  # park, and leaving it open would hold every project on something nobody has to do.
  if [ -n "${1:-}" ]; then
    escalation_write "" "" "" "" baton-unhealthy project "$1"
    printf '%s' "$1" | jq -r '"unhealthy   " + .detail'
    park_resolve "" '^baton-unhealthy$' 'the lock was cleared' > /dev/null
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
      park_resolve "$tr_key" '^plan-(unreadable|unparseable)$' 'the plan file reads again'
    else
      echo "self-check  $tr_key · $tr_plan"
    fi
  done

  # Nothing past the self-check happens on a tick that could not read the rows. Every rule from
  # here on reads "no live row" as a fact about a session, and a listing the service failed to
  # produce would make that true of every one of them: the consume would reject a handover a live
  # session is mid-writing and record an asking session as already stopped, the crash rule would
  # sight every lane, and a dispatch would be a dispatch over something already running. A handover
  # waiting one more minute costs nothing; `status` line 9 shows it waiting. The status says the
  # tick did not complete, so the marker is not written and the gap report is what tells the person.
  [ "$tr_rows_ok" = yes ] || { gap_check "$tr_rows"; return 3; }

  # 2. Consume the inbox. Moving the call is all this is: inbox_consume is M02's, it takes the lock
  #    and nothing else, and the lock is already held here.
  inbox_consume "$tr_rows" "$tr_rows_ok"

  # 3 to 8, per project.

  # A project whose reconciliation or dispatch fails is reported and the others carry on, which is
  # what step 1 already does for a project whose plan will not read. One lane with an unparseable
  # timestamp must not cost every other project its tick, every minute, until someone reads a log.
  printf '%s' "$tr_projects" | while IFS= read -r tr_key; do
    [ -n "$tr_key" ] || continue
    tick_project "$tr_key" "$(printf '%s' "$tr_plans" | jq -c --arg k "$tr_key" '.[$k]')" \
      "$tr_rows" "$tr_now" || echo "reconcile   $tr_key · the tick could not finish this project"
  done

  # The gap belongs to Baton and not to a project, so it is read once, after every lane.
  gap_check "$tr_rows"
}

# verb_tick [<broken lock's carries>]: the tick under the lock, then the marker outside it. The
# marker is written after the lock is released and never before the work, so it means "a tick
# completed"; a tick that dies halfway leaves the previous value and the next tick's gap report is
# true (INV-11).
#
# A tick that could not read the rows returns 3 and gets no marker either. It skipped six of the
# eight steps, so it did not complete, and saying it did would advance the clock the gap is measured
# against — which is the only thing that would tell a person the relay had been blind all night.
verb_tick() {
  vt_status=0
  tick_run "${1:-}" || vt_status=$?
  lock_release
  trap - EXIT
  [ "$vt_status" -ne 0 ] || marker_write
  return "$vt_status"
}
