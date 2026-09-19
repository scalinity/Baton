#!/bin/sh
# lib/disposition.sh — what a condition needs from outside Baton, and the record that asks for
# nothing.
#
# `lib/escalate.sh` and `lib/notify.sh` answer "how does this reach the person". This answers the
# question underneath it — whether it should — and it is the first file in Baton that treats the two
# as separable. Every class in `class_or_fail`'s two lists is assigned here, and a class neither list
# holds is refused rather than defaulted, so the mapping is exhaustive by construction and not by a
# document anybody has to keep up to date (REQ-ESC-12).
#
# Two clauses come before the four dispositions, because both decide whether a condition reaches the
# table at all.
#
#   1. **Re-read before you route.** A condition Baton can read for itself needs nothing from
#      outside, so it is re-read and closed rather than routed. `park_resolve` does this for the
#      self-check's parks, `edit_reread_check` for the classes an edit answers,
#      `question_resolve_check` for a question answered in place, `fork_resolve_check` for a copy
#      whose original has ended, and `planning_pass` for a `dispatch-failed` park on the planning
#      lane whose preconditions read clean again (D-169). `rejection_resolve_check` below is the
#      sixth, and it exists because it was the one park with no such route at all (limitation 33).
#
#   2. **A repair already asked for spends no new class.** D-167 settled one instance of this — the
#      generation bound records `plan_generation` with outcome `exhausted` and leaves the standing
#      `plan-unreadable` park to reach the person, because that park's repair *is* this one's
#      repair — and asked M15 whether it is the general rule. It is. REQ-ESC-04 fixes the class
#      list, and a class earns its place by needing a verb of its own, a `status` line and an
#      `answer` route; a condition that adds no new act for the person adds no new class, it adds an
#      event under the park that already asked for that act. The exception is a condition whose
#      repair is the same but whose *scope* differs, and scope is already its own field on the event
#      rather than a property of the class (REQ-ESC-04), so it needs no class either.
#
# The four dispositions, which partition what survives those two clauses:
#
#   * `AI-resolvable` — the whole of what resolves it is inside the project's own record, so a
#     session holding that record could decide it without a person. Only `asking` with options
#     carries it, for the reason given at that arm.
#   * `human-required` — a person is the one who resolves it, or the one whose plans it changes.
#     Credentials, access grants and facts about the world outside the repository are always this,
#     and so is a question Baton cannot read the text of.
#   * `replan` — what is wrong is the plan itself, so the answer is a plan and not a ruling.
#   * `HOST-EXPLAINED` — the condition is real, correctly detected, fully explained by something
#     Baton can point to, and carries no act for anyone, because it was already over when it was
#     recorded. Record the event; send no message.
#
# **A disposition is not a delivery.** This file says what a condition needs; what each producer
# does today is the producers' own, and the two are deliberately allowed to differ while a
# successor closes the gap. Only one delivery changes with this file — `baton-unhealthy`, whose own
# verb already reads "nothing to do; Baton cleared it and carried on" — because a table that
# described nothing measurable would be the rule-stated-but-not-measured drift D-171 exists to
# avoid, and that is the one condition whose disposition can be honoured without new evidence.
# `gap` is the other HOST-EXPLAINED candidate and is deliberately *not* assigned it here: a gap is
# over when it is reported, but it is not yet explained, and the evidence that would explain it is
# M15-b's to gather. An unexplained gap reaches a person.
set -eu

