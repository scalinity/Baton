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

# class_ends_on_done <class>: whether the one edit that ends this class is the milestone's `Status`
# changing to `done` — the plan-file fallback REQ-STOP-12 gives `merge-failed` and `main-broken` when
# the session cannot finish its own close-out.
#
# Not any edit, and that is the whole difference from the classes above. Both endings stop before
# step (c), so the session still owes the refresh, the `done` and the artifact, and a ruling is how
# it is sent back to them; a person editing the Model cell or a brief meanwhile has not done any of
# that, and unparking on it would leave a session waiting for a ruling with no park to receive one.
# `done` written after the park is the state step (c) produces, so it is the person saying the
# close-out happened by hand. Written after the park and not merely present: a session that wrote
# `done` a step early and then failed its merge left the cell reading `done` at the escalation, and
# that must not close the park on the only copy of an unmerged milestone.
class_ends_on_done() {
  case "$1" in
    merge-failed|main-broken) return 0 ;;
    *) return 1 ;;
  esac
}

# class_reread_policy <class>: which readings a person's decision about this park would change, and
# therefore the only ones whose change may end it.
#
# The park's class is the question the person was asked, so it is also the answer's shape. A refused
# model is answered by a model and by nothing else; an ended ladder is answered by new instructions,
# which are the brief or the work plan the lane runs from; a blocked lane is answered by its
# blocker's row as well; a close-out that could not finish is answered by the `done` a person writes
# when they finish it by hand. Hashing everything a park could conceivably read made any of those
# answers look like all of them: a peer session correcting an unrelated downstream row released a
# `model_not_found` park and redispatched the same refused model under a message claiming the Model
# cell had been edited (D-134, measured).
class_reread_policy() {
  case "$1" in
    model_not_found)          echo effective-model ;;
    blocked)                  echo blocker-and-instructions ;;
    merge-failed|main-broken) echo close-out-status ;;
    *)                        echo instructions ;;
  esac
}

# policy_fields <policy>: the hash fields that policy designates, as a JSON array. These and no
# others are compared; the receipt's own wrapper is interpretation and never evidence, and a field
# that appears in a receipt without being designated is read by nothing.
policy_fields() {
  case "$1" in
    effective-model)          echo '["model_sha256"]' ;;
    blocker-and-instructions) echo '["brief_sha256","work_plan_sha256","blocker_sha256"]' ;;
    close-out-status)         echo '["status_sha256"]' ;;
    *)                        echo '["brief_sha256","work_plan_sha256"]' ;;
  esac
}

