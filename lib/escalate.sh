#!/bin/sh
# lib/escalate.sh — everything that needs a person, and the record that says so.
#
# An escalation parks a lane or a project and Baton stops acting on it; a notification is a message
# it keeps working past (REQ-ESC-01). Both reach the Mac the same way, and both are written here or
# in `lib/notify.sh` so that "every escalation reaches the person" is true by construction. What
# this file adds over M03's bare writer is the part that lets the park end: the class's own
# `carries`, the message a person can act on without opening anything, and the three resolutions —
# a ruling, a question answered in place, and an edit the next tick re-reads (REQ-ESC-05).
#
# **Nothing times out.** There is no clock anywhere in this file. A parked lane waits for a person
# and a person is the only thing that ends it, which is the whole difference between a relay and a
# supervisor: Baton stops rather than guesses.
#
# The two verbs a person runs to come back — `answer` and `allow` — live in `lib/answer.sh`, which
# reads this file's record. The seam is direction: this is what Baton writes when it needs a
# person, that is what the person runs to reach the session.
set -eu

# class_unparks_by_edit <class>: whether a person's edit to the plan file or the brief is a
# resolution path for this class. This is the per-class half of REQ-ESC-05, and it is a property of
# what the person has to do, not a severity: the escalation table in "Where an escalation goes" §5
# gives each class its verb, and only these classes' verbs are an edit.
#
# It decides two things at once. An escalation of one of these classes carries the hashes the
# re-read compares against, so the next tick can see the edit; one of the others carries none, and
# `edit_reread_check` passes it by. That second half is load-bearing and not an optimisation: a
# ruling is the only way an `asking` park ends, because the session was stopped on consume and
# nothing but a resume reaches it. Unparking it on an unrelated plan edit would leave a stopped
# session, an open lane and no park — a lane that has left every view Baton has, which is worse
# than a park nobody has answered yet.
class_unparks_by_edit() {
  case "$1" in
    ladder-end|unfinished-twice|blocked|model_not_found|disagreement|omitted|dispatch-failed) return 0 ;;
    *) return 1 ;;
  esac
}