# disposition_of <kind> <class> [<carries json>]: the table. Prints one of the four words; status 1
# for a class neither of `class_or_fail`'s lists holds, which is the same refusal for the same
# reason — a class outside them is a typo, and a typo that defaulted to `human-required` would park
# a lane under a state no verb clears.
#
# The carries is read by exactly one arm and is optional everywhere else. That is a deliberate
# bound: a disposition read out of a session's own prose would be a second taxonomy, and D-119
# already settled that the class is passed rather than inferred from the carries. The one exception
# is a discrimination the codebase already makes for its own reasons, named at the arm that makes it.
disposition_of() {
  dof_carries=${3:-}
  case "$1:$2" in
    # A session that asked with options enumerated the readings it was choosing between and marked
    # the one it recommends; the set is closed, and everything needed to choose inside it is the
    # brief and the code the session was reading. `escalation_verb` already branches on exactly this
    # to print `baton answer <M> <n>` rather than `baton answer <M> "<ruling>"`, and `answer_options`
    # expands the number from the archived artifact — so the bounded case is one Baton already
    # handles as bounded. Nothing here routes it yet: the second judgment role that would answer it
    # is `docs/milestones/M15-d.md`'s, and until it lands such a park reaches a person like any
    # other. The disposition is recorded ahead of the route on purpose, because the route has to
    # know which parks are its own before it can be written.
    escalation:asking)
      if [ -n "$dof_carries" ] \
         && printf '%s' "$dof_carries" | jq -e '((.options // []) | if type == "array" then . else [.] end | length) > 0' \
              > /dev/null 2>&1; then
        echo AI-resolvable
      else
        # No options is an open question, and an open question may be asking for a credential. The
        # class cannot tell, so the person the session chose to ask is who it goes to.
        echo human-required
      fi ;;

    # The row says a session is waiting for input and nothing more: `question_check`'s own carries
    # records that "no payload carries the question, so it can only be read in the session". A
    # disposition cannot be made about text Baton has never seen.
    escalation:question) echo human-required ;;

    # Three failure endings in a row with no artifact between them. What is wrong is the environment
    # or the instructions, and neither is in the record the lane failed to produce — the ladder has
    # already spent the two remedies that use only what Baton holds.
    escalation:ladder-end) echo human-required ;;

    # The session came back twice saying the milestone does not fit one session, and carried both
    # splits it proposed (`splits_carries`). That is the plan's sizing being wrong rather than any
    # run of it, and `escalation_verb` says as much already: "edit the plan; a split is a plan edit".
    escalation:unfinished-twice) echo replan ;;

    # This class is raised only on the arm where the named blocker is one the plan "neither holds nor
    # makes eligible nor shows in flight" — nothing is coming to unblock it. A graph with an edge
    # into a milestone that can never complete is a defect in the graph. The other two arms of
    # `declared_step` never reach here: a `done` blocker redispatches and a live one notifies
    # `blocked_by`.
    escalation:blocked) echo replan ;;

    # A merge conflict is in a working tree, between two branches Baton created but whose contents it
    # has no reading of. The close-out is also the one step whose evidence Baton refuses to take from
    # a session (CONTRACT clause 4), so a judgement about whether the merge is right is exactly the
    # judgement that may not be self-reported.
    escalation:merge-failed) echo human-required ;;

    # `other` is the house class and has four producers — a rejected artifact, a fork whose original
    # could not be proved stopped, a session's own `stopped` with reason `other`, and a transcript
    # that cannot be scanned. They are one disposition, so the carries is not read: each names a
    # thing outside Baton's reading — a file, a process, a sentence a session wrote, an unreadable
    # transcript — and a person is the one who can look at it.
    escalation:other) echo human-required ;;

    # Both end themselves the tick their condition stops holding (D-071), which is clause 1 at work.
    # While one stands it is a difference between what a session said and what the plan says, and the
    # plan is the person's document.
    escalation:disagreement|escalation:omitted) echo human-required ;;

    # Which models exist is a fact about the account and the CLI, outside every repository.
    escalation:model_not_found) echo human-required ;;

    # The stage names a checkout, a brief that is not on `main`, a worktree or a permission rail.
    # On the planning lane the same park is released by the pass that would re-fail on it once the
    # condition reads clean (D-169) — clause 1 again, and not a different disposition: a person still
    # repairs what the stage named.
    escalation:dispatch-failed) echo human-required ;;

    # A plan file that cannot be read or parsed. For a project whose registration owes a plan,
    # generation attempts it first and is bounded by `planningAttempts`; that attempt is a resolution
    # path under this same park and spends no class of its own (D-167, clause 2 above). When the
    # attempts are spent, or when the project never owed a plan, the repair is the one the park
    # already named.
    escalation:plan-unreadable|escalation:plan-unparseable) echo human-required ;;

    # `main` does not pass the project's own standing check. Every lane of the project is standing on
    # it, and the fix is in the code.
    escalation:main-broken) echo human-required ;;

    # The one HOST-EXPLAINED arm, and the only delivery this file changes. Its single writer is the
    # stale-lock break, which has already done the one thing there was to do: `tick_run` escalates
    # it, prints it and resolves it in the same breath, so the park never outlives the tick that
    # raised it. `escalation_verb` has said "nothing to do; Baton cleared it and carried on" since
    # M05. Real, correctly detected, explained by Baton's own act, over before it was written, and
    # carrying nothing for anyone to do.
    escalation:baton-unhealthy) echo HOST-EXPLAINED ;;

    # The notifications. Every one of them is `human-required`, and that is a finding rather than a
    # default: a notification is by definition a message Baton keeps working past (REQ-ESC-01), so
    # the channel was already filtered once for actionability before this table existed. What is left
    # either asks for a decision — a usage limit the person may re-steer around, a billing error, a
    # stall, a session running six hours — or changes what the person expects of the night, which is
    # the other half of `human-required`. `blocked_by` and `distant_wait_for` are the two that come
    # closest to the fourth disposition, and they miss it on "already over": both describe a wait
    # that is still running, and the person's view of why nothing is happening is the whole reason
    # each is sent once.
    #
    # `gap` is the class the fourth disposition was named for and it stays here. A gap is over when
    # it is reported, but "over" is only half of HOST-EXPLAINED: nothing yet explains it. D-174
    # already narrowed the class to mean exactly "Baton was not running", by measuring from the clock
    # the tick started with, so a stretch the tick spent working under its own lock is not a gap at
    # all rather than a gap Baton chose not to send. That definition is inherited rather than
    # re-opened here, and it is the right one for this table: it makes the class a statement about
    # the relay's liveness with no cause attached, which is what leaves room for `docs/milestones/
    # M15-b.md` to attach one. An unexplained gap reaches a person — unloaded launchd, a stuck lock
    # or a crashing tick are what it can also mean.
    notification:rate_limit|notification:billing_error|notification:unrecoverable) echo human-required ;;
    notification:transient|notification:stall|notification:long-running) echo human-required ;;
    notification:blocked_by|notification:distant_wait_for|notification:prompt-lost) echo human-required ;;
    notification:gap|notification:takeover-silent) echo human-required ;;

    *) render_failure err "disposition_of: \"$2\" is not one of the $1 classes"; return 1 ;;
  esac
}

