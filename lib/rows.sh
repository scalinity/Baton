#!/bin/sh
# lib/rows.sh — step 3 of the tick: the rows reconciled against the log's in-flight lanes. A crash,
# a stall, a long-running session, a live question, a takeover and the gap, each detected from a
# derivation over the five inputs and each recorded once. Nothing here resumes, redispatches or
# types into a session: M03 detects and records, M04 acts on the ladder and M05 on the parks.
#
# Every check is idempotent, because the tick is run twice against the same fixture and the second
# run must change nothing (INV-05). What makes each one idempotent is named at the check.
set -eu

# rows_read: `claude agents --json`, once per tick. Unlike rows_json this distinguishes a listing
# that could not be read from one that is empty, and the difference decides a night: with no
# listing every in-flight lane reads as a lane with no row, which is the crash rule's whole input,
# so a background service that is merely down would otherwise confirm a crash on every lane two
# ticks later. Prints the array either way; returns 1 when the listing could not be read.
rows_read() {
  if ! rr_out=$("$BATON_CLAUDE" agents --json 2>/dev/null); then
    echo '[]'
    return 1
  fi
  [ -n "$rr_out" ] || { echo '[]'; return 1; }
  printf '%s' "$rr_out" | jq -ce 'if type == "array" then . else empty end' 2>/dev/null && return 0
  echo '[]'
  return 1
}

# inbox_holds <session>: whether a handover for this session is waiting in the inbox. Stall, crash
# and the question check all test this, and it is true only after step 2 has read the inbox in the
# same tick (REQ-TICK-04) — an artifact that landed a second ago is neither a stall nor a crash.
inbox_holds() {
  for ih_f in "$BATON_HOME"/inbox/*-"$1".json "$BATON_HOME"/inbox/*-"$1".json.tmp; do
    [ -f "$ih_f" ] && return 0
  done
  return 1
}

# ended_on_disk <session> [delivered execution json]: whether the session's handover has already been moved out of the inbox,
# whatever the log says. The move is the consumption (INV-06) and the event comes after it, so a
# tick killed between the two leaves a file in archive/ or rejected/ with nothing in the log — which
# derivation 1 reads as a lane still open and the crash rule would read as a crash on a session that
# had in fact finished. derive_consumed's `unrecorded` names such a file; this is the same fact
# asked of one session. The optional bound holds at and archives consumed before that execution.
# Equal timestamps need that log-order proof: all events in one tick share a clock reading, and
# an unrecorded archive at that time must still protect the move-before-log window (INV-06).
# Rejections remain unbounded: they parked the lane, irrespective of a later execution.
ended_on_disk() {
  for eo_f in "$BATON_HOME"/rejected/*-"$1".json "$BATON_HOME"/rejected/*-"$1".json.tmp; do
    [ -f "$eo_f" ] && return 0
  done
  eo_bound=${2:-'{}'}
  eo_at=$(printf '%s' "$eo_bound" | jq -r '.at // ""')
  eo_epoch=''
  if [ -n "$eo_at" ]; then eo_epoch=$(iso_epoch "$eo_at") || return 0; fi
  for eo_f in "$BATON_HOME"/archive/*-"$1"-*.json; do
    [ -f "$eo_f" ] || continue
    [ -n "$eo_epoch" ] || return 0
    eo_stamp=${eo_f##*/}; eo_stamp=${eo_stamp#*-"$1"-}; eo_stamp=${eo_stamp%.json}
    eo_when=$(iso_epoch "$eo_stamp") || return 0
    [ "$eo_when" -lt "$eo_epoch" ] && continue
    if [ "$eo_when" -eq "$eo_epoch" ] && printf '%s' "$eo_bound" | jq -e --arg p "$eo_f" \
         '(.archives // []) | index($p) != null' > /dev/null; then continue; fi
    return 0
  done
  return 1
}

# stood_off <session> <list>: whether the lane is one Baton has stopped acting on this tick — a
# takeover, or a transcript it could not scan. INV-04: a session nobody typed into is never
# prompted over, and a lane whose transcript could not be read must not be treated as clean.
stood_off() {
  printf '%s\n' "$2" | grep -Fqx "$1"
}

# newest_event_at <project> <milestone> <attempt> <kinds regex>: the `at` of the newest event of
# those kinds for the attempt, or empty. The attempt's clock, read from the log and stored nowhere.
newest_event_at() {
  ne_log=$(log_json) || { echo "$ne_log"; return 1; }
  printf '%s' "$ne_log" | jq -r --arg p "$1" --arg m "$2" --argjson a "$3" --arg k "$4" '
    [ .[] | select(.project == $p and .milestone == $m and .attempt == $a
                   and (.kind | test($k))) ] | last | .at // empty'
}