# reread_hashes <project> <milestone> <carries json> [<plan json>]: the two readings an edit changes
# — the plan rows that answer this park, and the brief's kickoff prompt — hashed as they stand now.
# The plan is the tick's own parsed document when the caller holds one, and read afresh when not.
#
# **The rows that answer the park, and no others.** An unpark now leads somewhere — a redispatch —
# so an unpark on a change nobody meant for this lane would restart a lane whose ladder ended
# because another lane's close-out wrote `done` in its own `Status` cell. The rows are the
# milestone's own (its `Model` cell answers a refused model), every row whose `Depends on` names it
# (a split adds one), and the row the carries names as the blocker (its `Status` releases a
# `blocked` lane). Each is the parsed row with its row number taken out, so a row added above it or
# pipes re-aligned around it is not a decision, and prose outside the table never is.
#
# **The brief through `git show main:`**, which is how a dispatch reads it (`prompt_from_brief`).
# An uncommitted edit is not one a session would ever receive, so it is not one that should unpark
# a lane: the person's edit becomes real when it is committed, and that is the same moment for both
# halves of Baton.
#
# A reading that fails is absent rather than empty, the envelope's rule: a plan file that cannot be
# read parks the project on its own account, and a brief that is not on main is not evidence that
# anything changed.
reread_hashes() {
  rrh_plan=''; rrh_brief=''
  [ -n "$2" ] || { echo '{}'; return 0; }
  rrh_doc=${4:-}
  [ -n "$rrh_doc" ] || rrh_doc=$(plan_of_project "$1" 2>/dev/null) || rrh_doc=''
  if [ -n "$rrh_doc" ]; then
    rrh_plan=$(printf '%s' "$rrh_doc" | jq -c --arg m "$2" \
        --arg b "$(printf '%s' "${3:-"{}"}" | jq -r '.blocked_by // ""' 2>/dev/null || true)" '
        [ .milestones[]
          | select(.id == $m or ((.depends // []) | index($m)) != null or ($b != "" and .id == $b))
          | del(.row) ]' 2>/dev/null | shasum -a 256 | awk '{ print $1 }') || rrh_plan=''
  fi
  if rrh_path=$(project_path "$1" 2>/dev/null); then
    if rrh_text=$(prompt_from_brief "$rrh_path" "docs/milestones/$2.md" "Copy-ready session prompt" 2>/dev/null); then
      rrh_brief=$(printf '%s' "$rrh_text" | shasum -a 256 | awk '{ print $1 }')
    fi
  fi
  jq -nc --arg p "$rrh_plan" --arg b "$rrh_brief" \
    '{plan_rows_sha256: $p, brief_sha256: $b} | with_entries(select(.value != ""))'
}

# person_acted <project> <milestone> <class>: how a person answered the park this lane's newest
# ending earned — `edit`, `ruling`, or nothing when the park is still open or no park of that class
# followed the ending.
#
# This is what makes a resolution the end of a park and not a pause in one. The rules that park a
# lane — the ladder's last rung, two `unfinished` in a row, a refused model, a blocker nothing is
# coming for — read the same ending on every tick, so a lane freed by a person would be parked again
# by the rule a second later and the person's decision would last one tick. Each of them asks this
# first. An **edit** is the person changing the plan or the brief the lane runs from, so the rule
# takes the step the edit was for; a **ruling** was delivered to the session, which is now working
# on it, so the rule stands down until the session's next ending.
#
# Everything is compared by position in the log, never by time: every event a tick writes carries
# the same reading of the clock, so "after" is the only order that survives a second. A ruling's own
# resume that the CLI refused is not an ending: the session did not end, Baton failed to reach it,
# and the park stands until the person sends the ruling again — which must then still count.
person_acted() {
  pac_log=$(log_json) || { echo "$pac_log" >&2; return 1; }
  printf '%s' "$pac_log" | jq -r --arg p "$1" --arg m "$2" --arg c "$3" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
    | ([ $ev[] | select(.kind == "consumed" or (.kind == "crash_sighting" and .sighting == 2)
                        or (.kind == "resume" and .outcome == "refused" and .resume_kind != "ruling"))
       ] | last | .i // -1) as $end
    | ([ $ev[] | select(.kind == "escalation" and .class == $c and .i > $end) ] | last) as $park
    | if $park == null then empty
      else ([ $ev[] | select(.kind == "resolution" and .escalation_at == $park.at and .i > $park.i) ]
            | last | .how // empty) end'
}

# escalate <project> <milestone> <session> <attempt> <class> <scope> <carries json>: the one writer
# of an `escalation` event and the Mac message that goes with it. Every writer in M02 to M04 that
# wrote one directly calls this instead.
#
# Three things happen in a fixed order, and the order is the rule.
#
# 1. The class and the fields are checked. A class outside the log's two lists is a typo that would
#    sit in the record looking like a state nothing can resolve, and `baton answer` matches on the
#    class.
# 2. The re-read hashes are attached, for the classes an edit resolves. They are attached here
#    rather than by each caller because the caller knows what failed and this knows what ends it.
# 3. The event is written, and **only then** is the message raised. `log_event` refuses a line at
#    4 KB and refuses one without the lock, and a message with no event behind it is worse than
#    neither: every once-only rule in Baton reads the log, so an escalation nothing recorded is a
#    park that does not exist — the lane is never held, the retries never stop, and the same
#    message goes out on every tick with nothing in the record to answer it (D-057, measured at
#    28,757 bytes on an `unfinished-twice` carrying two splits a session had really written).
#
# A writer bounds its own fields, and that stays with the callers: the cut belongs where the
# unbounded thing is known — `artifact_detail` cuts a session's prose, `asking_carries` cuts a
# question — because a second cut here would hide a missing one there from the fixture that exists
# to catch it.
escalate() {
  esc_class=$5; esc_scope=$6; esc_carries=$7
  class_or_fail escalate escalation "$esc_class" || return 1
  fields_or_fail escalate "$esc_carries" || return 1
  # Scope is read by `status`, `derive_parked` and every rule that stands a lane down, so a scope
  # outside the two is a park that holds nothing and is shown as nothing.
  case "$esc_scope" in
    lane|project) ;;
    *) echo "escalate: \"$esc_scope\" is not a scope; it is lane or project" >&2; return 1 ;;
  esac
  # The hashes go on a lane park when an edit is a way out of its class — or when no ruling can
  # reach the lane, whatever its class. A ruling is delivered by resuming a session Baton dispatched
  # (`ruling_target`), so a park without one has no ruling route at all: a rejected artifact whose
  # lane Baton never dispatched, an `eligible[]` entry dropped for a brief pointer that is not on
  # main. Without this such a park would have no way out whatsoever, and a park nothing can resolve
  # holds its milestone out of every dispatch for as long as Baton runs. A project park is never
  # given them: the self-check re-reads the plan every tick and `park_resolve` closes it.
  if [ "$esc_scope" = lane ] && [ -n "$1" ] \
     && { class_unparks_by_edit "$esc_class" || [ -z "$(ruling_target "$1" "$3" "$4")" ]; }; then
    esc_carries=$(printf '%s' "$esc_carries" | jq -c --argjson r "$(reread_hashes "$1" "$2" "$esc_carries")" \
      'if ($r | length) > 0 then . + {reread: $r} else . end')
  fi
  log_event escalation "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg c "$esc_class" --arg s "$esc_scope" --argjson carries "$esc_carries" \
       '{class: $c, scope: $s, carries: $carries, channel: ["notification"]}')" || return 1
  esc_msg=$(message_render "$1" "$2" "$esc_class" "$esc_carries" "$3" "$4")
  notify "$(printf '%s' "$esc_msg" | jq -r .address)" "$(printf '%s' "$esc_msg" | jq -r .body)"
}

# resolve <project> <milestone> <session> <attempt> <escalation at> <how>: the unpark. One of
# exactly three ways (REQ-ESC-05), named on the event so that `status` and a person reading the log
# can tell a ruling from an answer given in place from an edit — three different things a person
# did, and the log is the only place that remembers which.
#
# The escalation is named by its `at`, which is what derivation 2 joins on. Nothing is deleted: an
# escalation record is resolved, never removed, so the morning after can still read what happened.
resolve() {
  case "$6" in
    ruling|"answered in place"|edit) ;;
    *) echo "resolve: \"$6\" is not one of ruling, answered in place, edit" >&2; return 1 ;;
  esac
  log_event resolution "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg h "$6" --arg a "$5" '{how: $h, escalation_at: $a}')"
}

# ruling_target <project> <session> <attempt>: the session a ruling would be delivered to, or
# nothing.
#
# All three are needed, and this is the one definition of "a session Baton dispatched" the park and
# the verb share with the consume, which refuses to stop a session no attempt names. A resume is
# logged against a lane, so a park that names a session but no project — a handover whose `project`
# names a checkout Baton has never heard of — is not a lane Baton may resume; nor is one with no
# attempt, which is a session a person started by hand. Baton does not start, stop or resume what it
# did not start. Such a park gets the edit route instead (`escalate`).
ruling_target() {
  { [ -n "$1" ] && [ -n "$2" ] && [ -n "${3:-}" ]; } || return 0
  printf '%s' "$2"
}

# escalation_content <class> <carries json>: REQ-ESC-03's second part — the decision itself, never
# a pointer to something that must be opened. A question arrives with its options numbered and its
# recommendation marked; everything else arrives as its detail.
#
# This is `one_line`'s longer sibling and the two are deliberately different. `status` prints one
# line per park (§5.3 line 3), so `one_line` takes the first; the Mac message is where the decision
# is made, so this takes the whole of it and lets `notify_text` cap what Notification Center would
# have truncated anyway.
escalation_content() {
  printf '%s' "$2" | jq -r '
    . as $c
    | if type != "object" then tostring
      elif has("question") then
        .question
        + (if ((.options // []) | length) > 0
           then "  " + ((.options | to_entries
                         | map("\(.key + 1) \(.value)"
                               + (if (.value | tostring) == (($c.recommendation // "") | tostring)
                                  then " (recommended)" else "" end)))
                        | join("   "))
           elif (($c.recommendation // "") | tostring) != ""
           then "  recommended: \($c.recommendation)"
           else "" end)
      elif has("detail") then .detail
      elif has("rule") then "\(.rule) · \(.path // "")"
      else (to_entries | map("\(.key) \(.value | tostring)") | join(", ")) end' 2>/dev/null \
    || printf '%s' "$2"
}

# escalation_verb <class> <milestone> <carries json> [<session>]: REQ-ESC-03's third part — the
# `baton` command that resolves this park, or the edit that does. One line, last, because the first
# two lines are the decision and this is the acting: the message is read where a person decides and
# run where they have a keyboard.
#
# The option form is `<n>` and not the recommended number, though the ticket's worked example shows
# one. The content above already marks which option is recommended; a copy-ready command carrying
# it would make the recommended answer the only one that costs nothing to give, which is a nudge
# Baton has no business making on a decision it escalated precisely because it cannot make it.
escalation_verb() {
  evb_m=$2
  # A ruling is delivered by resuming a session inside a lane, so a park that `ruling_target` calls
  # unreachable cannot be answered and must not print a command that would be refused. The edit is
  # its way out, and `escalate` gave it the hashes that make the edit visible.
  if [ -z "${4:-}" ]; then
    case "$1" in
      asking|question|merge-failed|other)
        printf 'fix what it names; the next tick re-reads the plan and the brief'
        return 0 ;;
    esac
  fi
  case "$1" in
    asking)
      if printf '%s' "$3" | jq -e '((.options // []) | length) > 0' > /dev/null 2>&1; then
        printf 'baton answer %s <n>' "$evb_m"
      else
        printf 'baton answer %s "<ruling>"' "$evb_m"
      fi ;;
    question)
      evb_job=$(printf '%s' "$3" | jq -r '.job // ""' 2>/dev/null || true)
      if [ -n "$evb_job" ]; then
        printf 'answer it in place (claude attach %s), or baton answer %s "<ruling>"' "$evb_job" "$evb_m"
      else
        printf 'answer it in place, or baton answer %s "<ruling>"' "$evb_m"
      fi ;;
    merge-failed)
      printf 'baton answer %s "merge resolved; finish the close-out from step (c)"' "$evb_m" ;;
    ladder-end)
      printf 'edit the brief or the plan, or baton answer %s "<ruling>"' "$evb_m" ;;
    unfinished-twice)
      printf 'edit the plan; a split is a plan edit' ;;
    blocked)
      printf 'edit the plan, or baton answer %s "<ruling>"' "$evb_m" ;;
    model_not_found)
      printf 'edit the Model cell for %s in %s; the next tick redispatches' "$evb_m" \
        "$(printf '%s' "$3" | jq -r '.plan // "the plan file"' 2>/dev/null || echo 'the plan file')" ;;
    disagreement|omitted)
      printf 'edit the plan or the brief; the next tick re-reads it' ;;
    plan-unreadable|plan-unparseable)
      printf 'fix the plan file; the next tick re-reads it' ;;
    main-broken)
      printf 'fix main; the next tick re-reads it' ;;
    dispatch-failed)
      printf 'fix what the %s stage names; the next tick dispatches again' \
        "$(printf '%s' "$3" | jq -r '.stage // "failed"' 2>/dev/null || echo failed)" ;;
    baton-unhealthy)
      # The only writer of this class is the stale-lock break, which has already done the one thing
      # there was to do and resolves its own park in the same tick. A verb here would tell a person
      # to fix something Baton fixed while they slept.
      printf 'nothing to do; Baton cleared it and carried on' ;;
    *)
      printf 'baton answer %s "<ruling>"' "$evb_m" ;;
  esac
}

