#!/bin/sh
# lib/candidates.sh — steps 5, 6 and 7 of the tick: which eligible milestones the tick dispatches,
# and in what order. Step 5 is the plan's alone. Step 6 intersects it with what the handovers said.
# Step 7 drops what a hold withholds and orders the rest under the cap. Step 8, the dispatch itself,
# is `lib/dispatch.sh`; `dispatch_run` in `lib/tick.sh` joins the two.
#
# **The plan wins on gates, both ways, and says so in the log** (REQ-DISPATCH-01). A gate is a
# person's recorded act, and a handover's word about it is always the older of the two: a `held` on
# a gate the plan shows cleared is dispatched, a `run` on a milestone the plan holds is not, and
# either is a `plan_override` and never an escalation. Exactly two things escalate, lane scope, by
# milestone name: a `run` the plan makes ineligible (`disagreement`) and a plan-eligible milestone no
# handover lists (`omitted`).
set -eu

# project_held <project>: whether an open project-scope park holds dispatch for the project. Prints
# the class of the first such park.
#
# A project escalation parks every lane of the project (CONTEXT.md, "Escalation scope"), and what it
# holds is the new work: no candidate is dispatched and no lane is redispatched while it stands.
# In-flight lanes run on — their resumes and their waits carry on — because each will meet the same
# ground at its own close-out, and a session stopped for it would lose work the park did not ask to
# lose (REQ-STOP-12). The self-check's parks already skip the whole project before this is asked, and
# a stale lock's is resolved in the tick that raised it, so in practice this is `main-broken`.
project_held() {
  # A park that cannot be read holds, because dispatching onto ground a person may have been asked to
  # fix is the mistake with no undo; the class it prints then says it is not known.
  phd_parked=$(derive_parked "$1") || { echo "$phd_parked" >&2; echo "unknown: the parks could not be read"; return 0; }
  phd_class=$(printf '%s' "$phd_parked" | jq -r 'first(.parked[] | select(.scope == "project") | .class) // empty')
  [ -n "$phd_class" ] || return 1
  printf '%s\n' "$phd_class"
}