# disposition_notifies <disposition>: whether a condition carrying it reaches the Mac. Derived and
# never a second opinion — `HOST-EXPLAINED` is the disposition that means "no act exists", and a
# message with no act is the one this milestone exists to stop sending. Status 1 for anything that
# is not one of the four, so a caller that passed a class where a disposition belongs fails here
# rather than falling through to a silent write.
disposition_notifies() {
  case "$1" in
    HOST-EXPLAINED) return 1 ;;
    AI-resolvable|human-required|replan) return 0 ;;
    *) render_failure err "disposition_notifies: \"$1\" is not a disposition"; return 2 ;;
  esac
}

# record_only <project> <milestone> <session> <attempt> <class> <scope> <carries json>: the silent
# record — the event a HOST-EXPLAINED condition leaves, and no Mac message. It takes `escalate`'s
# arguments in `escalate`'s order, because it is that function minus the message and a caller
# swapping one for the other should be reading a one-word diff.
#
# It is a sibling rather than a flag on `escalate`, and the two reasons are one reason from opposite
# ends. `escalate` and `notification_write` each guarantee that a message implies a record (D-057),
# which is why both write the event before raising the message; a flag that skipped the message would
# make that guarantee conditional on an argument, and the guarantee is what the whole channel rests
# on. From this end, a silent record is not a suppressed message — it is a different act, whose
# correctness is that nothing was asked of anybody, and a reader of the log has to be able to tell
# the two apart. `channel` is how: `["record"]` where a delivered one writes `["notification"]`. The
# field is already on the event (REQ-ESC-07) and nothing decides on it, so this costs no new shape
# and gives `status` and a person reading the log the distinction for free.
#
# **There is no notification arm, and that is the contract being honest about its own reach.** The
# fourth disposition was named for the `gap` notification, but no notification class carries it yet
# and none may until `docs/milestones/M15-b.md` can say which gaps the host explains — so an arm for
# one would be a branch no caller could reach and no fixture could exercise, which is the
# rule-stated-but-not-measured shape D-171 rejects. M15-b adds it beside this, in the milestone that
# can test it; what is settled here and will not move is how a silent record is written and what
# `channel` says about it.
#
# The guard is the point of the function. A class whose disposition is not HOST-EXPLAINED may not be
# written silently, whatever the caller believes, because the failure mode of this whole file is a
# condition that needed a person and got an event nobody will read. The disposition is asked of the
# table and never taken from the caller.
record_only() {
  rco_class=$5; rco_scope=$6; rco_carries=$7
  class_or_fail record_only escalation "$rco_class" || return 1
  fields_or_fail record_only "$rco_carries" || return 1
  case "$rco_scope" in
    lane|project) ;;
    *) render_failure err "record_only: \"$rco_scope\" is not a scope; it is lane or project"; return 1 ;;
  esac
  rco_d=$(disposition_of escalation "$rco_class" "$rco_carries") || return 1
  # Matched positively: only a 1 — HOST-EXPLAINED — goes on. `disposition_notifies` answers 0 for a
  # class that reaches a person and 2 for a word that is not a disposition at all, and a plain `if`
  # would read that 2 as "does not notify" and write the line. The wrong answer here is the one this
  # whole file exists to prevent, so the safe case is the one named rather than the one left over.
  rco_n=0; disposition_notifies "$rco_d" || rco_n=$?
  [ "$rco_n" -eq 1 ] || {
    render_failure err "record_only: $rco_class is $rco_d, which reaches a person; it cannot be recorded silently"
    return 1
  }
  log_event escalation "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg c "$rco_class" --arg s "$rco_scope" --argjson carries "$rco_carries" \
       '{class: $c, scope: $s, carries: $carries, channel: ["record"]}')"
}

