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

# answer_resolve <milestone> [<project>] [<park at>]: derivation 13, narrowed by the long form when
# it was given and by the park's own `at` when that was. Prints {milestone, count, candidates}; the
# caller decides what a count means, because `answer` and `allow` refuse for different reasons and
# say different things.
#
# The `at` is the third narrowing and not a different kind of thing: derivation 2 keys a park on it,
# `resolve` names the escalation it closes by it, and every park this function returns carries it
# already. What it adds is the one case the other two narrowings cannot reach — several parks on one
# lane, where naming the project again names the same lane (limitation 33).
answer_resolve() {
  anr_c=$(derive_answer_candidates "$1") || { echo "$anr_c"; return 1; }
  [ -z "${2:-}" ] || anr_c=$(printf '%s' "$anr_c" | jq -c --arg p "$2" \
    '.candidates |= map(select(.project == $p)) | .count = (.candidates | length)')
  [ -z "${3:-}" ] || anr_c=$(printf '%s' "$anr_c" | jq -c --arg a "$3" \
    '.candidates |= map(select(.at == $a)) | .count = (.candidates | length)')
  printf '%s\n' "$anr_c"
}

# answer_candidates_print <candidates json> <out|err> [<qualify: at>]: the refusal a person reads
# when more than one park answers to the name they typed. The long form is printed as a command
# rather than as a list, because the next thing that happens is one of these lines being run.
#
# Its stream is an argument because both callers print it on stderr, beneath their own refusal, and
# a helper that guessed would guess for the stream the refusal did not use. The qualifier is an
# argument for the same reason and not a rule read off the candidates: the two refusals ask different
# questions. "Parked in three projects" is answered by naming a project, and appending a timestamp to
# each line would be three ways of saying the same thing; "this lane carries two parks" is answered
# only by naming a park, and that is what the `at` is.
answer_candidates_print() {
  acp_stream=$2; acp_q=${3:-}
  acp_n=$(printf '%s' "$1" | jq length); acp_i=0
  while [ "$acp_i" -lt "$acp_n" ]; do
    acp_c=$(printf '%s' "$1" | jq -c --argjson i "$acp_i" '.[$i]'); acp_i=$((acp_i + 1))
    acp_target=$(printf '%s' "$acp_c" | jq -r '.project + "/" + .milestone')
    [ "$acp_q" != at ] || acp_target=$acp_target@$(printf '%s' "$acp_c" | jq -r .at)
    render_row "$acp_stream" plain '  %s · %s · %s\n' \
      "$(render_hint "$acp_stream" "baton answer $acp_target")" \
      "$(printf '%s' "$acp_c" | jq -r '.class // "?"')" \
      "$(printf '%s' "$acp_c" | jq -r '(.carries.question // .carries.detail // "") | split("\n")[0]')"
  done
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
    jq -c '(.options // []) | (if type == "array" then . else [.] end) | map(tostring)' "$ano_arch" 2>/dev/null && return 0
  fi
  printf '%s' "$4" | jq -c '(.options // []) | (if type == "array" then . else [.] end) | map(tostring)'
}

