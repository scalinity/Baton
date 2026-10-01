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
# successor closes the gap. Two deliveries turn on it. `baton-unhealthy`, whose own verb already
# reads "nothing to do; Baton cleared it and carried on", is HOST-EXPLAINED by its class alone. The
# `gap` notification is HOST-EXPLAINED **per event and not per class**: M15 left it `human-required`
# because a gap was over when it was reported but nothing explained it, and `lib/host.sh` is the
# evidence that completes the other half. Asked about the class with no evidence the table still
# answers `human-required`, which is what a gap nothing accounts for really needs.
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
      # A lone value becomes a list of one, the coercion `asking_carries` already makes for a session
      # that wrote a string where the contract says a list — but only a value that is an option.
      # `""`, `0` and `{}` are what a session writes when it had none, and wrapping those would make
      # an open question look bounded, which is the one direction this arm must not err in.
      if [ -n "$dof_carries" ] \
         && printf '%s' "$dof_carries" | jq -e '
              ((.options // []) | if type == "array" then . elif type == "string" and . != "" then [.] else [] end
               | length) > 0' > /dev/null 2>&1; then
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

    # `other` is the house class and has five producers — a rejected artifact, a fork whose original
    # could not be proved stopped, a session's own `stopped` with reason `other`, a transcript that
    # cannot be scanned, and a scope guard request no guard could give a verdict on. They are one
    # disposition, so the carries is not read: each names a thing outside Baton's reading — a file, a
    # process, a sentence a session wrote, an unreadable transcript, a judgement not made — and a
    # person is the one who can look at it.
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

    # The scope guard found the work departing from the confirmed intent (`lib/scope.sh`). This is the
    # one escalation SCOPE §6 M15-c says must always reach a person, and it is a constant on the class
    # for that reason: the carries is never read here, so no evidence a caller attaches — a host
    # assessment, a list of options, anything a later route learns to write — can move it to a
    # disposition that is recorded silently or resolved by a model. That is a sharper promise than
    # `other`'s, whose carries is unread by choice; here an arm that read it would be the defect.
    # Who would judge it is the point: the guard can see drift only because it holds the person's
    # record and nothing else, and a model that read the same work with the plan beside it is the
    # review that inherited the premise in the first place.
    escalation:drift) echo human-required ;;

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
    notification:takeover-silent) echo human-required ;;

    # The second arm that reads the carries, and the only one whose disposition is not a constant.
    # It is a constant everywhere it can be: asked about the class in general — with no carries, as
    # the table's own listing asks it — a gap is `human-required`, which is the true general answer,
    # because a gap with nothing accounting for it is exactly what unloaded launchd, a stuck lock or
    # a crashing tick look like and all three are a person's to look at.
    #
    # What moves it is evidence, and only one kind: `lib/host.sh` assessing the window the gap
    # measured against the host's own sleep history and finding it covered. That is the second half
    # of HOST-EXPLAINED which M15 could not supply — a gap was already over when it was reported,
    # and now it can also be explained. `host.assessed` is the parser's word and the only field read
    # here: `disposition` on the same event is this function's own answer written down, and reading
    # it back would be the table taking its answer from the caller, which is the one thing
    # `record_only` exists to stop.
    #
    # Anything short of `explained` reaches a person, and that includes `unknown` — an unreadable,
    # truncated, ambiguous or discontinuous history is not a host that reported no sleep, and
    # silence on evidence that was never established is the failure this whole milestone is against.
    notification:gap)
      if [ -n "$dof_carries" ] \
         && printf '%s' "$dof_carries" | jq -e '(.host.assessed // "") == "explained"' > /dev/null 2>&1; then
        echo HOST-EXPLAINED
      else
        echo human-required
      fi ;;

    *) render_failure err "disposition_of: \"$2\" is not one of the $1 classes"; return 1 ;;
  esac
}