# transcript_mtime <session>: the newest modification time across the session's transcript and its
# subagents' transcripts, in epoch seconds; empty when there is no transcript. A stat, never a read
# (REQ-STOP-01). The subagents must be counted or every close-out reads as a stall: the parent sits
# on one Agent call for twenty minutes while its own file does not move (D-008).
transcript_mtime() {
  tm_file=$(transcript_of "$1") || return 1
  tm_newest=$(stat -f %m "$tm_file")
  for tm_sub in "$(dirname "$tm_file")/$1"/subagents/agent-*.jsonl; do
    [ -f "$tm_sub" ] || continue
    tm_at=$(stat -f %m "$tm_sub")
    [ "$tm_at" -le "$tm_newest" ] || tm_newest=$tm_at
  done
  printf '%s\n' "$tm_newest"
}

# takeover_check <project> <rows json>: derivation 3 applied. One `takeover` event per session and
# one Mac message, then Baton stops acting on the lane — no resume, redispatch, ruling or ladder
# step (REQ-STOP-14, INV-04). A lane whose only transcript is an .orphaned- sibling, and one whose
# transcript will not parse, are escalated with the path rather than scanned, and stood off too:
# neither is evidence that nobody is typing.
#
# Idempotent because the `takeover` event is the key: a session that already has one is past.
#
# The result is one JSON object — {stand_off, lines} — because the check has two: the sessions the
# rest of the tick must leave alone, and the record a person reads. That is the same convention
# every derivation naming two halves of one read follows (D-031).
takeover_check() {
  tc_over=$(derive_taken_over "$1" "$2") || { render_failure err "$tc_over"; return 1; }
  tc_log=$(log_json) || { render_failure err "$tc_log"; return 1; }
  tc_parked=$(derive_parked "$1") || { render_failure err "$tc_parked"; return 1; }
  tc_off='[]'; tc_lines='[]'

  tc_n=$(printf '%s' "$tc_over" | jq '.taken_over | length'); tc_i=0
  while [ "$tc_i" -lt "$tc_n" ]; do
    tc_l=$(printf '%s' "$tc_over" | jq -c ".taken_over[$tc_i]"); tc_i=$((tc_i + 1))
    tc_session=$(printf '%s' "$tc_l" | jq -r .session)
    tc_milestone=$(printf '%s' "$tc_l" | jq -r .milestone)
    tc_attempt=$(printf '%s' "$tc_l" | jq -r '.attempt // ""')
    tc_off=$(printf '%s' "$tc_off" | jq -c --arg s "$tc_session" '. + [$s]')
    if printf '%s' "$tc_log" | jq -e --arg s "$tc_session" \
         'any(.[]; .kind == "takeover" and .session == $s)' > /dev/null; then
      continue
    fi
    log_event takeover "$1" "$tc_milestone" "$tc_session" "$tc_attempt" \
      "$(printf '%s' "$tc_l" | jq -c '{first_unmatched_at, first_unmatched_uuid, typed_count}
                                      | with_entries(select(.value != null))')"
    tc_fields=$(printf '%s' "$tc_l" | jq -c --arg m "$tc_milestone" '{detail:
      "a typed message Baton did not send at \(.first_unmatched_at // "an unknown time"); Baton has stood off this lane · baton answer \($m) \"continue\" hands it back"}')
    notification_write "$1" "$tc_milestone" "$tc_session" "$tc_attempt" takeover-silent "$tc_session" \
      "$tc_fields"
    tc_lines=$(printf '%s' "$tc_lines" | jq -c --arg l "takeover  $1/$tc_milestone · $tc_session · Baton has stood off" '. + [$l]')
  done

  # The two lanes that cannot be judged. Each is the lane's own "something else", which is what the
  # `other` class is for, and each is raised once: an open escalation naming the same rule is the key.
  for tc_kind in orphaned unreadable; do
    case "$tc_kind" in
      orphaned) tc_rule=transcript-orphaned
        tc_why="the transcript is an .orphaned- sibling, so the lane was not scanned and cannot be read as clean" ;;
      *) tc_rule=transcript-unreadable
        tc_why="the transcript will not parse, so the lane was not scanned and cannot be read as clean" ;;
    esac
    tc_n=$(printf '%s' "$tc_over" | jq --arg k "$tc_kind" '.[$k] | length'); tc_i=0
    while [ "$tc_i" -lt "$tc_n" ]; do
      tc_l=$(printf '%s' "$tc_over" | jq -c --arg k "$tc_kind" --argjson i "$tc_i" '.[$k][$i]')
      tc_i=$((tc_i + 1))
      tc_session=$(printf '%s' "$tc_l" | jq -r .session)
      tc_milestone=$(printf '%s' "$tc_l" | jq -r .milestone)
      tc_attempt=$(printf '%s' "$tc_l" | jq -r '.attempt // ""')
      tc_path=$(printf '%s' "$tc_l" | jq -r .path)
      tc_off=$(printf '%s' "$tc_off" | jq -c --arg s "$tc_session" '. + [$s]')
      # Keyed on the session as well as the milestone and the rule: a second attempt at the same
      # milestone is a new session with a new transcript, and its own unscannable transcript is news
      # rather than the first attempt's still-open park repeating itself.
      if printf '%s' "$tc_parked" | jq -e --arg m "$tc_milestone" --arg r "$tc_rule" --arg s "$tc_session" \
           'any(.parked[]; .milestone == $m and .session == $s and .class == "other"
                           and .carries.rule == $r)' > /dev/null; then
        continue
      fi
      tc_carries=$(jq -nc --arg r "$tc_rule" --arg p "$tc_path" --arg d "$tc_why ($tc_path)" \
        '{rule: $r, path: $p, detail: $d}')
      escalate "$1" "$tc_milestone" "$tc_session" "$tc_attempt" other lane "$tc_carries"
      tc_lines=$(printf '%s' "$tc_lines" | jq -c --arg l "unscannable  $1/$tc_milestone · $tc_rule · $tc_path" '. + [$l]')
    done
  done
  jq -nc --argjson o "$tc_off" --argjson l "$tc_lines" '{stand_off: $o, lines: $l}'
}

