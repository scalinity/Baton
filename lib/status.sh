#!/bin/sh
# lib/status.sh — the one view. Whole file, every time, no flags, in the fixed order of
# docs/ARCHITECTURE.md §5.3: the last tick, project-scope parks, parked lanes, taken-over lanes,
# waits and holds, in flight, silent waits, an open gap, and last what is waiting in the inbox.
# Every line is a field of a derivation's document; nothing here re-derives and nothing writes. The
# loops read a JSON array by index rather than through a pipe, because a while-read pipeline is a
# subshell and a failure inside one would be swallowed.
set -eu

# duration <seconds>: the elapsed form a person reads — "40 s", "4 m", "3 h 12 m", "2 d 4 h".
duration() {
  awk -v s="$1" 'BEGIN {
    if (s < 0) s = 0
    if (s < 60) printf "%d s", s
    else if (s < 3600) printf "%d m", int(s / 60)
    else if (s < 86400) printf "%d h %d m", int(s / 3600), int((s % 3600) / 60)
    else printf "%d d %d h", int(s / 86400), int((s % 86400) / 3600)
  }'
}

# nth <json array> <n>: one element, compactly, so a caller can read its fields.
nth() { printf '%s' "$1" | jq -c --argjson n "$2" '.[$n]'; }

# field <json object> <path> [<default>]: one field, or the default when it is absent. The path is
# a literal at every call site and has to be part of the program; the default is data and goes
# through --arg, so a value carrying a quote cannot reshape the program.
field() { printf '%s' "$1" | jq -r --arg d "${3:-}" "$2 // \$d"; }

# verb_for <class> <milestone> [<carries json>] [<session>] [<project>] [<attempt>]: the baton
# command that resolves a park of that class — REQ-ESC-03's third part, and the same text the Mac
# message ended with.
#
# It is the same function, not a second table: a person who read the message at 3 a.m. and then ran
# `baton status` at 8 must be told the same thing to type, and two tables saying it is how they
# come to disagree. `escalation_verb` is in `lib/escalate.sh` with the rest of the message.
verb_for() {
  vfr_carries=${3:-}
  [ -n "$vfr_carries" ] || vfr_carries='{}'
  escalation_verb "$1" "$2" "$vfr_carries" "$(ruling_target "${5:-}" "${4:-}" "${6:-}")"
}

# one_line <carries json>: the one line a person read — the question when the escalation carries
# one, else its detail, else the rule and the path a rejection carries. Literally one line: a
# question is carried verbatim (REQ-ARTIFACT-03) and may run to several, and §5.3 line 3 is one
# line per park. The whole of it, with the options and the verb, is what the Mac message carries
# (`message_render`); this is the same words cut to the width of a view.
one_line() {
  printf '%s' "$1" | jq -r '
    ( if type != "object" then tostring
      elif has("question") then .question
      elif has("detail") then .detail
      elif has("rule") then "\(.rule) · \(.path // "")"
      else (to_entries | map("\(.key) \(.value | tostring)") | join(", ")) end )
    | split("\n")[0]' 2>/dev/null \
    || printf '%s' "$1"
}