# answer_deliver <park json> <ruling or option number> <rows json> [<cascade: yes|no>]: the ruling's
# return. A delivered `main-broken` ruling is then carried to every other `main-broken` park of the
# project (`main_broken_cascade`), unless the call is that cascade's own.
#
# An option number expands to that option's text verbatim before delivery, so the session receives
# a ruling and never a digit — it may have compacted since it asked, and a digit means nothing to a
# context that no longer holds the list.
#
# A sessionless dispatch-failed park accepts a hand-back ruling without a resume. For a session,
# **the resolution follows a delivered resume and never precedes one.** A park is closed by a ruling
# that reached the session, and only the resume's outcome can say it did. Closed first, a resume the
# CLI refused would leave the lane unparked with the ruling undelivered: `baton answer` would then
# say nothing is waiting, so the person could not send it again, and the next tick would resume the
# session with the continue template, which does not carry the ruling — the session asks again and
# the night is lost. So a refused resume leaves the park standing and says so, and the same command
# works once the resume can go through. A fork closes it, because the copy received the ruling.
answer_deliver() {
  and_p=$(printf '%s' "$1" | jq -r '.project // ""')
  and_m=$(printf '%s' "$1" | jq -r '.milestone // ""')
  and_s=$(printf '%s' "$1" | jq -r '.session // ""')
  and_a=$(printf '%s' "$1" | jq -r '.attempt // ""')
  and_at=$(printf '%s' "$1" | jq -r .at)
  and_class=$(printf '%s' "$1" | jq -r '.class // ""')
  and_carries=$(printf '%s' "$1" | jq -c '.carries // {}')

  # The same test the message's verb was chosen by, so the command a person was told to type is never
  # one this refuses, and a session Baton did not dispatch is never resumed by it.
  if [ -z "$(ruling_target "$and_p" "$and_s" "$and_a")" ]; then
    if [ "$and_class" = dispatch-failed ] && [ -z "$and_s" ] && [ -n "$and_p" ] && [ -n "$and_m" ] \
       && [ "$(printf '%s' "$1" | jq -r '.scope // ""')" = lane ]; then
      if [ -z "$2" ]; then
        render_failure err "baton: a hand-back ruling must not be empty"
        return 1
      fi
      resolve "$and_p" "$and_m" "" "" "$and_at" ruling || return 1
      render_row out record 'retry     %s/%s · the dispatch-failed park is released; the next tick may dispatch when eligible\n' \
        "$(render_token out lane "$and_p")" "$(render_token out milestone "$and_m")"
      return 0
    fi
    render_failure err "baton: the $and_class park on $and_p/$and_m names no session Baton dispatched, so there is nothing a ruling can reach; the way out is an edit to the plan or the brief"
    return 1
  fi

  and_text=$2
  case "$2" in
    ''|*[!0-9]*) ;;
    *)
      and_opts=$(answer_options "$and_p" "$and_m" "$and_s" "$and_carries") \
        || { render_failure err "baton: $and_opts"; return 1; }
      and_n=$(printf '%s' "$and_opts" | jq length)
      if [ "$and_n" -eq 0 ]; then
        render_failure err "baton: $and_p/$and_m offered no options, so $2 is not a choice; give the ruling as text"
        return 1
      fi
      if [ "$2" -lt 1 ] || [ "$2" -gt "$and_n" ]; then
        render_failure err "baton: $and_p/$and_m offered $and_n options and $2 is not one of them:"
        # The numbers are what the next command will carry, so they are rendered as the identity
        # of each option rather than left as part of its text.
        and_i=0
        while [ "$and_i" -lt "$and_n" ]; do
          and_i=$((and_i + 1))
          render_row err plain '  %s %s\n' "$(render_token err milestone "$and_i")" \
            "$(printf '%s' "$and_opts" | jq -r --argjson n "$and_i" '.[$n - 1]')"
        done
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
  and_n=$(resume_count_next "$and_p" "$and_m" "$and_a") || { render_failure err "$and_n"; return 1; }
  and_label=$(template_ruling "$and_m" "${and_n% *}" "${and_n#* }" "$and_at" "$and_q" "$and_text")

  and_out=$(resume_session "$and_p" "$and_m" "$and_a" "$and_s" \
    "$(job_of_session "$3" "$and_s")" ruling "$and_class" "$and_label") || { render_failure err "$and_out"; return 1; }
  and_outcome=$(printf '%s' "$and_out" | jq -r .outcome)
  render_row out record 'ruling    %s/%s · %s · %s · %s\n' \
    "$(render_token out lane "$and_p")" "$(render_token out milestone "$and_m")" \
    "$(render_token out session "$and_s")" "$and_class" "$and_outcome"
  case "$and_outcome" in
    delivered|forked)
      resolve "$and_p" "$and_m" "$and_s" "$and_a" "$and_at" ruling
      # Last, because the cascade delivers through this same function and its variables are the
      # file's: nothing of this delivery is read after it.
      if [ "$and_class" = main-broken ] && [ "${4:-yes}" != no ]; then
        main_broken_cascade "$and_p" "$2" "$3" "$and_at" "$and_m" || return 1
      fi ;;
    *)
      render_failure err "baton: the ruling did not reach $and_p/$and_m, so the park stands; run the same answer again once the resume can go through"
      return 1 ;;
  esac
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
  ahb_over=$(derive_taken_over "${2:-}" "$3") || { render_failure err "$ahb_over"; return 1; }
  ahb_list=$(printf '%s' "$ahb_over" | jq -c --arg m "$1" '[ .taken_over[] | select(.milestone == $m) ]')
  printf '%s\n' "$ahb_list"
}

