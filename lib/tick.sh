#!/bin/sh
# lib/tick.sh — the tick: the eight steps of docs/ARCHITECTURE.md §4.1, under the lock, for every
# registered project, and then the marker. The tick remembers nothing (REQ-TICK-02): every fact it
# acts on is a derivation over the five inputs — the dispatch log, `claude agents --json`, the
# inbox, the plan file and one git check — so a sleep, a restart or a killed process leaves the
# same inputs for the next run and every tick is a recovery.
#
# Steps 3 and 4 run per project. Steps 5 and 6 run per project too, and collect candidates rather
# than dispatching them, because step 7's order is a question across projects — the project with
# fewer in flight goes first — and it can only be asked once every project has answered. Step 8 then
# runs once, in that order, under the cap (`dispatch_run`).
set -eu

# lock_stale_report: one line when the lock exists and is older than the interval, printed before
# anything else by every verb (REQ-TICK-03). A verb runs for seconds and launchd fires every sixty,
# so a lock past the interval used to be a tick that died holding it, and the person reads why the
# verb is about to refuse rather than a bare "lock held".
#
# Since D-148 a long hold is also the ordinary case: step 2 runs a target project's standing check
# under the lock, which is minutes for a suite of any size. So the age alone no longer says the
# holder is gone, and the pid is asked. A holder that answers `kill -0` is running, and the line
# says so and offers nothing to remove: `lock_stale_break` is safe because it asks the same
# question, but a person acting on advice to remove a live verb's lock is not. Only a holder that
# cannot be found — no pid recorded, or a pid nothing answers for — is called stale.
lock_stale_report() {
  [ -d "$BATON_HOME/lock" ] || return 0
  ls_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null || true)
  if ! ls_epoch=$(iso_epoch "$ls_at" 2>/dev/null); then
    ls_epoch=$(stat -f %m "$BATON_HOME/lock" 2>/dev/null) || return 0
    ls_at="directory mtime $ls_epoch"
  fi
  ls_age=$(( $(now_epoch) - ls_epoch ))
  [ "$ls_age" -ge "$BATON_TICK_SECONDS" ] || return 0
  ls_pid=$(cat "$BATON_HOME/lock/pid" 2>/dev/null || true)
  if [ -n "$ls_pid" ] && kill -0 "$ls_pid" 2>/dev/null; then
    render_row out action 'lock held   %s held by pid %s since %s (%s ago); its holder is running, so nothing here is stale\n' \
      "$(render_token out path "$BATON_HOME/lock")" "$ls_pid" \
      "$(render_token out timestamp "$ls_at")" "$(duration "$ls_age")"
    return 0
  fi
  render_row out action 'stale lock  %s held by pid %s since %s (%s ago); if no verb is running, remove it\n' \
    "$(render_token out path "$BATON_HOME/lock")" "${ls_pid:-?}" \
    "$(render_token out timestamp "$ls_at")" "$(duration "$ls_age")"
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
  lb_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null || true)
  lb_pid=$(cat "$BATON_HOME/lock/pid" 2>/dev/null || echo '')
  lb_stamp=
  if ! lb_epoch=$(iso_epoch "$lb_at" 2>/dev/null); then
    lb_stamp=$(stat -f %m "$BATON_HOME/lock" 2>/dev/null) || return 0
    lb_epoch=$lb_stamp
    lb_since="directory mtime $lb_epoch"
  else
    lb_since=$lb_at
  fi
  lb_age=$(( $(now_epoch) - lb_epoch ))
  [ "$lb_age" -ge "$BATON_TICK_SECONDS" ] || return 0
  if [ -n "$lb_pid" ] && kill -0 "$lb_pid" 2>/dev/null; then return 0; fi
  lb_claim=$BATON_HOME/lock.stale.$$
  mv "$BATON_HOME/lock" "$lb_claim" 2>/dev/null || return 0
  if [ "$(cat "$lb_claim/at" 2>/dev/null || true)" != "$lb_at" ] \
     || [ "$(cat "$lb_claim/pid" 2>/dev/null || true)" != "$lb_pid" ] \
     || { [ -n "$lb_stamp" ] && [ "$(stat -f %m "$lb_claim" 2>/dev/null)" != "$lb_stamp" ]; }; then
    mv "$lb_claim" "$BATON_HOME/lock" 2>/dev/null || rm -rf "$lb_claim"
    return 0
  fi
  rm -rf "$lb_claim"
  jq -nc --arg p "${lb_pid:-unknown}" --arg at "$lb_since" --argjson age "$lb_age" \
    --arg d "the lock was held by pid ${lb_pid:-unknown} since $lb_since ($(duration "$lb_age")) and its holder is gone; it has been cleared and the tick proceeded" \
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
  sfc_parked=$(derive_parked "$1") || { render_failure err "$sfc_parked"; return 1; }
  if printf '%s' "$sfc_parked" | jq -e --arg c "$sfc_class" \
       'any(.parked[]; .scope == "project" and .class == $c)' > /dev/null; then
    return 0
  fi
  log_event self_check_failed "$1" "" "" "" "$sfc_fields"
  escalate "$1" "" "" "" "$sfc_class" project "$sfc_fields"
}

