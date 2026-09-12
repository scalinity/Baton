#!/bin/sh
# lib/answer.sh — the two verbs a person runs, and the only two things a person types into Baton.
#
# `baton answer` delivers a ruling into a parked lane and hands back a lane a person took over;
# `baton allow` widens a project's allowlist with a rule the person wrote. Both resolve a milestone
# name across every project, act on exactly one match, and refuse ambiguity by printing
# `<project>/<milestone>` candidates — the same rule the log's counting key already forces
# (REQ-ESC-06), because every project has an M01 and 3 a.m. is when it matters.
#
# Both are hand-run from a terminal, which is why everything they read from the CLI goes through
# `cli_plain` (D-050): a verb run from inside a Claude Code session inherits `FORCE_COLOR`, and the
# id in a coloured line does not match the id in a plain one. `resume_session` already reads that
# way and is the one path to a running session here.
#
# The seam against `lib/escalate.sh` is direction: that file is what Baton writes when it needs a
# person, this is what the person runs to reach the session. Neither decides anything.
set -eu

# answer_resolve <milestone> [<project>]: derivation 13, narrowed by the long form when it was
# given. Prints {milestone, count, candidates}; the caller decides what a count means, because
# `answer` and `allow` refuse for different reasons and say different things.
answer_resolve() {
  anr_c=$(derive_answer_candidates "$1") || { echo "$anr_c"; return 1; }
  [ -z "${2:-}" ] || anr_c=$(printf '%s' "$anr_c" | jq -c --arg p "$2" \
    '.candidates |= map(select(.project == $p)) | .count = (.candidates | length)')
  printf '%s\n' "$anr_c"
}