# reread_project <plan json> <milestone> <blocker> <what>: one projection of the parsed plan, as
# canonical JSON, or nothing when the plan does not hold it.
#
# `model` and `status` are the milestone's own cells as the parse resolved them — `model` is the
# effective model, an alias already expanded through `config.json`, so renaming an alias to a
# different model is the decision it really is. `blocker` is the row the carries names, and its
# `Status` is what releases a `blocked` lane.
#
# `work_plan` is the lane's own execution fields and dependencies, plus the ids and dependency edges
# of every milestone downstream of it — enough to recognise a split, which adds a row that names
# this one. It excludes row position and it excludes `Status`: a row moving and a sibling's
# bookkeeping are not decisions about this lane, and the downstream rows contribute their edges
# alone, never their own `Model` or `Effort`, because a peer's model is the peer's business. The
# downstream list is sorted by id for the same reason the row number is dropped — where a row sits
# is not what it says.
reread_project() {
  printf '%s' "$1" | jq -c --arg m "$2" --arg b "$3" --arg w "$4" '
    (.milestones // []) as $ms
    | ($ms | map(select(.id == $m)) | first) as $self
    | if $w == "model"  then (if $self == null then empty else $self.model end)
      elif $w == "status" then (if $self == null then empty else $self.status end)
      elif $w == "blocker" then
        (if $b == "" then empty
         else ($ms | map(select(.id == $b)) | first) as $r
              | (if $r == null then empty else {id: $r.id, status: $r.status} end)
         end)
      else
        (if $self == null then empty
         else {self: {id: $self.id, depends: $self.depends, model: $self.model,
                      effort: $self.effort, remote: $self.remote},
               downstream: ([ $ms[] | select(.id != $m and ((.depends // []) | index($m)) != null)
                              | {id: .id, depends: .depends} ] | sort_by(.id))}
         end)
      end' 2>/dev/null
}

# reread_hashes <project> <milestone> <class> <carries json> [<plan json>]: the readings a decision
# about this park would change, hashed as they stand now, as an explicitly versioned receipt:
#
#     {"version": 2, "policy": "effective-model", "hashes": {"model_sha256": "…"}}
#
# The plan is the tick's own parsed document when the caller holds one, and read afresh when not.
# The version and the policy say how to read the hashes and are never themselves evidence: a
# comparison over the wrapper would make an upgrade look like a person, which is the whole defect
# this shape exists to close.
#
# **The brief through `git show main:`**, which is how a dispatch reads it (`prompt_from_brief`).
# An uncommitted edit is not one a session would ever receive, so it is not one that should unpark
# a lane: the person's edit becomes real when it is committed, and that is the same moment for both
# halves of Baton. It is read only for a policy that designates it.
#
# A reading that fails is absent rather than empty, the envelope's rule: a plan file that cannot be
# read parks the project on its own account. Absence is a distinct state: a brief first becoming
# readable on main is an edit, while a reading becoming unavailable does not release a park. A
# receipt with no reading at all is `{}`, and `escalate` then attaches none.
reread_hashes() {
  rrh_h='{}'
  [ -n "$2" ] || { echo '{}'; return 0; }
  rrh_policy=$(class_reread_policy "$3")
  rrh_want=$(policy_fields "$rrh_policy")
  rrh_doc=${5:-}
  [ -n "$rrh_doc" ] || rrh_doc=$(plan_of_project "$1" 2>/dev/null) || rrh_doc=''
  rrh_b=$(printf '%s' "${4:-"{}"}" | jq -r '.blocked_by // ""' 2>/dev/null || true)
  if [ -n "$rrh_doc" ]; then
    for rrh_f in $(printf '%s' "$rrh_want" | jq -r '.[] | select(. != "brief_sha256")'); do
      case "$rrh_f" in
        model_sha256)     rrh_v=$(reread_project "$rrh_doc" "$2" "$rrh_b" model) ;;
        status_sha256)    rrh_v=$(reread_project "$rrh_doc" "$2" "$rrh_b" status) ;;
        blocker_sha256)   rrh_v=$(reread_project "$rrh_doc" "$2" "$rrh_b" blocker) ;;
        *)                rrh_v=$(reread_project "$rrh_doc" "$2" "$rrh_b" work_plan) ;;
      esac
      [ -n "$rrh_v" ] || continue
      rrh_h=$(printf '%s' "$rrh_h" | jq -c --arg k "$rrh_f" \
        --arg v "$(printf '%s' "$rrh_v" | shasum -a 256 | awk '{ print $1 }')" '. + {($k): $v}')
    done
  fi
  if printf '%s' "$rrh_want" | jq -e 'index("brief_sha256") != null' > /dev/null \
     && rrh_path=$(project_path "$1" 2>/dev/null) \
     && rrh_text=$(prompt_from_brief "$rrh_path" "docs/milestones/$2.md" "Copy-ready session prompt" 2>/dev/null); then
    rrh_h=$(printf '%s' "$rrh_h" | jq -c \
      --arg v "$(printf '%s' "$rrh_text" | shasum -a 256 | awk '{ print $1 }')" '. + {brief_sha256: $v}')
  fi
  [ "$(printf '%s' "$rrh_h" | jq length)" -gt 0 ] || { echo '{}'; return 0; }
  jq -nc --arg p "$rrh_policy" --argjson h "$rrh_h" '{version: 2, policy: $p, hashes: $h}'
}