# silent_waits <project> <rows json>: §5.3 line 7 for one project — a blocked_by nothing has
# redispatched since AND whose blocker is in flight or eligible, and a wait_for in the newest
# archived complete handover that names a milestone which is neither done, eligible nor in flight.
# A blocked lane whose blocker is done, held or parked is not a silent wait: it is waiting on a
# person, which the parked line already says. A project whose plan does not parse is skipped here;
# reporting that is the self-check's job (M03).
silent_waits() {
  sw_log=$(log_json) || return 0
  sw_plan=$(plan_of_project "$1" 2>/dev/null) || return 0
  sw_done=$(printf '%s' "$sw_plan" | jq -c '[ .milestones[] | select(.status == "done") | .id ]')
  sw_eligible=$(printf '%s' "$sw_plan" | plan_eligible | jq -Rsc 'split("\n") | map(select(length > 0))')
  sw_flying=$(derive_in_flight "$1" "$2") || { echo "$sw_flying"; return 1; }
  sw_flying=$(printf '%s' "$sw_flying" | jq -c '[ .in_flight[] | .milestone ]')

  # Both selections stay in jq, which is where the rule lives; only the line itself comes out as
  # fields, so the lane and the milestones it waits on are rendered like every other record's.
  sw_blocked=$(printf '%s' "$sw_log" | jq -c --arg p "$1" --argjson el "$sw_eligible" --argjson fly "$sw_flying" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p) ] as $ev
    | [ $ev[] | select(.kind == "consumed" and .reason == "blocked" and .blocked_by != null) | . as $c
        | select(($ev | any(.kind == "dispatch" and .milestone == $c.milestone and .i > $c.i)) | not)
        | select($c.blocked_by as $b | ($el | index($b)) != null or ($fly | index($b)) != null)
        | {project: $c.project, milestone: $c.milestone, blocked_by: $c.blocked_by} ]')
  sw_n=$(printf '%s' "$sw_blocked" | jq length); sw_i=0
  while [ "$sw_i" -lt "$sw_n" ]; do
    sw_b=$(nth "$sw_blocked" "$sw_i"); sw_i=$((sw_i + 1))
    render_row out action 'blocked  %s/%s · waiting on %s\n' \
      "$(render_token out lane "$(field "$sw_b" .project)")" \
      "$(render_token out milestone "$(field "$sw_b" .milestone)")" \
      "$(render_token out milestone "$(field "$sw_b" .blocked_by)")"
  done

  sw_newest=$(derive_consumed "$1" | jq -r '
    [ .consumed[] | select(.outcome == "complete" and .archive_present) ] | last | .archive // empty')
  [ -n "$sw_newest" ] || return 0
  [ -f "$sw_newest" ] || return 0
  sw_distant=$(jq -c --argjson done "$sw_done" --argjson el "$sw_eligible" --argjson fly "$sw_flying" '
    [ .eligible[]? | select(.disposition == "wait")
      | . as $e
      | [ .wait_for[]? as $w | select(($done | index($w)) == null and ($el | index($w)) == null
                                      and ($fly | index($w)) == null) | $w ] as $distant
      | select(($distant | length) > 0)
      | {milestone: $e.milestone, waits_for: ($distant | join(", "))} ]' \
    "$sw_newest")
  sw_n=$(printf '%s' "$sw_distant" | jq length); sw_i=0
  while [ "$sw_i" -lt "$sw_n" ]; do
    sw_d=$(nth "$sw_distant" "$sw_i"); sw_i=$((sw_i + 1))
    render_row out action 'waiting for  %s/%s · waits for %s · not eligible yet\n' \
      "$(render_token out lane "$1")" \
      "$(render_token out milestone "$(field "$sw_d" .milestone)")" \
      "$(render_token out milestone "$(field "$sw_d" .waits_for)")"
  done
}

# status_render <rows json>: §5.3 in order. A section with nothing in it prints nothing, so the
# file is as short as the state is quiet.
status_render() {
  sr_rows=$1
  sr_now=$(now_epoch)

  # 1. The last tick, from the marker, never from the newest event, and the hardware condition on
  # the same line: caffeinate -i does not prevent lid-close sleep and timers stretch by any sleep,
  # so an unattended night needs the lid open or clamshell and Baton cannot lift it (REQ-SETUP-07).
  sr_tick=$(derive_last_tick) || { echo "$sr_tick"; return 1; }
  if [ "$(field "$sr_tick" .present)" = true ]; then
    render_row out record 'last tick %s (%s ago) · unattended needs the lid open or clamshell\n' \
      "$(render_token out timestamp "$(field "$sr_tick" .last_tick)")" \
      "$(duration "$(field "$sr_tick" .age_seconds)")"
  else
    render_row out record 'last tick: no tick yet · unattended needs the lid open or clamshell\n'
  fi

  sr_parked=$(derive_parked "") || { echo "$sr_parked"; return 1; }

  # 2 and 3. Project-scope parks, then parked lanes: <project>/<milestone> · <class> · the one
  # line the person read · the verb that resolves it.
  for sr_scope in project lane; do
    sr_list=$(printf '%s' "$sr_parked" | jq -c --arg s "$sr_scope" '[ .parked[] | select(.scope == $s) ]')
    sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
    while [ "$sr_i" -lt "$sr_n" ]; do
      sr_e=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
      sr_class=$(field "$sr_e" .class '?')
      sr_carries=$(printf '%s' "$sr_e" | jq -c '.carries // {}')
      # `one_line` and `verb_for` stay as they were: both return the words themselves, and the Mac
      # message composes from the same two. The styling is put on here, at the one place that knows
      # these bytes are going to a terminal rather than into a notification.
      sr_verb=$(render_hint out \
        "$(verb_for "$sr_class" "$(field "$sr_e" .milestone '?')" "$sr_carries" "$(field "$sr_e" .session)" "$(field "$sr_e" .project)" "$(field "$sr_e" .attempt)")")
      if [ "$sr_scope" = project ]; then
        # A project-scope park with no project named is Baton's own health — a stale lock holds
        # every project, so the field is absent rather than pointing at one of them.
        render_row out action 'project park  %s · %s · %s · %s\n' \
          "$(render_token out lane "$(field "$sr_e" .project 'all projects')")" "$sr_class" \
          "$(one_line "$sr_carries")" "$sr_verb"
      else
        render_row out action 'parked  %s/%s · %s · %s · %s\n' \
          "$(render_token out lane "$(field "$sr_e" .project '?')")" \
          "$(render_token out milestone "$(field "$sr_e" .milestone '?')")" "$sr_class" \
          "$(one_line "$sr_carries")" "$sr_verb"
      fi
    done
  done

  # 4. Taken-over lanes, with the hand-back. A lane whose only transcript is an orphaned sibling
  # was not scanned and says so.
  # These three read their fields and compose the line in the shell, where the earlier sections
  # already do. jq built the whole string before this layer existed; a line assembled inside jq
  # cannot say which of its parts is a lane and which is a path, so the fields come out and the
  # record goes through the same primitives as every other one.
  sr_over=$(derive_taken_over "" "$sr_rows") || { echo "$sr_over"; return 1; }
  for sr_kind in taken_over orphaned unreadable; do
    sr_list=$(printf '%s' "$sr_over" | jq -c --arg k "$sr_kind" '.[$k]')
    sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
    while [ "$sr_i" -lt "$sr_n" ]; do
      sr_t=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
      sr_m=$(field "$sr_t" .milestone)
      sr_lane="$(render_token out lane "$(field "$sr_t" .project)")/$(render_token out milestone "$sr_m")"
      case "$sr_kind" in
        taken_over)
          render_row out action 'taken over  %s at %s; hand back with %s\n' "$sr_lane" \
            "$(render_token out timestamp "$(field "$sr_t" .first_unmatched_at '?')")" \
            "$(render_hint out "baton answer $sr_m \"continue\"")" ;;
        orphaned)
          render_row out action 'taken over  %s · transcript orphaned at %s · not scanned\n' "$sr_lane" \
            "$(render_token out path "$(field "$sr_t" .path)")" ;;
        *)
          render_row out action 'taken over  %s · transcript %s will not parse · not scanned\n' "$sr_lane" \
            "$(render_token out path "$(field "$sr_t" .path)")" ;;
      esac
    done
  done

  # 5. Waits and holds: the error, the elapsed from since, the next retry read from the last
  # retry; then each hold with its model and cause.
  sr_waits=$(derive_waits "") || { echo "$sr_waits"; return 1; }
  sr_list=$(printf '%s' "$sr_waits" | jq -c .waits)
  sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
  while [ "$sr_i" -lt "$sr_n" ]; do
    sr_w=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
    sr_next=$(field "$sr_w" .next_retry_epoch 0)
    if [ "$sr_next" -le "$sr_now" ]; then sr_when='retry due'
    else sr_when="next retry in $(duration "$((sr_next - sr_now))")"; fi
    render_row out action 'waiting  %s/%s · %s · %s since %s · %s\n' \
      "$(render_token out lane "$(field "$sr_w" .project '?')")" \
      "$(render_token out milestone "$(field "$sr_w" .milestone '?')")" \
      "$(field "$sr_w" .error api-error)" \
      "$(duration "$(field "$sr_w" .elapsed_seconds 0)")" \
      "$(render_token out timestamp "$(field "$sr_w" .since '?')")" "$sr_when"
  done
  sr_holds=$(derive_holds) || { echo "$sr_holds"; return 1; }
  sr_list=$(printf '%s' "$sr_holds" | jq -c .holds)
  sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
  while [ "$sr_i" -lt "$sr_n" ]; do
    sr_h=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
    sr_reading=$(printf '%s' "$sr_h" | jq -r 'if .reading then " · reading \(.reading)" else "" end')
    render_row out action 'hold  %s · %s%s\n' "$(render_token out state "$(field "$sr_h" .model)")" \
      "$(field "$sr_h" .cause)" "$sr_reading"
  done

  # 6. In flight: the lane, the session, the model, the attempt, the elapsed since the latest
  # dispatch-or-resume, and any live notification the row carries.
  sr_flight=$(derive_in_flight "" "$sr_rows") || { echo "$sr_flight"; return 1; }
  sr_list=$(printf '%s' "$sr_flight" | jq -c .in_flight)
  sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
  while [ "$sr_i" -lt "$sr_n" ]; do
    sr_l=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
    sr_since=$(iso_epoch "$(field "$sr_l" .since)") || { echo "$sr_since"; return 1; }
    # The live notifications the tick wrote for this attempt, and the row's own waitingFor, which
    # says what the session is holding open when nothing has been notified about it yet.
    sr_live=''
    for sr_class in stall long-running; do
      sr_spent=$(derive_key_spent "$(field "$sr_l" .project)" "$(field "$sr_l" .milestone)" \
        "$(field "$sr_l" .attempt 0)" "$sr_class") || { echo "$sr_spent"; return 1; }
      [ "$(field "$sr_spent" .spent)" = true ] || continue
      case "$sr_class" in stall) sr_live="$sr_live · stalled" ;; *) sr_live="$sr_live · long-running" ;; esac
    done
    render_row out record 'in flight  %s/%s · %s · %s · attempt %s · %s%s%s\n' \
      "$(render_token out lane "$(field "$sr_l" .project '?')")" \
      "$(render_token out milestone "$(field "$sr_l" .milestone '?')")" \
      "$(render_token out session "$(field "$sr_l" .session '?')")" \
      "$(field "$sr_l" .model '?')" \
      "$(field "$sr_l" .attempt '?')" "$(duration "$((sr_now - sr_since))")" "$sr_live" \
      "$(printf '%s' "$sr_l" | jq -r 'if (.row.waitingFor // "") != "" then " · \(.row.waitingFor)" else "" end')"
  done
  # Only lanes with a live row are printed here. derive_in_flight's other half, no_row, is the
  # crash rule's input and not a state: it holds a session Baton itself stopped on an asking
  # consume and one that ended with a declared stop, and printing those as in flight would show a
  # parked lane twice and call a finished one running. M03 acts on no_row; §5.3 line 6 is this.

  # 7. Silent waits, per registered project.
  for sr_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$sr_pj" ] || continue
    silent_waits "$(basename "$(dirname "$sr_pj")")" "$sr_rows"
  done

  # 8. An open gap, if one was reported and nothing has cleared it.
  sr_gap=$(derive_gap "$sr_rows") || { echo "$sr_gap"; return 1; }
  if [ "$(field "$sr_gap" .report)" = true ]; then
    render_row out action 'gap  Baton was not running for %s, measured against %s\n' \
      "$(duration "$(field "$sr_gap" .gap_seconds 0)")" \
      "$(render_token out timestamp "$(field "$sr_gap" .marker '?')")"
  fi

  # 9. What is waiting in the inbox. The move is the consumption, so a file still here has not
  # been acted on; between ticks that is a handover Baton has not yet read (D-035).
  sr_consumed=$(derive_consumed "") || { echo "$sr_consumed"; return 1; }
  sr_list=$(printf '%s' "$sr_consumed" | jq -c .waiting)
  sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
  while [ "$sr_i" -lt "$sr_n" ]; do
    sr_w=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
    render_row out action 'inbox  %s · %s · not yet consumed\n' \
      "$(render_token out path "$(field "$sr_w" .file)")" \
      "$(field "$sr_w" .outcome unreadable)"
  done

  # 10. Finished sessions the offline rule took offline, with the way back, and the wake session when
  # its last start or resume was refused — the one thing that would leave them out of reach (REQ-LIFE).
  # A running finished session is the ordinary case and prints nothing.
  sr_log=$(log_json) || { echo "$sr_log"; return 1; }
  sr_list=$(lifecycle_finished "$sr_log" "$sr_rows" | jq -c --argjson log "$sr_log" '
    [ .[] | select(has("pid") | not) | . as $f
      | select($log | any(.kind == "offline" and .session == $f.session))
      | {project: $f.project, milestone: $f.milestone} ]')
  sr_n=$(printf '%s' "$sr_list" | jq length); sr_i=0
  while [ "$sr_i" -lt "$sr_n" ]; do
    sr_o=$(nth "$sr_list" "$sr_i"); sr_i=$((sr_i + 1))
    sr_p=$(field "$sr_o" .project); sr_m=$(field "$sr_o" .milestone)
    render_row out action 'offline  %s/%s · message %s, or %s\n' \
      "$(render_token out lane "$sr_p")" "$(render_token out milestone "$sr_m")" \
      "$(render_hint out 'Baton · wake')" "$(render_hint out "baton wake $sr_p/$sr_m")"
  done
  sr_wake=$(printf '%s' "$sr_log" | jq -r '[ .[] | select(.kind == "wake" and .milestone == null) ] | last // empty
    | select(.outcome == "refused") | .note // "refused"')
  [ -z "$sr_wake" ] || render_row out action 'wake session  not running · %s\n' "$sr_wake"
}

# verb_status: the whole view, for the rows read once. Writes nothing.
verb_status() {
  status_render "$(rows_json)"
}
