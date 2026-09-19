#!/bin/sh
# lib/stops.sh — step 4 of the tick: every ending acted on by its rule. M03 left the step as a
# name holding only the caffeinate re-arm; this is its body.
#
# One ending, one rule, one act. The taxonomy of docs/ARCHITECTURE.md §5.2 is `route_ending`, a
# lookup from (outcome, reason, error) to an action, a retry bit and a notify bit — data, not a
# chain of tests — because the cost of a wrong label is then one refused request per interval
# rather than a night (REQ-STOP-01). Everything below reads that answer and does the one thing it
# names: wait and resume, climb the ladder, redispatch, hold a model, or escalate.
#
# Nothing here decides anything a session or a person should. A resume carries a fixed text with
# slots filled from the log; a redispatch is the brief's own recovery clause; an escalation hands
# the lane over and stops acting on it.
#
# The wait and the hold live beside this in `lib/waits.sh`, which reads the same table. They are the
# half of step 4 that spends no attempt. The stops a session declared — `unfinished`, `blocked`,
# `main-broken` and a distant `wait` — live in `lib/declared.sh` (D-070). `stops_run` at the foot of
# this file drives all three.
set -eu

# route_ending <outcome> [<reason>] [<error>]: the stops taxonomy as one lookup. Prints
# {class, action, retry, notify, hold}.
#
#   class   the notification or escalation class the ending answers to
#   action  wait | ladder | redispatch | blocker | escalate | park-project | dispatch
#   retry   interval | at-once | ladder | none
#   notify  now | 1h | 2h | at-escalation | at-second | when-distant | no
#   hold    whether the class holds its model while the wait stands (REQ-STOP-13)
#
# API errors split on `error` alone (REQ-STOP-02) and nothing under them has retry = no: retrying
# into a hard block costs one refused request, while failing to retry a soft one costs the night.
# "Unrecoverable" therefore means notify now, not stop.
route_ending() {
  re_class=other; re_action=escalate; re_retry=none; re_notify=now; re_hold=false
  case "$1" in
    complete) re_class=complete; re_action=dispatch; re_notify=no ;;
    asking)   re_class=asking;   re_action=escalate ;;
    stopped)
      case "${2:-}" in
        api-error)
          case "${3:-}" in
            rate_limit)    re_class=rate_limit;    re_action=wait; re_retry=interval; re_notify=2h; re_hold=true ;;
            billing_error) re_class=billing_error; re_action=wait; re_retry=interval; re_notify=now; re_hold=true ;;
            overloaded|server_error) re_class=transient; re_action=wait; re_retry=interval; re_notify=1h ;;
            # The turn ended at the output limit with the process and the transcript intact, so
            # there is nothing to wait out: the retry is at once and the ceiling is the transient's.
            max_output_tokens)       re_class=transient; re_action=wait; re_retry=at-once;  re_notify=1h ;;
            # The same context fails the same way, so a resume is a refused request every fifteen
            # minutes forever; the recovery clause and a fresh context are the only way through.
            invalid_request) re_class=invalid_request; re_action=redispatch; re_notify=no ;;
            # A flagless resume restores the saved --model, so no retry can pick up a corrected
            # plan cell: the plan edit is the ruling and the next tick redispatches (D-014).
            model_not_found) re_class=model_not_found; re_action=escalate ;;
            authentication_failed|oauth_org_not_allowed|account_on_hold|cloud_credential_error|unknown)
              re_class=unrecoverable; re_action=wait; re_retry=interval ;;
            # An error string this table does not know lands where the five named ones land, which
            # is the safe direction: the person hears at once and the retries carry on, so a value
            # the CLI adds tomorrow costs a message rather than a night.
            *) re_class=unrecoverable; re_action=wait; re_retry=interval ;;
          esac ;;
        no-handover) re_class=no-handover; re_action=ladder;       re_retry=ladder; re_notify=at-escalation ;;
        unfinished)  re_class=unfinished;  re_action=redispatch;   re_notify=at-second ;;
        blocked)     re_class=blocked;     re_action=blocker;      re_notify=when-distant ;;
        merge-failed) re_class=merge-failed; re_action=escalate ;;
        main-broken)  re_class=main-broken;  re_action=park-project ;;
        *) ;;
      esac ;;
    *) ;;
  esac
  jq -nc --arg c "$re_class" --arg a "$re_action" --arg r "$re_retry" --arg n "$re_notify" \
    --argjson h "$re_hold" '{class: $c, action: $a, retry: $r, notify: $n, hold: $h}'
}

# ceiling_seconds <notify>: how long a wait runs before the person hears. A ceiling is when the
# person hears and never when the retries stop (REQ-STOP-03), so this is only ever compared against
# the elapsed time of a wait that is still retrying.
ceiling_seconds() {
  case "$1" in
    now) echo 0 ;;
    1h)  echo 3600 ;;
    2h)  echo 7200 ;;
    *)   echo -1 ;;
  esac
}