# verb_answer <milestone | project/milestone | project/milestone@at> <ruling | n>: REQ-VERB-03.
#
# The target has three forms and they narrow in that order: a bare name across every project, a lane,
# and one park of that lane. The third is limitation 33's first half. A lane that carries two parks
# refused every ruling and printed the long form twice, which names the same lane and leads back to
# the same refusal — so a park that Baton had recorded, notified about and shown in `status` could
# not be answered through the public controls at all.
#
# The park is named by its `at`, because that is already its identity everywhere else: derivation 2
# keys on it, `resolve` closes an escalation by it, and `escalation_at` joins the two. Inventing a
# short id would be a second name for a thing that has one. `@` separates it because no milestone id
# and no ISO timestamp holds one, and the split takes the *last* `@` so a project key that holds one
# still parses.
verb_answer() {
  # An empty ruling would still arrive under the label, telling the session a decision had been made
  # and giving it nothing; and it would close the park, so the person could not send the real one.
  [ -n "$2" ] || { render_failure err "baton: a ruling is words or an option number, and this one is empty"; return 1; }
  case "$1" in
    *@*) vba_at=${1##*@}; vba_t=${1%@*} ;;
    *)   vba_at=''; vba_t=$1 ;;
  esac
  case "$vba_t" in
    */*) vba_p=${vba_t%%/*}; vba_m=${vba_t#*/} ;;
    *)   vba_p=''; vba_m=$vba_t ;;
  esac
  vba_rows=$(rows_json)
  vba_c=$(answer_resolve "$vba_m" "$vba_p" "$vba_at") || { render_failure err "baton: $vba_c"; return 1; }
  vba_n=$(printf '%s' "$vba_c" | jq -r .count)

  # A park id that matches nothing is refused on its own terms, because the two ways to reach zero
  # read identically otherwise and are opposite in what to do next: a lane with no park at all wants
  # "nothing is waiting", and a lane whose parks are all at other times wants to be shown them.
  if [ "$vba_n" -eq 0 ] && [ -n "$vba_at" ]; then
    vba_all=$(answer_resolve "$vba_m" "$vba_p") || { render_failure err "baton: $vba_all"; return 1; }
    if [ "$(printf '%s' "$vba_all" | jq -r .count)" -gt 0 ]; then
      render_failure err "baton: no park of $vba_t was raised at $vba_at; the open ones are:"
      answer_candidates_print "$(printf '%s' "$vba_all" | jq -c .candidates)" err at
      return 1
    fi
  fi

  if [ "$vba_n" -gt 1 ]; then
    # Parks in several projects are what the long form is for, and naming a project settles them.
    # Several parks on one lane are not: the long form names the same lane again, so those are shown
    # with the `at` that tells them apart and the refusal asks for a park rather than a project.
    vba_pn=$(printf '%s' "$vba_c" | jq '[ .candidates[] | .project ] | unique | length')
    if [ "$vba_pn" -gt 1 ]; then
      render_failure err "baton: $vba_m is parked in $vba_pn projects; name one:"
      answer_candidates_print "$(printf '%s' "$vba_c" | jq -c .candidates)" err
    else
      render_failure err "baton: $vba_t carries $vba_n open parks at once, which one lane should never do; Baton will not guess which the ruling answers. Name the park:"
      answer_candidates_print "$(printf '%s' "$vba_c" | jq -c .candidates)" err at
    fi
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
    render_failure err "baton: $vba_m is taken over in $vba_on projects; name one:"
    vba_i=0
    while [ "$vba_i" -lt "$vba_on" ]; do
      vba_c=$(printf '%s' "$vba_over" | jq -c --argjson i "$vba_i" '.[$i]'); vba_i=$((vba_i + 1))
      render_row err plain '  %s\n' "$(render_hint err \
        "baton answer $(printf '%s' "$vba_c" | jq -r .project)/$(printf '%s' "$vba_c" | jq -r .milestone) \"continue\"")"
    done
    return 1
  fi
  if [ "$vba_on" -eq 1 ]; then
    if [ "$2" != continue ]; then
      render_failure err "baton: $vba_m is taken over, not parked; nothing is waiting on a ruling. Hand it back with baton answer $vba_m \"continue\" and it is Baton's again"
      return 1
    fi
    vba_l=$(printf '%s' "$vba_over" | jq -c '.[0]')
    vba_ls=$(printf '%s' "$vba_l" | jq -r .session)
    vba_out=$(resume_session "$(printf '%s' "$vba_l" | jq -r .project)" "$vba_m" \
      "$(printf '%s' "$vba_l" | jq -r '.attempt // ""')" "$vba_ls" \
      "$(job_of_session "$vba_rows" "$vba_ls")" continue 'handed back') \
      || { render_failure err "$vba_out"; return 1; }
    render_row out record 'handed back  %s/%s · %s · %s\n' \
      "$(render_token out lane "$(printf '%s' "$vba_l" | jq -r .project)")" \
      "$(render_token out milestone "$vba_m")" \
      "$(render_token out session "$vba_ls")" "$(printf '%s' "$vba_out" | jq -r .outcome)"
    return 0
  fi

  # The target as the person typed it, long form and all: they named a lane, and being told that
  # nothing is waiting on the bare milestone would read as though the project half was ignored.
  render_failure err "baton: nothing is waiting on $1"
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
    . as $ev
    | [ $ev[] | select(.kind == "dispatch" and .milestone == $m and ($p == "" or .project == $p)) ]
    | group_by(.project) | map(last)
    | map({project, milestone, attempt, session,
           closed: (. as $d
                    | $ev | any(.kind == "consumed" and .project == $d.project
                                and .milestone == $d.milestone and .attempt == $d.attempt
                                and .outcome == "complete"))})
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
    '') render_failure err "baton: the rule is empty"; return 1 ;;
    ask|ask:*|'ask '*|Ask|Ask:*|'Ask '*)
      render_failure err "baton: refusing to write an ask rule. What a permissions.ask rule does under bypassPermissions is unknown (live item 42, unrun), and Baton does not write a rule whose effect it cannot state; the dispatched settings file carries no ask rules at all (INV-09)"
      return 1 ;;
  esac
  # The newline is a literal in the pattern and never `$(printf '\n')`: command substitution strips
  # trailing newlines, so that form is the empty string and the pattern `**` matches every rule.
  alw_nl='