# answer_candidates_print <candidates json>: the refusal a person reads when a milestone name is
# parked in more than one project. The long form is printed as a command rather than as a list,
# because the next thing that happens is one of these lines being run.
answer_candidates_print() {
  printf '%s' "$1" | jq -r '.[] | "  baton answer \(.project)/\(.milestone) · \(.class // "?") · "
                                  + ((.carries.question // .carries.detail // "") | split("\n")[0])'
}

# answer_options <project> <milestone> <session> <carries json>: the options an `asking` artifact
# offered, **read from the archive**. The escalation's `carries` holds a cut copy for the message;
# this is the list the number is expanded against, so a long option is answered in full and a
# truncated message costs nothing. The carries is the fallback for an archive a person has moved.
answer_options() {
  ano_log=$(log_json) || { echo "$ano_log"; return 1; }
  ano_arch=$(printf '%s' "$ano_log" | jq -r --arg p "$1" --arg m "$2" --arg s "$3" '
    [ .[] | select(.kind == "consumed" and .project == $p and .milestone == $m
                   and .session == $s and .outcome == "asking") ] | last | .archive // empty')
  if [ -n "$ano_arch" ] && [ -f "$ano_arch" ]; then
    jq -c '[ .options[]? | tostring ]' "$ano_arch" 2>/dev/null && return 0
  fi
  printf '%s' "$4" | jq -c '[ .options[]? | tostring ]'
}

# answer_deliver <park json> <ruling or option number> <rows json>: the ruling's return.
#
# An option number expands to that option's text verbatim before delivery, so the session receives
# a ruling and never a digit — it may have compacted since it asked, and a digit means nothing to a
# context that no longer holds the list.
#
# The resolution is written before the resume, which is the order the log's own example carries and
# the order a reader needs: the resolution names the escalation it closes, and the resume that
# follows is what it caused. A resume the CLI refuses is a failure ending the ladder counts, so a
# ruling that could not be delivered is not silently lost — it is loud on stderr and the lane
# climbs on the next tick.
answer_deliver() {
  and_p=$(printf '%s' "$1" | jq -r '.project // ""')
  and_m=$(printf '%s' "$1" | jq -r '.milestone // ""')
  and_s=$(printf '%s' "$1" | jq -r '.session // ""')
  and_a=$(printf '%s' "$1" | jq -r '.attempt // ""')
  and_at=$(printf '%s' "$1" | jq -r .at)
  and_class=$(printf '%s' "$1" | jq -r '.class // ""')
  and_carries=$(printf '%s' "$1" | jq -c '.carries // {}')

  if [ -z "$and_s" ]; then
    echo "baton: the $and_class park on $and_p/$and_m names no session, so there is nothing to resume; the way out is an edit" >&2
    return 1
  fi

  and_text=$2
  case "$2" in
    ''|*[!0-9]*) ;;
    *)
      and_opts=$(answer_options "$and_p" "$and_m" "$and_s" "$and_carries") \
        || { echo "baton: $and_opts" >&2; return 1; }
      and_n=$(printf '%s' "$and_opts" | jq length)
      if [ "$and_n" -eq 0 ]; then
        echo "baton: $and_p/$and_m offered no options, so $2 is not a choice; give the ruling as text" >&2
        return 1
      fi
      if [ "$2" -lt 1 ] || [ "$2" -gt "$and_n" ]; then
        echo "baton: $and_p/$and_m offered $and_n options and $2 is not one of them:" >&2
        printf '%s' "$and_opts" | jq -r 'to_entries[] | "  \(.key + 1) \(.value)"' >&2
        return 1
      fi
      and_text=$(printf '%s' "$and_opts" | jq -r --argjson n "$2" '.[$n - 1]')
      ;;
  esac

  # The question is quoted in the label because the session may have compacted since it asked, and
  # a bare ruling can land on a question the model no longer holds. A park that carries no question
  # — a merge that failed, a ladder that ended — is quoted by what it does carry, which is the
  # sentence the person read when they decided.
  #
  # A `question` park is the exception, because no payload carries its words: the row says only that
  # the session is waiting for input. Quoting the park's detail there would hand the session Baton's
  # own sentence about a row as though it were what the session asked — measured live. The session
  # can usually see its own question: the second probe's call was on disk and came back on the
  # resume as `[Request interrupted by user for tool use]`. The first probe's was not in its
  # transcript when the stop landed, so the label points at the call rather than relying on it.
  case "$and_class" in
    question) and_q="the question you put with AskUserQuestion in this session, whose words no payload carries to Baton" ;;
    *) and_q=$(printf '%s' "$and_carries" | jq -r '.question // .detail // "" | split("\n") | join(" ")') ;;
  esac
  [ -n "$and_q" ] || and_q="(the park carried no words of its own)"
  # Both numbers from one reading, so the label and the event it is logged beside cannot disagree.
  # The attempt is the derived count and not the park's stamp: a park written for a session Baton
  # never dispatched carries none, and the count is the authority in any case.
  and_n=$(resume_count_next "$and_p" "$and_m" "$and_a") || { echo "$and_n" >&2; return 1; }
  and_label=$(template_ruling "$and_m" "${and_n% *}" "${and_n#* }" "$and_at" "$and_q" "$and_text")

  resolve "$and_p" "$and_m" "$and_s" "$and_a" "$and_at" ruling || return 1
  and_out=$(resume_session "$and_p" "$and_m" "$and_a" "$and_s" \
    "$(job_of_session "$3" "$and_s")" ruling "$and_class" "$and_label") || { echo "$and_out" >&2; return 1; }
  printf 'ruling    %s/%s · %s · %s · %s\n' "$and_p" "$and_m" "$and_s" "$and_class" \
    "$(printf '%s' "$and_out" | jq -r .outcome)"
}