# message_render <project> <milestone> <class> <carries json> [<session>] [<attempt>]: the
# three-part message, REQ-ESC-03, as one document — address, content, verb, and the body the Mac message carries.
#
# The body is the content and the verb joined, because `display notification` has two fields and
# the address takes the title. The decision leads and the verb is last, which is the order the
# ticket fixed for a lock screen and which still holds at a keyboard: a person reads to decide and
# then reads what to type.
# **The verb is never the part that gets cut.** `notify_text` caps the body at 250 code points
# because Notification Center truncates far shorter, and the verb is last — so a long detail would
# eat exactly the sentence that says what to do, which is the one part a person cannot reconstruct.
# The content is cut to what is left after the verb instead, in code points and by jq, for the same
# two reasons `notify_text` gives: this Mac's awk counts bytes, and a cut applied after escaping can
# leave a literal ending in a lone backslash.
message_render() {
  mrn_content=$(escalation_content "$3" "$4")
  mrn_verb=$(escalation_verb "$3" "$2" "$4" "$(ruling_target "$1" "${5:-}" "${6:-}")")
  jq -nc --arg a "$(notify_title "$1" "$2" "$3")" --arg c "$mrn_content" --arg v "$mrn_verb" '
    (250 - ($v | length) - 3) as $room
    | { address: $a, content: $c, verb: $v,
        body: (if $v == "" then $c
               elif $room < 20 then "\($c[0:20])… · \($v)"
               elif ($c | length) > $room then "\($c[0:$room - 1])… · \($v)"
               else "\($c) · \($v)" end) }'
}