# reread_changed <was json> <now json> <fields json>: the designated readings that have changed —
# newly present, or present in both and different.
#
# Newly present counts, and that half is load-bearing: a brief that was unreadable when the lane
# parked and reads now is the person's edit arriving, not a missing key. Absent now cannot count,
# for the mirror reason: a plan file that has become unreadable parks the project on its own account
# and must not also unpark every lane waiting on it. Only the designated fields are looked at, so a
# key the receipt happens to carry from an older policy is neither compared nor missed.
reread_changed() {
  jq -nc --argjson was "$1" --argjson now "$2" --argjson want "$3" \
    '[ $want[] as $k | select(($now | has($k)) and (($was | has($k) | not) or $now[$k] != $was[$k])) | $k ]'
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
  pac_log=$(log_json) || { render_failure err "$pac_log"; return 1; }
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
    *) render_failure err "escalate: \"$esc_scope\" is not a scope; it is lane or project"; return 1 ;;
  esac
  # The hashes go on a lane park when an edit is a way out of its class — or when no ruling can
  # reach the lane, whatever its class. A ruling is delivered by resuming a session Baton dispatched
  # (`ruling_target`), so a park without one has no ruling route at all: a rejected artifact whose
  # lane Baton never dispatched, an `eligible[]` entry dropped for a brief pointer that is not on
  # main. Without this such a park would have no way out whatsoever, and a park nothing can resolve
  # holds its milestone out of every dispatch for as long as Baton runs. A project park is given them
  # only when it names a milestone whose `done` ends it (`main-broken`): the self-check's parks are
  # re-read every tick and `park_resolve` closes them.
  if { [ "$esc_scope" = lane ] && [ -n "$1" ] \
       && { class_unparks_by_edit "$esc_class" || [ -z "$(ruling_target "$1" "$3" "$4")" ]; }; } \
     || { [ -n "$1" ] && [ -n "$2" ] && class_ends_on_done "$esc_class"; }; then
    # The class is what the person was asked, so it is what decides which readings can answer. It is
    # passed rather than inferred from the carries: it is an argument here and a top-level field on
    # the event, and a reader that guessed it from the carries would be a second taxonomy (D-119).
    esc_reread=$(reread_hashes "$1" "$2" "$esc_class" "$esc_carries") || esc_reread='{}'
    # For the two classes a `done` written by hand ends, the cell as it reads now is part of the
    # record, because "written after the park" is the whole of that rule and a hash cannot say which
    # cell changed. It sits beside the hashes rather than among them: it is the literal the rule
    # tests, not a reading whose change releases anything. Absent when the plan cannot be read, and
    # the resolution then refuses.
    if class_ends_on_done "$esc_class" \
       && printf '%s' "$esc_reread" | jq -e 'has("version")' > /dev/null 2>&1 \
       && esc_plan=$(plan_of_project "$1" 2>/dev/null) \
       && esc_row=$(printf '%s' "$esc_plan" | plan_row "$2" 2>/dev/null); then
      esc_reread=$(printf '%s' "$esc_reread" | jq -c --argjson row "$esc_row" '. + {status_at_park: $row.status}')
    fi
    esc_carries=$(printf '%s' "$esc_carries" | jq -c --argjson r "$esc_reread" \
      'if ($r | length) > 0 then . + {reread: $r} else . end')
  fi
  log_event escalation "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg c "$esc_class" --arg s "$esc_scope" --argjson carries "$esc_carries" \
       '{class: $c, scope: $s, carries: $carries, channel: ["notification"]}')" || return 1
  esc_msg=$(message_render "$1" "$2" "$esc_class" "$esc_carries" "$3" "$4")
  notify "$(printf '%s' "$esc_msg" | jq -r .address)" "$(printf '%s' "$esc_msg" | jq -r .body)" "$3"
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
    *) render_failure err "resolve: \"$6\" is not one of ruling, answered in place, edit"; return 1 ;;
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
# is made, so this takes the whole of it and lets `notify_line` cap what Notification Center would
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
  # The fork park first, because neither of the two routes below is its way out. A resume that forked
  # and could not prove its compensating stop landed leaves a process that may be running under a
  # session Baton no longer tracks (D-132): no plan or brief edit bears on that, and a ruling would be
  # delivered into the copy — a session that is running and has nothing wrong with it. The one act
  # that ends it is a person stopping the original, and the park carries which one. The park clears
  # itself once no row carries that session (`fork_resolve_check`), so the line says so and asks for
  # nothing else afterwards. Its class is the house `other`, which a rejection also uses, so the test
  # is the field and never the class.
  evb_orig=$(printf '%s' "$3" | jq -r '.original // empty' 2>/dev/null || true)
  if [ -n "$evb_orig" ]; then
    printf 'stop the original session %s by hand; the park clears itself once no row carries it' "$evb_orig"
    return 0
  fi
  # A ruling is delivered by resuming a session inside a lane, so a park that `ruling_target` calls
  # unreachable cannot be answered and must not print a command that would be refused. The edit is
  # its way out, and `escalate` gave it the hashes that make the edit visible.
  if [ -z "${4:-}" ]; then
    case "$1" in
      asking|question|other)
        printf 'fix what it names; the next tick re-reads the plan and the brief'
        return 0 ;;
      merge-failed)
        printf 'finish the close-out by hand and write done in the Status cell of %s; the next tick re-reads the plan' "$evb_m"
        return 0 ;;
      main-broken)
        printf 'fix main, finish the close-out by hand and write done in the Status cell of %s; the next tick re-reads the plan' "$evb_m"
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
      # Every dispatched session is on Remote Control (D-081) and a click on the message opens its
      # thread, so Claude.app is where the question is answered; the same words serve `status`.
      printf 'answer it in place in Claude.app, or baton answer %s "<ruling>"' "$evb_m" ;;
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
      printf 'fix main, then baton answer %s "main fixed; finish the close-out from step (c)"' "$evb_m" ;;
    dispatch-failed)
      printf 'fix what the %s stage names, then baton answer %s "<ruling>"' \
        "$(printf '%s' "$3" | jq -r '.stage // "failed"' 2>/dev/null || echo failed)" "$evb_m" ;;
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
# **The verb is never the part that gets cut.** `notify_line` caps the body at 250 code points
# because Notification Center truncates far shorter, and the verb is last — so a long detail would
# eat exactly the sentence that says what to do, which is the one part a person cannot reconstruct.
# The content is cut to what is left after the verb instead, in code points and by jq, for the same
# two reasons `notify_line` gives: this Mac's awk counts bytes, and a cut applied after escaping can
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
  # `main-broken` is the one ending whose scope is the project: what failed is the combined tree on
  # `main`, which every lane of the project stands on, not the session that found it (REQ-ESC-04).
  end_scope=lane
  [ "$end_class" != main-broken ] || end_scope=project
  case "$end_class" in
    asking)
      end_carries=$(asking_carries "$5" 2>/dev/null) || end_carries='' ;;
    *)
      end_detail=$(artifact_detail "$7")
      [ -n "$end_detail" ] || end_detail="the session gave no detail"
      case "$end_class" in
        merge-failed) end_detail="the merge into main failed: $end_detail" ;;
        main-broken)  end_detail="the standing check failed on main after the merge: $end_detail" ;;
        *)            end_detail="the session stopped: $end_detail" ;;
      esac
      end_carries=$(jq -nc --arg d "$end_detail" --arg a "$7" '{detail: $d, archive: $a}') ;;
  esac
  if [ -n "$end_carries" ] && escalate "$1" "$2" "$3" "$4" "$end_class" "$end_scope" "$end_carries"; then
    return 0
  fi
  render_failure err "baton: $1/$2 the $end_class park did not fit its full carries; parking it with a pointer to $7"
  escalate "$1" "$2" "$3" "$4" "$end_class" "$end_scope" \
    "$(jq -nc --arg a "$7" '{detail: "the session stopped with words Baton could not carry whole; they are in the archived artifact", archive: $a}')"
}