# answer_handback <milestone> [<project>] <rows json>: the way a taken-over lane comes back.
#
# A takeover is not a park (D-015): Baton stood off because a person was already acting, so there
# is no escalation to resolve and no resolution event to write — only the resume. The release is
# the takeover rule's own: the lane is taken over exactly while the newest typed record is one
# Baton did not send, so delivering any prompt makes Baton's the newest and the next tick finds the
# lane clear. Nothing marks it, and nothing needs to.
#
# The text is the continue template rather than the ruling label, because there is no question and
# no escalation time to quote — and because what the session needs to hear is exactly what that
# template says: carry on from where the last turn ended, and the handover is still owed.
answer_handback() {
  ahb_over=$(derive_taken_over "${2:-}" "$3") || { echo "$ahb_over" >&2; return 1; }
  ahb_list=$(printf '%s' "$ahb_over" | jq -c --arg m "$1" '[ .taken_over[] | select(.milestone == $m) ]')
  printf '%s\n' "$ahb_list"
}

# verb_answer <milestone | project/milestone> <ruling | n>: REQ-VERB-03.
verb_answer() {
  case "$1" in
    */*) vba_p=${1%%/*}; vba_m=${1#*/} ;;
    *)   vba_p=''; vba_m=$1 ;;
  esac
  vba_rows=$(rows_json)
  vba_c=$(answer_resolve "$vba_m" "$vba_p") || { echo "baton: $vba_c" >&2; return 1; }
  vba_n=$(printf '%s' "$vba_c" | jq -r .count)

  if [ "$vba_n" -gt 1 ]; then
    echo "baton: $vba_m is parked in $vba_n projects; name one:" >&2
    answer_candidates_print "$(printf '%s' "$vba_c" | jq -c .candidates)" >&2
    return 1
  fi

  if [ "$vba_n" -eq 1 ]; then
    answer_deliver "$(printf '%s' "$vba_c" | jq -c '.candidates[0]')" "$2" "$vba_rows"
    return
  fi

  # Nothing is parked. The one other thing `answer` does is hand back a lane a person took over,
  # and the hand-back is the word "continue" exactly — anything else typed at a lane whose person
  # is still in it would be Baton prompting over them, which it never does (INV-04).
  vba_over=$(answer_handback "$vba_m" "$vba_p" "$vba_rows") || return 1
  vba_on=$(printf '%s' "$vba_over" | jq length)
  if [ "$vba_on" -gt 1 ]; then
    echo "baton: $vba_m is taken over in $vba_on projects; name one:" >&2
    printf '%s' "$vba_over" | jq -r '.[] | "  baton answer \(.project)/\(.milestone) \"continue\""' >&2
    return 1
  fi
  if [ "$vba_on" -eq 1 ]; then
    if [ "$2" != continue ]; then
      echo "baton: $vba_m is taken over, not parked; nothing is waiting on a ruling. Hand it back with baton answer $vba_m \"continue\" and it is Baton's again" >&2
      return 1
    fi
    vba_l=$(printf '%s' "$vba_over" | jq -c '.[0]')
    vba_ls=$(printf '%s' "$vba_l" | jq -r .session)
    vba_out=$(resume_session "$(printf '%s' "$vba_l" | jq -r .project)" "$vba_m" \
      "$(printf '%s' "$vba_l" | jq -r '.attempt // ""')" "$vba_ls" \
      "$(job_of_session "$vba_rows" "$vba_ls")" continue 'handed back') \
      || { echo "$vba_out" >&2; return 1; }
    printf 'handed back  %s/%s · %s · %s\n' "$(printf '%s' "$vba_l" | jq -r .project)" "$vba_m" \
      "$vba_ls" "$(printf '%s' "$vba_out" | jq -r .outcome)"
    return 0
  fi

  # The target as the person typed it, long form and all: they named a lane, and being told that
  # nothing is waiting on the bare milestone would read as though the project half was ignored.
  echo "baton: nothing is waiting on $1" >&2
  return 1
}