# disposition_notifies <disposition>: whether a condition carrying it reaches the Mac. Derived and
# never a second opinion — `HOST-EXPLAINED` is the disposition that means "no act exists", and a
# message with no act is the one this milestone exists to stop sending.
#
# Three answers and not two: 0 reaches a person, **1 is silent**, and 2 is a word that is not a
# disposition at all. The third exists so that a caller testing only for 1 cannot mistake a class
# name, an empty string or a typo for HOST-EXPLAINED and write it silently — which is why
# `record_only` matches the 1 positively rather than testing for the absence of 0.
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
# **The notification half is `record_notification` below**, added beside this rather than as an arm
# of it, because the two writers it mirrors take different arguments: `escalate` takes a scope and
# `notification_write` takes a once-only key, and a function pretending both were one field would
# read worse than two that each mirror their own. What M15 settled and this did not move is how a
# silent record is written and what `channel` says about it.
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

# record_notification <project> <milestone> <session> <attempt> <class> <key> <fields json>: the
# silent record's notification half — `notification_write`'s arguments in `notification_write`'s
# order, minus the message. Everything `record_only`'s comment says about why this is a sibling
# rather than a flag holds here for the same reason: `notification_write` guarantees that a message
# implies a record by writing the event first (D-057), and a flag that skipped the message would
# make that guarantee conditional on an argument.
#
# The event is the one the notifier would have raised, to the field, plus `channel: ["record"]` and
# **the class's own once-only key**, which is what makes a recorded gap and a delivered one
# interchangeable to the rule that spends the key: `gap_check` looks for a `notification` event of
# class `gap` with the marker as its key and finds either, so one outage is assessed once whichever
# way it went out.
#
# `channel` is written here and not by `notification_write`. That asymmetry is deliberate and is the
# smaller of two costs: a delivered notification has never carried the field, and backfilling
# `["notification"]` onto it would move forty-nine events across thirty-six frozen expectations
# without changing a single decision, since nothing reads the field (D-192). On a `notification`
# event the field present and reading `["record"]` is the whole of what it says.
#
# The guard is `record_only`'s guard and is asked of the table rather than of the caller. It matters
# more here than there, because the notification classes are not one-per-disposition: `gap` is
# HOST-EXPLAINED only for an event whose own evidence explains it, so this refuses the same class it
# admits a moment later, on the fields and nothing else.
record_notification() {
  rcn_class=$5; rcn_key=$6; rcn_fields=$7
  class_or_fail record_notification notification "$rcn_class" || return 1
  fields_or_fail record_notification "$rcn_fields" || return 1
  rcn_d=$(disposition_of notification "$rcn_class" "$rcn_fields") || return 1
  # Matched positively, for the reason `record_only` gives: `disposition_notifies` answers 0 for a
  # class that reaches a person and 2 for a word that is not a disposition at all, and a plain `if`
  # would read that 2 as "does not notify" and write the line silently.
  rcn_n=0; disposition_notifies "$rcn_d" || rcn_n=$?
  [ "$rcn_n" -eq 1 ] || {
    render_failure err "record_notification: this $rcn_class is $rcn_d, which reaches a person; it cannot be recorded silently"
    return 1
  }
  log_event notification "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg c "$rcn_class" --arg k "$rcn_key" --argjson f "$rcn_fields" \
       '{class: $c} | if $k != "" then . + {key: $k} else . end | . + $f + {channel: ["record"]}')"
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
  rrc_status=0
  rrc_done=''
  while [ "$rrc_i" -lt "$rrc_n" ]; do
    rrc_e=$(printf '%s' "$rrc_list" | jq -c ".[$rrc_i]"); rrc_i=$((rrc_i + 1))
    rrc_at=$(printf '%s' "$rrc_e" | jq -r .at)
    rrc_path=$(printf '%s' "$rrc_e" | jq -r '.carries.path // ""')
    rrc_s=$(printf '%s' "$rrc_e" | jq -r '.session // ""')
    rrc_m=$(printf '%s' "$rrc_e" | jq -r '.milestone // ""')
    # `derive_parked` keys a resolution on `(escalation_at, project, milestone)` and the parks were
    # derived once, before any of them was closed. Two parks of one milestone raised in the same
    # second are therefore indistinguishable to that join, and the first `resolve` closes both — so
    # the second would write a redundant `resolution` for a park already closed. The pair is
    # remembered rather than the log re-read, because re-deriving per park would read the whole log
    # once per orphan for a case that is two lines to handle.
    case "$rrc_done" in *"|$rrc_at $rrc_m|"*) continue ;; esac
    rrc_why=''
    # The file first, because it is the thing the park's own message names and the cheaper read.
    # An absolute path under `$BATON_HOME`, as `reject_move` wrote it: moving the home would read as
    # every orphan park's file being gone. Deliberate on one Mac, where the home does not move, and
    # the alternative — re-deriving the path from the home and the basename — would invent a second
    # opinion about where the file is when the park already carries the one Baton chose.
    if [ ! -e "$rrc_path" ]; then
      rrc_why="the file it names is gone"
    elif [ -n "$rrc_s" ] && [ -n "$rrc_m" ] \
         && printf '%s' "$rrc_log" | jq -e --arg s "$rrc_s" --arg a "$rrc_at" --arg m "$rrc_m" '
           [ to_entries[] | {i: .key} + .value ] as $ev
           | ([ $ev[] | select(.kind == "escalation" and .at == $a and .session == $s
                               and .milestone == $m and (.project // "") == "") ] | last | .i // -1) as $park
           | $park >= 0 and any($ev[]; .kind == "consumed" and .session == $s and .milestone == $m
                                       and .i > $park)' > /dev/null 2>&1; then
      # The other correction: the session wrote an artifact Baton could read *for this milestone*,
      # and that handover has been acted on. The milestone is part of the test and not only the
      # session, because one session can owe more than one artifact — a hand-run session whose bad
      # `M02-<id>.json` was rejected and whose good `M01-<id>.json` was consumed has corrected
      # nothing about M02, and the file the M02 park names is still sitting in `rejected/`.
      #
      # "Since" is **log order and not the timestamp**, the rule CONTRACT clause 3(c) states for
      # exactly this question and which `person_acted` and `derive_key_spent` already follow: `at`
      # carries an offset, so two events an hour apart in different zones sort by their text the
      # wrong way round, and a rejection is where that is likeliest — the artifact came from a
      # session whose clock Baton does not own. The park's own index is found by matching its
      # whole identity and not its `at` alone, so an unrelated escalation in the same second cannot
      # stand in for it.
      rrc_why="the session it names has had a handover consumed since"
    fi
    [ -n "$rrc_why" ] || continue
    if ! resolve "" "$rrc_m" "$rrc_s" "" "$rrc_at" edit; then
      # The tick's own status, not a swallowed `continue`: the marker means "a tick completed"
      # (INV-11), and a pass that could not write a resolution has not.
      render_failure err "baton: the rejection park raised at $rrc_at could not be resolved"
      rrc_status=1
      continue
    fi
    rrc_done="$rrc_done|$rrc_at $rrc_m|"
    render_row out record 'settled   %s · the rejection park raised at %s is closed · %s\n' \
      "$(render_token out milestone "${rrc_m:-an unnamed milestone}")" \
      "$(render_token out timestamp "$rrc_at")" "$rrc_why"
  done
  return "$rrc_status"
}

# ---- the replan route ------------------------------------------------------------------------
#
# `replan` is the disposition whose answer is a plan, and this is the route that asks for one
# (`docs/milestones/M15-e.md`). Its three halves are here because this is the home of the route
# family: the gate, the park written without a message, and the request. `lib/planning.sh` does the
# rest — it dispatches the planning lane for the request, measures what it lands, adopts it and closes
# the park — and is not changed by any of this.
#
# **The gate is decided once, at the raise, and the park's `channel` says which way it went.**
# `declared_step` asks `replan_route` before it raises either replan class. When the gate passes, the
# park is written by `replan_raise` with `channel: ["replan"]` and no Mac message, and the request is
# made from it in the same breath; when it does not, the line says why and `escalate` raises the park
# as it always has, with the message. A park a person was told about stays theirs: requesting a replan
# from it later, when the gate happened to pass, would set a planning session writing the very plan
# the message had just asked the person to edit, and the two writers would meet on `main`.
#
# **Silence ends when the route does.** A park nobody was told about may stand only while its replan
# can still arrive, so every way the route finishes without an adoption — its attempts spent (D-167's
# bound, unchanged), `plan_owed` removed without one, or the gate refusing on a tick that had to make
# the request again — delivers the park's own message once, and spends no new class (clause 2 above).
# `replan_pass` is the per-tick half that notices each of those.

# replan_gate <project> <milestone> <class> <rows json>: whether a replan may be requested for a park
# of this milestone and class. Nothing and status 0 when it may; one sentence and status 1 when it may
# not, which is the reason the park goes to the person instead. A reading that fails refuses, because
# the refusal is the side that tells somebody.
#
# The conditions, cheapest first, and each is a certain refusal further down the line:
#
#   * **No plan already owed.** `plan_owed` is one record; a second request would overwrite the
#     first one's park, or a first plan's reason, and leave that one with nobody coming for it.
#   * **No replan already tried for this run of endings.** An adoption closes the park with an
#     `edit`, and `declared_step` judges the ending again under the new plan: a blocker the new plan
#     still does not hold parks the lane again from the same ending, and one more `unfinished` after
#     the redispatch makes the run longer, not new. Either way the replan was tried and the lane came
#     back the same way, so a second request would be the same answer asked for again, silently and
#     with no bound — each request starts `planningAttempts` afresh. The run is the lane's trailing
#     session-written endings of the class's reason, and an `adopted` replan of this milestone and
#     class after its first one refuses: the park goes to the person, as it did before the route.
#   * **A confirmed goal** — the planning input, as `planning_pass` refuses a first plan without one.
#   * **A `native` plan registered at `docs/MILESTONES.md`.** A replacement is read as strictly as a
#     first plan and proved against the planning lane's scope, which is that path and the briefs, so an
#     `adapted` plan, or one registered anywhere else, can never have a replacement adopted. A
#     registration with no `plan_format` predates onboarding and is not called native on its silence.
#   * **No other open lane and no project park.** Every lane `derive_in_flight` names, live or rowless,
#     runs from the plan being replaced, and the parked milestone's own lane is the one asking. The
#     scope guard's lane is the exception: it writes nothing in any repository, it is given no plan to
#     run from, and it is dispatched at every close-out, so counting it would refuse most requests for
#     a lane that cannot be affected by one. A project-scope park holds every lane, the planning one
#     included (`planning_pass`), so a request under one is a session that cannot start.
#   * **Every `done` row proved.** A replacement may carry `done` only where Baton proved it
#     (REQ-GENERATE-13): one that keeps an unproved `done` is refused, and requesting it spends
#     `planningAttempts` sessions on that refusal; one that follows the replan prompt and blanks the
#     row is adopted, and the row is then eligible again, so Baton dispatches finished work a second
#     time. Neither is an answer, so no request is made. The count goes on the line, because it is the
#     cost of the rule (D-201).
replan_gate() {
  rgt_f=$BATON_HOME/projects/$1/project.json
  if rgt_owed=$(planning_owed "$1"); then
    echo "a plan is already owed ($(printf '%s' "$rgt_owed" | jq -r '.reason // "no reason recorded"'))"
    return 1
  fi
  rgt_log=$(log_json) || { echo "Baton's record of the project could not be read"; return 1; }
  rgt_tried=$(printf '%s' "$rgt_log" | jq -r --arg p "$1" --arg m "$2" --arg c "$3" --arg pm "$PLANNING_ID" '
    ({"unfinished-twice": "unfinished", "blocked": "blocked"}[$c] // $c) as $r
    | [ to_entries[] | {i: .key} + .value | select(.project == $p) ] as $ev
    | ([ $ev[] | select(.kind == "consumed" and .milestone == $m and .written_by == "session") ]
       | reverse) as $s
    | (([ range(0; $s | length) | select($s[.].reason != $r) ] | first) // ($s | length)) as $n
    | (if $n == 0 then -1 else $s[$n - 1].i end) as $from
    | [ $ev[] | select(.kind == "plan_generation" and .milestone == $pm and .outcome == "adopted"
                       and .replan.milestone == $m and .replan.class == $c and .i > $from) ]
    | last | .at // empty') || { echo "Baton's record of the project could not be read"; return 1; }
  if [ -n "$rgt_tried" ]; then
    echo "a replan for this $3 was adopted at $rgt_tried and $2 has come back the same way"
    return 1
  fi
  if ! jq -e '(.goal // "") != ""' "$rgt_f" > /dev/null 2>&1; then
    echo "the registration carries no confirmed goal to replan against · run baton onboard $(project_path "$1" 2>/dev/null || printf '<path>')"
    return 1
  fi
  rgt_fmt=$(jq -r '.plan_format // ""' "$rgt_f" 2>/dev/null) || rgt_fmt=''
  rgt_plan=$(jq -r '.plan // ""' "$rgt_f" 2>/dev/null) || rgt_plan=''
  if [ "$rgt_fmt" != native ] || [ "$rgt_plan" != "$PLANNING_PLAN" ]; then
    echo "the plan is ${rgt_fmt:-of no recorded format} at ${rgt_plan:-no recorded path}, and only a native plan at $PLANNING_PLAN can have a replacement adopted"
    return 1
  fi
  rgt_fl=$(derive_in_flight "$1" "$4") || { echo "the open lanes could not be read"; return 1; }
  rgt_open=$(printf '%s' "$rgt_fl" | jq -r --arg m "$2" --arg s "$SCOPE_ID" '
    [ (.in_flight + .no_row)[] | .milestone | select(. != $m and . != $s) ] | unique | join(", ")')
  if [ -n "$rgt_open" ]; then
    echo "another lane runs from this plan ($rgt_open)"
    return 1
  fi
  rgt_pp=$(derive_parked "$1") || { echo "the parks could not be read"; return 1; }
  rgt_pc=$(printf '%s' "$rgt_pp" | jq -r 'first(.parked[] | select(.scope == "project") | .class) // empty')
  if [ -n "$rgt_pc" ]; then
    echo "the project is parked ($rgt_pc)"
    return 1
  fi
  rgt_doc=$(plan_of_project "$1" 2>/dev/null) || { echo "the plan could not be read"; return 1; }
  rgt_hist=$(planning_history "$1") || { echo "Baton's record of the project could not be read"; return 1; }
  rgt_un=$(jq -nc --argjson p "$rgt_doc" --argjson h "$rgt_hist" \
    '[ $p.milestones[] | select(.status == "done") | .id ] - $h.preserved')
  rgt_n=$(printf '%s' "$rgt_un" | jq length)
  if [ "$rgt_n" -gt 0 ]; then
    echo "$rgt_n done row$([ "$rgt_n" -eq 1 ] || printf s) Baton never proved complete ($(printf '%s' "$rgt_un" | jq -r 'if length > 5 then (.[0:5] | join(", ")) + ", …" else join(", ") end')): a replacement would be refused for keeping such a row done, or would blank it and have it built again"
    return 1
  fi
}

# replan_raise <project> <milestone> <session> <attempt> <class> <carries json>: the park written
# without a Mac message, for a class whose disposition is `replan`. `escalate`'s arguments in
# `escalate`'s order less the scope, which is always `lane` — the class is about one milestone's
# place in the plan.
#
# A sibling of `record_only` for `record_only`'s own reason: `escalate` guarantees a message implies a
# record, and a flag that skipped the message would make that guarantee conditional (D-057). It
# differs from `record_only` in two things, both because this park is not over when it is written.
# **It carries the re-read receipt**, `escalate`'s, so that once the plan is replaced — or once a
# person ends the replan by hand — `edit_reread_check` reads the change the way it reads any edit.
# **And its `channel` is `["replan"]`**, which says why no message went: not that nothing was asked of
# anyone, as `["record"]` says, but that what was asked went to the planning lane. `replan_pass` reads
# it to find the parks whose silence it has to end.
#
# The guard is `record_only`'s, inverted: the disposition is asked of the table, and anything but
# `replan` is refused, so no caller can route a park a person must see down the silent path.
replan_raise() {
  rrs_class=$5; rrs_carries=$6
  class_or_fail replan_raise escalation "$rrs_class" || return 1
  fields_or_fail replan_raise "$rrs_carries" || return 1
  rrs_d=$(disposition_of escalation "$rrs_class" "$rrs_carries") || return 1
  [ "$rrs_d" = replan ] || {
    render_failure err "replan_raise: $rrs_class is $rrs_d, not replan; it cannot be raised without a message"
    return 1
  }
  rrs_reread=$(reread_hashes "$1" "$2" "$rrs_class" "$rrs_carries") || rrs_reread='{}'
  rrs_carries=$(printf '%s' "$rrs_carries" | jq -c --argjson r "$rrs_reread" \
    'if ($r | length) > 0 then . + {reread: $r} else . end')
  log_event escalation "$1" "$2" "$3" "$4" \
    "$(jq -nc --arg c "$rrs_class" --argjson carries "$rrs_carries" \
       '{class: $c, scope: "lane", carries: $carries, channel: ["replan"]}')"
}

# replan_request <project> <park json>: the request — `plan_owed` with the park it answers, then the
# `plan_generation` event with outcome `requested`.
#
# **The registration first.** `planning_replan` reads the first and `planning_landed` and
# `planning_attempts` read the second, and a tick can end between them. With the registration first,
# what that leaves is a replan owed with no event, which `replan_pass` can see and repair; the other
# order would leave an event with no `plan_owed`, which reads exactly like a replan a person ended by
# hand. The event is written with `log_event` and not `planning_record`, which swallows a refusal:
# a request whose event was refused has to be made again, and it can only be seen to need that if
# the refusal is.
replan_request() {
  rrq_park=$2
  rrq_f=$BATON_HOME/projects/$1/project.json
  rrq_doc=$(jq -c --argjson k "$rrq_park" '
    .plan_owed = {reason: "\($k.milestone) is parked \($k.class), and the plan is what is wrong",
                  owner: "M15-e",
                  replan: {milestone: $k.milestone, class: $k.class, at: $k.at,
                           detail: ($k.carries.detail // "")}}' "$rrq_f") \
    || { render_failure err "baton: $rrq_f does not parse; no replan was requested"; return 1; }
  onboard_registration_write "$1" "$rrq_doc"
  replan_requested_event "$1" "$rrq_park" || return 1
  render_row out action 'replan    %s/%s · requested · a planning session replaces the plan, and nothing else of %s is dispatched until it is adopted\n' \
    "$(render_token out lane "$1")" "$(render_token out milestone "$(printf '%s' "$rrq_park" | jq -r .milestone)")" "$1"
}

# replan_requested_event <project> <park json>: the request's own record, `replan` naming the park by
# its `at` as well as its milestone and class, so that every later reading — the repair, the
# exhaustion, the end without an adoption — finds this park's request and no other's.
replan_requested_event() {
  rre_n=$(planning_attempts "$1") || { render_failure err "$rre_n"; return 1; }
  log_event plan_generation "$1" "$PLANNING_ID" "" "" \
    "$(printf '%s' "$2" | jq -c --argjson n "$rre_n" \
       '{outcome: "requested", attempts: $n, replan: {milestone, class, at}}')" \
    || { render_failure err "baton: $1 the replan request's event could not be written"; return 1; }
}

# replan_route <project> <milestone> <session> <attempt> <class> <carries json> <rows json>:
# `declared_step`'s one question before it raises a replan class. Status 0 when the park is raised
# here, silently, and the request made from it; status 1 when the caller is to `escalate` as it always
# has — the gate refused, with the line saying why, or the silent park could not be written.
#
# The request is made from the park just written, found again by its milestone and class among the
# standing parks, because the request names the park by `at` and only the log knows the `at` it got.
# A request that fails after the park is written leaves a silent park with nothing owed, which is
# `replan_pass`'s to find on the next tick — the gate is asked again there and the message delivered
# if it refuses — so the park is still this function's and the status is 0.
replan_route() {
  if ! rrt_no=$(replan_gate "$1" "$2" "$5" "$7"); then
    render_row out action 'replan    %s/%s · not requested: %s · the park goes to the person\n' \
      "$(render_token out lane "$1")" "$(render_token out milestone "$2")" "$rrt_no"
    return 1
  fi
  replan_raise "$1" "$2" "$3" "$4" "$5" "$6" || return 1
  rrt_pp=$(derive_parked "$1") || { render_failure err "$rrt_pp"; return 0; }
  rrt_park=$(printf '%s' "$rrt_pp" | jq -c --arg m "$2" --arg c "$5" '
    [ .parked[] | select(.scope == "lane" and .milestone == $m and .class == $c
                         and ((.channel // []) | index("replan")) != null) ] | last // empty')
  [ -n "$rrt_park" ] || return 0
  replan_request "$1" "$rrt_park" || true
}

# replan_pass <project> <rows json>: the per-tick half, run just before `planning_pass`, so that a
# request whose event was lost is whole before generation reads the newest `requested` event; an
# exhaustion that pass records is acted on by the next tick's. For every standing park this route
# raised:
#
#   * **answered** — an `adopted` event names its `at`: nothing. `onboard_commit` removes `plan_owed`
#     before `planning_close_park` resolves the park, so a tick that ended between the two leaves this
#     park standing; requesting from it would replace the plan just adopted. Once nothing is owed the
#     re-read runs again and reads the adopted plan as the change it is.
#   * **delivered** — a `delivered` event names it: nothing. It is a person's park now.
#   * **owed, with no event** — the registration names it and no `requested` event does: the tick that
#     made the request ended between its two writes. The event is written.
#   * **owed and spent** — an `exhausted` event follows its request: delivered.
#   * **owed** otherwise: nothing. The planning lane is working on it.
#   * **requested, and owed no longer** — `plan_owed` is gone without an adoption, which only a person
#     does (`baton onboard` re-reads the plan and drops it): delivered, because the route is over.
#   * **never requested** — the tick that raised it ended before the request: the gate is asked again,
#     and the request made, or the message delivered with the refusal leading it.
replan_pass() {
  rps_parked=$(derive_parked "$1") || { render_failure err "$rps_parked"; return 1; }
  rps_list=$(printf '%s' "$rps_parked" | jq -c '
    [ .parked[] | select(.scope == "lane" and ((.channel // []) | index("replan")) != null) ]')
  rps_n=$(printf '%s' "$rps_list" | jq length); rps_i=0
  [ "$rps_n" -gt 0 ] || return 0
  rps_log=$(log_json) || { render_failure err "$rps_log"; return 1; }
  rps_owed=$(planning_replan "$1" 2>/dev/null | jq -r '.at // ""') || rps_owed=''
  rps_status=0
  while [ "$rps_i" -lt "$rps_n" ]; do
    rps_k=$(printf '%s' "$rps_list" | jq -c ".[$rps_i]"); rps_i=$((rps_i + 1))
    rps_at=$(printf '%s' "$rps_k" | jq -r .at)
    rps_state=$(printf '%s' "$rps_log" | jq -r --arg p "$1" --arg m "$PLANNING_ID" --arg a "$rps_at" '
      [ to_entries[] | {i: .key} + .value
        | select(.kind == "plan_generation" and .project == $p and .milestone == $m) ] as $ev
      | ([ $ev[] | select(.outcome == "requested" and .replan.at == $a) ] | last | .i // -1) as $req
      | if any($ev[]; .outcome == "adopted" and .replan.at == $a) then "answered"
        elif any($ev[]; .outcome == "delivered" and .replan.at == $a) then "delivered"
        elif $req < 0 then "unrequested"
        elif any($ev[]; .outcome == "exhausted" and .i > $req) then "exhausted"
        else "requested" end')
    case "$rps_state" in
      answered|delivered) continue ;;
    esac
    if [ "$rps_owed" = "$rps_at" ]; then
      case "$rps_state" in
        unrequested)
          if replan_requested_event "$1" "$rps_k"; then
            render_row out action 'replan    %s/%s · requested · the request a tick ended part-way through is completed\n' \
              "$(render_token out lane "$1")" "$(render_token out milestone "$(printf '%s' "$rps_k" | jq -r .milestone)")"
          else
            rps_status=1
          fi ;;
        exhausted)
          replan_deliver "$1" "$rps_k" exhausted \
            "$(planning_attempts "$1" 2>/dev/null || printf 'its') replan attempts, none adopted; repair the plan, then run baton onboard $(project_path "$1" 2>/dev/null || printf '<path>')" \
            || rps_status=1 ;;
      esac
      continue
    fi
    case "$rps_state" in
      requested|exhausted)
        replan_deliver "$1" "$rps_k" ended "the replan was ended without a plan being adopted" || rps_status=1 ;;
      unrequested)
        rps_m=$(printf '%s' "$rps_k" | jq -r .milestone)
        if rps_no=$(replan_gate "$1" "$rps_m" "$(printf '%s' "$rps_k" | jq -r .class)" "$2"); then
          replan_request "$1" "$rps_k" || rps_status=1
        else
          replan_deliver "$1" "$rps_k" refused "no replan could be requested: $rps_no" || rps_status=1
        fi ;;
    esac
  done
  return "$rps_status"
}

# replan_deliver <project> <park json> <why> <lead>: the park's own message, once, now that its route
# is over. The `delivered` event first and the message after it, the order `escalate` keeps (D-057):
# the event is what makes it once, so a message with no event behind it would go out every tick.
#
# The message is the one `escalate` would have sent when the park was raised — `message_render` over
# the park's own class and carries — with one sentence leading the detail, because the person is
# reading about a park that has stood for a while and needs to know why it reaches them now and what
# ends it. Nothing else changes: the park stands as it was, the same verb answers it, and no class is
# spent (REQ-ESC-04).
replan_deliver() {
  rdl_k=$2
  rdl_m=$(printf '%s' "$rdl_k" | jq -r .milestone)
  rdl_s=$(printf '%s' "$rdl_k" | jq -r '.session // ""')
  rdl_n=$(planning_attempts "$1") || rdl_n=0
  log_event plan_generation "$1" "$PLANNING_ID" "" "" \
    "$(printf '%s' "$rdl_k" | jq -c --arg w "$3" --argjson n "$rdl_n" \
       '{outcome: "delivered", attempts: $n, replan: {milestone, class, at}, why: $w}')" \
    || { render_failure err "baton: $1 the delivery of the park on $rdl_m could not be recorded, so it is not sent"; return 1; }
  rdl_carries=$(printf '%s' "$rdl_k" | jq -c --arg l "$4" \
    '(.carries // {}) | .detail = (if (.detail // "") == "" then $l else "\($l) · \(.detail)" end)')
  rdl_msg=$(message_render "$1" "$rdl_m" "$(printf '%s' "$rdl_k" | jq -r .class)" "$rdl_carries" \
    "$rdl_s" "$(printf '%s' "$rdl_k" | jq -r '.attempt // ""')")
  notify "$(printf '%s' "$rdl_msg" | jq -r .address)" "$(printf '%s' "$rdl_msg" | jq -r .body)" "$rdl_s"
  render_row out action 'replan    %s/%s · %s · the park'"'"'s message is delivered now\n' \
    "$(render_token out lane "$1")" "$(render_token out milestone "$rdl_m")" "$4"
}