'
  case "$alw_rule" in
    *"$alw_nl"*) render_failure err "baton: a rule is one line; this one has more than one"; return 1 ;;
  esac
  # A rule is `Tool` or `Tool(pattern)`, which is never valid JSON; anything that parses — an
  # object, a list, a quoted string, a number — is a settings fragment or a paste gone wrong, and
  # written as given it would sit in the allowlist matching nothing while looking like a rule.
  if printf '%s' "$alw_rule" | jq -e . > /dev/null 2>&1; then
    render_failure err "baton: a rule is written as it appears in the allowlist, such as Bash(xcodebuild:*), and this one is JSON"
    return 1
  fi
  # Bounded like every other field a writer carries into the log: the rule goes onto the `widening`
  # line whole, and a rule the log refused would leave two widened files and no provenance for them.
  if [ "$(printf '%s' "$alw_rule" | wc -c | tr -d ' ')" -gt 1024 ]; then
    render_failure err "baton: the rule is over 1 KB, which no permission rule needs; it is refused rather than written without its record"
    return 1
  fi

  alw_perm=$BATON_HOME/projects/$1/permissions.json
  alw_set=$BATON_HOME/settings/$1-$2.json
  if [ ! -f "$alw_perm" ]; then
    render_failure err "baton: $alw_perm does not exist, so project $1 has no allowlist to widen"
    return 1
  fi
  # Both files are read before either is written. Found out after the first write, a settings file
  # that does not parse would leave the allowlist widened with no `widening` event beside it, and
  # `baton plan`'s provenance would then disagree with the file it describes.
  jq -e . "$alw_perm" > /dev/null 2>&1 || { render_failure err "baton: $alw_perm does not parse; nothing was written"; return 1; }
  if [ -f "$alw_set" ] && ! jq -e . "$alw_set" > /dev/null 2>&1; then
    render_failure err "baton: $alw_set does not parse; nothing was written"
    return 1
  fi
  # Written as given, because Baton never judges a rule — but not in silence when the deny list
  # names the same one: deny wins at run time, so the widening would change nothing, and "allowed"
  # would be the wrong word for it.
  alw_word=allowed; alw_kind=record
  if jq -e --arg r "$alw_rule" '((.permissions.deny // []) | index($r)) != null' "$alw_perm" > /dev/null 2>&1; then
    alw_word='denied'; alw_kind=action
    render_failure err "baton: $alw_rule is also in the deny list of $alw_perm, and deny wins, so this widens nothing a session can use"
  fi
  alw_add='if ((.permissions.allow // []) | index($r)) == null
           then .permissions.allow = ((.permissions.allow // []) + [$r]) else . end'
  alw_wrote=no
  alw_new=$(jq --arg r "$alw_rule" "$alw_add" "$alw_perm") || { render_failure err "baton: $alw_perm does not parse"; return 1; }
  if [ "$alw_new" != "$(jq . "$alw_perm")" ]; then
    printf '%s\n' "$alw_new" > "$alw_perm.tmp"
    mv "$alw_perm.tmp" "$alw_perm"
    alw_wrote=yes
    render_row out "$alw_kind" '%-9s %s · %s · %s\n' "$alw_word" "$(render_token out lane "$1")" "$alw_rule" "$(render_token out path "$alw_perm")"
  else
    render_row out record 'already   %s · %s is in %s\n' "$(render_token out lane "$1")" "$alw_rule" "$(render_token out path "$alw_perm")"
  fi

  if [ -f "$alw_set" ]; then
    alw_new=$(jq --arg r "$alw_rule" "$alw_add" "$alw_set") \
      || { render_failure err "baton: $alw_set does not parse"; return 1; }
    if [ "$alw_new" != "$(jq . "$alw_set")" ]; then
      printf '%s\n' "$alw_new" > "$alw_set.tmp"
      mv "$alw_set.tmp" "$alw_set"
      alw_wrote=yes
      render_row out "$alw_kind" '%-9s %s · %s · %s\n' "$alw_word" "$(render_token out milestone "$2")" "$alw_rule" "$(render_token out path "$alw_set")"
    else
      render_row out record 'already   %s · %s is in %s\n' "$(render_token out milestone "$2")" "$alw_rule" "$(render_token out path "$alw_set")"
    fi
  else
    # Said rather than swallowed: the rule is in the project's allowlist and will reach the next
    # dispatch, but the session running now is reading a file that no longer exists, so a resume
    # would not pick the rule up either.
    render_failure err "baton: $alw_set does not exist, so only the project's allowlist was widened"
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
  vbl_lane=$(allow_lane "$vbl_m" "$vbl_p") || { render_failure err "baton: $vbl_lane"; return 1; }
  vbl_n=$(printf '%s' "$vbl_lane" | jq -r .count)
  if [ "$vbl_n" -eq 0 ]; then
    render_failure err "baton: Baton has dispatched no $vbl_m, so there is no allowlist it has earned; widen a project's permissions.json by hand instead"
    return 1
  fi
  if [ "$vbl_n" -gt 1 ]; then
    render_failure err "baton: $vbl_m has run in $vbl_n projects; name one:"
    vbl_i=0
    while [ "$vbl_i" -lt "$vbl_n" ]; do
      vbl_c=$(printf '%s' "$vbl_lane" | jq -c --argjson i "$vbl_i" '.candidates[$i]'); vbl_i=$((vbl_i + 1))
      render_row err plain '  %s\n' "$(render_hint err "$(printf '%s' "$vbl_c" | jq -r --arg r "$2" \
        '"baton allow \(.project)/\(.milestone) \($r | @sh)"')")"
    done
    return 1
  fi
  vbl_l=$(printf '%s' "$vbl_lane" | jq -c '.candidates[0]')
  vbl_pj=$(printf '%s' "$vbl_l" | jq -r .project)
  # A parked lane is not woken by a widening. The usual reason to widen is a session that stopped
  # and said why, which parked the lane: `--resume` would start the session again while the park
  # still stood, so no rule would act on the lane, `status` would show a park nobody could clear
  # but by a ruling, and that ruling would resume a session already running. The way back into a
  # parked lane is `baton answer`, which resolves the park it delivers into. Refused before
  # anything is written, so the command either does all of what it says or none of it.
  if [ "${3:-}" = --resume ]; then
    # A completed attempt is not a lane. `allow_lane` takes the milestone's newest dispatch and asks
    # nothing about how it ended, while every guard below reads `derive_taken_over`, whose domain is
    # `lanes_open` — which has already dropped an attempt a consumed `complete` closed. So against a
    # completed target the takeover check has nothing to look at and passes on an empty list, and the
    # resume goes through: that session's process can still be alive, because a finished session is
    # kept while it is one of the few most recently active, and it is a person's to continue by hand
    # (D-078). Stopping and re-prompting a conversation that is no longer Baton's, with no way to
    # have seen a person typing in it, is the one thing INV-04 exists for. The rule is still written,
    # because widening a finished milestone's allowlist costs nothing; only the resume is refused,
    # and before anything is written (D-132).
    if printf '%s' "$vbl_l" | jq -e '.closed' > /dev/null; then
      render_failure err "baton: $vbl_pj/$vbl_m completed attempt $(printf '%s' "$vbl_l" | jq -r '.attempt // "?"'), so there is no open lane to resume and its session is a person's to continue by hand; run baton allow $vbl_pj/$vbl_m with the rule alone to widen without resuming"
      return 1
    fi
    vbl_park=$(derive_parked "$vbl_pj") || { render_failure err "baton: $vbl_park"; return 1; }
    vbl_class=$(printf '%s' "$vbl_park" | jq -r --arg m "$vbl_m" \
      '[ .parked[] | select(.milestone == $m and .scope == "lane") ] | first | .class // empty')
    if [ -n "$vbl_class" ]; then
      render_failure err "baton: $vbl_pj/$vbl_m is parked ($vbl_class), so --resume would wake it behind its own park; run baton allow $vbl_pj/$vbl_m with the rule alone, then baton answer $vbl_pj/$vbl_m \"<ruling>\", which resumes it and closes the park"
      return 1
    fi
    vbl_rows=$(rows_read) || { render_failure err "baton: the session rows could not be read; --resume refused before widening"; return 1; }
    vbl_over=$(derive_taken_over "$vbl_pj" "$vbl_rows") || { render_failure err "baton: $vbl_over"; return 1; }
    if printf '%s' "$vbl_over" | jq -e --arg m "$vbl_m" \
         'any(.taken_over[]; .milestone == $m)' > /dev/null; then
      render_failure err "baton: $vbl_pj/$vbl_m is taken over; --resume would interrupt the person. Use the rule alone to widen without resuming, or baton answer $vbl_pj/$vbl_m \"continue\" to hand the lane back"
      return 1
    fi
    if printf '%s' "$vbl_over" | jq -e --arg m "$vbl_m" \
         'any((.orphaned + .unreadable)[]; .milestone == $m)' > /dev/null; then
      render_failure err "baton: $vbl_pj/$vbl_m could not be checked for takeover; --resume refused before widening"
      return 1
    fi
  fi
  allow_write "$vbl_pj" "$vbl_m" "$2" || return 1

  [ "${3:-}" = --resume ] || return 0
  # The re-issued command passes because the resumed session reads the widened settings file, and
  # the call the refusal dropped is repeated by the continue template's own interrupted-tool
  # sentence. One path serves a live prompt and a lost one alike.
  vbl_a=$(printf '%s' "$vbl_l" | jq -r '.attempt // ""')
  vbl_s=$(current_session "$vbl_pj" "$vbl_m" "$vbl_a") || { render_failure err "baton: $vbl_s"; return 1; }
  if [ -z "$vbl_s" ]; then
    render_failure err "baton: no session carries $vbl_pj/$vbl_m attempt $vbl_a, so there is nothing to resume"
    return 1
  fi
  vbl_out=$(resume_session "$vbl_pj" "$vbl_m" "$vbl_a" "$vbl_s" \
    "$(job_of_session "$vbl_rows" "$vbl_s")" continue 'the allowlist was widened') \
    || { render_failure err "$vbl_out"; return 1; }
  # A resume that forked and could not confirm the original stopped is not a plain success, whatever
  # the classifier called it: the lane has moved to the copy and another worker may be running under
  # an id nothing tracks. The park `resume_session` wrote says so durably; this says so here, where
  # the person who typed the command is reading (D-132).
  render_row out record 'resumed   %s/%s · %s · %s%s\n' \
    "$(render_token out lane "$vbl_pj")" "$(render_token out milestone "$vbl_m")" \
    "$(render_token out session "$vbl_s")" \
    "$(printf '%s' "$vbl_out" | jq -r .outcome)" \
    "$(printf '%s' "$vbl_out" | jq -r 'if has("unresolved_original") then " · the original may still be running: " + .unresolved_original else "" end')"
}