# allow_lane <milestone> [<project>]: the lane a rule is earned by, from the log's dispatches —
# the newest per project, so the settings file the rule is written into is the one the session
# actually carries. A milestone Baton has never dispatched has no settings file and no lane, and
# the refusal says so: a person who wants to widen ahead of a dispatch edits `permissions.json`,
# which REQ-PERM-02 already names as one of its two writers.
allow_lane() {
  alr_log=$(log_json) || { echo "$alr_log"; return 1; }
  printf '%s' "$alr_log" | jq -c --arg m "$1" --arg p "${2:-}" '
    [ .[] | select(.kind == "dispatch" and .milestone == $m and ($p == "" or .project == $p)) ]
    | group_by(.project) | map(last | {project, milestone, attempt, session})
    | {milestone: $m, count: length, candidates: .}'
}

# allow_write <project> <milestone> <rule>: REQ-ESC-09. The rule as given, into the project's
# allowlist and into the dispatched settings file in place, plus the `widening` event that is the
# allowlist's provenance in `status` and in `baton plan`.
#
# **Exactly the rule given, and never one Baton composed.** A head-of-command heuristic is a fine
# suggestion and a bad writer: a rule that matches nothing looks identical to a rule not yet
# needed, and a rule that matches too much is invisible until it approves something it should not
# have. Neither failure is visible to a relay, and the half of this verb that read
# `permission_suggestions[]` off a permission escalation has had no mechanism since the mode became
# `bypassPermissions` (D-016) — so the person types the rule, always.
#
# **No `ask` rule.** What a `permissions.ask` rule does under `bypassPermissions` is unknown from
# the binary's strings and from the documentation (live item 42, unrun and owned here), and the
# dispatched settings file carries none by construction (INV-09). Baton does not write a rule whose
# effect it cannot state, so the ask forms are refused here rather than written and found out about
# on a night nobody was watching.
#
# The settings file is edited in place and never recomposed. A flagless resume restores the
# `--settings` path the dispatch gave (D-017), so the rule is in force for the resumed session; and
# in place means a person's own edit to that file survives a widening.
allow_write() {
  alw_rule=$3
  case "$alw_rule" in
    '') echo "baton: the rule is empty" >&2; return 1 ;;
    ask|ask:*|'ask '*|Ask|Ask:*|'Ask '*)
      echo "baton: refusing to write an ask rule. What a permissions.ask rule does under bypassPermissions is unknown (live item 42, unrun), and Baton does not write a rule whose effect it cannot state; the dispatched settings file carries no ask rules at all (INV-09)" >&2
      return 1 ;;
  esac
  # The newline is a literal in the pattern and never `$(printf '\n')`: command substitution strips
  # trailing newlines, so that form is the empty string and the pattern `**` matches every rule.
  alw_nl='
