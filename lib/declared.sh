#!/bin/sh
# lib/declared.sh — the declared stops of REQ-STOP-12: an ending the session chose and named, with a
# reason and a detail it wrote. `unfinished` redispatches and escalates on the second in a row;
# `blocked` waits silently for a blocker that is coming and escalates one that is not; a handover
# `wait` whose target nothing is going to finish notifies once.
#
# The seam against lib/stops.sh is who named the ending (D-070): there, Baton detected it and climbs
# a ladder over it; here, the session declared it. `stops_run` drives both.
set -eu

# declared_open <project>: every lane whose newest ending is a declared stop that has not been acted
# on — an `unfinished` or a `blocked` with no later dispatch for the milestone. `merge-failed` and
# `other` are not here because they are parked at the consume, where the artifact that says what
# went wrong is in hand; `main-broken` parks the project, which is M06's.
declared_open() {
  dop_log=$(log_json) || { echo "$dop_log"; return 1; }
  printf '%s' "$dop_log" | jq -c --arg p "$1" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p) ] as $ev
    | [ $ev[] | select(.kind == "consumed") ] | group_by(.milestone) | map(last)
    | map(select(.reason == "unfinished" or .reason == "blocked"))
    | map(. as $c
          | select(($ev | any(.kind == "dispatch" and .milestone == $c.milestone and .i > $c.i)) | not)
          | {at, project, milestone, session, attempt, reason, blocked_by, archive}
          | with_entries(select(.value != null)))'
}