# asking_carries <artifact json>: what an `asking` escalation carries — the question verbatim, its
# options, the recommendation and the context pointer the contract asks for (REQ-ARTIFACT-03).
#
# **Every field is cut, and cut in bytes**, because every one is a session's own prose at whatever
# length and in whatever script it took, and the log refuses a line at 4096 bytes and not at 4096
# characters. A question of five hundred characters in Japanese is fifteen hundred bytes; cutting by
# code points would pass it and the refusal would be the first defence after all. `cut` keeps a
# string whole when it fits its budget and otherwise takes as many characters as the budget holds
# even at four bytes each, so the bound is exact whatever the text is. The budgets sum to about
# 2.3 KB, which leaves the envelope and the re-read room under the line.
#
# The shapes are forced as well as the lengths. `options` is a list in the contract and a session
# can still write a string, which jq cannot iterate — measured, that aborted the carries and lost
# the park — so a lone value becomes a list of one. `context` keeps the two fields the contract
# names and nothing a session pasted beside them.
#
# The options are cut hardest and capped at six, and that costs nothing: `baton answer <M> <n>`
# expands the number from the **archived artifact**, not from this record, so a shortened list
# shortens the message and never the answer.
asking_carries() {
  printf '%s' "$1" | jq -c '
    def cut($n): tostring
      | if utf8bytelength <= $n then .
        elif (.[0:$n] | utf8bytelength) <= $n then .[0:$n] + "…"
        else .[0:($n / 4 | floor)] + "…" end;
    {question, options, recommendation, context}
    | with_entries(select(.value != null))
    | (if has("question") then .question |= cut(600) else . end)
    | (if has("recommendation") then .recommendation |= cut(150) else . end)
    | (if has("options") then .options |= ((if type == "array" then . else [.] end) | [ .[0:6][] | cut(150) ]) else . end)
    | (if has("context") then .context |= (if type == "object"
                                           then {path: (.path // "" | cut(300)), heading: (.heading // "" | cut(150))}
                                                | with_entries(select(.value != ""))
                                           else {path: cut(300)} end) else . end)'
}

# ending_escalate <project> <milestone> <session> <attempt> <artifact json> <class> <archive path>:
# the park an ending earns at the moment it is consumed. `asking`, `merge-failed` and `other` are
# the three `route_ending` names and nothing acted on until now (M04's known limitations).
#
# It happens at the consume rather than in step 4 because the artifact is in hand there: the
# question, its options and its recommendation are the session's own words, and re-reading them
# from the archive a step later would be reading a file to learn what was just parsed. The consume
# is once by the move (INV-06), so the park is written once for the same reason.
#
# **The park is not optional once the session has been stopped.** An `asking` consume stops the
# session before it parks the lane, and no later rule looks at an asking consume again — the crash
# rule passes it by and the ladder counts no failure — so a park that could not be written would be
# a stopped session with no park, no message and no verb, for as long as Baton runs. Whatever made
# the full carries fail, a carries of one sentence and the archive's path is written instead; it is
# small enough that only a missing lock refuses it, and the question is in the file it names.
ending_escalate() {
  end_class=$6
  case "$end_class" in
    asking)
      end_carries=$(asking_carries "$5" 2>/dev/null) || end_carries='' ;;
    *)
      end_detail=$(artifact_detail "$7")
      [ -n "$end_detail" ] || end_detail="the session gave no detail"
      case "$end_class" in
        merge-failed) end_detail="the merge into main failed: $end_detail" ;;
        *)            end_detail="the session stopped: $end_detail" ;;
      esac
      end_carries=$(jq -nc --arg d "$end_detail" --arg a "$7" '{detail: $d, archive: $a}') ;;
  esac
  if [ -n "$end_carries" ] && escalate "$1" "$2" "$3" "$4" "$end_class" lane "$end_carries"; then
    return 0
  fi
  echo "baton: $1/$2 the $end_class park did not fit its full carries; parking it with a pointer to $7" >&2
  escalate "$1" "$2" "$3" "$4" "$end_class" lane \
    "$(jq -nc --arg a "$7" '{detail: "the session stopped with words Baton could not carry whole; they are in the archived artifact", archive: $a}')"
}