# model_of_attempt <project> <milestone> <attempt>: the model the attempt actually ran on, from its
# own dispatch event (REQ-LOG-08). The plan's cell is what the next dispatch would use; this is what
# the refused request was made on, which is what a hold is about.
model_of_attempt() {
  moa_log=$(log_json) || { echo "$moa_log"; return 1; }
  printf '%s' "$moa_log" | jq -r --arg p "$1" --arg m "$2" --argjson a "$3" '
    [ .[] | select(.kind == "dispatch" and .project == $p and .milestone == $m and .attempt == $a) ]
    | last | .model // empty'
}

# job_of_session <rows json> <session>: the background job id `claude stop` takes, which only a
# live row carries. Recovery can request any-state: a missing pid is not proof no process exists,
# and an identifiable stopped row still gives claude stop the job it must settle before reuse.
job_of_session() {
  printf '%s' "$1" | jq -r --arg s "$2" --arg mode "${3:-live}" \
    'map(select(.sessionId == $s and ($mode == "any-state" or .pid != null))
         | select((.id | type) == "string" and (.id | length) > 0)) | first | .id // empty'
}

# fork_session <short id>: the session id of a copy, from the 8-hex job id its note named.
#
# The note names the *job* id and every count, join and glob in Baton is on the session id, so the
# two must not be confused: measured live (item 46), a copy announced as `d2007634` has session id
# `d2007634-d17b-4b0d-9c67-a0cec9b98ff6`. Written short, `copy_fork.session` would point at nothing
# — no transcript, no row, and `current_session` would hand the next resume an id the CLI does not
# know. The row is asked first, as a dispatch asks it; the transcripts answer when no row does,
# because the short id is the session id's own prefix and the tree is globbed, never derived from a
# project — the same capture found a copy's transcript filed under the *resuming* process's cwd and
# not the original session's.
fork_session() {
  if fs_row=$(row_for_id "$1"); then
    fs_id=$(printf '%s' "$fs_row" | jq -r '.sessionId // empty')
    [ -z "$fs_id" ] || { printf '%s\n' "$fs_id"; return 0; }
  fi
  for fs_f in "$BATON_TRANSCRIPTS"/*/"$1"-*.jsonl; do
    [ -f "$fs_f" ] || continue
    basename "$fs_f" .jsonl
    return 0
  done
  return 1
}

# artifact_detail <archived path>: the `detail` of an archived artifact, cut to 500 characters. The
# consumed event records what an ending decided and not what it said, so the sentence a person needs
# — the split, the last assistant message — is read back from the archive, which derivation 4 calls
# the answer.
#
# The cut is the point. This is prose a session wrote at whatever length it took, and an escalation
# carries two of them at once: uncut, one `unfinished-twice` measured 28,757 bytes and `log_event`
# refused it, so the park that stops the retries was never written while the Mac message went out
# anyway — one notification a minute until morning, with nothing in the log to answer. A writer
# bounds its own fields, exactly as `dispatch_failed` bounds a stderr and `consume_one` bounds its
# own; the 4 KB refusal is the last defence and not the first.
artifact_detail() {
  [ -f "$1" ] || return 0
  jq -r '(.detail // "") | if length > 500 then .[0:500] + "…" else . end' "$1" 2>/dev/null || true
}

# stop_settle <session>: waits, for up to thirty seconds, until no row carrying the session has a
# pid — the moment a `claude stop` has taken effect. Non-zero when it has not by then.
#
# **A stop is not synchronous, and a resume issued before it lands forks.** M04 measured it once
# (item 46): `claude stop` returned `stopped 19fb4653` and a flagless resume a moment later met a
# session the CLI still called "already running in the background". M05's live proof met it on the
# path that matters most: a ruling delivered to a session parked at `AskUserQuestion` — the one kind
# of session that is certain to be running when Baton speaks to it — landed in a copy under a new
# id, filed under the resuming process's working directory, while the original was stopped behind
# it. The fork classifier recorded that correctly; this is what keeps it from being the normal case.
#
# Liveness is the pid and never the state (derivation 1), so the row may linger with `pid: null`
# and that is already stopped. The listing is read through `rows_read`, which tells a listing that
# could not be read from an empty one: read through `rows_json` a failed read is `[]`, which has no
# row with a pid, and the resume would go ahead on the one reading that saw nothing at all.
#
# The bound is sixty listings half a second apart — thirty seconds of sleep, and longer by however
# long each listing takes, all of it under the tick's lock. It is `row_for_id`'s bound, for the same
# reason in reverse: a fact about a row takes a beat to settle. Past it the resume goes ahead, the
# classifier is still there to catch a fork, and the caller says on stderr that the stop never
# showed, which is where a skipped tick's cause is then found.
stop_settle() {
  sts_i=0
  while [ "$sts_i" -lt 60 ]; do
    if sts_rows=$(rows_read); then
      printf '%s' "$sts_rows" | jq -e --arg s "$1" 'any(.[]; .sessionId == $s and .pid != null)' \
        > /dev/null 2>&1 || return 0
    fi
    sts_i=$((sts_i + 1))
    sleep 0.5
  done
  return 1
}

# resume_count_next <project> <milestone> <attempt>: "<attempt> <resume>" — derivation 10's attempt
# count, and the number the next resume of that attempt carries.
#
# It is a function rather than three lines inside `resume_session` because the ruling label names
# both numbers in its own text while the event records them as fields: two readings of one count,
# which must agree or the log and the prompt disagree about which resume a session is on. An empty
# attempt asks for the current one, which is the count, and the count is the authority (§6.1).
resume_count_next() {
  rcn_a=$(derive_attempt "$1" "$2" "$3") || { echo "$rcn_a"; return 1; }
  printf '%s %s\n' "$(printf '%s' "$rcn_a" | jq -r .resumes_for)" \
    "$(( $(printf '%s' "$rcn_a" | jq -r .resumes) + 1 ))"
}

# resume_session <project> <milestone> <attempt> <session> <job> <kind> <class> [<text>]: the one
# way Baton speaks to a running session. `claude stop <job>` first, then a flagless
# `claude --bg --resume <uuid> "<text>"`. Prints {outcome, session, note}; writes the `resume` event
# and, on a fork, the `copy_fork` event.
#
# **Flagless, and this is why.** A flagless resume continues under the same id and restores -n,
# --settings, --model and --permission-mode by itself, so the Stop gate survives; *any* flag forks a
# copy under a new id, measured (D-017, INV-08). To widen an allowlist the settings file is edited
# in place at the dispatched path, never re-passed here.
#
# **Three outcomes, from what the CLI prints.** A `note:` line saying the CLI started a copy means
# the stop did not take and a copy is now running: two live sessions on one milestone is duplicated
# work and a merge collision, so the original is stopped again and the new id carries the attempt.
# "woke session" is the success line. Anything else is refused, which is a failure ending on the
# ladder — after three of them the lane is handed over rather than resumed forever.
#
# **The fork test matches the family and not one phrasing.** §4.3 lists eight `note:` variants, and
# seven read "…started a copy as <Y>" while the generic one reads "started a copy *of that
# conversation* as <Y>". A rule keyed on the literal `started a copy as ` misses that one, and the
# section's claim that its rule survives every variant was false against its own list. Missing one
# costs the whole failure this function exists to prevent: the note is not seen, it is not the
# success line either, so the resume reads `refused`, the original is never stopped a second time,
# no `copy_fork` is written, and two live sessions run on one branch while the ladder climbs on a
# resume that in fact succeeded. So the test is `started a copy` and the id is the 8-hex token after
# the last ` as `, which reads every variant the section lists (D-058).
#
# Both streams are read and the fork test comes first. Which stream the note goes to was live item
# 46 and is recorded in this milestone's completion evidence; reading one stream only, or testing
# for the success line first, would classify a fork as refused or as delivered, and either would
# leave a second session running on the branch.
resume_session() {
  rs_p=$1; rs_m=$2; rs_a=$3; rs_s=$4; rs_job=$5; rs_kind=$6; rs_class=$7

  rs_r=$(resume_count_next "$rs_p" "$rs_m" "$rs_a") || { echo "$rs_r"; return 1; }
  rs_r=${rs_r#* }
  # A ruling is the third kind, and the only one whose text Baton does not compose from the log: it
  # carries a person's words, so the caller passes the finished label rather than a template and a
  # slot. The kind stays on the event either way, because `continue`, `finish` and `ruling` are
  # three different things to have done to a session.
  case "$rs_kind" in
    ruling)
      rs_text=${8:-}
      [ -n "$rs_text" ] || { echo "resume_session: a ruling carries its own text"; return 1; } ;;
    finish) rs_text=$(template_finish "$rs_m" "$rs_a" "$rs_r" "$rs_s") ;;
    *)      rs_text=$(template_continue "$rs_class" "$rs_m" "$rs_a" "$rs_r") ;;
  esac

  if [ -n "$rs_job" ]; then
    "$BATON_CLAUDE" stop "$rs_job" > /dev/null 2>&1 || true
    stop_settle "$rs_s" || render_failure err "baton: $rs_p/$rs_m session $rs_s still had a live row after the stop; resuming anyway, and a fork is what the classifier below is for"
  fi

  rs_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-resume.XXXXXX")
  set +e
  "$BATON_CLAUDE" --bg --resume "$rs_s" "$rs_text" > "$rs_tmp" 2> "$rs_tmp.err"
  rs_status=$?
  set -e
  # Both streams, and the colour taken out of both before anything is matched: the note the
  # classifier keys on is printed by the same CLI that colours the dispatch line (D-050). They are
  # kept apart as well as together, because the refusal below wants the diagnostic and the CLI puts
  # a `backgrounded` line on stdout whichever way the resume went.
  rs_out=$(cli_plain < "$rs_tmp"); rs_err=$(cli_plain < "$rs_tmp.err")
  rm -f "$rs_tmp" "$rs_tmp.err"

  rs_cls=$(resume_classify "$rs_out" "$rs_err" "$rs_status")
  rs_outcome=$(printf '%s' "$rs_cls" | jq -r .outcome)
  rs_note=$(printf '%s' "$rs_cls" | jq -r .note)
  rs_new=$(printf '%s' "$rs_cls" | jq -r '.copy // ""')
  # Why the original may still be running, once the fork branch below has tried to stop it; empty
  # while nothing is outstanding, which is every resume that did not fork.
  rs_unresolved=
  if [ "$rs_outcome" = refused ]; then
    # The `resume` event records that it was refused; the table fixes its fields and the reason is
    # not one of them. So the reason goes where a dispatch failure's detail already goes, which is
    # the one place a person looking at why the ladder is climbing will find it.
    render_failure err "baton: $rs_p/$rs_m the resume was refused: $rs_note"
  fi

  rs_side=$(sidecar_write "$rs_s" "$rs_text")
  log_event resume "$rs_p" "$rs_m" "$rs_s" "$rs_a" "$(jq -nc \
    --arg k "$rs_kind" --argjson r "$rs_r" --arg c "$rs_class" --arg o "$rs_outcome" \
    --arg pp "${rs_side% *}" --arg sha "${rs_side##* }" '
    {resume_kind: $k, resume: $r}
    | if $c != "" then . + {class: $c} else . end
    | . + {outcome: $o, prompt_path: $pp, prompt_sha256: $sha}')"

  if [ "$rs_outcome" = forked ]; then
    # The record comes before the second stop, and that order is the recovery. A fork writes no
    # dispatch event, so the attempt count is unchanged and the new id simply carries attempt n
    # (§6.1) — but only once `copy_fork` says so: until then `current_session` still answers with the
    # original, and a tick killed between the two would leave the next tick resuming a session the
    # CLI had already replaced, which is the second live session all over again. Writing the event
    # first cannot be made atomic with the stop, but it fails in the direction a recovery can read.
    if [ -n "$rs_new" ]; then
      rs_full=$(fork_session "$rs_new") || rs_full=''
      if [ -z "$rs_full" ]; then
        rs_full=$rs_new
        render_failure err "baton: $rs_p/$rs_m forked as $rs_new and neither a row nor a transcript names its session id; the short id stands in"
      fi
      log_event copy_fork "$rs_p" "$rs_m" "$rs_full" "$rs_a" \
        "$(jq -nc --arg f "$rs_s" --arg n "$rs_note" '{from_session: $f, note: $n}')"
      rs_new=$rs_full
    else
      # A note naming no id is still a fork: something is running that Baton cannot address. The
      # resume event already records `forked`, which is not a failure ending, so this is said where
      # a person will read it rather than swallowed.
      render_failure err "baton: $rs_p/$rs_m forked on resume but the note named no id: $rs_note"
    fi
    # Find the original again by the lane's name and its original session id, without a pid test.
    # A fork has the same name, so name alone could stop the copy we just adopted. This also works
    # when the caller had no live-row job id (for example, a wait's stale pid-less listing).
    rs_original=$(rows_read) || rs_original='[]'
    rs_original=$(printf '%s' "$rs_original" | jq -c --arg n "$(session_name "$rs_p" "$rs_m")" \
      'map(select(.name == $n))')
    rs_original=$(job_of_session "$rs_original" "$rs_s" any-state)
    rs_original=${rs_original:-$rs_job}
    # Finding the original is not stopping it. `copy_fork` has already moved the lane to the copy, so
    # every derivation from here on follows the copy and the original is tracked by nothing: if it
    # outlives this, two sessions work one branch and one of them is invisible. The first stop is
    # allowed to fail — that is the classifier's whole design, and the fork is how it finds out — but
    # this one is the last thing standing between a reported success and an untracked worker, so it
    # is settled exactly as the first one is, and what will not settle is escalated rather than
    # warned about. The park is what stops Baton acting on the lane, and the message is what tells
    # the person which session to stop; a lane never reports plain success while a worker it no
    # longer tracks may be running (D-132).
    if [ -z "$rs_original" ]; then
      rs_unresolved="no job in the listing identifies it"
    elif ! "$BATON_CLAUDE" stop "$rs_original" > /dev/null 2>&1; then
      rs_unresolved="the stop of job $rs_original was refused"
    elif ! stop_settle "$rs_s"; then
      rs_unresolved="job $rs_original was stopped but its row still carried a pid"
    fi
    if [ -n "$rs_unresolved" ]; then
      rs_carries=$(jq -nc --arg o "$rs_s" --arg c "${rs_new:-}" --arg w "$rs_unresolved" \
        --arg d "the resume forked and the original session $rs_s may still be running: $rs_unresolved. $(session_name "$rs_p" "$rs_m") is now carried by ${rs_new:-a copy Baton could not name}; stop the original by hand and leave one session live" \
        '{original: $o, why: $w, detail: $d} | if $c != "" then . + {copy: $c} else . end')
      escalate "$rs_p" "$rs_m" "${rs_new:-$rs_s}" "$rs_a" other lane "$rs_carries" \
        || render_failure err "baton: $rs_p/$rs_m the park for the unstopped original $rs_s could not be written"
      render_failure err "baton: $rs_p/$rs_m forked and the original session $rs_s was not confirmed stopped ($rs_unresolved); the lane is parked"
    fi
  fi

  jq -nc --arg o "$rs_outcome" --arg s "${rs_new:-$rs_s}" --arg n "$rs_note" --arg u "$rs_unresolved" \
    '{outcome: $o, session: $s, note: $n}
     | if $u != "" then . + {unresolved_original: $u} else . end'
}
# ladder_position <project> <milestone> <attempt>: derivation 9, plus the two facts acting on it
# needs — which ending was the newest, and whether a step has already been taken for it. One resume,
# then one redispatch, then escalate; a wait never counts and never re-arms. A second count spans
# attempts until a session-written consumed proves progress; its third failure also ends the ladder.
#
# `acted` is what stops the resume rung firing every sixty seconds. The rung itself does not change
# the count — a resume is not a failure ending and not a reset point — so without it the same
# failure would be answered on every tick until it became a second one.
ladder_position() {
  lpo_log=$(log_json) || { echo "$lpo_log"; return 1; }
  printf '%s' "$lpo_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" '
    def failure: (.kind == "consumed" and .reason == "no-handover")
                 or (.kind == "crash_sighting" and .sighting == 2)
                 or (.kind == "resume" and .outcome == "refused" and .resume_kind != "ruling");
    [ to_entries[] | {i: .key} + .value
      | select(.project == $p and .milestone == $m) ] as $lane
    | ([$lane[] | select(.kind == "consumed" and .written_by == "session")] | last) as $progress
    | ([$lane[] | select(.i > ($progress.i // -1)) | select(failure)] | length) as $ineffective
    | [$lane[] | select(.attempt == $a)] as $ev
    | ([ $ev[] | select(.kind == "dispatch" or (.kind == "consumed" and .written_by == "session")) ]
       | last) as $reset
    | [ $ev[] | select(.i > ($reset.i // -1))
        | select(failure) ] as $f
    | ($f | last) as $newest
    | { failures: ($f | length), ineffective_failures: $ineffective,
        next: (if ($f | length) == 0 then "none"
               elif $ineffective >= 3 then "escalate"
               elif ($f | length) == 1 then "resume"
               elif ($f | length) == 2 then "redispatch"
               else "escalate" end),
        ending: $newest.kind, ending_at: $newest.at, ending_class: $newest.class,
        archive: $newest.archive,
        acted: (([ $ev[] | select(.i > ($newest.i // -1))
                   | select(.kind == "resume" or .kind == "dispatch") ] | length) > 0) }
    | with_entries(select(.value != null))'
}

# redispatch <project> <milestone> <plan json> <rows json> <why>: attempt n+1 through the brief's
# own recovery clause. The worktree is the reused one, so the new session stands on the branch that
# holds the last attempt's work and the slot line names the commit (REQ-STOP-07); the recovery
# clause keys on the brief's completion evidence and never on the number.
#
# It goes through dispatch_try rather than dispatch_one so that a redispatch which cannot produce a
# session is bounded the same way a first dispatch is: two failures in a row park the lane.
redispatch() {
  if ! rdp_row=$(printf '%s' "$3" | plan_row "$2" 2>/dev/null); then
    render_failure err "baton: $1/$2 would be redispatched but the plan no longer holds it"
    return 0
  fi
  rdp_model=$(printf '%s' "$rdp_row" | jq -r '.model // ""')
  # A redispatch is a new session, and a project park holds every new session for the project: it
  # would start from a `main` a person has been asked to fix. It waits as it waits for a hold, and the
  # rule that asked for it asks again on the tick after the park is answered.
  if rdp_park=$(project_held "$1"); then
    render_row out action 'held      %s/%s · the project is parked (%s), so the redispatch waits for the park to be answered\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$rdp_park"
    return 0
  fi
  # The line says the hold stands rather than naming what would lift it: since M14 a hold is not
  # always a usage-limit wait — a budget pause holds every model until the window rolls — and a
  # line that told a person to wait for a wait that does not exist would send them looking for one.
  # `baton status` names each open hold and its cause, which is where that answer belongs.
  if hold_bites "$rdp_model"; then
    render_row out action 'held      %s/%s · %s is held, so the redispatch waits until the hold lifts\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$(render_token out state "$rdp_model")"
    return 0
  fi
  # The budget's remaining starts, beside the hold, because this rung runs in steps 3 to 6 — before
  # the dispatch pass — and writes a `dispatch` event of its own. `hold_bites` answers from the hold
  # `budget_check` wrote at the top of the tick, which is a count taken before this tick's own
  # redispatches; with several lanes on the rung at once they would each pass it and each spend a
  # start the window could not afford. `budget_room` re-reads the log, so a redispatch made a moment
  # ago in this same tick is already in the number. Empty when `budgetSessions` is off, which is the
  # default, and this costs nothing (D-181).
  rdp_room=$(budget_room) || { render_failure err "$rdp_room"; return 1; }
  if [ -n "$rdp_room" ] && [ "$rdp_room" -le 0 ]; then
    render_row out action 'held      %s/%s · the window has no start left to spend, so the redispatch waits for it to roll\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")"
    return 0
  fi
  rdp_attempt=$(attempt_of "$1" "$2")
  rdp_session=$(current_session "$1" "$2" "$rdp_attempt")
  rdp_job=$(job_of_session "$4" "$rdp_session" any-state)
  if [ -z "$rdp_job" ]; then
    render_failure err "baton: $1/$2 redispatch refused: no job identifies outgoing session $rdp_session in the listing"
    return 0
  fi
  if ! "$BATON_CLAUDE" stop "$rdp_job" > /dev/null 2>&1 || ! stop_settle "$rdp_session"; then
    render_failure err "baton: $1/$2 redispatch refused: outgoing job $rdp_job has not been confirmed stopped"
    return 0
  fi
  render_row out record 'redispatch %s/%s · %s\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$5"
  dispatch_try "$1" "$2" "$3" "$4"
}

# ladder_step <project> <milestone> <attempt> <plan json> <rows json> <position json>: the rung.
ladder_step() {
  lst_next=$(printf '%s' "$6" | jq -r .next)
  [ "$lst_next" != none ] || return 0
  lst_ending=$(printf '%s' "$6" | jq -r '.ending // ""')
  lst_acted=$(printf '%s' "$6" | jq -r .acted)
  lst_fail=$(printf '%s' "$6" | jq -r '.ineffective_failures // .failures')
  lst_s=$(current_session "$1" "$2" "$3") || { render_failure err "$lst_s"; return 1; }

  case "$lst_next" in
    resume)
      [ "$lst_acted" = false ] || return 0
      [ -n "$lst_s" ] || { render_failure err "baton: $1/$2 has a failure ending but no event names its session"; return 0; }
      lst_job=$(job_of_session "$5" "$lst_s" any-state)
      if [ -z "$lst_job" ]; then
        render_failure err "baton: $1/$2 resume rung refused: no job identifies session $lst_s in the listing"
        return 0
      fi
      # A crash with no transcript on disk cannot be resumed under its id, so it takes the
      # redispatch instead — the resume-versus-redispatch test REQ-STOP-10 names (and the reason
      # cleanupPeriodDays is a setup fact: a swept transcript changes this answer silently).
      if [ "$lst_ending" = crash_sighting ] && ! transcript_of "$lst_s" > /dev/null 2>&1; then
        redispatch "$1" "$2" "$4" "$5" "the crash left no transcript, so attempt $(( $3 + 1 )) starts fresh"
        return 0
      fi
      case "$lst_ending" in
        consumed)       lst_kind=finish;   lst_class='no handover' ;;
        crash_sighting) lst_kind=continue; lst_class='process gone' ;;
        *)              lst_kind=continue
                        lst_class=$(printf '%s' "$6" | jq -r '.ending_class // "process gone"') ;;
      esac
      lst_out=$(resume_session "$1" "$2" "$3" "$lst_s" "$lst_job" \
        "$lst_kind" "$lst_class") || { render_failure err "$lst_out"; return 1; }
      render_row out record 'resume    %s/%s · %s · %s · %s\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$(render_token out session "$lst_s")" "$lst_kind" \
        "$(printf '%s' "$lst_out" | jq -r .outcome)"
      ;;
    redispatch)
      [ "$lst_acted" = false ] || return 0
      redispatch "$1" "$2" "$4" "$5" "the resume did not bring it back, so attempt $(( $3 + 1 )) starts from the brief"
      ;;
    escalate)
      # The park is the guard: stops_run skips a lane that already has one, so this is written once
      # and the retries stop with it. Nothing times out into a decision — the lane waits for the
      # person and the record says what it was carrying when it stopped. Once the person has
      # answered the park, the same count must not park it again: an edit to the brief or the plan
      # is what the next attempt starts from, and a ruling is already in the session's hands.
      case "$(person_acted "$1" "$2" ladder-end)" in
        edit)
          redispatch "$1" "$2" "$4" "$5" "the brief or the work plan changed after the ladder ended, so attempt $(( $3 + 1 )) starts from it"
          return 0 ;;
        ruling) return 0 ;;
      esac
      lst_detail=$(artifact_detail "$(printf '%s' "$6" | jq -r '.archive // ""')")
      case "$lst_ending" in
        consumed)       lst_says="a turn that ended with no handover" ;;
        crash_sighting) lst_says="a crash confirmed over two ticks" ;;
        resume)         lst_says="a resume the CLI refused" ;;
        *)              lst_says="an ending Baton could not name" ;;
      esac
      [ -n "$lst_detail" ] || lst_detail="it left no detail"
      lst_span='in a row on this attempt'
      if [ "$lst_fail" -gt "$(printf '%s' "$6" | jq -r .failures)" ]; then
        lst_span='since the last session-written handover, across attempts'
      fi
      lst_carries=$(jq -nc --argjson n "$lst_fail" --arg e "$lst_ending" --arg d "$lst_detail" \
        --arg dd "$lst_fail failure endings $lst_span, the last $lst_says: $lst_detail" \
        '{failures: $n, ending: $e, last_detail: $d, detail: $dd}')
      escalate "$1" "$2" "$lst_s" "$3" ladder-end lane "$lst_carries"
      render_row out action 'ladder    %s/%s · %s failures in a row · the lane is parked\n' "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$lst_fail"
      ;;
  esac
}

# stops_standing_by <session> <milestone> <stand-off list> <parked json>: whether Baton has stopped
# acting on this lane. A taken-over lane is a person's (INV-04); a parked lane waits for a ruling or
# an edit and nothing times out into a decision. Either way step 4 passes it by — and that is also
# what stops an escalation this step writes from being written again on the next tick.
#
# Any park naming the milestone stands it by, whatever its scope. A `main-broken` park is project
# scope because of what it holds — every new dispatch for the project — but it is still the park of
# the session that wrote it, which waits for its ruling; the in-flight lanes that run on are the
# others. Read as a lane with no park, the ladder would count that ruling's own refused resume as a
# failure ending and resume the session with the continue template, which does not carry the ruling.
stops_standing_by() {
  if stood_off "$1" "$3"; then return 0; fi
  if printf '%s' "$4" | jq -e --arg m "$2" \
       'any(.parked[]; .milestone == $m)' > /dev/null; then return 0; fi
  return 1
}

# stops_run <project> <plan json> <rows json> <stand-off list>: step 4 for one project — the waits
# and their retries, the ladder, the declared stops, and the distant wait.
#
# The order is the order a lane's facts arrive. The waits go first because a retry this tick is a
# fact the ladder then reads: a resume that was refused is a failure ending, and the lane climbs on
# the same tick rather than a minute later. The declared stops come after the ladder because their
# redispatch opens a new attempt and everything above reads the old one.
#
# A lane with an active wait is the wait's and not the ladder's: the wait already resumes it every
# fifteen minutes, so the ladder's resume and redispatch rungs would resume the same session twice.
# The escalate rung still fires, because three refused resumes in a row mean the session cannot be
# resumed at all, and the lane is better handed over than retried until morning.
stops_run() {
  srn_parked=$(derive_parked "$1") || { render_failure err "$srn_parked"; return 1; }
  srn_flight=$(derive_in_flight "$1" "$3") || { render_failure err "$srn_flight"; return 1; }
  srn_flying=$(printf '%s' "$srn_flight" | jq -c '[ .in_flight[] | .milestone ]')
  srn_now=$(now_epoch)

  # 1. The waits, routed by the error alone.
  srn_waits=$(wait_due "$1") || { render_failure err "$srn_waits"; return 1; }
  srn_waiting=''
  srn_n=$(printf '%s' "$srn_waits" | jq length); srn_i=0
  while [ "$srn_i" -lt "$srn_n" ]; do
    srn_w=$(printf '%s' "$srn_waits" | jq -c ".[$srn_i]"); srn_i=$((srn_i + 1))
    srn_m=$(printf '%s' "$srn_w" | jq -r .milestone)
    srn_a=$(printf '%s' "$srn_w" | jq -r .attempt)
    srn_s=$(printf '%s' "$srn_w" | jq -r '.session // ""')
    srn_e=$(printf '%s' "$srn_w" | jq -r '.error // "unknown"')
    srn_waiting="$srn_waiting$srn_m
"
    if stops_standing_by "$srn_s" "$srn_m" "$4" "$srn_parked"; then continue; fi
    case "$(printf '%s' "$srn_w" | jq -r .route.action)" in
      wait)
        srn_run=$(wait_run "$1" "$srn_m" "$srn_a") || { render_failure err "$srn_run"; return 1; }
        srn_since=$(printf '%s' "$srn_run" | jq -r --arg f "$(printf '%s' "$srn_w" | jq -r .since)" '.since // $f')
        srn_at=$(iso_epoch "$srn_since") || { render_failure err "$srn_at"; return 1; }
        wait_notify "$1" "$srn_w" "$srn_since" "$((srn_now - srn_at))"
        # max_output_tokens is retried at once, but only for its first retry: the turn ended at the
        # output limit with everything intact, so there is nothing to wait out — and a session that
        # meets it again has a real loop, which the interval is the right answer to.
        srn_due=$(printf '%s' "$srn_w" | jq -r .due)
        if [ "$srn_due" != true ] && [ "$(printf '%s' "$srn_w" | jq -r .route.retry)" = at-once ] \
           && [ "$(printf '%s' "$srn_w" | jq -r .retries)" = 0 ]; then
          srn_due=true
        fi
        [ "$srn_due" != true ] || wait_retry_run "$1" "$srn_w" "$3"
        ;;
      redispatch)
        # invalid_request: the context is what failed, so a resume fails the same way. The second in
        # a row says the fresh context was not the answer either, and the ladder has then ended.
        srn_run=$(consecutive_run "$1" "$srn_m" invalid_request) || { render_failure err "$srn_run"; return 1; }
        if [ "$(printf '%s' "$srn_run" | jq -r .count)" -ge 2 ]; then
          case "$(person_acted "$1" "$srn_m" ladder-end)" in
            edit)
              redispatch "$1" "$srn_m" "$2" "$3" "the brief or the work plan changed after the context overflowed twice, so attempt $((srn_a + 1)) starts from it"
              continue ;;
            ruling) continue ;;
          esac
          escalate "$1" "$srn_m" "$srn_s" "$srn_a" ladder-end lane \
            "$(splits_carries "$srn_run" "$srn_m" "with $srn_e")"
          render_row out action 'ladder    %s/%s · %s twice in a row · the lane is parked\n' "$(render_token out lane "$1")" "$(render_token out milestone "$srn_m")" "$srn_e"
        else
          redispatch "$1" "$srn_m" "$2" "$3" "the context is what failed, so attempt $((srn_a + 1)) starts fresh"
        fi
        ;;
      escalate)
        # model_not_found, at once and with no retry: a flagless resume restores the refused model,
        # so nothing Baton can do reaches it. The plan edit is the ruling and the next tick
        # redispatches with the model the cell then names — so once the person has edited, the step
        # is the redispatch and not a second park, and a ruling stands this down until the resumed
        # session ends again.
        #
        # The line says the model changed and not that a person edited the cell. What released the
        # park is a digest of the effective model differing from the one the park recorded, and a
        # content hash establishes a difference and never an author: the cell may have been edited,
        # or the alias it names may now resolve elsewhere in `config.json` (D-134).
        case "$(person_acted "$1" "$srn_m" model_not_found)" in
          edit)
            redispatch "$1" "$srn_m" "$2" "$3" "the effective model changed since the model was refused, so attempt $((srn_a + 1)) runs on it"
            continue ;;
          ruling) continue ;;
        esac
        # The model the attempt ran on, from its own dispatch event, and never the plan's cell: the
        # cell is what the next attempt will use, and after an edit it names the model that fixed it.
        srn_cell=$(model_of_attempt "$1" "$srn_m" "$srn_a" 2>/dev/null || true)
        [ -n "$srn_cell" ] || srn_cell='?'
        srn_plan_file=$(jq -r '.plan // "docs/MILESTONES.md"' "$BATON_HOME/projects/$1/project.json" 2>/dev/null || echo docs/MILESTONES.md)
        # The detail says what happened and the message's verb says what to do about it; saying the
        # edit in both is the same sentence twice on a lock screen (REQ-ESC-03's three parts).
        srn_detail="the model $srn_cell was refused; a flagless resume would ask for it again, so nothing Baton can do reaches this lane"
        escalate "$1" "$srn_m" "$srn_s" "$srn_a" model_not_found lane \
          "$(jq -nc --arg m "$srn_cell" --arg f "$srn_plan_file" --arg d "$srn_detail" \
             '{model: $m, plan: $f, detail: $d}')"
        render_row out action 'model     %s/%s · %s was refused · the lane is parked until the cell is edited\n' "$(render_token out lane "$1")" "$(render_token out milestone "$srn_m")" "$(render_token out state "$srn_cell")"
        ;;
    esac
  done

  # 2. The ladder, over every open lane. The parks are re-read first: a section above may have
  # written one, and a lane parked twice in a tick is a lane `baton answer` then refuses to act on
  # because two escalations carry its name.
  srn_parked=$(derive_parked "$1") || { render_failure err "$srn_parked"; return 1; }
  srn_log=$(log_json) || { render_failure err "$srn_log"; return 1; }
  srn_open=$(lanes_open "$1" "$srn_log") || { render_failure err "$srn_open"; return 1; }
  srn_n=$(printf '%s' "$srn_open" | jq length); srn_i=0
  while [ "$srn_i" -lt "$srn_n" ]; do
    srn_l=$(printf '%s' "$srn_open" | jq -c ".[$srn_i]"); srn_i=$((srn_i + 1))
    srn_m=$(printf '%s' "$srn_l" | jq -r .milestone)
    srn_a=$(printf '%s' "$srn_l" | jq -r '.attempt // ""')
    srn_s=$(printf '%s' "$srn_l" | jq -r '.session // ""')
    [ -n "$srn_a" ] || continue
    if stops_standing_by "$srn_s" "$srn_m" "$4" "$srn_parked"; then continue; fi
    srn_pos=$(ladder_position "$1" "$srn_m" "$srn_a") || { render_failure err "$srn_pos"; return 1; }
    srn_next=$(printf '%s' "$srn_pos" | jq -r .next)
    [ "$srn_next" != none ] || continue
    if [ "$srn_next" != escalate ] && printf '%s\n' "$srn_waiting" | grep -Fqx "$srn_m"; then continue; fi
    ladder_step "$1" "$srn_m" "$srn_a" "$2" "$3" "$srn_pos"
  done

  # 3. The declared stops that have not been acted on, against the parks as they now stand.
  srn_parked=$(derive_parked "$1") || { render_failure err "$srn_parked"; return 1; }
  srn_declared=$(declared_open "$1") || { render_failure err "$srn_declared"; return 1; }
  srn_n=$(printf '%s' "$srn_declared" | jq length); srn_i=0
  while [ "$srn_i" -lt "$srn_n" ]; do
    srn_d=$(printf '%s' "$srn_declared" | jq -c ".[$srn_i]"); srn_i=$((srn_i + 1))
    srn_m=$(printf '%s' "$srn_d" | jq -r .milestone)
    srn_s=$(printf '%s' "$srn_d" | jq -r '.session // ""')
    if stops_standing_by "$srn_s" "$srn_m" "$4" "$srn_parked"; then continue; fi
    declared_step "$1" "$srn_d" "$2" "$3" "$srn_flying"
  done

  # 4. A handover that waits for something nothing is going to finish.
  distant_wait_for_check "$1" "$2" "$srn_flying"
}