# reread_baseline_of <project> <milestone> <escalation at>: the baseline already appended for that
# park — `{found: <how many>, hashes: {…}}`. The count is printed rather than swallowed because two
# baselines for one park are a state nothing can read, and guessing between them would be the same
# mistake as guessing a person's intent from a hash.
reread_baseline_of() {
  rbo_log=$(log_json) || { echo "$rbo_log"; return 1; }
  printf '%s' "$rbo_log" | jq -c --arg p "$1" --arg m "$2" --arg at "$3" '
    [ .[] | select(.kind == "reread_baseline" and .project == $p and .milestone == $m
                   and .escalation_at == $at) ] as $b
    | {found: ($b | length), hashes: ($b | last | .hashes // {})}'
}

# edit_reread_check <project> <plan json> [<rows json>]: REQ-ESC-05's third route, and the one only the tick can
# see, because only the tick re-reads. For every parked lane carrying a receipt, the readings its own
# class designates — from the plan the tick has already parsed, and the brief on `main` — are read
# again and compared against the receipt; a difference is the person's decision arriving, and the
# lane unparks without a second command.
#
# **Only the designated readings.** The receipt names a policy and the policy names its fields, and
# nothing outside them is compared — not the wrapper, and not a key some earlier policy left behind.
# That is the whole of D-134: a park is released by an answer to the question it asked, so a peer's
# close-out writing `done` in its own cell, or correcting a downstream row, is no longer a decision
# about this lane.
#
# **A v1 receipt cannot be converted, so it is rebaselined.** Its `plan_rows_sha256` is a digest of
# rows that no longer exist as a unit, and the old underlying values are gone; `carries.model` is the
# model the attempt asked for, not the one the cell held, so substituting it would invent evidence.
# What a v1 receipt does still say is kept — its exact brief digest, and `status_at_park` — and those
# are compared first, so the brief-only release and a brief that first became readable both still
# work without waiting for anything. Only when they say nothing is one `reread_baseline` event
# appended, carrying today's readings for the fields v1 never held, and the park stands that tick.
# The cost is said out loud on the line: an edit made before the upgrade may no longer be provable.
# An unknown version, two baselines for one park, a reading that will not come, or an append that
# fails all leave the park exactly as it was — the upgrade itself must never be what frees a lane.
#
# The unpark is written before step 4 runs, so the rule that parked the lane gets the same tick to
# act on the edit: a `blocked` lane whose blocker now reads `done` is redispatched a second later
# rather than a minute later, and a refused model or an ended ladder is redispatched rather than
# parked again (`person_acted`).
edit_reread_check() {
  err_parked=$(derive_parked "$1") || { render_failure err "$err_parked"; return 1; }
  err_list=$(printf '%s' "$err_parked" | jq -c '[ .parked[] | select(.carries.reread != null) ]')
  err_n=$(printf '%s' "$err_list" | jq length); err_i=0
  while [ "$err_i" -lt "$err_n" ]; do
    err_e=$(printf '%s' "$err_list" | jq -c ".[$err_i]"); err_i=$((err_i + 1))
    err_m=$(printf '%s' "$err_e" | jq -r '.milestone // ""')
    err_class=$(printf '%s' "$err_e" | jq -r '.class // ""')
    err_at=$(printf '%s' "$err_e" | jq -r .at)
    err_receipt=$(printf '%s' "$err_e" | jq -c .carries.reread)
    err_v=$(printf '%s' "$err_receipt" | jq -r '.version // 1')
    case "$err_v" in
      1|2) ;;
      *) render_failure err "baton: $1/$err_m the park raised at $err_at carries a re-read receipt of version $err_v, which this relay cannot read; the park stands"
         continue ;;
    esac
    err_want=$(policy_fields "$(class_reread_policy "$err_class")")
    err_now=$(reread_hashes "$1" "$err_m" "$err_class" "$(printf '%s' "$err_e" | jq -c .carries)" "${2:-}")
    err_now=$(printf '%s' "$err_now" | jq -c '.hashes // {}')
    if [ "$err_v" = 2 ]; then
      err_changed=$(reread_changed "$(printf '%s' "$err_receipt" | jq -c '.hashes // {}')" "$err_now" "$err_want")
    else
      # What a v1 receipt still speaks for: the brief digest it wrote under the same rule, and the
      # Status cell it recorded as a literal. Its absence is evidence too — v1 wrote the brief digest
      # whenever the brief read — so a newly readable brief still releases the park.
      err_was=$(printf '%s' "$err_receipt" | jq -c \
        'if has("brief_sha256") then {brief_sha256: .brief_sha256} else {} end')
      if printf '%s' "$err_receipt" | jq -e 'has("status_at_park")' > /dev/null 2>&1; then
        # Hashed the way `reread_project` hashes it — the JSON value, not the bare text — so the two
        # readings are comparable at all.
        err_was=$(printf '%s' "$err_was" | jq -c --arg v "$(printf '%s' \
          "$(printf '%s' "$err_receipt" | jq -c .status_at_park)" | shasum -a 256 | awk '{ print $1 }')" \
          '. + {status_sha256: $v}')
      fi
      err_changed=$(reread_changed "$err_was" "$err_now" \
        "$(printf '%s' "$err_want" | jq -c '[ .[] | select(. == "brief_sha256" or . == "status_sha256") ]')")
      err_rest=$(printf '%s' "$err_want" | jq -c '[ .[] | select(. != "brief_sha256" and . != "status_sha256") ]')
      if [ "$(printf '%s' "$err_changed" | jq length)" -eq 0 ] \
         && [ "$(printf '%s' "$err_rest" | jq length)" -gt 0 ]; then
        err_base=$(reread_baseline_of "$1" "$err_m" "$err_at") || { render_failure err "$err_base"; return 1; }
        if [ "$(printf '%s' "$err_base" | jq -r .found)" -gt 1 ]; then
          render_failure err "baton: $1/$err_m more than one re-read baseline names the park raised at $err_at; the park stands"
          continue
        elif [ "$(printf '%s' "$err_base" | jq -r .found)" -eq 0 ]; then
          err_new=$(printf '%s' "$err_now" | jq -c --argjson want "$err_rest" \
            '. as $n | reduce $want[] as $k ({}; if $n | has($k) then . + {($k): $n[$k]} else . end)')
          if [ "$(printf '%s' "$err_new" | jq length)" -ne "$(printf '%s' "$err_rest" | jq length)" ]; then
            render_failure err "baton: $1/$err_m the re-read baseline for the park raised at $err_at needs a reading the plan does not give; the park stands"
            continue
          fi
          log_event reread_baseline "$1" "$err_m" "$(printf '%s' "$err_e" | jq -r '.session // ""')" \
            "$(printf '%s' "$err_e" | jq -r '.attempt // ""')" \
            "$(jq -nc --arg a "$err_at" --arg p "$(class_reread_policy "$err_class")" --argjson h "$err_new" \
               '{escalation_at: $a, version: 2, policy: $p, hashes: $h}')" \
            || { render_failure err "baton: $1/$err_m the re-read baseline for the park raised at $err_at could not be written; the park stands"; continue; }
          render_row out record 'rebased   %s/%s · the %s park predates the %s policy, so its plan evidence is taken afresh · the park stands and an edit made before now cannot be proved\n' \
            "$(render_token out lane "$1")" "$(render_token out milestone "$err_m")" "$err_class" "$(class_reread_policy "$err_class")"
          continue
        fi
        err_changed=$(reread_changed "$(jq -nc --argjson a "$err_was" \
          --argjson b "$(printf '%s' "$err_base" | jq -c .hashes)" '$a + $b')" "$err_now" "$err_want")
      fi
    fi
    [ "$(printf '%s' "$err_changed" | jq length)" -gt 0 ] || continue
    # A park whose way out is the close-out done by hand ends on the milestone's own `Status` cell
    # reading `done`, and on nothing else (`class_ends_on_done`).
    if class_ends_on_done "$err_class"; then
      printf '%s' "$err_changed" | jq -e 'index("status_sha256") != null' > /dev/null || continue
      # `done` already there at the park is a close-out that wrote it a step early, not one finished
      # by hand; a park recorded without the cell cannot tell, so it waits for its ruling.
      printf '%s' "$err_e" | jq -e '(.carries.reread | has("status_at_park")) and .carries.reread.status_at_park != "done"' \
        > /dev/null 2>&1 || continue
      err_plan=${2:-}
      [ -n "$err_plan" ] || err_plan=$(plan_of_project "$1" 2>/dev/null) || continue
      [ "$(printf '%s' "$err_plan" | plan_row "$err_m" 2>/dev/null | jq -r '.status // ""')" = done ] || continue
    fi
    # What changed, named as what it is. A hash says a reading differs and never who made it differ,
    # so the line reports the reading and leaves authorship to the person who knows.
    err_what=$(printf '%s' "$err_changed" | jq -r \
      'map(if . == "model_sha256" then "the effective model"
           elif . == "work_plan_sha256" then "the work plan it answers to"
           elif . == "blocker_sha256" then "the row of the blocker it names"
           elif . == "status_sha256" then "its Status cell"
           else "the brief" end) | join(" and ")')
    resolve "$1" "$err_m" "$(printf '%s' "$err_e" | jq -r '.session // ""')" \
      "$(printf '%s' "$err_e" | jq -r '.attempt // ""')" "$err_at" edit \
      || { render_failure err "baton: $1/$err_m the unpark of the park raised at $err_at could not be written"; continue; }
    render_row out record 'unparked  %s/%s · %s changed since the %s park · Baton acts on the lane again\n' \
      "$(render_token out lane "$1")" "$(render_token out milestone "$err_m")" "$err_what" "$err_class"
    # A close-out done by hand leaves the session that stopped before it idle and still live: nothing
    # Baton does ends that process — only an `asking` consume stops a session — and while its row has a
    # pid its lane counts against the cap. The person who just finished its work is told which job it
    # is, once, on the line they read.
    if class_ends_on_done "$err_class" && [ -n "${3:-}" ]; then
      err_job=$(job_of_session "$3" "$(printf '%s' "$err_e" | jq -r '.session // ""')")
      [ -z "$err_job" ] || render_row out action 'idle      %s/%s · its session is still live as job %s and counts against the cap until it ends: %s\n' \
        "$(render_token out lane "$1")" "$(render_token out milestone "$err_m")" "$(render_token out session "$err_job")" "$(render_hint out "claude stop $err_job")"
    fi
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
  qrc_parked=$(derive_parked "$1") || { render_failure err "$qrc_parked"; return 1; }
  qrc_list=$(printf '%s' "$qrc_parked" | jq -c '[ .parked[] | select(.class == "question") ]')
  [ "$(printf '%s' "$qrc_list" | jq length)" -gt 0 ] || return 0
  qrc_log=$(log_json) || { render_failure err "$qrc_log"; return 1; }
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
      render_row out record 'unparked  %s/%s · %s · the session wrote its own handover after the question, so it was answered in place\n' \
        "$(render_token out lane "$1")" "$(render_token out milestone "$qrc_m")" \
        "$(render_token out session "$qrc_s")"
      continue
    fi
    qrc_row=$(printf '%s' "$2" | jq -c --arg s "$qrc_s" \
      'map(select(.sessionId == $s and .pid != null)) | first // {}')
    if [ "$(printf '%s' "$qrc_row" | jq 'length')" -gt 0 ]; then
      [ "$(printf '%s' "$qrc_row" | jq -r '.waitingFor // ""')" != "input needed" ] || continue
      resolve "$1" "$qrc_m" "$qrc_s" "$qrc_a" "$qrc_at" "answered in place"
      render_row out record 'unparked  %s/%s · %s · the question was answered in place\n' "$(render_token out lane "$1")" "$(render_token out milestone "$qrc_m")" "$(render_token out session "$qrc_s")"
      continue
    fi
    # No live row: the session is stopped and the row transition can no longer unpark the lane.
    # Once per park, keyed on the escalation's own `at`, because a second park is a second question.
    qrc_spent=$(derive_key_spent "$1" "$qrc_m" "${qrc_a:-0}" prompt-lost "$qrc_at") \
      || { render_failure err "$qrc_spent"; return 1; }
    [ "$(printf '%s' "$qrc_spent" | jq -r .spent)" = false ] || continue
    # A notification's body is its detail alone — the three-part message with its verb last belongs
    # to a park — so the command goes in the sentence. This one is worth the words: the person is
    # being told that the way they would have answered is gone, and the way that is left is a verb.
    qrc_detail="the session stopped while the question was open, so answering it in the session can no longer unpark the lane; the call can still be answered on the resume, with baton answer $qrc_m \"<ruling>\""
    notification_write "$1" "$qrc_m" "$qrc_s" "$qrc_a" prompt-lost "$qrc_at" \
      "$(jq -nc --arg a "$qrc_at" --arg d "$qrc_detail" '{asked_at: $a, detail: $d}')"
    render_row out action 'prompt    %s/%s · %s · the question outlived its session; only a ruling reaches it now\n' \
      "$(render_token out lane "$1")" "$(render_token out milestone "$qrc_m")" "$(render_token out session "$qrc_s")"
  done
}