# edit_reread_check <project> <plan json>: REQ-ESC-05's third route, and the one only the tick can
# see, because only the tick re-reads. For every parked lane carrying the hashes, the rows that answer
# it — from the plan the tick has already parsed — and the brief are read again and compared against
# the hashes the escalation carried; a difference is the person's decision arriving, and the lane
# unparks without a second command.
#
# Only the fields the escalation carried are compared. A reading that fails now is absent, not
# different: a plan file that has become unreadable parks the project on its own account and must
# not also unpark every lane that was waiting on it.
#
# The unpark is written before step 4 runs, so the rule that parked the lane gets the same tick to
# act on the edit: a `blocked` lane whose blocker now reads `done` is redispatched a second later
# rather than a minute later, and a refused model or an ended ladder is redispatched rather than
# parked again (`person_acted`).
edit_reread_check() {
  err_parked=$(derive_parked "$1") || { echo "$err_parked" >&2; return 1; }
  err_list=$(printf '%s' "$err_parked" | jq -c '[ .parked[] | select(.carries.reread != null) ]')
  err_n=$(printf '%s' "$err_list" | jq length); err_i=0
  while [ "$err_i" -lt "$err_n" ]; do
    err_e=$(printf '%s' "$err_list" | jq -c ".[$err_i]"); err_i=$((err_i + 1))
    err_m=$(printf '%s' "$err_e" | jq -r '.milestone // ""')
    err_was=$(printf '%s' "$err_e" | jq -c .carries.reread)
    err_now=$(reread_hashes "$1" "$err_m" "$(printf '%s' "$err_e" | jq -c .carries)" "${2:-}")
    err_changed=$(jq -nc --argjson was "$err_was" --argjson now "$err_now" '
      [ $was | keys[] | select(($now[.] // null) != null and $now[.] != $was[.]) ]')
    [ "$(printf '%s' "$err_changed" | jq length)" -gt 0 ] || continue
    err_what=$(printf '%s' "$err_changed" | jq -r \
      'map(if . == "plan_rows_sha256" then "the plan rows it answers to" else "the brief" end) | join(" and ")')
    resolve "$1" "$err_m" "$(printf '%s' "$err_e" | jq -r '.session // ""')" \
      "$(printf '%s' "$err_e" | jq -r '.attempt // ""')" \
      "$(printf '%s' "$err_e" | jq -r .at)" edit
    printf 'unparked  %s/%s · %s changed since the %s park · Baton acts on the lane again\n' \
      "$1" "$err_m" "$err_what" "$(printf '%s' "$err_e" | jq -r '.class // "?"')"
  done
}

# question_resolve_check <project> <rows json>: the second route out of a park, and the one nobody
# types — a live question answered in place. The row is the only signal there is: no field records
# who answered, and `timeline.jsonl` is an interface its own documentation calls unstable, so the
# transition out of `waitingFor: "input needed"` is what says the person answered.
#
# The same read answers the other question about such a lane. A park whose session no longer has a
# live row has lost that route: the row transition can never happen now, so `baton answer` is the
# only way left, and `prompt-lost` says so once. It has **not** lost the call — a call parked at
# `AskUserQuestion` when the session stops receives `[Request interrupted by user for tool use]`
# and can be answered on resume (D-016) — which is why the ruling that follows carries no
# dropped-call sentence and why this is a notification and not a second park.
question_resolve_check() {
  qrc_parked=$(derive_parked "$1") || { echo "$qrc_parked" >&2; return 1; }
  qrc_list=$(printf '%s' "$qrc_parked" | jq -c '[ .parked[] | select(.class == "question") ]')
  [ "$(printf '%s' "$qrc_list" | jq length)" -gt 0 ] || return 0
  qrc_log=$(log_json) || { echo "$qrc_log" >&2; return 1; }
  qrc_n=$(printf '%s' "$qrc_list" | jq length); qrc_i=0
  while [ "$qrc_i" -lt "$qrc_n" ]; do
    qrc_e=$(printf '%s' "$qrc_list" | jq -c ".[$qrc_i]"); qrc_i=$((qrc_i + 1))
    qrc_m=$(printf '%s' "$qrc_e" | jq -r '.milestone // ""')
    qrc_s=$(printf '%s' "$qrc_e" | jq -r '.session // ""')
    qrc_a=$(printf '%s' "$qrc_e" | jq -r '.attempt // ""')
    qrc_at=$(printf '%s' "$qrc_e" | jq -r .at)
    # The session's own artifact, consumed after the park, is the surest sign of all that the
    # question was answered in place: a session waiting for input writes nothing. It comes first
    # because the row is the slowest witness — it can still read `input needed` a minute after the
    # session moved on, or be gone because the consume stopped it — and a park left open beside the
    # park that artifact earned is a lane `baton answer` can never act on, since both carry its name.
    # Positions in the log, not times: a tick stamps every event with one reading of the clock.
    if printf '%s' "$qrc_log" | jq -e --arg s "$qrc_s" --arg at "$qrc_at" --arg m "$qrc_m" '
         [ to_entries[] | {i: .key} + .value ] as $ev
         | ([ $ev[] | select(.kind == "escalation" and .class == "question" and .at == $at
                             and .milestone == $m and .session == $s) ] | last | .i) as $park
         | any($ev[]; .kind == "consumed" and .session == $s and .written_by == "session" and .i > $park)' \
         > /dev/null; then
      resolve "$1" "$qrc_m" "$qrc_s" "$qrc_a" "$qrc_at" "answered in place"
      printf 'unparked  %s/%s · %s · the session wrote its own handover after the question, so it was answered in place\n' \
        "$1" "$qrc_m" "$qrc_s"
      continue
    fi
    qrc_row=$(printf '%s' "$2" | jq -c --arg s "$qrc_s" \
      'map(select(.sessionId == $s and .pid != null)) | first // {}')
    if [ "$(printf '%s' "$qrc_row" | jq 'length')" -gt 0 ]; then
      [ "$(printf '%s' "$qrc_row" | jq -r '.waitingFor // ""')" != "input needed" ] || continue
      resolve "$1" "$qrc_m" "$qrc_s" "$qrc_a" "$qrc_at" "answered in place"
      printf 'unparked  %s/%s · %s · the question was answered in place\n' "$1" "$qrc_m" "$qrc_s"
      continue
    fi
    # No live row: the session is stopped and the row transition can no longer unpark the lane.
    # Once per park, keyed on the escalation's own `at`, because a second park is a second question.
    qrc_spent=$(derive_key_spent "$1" "$qrc_m" "${qrc_a:-0}" prompt-lost "$qrc_at") \
      || { echo "$qrc_spent" >&2; return 1; }
    [ "$(printf '%s' "$qrc_spent" | jq -r .spent)" = false ] || continue
    # A notification's body is its detail alone — the three-part message with its verb last belongs
    # to a park — so the command goes in the sentence. This one is worth the words: the person is
    # being told that the way they would have answered is gone, and the way that is left is a verb.
    qrc_detail="the session stopped while the question was open, so answering it in the session can no longer unpark the lane; the call can still be answered on the resume, with baton answer $qrc_m \"<ruling>\""
    notification_write "$1" "$qrc_m" "$qrc_s" "$qrc_a" prompt-lost "$qrc_at" \
      "$(jq -nc --arg a "$qrc_at" --arg d "$qrc_detail" '{asked_at: $a, detail: $d}')"
    printf 'prompt    %s/%s · %s · the question outlived its session; only a ruling reaches it now\n' \
      "$1" "$qrc_m" "$qrc_s"
  done
}