# dispositions_in_force <project>: for every milestone a complete handover of the project names with
# a disposition Baton knows, the entry from the newest archived handover that lists it —
# {milestone, disposition, wait_for, held_by, archive, rank, index}, `rank` 0 for the newest archive
# and `index` the entry's place in that archive's `eligible[]`. Prints {has_handover, in_force}.
#
# The newest handover **that lists the milestone**, not the newest handover full stop: a milestone
# an older handover named and the newest does not mention is neither `run` nor `omitted`, and taking
# only the newest would drop it silently. An entry whose disposition is not `run`, `wait` or `held`
# does not list the milestone, so a garbled one reaches the person as an omission rather than as a
# guess.
#
# The order is the order the handovers were first acted on: derivation 4's `consumed`, which holds a
# handover once. A file delivered again repeats a handover rather than being one, is recorded as
# `repeated` and never as `consumed`, and so takes no place here — however late it arrives, it cannot
# stand in front of a handover written after it (D-095). `cap_order` reads the rank this prints.
dispositions_in_force() {
  dif_doc=$(derive_consumed "$1") || { echo "$dif_doc"; return 1; }
  dif_files=$(printf '%s' "$dif_doc" | jq -c \
    '[ .consumed[] | select(.outcome == "complete" and .archive_present) | .archive ] | reverse')
  dif_all='[]'; dif_read=0
  dif_n=$(printf '%s' "$dif_files" | jq length); dif_i=0
  while [ "$dif_i" -lt "$dif_n" ]; do
    dif_f=$(printf '%s' "$dif_files" | jq -r ".[$dif_i]")
    dif_rank=$dif_i; dif_i=$((dif_i + 1))
    [ -f "$dif_f" ] || continue
    # Only a handover that can be read counts as one: a project whose every complete archive has been
    # moved away has nothing an omission could have been missed by.
    dif_read=$((dif_read + 1))
    dif_entries=$(jq -c --arg a "$dif_f" --argjson r "$dif_rank" '
      [ (.eligible // []) | to_entries[] | .key as $k | .value
        | select(type == "object" and (.milestone | type) == "string")
        | select(.disposition == "run" or .disposition == "wait" or .disposition == "held")
        | {milestone, disposition,
           wait_for: (if (.wait_for | type) == "array" then .wait_for else [] end),
           held_by: (if (.held_by | type) == "string" then .held_by else null end),
           archive: $a, rank: $r, index: $k} ]' "$dif_f" 2>/dev/null) || dif_entries='[]'
    dif_all=$(jq -nc --argjson a "$dif_all" --argjson b "$dif_entries" '$a + $b')
  done
  jq -nc --argjson all "$dif_all" --argjson n "$dif_read" '
    {has_handover: ($n > 0),
     in_force: ($all | group_by(.milestone) | map(min_by([.rank, .index])))}'
}

# intersect_verdicts <project> <plan json> <in force json> <has handover> <open lanes json>
# <parks json>: step 6 as data, with the log on stdin. One verdict per milestone that is eligible or
# named by a handover in force, and one `clear` per open `omitted` or `disagreement` park whose
# condition no longer holds. Prints {candidates, overrides, conditions, clears}.
#
# `omitted` waits while a dependency's session is still mid-run — its newest dispatch or delivered
# resume is later than its newest ending the session wrote itself. A close-out writes `done` at step
# (c) and its artifact at step (d), seconds or minutes apart, and a tick in between would otherwise
# read the successor as eligible and unlisted every time a milestone finished. Only a
# session-written ending ends the run: an `api-error` or `no-handover` artifact is a hook's, the wait
# or the ladder resumes that session, and its handover is still to come.
#
# An omission held back that way is `suspended`: it raises nothing, and it does not clear a park
# already standing either. Clearing it would write `how: edit` for a change nobody made, and
# `person_acted` would then read that as a person's edit and dispatch the milestone unlisted the
# next time the condition showed.
intersect_verdicts() {
  jq -c --arg p "$1" --argjson plan "$2" --argjson force "$3" --argjson has "$4" \
    --argjson open "$5" --argjson parks "$6" '
    def midrun($ev; $m):
      ([ $ev[] | select(.milestone == $m and (.kind == "dispatch"
                        or (.kind == "consumed" and .written_by == "session")
                        or (.kind == "resume" and (.outcome == "delivered" or .outcome == "forked")))) ]
       | last | .kind // "consumed") != "consumed";
    [ .[] | select(.project == $p) ] as $ev
    | ($plan.milestones | map({key: .id, value: .}) | from_entries) as $rows
    | ($plan.milestones | map(select(.status == "done") | .id)) as $done
    | ([ $plan.gates[] | select(.cleared == "") ]) as $open_gates
    | ($force | map({key: .milestone, value: .}) | from_entries) as $by
    | ([ $open_gates[] | .holds[] ]) as $held
    | [ $plan.milestones[] | .id as $i
        | select(.status == "" and ($held | index($i) | not)
                 and all(.depends[]; . as $d | $done | index($d) != null))
        | $i ] as $eligible
    | ([ $eligible[], ($force[] | .milestone) ] | unique) as $names
    | [ $names[] | . as $m | select($open | index($m) | not)
        | $rows[$m] as $row | $by[$m] as $d
        | ($eligible | index($m) != null) as $el
        | ([ $open_gates[] | select(.holds | index($m) != null) | .gate ]) as $gates
        | {milestone: $m, row: ($row.row // 0), model: ($row.model // ""), remote: ($row.remote // false)} as $base
        | if $row != null and $row.status == "done" then empty
          elif $d == null then
            if $el and $has
            then {kind: "condition", class: "omitted", milestone: $m,
                  suspended: any($row.depends[]; midrun($ev; .)),
                  detail: "no archived handover of \($p) lists \($m), though the plan makes it eligible",
                  # Ranked after every entry any handover wrote: a person edited it into the order,
                  # and a milestone a handover did list keeps its place ahead of it.
                  candidate: ($base + {rank: 1000000000, index: 0})}
            else empty end
          elif $d.disposition == "run" then
            if $el then {kind: "candidate"} + $base + {rank: $d.rank, index: $d.index}
            elif $row != null and ($row.status == "held" or ($gates | length) > 0) then
              {kind: "override", milestone: $m, direction: "withheld_over_run", gate: $gates[0]}
            else
              ($row.depends // [] | map(select(. as $x | $done | index($x) == null))) as $undone
              | {kind: "condition", class: "disagreement", milestone: $m, disposition: "run",
                 handover: $d.archive, waiting_on: $undone,
                 detail: ("the handover \($d.archive | sub("^.*/"; "")) says run \($m), and the plan makes it ineligible: "
                          + (if $row == null then "the plan has no row for \($m)"
                             else "\($undone | join(", ")) \(if ($undone | length) == 1 then "is" else "are" end) not done" end))}
            end
          elif $d.disposition == "wait" then
            if $el and all($d.wait_for[]; . as $w | $done | index($w) != null)
            then {kind: "candidate"} + $base + {rank: $d.rank, index: $d.index} else empty end
          else
            if $el then
              ([ $plan.gates[] | select(.gate == $d.held_by) | .cleared ] | first // "") as $cleared
              | {kind: "candidate"} + $base + {rank: $d.rank, index: $d.index,
                  override: ({direction: "dispatched_over_held", gate: $d.held_by, cleared_by: $cleared}
                             | with_entries(select(.value != null and .value != "")))}
            else empty end
          end
        | with_entries(select(.value != null)) ] as $v
    | { candidates: [ $v[] | select(.kind == "candidate") | del(.kind) | . + {project: $p} ],
        overrides: [ $v[] | select(.kind == "override") | del(.kind) ],
        conditions: [ $v[] | select(.kind == "condition" and (.suspended | not)) | del(.kind, .suspended) ],
        clears: [ $parks[] | . as $k
                  | select(any($v[]; .kind == "condition" and .milestone == $k.milestone
                                     and .class == $k.class) | not)
                  | . + {why: (if ($open | index($k.milestone)) != null then "its lane is open"
                               elif ($rows[$k.milestone].status // "") == "done" then "it reads done"
                               elif $k.class == "omitted" and $by[$k.milestone] != null then "a handover now lists it"
                               elif $k.class == "omitted" then "the plan no longer makes it eligible"
                               elif ($eligible | index($k.milestone)) != null then "the plan now makes it eligible"
                               else "the handover in force no longer says run" end)} ] }'
}

# plan_override_spent <project> <milestone> <direction> <gate>: whether this override is already on
# record since the milestone's newest dispatch. The table gives the event no once-only key, but a
# tick that wrote it again every sixty seconds would change the state on every run, which INV-05
# forbids; and a dispatch starts a new decision, so the key re-arms there.
plan_override_spent() {
  pos_log=$(log_json) || { echo "$pos_log" >&2; return 0; }
  printf '%s' "$pos_log" | jq -e --arg p "$1" --arg m "$2" --arg d "$3" --arg g "$4" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch") ] | last | .i // -1) as $reset
    | any($ev[]; .kind == "plan_override" and .i > $reset and .direction == $d and (.gate // "") == $g)' \
    > /dev/null
}

# plan_override_once <project> <milestone> <override json>: the record of the plan doing its job.
plan_override_once() {
  poo_d=$(printf '%s' "$3" | jq -r .direction)
  poo_g=$(printf '%s' "$3" | jq -r '.gate // ""')
  plan_override_spent "$1" "$2" "$poo_d" "$poo_g" && return 0
  poo_fields=$(printf '%s' "$3" | jq -c '{direction, gate, cleared_by} | with_entries(select(.value != null))')
  log_event plan_override "$1" "$2" "" "" "$poo_fields" || return 1
  poo_line=$(printf '%s' "$3" | jq -r --arg p "$1" --arg m "$2" '
    if .direction == "withheld_over_run"
    then "override  \($p)/\($m) · the handover says run and the plan holds it"
         + (if .gate then " by gate \"\(.gate)\"" else "" end) + " · withheld"
    else "override  \($p)/\($m) · the handover says held by \"\(.gate // "")\" and the plan does not hold it"
         + (if .cleared_by then ", cleared by \(.cleared_by)" else "" end) + " · dispatched" end')
  printf '%s\n' "$poo_line"
}

# dispositions_intersect <project> <plan json> <rows json>: step 6 for one project, acted on. Writes
# the resolutions, the withheld overrides and the two escalations, and prints {candidates, lines}:
# the milestones step 7 may dispatch, each with its order key and any override to record at dispatch,
# and what a person reads in launchd.out. The dispatched override is written after the dispatch, not
# here, so that neither a candidate the cap holds back nor a dispatch that failed leaves a record of a
# dispatch that did not happen.
#
# An `omitted` or `disagreement` park ends when its condition does — a handover that now lists the
# milestone, a dependency that now reads done, a newer handover that no longer says run — because
# neither parks a session, so no ruling reaches it, and the re-read hashes see only the plan rows and
# the brief. And each ends by an edit the usual way (D-061): after one, an omitted milestone the plan
# still makes eligible is dispatched, because the person edited rather than held it; a disagreement
# is withheld silently until the plan makes the milestone eligible, because the plan wins.
dispositions_intersect() {
  dsi_p=$1; dsi_plan=$2; dsi_rows=$3
  dsi_log=$(log_json) || { echo "$dsi_log"; return 1; }
  dsi_force=$(dispositions_in_force "$dsi_p") || { echo "$dsi_force"; return 1; }
  dsi_open=$(lanes_open "$dsi_p" "$dsi_log") || { echo "$dsi_open"; return 1; }
  dsi_open=$(printf '%s' "$dsi_open" | jq -c '[ .[] | .milestone ] | unique')
  dsi_parked=$(derive_parked "$dsi_p") || { echo "$dsi_parked"; return 1; }
  dsi_parks=$(printf '%s' "$dsi_parked" | jq -c '[ .parked[] | select(.scope == "lane"
    and (.class == "omitted" or .class == "disagreement")) | {at, milestone, class, session, attempt} ]')
  dsi_v=$(printf '%s' "$dsi_log" | intersect_verdicts "$dsi_p" "$dsi_plan" \
    "$(printf '%s' "$dsi_force" | jq -c .in_force)" "$(printf '%s' "$dsi_force" | jq -c .has_handover)" \
    "$dsi_open" "$dsi_parks") || { echo "the intersection for $dsi_p could not be computed"; return 1; }

  dsi_lines=''
  dsi_n=$(printf '%s' "$dsi_v" | jq '.clears | length'); dsi_i=0
  while [ "$dsi_i" -lt "$dsi_n" ]; do
    dsi_e=$(printf '%s' "$dsi_v" | jq -c ".clears[$dsi_i]"); dsi_i=$((dsi_i + 1))
    resolve "$dsi_p" "$(printf '%s' "$dsi_e" | jq -r .milestone)" "" "" "$(printf '%s' "$dsi_e" | jq -r .at)" edit
    dsi_lines="$dsi_lines$(printf '%s' "$dsi_e" | jq -r --arg p "$dsi_p" \
      '"unparked  \($p)/\(.milestone) · the \(.class) no longer holds: \(.why)"')
"
  done

  dsi_n=$(printf '%s' "$dsi_v" | jq '.overrides | length'); dsi_i=0
  while [ "$dsi_i" -lt "$dsi_n" ]; do
    dsi_e=$(printf '%s' "$dsi_v" | jq -c ".overrides[$dsi_i]"); dsi_i=$((dsi_i + 1))
    dsi_said=$(plan_override_once "$dsi_p" "$(printf '%s' "$dsi_e" | jq -r .milestone)" "$dsi_e") || continue
    [ -z "$dsi_said" ] || dsi_lines="$dsi_lines$dsi_said
"
  done

  dsi_cands=$(printf '%s' "$dsi_v" | jq -c .candidates)
  dsi_parked=$(derive_parked "$dsi_p") || { echo "$dsi_parked"; return 1; }
  dsi_n=$(printf '%s' "$dsi_v" | jq '.conditions | length'); dsi_i=0
  while [ "$dsi_i" -lt "$dsi_n" ]; do
    dsi_e=$(printf '%s' "$dsi_v" | jq -c ".conditions[$dsi_i]"); dsi_i=$((dsi_i + 1))
    dsi_m=$(printf '%s' "$dsi_e" | jq -r .milestone)
    dsi_c=$(printf '%s' "$dsi_e" | jq -r .class)
    if printf '%s' "$dsi_parked" | jq -e --arg m "$dsi_m" --arg c "$dsi_c" \
         'any(.parked[]; .scope == "lane" and .milestone == $m and .class == $c)' > /dev/null; then
      continue
    fi
    case "$(person_acted "$dsi_p" "$dsi_m" "$dsi_c")" in
      edit)
        [ "$dsi_c" = omitted ] || continue
        dsi_cands=$(printf '%s' "$dsi_cands" | jq -c --argjson c "$(printf '%s' "$dsi_e" | jq -c --arg p "$dsi_p" '.candidate + {project: $p}')" '. + [$c]')
        continue ;;
      ruling) continue ;;
    esac
    escalate "$dsi_p" "$dsi_m" "" "" "$dsi_c" lane "$(printf '%s' "$dsi_e" | jq -c 'del(.class, .milestone, .candidate)')"
    dsi_lines="$dsi_lines$(printf '%s  %s/%s · %s · the lane is parked' "$dsi_c" "$dsi_p" "$dsi_m" "$(printf '%s' "$dsi_e" | jq -r .detail)")
"
  done

  # What survives is a candidate unless a person has to answer its lane first, or a live row already
  # carries its name. The last is what a hand-started session under Baton's own name looks like, and
  # dispatching over it is the one mistake with no undo. A Remote: yes milestone is a candidate like
  # any other: the dispatch command is the same for every row, and Remote Control rides in the
  # settings file every dispatch composes (REQ-DISPATCH-07, D-080).
  dsi_out='[]'
  dsi_n=$(printf '%s' "$dsi_cands" | jq length); dsi_i=0
  while [ "$dsi_i" -lt "$dsi_n" ]; do
    dsi_e=$(printf '%s' "$dsi_cands" | jq -c ".[$dsi_i]"); dsi_i=$((dsi_i + 1))
    dsi_m=$(printf '%s' "$dsi_e" | jq -r .milestone)
    printf '%s' "$dsi_parked" | jq -e --arg m "$dsi_m" \
      'any(.parked[]; .milestone == $m and .scope == "lane") | not' > /dev/null || continue
    printf '%s' "$dsi_rows" | jq -e --arg n "$(session_name "$dsi_p" "$dsi_m")" \
      'any(.[]; .name == $n and .pid != null) | not' > /dev/null || continue
    dsi_out=$(printf '%s' "$dsi_out" | jq -c --argjson e "$dsi_e" '. + [$e]')
  done
  jq -nc --argjson c "$dsi_out" --arg l "$dsi_lines" \
    '{candidates: $c, lines: ($l | split("\n") | map(select(length > 0)))}'
}

# cap_order <candidates json> <in-flight per project json>: step 7's order, as one list
# (REQ-DISPATCH-02). Within a project, the handover's `eligible[]` order; across projects, the project
# with fewer in flight first, counting each dispatch this order makes ahead of it; then plan row order;
# then the project key, so that two ties can never depend on the order the directory was read in.
#
# The count moves as the list is built rather than being read once, because "the project with fewer in
# flight" is a question asked of every slot: two idle projects with two candidates each take one slot
# each, not both slots to whichever sorted first.
cap_order() {
  jq -nc --argjson c "$1" --argjson n "$2" '
    def key: [.rank, .index, .row, .milestone];
    { q: ($c | group_by(.project) | map({key: .[0].project, value: sort_by(key)}) | from_entries),
      n: $n, out: [] }
    | until(([ .q[] | length ] | add // 0) == 0;
        . as $s
        | ([ $s.q | to_entries[] | select((.value | length) > 0)
             | {p: .key, k: [($s.n[.key] // 0), .value[0].row, .key]} ] | min_by(.k) | .p) as $p
        | .out += [ .q[$p][0] ] | .q[$p] |= .[1:] | .n[$p] = ((.n[$p] // 0) + 1))
    | .out'
}