# consecutive_run <project> <milestone> <kind>: how many of one declared ending the milestone has
# produced in a row, newest first, with the archived files that carry what each said.
#
#   unfinished       consecutive session-written endings whose reason is `unfinished`
#   invalid_request  api-error consumes with that error since the newest session-written ending
#
# Both bound a redispatch that would otherwise repeat nightly. A milestone that does not converge is
# a plan edit and plan edits are a person's; a context that overflows twice will overflow again, and
# the fresh context the redispatch bought is the evidence that it was not the problem.
consecutive_run() {
  crn_log=$(log_json) || { echo "$crn_log"; return 1; }
  if [ "$3" = unfinished ]; then
    printf '%s' "$crn_log" | jq -c --arg p "$1" --arg m "$2" '
      [ .[] | select(.kind == "consumed" and .project == $p and .milestone == $m
                     and .written_by == "session") ]
      | reverse | . as $s
      | ([ range(0; ($s | length)) | select($s[.].reason != "unfinished") ] | first) as $stop
      | ($stop // ($s | length)) as $n
      | {count: $n, archives: [ $s[0:$n][] | .archive // empty ]}'
  else
    printf '%s' "$crn_log" | jq -c --arg p "$1" --arg m "$2" '
      [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
      | ([ $ev[] | select(.kind == "consumed" and .written_by == "session") ] | last) as $reset
      | [ $ev[] | select(.i > ($reset.i // -1))
          | select(.kind == "consumed" and .reason == "api-error" and .error == "invalid_request") ]
      # Newest first, as the unfinished branch returns them: splits_carries reads element 0 as the
      # newest and says so to the person, so a branch returning log order would print each ending
      # under the label belonging to the other.
      | {count: length, archives: ([ .[] | .archive // empty ] | reverse)}'
  fi
}

# splits_carries <run json> <milestone> <what>: the carries of an escalation that hands over two
# endings at once, each with what its own artifact said. Both are quoted because the person is being
# asked to choose between them — the split a session proposes is a plan edit, and a plan edit needs
# to see what was proposed, not that something was.
splits_carries() {
  scr_one=$(artifact_detail "$(printf '%s' "$1" | jq -r '.archives[0] // ""')")
  scr_two=$(artifact_detail "$(printf '%s' "$1" | jq -r '.archives[1] // ""')")
  [ -n "$scr_one" ] || scr_one="the newest ending left no detail"
  [ -n "$scr_two" ] || scr_two="the previous ending left no detail"
  scr_detail="$2 ended $3 twice in a row; the newest says: $scr_one · the previous says: $scr_two"
  jq -nc --arg a "$scr_one" --arg b "$scr_two" --arg d "$scr_detail" \
    '{newest: $a, previous: $b, detail: $d}'
}

# blocker_state <plan json> <blocker> <in-flight milestones json>: what the plan says about the
# milestone a blocked lane names. `done` releases it, `in flight` and `eligible` mean it releases
# itself, and anything else means nothing is coming to unblock it.
blocker_state() {
  if ! bst_row=$(printf '%s' "$1" | plan_row "$2" 2>/dev/null); then echo absent; return 0; fi
  if [ "$(printf '%s' "$bst_row" | jq -r '.status // ""')" = done ]; then echo done; return 0; fi
  if printf '%s' "$3" | jq -e --arg m "$2" 'index($m) != null' > /dev/null; then echo "in flight"; return 0; fi
  if printf '%s' "$1" | plan_eligible | grep -Fqx "$2"; then echo eligible; return 0; fi
  echo waiting
}

# declared_step <project> <declared json> <plan json> <rows json> <in-flight milestones json>:
# REQ-STOP-12 for the two reasons this milestone owns.
declared_step() {
  dst_m=$(printf '%s' "$2" | jq -r .milestone)
  dst_s=$(printf '%s' "$2" | jq -r '.session // ""')
  dst_a=$(printf '%s' "$2" | jq -r '.attempt // ""')
  case "$(printf '%s' "$2" | jq -r .reason)" in
    unfinished)
      dst_run=$(consecutive_run "$1" "$dst_m" unfinished) || { render_failure err "$dst_run"; return 1; }
      if [ "$(printf '%s' "$dst_run" | jq -r .count)" -ge 2 ]; then
        # A split is a plan edit and the edit is what ends the park, so the next attempt starts
        # from the instructions as they now read; a ruling was delivered to the session, which is
        # working. The line says which readings changed and never who changed them (D-134): what
        # Baton has is two digests that differ, which is a fact about the brief and the work plan
        # and not about anybody's hands. The `instructions` policy this park unparks under hashes
        # exactly those two, so they are what the line names — the same register `lib/stops.sh`
        # already uses for the ladder's own redispatch.
        case "$(person_acted "$1" "$dst_m" unfinished-twice)" in
          edit)
            redispatch "$1" "$dst_m" "$3" "$4" "the brief or the work plan changed after two unfinished endings, so attempt $(( ${dst_a:-0} + 1 )) starts from it"
            return 0 ;;
          ruling) return 0 ;;
        esac
        escalate "$1" "$dst_m" "$dst_s" "$dst_a" unfinished-twice lane \
          "$(splits_carries "$dst_run" "$dst_m" unfinished)"
        render_row out action 'unfinished %s/%s · twice in a row · the lane is parked with both splits\n' "$(render_token out lane "$1")" "$(render_token out milestone "$dst_m")"
      else
        # Not a failure ending: the session came back and said what it had done, which is the
        # reset point the ladder reads. A redispatch here is the plan working, not a retry.
        redispatch "$1" "$dst_m" "$3" "$4" "the session stopped unfinished, so attempt $(( ${dst_a:-0} + 1 )) resumes from the brief"
      fi
      ;;
    blocked)
      dst_by=$(printf '%s' "$2" | jq -r '.blocked_by // ""')
      dst_state=$(blocker_state "$3" "$dst_by" "$5")
      case "$dst_state" in
        done)
          redispatch "$1" "$dst_m" "$3" "$4" "$dst_by reads done, so the blocker is gone"
          ;;
        "in flight"|eligible)
          # Silent, because the wait resolves itself: one message so that `status` and the person
          # both know what the lane is waiting for, and nothing else until it moves.
          # One value for the check and the write. The check needs a number and the event carries
          # what it is given, so reading the attempt two ways would let a lane with no attempt on
          # record spend a key the event never matches, and notify on every tick.
          dst_key_a=${dst_a:-0}
          dst_spent=$(derive_key_spent "$1" "$dst_m" "$dst_key_a" blocked_by "$dst_by") \
            || { render_failure err "$dst_spent"; return 1; }
          [ "$(printf '%s' "$dst_spent" | jq -r .spent)" = false ] || return 0
          dst_detail="blocked by $dst_by, which is $dst_state; Baton redispatches this lane when the plan reads it done"
          notification_write "$1" "$dst_m" "$dst_s" "$dst_key_a" blocked_by "$dst_by" \
            "$(jq -nc --arg b "$dst_by" --arg s "$dst_state" --arg d "$dst_detail" \
               '{blocked_by: $b, blocker_state: $s, detail: $d}')"
          render_row out record 'blocked   %s/%s · waiting on %s (%s)\n' "$(render_token out lane "$1")" "$(render_token out milestone "$dst_m")" "$(render_token out milestone "$dst_by")" "$dst_state"
          ;;
        *)
          # Nothing is coming to unblock it, so the wait would never end. That is a person's to
          # settle — the plan is theirs — and a lane parked on a named milestone is answerable. A
          # ruling ("go on without it") is the person settling it, and the session is working on
          # it; an edit is re-judged by the three branches above, which is why only the ruling
          # stands this down.
          [ "$(person_acted "$1" "$dst_m" blocked)" != ruling ] || return 0
          dst_detail=$(artifact_detail "$(printf '%s' "$2" | jq -r '.archive // ""')")
          dst_says="blocked by $dst_by, which the plan neither holds nor makes eligible nor shows in flight"
          [ "$dst_state" != waiting ] || dst_says="blocked by $dst_by, which is in the plan but is neither done, eligible nor in flight, so nothing is coming to unblock it"
          [ -z "$dst_detail" ] || dst_says="$dst_says · the session said: $dst_detail"
          escalate "$1" "$dst_m" "$dst_s" "$dst_a" blocked lane \
            "$(jq -nc --arg b "$dst_by" --arg s "$dst_state" --arg d "$dst_says" \
               '{blocked_by: $b, blocker_state: $s, detail: $d}')"
          render_row out action 'blocked   %s/%s · nothing is coming to unblock %s · the lane is parked\n' "$(render_token out lane "$1")" "$(render_token out milestone "$dst_m")" "$(render_token out milestone "$dst_by")"
          ;;
      esac
      ;;
  esac
}

# distant_wait_for_check <project> <plan json> <in-flight milestones json>: a handover `wait` whose
# target is neither done, eligible nor in flight notifies once, the same way a distant `blocked_by`
# does, so that a lane is not left waiting for days on nobody's decision.
#
# The key is the handover file and the named milestone, not the attempt: the milestone that waits
# has not been dispatched, so it has no attempt, and the next handover to name it is new
# information whatever happened in between.
distant_wait_for_check() {
  dwf_doc=$(derive_consumed "$1") || { render_failure err "$dwf_doc"; return 1; }
  dwf_file=$(printf '%s' "$dwf_doc" | jq -r \
    '[ .consumed[] | select(.outcome == "complete" and .archive_present) ] | last | .archive // empty')
  [ -n "$dwf_file" ] && [ -f "$dwf_file" ] || return 0
  dwf_done=$(printf '%s' "$2" | jq -c '[ .milestones[] | select(.status == "done") | .id ]')
  dwf_el=$(printf '%s' "$2" | plan_eligible | jq -Rsc 'split("\n") | map(select(length > 0))')
  dwf_log=$(log_json) || { render_failure err "$dwf_log"; return 1; }
  dwf_key=$(basename "$dwf_file")
  jq -r --argjson done "$dwf_done" --argjson el "$dwf_el" --argjson fly "$3" '
    .eligible[]? | select(.disposition == "wait") | . as $e
    | .wait_for[]? as $w
    | select(($done | index($w)) == null and ($el | index($w)) == null and ($fly | index($w)) == null)
    | "\($e.milestone) \($w)"' "$dwf_file" \
  | while read -r dwf_m dwf_w; do
      [ -n "$dwf_m" ] || continue
      # Scoped by project like every other key: two projects can each archive a handover with the
      # same basename naming the same milestone, and the second must not be silenced by the first.
      if printf '%s' "$dwf_log" | jq -e --arg k "$dwf_key|$dwf_w" --arg m "$dwf_m" --arg p "$1" \
           'any(.[]; .kind == "notification" and .class == "distant_wait_for"
                     and .project == $p and .milestone == $m and .key == $k)' > /dev/null; then
        continue
      fi
      dwf_detail="waits for $dwf_w, which is neither done, eligible nor in flight, so this lane is not moving on its own"
      notification_write "$1" "$dwf_m" "" "" distant_wait_for "$dwf_key|$dwf_w" \
        "$(jq -nc --arg w "$dwf_w" --arg h "$dwf_key" --arg d "$dwf_detail" \
           '{wait_for: $w, handover: $h, detail: $d}')"
      render_row out action 'waiting   %s/%s · waits for %s, which nothing is going to finish\n' "$(render_token out lane "$1")" "$(render_token out milestone "$dwf_m")" "$(render_token out milestone "$dwf_w")"
    done
}

# main_broken_cascade <project> <ruling> <rows json> <answered park at> <its milestone>: the rest
# of a broken `main`, once a person has answered the first park (REQ-STOP-12).
#
# When several lanes merge onto a broken tree, each meets the same standing check and each writes
# `main-broken`, so one fix leaves several parks. Their merges landed; what each still owes is step
# (c) onward, which is exactly what the ruling tells it to finish. So the ruling a person gave one
# of them is delivered to every other `main-broken` park of the project, oldest first, each through
# the same stop, settle and flagless resume, and each closed only by its own delivered resume. One
# that is refused keeps its park, and the project stays held until that one is answered again.
#
# `answer_deliver` is called with its cascade turned off, so a delivery here cannot start another.
main_broken_cascade() {
  mbc_parked=$(derive_parked "$1") || { render_failure err "$mbc_parked"; return 1; }
  mbc_list=$(printf '%s' "$mbc_parked" | jq -c --arg at "$4" --arg m "$5" \
    '[ .parked[] | select(.scope == "project" and .class == "main-broken" and (.at != $at or .milestone != $m)) ]')
  mbc_status=0
  mbc_n=$(printf '%s' "$mbc_list" | jq length); mbc_i=0
  while [ "$mbc_i" -lt "$mbc_n" ]; do
    mbc_e=$(printf '%s' "$mbc_list" | jq -c ".[$mbc_i]"); mbc_i=$((mbc_i + 1))
    answer_deliver "$mbc_e" "$2" "$3" no || mbc_status=1
  done
  return "$mbc_status"
}