# crash_check <project> <rows json> <stand-off list> <this tick's clock>: REQ-STOP-10. A logged
# in-flight lane whose row is absent or carries pid null — the tell, while `state` may still read
# `working` — with no artifact in the inbox and no ending on record, on two consecutive ticks. The
# first sighting is `crash_sighting` 1; the second confirms, and M04 stops and resumes on it.
#
# Three guards, each for a failure that has been measured:
#  - a sleep leaves the row byte-identical, so it is never a crash (D-008); the two-tick rule is
#    against a momentary read, such as the supervisor restart that gives a session a new pid.
#  - a lane with an ending since its newest delivered execution is already routed —
#    an asking artifact Baton itself stopped the session for, a declared stop, an api-error wait.
#    derivation 1's `no_row` holds all of those, and calling one a crash would act on it twice.
#  - a sighting this tick wrote is not the previous tick's. The two runs of a scenario share one
#    frozen clock, so "an event bearing this tick's own reading" is exactly the second run's view
#    of the first run's event, which is what INV-05 requires it to ignore. Two real ticks are sixty
#    seconds apart and never share a reading.
crash_check() {
  cc_flight=$(derive_in_flight "$1" "$2") || { render_failure err "$cc_flight"; return 1; }
  cc_log=$(log_json) || { render_failure err "$cc_log"; return 1; }
  cc_window=$(( 2 * BATON_TICK_SECONDS ))
  cc_now=$(iso_epoch "$4") || { render_failure err "$cc_now"; return 1; }

  cc_n=$(printf '%s' "$cc_flight" | jq '.no_row | length'); cc_i=0
  while [ "$cc_i" -lt "$cc_n" ]; do
    cc_l=$(printf '%s' "$cc_flight" | jq -c ".no_row[$cc_i]"); cc_i=$((cc_i + 1))
    cc_session=$(printf '%s' "$cc_l" | jq -r .session)
    cc_milestone=$(printf '%s' "$cc_l" | jq -r .milestone)
    cc_attempt=$(printf '%s' "$cc_l" | jq -r '.attempt // ""')
    stood_off "$cc_session" "$3" && continue
    inbox_holds "$cc_session" && continue
    [ -n "$cc_attempt" ] || continue
    # An ending on record, by either half of what an ending is. A `consumed` says the artifact was
    # acted on; a `rejected` says it was refused, which parked the lane already — sighting either
    # as a crash would act on one ending twice, and M04's resume would land on a parked lane.
    cc_execution=$(printf '%s' "$cc_log" | jq -c --arg p "$1" --arg m "$cc_milestone" --argjson a "$cc_attempt" \
         --arg s "$cc_session" '
         . as $log
         | [to_entries[] | {i: .key} + .value
            | select(.project == $p and .milestone == $m and .attempt == $a)] as $ev
         | ([$ev[] | select(.kind == "dispatch" or
              (.kind == "resume" and (.outcome == "delivered" or .outcome == "forked")))] | last) as $execution
         | {at: $execution.at,
            archives: [$ev[] | select(.kind == "consumed" and .i < ($execution.i // -1))
                        | .archive | select(. != null)],
            ended: (any($ev[]; .kind == "consumed" and .i > ($execution.i // -1))
                    or any($log[]; .kind == "rejected" and .session == $s))}')
    ended_on_disk "$cc_session" "$cc_execution" && continue
    [ "$(printf '%s' "$cc_execution" | jq -r .ended)" = false ] || continue

    # The sightings that count: this attempt's, since its newest dispatch or resume. A sighting
    # bearing this tick's own reading of the clock is one this tick wrote, so there is nothing left
    # to do for the lane; the rest are earlier ticks', and only one no older than two intervals is
    # half of a consecutive pair.
    cc_sight=$(printf '%s' "$cc_log" | jq -c --arg p "$1" --arg m "$cc_milestone" \
      --argjson a "$cc_attempt" --arg now "$4" '
      [ to_entries[] | {i: .key} + .value
        | select(.project == $p and .milestone == $m and .attempt == $a) ] as $ev
      | ([ $ev[] | select(.kind == "dispatch" or .kind == "resume") ] | last) as $reset
      | [ $ev[] | select(.kind == "crash_sighting" and .i > ($reset.i // -1)) ] as $sightings
      | { mine: ([ $sightings[] | select(.at == $now) ] | length),
          reset_at: $reset.at,
          previous: ([ $sightings[] | select(.at != $now) ] | last) }')
    [ "$(printf '%s' "$cc_sight" | jq -r .mine)" = 0 ] || continue
    # A lane Baton dispatched or resumed within the last two intervals is starting up, not crashed.
    # The row takes a beat to carry a pid again — `state: failed` was measured arriving up to
    # seventy seconds after a process died, and a resumed session is the same transition in reverse
    # — so sighting one here would confirm a crash on the session the previous tick just brought
    # back, and the ladder would climb on its own remedy. Two intervals is the same window a first
    # sighting expires in, for the same reason: it is how long a fact about a row takes to settle.
    cc_reset=$(printf '%s' "$cc_sight" | jq -r '.reset_at // ""')
    if [ -n "$cc_reset" ]; then
      cc_reset=$(iso_epoch "$cc_reset") || { render_failure err "$cc_reset"; return 1; }
      [ $((cc_now - cc_reset)) -ge "$cc_window" ] || continue
    fi
    cc_sight=$(printf '%s' "$cc_sight" | jq -c '.previous // {}')
    cc_prev=$(printf '%s' "$cc_sight" | jq -r '.sighting // ""')
    # Only a first sighting expires. A confirmation stands until the attempt's next dispatch or
    # resume clears it, which is what M04 writes when it acts on one: expiring it too would restart
    # the pair every two intervals, so a crash nothing had acted on yet would write a sighting pair
    # every four minutes and derive_ladder, which counts every second sighting since the reset as a
    # failure ending, would read "escalate" off a single crash.
    if [ -n "$cc_prev" ] && [ "$cc_prev" != 2 ]; then
      cc_at=$(iso_epoch "$(printf '%s' "$cc_sight" | jq -r .at)") || { render_failure err "$cc_at"; return 1; }
      [ $((cc_now - cc_at)) -le "$cc_window" ] || cc_prev=''
    fi
    [ "$cc_prev" != 2 ] || continue

    cc_row=$(printf '%s' "$cc_l" | jq -c '.row // {}')
    if [ "$cc_prev" = 1 ]; then cc_next=2; else cc_next=1; fi
    # `pid: null` is the tell and is written as null deliberately — it is the observation. `state`
    # follows the envelope's rule instead: a lane whose row is gone altogether has no state to
    # report, so the field is absent rather than null.
    log_event crash_sighting "$1" "$cc_milestone" "$cc_session" "$cc_attempt" \
      "$(printf '%s' "$cc_row" | jq -c --argjson n "$cc_next" \
           '{pid: null, state: .state, sighting: $n} | with_entries(select(.key == "pid" or .value != null))')"
    if [ "$cc_next" = 2 ]; then
      render_row out action 'crash     %s/%s · %s · confirmed on the second sighting\n' "$(render_token out lane "$1")" "$(render_token out milestone "$cc_milestone")" "$(render_token out session "$cc_session")"
    else
      render_row out action 'crash?    %s/%s · %s · first sighting, no row and no ending\n' "$(render_token out lane "$1")" "$(render_token out milestone "$cc_milestone")" "$(render_token out session "$cc_session")"
    fi
  done
}

# stall_check <project> <rows json> <stand-off list>: REQ-STOP-08. A live, non-waiting lane with no
# artifact whose transcripts — its own and its subagents' — have not moved for stallMinutes.
# Notify once with the row's state and the verb; the session is untouched, and the notification is
# resolved by the session's own artifact; a delivered or forked resume also re-arms the key
# (derivation 11).
#
# A Remote: yes lane is judged waiting or not, because its row is not a park detector (REQ-ESC-08):
# the prototype's remote session read `blocked/waiting` on one question and `working/idle` on the
# next, and `question_check` parks neither. A prompt nobody answers from the phone is then this
# check's to surface, whichever the row reads, or it would surface nowhere.
stall_check() {
  sc_flight=$(derive_in_flight "$1" "$2") || { render_failure err "$sc_flight"; return 1; }
  sc_limit=$(( $(config_num stallMinutes 30) * 60 ))
  sc_now=$(now_epoch)
  sc_n=$(printf '%s' "$sc_flight" | jq '.in_flight | length'); sc_i=0
  while [ "$sc_i" -lt "$sc_n" ]; do
    sc_l=$(printf '%s' "$sc_flight" | jq -c ".in_flight[$sc_i]"); sc_i=$((sc_i + 1))
    sc_session=$(printf '%s' "$sc_l" | jq -r .session)
    sc_milestone=$(printf '%s' "$sc_l" | jq -r .milestone)
    sc_attempt=$(printf '%s' "$sc_l" | jq -r '.attempt // ""')
    stood_off "$sc_session" "$3" && continue
    inbox_holds "$sc_session" && continue
    # A lane with no attempt is skipped rather than notified, as the crash and long-running checks
    # skip one: derive_key_spent takes the attempt as a JSON number, and passing it nothing fails
    # the derivation, which under set -eu would take the whole tick down — and with it the marker —
    # over one malformed line in the log. Baton's own dispatch always stamps an attempt, so this is
    # the guard against a hand-written event and not against anything Baton writes.
    [ -n "$sc_attempt" ] || continue
    printf '%s' "$sc_l" | jq -e '(.remote // false) == true or (.row.status // "") != "waiting"' > /dev/null || continue
    sc_mtime=$(transcript_mtime "$sc_session") || continue
    sc_age=$((sc_now - sc_mtime))
    [ "$sc_age" -ge "$sc_limit" ] || continue
    # Age the host was asleep through is not inactivity. A Mac that slept the night leaves every
    # transcript in the fleet older than the threshold, and a session woken beside Baton has not
    # stopped working — it has not been running. So the proven sleep inside the very window being
    # measured comes off the age, and what is left is the awake inactivity the threshold was written
    # about (D-008's thirty minutes of *unchanged transcripts*, which presumes a machine that was
    # there to change them).
    #
    # It is asked last of the three tests and not first: the raw age has to be past the threshold
    # and the key has to be unspent. An ordinary tick therefore costs no read at all, and a lane
    # already notified about costs none however many ticks it stays stalled. **The case that does
    # cost one every tick is a lane held silent by this subtraction** — its raw age stays past the
    # threshold and its key stays unspent, so each tick re-reads until the transcript moves or the
    # awake share crosses the line. On the real Mac that is a `pmset -g log` a minute, for at most
    # `stallMinutes` after a wake, per idle lane; measured at about a second. Priced and accepted
    # rather than cached across ticks, because a cache that outlived the lock would be Baton state
    # with a staleness rule of its own, and the whole of this file's cost is one second of a sixty.
    # The subtraction is bounded by what the host proved: `host_sleep_proven` prints nothing
    # when the history is unreadable, ambiguous or does not reach back to the transcript, and the
    # age then stands exactly as it did before this existed — the conservative direction, because a
    # stall is a notification Baton keeps working past and an unnotified one is the thing nobody
    # hears about.
    #
    # The age itself is not rewritten: `transcript_age_seconds` stays the wall age, because that is
    # the observation, and the awake share is a second field beside it. A line saying "no transcript
    # change for 31 m" about a transcript last touched ten hours ago would trade one wrong number
    # for another.
    sc_spent=$(derive_key_spent "$1" "$sc_milestone" "$sc_attempt" stall) || { render_failure err "$sc_spent"; return 1; }
    if [ "$(printf '%s' "$sc_spent" | jq -r .spent)" != false ]; then
      # A remote lane's stall key is spent only while the transcript has not moved since the
      # notification. For it the stall is the only way an unanswered phone prompt surfaces, and a
      # prompt answered from the phone moves the transcript without an artifact or successful resume
      # to re-arm the key — so the next unanswered prompt of the attempt would pass
      # in silence. The second run of a tick sees its own notification at or after the mtime.
      printf '%s' "$sc_l" | jq -e '(.remote // false) == true' > /dev/null || continue
      sc_spent_at=$(iso_epoch "$(printf '%s' "$sc_spent" | jq -r .at)") || { render_failure err "$sc_spent_at"; return 1; }
      [ "$sc_mtime" -gt "$sc_spent_at" ] || continue
    fi
    sc_slept=$(host_sleep_proven "$sc_mtime" "$sc_now" "$BATON_TICK_SECONDS")
    sc_awake=''
    if [ -n "$sc_slept" ] && [ "$sc_slept" -gt 0 ]; then
      sc_awake=$((sc_age - sc_slept))
      [ "$sc_awake" -ge 0 ] || sc_awake=0
      [ "$sc_awake" -ge "$sc_limit" ] || continue
    fi
    sc_state=$(printf '%s' "$sc_l" | jq -r '.row.state // "unknown"')
    # Composed here and not inside the call: a message built inside a nested command substitution
    # is parsed by /bin/sh — bash 3.2 on this Mac — with the quoting state mistracked, so an
    # apostrophe in the text silently ends the quoted jq program and the event loses its fields.
    sc_detail="no transcript change for $(duration "$sc_age")"
    [ -z "$sc_awake" ] || sc_detail="$sc_detail, of which $(duration "$sc_awake") with the host awake"
    sc_detail="$sc_detail; the row reads $sc_state"
    sc_fields=$(jq -nc --arg s "$sc_state" --argjson age "$sc_age" --arg m "$sc_milestone" \
      --arg d "$sc_detail" --arg aw "$sc_awake" '
      {state: $s, transcript_age_seconds: $age}
      | if $aw != "" then . + {awake_age_seconds: ($aw | tonumber)} else . end
      | . + {detail: ($d + (if $s == "done" then " · baton answer \($m) to finish the close-out"
                      else " · read it in Claude.app before touching it" end))}')
    notification_write "$1" "$sc_milestone" "$sc_session" "$sc_attempt" stall "" "$sc_fields"
    render_row out action 'stall     %s/%s · %s · %s unchanged, state %s\n' "$(render_token out lane "$1")" "$(render_token out milestone "$sc_milestone")" "$(render_token out session "$sc_session")" "$(duration "$sc_age")" "$sc_state"
  done
}

# long_running_check <project> <rows json>: REQ-STOP-09. longRunningHours since the attempt's
# latest dispatch, delivered/forked resume or takeover; notify once, session untouched. A taken-over
# lane is still counted — the takeover restarts the clock and resets the key (derivation 11), so an abandoned
# lane notifies once and is not silently forgotten.
long_running_check() {
  lr_flight=$(derive_in_flight "$1" "$2") || { render_failure err "$lr_flight"; return 1; }
  lr_log=$(log_json) || { render_failure err "$lr_log"; return 1; }
  lr_limit=$(( $(config_num longRunningHours 6) * 3600 ))
  lr_now=$(now_epoch)
  lr_n=$(printf '%s' "$lr_flight" | jq '.in_flight | length'); lr_i=0
  while [ "$lr_i" -lt "$lr_n" ]; do
    lr_l=$(printf '%s' "$lr_flight" | jq -c ".in_flight[$lr_i]"); lr_i=$((lr_i + 1))
    lr_session=$(printf '%s' "$lr_l" | jq -r .session)
    lr_milestone=$(printf '%s' "$lr_l" | jq -r .milestone)
    lr_attempt=$(printf '%s' "$lr_l" | jq -r '.attempt // ""')
    [ -n "$lr_attempt" ] || continue
    lr_since=$(printf '%s' "$lr_log" | jq -r --arg p "$1" --arg m "$lr_milestone" --argjson a "$lr_attempt" '
      [ .[] | select(.project == $p and .milestone == $m and .attempt == $a)
        | select(.kind == "dispatch" or .kind == "takeover"
                 or (.kind == "resume" and (.outcome == "delivered" or .outcome == "forked"))) ]
      | last | .at // empty') \
      || { render_failure err "$lr_since"; return 1; }
    [ -n "$lr_since" ] || continue
    lr_at=$(iso_epoch "$lr_since") || { render_failure err "$lr_at"; return 1; }
    lr_age=$((lr_now - lr_at))
    [ "$lr_age" -ge "$lr_limit" ] || continue
    lr_spent=$(derive_key_spent "$1" "$lr_milestone" "$lr_attempt" long-running) || { render_failure err "$lr_spent"; return 1; }
    [ "$(printf '%s' "$lr_spent" | jq -r .spent)" = false ] || continue
    lr_detail="running $(duration "$lr_age") since $lr_since, the latest dispatch, successful resume or takeover of this attempt"
    lr_fields=$(jq -nc --argjson age "$lr_age" --arg since "$lr_since" --arg d "$lr_detail" \
      '{elapsed_seconds: $age, since: $since, detail: $d}')
    notification_write "$1" "$lr_milestone" "$lr_session" "$lr_attempt" long-running "" "$lr_fields"
    render_row out action 'long      %s/%s · %s · %s\n' "$(render_token out lane "$1")" "$(render_token out milestone "$lr_milestone")" "$(render_token out session "$lr_session")" "$(duration "$lr_age")"
  done
}

# question_check <project> <rows json> <stand-off list>: REQ-STOP-11's live half. A row reading
# waitingFor "input needed" with no artifact escalates at once, lane scope; the process is never
# touched and never times out. The row is not a park detector for a Remote: yes lane (REQ-ESC-08):
# there the park is artifact-borne and an unanswered phone prompt surfaces as a stall.
#
# Idempotent because an open escalation of the class for the lane is the key; the lane unparks when
# the question is answered in place, which is M05's resolution.
question_check() {
  qc_flight=$(derive_in_flight "$1" "$2") || { render_failure err "$qc_flight"; return 1; }
  qc_parked=$(derive_parked "$1") || { render_failure err "$qc_parked"; return 1; }
  qc_n=$(printf '%s' "$qc_flight" | jq '.in_flight | length'); qc_i=0
  while [ "$qc_i" -lt "$qc_n" ]; do
    qc_l=$(printf '%s' "$qc_flight" | jq -c ".in_flight[$qc_i]"); qc_i=$((qc_i + 1))
    qc_session=$(printf '%s' "$qc_l" | jq -r .session)
    qc_milestone=$(printf '%s' "$qc_l" | jq -r .milestone)
    qc_attempt=$(printf '%s' "$qc_l" | jq -r '.attempt // ""')
    stood_off "$qc_session" "$3" && continue
    inbox_holds "$qc_session" && continue
    printf '%s' "$qc_l" | jq -e '(.remote // false) != true' > /dev/null || continue
    printf '%s' "$qc_l" | jq -e '(.row.waitingFor // "") == "input needed"' > /dev/null || continue
    # Keyed on the session, not the milestone alone: an unresolved park from an earlier attempt
    # would otherwise silence the new attempt's question, and a lane waiting for input that nobody
    # hears about is the one thing the class exists to prevent.
    #
    # Any open lane park stops it, not a `question` one alone. A row keeps its last state for up to
    # seventy seconds after the session is stopped, so a session that asked in place and then wrote
    # an `asking` artifact is consumed, stopped and parked in step 2 while its row still reads
    # `input needed` in step 3 — and a second park on one lane is what `baton answer` then refuses
    # to act on, because two escalations carry the lane's name. One lane, one thing to answer.
    if printf '%s' "$qc_parked" | jq -e --arg m "$qc_milestone" --arg s "$qc_session" \
         'any(.parked[]; .milestone == $m and .session == $s and .scope == "lane")' > /dev/null; then
      continue
    fi
    # Nor a row read within two intervals of a dispatch or resume. A ruling resumes the session and
    # resolves its park, and the row can still read the `input needed` of the question the ruling
    # answered; parking on that would send the person a message about a question already decided and
    # have `baton answer` deliver the same ruling twice. Two intervals is the window the crash rule
    # gives a row to settle after the same two events (D-054): a real question is still open after it.
    if [ -n "$qc_attempt" ]; then
      qc_last=$(newest_event_at "$1" "$qc_milestone" "$qc_attempt" '^(dispatch|resume)$') \
        || { render_failure err "$qc_last"; return 1; }
      if [ -n "$qc_last" ]; then
        qc_last=$(iso_epoch "$qc_last") || { render_failure err "$qc_last"; return 1; }
        [ $(( $(now_epoch) - qc_last )) -ge $(( 2 * BATON_TICK_SECONDS )) ] || continue
      fi
    fi
    qc_job=$(printf '%s' "$qc_l" | jq -r '.row.id // ""')
    qc_name=$(printf '%s' "$qc_l" | jq -r '.row.name // ""')
    # What is happening, and nothing about what to do: the message's verb says where to answer and
    # `status` prints the same verb, so a detail repeating it says it twice.
    qc_detail="$qc_name is waiting for input, and no payload carries the question, so it can only be read in the session"
    qc_carries=$(jq -nc --arg n "$qc_name" --arg j "$qc_job" --arg d "$qc_detail" \
      '{row: $n, job: $j, waiting_for: "input needed", detail: $d}')
    escalate "$1" "$qc_milestone" "$qc_session" "$qc_attempt" question lane "$qc_carries"
    render_row out action 'question  %s/%s · %s · waiting for input\n' "$(render_token out lane "$1")" "$(render_token out milestone "$qc_milestone")" "$(render_token out session "$qc_session")"
  done
}

# gap_check <rows json> [<as-of>]: REQ-ESC-10, derivation 15. The as-of minus the marker, the as-of
# defaulting to now, reported only when a lane was in flight, waiting or parked during it, and keyed
# on the marker value so one outage reports once. The gap belongs to no milestone, so the event
# carries no lane and the key alone is the guard; the marker this tick is about to write changes the
# key, which is why the second run of a scenario reports nothing.
#
# The tick passes the clock it started with, because its own step 2 can run for minutes and a tick
# is not an outage while it is working; every other caller reads the gap from outside a tick, where
# now is the honest instant.
#
# **Detection and attribution are two steps and stay two steps.** Everything above this line is
# unchanged: the threshold, the open-lane test and the marker key decide *that* there was a gap, and
# nothing about the host is asked until they have. Only then does `lib/host.sh` read the sleep
# history — once, after the key test, so a gap already reported costs no read and a tick with no gap
# costs none either — and `disposition_of` turns its answer into the one thing that differs:
# `record_notification` for a gap the host accounts for, `notification_write` for every other, which
# is both halves of "unexplained still notifies, unknown still notifies, and neither is silently
# suppressed". The event is written in both cases and carries the evidence either way.
gap_check() {
  gc_gap=$(derive_gap "$1" "${2:-}") || { render_failure err "$gc_gap"; return 1; }
  [ "$(printf '%s' "$gc_gap" | jq -r .report)" = true ] || return 0
  gc_marker=$(printf '%s' "$gc_gap" | jq -r .marker)
  gc_log=$(log_json) || { render_failure err "$gc_log"; return 1; }
  # The key is spent by a recorded gap as much as by a delivered one: `record_notification` writes
  # the same `notification` event with the same class and key, so the second reading of one marker
  # writes nothing and raises nothing whichever channel the first went out on.
  if printf '%s' "$gc_log" | jq -e --arg k "$gc_marker" \
       'any(.[]; .kind == "notification" and .class == "gap" and .key == $k)' > /dev/null; then
    return 0
  fi
  gc_seconds=$(printf '%s' "$gc_gap" | jq -r .gap_seconds)
  # The window the gap measured, and never the instant this runs: `host_gap_evidence` derives the
  # endpoint from the marker and the duration, because an event written minutes after the gap ended
  # would otherwise ask the host to account for minutes the gap never covered.
  gc_host=$(host_gap_evidence "$gc_marker" "$gc_seconds") || { render_failure err "$gc_host"; return 1; }
  # Emptiness is checked as well as the status, because the two failures downstream of it are the
  # ones this whole change must not have: an empty evidence object makes `--argjson h` fail, which
  # leaves `gc_fields` empty, which `fields_or_fail` refuses — and the gap then has no event *and*
  # no message. `host_window` always prints an object, so this is the awk itself having broken;
  # failing the tick here costs a marker and reports the gap again next minute, which is the
  # direction to err in.
  [ -n "$gc_host" ] || { render_failure err "gap_check: the host evidence came back empty; the gap is not reported this tick"; return 1; }
  gc_base="no tick for $(duration "$gc_seconds"); the last one completed at $gc_marker, and a lane was open through it"
  gc_detail=$(host_gap_detail "$gc_base" "$gc_host")
  gc_fields=$(jq -nc --argjson s "$gc_seconds" --arg m "$gc_marker" --arg d "$gc_detail" \
    --argjson h "$gc_host" '{gap_seconds: $s, marker: $m, detail: $d, host: $h}')
  gc_disp=$(disposition_of notification gap "$gc_fields") || { render_failure err "gap_check: the gap has no disposition"; return 1; }
  # Recorded as the table's answer, after it was asked. It is written for a person reading the log
  # and for `status`, and it is never read back as input: `disposition_of` reads `host.assessed` and
  # nothing else, so a field on the event cannot talk the table into a different answer.
  gc_fields=$(printf '%s' "$gc_fields" | jq -c --arg d "$gc_disp" '. + {disposition: $d}')
  gc_notifies=0; disposition_notifies "$gc_disp" || gc_notifies=$?
  if [ "$gc_notifies" -eq 1 ]; then
    record_notification "" "" "" "" gap "$gc_marker" "$gc_fields" || return 1
    render_row out record 'gap       Baton was not running for %s, measured against %s · the host accounts for it · recorded, not sent\n' "$(duration "$gc_seconds")" "$(render_token out timestamp "$gc_marker")"
  else
    notification_write "" "" "" "" gap "$gc_marker" "$gc_fields"
    render_row out action 'gap       Baton was not running for %s, measured against %s\n' "$(duration "$gc_seconds")" "$(render_token out timestamp "$gc_marker")"
  fi
}
