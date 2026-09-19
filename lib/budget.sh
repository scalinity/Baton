#!/bin/sh
# lib/budget.sh — budget-aware pacing: the subscription's five-hour window, how much of it has been
# spent, and the pause that stops a new session being started into a window that is nearly gone
# (SCOPE §6 M14). An unattended runner that does not know its own allowance exhausts the window at
# 2 a.m. and sits stalled until morning looking like it is working; the pause makes that a recorded
# state with a resume time instead of a dispatch that fails on quota.
#
# The pause is a **hold**, cause `budget`, model `all`, written once and lifted once like the
# `fableReserve` hold beside it. That is the whole of the integration, and it is deliberate: every
# automatic session start already asks `hold_bites` before it starts one — step 7's filter loop in
# `dispatch_run`, which covers work milestones and the planning lane alike, and `redispatch` in
# `lib/stops.sh` — so extending that seam paces every automatic route at once. A second place
# deciding whether a candidate may start would be a second dispatcher (SCOPE §6 M13).
#
# **Two guards, and one of them is the account's own word.** The status feed carries
# `rate_limits.five_hour.used_percentage` and `resets_at`, rewritten by every session every turn,
# so what the account has actually spent — Baton's sessions, their resumes, their subagents and the
# person's own work — is observable rather than estimated, and the resume time is the account's own
# boundary rather than a guess. That reading is the first guard. The second is the count of session
# starts Baton itself made in the window, which exists for the one moment the reading cannot cover:
# a tick admits several sessions at once and none of them has written a feed entry yet, so the
# reading it read is a reading from before its own work. The count catches that; the reading
# catches everything else. Either one pauses.
#
# **`sessions_used` is a pacing estimate and never a quota.** The installed CLI (2.1.278) has no
# usage or tier command — `claude --help` lists `agents`, `attach`, `auth`, `auto-mode`, `doctor`,
# `gateway`, `import`, `install`, `logs`, `mcp`, `plugin`, `project`, `respawn`, `rm`,
# `setup-token`, `stop`, `ultrareview` and `update`, and none of them reports an allowance — and
# the feed names a percentage, never a number of sessions. So no tier maps to a number of sessions
# here: `budgetTier` records the person's word for the plan and nothing is derived from it, and
# `budgetSessions` is a number a person sets, defaulting to 0, which is off. A built-in table would
# be stating a guarantee the provider never gave (D-196).
set -eu

# budget_int <key> <default>: one whole number out of config.json, or a failure naming the key.
#
# `config_num` returns whatever `tostring` gives, and a value that is not a number reaches two
# places that treat it differently: `[ "$x" -gt 0 ]` exits 2, which an `|| return 0` beside it turns
# into "the guard is off", while `--argjson` makes jq reject the document and the pass fails. Silent
# off and loud failure at once is the one shape this file must not have — a pacing pass that failed
# has to withhold, never to admit — so the value is checked once, here, and a misconfiguration stops
# the pass rather than quietly disabling the guard it configures.
budget_int() {
  bin_v=$(config_num "$1" "$2")
  case $bin_v in ''|*[!0-9]*) echo "config.json: $1 is not a whole number: $bin_v"; return 1 ;; esac
  printf '%s\n' "$bin_v"
}

# budget_span: the window's length in seconds. Five hours, `budgetWindowHours` in config.json.
budget_span() { bsp_h=$(budget_int budgetWindowHours 5) || { echo "$bsp_h"; return 1; }; echo $((bsp_h * 3600)); }

# budget_tier: the person's word for the subscription plan, recorded in every budget record so a
# reading taken later can be read against the plan it was taken under. Nothing reads it back.
budget_tier() { jq -r '.budgetTier // "unset"' "$BATON_HOME/config.json" 2>/dev/null || echo unset; }