'
  case "$alw_rule" in
    *"$alw_nl"*) echo "baton: a rule is one line; this one has more than one" >&2; return 1 ;;
  esac
  if printf '%s' "$alw_rule" | jq -e 'type == "object"' > /dev/null 2>&1; then
    echo "baton: a rule is a string such as 'Bash(xcodebuild:*)', not a JSON object" >&2
    return 1
  fi

  alw_perm=$BATON_HOME/projects/$1/permissions.json
  if [ ! -f "$alw_perm" ]; then
    echo "baton: $alw_perm does not exist, so project $1 has no allowlist to widen" >&2
    return 1
  fi
  alw_add='if ((.permissions.allow // []) | index($r)) == null
           then .permissions.allow = ((.permissions.allow // []) + [$r]) else . end'
  alw_wrote=no
  alw_new=$(jq --arg r "$alw_rule" "$alw_add" "$alw_perm") || { echo "baton: $alw_perm does not parse" >&2; return 1; }
  if [ "$alw_new" != "$(jq . "$alw_perm")" ]; then
    printf '%s\n' "$alw_new" > "$alw_perm.tmp"
    mv "$alw_perm.tmp" "$alw_perm"
    alw_wrote=yes
    printf 'allowed   %s · %s · %s\n' "$1" "$alw_rule" "$alw_perm"
  else
    printf 'already   %s · %s is in %s\n' "$1" "$alw_rule" "$alw_perm"
  fi

  alw_set=$BATON_HOME/settings/$1-$2.json
  if [ -f "$alw_set" ]; then
    alw_new=$(jq --arg r "$alw_rule" "$alw_add" "$alw_set") \
      || { echo "baton: $alw_set does not parse" >&2; return 1; }
    if [ "$alw_new" != "$(jq . "$alw_set")" ]; then
      printf '%s\n' "$alw_new" > "$alw_set.tmp"
      mv "$alw_set.tmp" "$alw_set"
      alw_wrote=yes
      printf 'allowed   %s · %s · %s\n' "$2" "$alw_rule" "$alw_set"
    else
      printf 'already   %s · %s is in %s\n' "$2" "$alw_rule" "$alw_set"
    fi
  else
    # Said rather than swallowed: the rule is in the project's allowlist and will reach the next
    # dispatch, but the session running now is reading a file that no longer exists, so a resume
    # would not pick the rule up either.
    echo "baton: $alw_set does not exist, so only the project's allowlist was widened" >&2
  fi

  # The event records a widening and not an attempt at one. A rule both files already carry widens
  # nothing, and a second `widening` for it would put a line in `baton plan`'s provenance saying the
  # allowlist grew on a day it did not.
  [ "$alw_wrote" = yes ] || return 0
  log_event widening "$1" "$2" "" "" \
    "$(jq -nc --arg r "$alw_rule" --arg f "$alw_perm" '{rule: $r, permissions_file: $f}')"
}

# verb_allow <milestone | project/milestone> <rule> [--resume]: REQ-VERB-07.
verb_allow() {
  case "$1" in
    */*) vbl_p=${1%%/*}; vbl_m=${1#*/} ;;
    *)   vbl_p=''; vbl_m=$1 ;;
  esac
  vbl_lane=$(allow_lane "$vbl_m" "$vbl_p") || { echo "baton: $vbl_lane" >&2; return 1; }
  vbl_n=$(printf '%s' "$vbl_lane" | jq -r .count)
  if [ "$vbl_n" -eq 0 ]; then
    echo "baton: Baton has dispatched no $vbl_m, so there is no allowlist it has earned; widen a project's permissions.json by hand instead" >&2
    return 1
  fi
  if [ "$vbl_n" -gt 1 ]; then
    echo "baton: $vbl_m has run in $vbl_n projects; name one:" >&2
    printf '%s' "$vbl_lane" | jq -r --arg r "$2" '.candidates[] | "  baton allow \(.project)/\(.milestone) \($r | @sh)"' >&2
    return 1
  fi
  vbl_l=$(printf '%s' "$vbl_lane" | jq -c '.candidates[0]')
  vbl_pj=$(printf '%s' "$vbl_l" | jq -r .project)
  allow_write "$vbl_pj" "$vbl_m" "$2" || return 1

  [ "${3:-}" = --resume ] || return 0
  # The re-issued command passes because the resumed session reads the widened settings file, and
  # the call the refusal dropped is repeated by the continue template's own interrupted-tool
  # sentence. One path serves a live prompt and a lost one alike.
  vbl_a=$(printf '%s' "$vbl_l" | jq -r '.attempt // ""')
  vbl_s=$(current_session "$vbl_pj" "$vbl_m" "$vbl_a") || { echo "baton: $vbl_s" >&2; return 1; }
  if [ -z "$vbl_s" ]; then
    echo "baton: no session carries $vbl_pj/$vbl_m attempt $vbl_a, so there is nothing to resume" >&2
    return 1
  fi
  vbl_out=$(resume_session "$vbl_pj" "$vbl_m" "$vbl_a" "$vbl_s" \
    "$(job_of_session "$(rows_json)" "$vbl_s")" continue 'the allowlist was widened') \
    || { echo "$vbl_out" >&2; return 1; }
  printf 'resumed   %s/%s · %s · %s\n' "$vbl_pj" "$vbl_m" "$vbl_s" \
    "$(printf '%s' "$vbl_out" | jq -r .outcome)"
}