# rejection_resolve_check: limitation 33's second half — the park a rejected artifact leaves when
# Baton cannot say which lane it belonged to, and the route out it has never had.
#
# `reject` recovers the project from the file, and failing that from the log by session
# (`lane_of_session`). When both come up empty the escalation is written with no project, no attempt
# and no ruling target, which costs it every route at once: `escalate` attaches no re-read receipt
# because there is no plan or brief to hash, `baton answer` cannot deliver a ruling into a lane Baton
# never dispatched, and `edit_reread_check` runs per registered project and so never visits a park
# that names none. The message it sends says "fix what it names; the next tick re-reads the plan and
# the brief", and for this park there is no plan and no brief — measured on `reject-unparseable`,
# whose expected log holds an escalation with no `project` key at all. The park then stands for as
# long as Baton runs, in `status`, counting as a parked lane, after the file has been dealt with.
#
# This is clause 1 applied to it. What the park named is a file at a path Baton itself chose, and
# whether that file is still there is a thing Baton reads rather than asks about; so is whether the
# session that wrote it has since had a handover acted on. Either is the problem being corrected,
# and neither needs the project the park has not got.
#
# It runs project-less, beside the stale lock's own resolution, because a park with no project is
# absent from every per-project pass by construction — which is the whole of why this park was the
# one with no route. It is deliberately narrow: only a lane-scope park with an empty project, which
# `escalate`'s callers make reachable from the rejection path alone. A rejection park that *does*
# name a project keeps the route it already has, since `escalate` gave it re-read hashes the moment
# `ruling_target` came back empty.
#
# Nothing here notifies. The park is closed with a `resolution` event and one line, and the line
# states a condition and offers no act — the shape `lock_stale_report` settled for a reading a person
# can do nothing about (D-174). A person who never sees the line loses nothing: what it reports is
# that something they already did has been noticed.
rejection_resolve_check() {
  rrc_parked=$(derive_parked "") || { render_failure err "$rrc_parked"; return 1; }
  rrc_list=$(printf '%s' "$rrc_parked" | jq -c '
    [ .parked[] | select(.scope == "lane" and (.project // "") == "" and (.carries.path // "") != "") ]')
  rrc_n=$(printf '%s' "$rrc_list" | jq length); rrc_i=0
  [ "$rrc_n" -gt 0 ] || return 0
  rrc_log=$(log_json) || { render_failure err "$rrc_log"; return 1; }
  while [ "$rrc_i" -lt "$rrc_n" ]; do
    rrc_e=$(printf '%s' "$rrc_list" | jq -c ".[$rrc_i]"); rrc_i=$((rrc_i + 1))
    rrc_at=$(printf '%s' "$rrc_e" | jq -r .at)
    rrc_path=$(printf '%s' "$rrc_e" | jq -r '.carries.path // ""')
    rrc_s=$(printf '%s' "$rrc_e" | jq -r '.session // ""')
    rrc_why=''
    # The file first, because it is the thing the park's own message names and the cheaper read.
    if [ ! -e "$rrc_path" ]; then
      rrc_why="the file it names is gone"
    elif [ -n "$rrc_s" ] && printf '%s' "$rrc_log" | jq -e --arg s "$rrc_s" --arg a "$rrc_at" '
           [ to_entries[] | {i: .key} + .value ] as $ev
           | ([ $ev[] | select(.kind == "escalation" and .at == $a) ] | last | .i // -1) as $park
           | any($ev[]; .kind == "consumed" and .session == $s and .i > $park)' > /dev/null 2>&1; then
      # The other correction: the session wrote an artifact Baton could read, and that handover has
      # been acted on. "Since" is **log order and not the timestamp**, which is the rule CONTRACT
      # clause 3(c) states for exactly this question and which `person_acted` and `derive_key_spent`
      # already follow: `at` carries an offset, so two events an hour apart in different zones sort
      # by their text the wrong way round, and a rejection is the case where that is likeliest —
      # the artifact came from a session whose clock Baton does not own. The park's index is found
      # from its `at`, which is its identity everywhere else.
      rrc_why="the session it names has had a handover consumed since"
    fi
    [ -n "$rrc_why" ] || continue
    resolve "" "$(printf '%s' "$rrc_e" | jq -r '.milestone // ""')" "$rrc_s" "" "$rrc_at" edit \
      || { render_failure err "baton: the rejection park raised at $rrc_at could not be resolved"; continue; }
    render_row out record 'settled   %s · the rejection park raised at %s is closed · %s\n' \
      "$(render_token out milestone "$(printf '%s' "$rrc_e" | jq -r '.milestone // "an unnamed milestone"')")" \
      "$(render_token out timestamp "$rrc_at")" "$rrc_why"
  done
}