# budget_reading: the freshest reading of the account's five-hour window — the status file with the
# newest modification time carrying `rate_limits.five_hour.used_percentage` as a number, whichever
# session wrote it. Prints {reading, status_file} and `resets_at` when the file carries one as a
# number, or {} when there is no reading. `resets_at` is floored: the field is documented and
# observed as whole epoch seconds, and the window is derived from it in shell arithmetic, which
# has no fractions — so a feed that ever sent one would otherwise fail the pass rather than round.
#
# The same rule `reserve_reading` keeps for the seven-day window, for the same reasons: the windows
# are account-wide, so any session's reading is the account's; the feed carries no time of its own
# and is rewritten every turn, so modification time is the only freshness it has; and a file from a
# session that has had no response yet holds no number and must not hide an older one that does.
#
# A reading whose own `five_hour.resets_at` has passed is a reading of a window that is over, and
# nothing older describes the one open now, so there is no reading at all. Without that the pause
# could never lift on a night nothing else ran: it stops sessions from starting, so nothing writes
# a fresher file, and the last reading would stand until a person ran something.
budget_reading() {
  brd_now=$(now_epoch)
  brd_list=$(ls -t "$BATON_HOME"/status/*.json 2>/dev/null) || brd_list=''
  while IFS= read -r brd_f; do
    [ -n "$brd_f" ] || continue
    brd_doc=$(jq -c --argjson now "$brd_now" '
      .rate_limits.five_hour as $w
      | if ($w.used_percentage | type) != "number" then empty
        elif ($w.resets_at | type) == "number" and $w.resets_at <= $now then {expired: true}
        elif ($w.resets_at | type) == "number" then {reading: $w.used_percentage, resets_at: ($w.resets_at | floor)}
        else {reading: $w.used_percentage} end' "$brd_f" 2>/dev/null) || continue
    [ -n "$brd_doc" ] || continue
    if printf '%s' "$brd_doc" | jq -e '.expired' > /dev/null; then echo '{}'; return 0; fi
    printf '%s' "$brd_doc" | jq -c --arg f "$brd_f" '. + {status_file: $f}'
    return 0
  done <<EOF
$brd_list
EOF
  echo '{}'
}

# budget_starts <cutoff epoch>: the session starts Baton made automatically at or after the cutoff,
# oldest first, as [{project, at, epoch}].
#
# **What a start is.** A `dispatch` event, and a `dispatch_failed` at the `launch` or `service`
# stage. Those two stages are the ones that reached the CLI, so each may have spent allowance and
# may even have left a worker running under no id Baton holds (D-130); the earlier stages —
# `worktree`, `settings`, `prompt` — failed before the CLI was asked for anything and spent
# nothing. Counting a reached launch is M14 §7 item 2's failed-start accounting, and it leaves
# M13's rule exactly where it was: a dispatch that produced no session still writes
# `dispatch_failed` and not `dispatch`, so no attempt moves and no ladder advances. Pacing reads a
# second kind of event rather than the event table gaining a lie.
#
# **What a start is not.** A resume continues a session rather than starting one, and neither it nor
# a copy fork nor the wake session is counted: the wake session must stay reachable whatever the
# pacing says, because it is how a person reaches a session that has gone offline. All of them spend
# allowance and all of them are inside the feed's reading, which is the guard that covers what this
# count cannot see.
#
# **A hand-run `baton dispatch` is charged, and is not paced.** The two are different things and
# were once conflated here. `verb_dispatch` never asks `hold_bites`, so a pause never stops a
# person from starting a milestone by hand — that is the same line the `fableReserve` hold has
# always drawn, and a tool that refused its owner would be the wrong tool. But the session it
# started is a session on the same subscription, and its event is a `dispatch` like any other, so
# counting it is simply true. A count that pretended otherwise would read low by exactly the work a
# person did most recently, which is the worst moment to under-read (D-197).
#
# The walk is backwards from the newest event and stops at the first start older than the cutoff.
# The log is append-ordered under one writer holding the lock, so its order is its time order and
# in a steady state this converts a handful of timestamps rather than the whole file — which the
# alternative, an `iso_epoch` per dispatch event ever logged, would do twice a tick for ever.
# The one way the order can lie is a system clock that jumped backwards, and then the walk stops
# early and the count reads low for the rest of that window; it is stated rather than guarded
# against, because the guard costs the whole log every tick and the condition heals itself at the
# next boundary. All time arithmetic goes through `iso_epoch` (§6.4).
budget_starts() {
  bst_log=$(log_json) || { echo "$bst_log"; return 1; }
  bst_all=$(printf '%s' "$bst_log" | jq -c '
    [ .[] | select(.kind == "dispatch"
                   or (.kind == "dispatch_failed" and (.stage == "launch" or .stage == "service")))
      | {project: (.project // ""), at} ] | reverse')
  bst_in='[]'
  bst_n=$(printf '%s' "$bst_all" | jq length); bst_i=0
  while [ "$bst_i" -lt "$bst_n" ]; do
    bst_s=$(printf '%s' "$bst_all" | jq -c ".[$bst_i]"); bst_i=$((bst_i + 1))
    bst_e=$(iso_epoch "$(printf '%s' "$bst_s" | jq -r .at)") || { echo "$bst_e"; return 1; }
    [ "$bst_e" -ge "$1" ] || break
    bst_in=$(printf '%s' "$bst_in" | jq -c --argjson s "$bst_s" --argjson e "$bst_e" \
      '[$s + {epoch: $e}] + .')
  done
  printf '%s\n' "$bst_in"
}

# budget_state: the whole pacing picture for this instant, as one document —
# {window_start, ends, source, tier, paused, why[], sessions_used, per_project{},
#  reading?, status_file?}. `source` is read by nothing and kept anyway: it names which of the three
# window rules produced this answer, which is the first thing a person debugging a pause wants and
# the thing M16's live observation has to record.
#
# `window_start` is null where `source` is `empty` — no reading and nothing spent, so there is no
# window open to name. The alternative, naming this instant, would move the value every tick and
# rewrite every project's record once a minute through a quiet night, which is exactly the churn
# the record's "only when it would change" test exists to avoid.
#
# **The window being paced against.** When a reading names `resets_at`, that is the account's own
# boundary and the window is the span ending there; nothing better exists and nothing is guessed.
# With no such reading the window ends one span after the oldest start still inside it, which rolls
# by itself: as a start ages past the span it leaves the count, the window's start moves forward
# and the count falls. With neither a reading nor a start the window begins now and nothing has
# been spent in it.
#
# `sessions_used` counts from the window's own start rather than from one span before now, so a
# record and the boundary it names can never be describing two different windows.
#
# **`ends` is Baton's statement of when it expects the pause to lift, and never a timer.** Nothing
# waits on it: the pause is recomputed from fresh inputs every tick and lifts the moment neither
# guard bites, so a reading that arrives early lifts it early and an estimate that read long costs
# nothing but the line a person saw. Where the count is the guard and more starts stand above the
# allowance than one boundary releases, it is the first of several such boundaries, and each tick
# computes the next one.
budget_state() {
  # Guarded like every other call that can fail: `budget_state` is always invoked as
  # `x=$(budget_state) || …`, which suppresses `set -e` through its whole body, so an unguarded
  # assignment would carry the failure's own message forward as if it were a number and the reason
  # would be lost in the arithmetic that followed.
  bsx_span=$(budget_span) || { echo "$bsx_span"; return 1; }
  bsx_now=$(now_epoch)
  bsx_reading=$(budget_reading)
  bsx_starts=$(budget_starts "$((bsx_now - bsx_span))") || { echo "$bsx_starts"; return 1; }

  # The window. A feed boundary wins; then the oldest start still inside the span; then now. A feed
  # boundary is always in the future (an expired one is not a reading), so the window it names
  # begins at most one span ago and the walk above can never have stopped short of it.
  #
  # The start is clamped to now, for the one case that breaks that: a `resets_at` more than a span
  # ahead, which the account's clock running ahead of this Mac's would give. Unclamped, the window
  # would begin in the future, every real start would fall outside it, and the count guard would
  # read zero while the reading guard carried on alone — a guard silently disabled by a clock skew.
  bsx_resets=$(printf '%s' "$bsx_reading" | jq -r '.resets_at // empty')
  if [ -n "$bsx_resets" ]; then
    bsx_from=$((bsx_resets - bsx_span)); bsx_ends=$bsx_resets; bsx_source=feed
    [ "$bsx_from" -le "$bsx_now" ] || bsx_from=$bsx_now
  else
    bsx_oldest=$(printf '%s' "$bsx_starts" | jq -r 'first | .epoch // empty')
    if [ -n "$bsx_oldest" ]; then bsx_from=$bsx_oldest; bsx_source=starts
    else bsx_from=$bsx_now; bsx_source=empty; fi
    bsx_ends=$((bsx_from + bsx_span))
  fi

  # The two guards, both decided inside jq: a reading is a number whose type the feed chose, and
  # `[ "$a" -ge "$b" ]` is integer-only, so a percentage arriving as 92.5 would fail the test
  # rather than trip it.
  bsx_ceiling=$(budget_int budgetCeiling 90) || { echo "$bsx_ceiling"; return 1; }
  bsx_allowed=$(budget_int budgetSessions 0) || { echo "$bsx_allowed"; return 1; }
  jq -nc --argjson r "$bsx_reading" --argjson starts "$bsx_starts" \
    --argjson ceiling "$bsx_ceiling" --argjson allowed "$bsx_allowed" --argjson from "$bsx_from" \
    --arg ws "$(epoch_iso "$bsx_from")" --arg ends "$(epoch_iso "$bsx_ends")" \
    --arg source "$bsx_source" --arg tier "$(budget_tier)" '
    [ $starts[] | select(.epoch >= $from) ] as $in
    | ($in | length) as $used
    | ( (if $ceiling < 100 and ($r.reading // -1) >= $ceiling
         then ["the five-hour window reads \($r.reading)%, at or above the ceiling of \($ceiling)%"]
         else [] end)
        + (if $allowed > 0 and $used >= $allowed
           then ["\($used) session starts in this window, at or above the \($allowed) budgetSessions allows"]
           else [] end) ) as $why
    | {window_start: (if $source == "empty" then null else $ws end),
       ends: $ends, source: $source, tier: $tier,
       paused: (($why | length) > 0), why: $why, sessions_used: $used,
       per_project: ($in | group_by(.project) | map({key: .[0].project, value: length}) | from_entries)}
    + (if ($r | has("reading")) then {reading: $r.reading, status_file: $r.status_file} else {} end)'
}

# budget_record <project> <state json>: this project's `projects/<key>/budget.json` — the three
# fields SCOPE §5 names, `window_start`, `sessions_used` and `tier` — written `.tmp` then renamed,
# and only when it would change, so the file's own modification time says when this project's
# pacing picture last moved rather than when the last tick ran.
#
# It is a record and never an input. Every field is derived from the log, the feed and the clock on
# the tick that writes it, so nothing reads it back, deleting it loses nothing, a stale one cannot
# mislead a decision, and a project registered before this milestone needs no migration. The record
# is per project because that is where SCOPE §5 puts it and because it is what a person asks of one
# project; the decision above it is not, and is never taken from one of these files. All sessions
# share the one subscription, so `sessions_used` here is this project's share of an account-wide
# count and never an allowance of its own.
budget_record() {
  brc_dir=$BATON_HOME/projects/$1
  [ -d "$brc_dir" ] || return 0
  brc_want=$(printf '%s' "$2" | jq -c --arg k "$1" \
    '{window_start, sessions_used: (.per_project[$k] // 0), tier}')
  brc_file=$brc_dir/budget.json
  if [ -f "$brc_file" ] && brc_have=$(jq -c . "$brc_file" 2>/dev/null) \
     && [ "$brc_have" = "$brc_want" ]; then return 0; fi
  printf '%s\n' "$brc_want" > "$brc_file.tmp"
  mv "$brc_file.tmp" "$brc_file"
}

# budget_room: how many further session starts the count guard allows right now — a number, or
# empty when `budgetSessions` is 0 and the guard is off.
#
# The hold is a per-tick fact and the count guard cannot be one. It exists for the sub-tick moment
# the reading cannot cover: a pass admits several sessions at once and none of them has written a
# feed entry yet, so a guard consulted only before the pass would let the cap spend a whole tick's
# worth of starts past the allowance — which is the one thing the count is there to stop. So step 8
# reads this beside the cap and stops on whichever binds first. It is the same decision in the same
# dispatcher, not a second one: the number comes from `budget_state`, which is what the hold above
# is written from.
#
# **Every route that starts a session in a tick reads it, not only step 8.** The ladder's
# `redispatch` runs inside steps 3 to 6, before the dispatch pass, and writes `dispatch` events of
# its own; gated by `hold_bites` alone it would be gated by a count taken before its own work, which
# is the very gap the paragraph above describes. It asks this too. Each call re-reads the log, so a
# redispatch made a moment ago in the same tick is already in the number — the same reason
# `dispatch_run` re-reads the listing between its own dispatches (D-177).
budget_room() {
  # Every pacing number is read here, including the ones this function does not use, so that a
  # configuration Baton cannot read stops the dispatch rather than leaving one guard running and
  # the other silently off. `budget_check` would refuse on the same value and say so, but it only
  # reports — `hold_bites` reads the log, not that function — so the refusal has to reach the
  # dispatcher through something the dispatcher itself calls, and this is it.
  brm_allowed=$(budget_int budgetSessions 0) || { echo "$brm_allowed"; return 1; }
  brm_x=$(budget_int budgetCeiling 90) || { echo "$brm_x"; return 1; }
  brm_x=$(budget_int budgetWindowHours 5) || { echo "$brm_x"; return 1; }
  [ "$brm_allowed" -gt 0 ] || return 0
  brm_state=$(budget_state) || { echo "$brm_state"; return 1; }
  brm_used=$(printf '%s' "$brm_state" | jq -r .sessions_used)
  if [ "$brm_used" -lt "$brm_allowed" ]; then echo $((brm_allowed - brm_used)); else echo 0; fi
}

# budget_check: the pacing pass, once per tick across every project, beside `reserve_check`. Writes
# each project's record, then the one `hold` or `hold_lifted` that opens or closes the pause.
#
# Once and once, like the reserve's, so the log says when pacing began to bite and when it stopped
# rather than carrying a line a minute. The hold names no milestone and no session, and no project
# either: the allowance is one account's and the pause holds every project and every model alike.
#
# **A pause is not a failure.** It writes no `dispatch_failed`, moves no attempt, spends nothing on
# the ladder and raises no escalation; a candidate it bites is dropped in step 7's filter loop
# exactly as a held model's is, and the lane is a lane still waiting. Nor does it look like a
# running one: `status` prints it under the holds with the time it expects to lift.
#
# **It refuses in the direction the rest of the tick refuses in.** A log it cannot read fails the
# pass rather than reading as no starts at all, which would be pacing over work it cannot see; the
# tick reports that and `hold_bites` independently reads a failed derivation as held.
budget_check() {
  bck_state=$(budget_state) || { render_failure err "$bck_state"; return 1; }
  bck_holds=$(derive_holds) || { render_failure err "$bck_holds"; return 1; }
  bck_at=$(printf '%s' "$bck_holds" | jq -r 'first(.holds[] | select(.cause == "budget") | .resumes_at // "") // empty')
  bck_open=$(printf '%s' "$bck_holds" | jq 'any(.holds[]; .cause == "budget")')
  bck_paused=$(printf '%s' "$bck_state" | jq -r .paused)

  # A pause that outlived the boundary it named. The two guards nearly always lift at their own
  # boundary — an expired reading is no reading, and a start ageing out drops the count — but a
  # session a person ran through the boundary can put the new window over the ceiling too, and then
  # the standing hold names a time that has passed and `status` reads "resume due" under a pause
  # that is not lifting. That is the same confusion inverted that M14 exists to remove, so the hold
  # is closed and reopened for the window now holding: two lines, each true, rather than one that
  # has stopped being.
  if [ "$bck_paused" = true ] && [ "$bck_open" = true ] && [ -n "$bck_at" ]; then
    bck_was=$(iso_epoch "$bck_at") || { render_failure err "$bck_was"; return 1; }
    if [ "$bck_was" -le "$(now_epoch)" ]; then
      budget_hold_lifted "the window it named has ended and the next one is over the line too" || return 1
      bck_open=false
    fi
  fi

  if [ "$bck_paused" = true ] && [ "$bck_open" = false ]; then
    log_event hold "" "" "" "" "$(printf '%s' "$bck_state" | jq -c \
      '{model: "all", cause: "budget", resumes_at: .ends, reason: (.why | join("; ")),
        window_start, sessions_used, tier}
       + (if has("reading") then {reading, status_file} else {} end)')" || return 1
    render_row out action 'hold      %s · budget · %s · resumes at %s\n' \
      "$(render_token out state all)" \
      "$(printf '%s' "$bck_state" | jq -r '.why | join("; ")')" \
      "$(render_token out timestamp "$(printf '%s' "$bck_state" | jq -r .ends)")"
  elif [ "$bck_paused" = false ] && [ "$bck_open" = true ]; then
    budget_hold_lifted "the window rolled or the reading fell below the ceiling" || return 1
  fi
}

# budget_hold_lifted <why>: the one lift, with the sentence a person reads for it.
budget_hold_lifted() {
  log_event hold_lifted "" "" "" "" '{"model":"all","cause":"budget"}' || return 1
  render_row out record 'lifted    %s · budget · %s\n' "$(render_token out state all)" "$1"
}

# budget_record_all: every registered project's record, written last in the tick.
#
# Last, and not in `budget_check` beside the pause, because the pause has to be decided before step
# 7 and the record has to be written after step 8. A record written with the hold would describe
# the tick from before its own dispatches — a person reading `sessions_used` a second after a tick
# started two sessions would be told about neither — and a file that is a tick behind the log it
# was derived from is the inconsistency §8 asks the window and the count not to have.
#
# Nothing downstream reads it, so this pass failing costs the record and not the tick.
budget_record_all() {
  bra_state=$(budget_state) || { render_failure err "$bra_state"; return 1; }
  for bra_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$bra_pj" ] || continue
    budget_record "$(basename "$(dirname "$bra_pj")")" "$bra_state" || return 1
  done
}