# park_resolve <project> <class regex> <what cleared it>: the unpark a fixed condition earns.
# REQ-ESC-05 gives a park three ways out, and one of them is a person's edit that the next tick
# re-reads — which only the tick can observe, because only the tick re-reads. So this resolution is
# written here rather than waiting for `baton answer`, which resolves the ruling route and not this
# one. Without it a park outlives the thing it named: `status` would show a plan file as broken
# after it was fixed, and `derive_gap`'s "a gap with nothing to do is not one" would never be true
# again, because a parked lane is a lane.
park_resolve() {
  prs_parked=$(derive_parked "$1") || { render_failure err "$prs_parked"; return 1; }
  prs_open=$(printf '%s' "$prs_parked" | jq -c --arg c "$2" \
    '[ .parked[] | select(.scope == "project" and (.class | test($c))) ]')
  prs_n=$(printf '%s' "$prs_open" | jq length); prs_i=0
  while [ "$prs_i" -lt "$prs_n" ]; do
    prs_e=$(printf '%s' "$prs_open" | jq -c ".[$prs_i]"); prs_i=$((prs_i + 1))
    prs_at=$(printf '%s' "$prs_e" | jq -r .at)
    resolve "$(printf '%s' "$prs_e" | jq -r '.project // ""')" "" "" "" "$prs_at" edit
    render_row out record 'resolved  %s · %s · the park raised at %s is closed\n' \
      "$(render_token out lane "$(printf '%s' "$prs_e" | jq -r '.project // "all projects"')")" "$3" "$(render_token out timestamp "$prs_at")"
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
  # The project key, so that a project onboarding registered an adaptation for is read with it. A
  # project without one — Baton's own, and any registered before onboarding existed — is read
  # exactly as strictly as before, because `plan_adaptation` answers `{}` for it.
  if ! sck_tables=$(plan_tables "$sck_file" "$1"); then
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
  cr_doc=$(derive_caffeinate "$1" "$2") || { render_failure err "$cr_doc"; return 1; }
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

# dispatch_failed_run <project> <milestone> <plan json> <rows json>: step 8 for one candidate, with
# the bound the retry needs. A dispatch that failed wrote no `dispatch` event, so the lane does not
# open and the milestone is a candidate again on the next tick — which is right for a transient
# cause and wrong for a permanent one, where it would spawn a process and write a line every sixty
# seconds for as long as the cause stood. The event table's rule is the bound: the second
# consecutive failure for the pair escalates, lane scope, and the park is then what stops the retry.
dispatch_try() {
  dt_project=$1; dt_id=$2
  dispatch_one "$dt_project" "$dt_id" "$3" "$4" && return 0
  dt_log=$(log_json) || { render_failure err "$dt_log"; return 0; }
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
  escalate "$dt_project" "$dt_id" "" "" dispatch-failed lane "$dt_carries"
  render_row out action 'dispatch  %s/%s · %s consecutive failures · the lane is parked\n' "$(render_token out lane "$dt_project")" "$(render_token out milestone "$dt_id")" "$dt_fails"
}

# tick_project <project> <plan json> <rows json> <this tick's clock>: steps 3 and 4 for one project.
# The takeover runs first because its result is the stand-off list the other three checks honour:
# Baton never acts on a lane a person is typing into (INV-04), and a lane whose transcript could not
# be scanned is not evidence that nobody is.
tick_project() {
  # The three unparks a tick can see, before anything reads the parks. An edit a person made is their
  # decision arriving, a question answered in place is the row saying so, and a fork park whose
  # original no longer has a row is a worry that has ended without anyone acting; all three are facts
  # every later check reads, and a lane freed here is one step 4 acts on in the same tick rather than
  # a minute later. A lane whose condition still stands is parked again by the rule that parked it.
  edit_reread_check "$1" "$2" "$3" || return 1
  question_resolve_check "$1" "$3" || return 1
  fork_resolve_check "$1" "$3" || return 1
  tp_over=$(takeover_check "$1" "$3") || return 1
  # `takeover_check` returns its lines beside the machine stand-off list, because they are two
  # halves of one reading and a helper that printed as it went would be deciding for its caller.
  # The lines carry no styling of their own: they are rendered here, where they meet a stream.
  render_lines "$(printf '%s' "$tp_over" | jq -c .lines)" action
  tp_off=$(printf '%s' "$tp_over" | jq -r '.stand_off[]')
  crash_check "$1" "$3" "$tp_off" "$4" || return 1
  stall_check "$1" "$3" "$tp_off" || return 1
  long_running_check "$1" "$3" || return 1
  question_check "$1" "$3" "$tp_off" || return 1
  # Step 4. After the row checks, because a crash confirmed a moment ago is an ending this step
  # acts on, and before the caffeinate re-arm, because a wait this step starts is one the re-arm
  # then holds the Mac awake for.
  stops_run "$1" "$2" "$3" "$tp_off" || return 1
  caffeinate_rearm "$1" "$3" || return 1
}

# dispatch_run <candidates json> <plans json>: steps 7 and 8, once, across every project.
# The holds drop their candidates first — a model with a rate-limit or billing wait, and the Fable
# family while the reserve bites — and are silent about it, because each hold already wrote its own
# event and its own message and a line per candidate per minute would bury them. What is left is
# ordered by `cap_order` and dispatched while the count is below the cap.
#
# The count is every lane in flight across every project — derivation 1, which resolves each lane
# through its copy forks to the session currently carrying it and asks the rows for that session's
# pid. A question park is in it, because its session is live and waiting; a stopped `asking` session
# is not, because the consume stopped it. Counting rows by name would miss a copy fork, whose row the
# CLI names for itself (M05's live proof). The cap is the Mac's, so no project has a share of it.
#
# The listing is read here and not handed down from the top of the tick, because steps 3 and 4 make
# it out of date in the one way that matters: `redispatch` stops a session and opens a new attempt
# under a new one, and a resume that forked moves the lane onto the copy's id. Derivation 1 reads the
# log itself, so it already names those identities — but it joins them against the listing it is
# given, and against the tick's opening one a replaced lane matches no row, counts as nothing, and
# the cap admits a second and a third worker over the one recovery has just started (D-130). A fresh
# listing holds them, because `dispatch_one` records a session only once `row_for_id` has seen a row
# carrying its pid, and `fork_session` adopts a copy the same way.
#
# A listing that cannot be read is not an empty one. `[]` would say nothing is in flight and admit
# every candidate over whatever is running, which is the failure the read exists to prevent, so the
# pass fails instead and the tick is incomplete — the same answer the top of the tick gives.
#
# A dispatch that produced no session takes no slot — the count moves only on a new `dispatch` event,
# and the next candidate in order is tried in its place — unless it could not be proved to have
# started nothing. `do_unresolved` is that proof's absence: a launch whose worker was neither
# identified nor stopped may be running under no id Baton holds, so derivation 1 cannot see it and
# only a conservative count keeps the cap honest. It is read in the loop's own condition because
# `dispatch_try` can raise it, and it outlives this pass only as far as the process does: the next
# tick reads the listing from nothing, where a worker that really started is a row like any other.
dispatch_run() {
  # No candidate is no admission, and no admission asks the CLI anything: a tick with nothing to
  # dispatch neither takes a listing it would not read nor counts a cap it would not spend.
  [ "$(printf '%s' "$1" | jq length)" -gt 0 ] || return 0
  drn_cap=$(config_num cap 2)
  drn_rows=$(rows_read) || { render_failure err "claude agents --json could not be read before the cap was counted"; return 1; }
  drn_flight=$(derive_in_flight "" "$drn_rows") || { render_failure err "$drn_flight"; return 1; }
  drn_counts=$(printf '%s' "$drn_flight" | jq -c \
    '[ .in_flight[] | .project ] | group_by(.) | map({key: .[0], value: length}) | from_entries')
  drn_total=$(printf '%s' "$drn_flight" | jq '.in_flight | length')
  drn_kept='[]'
  drn_n=$(printf '%s' "$1" | jq length); drn_i=0
  while [ "$drn_i" -lt "$drn_n" ]; do
    drn_c=$(printf '%s' "$1" | jq -c ".[$drn_i]"); drn_i=$((drn_i + 1))
    hold_bites "$(printf '%s' "$drn_c" | jq -r '.model // ""')" && continue
    drn_kept=$(printf '%s' "$drn_kept" | jq -c --argjson c "$drn_c" '. + [$c]')
  done
  drn_order=$(cap_order "$drn_kept" "$drn_counts") || { render_failure err "the cap order could not be computed"; return 1; }
  # The budget's remaining starts, beside the cap, because the two bound different things and
  # either may bind first: the cap is how many sessions this Mac runs at once, the room is how many
  # more this window can afford to start. Empty when `budgetSessions` is off, which is the default,
  # and the loop is then bounded by the cap alone exactly as it was. It is counted here rather than
  # left to the hold above because a hold is a fact from before this pass: every session this loop
  # starts is one the feed has not reported yet, so a guard that only ran between ticks would let a
  # full cap's worth through past the allowance, which is the one gap the count exists to close.
  drn_room=$(budget_room) || { render_failure err "$drn_room"; return 1; }
  drn_started=0
  drn_n=$(printf '%s' "$drn_order" | jq length); drn_i=0
  while [ "$drn_i" -lt "$drn_n" ] && [ "$((drn_total + do_unresolved))" -lt "$drn_cap" ] \
        && { [ -z "$drn_room" ] || [ "$drn_room" -gt 0 ]; }; do
    # The listing again, once this pass has started a session of its own. `dispatch_one` reads it for
    # one thing — the "also in flight" list its slot line carries — and against the listing taken
    # above, a sibling admitted a moment ago in this same loop is not in it. Both halves of an
    # independent pair were therefore told "Nothing else is in flight", each about the other, which is
    # the one sentence part 2 exists to say. It is the defect D-130 names one level further in: there
    # the listing went stale between the top of the tick and the cap, here between one dispatch and
    # the next, and the answer is the same — read it where it is used (D-177).
    #
    # A listing that cannot be re-read stops the pass rather than falling back to the stale one. The
    # fallback would be the cheaper mistake of the two — part 5 carries the standing parallel-run
    # rules whether or not anything is named (CONTRACT clause 1), so a session loses the names and
    # not the discipline — but this is the same listing the cap and `do_unresolved` are counted
    # against, and a tick that cannot see what is running is not a tick that should start more of it.
    # What it costs is a candidate waiting sixty seconds.
    if [ "$drn_started" -gt 0 ]; then
      drn_rows=$(rows_read) || { render_failure err "claude agents --json could not be re-read after a dispatch; nothing more is dispatched this tick"; return 1; }
    fi
    drn_c=$(printf '%s' "$drn_order" | jq -c ".[$drn_i]"); drn_i=$((drn_i + 1))
    drn_p=$(printf '%s' "$drn_c" | jq -r .project)
    drn_m=$(printf '%s' "$drn_c" | jq -r .milestone)
    drn_plan=$(printf '%s' "$2" | jq -c --arg k "$drn_p" '.[$k]')
    drn_before=$(attempt_of "$drn_p" "$drn_m") || { render_failure err "$drn_before"; return 1; }
    dispatch_try "$drn_p" "$drn_m" "$drn_plan" "$drn_rows"
    drn_after=$(attempt_of "$drn_p" "$drn_m") || { render_failure err "$drn_after"; return 1; }
    if [ "$drn_after" -le "$drn_before" ]; then
      # The dispatch produced no session, so it takes no slot — but it may still have reached the
      # CLI, and a `dispatch_failed` at stage `launch` or `service` is a charged start. Re-read the
      # room rather than assuming it did not move: the event has just been written, so the log says
      # which stage it failed at and `budget_room` answers from that. Without it a launch that
      # failed would leave the room untouched and the next candidate would spend a start the window
      # had already been charged for.
      [ -z "$drn_room" ] || { drn_room=$(budget_room) || { render_failure err "$drn_room"; return 1; }; }
      continue
    fi
    drn_total=$((drn_total + 1))
    drn_started=$((drn_started + 1))
    # Charged on the same test the slot is: `attempt_of` moved, so a `dispatch` event was written,
    # which is exactly what `budget_starts` counts on the next tick.
    [ -z "$drn_room" ] || drn_room=$((drn_room - 1))
    # The override follows the dispatch it records, so a dispatch that failed leaves no record of the
    # plan having overruled a `held` into a session that never started.
    if printf '%s' "$drn_c" | jq -e 'has("override")' > /dev/null; then
      plan_override_once "$drn_p" "$drn_m" "$(printf '%s' "$drn_c" | jq -c .override)" \
        || render_failure err "override  $drn_p/$drn_m · the plan_override for this dispatch could not be written"
    fi
  done
}

# tick_run [<broken lock's carries>]: the eight steps, in order, for every registered project. The
# order is REQ-TICK-04 and it is load-bearing: stall, crash and the dispatch hold all test "no
# artifact in the inbox for this session", which is true only after the inbox has been read in the
# same tick.
tick_run() {
  tr_status=0
  tr_now=$(baton_now) || return 3
  notify_flush
  # The stale lock the tick cleared before it took this one. It is a project-scope escalation
  # because REQ-TICK-03 names one, and it is resolved in the same breath because the condition it
  # names is already over: Baton kept working past it, which is what separates a message from a
  # park, and leaving it open would hold every project on something nobody has to do.
  #
  # **Recorded and not delivered** (`record_only`), because that sentence is the definition of the
  # fourth disposition and this class is the one condition that already met it. The event, the line
  # and the resolution are unchanged; what goes is the Mac message, which said "nothing to do; Baton
  # cleared it and carried on" — `escalation_verb`'s own words for this class since M05 — about a
  # park that no longer existed by the time the tick ended. A message that cannot be acted on
  # teaches its reader to dismiss the channel, and this channel carries the parks that can.
  # `record_only` asks `disposition_of` rather than taking this call's word for it, so the class and
  # the delivery cannot drift apart.
  if [ -n "${1:-}" ]; then
    record_only "" "" "" "" baton-unhealthy project "$1" || tr_status=3
    printf '%s' "$1" | jq -r '"unhealthy   " + .detail' || tr_status=3
    park_resolve "" '^baton-unhealthy$' 'the lock was cleared' > /dev/null || tr_status=3
  fi

  if tr_rows=$(rows_read); then
    tr_rows_ok=yes
  else
    tr_rows_ok=no
    render_failure err "baton: claude agents --json could not be read; no lane is reconciled and nothing is dispatched"
  fi

  # 1. Self-check, per registered project, in directory order. A project that fails is skipped for
  #    the rest of the tick; the others carry on.
  #
  #    The generation pass runs *before* each project's self-check and not after it, because a
  #    project that owes a plan is exactly a project the self-check fails: it reads the registration,
  #    finds no plan it can parse, parks the project `plan-unreadable` and skips it for the rest of
  #    the tick, so nothing downstream would ever reach it. The pass adopts a plan that has arrived
  #    and holds — after which the self-check on the next line reads it and `park_resolve` closes the
  #    park in the same tick — and otherwise produces the one candidate that asks for a plan to be
  #    written. The candidate joins `tr_cands`, so the holds, `cap_order` and the cap admit it like
  #    any other and nothing waits on its result (D-164).
  tr_plans='{}'
  tr_cands='[]'
  for tr_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$tr_pj" ] || continue
    tr_key=$(basename "$(dirname "$tr_pj")")
    #    Only on a tick that could see the rows, for the reason the guard below the loop gives: the
    #    pass asks whether the planning lane has a live session, and a listing the service failed to
    #    produce would answer no for every lane alike. A plan waiting one more minute costs nothing.
    if [ "$tr_rows_ok" = yes ]; then
      if tr_planning=$(planning_pass "$tr_key" "$tr_rows"); then
        render_lines "$(printf '%s' "$tr_planning" | jq -c .lines)" action
        tr_cands=$(printf '%s' "$tr_cands" | jq -c \
          --argjson a "$(printf '%s' "$tr_planning" | jq -c .candidates)" '. + $a')
      else
        render_row out action 'generate    %s · the plan generation pass failed this tick\n' "$(render_token out lane "$tr_key")"
        tr_status=3
      fi
    fi
    if tr_plan=$(self_check "$tr_key"); then
      tr_plans=$(printf '%s' "$tr_plans" | jq -c --arg k "$tr_key" --argjson p "$tr_plan" '. + {($k): $p}')
      park_resolve "$tr_key" '^plan-(unreadable|unparseable)$' 'the plan file reads again' || tr_status=3
    else
      render_row out action 'self-check  %s · %s\n' "$(render_token out lane "$tr_key")" "$tr_plan"
    fi
  done

  # Nothing past the self-check happens on a tick that could not read the rows. Every rule from
  # here on reads "no live row" as a fact about a session, and a listing the service failed to
  # produce would make that true of every one of them: the consume would reject a handover a live
  # session is mid-writing and record an asking session as already stopped, the crash rule would
  # sight every lane, and a dispatch would be a dispatch over something already running. A handover
  # waiting one more minute costs nothing; `status` line 9 shows it waiting. The status says the
  # tick did not complete, so the marker is not written and the gap report is what tells the person.
  # This reading stays on `now` where the one after the lanes passes `tr_now` (D-174): it returns
  # before step 2, the only pass that can spend minutes, so the two instants are the same second and
  # `now` is the one that stays honest if anything is ever added above it.
  [ "$tr_rows_ok" = yes ] || { gap_check "$tr_rows"; return 3; }

  # 2. Consume the inbox. Moving the call is all this is: inbox_consume is M02's, it takes the lock
  #    and nothing else, and the lock is already held here.
  #    Its first act is now the reconciliation of a consumption interrupted between its move and
  #    its event (F07, D-146); the pass owns that, so nothing here changes.
  inbox_consume "$tr_rows" "$tr_rows_ok" || {
    render_failure err "inbox       the inbox pass failed; some artifacts may remain unread"
    tr_status=3
  }

  # The rejection parks that name no project, re-read. It runs here and not inside `tick_project`
  # because a park with no project is absent from every per-project pass by construction, which is
  # the whole of why it was the one park with no route out at all (limitation 33). It runs *after*
  # the consume rather than before it because one of the two conditions it reads is a handover of
  # the same session having been acted on, and the consume is what acts on one — so a session that
  # rewrote its artifact correctly has its old rejection park closed in the same tick rather than a
  # minute later, which is the same reason step 3's three unparks run before the rows are read.
  rejection_resolve_check || {
    render_failure err "settle      the rejection parks could not be re-read this tick"
    tr_status=3
  }

  # The dispatch hold, once, before any project's step 4. A usage limit is a fact about the account
  # and not about a lane: the model one project's session was refused on is the model every
  # project's next dispatch would be refused on, so applying it per project would let whichever
  # project ran second spend the request the first had already learned was refused.
  # Guarded like every other step, and for a reason particular to this one: `tick_run` is called as
  # `tick_run … || vt_status=$?`, so `set -e` is suppressed through its whole body and a bare call
  # that failed would be stepped over in silence. A hold pass that failed writes no `hold`, and
  # `hold_bites` reads the log rather than this function, so the next dispatch would land on the
  # very model a limit had just refused.
  holds_apply || {
    render_failure err "holds       the hold pass failed; a dispatch may not be withheld this tick"
    tr_status=3
  }
  # The reserve beside it, for the same reason: the seven-day window is the account's, so it is read
  # once and holds Fable for every project alike.
  reserve_check || {
    render_failure err "holds       the reserve pass failed; a Fable dispatch may not be withheld this tick"
    tr_status=3
  }
  # Budget pacing beside both, for the third time the same reason holds: the five-hour window is
  # the account's, so it is read once and paces every project alike. It is after the reserve rather
  # than before it because it is the wider hold of the two — the reserve withholds Fable, this
  # withholds every model — and the log then reads in the order the pressure arrived.
  #
  # Guarded like the two above it, and for the reason `holds_apply`'s comment gives at length:
  # `tick_run` is called as `tick_run … || vt_status=$?`, so `set -e` is suppressed through its
  # whole body and a bare call that failed would be stepped over in silence. A pacing pass that
  # failed writes no `hold`, and step 7 reads the log rather than this function, so the next
  # dispatch would start a session into a window this pass had just found nearly spent.
  budget_check || {
    render_failure err "holds       the budget pass failed; a dispatch may not be paced this tick"
    tr_status=3
  }

  # 3 to 6, per project; then 7 and 8 once, across all of them.
  #
  # A project whose reconciliation fails is reported and the others carry on, which is what step 1
  # already does for a project whose plan will not read. One lane with an unparseable timestamp must
  # not cost every other project its tick, every minute, until someone reads a log. The loop reads the
  # keys by index rather than through a pipe, so the candidates it collects outlive it.
  tr_keys=$(printf '%s' "$tr_plans" | jq -c 'keys_unsorted')
  tr_n=$(printf '%s' "$tr_keys" | jq length); tr_i=0
  while [ "$tr_i" -lt "$tr_n" ]; do
    tr_key=$(printf '%s' "$tr_keys" | jq -r ".[$tr_i]"); tr_i=$((tr_i + 1))
    tr_plan=$(printf '%s' "$tr_plans" | jq -c --arg k "$tr_key" '.[$k]')
    if ! tick_project "$tr_key" "$tr_plan" "$tr_rows" "$tr_now"; then
      render_row out action 'reconcile   %s · the tick could not finish this project\n' "$(render_token out lane "$tr_key")"
      tr_status=3
      continue
    fi
    # Step 5 skips a project a project-scope park holds: nothing new starts on ground a person has
    # been asked to fix, while the lanes already running carried on through steps 3 and 4 above.
    project_held "$tr_key" > /dev/null && continue
    if tr_doc=$(dispositions_intersect "$tr_key" "$tr_plan" "$tr_rows"); then
      render_lines "$(printf '%s' "$tr_doc" | jq -c .lines)"
      tr_cands=$(printf '%s' "$tr_doc" | jq -c --argjson a "$tr_cands" '$a + .candidates')
    else
      render_row out action 'reconcile   %s · the dispositions could not be read: %s\n' "$(render_token out lane "$tr_key")" "$tr_doc"
      tr_status=3
    fi
  done
  # The legacy sibling worktrees into the managed root, per project, before the dispatch. After the
  # per-project loop because a lane recovered there may have just ended, and before the dispatch
  # because `worktree_ensure` resolves from git's own registration: a worktree moved in this pass is
  # found at its new path by the very next dispatch of that milestone, in this same tick. Ordered
  # before `offline_check` deliberately — that pass stops a finished session's process, and a
  # worktree freed by it is one this pass may move on the next tick, never in the same breath as a
  # stop no listing has yet confirmed.
  #
  # A project whose migration fails stops neither the others nor the dispatch. Nothing downstream
  # reads a worktree's location except through `worktree_of`, which asks git every time, so a
  # worktree that stayed where it was is a worktree that still works.
  #
  # **The listing is re-read here and never carried down from the top of the tick**, for the reason
  # `dispatch_run` already gives about the cap (D-130), and it is worse here than there. The loop
  # above can put a session *into* a legacy worktree: the ladder's redispatch rung reaches
  # `worktree_ensure`, which now resolves the registration and so reuses the sibling where it
  # stands, and its resume rung and a wait retry each wake a session whose row was `pid`-less when
  # `tr_rows` was taken. Against that listing the guard sees nothing there, moves the directory, and
  # strands the session Baton itself had just started — the `working directory no longer exists`
  # ending D-153 is written to prevent. A listing that cannot be re-read refuses the whole pass,
  # because a guard that cannot be answered refuses (D-155).
  if tr_mrows=$(rows_read); then
    tr_n=$(printf '%s' "$tr_keys" | jq length); tr_i=0
    while [ "$tr_i" -lt "$tr_n" ]; do
      tr_key=$(printf '%s' "$tr_keys" | jq -r ".[$tr_i]"); tr_i=$((tr_i + 1))
      worktree_migrate "$tr_key" "$tr_mrows" || tr_status=3
    done
  else
    render_failure err "baton: claude agents --json could not be re-read after the per-project passes; no worktree was migrated this tick"
    tr_status=3
  fi

  # A finished session's process, once across every project: its ranking bounds memory, which is the
  # Mac's, as the cap is. Before the dispatch, so a process taken offline is gone before a new one
  # starts; and the wake session after it, because the first `offline` event is what calls for one.
  offline_check "$tr_rows" || {
    render_row out action 'offline     the offline pass failed; no finished session was taken offline this tick\n'
    tr_status=3
  }
  wake_session_ensure "$tr_rows" || {
    render_row out action 'wake        the wake session could not be checked this tick\n'
    tr_status=3
  }
  dispatch_run "$tr_cands" "$tr_plans" || {
    render_row out action 'dispatch    the dispatch pass failed; nothing more is dispatched this tick\n'
    tr_status=3
  }
  # Each project's budget record, after the dispatch that changes what it says, so the file a
  # person reads is the tick's own answer and not the one from before its work (M14).
  budget_record_all || {
    render_row out action 'budget      the budget records could not be written this tick\n'
    tr_status=3
  }

  # The gap belongs to Baton and not to a project, so it is read once, after every lane. It is
  # measured against `tr_now`, the clock this tick started with, and not against the wall clock
  # here: the passes above can spend minutes — step 2 runs a project's standing check under this
  # lock (D-148) — and a tick that measured from the end of its own work would report the length of
  # that work as a stretch during which Baton was not running.
  gap_check "$tr_rows" "$tr_now" || tr_status=3
  # Other projects may have progressed, but a skipped step cannot certify a completed tick.
  # Keep the last honest marker so the gap continues to be measured against it (D-115).
  return "$tr_status"
}

# verb_tick [<broken lock's carries>]: the tick under the lock, then the marker outside it. The
# marker is written after the lock is released and never before the work, so it means "a tick
# completed"; a tick that dies halfway leaves the previous value and the next tick's gap report is
# true (INV-11).
#
# A tick that could not read the rows or finish a pass returns 3 and gets no marker either.
# Saying it completed would advance the clock the gap is measured against (D-049, D-115).
verb_tick() {
  vt_status=0
  tick_run "${1:-}" || vt_status=$?
  lock_release
  trap - EXIT
  [ "$vt_status" -ne 0 ] || marker_write
  return "$vt_status"
}
