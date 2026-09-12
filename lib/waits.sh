#!/bin/sh
# lib/waits.sh — the wait and the hold: the half of step 4 that spends no attempt. An API error is
# not a fault in the work, so Baton neither redispatches nor counts it on the ladder; it stops the
# session, resumes it flagless every retryMinutes with the continue template, tells the person once
# the class's ceiling passes, and holds the model against new dispatches until the wait clears
# (REQ-STOP-03, REQ-STOP-13).
#
# The taxonomy that decides which error waits at all is `route_ending` in lib/stops.sh; everything
# here reads its answer.
set -eu

# wait_run <project> <milestone> <attempt>: the continuous wait this attempt is in — when it began
# and how many retries it has had — measured from the attempt's newest reset point, the same reset
# the ladder and every once-only key use.
#
# Derivation 5 answers a different question, and both are needed. It names the *newest* api-error
# consume, because that is what makes the wait active and sets the next retry. But a resumed session
# that meets the same limit again writes another api-error artifact, so under a standing limit a new
# consume lands every fifteen minutes — and taking each one as the start would reset the clock every
# cycle and the two-hour ceiling would never be reached. The continuous wait therefore begins at the
# *oldest* api-error consume since the reset, and that is the `since` every wait_retry carries, so
# derivation 5 reports it too from the first retry on.
wait_run() {
  wrn_log=$(log_json) || { echo "$wrn_log"; return 1; }
  printf '%s' "$wrn_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" '
    [ to_entries[] | {i: .key} + .value
      | select(.project == $p and .milestone == $m and .attempt == $a) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch" or (.kind == "consumed" and .written_by == "session")) ]
       | last) as $reset
    | [ $ev[] | select(.i > ($reset.i // -1)) ] as $run
    | { since: ([ $run[] | select(.kind == "consumed" and .reason == "api-error") ] | first | .at),
        retries: ([ $run[] | select(.kind == "wait_retry") ] | length) }
    | with_entries(select(.value != null))'
}

# wait_due <project>: every active wait (derivation 5) with its routing attached, so a caller reads
# one document rather than asking the table again per field. `due` is derivation 5's own: the newest
# wait_retry plus retryMinutes, read from the last retry and never extrapolated from the first,
# because a lid-close sleep stretches every interval.
wait_due() {
  wdu_doc=$(derive_waits "$1") || { echo "$wdu_doc"; return 1; }
  wdu_out='[]'
  wdu_n=$(printf '%s' "$wdu_doc" | jq '.waits | length'); wdu_i=0
  while [ "$wdu_i" -lt "$wdu_n" ]; do
    wdu_w=$(printf '%s' "$wdu_doc" | jq -c ".waits[$wdu_i]"); wdu_i=$((wdu_i + 1))
    wdu_route=$(route_ending stopped api-error "$(printf '%s' "$wdu_w" | jq -r '.error // ""')")
    wdu_out=$(printf '%s' "$wdu_out" | jq -c --argjson w "$wdu_w" --argjson r "$wdu_route" \
      '. + [$w + {route: $r}]')
  done
  printf '%s\n' "$wdu_out"
}

# wait_notify <project> <wait json> <since> <elapsed seconds>: the ceiling. The person hears once
# per class per attempt, and the retries carry on past it up to the weekly horizon — a weekly limit
# is legitimate to wait for, and what the person needs by morning is to know the night went to a
# limit rather than to a bug (REQ-STOP-03).
wait_notify() {
  wn_m=$(printf '%s' "$2" | jq -r .milestone)
  wn_a=$(printf '%s' "$2" | jq -r .attempt)
  wn_s=$(printf '%s' "$2" | jq -r '.session // ""')
  wn_e=$(printf '%s' "$2" | jq -r '.error // "unknown"')
  wn_class=$(printf '%s' "$2" | jq -r .route.class)
  wn_ceiling=$(ceiling_seconds "$(printf '%s' "$2" | jq -r .route.notify)")
  [ "$wn_ceiling" -ge 0 ] || return 0
  [ "$4" -ge "$wn_ceiling" ] || return 0
  wn_spent=$(derive_key_spent "$1" "$wn_m" "$wn_a" "$wn_class") || { echo "$wn_spent" >&2; return 1; }
  [ "$(printf '%s' "$wn_spent" | jq -r .spent)" = false ] || return 0
  wn_retry=$(config_num retryMinutes 15)
  wn_detail="$wn_e since $3, waiting $(duration "$4"); Baton keeps resuming every $wn_retry minutes and stops for nothing"
  wn_fields=$(jq -nc --arg e "$wn_e" --argjson age "$4" --arg since "$3" --arg d "$wn_detail" \
    '{error: $e, elapsed_seconds: $age, since: $since, detail: $d}')
  notification_write "$1" "$wn_m" "$wn_s" "$wn_a" "$wn_class" "" "$wn_fields"
  echo "ceiling   $1/$wn_m · $wn_e · $(duration "$4") of waiting"
}

# wait_retry_run <project> <wait json> <rows json>: one turn of the wait — stop, flagless resume
# with the continue template, and the `wait_retry` event. Spends no attempt and never redispatches
# (REQ-STOP-03).
#
# The event is written whatever the resume returned, because the retry happened. Derivation 5 reads
# the next retry off the newest wait_retry, so a refused resume that wrote nothing would leave the
# wait due on every tick — a refused request a minute instead of one every fifteen.
wait_retry_run() {
  wrr_m=$(printf '%s' "$2" | jq -r .milestone)
  wrr_a=$(printf '%s' "$2" | jq -r .attempt)
  wrr_e=$(printf '%s' "$2" | jq -r '.error // "unknown"')
  wrr_run=$(wait_run "$1" "$wrr_m" "$wrr_a") || { echo "$wrr_run" >&2; return 1; }
  wrr_since=$(printf '%s' "$wrr_run" | jq -r --arg f "$(printf '%s' "$2" | jq -r .since)" '.since // $f')
  wrr_n=$(( $(printf '%s' "$wrr_run" | jq -r .retries) + 1 ))

  # The session currently carrying the attempt, which is the newest of its dispatch and every later
  # copy_fork (§6.1): a wait that forked once is resumed under the copy's id from then on.
  wrr_s=$(current_session "$1" "$wrr_m" "$wrr_a") || { echo "$wrr_s" >&2; return 1; }
  [ -n "$wrr_s" ] || wrr_s=$(printf '%s' "$2" | jq -r '.session // ""')
  [ -n "$wrr_s" ] || { echo "baton: $1/$wrr_m is waiting but no event names its session" >&2; return 0; }

  wrr_out=$(resume_session "$1" "$wrr_m" "$wrr_a" "$wrr_s" "$(job_of_session "$3" "$wrr_s")" \
    continue "$wrr_e") || { echo "$wrr_out" >&2; return 1; }
  log_event wait_retry "$1" "$wrr_m" "$wrr_s" "$wrr_a" \
    "$(jq -nc --arg e "$wrr_e" --arg since "$wrr_since" --argjson r "$wrr_n" \
       '{error: $e, since: $since, retry: $r}')"
  printf 'retry     %s/%s · %s · retry %s · %s\n' "$1" "$wrr_m" "$wrr_e" "$wrr_n" \
    "$(printf '%s' "$wrr_out" | jq -r .outcome)"
}

# holds_apply: REQ-STOP-13, over every project at once. A model with an active rate_limit or
# billing_error wait is held; once a second model is limited the limit is shared rather than
# per-model, so every model is held; all of them lift when the waits clear.
#
# The hold is a fact about the account and not about a lane, so it is applied once per tick before
# any project's step 4 — a limit one project met holds the model for every project.
#
# It lifts when the wait clears and not when a resume is delivered. A delivered resume only means
# the session was woken; under a standing limit it meets the same limit seconds later. Lifting there
# would open the model every fifteen minutes and the same tick would dispatch a new session onto it,
# which is the whole of what the hold exists to stop.
holds_apply() {
  hap_waits=$(wait_due "") || { echo "$hap_waits" >&2; return 1; }
  hap_want='[]'
  hap_n=$(printf '%s' "$hap_waits" | jq length); hap_i=0
  while [ "$hap_i" -lt "$hap_n" ]; do
    hap_w=$(printf '%s' "$hap_waits" | jq -c ".[$hap_i]"); hap_i=$((hap_i + 1))
    [ "$(printf '%s' "$hap_w" | jq -r .route.hold)" = true ] || continue
    hap_model=$(model_of_attempt "$(printf '%s' "$hap_w" | jq -r .project)" \
      "$(printf '%s' "$hap_w" | jq -r .milestone)" "$(printf '%s' "$hap_w" | jq -r .attempt)") \
      || { echo "$hap_model" >&2; return 1; }
    # A wait on a lane with no dispatch event names no model, so there is nothing to hold. The
    # wait itself still runs; only the hold needs the model.
    [ -n "$hap_model" ] || continue
    hap_want=$(printf '%s' "$hap_want" | jq -c --argjson w "$hap_w" --arg model "$hap_model" '
      . + [{model: $model, cause: $w.route.class, project: $w.project, session: ($w.session // "")}]')
  done
  hap_want=$(printf '%s' "$hap_want" | jq -c 'unique_by([.model, .cause])')

  hap_open=$(derive_holds) || { echo "$hap_open" >&2; return 1; }
  hap_open=$(printf '%s' "$hap_open" | jq -c \
    '[ .holds[] | select(.cause == "rate_limit" or .cause == "billing_error") ]')

  hap_n=$(printf '%s' "$hap_want" | jq length); hap_i=0
  while [ "$hap_i" -lt "$hap_n" ]; do
    hap_h=$(printf '%s' "$hap_want" | jq -c ".[$hap_i]"); hap_i=$((hap_i + 1))
    printf '%s' "$hap_open" | jq -e --argjson h "$hap_h" \
      'any(.[]; .model == $h.model and .cause == $h.cause) | not' > /dev/null || continue
    log_event hold "$(printf '%s' "$hap_h" | jq -r .project)" "" \
      "$(printf '%s' "$hap_h" | jq -r .session)" "" \
      "$(printf '%s' "$hap_h" | jq -c '{model, cause}')"
    printf 'hold      %s · %s · no dispatch on it while the wait stands\n' \
      "$(printf '%s' "$hap_h" | jq -r .model)" "$(printf '%s' "$hap_h" | jq -r .cause)"
  done

  # The second-model rule. rate_limit names two different limits — the per-model one, for which
  # holding that model is right, and the session and weekly limits, which are shared — and only the
  # message text says which, which the tick does not read. A second model refusing is the
  # deterministic answer: the limit is shared, so hold every model. One refused request is the price
  # of learning it, paid once and read from the log rather than from a sentence.
  hap_models=$(printf '%s' "$hap_want" | jq '[ .[] | .model ] | unique | length')
  hap_all_open=$(printf '%s' "$hap_open" | jq 'any(.[]; .model == "all")')
  if [ "$hap_models" -ge 2 ] && [ "$hap_all_open" = false ]; then
    hap_h=$(printf '%s' "$hap_want" | jq -c 'last')
    log_event hold "$(printf '%s' "$hap_h" | jq -r .project)" "" \
      "$(printf '%s' "$hap_h" | jq -r .session)" "" \
      "$(printf '%s' "$hap_h" | jq -c '{model: "all", cause: .cause}')"
    echo "hold      all · a second model is limited, so the limit is shared and every model is held"
  fi

  hap_n=$(printf '%s' "$hap_open" | jq length); hap_i=0
  while [ "$hap_i" -lt "$hap_n" ]; do
    hap_h=$(printf '%s' "$hap_open" | jq -c ".[$hap_i]"); hap_i=$((hap_i + 1))
    if [ "$(printf '%s' "$hap_h" | jq -r .model)" = all ]; then
      [ "$hap_models" -lt 2 ] || continue
    else
      printf '%s' "$hap_want" | jq -e --argjson h "$hap_h" \
        'any(.[]; .model == $h.model and .cause == $h.cause) | not' > /dev/null || continue
    fi
    log_event hold_lifted "$(printf '%s' "$hap_h" | jq -r '.project // ""')" "" "" "" \
      "$(printf '%s' "$hap_h" | jq -c '{model, cause}')"
    printf 'lifted    %s · %s · the wait cleared\n' \
      "$(printf '%s' "$hap_h" | jq -r .model)" "$(printf '%s' "$hap_h" | jq -r .cause)"
  done
}

# hold_bites <model>: whether a dispatch on that model is held right now (derivation 12). Every
# dispatch this milestone can cause goes through it — the tick's step 7 and the redispatch alike —
# because starting a new session on a limited model is the refused request the hold exists to save.
#
# A derivation that fails reads as held rather than as clear. The answer is a question about the
# account that Baton could not ask, and the two ways of being wrong are not equal: withholding a
# dispatch costs a minute, while dispatching onto a limited model costs the session.
hold_bites() {
  hb_doc=$(derive_dispatch_hold) || { echo "$hb_doc" >&2; return 0; }
  printf '%s' "$hb_doc" | jq -e --arg m "$1" '.all or ((.held_models | index($m)) != null)' > /dev/null
}