# fork_resolve_check <project> <rows json>: the route out of a park that needs no person at all,
# because its condition ends on its own.
#
# `resume_session` parks a lane when a resume forked and the compensating stop could not be proved to
# have landed: a process may still be running under a session `copy_fork` has already moved every
# derivation off, so nothing tracks it (D-132). That worry is about a process, and a process ends.
# The moment no row carries the original with a pid there is nothing left for a person to do, and a
# park that cannot end is a milestone held out of every dispatch and a lane `derive_gap` counts open
# for as long as Baton runs (lib/derive.sh:499-501).
#
# **Filtered by the field, not only by the class.** `escalate_rejection` writes the same shape —
# `other`, lane scope, no `reread` — for every rejected artifact (lib/inbox.sh:218-221), and a
# rejection's condition does not end by itself: a file was rejected and a person must decide
# something, so ruling-only is correct there and this must never touch it. `carries.original` is what
# tells the two apart, and a rejection has no such field.
#
# **The copy completing is not the test.** It is evidence about the copy and says nothing about
# whether the original process died; releasing a park on an act independent of its condition is the
# defect class D-134 exists to close. The rows are the only witness, and they are asked directly.
fork_resolve_check() {
  [ -n "${2:-}" ] || return 0
  frc_parked=$(derive_parked "$1") || { render_failure err "$frc_parked"; return 1; }
  frc_list=$(printf '%s' "$frc_parked" | jq -c \
    '[ .parked[] | select(.class == "other" and .scope == "lane" and (.carries.original // "") != "") ]')
  frc_n=$(printf '%s' "$frc_list" | jq length); frc_i=0
  while [ "$frc_i" -lt "$frc_n" ]; do
    frc_e=$(printf '%s' "$frc_list" | jq -c ".[$frc_i]"); frc_i=$((frc_i + 1))
    frc_o=$(printf '%s' "$frc_e" | jq -r .carries.original)
    # A row with a pid is the worry still standing. A listing read as empty is a listing: it says the
    # session is gone. A listing that could not be read never reaches here, because the tick fails on
    # it before step 3.
    if printf '%s' "$2" | jq -e --arg s "$frc_o" 'any(.[]; .sessionId == $s and .pid != null)' \
       > /dev/null 2>&1; then
      continue
    fi
    frc_m=$(printf '%s' "$frc_e" | jq -r '.milestone // ""')
    resolve "$1" "$frc_m" "$(printf '%s' "$frc_e" | jq -r '.session // ""')" \
      "$(printf '%s' "$frc_e" | jq -r '.attempt // ""')" "$(printf '%s' "$frc_e" | jq -r .at)" edit \
      || { render_failure err "baton: $1/$frc_m the unpark of the fork park naming $frc_o could not be written"; continue; }
    render_row out record 'unparked  %s/%s · no row carries the unstopped original %s any more · Baton acts on the lane again\n' \
      "$(render_token out lane "$1")" "$(render_token out milestone "$frc_m")" "$(render_token out session "$frc_o")"
  done
}
