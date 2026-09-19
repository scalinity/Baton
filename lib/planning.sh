#!/bin/sh
# lib/planning.sh — plan generation: a registered project with no plan Baton can read gets one
# written for it by a dispatched session, and Baton adopts the result only when it parses and
# conforms.
#
# M11 leaves this state exactly: `plan_format` reads `generated`, `plan_owed` carries the reason and
# names M12 as its owner, and there is no `start`, because there is no milestone to name. The next
# tick's self-check then parks the project `plan-unreadable`, which is accurate — a project whose
# plan cannot be read cannot be driven — and which is what this file clears (D-161).
#
# Four things follow from that, and they are the shape of this file:
#
#   * **Generation is a session, not a request.** Reading a whole repository and writing a plan and
#     its briefs is a session's work and has a session's cost, so it is dispatched like a
#     milestone's: a name, an attempt, a baseline, an injected Stop gate, an owed artifact and one
#     admission slot (`docs/ARCHITECTURE.md` §4.5, D-158). Nothing in the tick waits on its result:
#     the tick dispatches it and returns, its handover closes the lane, and the next tick reads the
#     answer. A verb or a tick that blocked on a session it had just dispatched would hold the lock
#     while the session it waited for could not be admitted, and `do_unresolved` counts a launch
#     that could not be proved to have started nothing (D-130).
#
#   * **The target repository is written, and this is the one place Baton has one written.** M11
#     records what a plan needs in order to be read as the registration's `adaptation` and leaves
#     the project's own documents alone (D-156, REQ-ONBOARD-02), because it is adapting someone
#     else's plan. Generation *authors* the plan and its briefs, so they are written where a plan
#     and its briefs live: in the target, committed, as the project's own documents. The dispatched
#     session writes them through the target's ordinary Git close-out; Baton itself still writes
#     nothing there.
#
#   * **Adoption goes through onboarding's own seeding path.** `onboard_commit` with the seed is the
#     write M11 already has — the rail, the registration, then the event, in one order — and
#     `onboard_start` is the `eligible[]` it seeds from. Generation calls it directly rather than
#     re-running `verb_onboard`, which prints a report written for a person at a terminal and
#     `exit`s on several paths — and an `exit` inside the tick ends the tick rather than the pass.
#     What nothing here does is compute eligibility a second way.
#
#   * **The plan is measured, not hoped.** Everything the generator is told to satisfy is something
#     `plan_tables`, `dispatch_preconditions` or this file can check, and a plan that fails one is
#     not adopted: its defects go back into the next attempt's prompt as concrete repairs, and the
#     partial work stays on the branch so that attempt repairs it rather than writing a second graph.
set -eu

# The planning lane's milestone id. It has to be one `parse_id` accepts, because `artifact_ids`
# recovers a handover's identity from its filename through that function and a name it refuses is a
# handover that can never be rejected — it would sit in the inbox for ever. It is reserved: a
# generated plan naming `M00-plan` as one of its own rows is refused.
PLANNING_ID=M00-plan

# Where the generator is told to write the plan. `onboard_plan_find` still decides where Baton reads
# one from, so a session that wrote it elsewhere is found anyway; this is the path the prompt names
# and half of what the planning role declares as its scope.
PLANNING_PLAN=docs/MILESTONES.md
PLANNING_BRIEFS=docs/milestones

# How many attempts generation gets before Baton stops spending a session a tick on it.
PLANNING_ATTEMPTS_DEFAULT=3

# What travels into the next attempt's prompt and onto the event. Bounded at the source for
# `log_event`'s reason: a line of 4 KB or more is refused, and a refusal here would lose the record
# of a generation that happened.
PLANNING_DEFECTS_SHOWN=12
PLANNING_DEFECT_CHARS=300

# A literal tab, built rather than typed: the defect lines the bulk producers answer with are joined
# on one, and a tab written into the source is invisible to a reader and the first thing an editor
# turns into spaces.
PLANNING_TAB=$(printf '\t')

# The slot paragraph, verbatim, as CONTRACT.md clause 1 fixes it. It is here because generation is
# the one place Baton checks a brief for it letter by letter: `dispatch_preconditions` asks only
# whether a paragraph begins with those first words, which is the right question of a plan a person
# wrote and the wrong one of a plan Baton commissioned with the sentence quoted in the prompt.
PLANNING_SLOT='WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.'

# planning_owed <project key>: the registration's `plan_owed`, or status 1 when nothing is owed.
# The one test for "this project is waiting on a plan", asked of the registration and never of the
# absence of a file: a project whose plan file was deleted by hand is a `plan-unreadable` park for a
# person to fix, not a repository Baton starts authoring documents in.
planning_owed() {
  pow_f=$BATON_HOME/projects/$1/project.json
  [ -f "$pow_f" ] || return 1
  jq -ce '.plan_owed | select(type == "object")' "$pow_f" 2>/dev/null
}

# planning_attempts <project key>: how many generation attempts this project has had, which is the
# count of the planning lane's dispatches. The log is the record and the registration is not: an
# attempt is a dispatch event, and a second counter would be a second truth about one fact.
planning_attempts() { attempt_of "$1" "$PLANNING_ID"; }

# planning_attempts_max: the bound, from config.json. Validated as text before it is compared, the
# way `completion_check_command` validates its deadline: `config_num` hands back whatever the file
# holds, and `[ 0 -ge abc ]` is an error rather than a comparison — which reads as "the bound is not
# reached" and quietly removes the bound. A value that is not a number falls back to the default.
planning_attempts_max() {
  pam_v=$(config_num planningAttempts "$PLANNING_ATTEMPTS_DEFAULT")
  case "$pam_v" in
    ''|*[!0-9]*) pam_v=$PLANNING_ATTEMPTS_DEFAULT ;;
    *) [ "${#pam_v}" -le 9 ] || pam_v=$PLANNING_ATTEMPTS_DEFAULT ;;
  esac
  printf '%s\n' "$pam_v"
}

# planning_scope_patterns: the planning role's declared scope, in `completion_scope_patterns`' own
# one-pattern-per-line shape.
#
# A milestone declares its scope in its brief's §5 and a completion is proved against it. The
# planning role has no brief in the target — its prompt is Baton's own text, composed below — so
# Baton states the scope itself, and it is the stronger evidence of the two: what Baton asked for,
# rather than what a session wrote about what it meant to do. The two paths are the two the prompt
# names, and every conforming generation changes both.
planning_scope_patterns() { printf '%s\n%s\n' "$PLANNING_BRIEFS" "$PLANNING_PLAN"; }

# planning_model / planning_effort: what the planning session runs at. Planning is the work every
# later milestone inherits, so it defaults to the capable model at high effort; both are one line in
# config.json for a person who wants otherwise.
#
# The model is resolved through `parse_model`, as a plan cell is, so an alias `config.json` maps
# reaches `claude_bg` as the id it maps to. A value that is neither a mapped alias nor a
# `claude-…` id is passed through as it was written rather than refused: a plan cell that will not
# parse parks the whole project, which is right for a document a person wrote and wrong for one
# number in Baton's own config — the CLI refuses the model itself, and its refusal is the message,
# recorded as a `dispatch_failed` at the launch stage.
planning_model() {
  pmo_alias=$(jq -r '.planningModel // "opus"' "$BATON_HOME/config.json" 2>/dev/null) || pmo_alias=opus
  [ -n "$pmo_alias" ] && [ "$pmo_alias" != null ] || pmo_alias=opus
  pmo_models=$(jq -c '.models // {}' "$BATON_HOME/config.json" 2>/dev/null || echo '{}')
  parse_model "$pmo_alias" "$pmo_models" 2>/dev/null || printf '%s\n' "$pmo_alias"
}
planning_effort() {
  peo_v=$(jq -r '.planningEffort // "high"' "$BATON_HOME/config.json" 2>/dev/null) || peo_v=high
  [ -n "$peo_v" ] && [ "$peo_v" != null ] || peo_v=high
  parse_effort "$peo_v" 2>/dev/null || printf '%s\n' high
}

# planning_defect <what> <repair>: one defect onto the ordered array its caller is building. A
# helper of `planning_validate` alone, which is why it reads and writes that function's variable —
# `dp_add` is the same shape for the same reason.
#
# `what` is the sentence a person and the next attempt both read; `repair` is the concrete act that
# fixes it, named on its own so nothing has to recover it from prose.
planning_defect() {
  pv_defects=$(printf '%s' "$pv_defects" | jq -c --arg w "$1" --arg r "$2" \
    '. + [{what: $w, repair: $r}]')
}

# planning_defects_from <tab-separated lines>: every `<what>\t<repair>` line onto the same array.
# The two producers that answer in bulk — the one jq pass over the table, and the per-brief checks —
# both come back as lines, and a `while read` over them would run `planning_defect` in a subshell
# whose assignment to `pv_defects` dies with it. The split is a `for` over an IFS of one newline,
# with globbing off so a defect naming `docs/*` is not expanded into the files it matches.
planning_defects_from() {
  [ -n "$1" ] || return 0
  pdf_old_ifs=$IFS
  IFS='
'
  set -f
  for pdf_l in $1; do
    [ -n "$pdf_l" ] || continue
    planning_defect "${pdf_l%%"$PLANNING_TAB"*}" "${pdf_l#*"$PLANNING_TAB"}"
  done
  set +f
  IFS=$pdf_old_ifs
}

# planning_brief_defects <checkout> <milestone id> <successor ids, space separated>: what a
# generated brief must carry beyond what `dispatch_preconditions` already inspects.
#
# The division is deliberate. `dispatch_preconditions` is the instrument that already names a brief
# absent from `main`, a heading with no complete fenced block under it, a prompt with no slot
# paragraph and a `docs/…` reference the prompt names that `main` does not have — every knowable
# reason a dispatch would refuse. What it does not ask is whether the brief is *shaped* like a brief,
# because for a hand-written plan that is a person's business. For a generated one it is Baton's,
# and these are the four questions whose answers a later session depends on:
#
#   * the eleven sections and the three unnumbered headings, which is the format every brief in the
#     plan inherits and the thing a fresh session navigates by;
#   * `## Completion evidence` empty, because the recovery clause keys on it: a brief that arrives
#     with evidence already under that heading tells the first session to resume work nobody did;
#   * §5 naming at least one path between backticks, read through `completion_scope_patterns` — the
#     very function that will judge the milestone's completion, so a brief that passes here is one
#     whose honest completion cannot be refused for declaring no scope (D-150);
#   * §11 naming every milestone whose `Depends on` names this one, because Baton dispatches only
#     what a handover lists and a close-out that omits a successor stops the chain there.
#
# Prints one `<what>\t<repair>` per defect, tab separated, and nothing when the brief is sound.
planning_brief_defects() {
  pbd_c=$1; pbd_id=$2; pbd_succ=${3:-}
  pbd_rel=$PLANNING_BRIEFS/$pbd_id.md
  pbd_text=$(git -C "$pbd_c" show "main:$pbd_rel" 2>/dev/null) || return 0

  # The headings, by exact line rather than by prefix: a `## 1a.` is not `## 1.`, and a brief whose
  # sections were renamed reads as a different document to the session navigating it.
  pbd_missing=$(printf '%s\n' "$pbd_text" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^## / { have[trim($0)] = 1 }
    END {
      out = ""
      for (i = 1; i <= 11; i++) {
        found = 0
        for (h in have) if (h ~ ("^## " i "\\.")) found = 1
        if (!found) out = out (out == "" ? "" : ", ") "## " i "."
      }
      split("Recovery procedure|Completion evidence|Copy-ready session prompt", want, "|")
      for (i = 1; i <= 3; i++) if (!("## " want[i] in have)) out = out (out == "" ? "" : ", ") "## " want[i]
      print out
    }')
  [ -z "$pbd_missing" ] \
    || printf '%s\t%s\n' \
         "$pbd_rel has no $pbd_missing, and a brief a session navigates by its headings needs the eleven numbered sections and the three unnumbered ones" \
         "add the missing headings to $pbd_rel in MILESTONE FORMAT order and commit it on main"

  # Everything between `## Completion evidence` and the next `## ` heading, which must be nothing.
  pbd_evidence=$(printf '%s\n' "$pbd_text" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    trim($0) == "## Completion evidence" { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && trim($0) != "" { print }' | head -1)
  [ -z "$pbd_evidence" ] \
    || printf '%s\t%s\n' \
         "$pbd_rel has content under ## Completion evidence before anybody has done the milestone, and the recovery clause reads that section as work already begun" \
         "empty the ## Completion evidence section of $pbd_rel and commit it on main"

  # The kickoff prompt's own anatomy. `dispatch_preconditions` already establishes that there is a
  # complete fenced block under the heading and that it carries *a* paragraph beginning with the slot
  # line's first words; what it does not ask is whether that paragraph is the slot line **verbatim**,
  # which CONTRACT clause 1 requires, or whether the block has the seven parts. Both are Baton's
  # business here and a person's business in a plan Baton did not author: this text was commissioned
  # with the labels named, so a block missing one is a block that did not do what it was asked.
  pbd_block=$(printf '%s\n' "$pbd_text" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    !found && trim($0) == "## Copy-ready session prompt" { found = 1; next }
    found && !infence && /^## / { exit }
    found && !infence && /^```/ { infence = 1; next }
    found && infence && /^```/ { exit }
    found && infence { print }')
  if [ -n "$pbd_block" ]; then
    # The line, and the blank line after it. `slot_line` replaces the paragraph and swallows every
    # non-blank line that follows, so a brief whose part 3 begins on the next line loses its whole
    # STARTUP ORDER at dispatch and nothing says so — the prompt simply arrives without it. The two
    # are one defect with one repair, so they are reported as one.
    printf '%s\n' "$pbd_block" | awk -v want="$PLANNING_SLOT" '
      $0 == want { found = 1; getline nextline; if (nextline ~ /^[ \t]*$/) alone = 1; exit }
      END { exit (found && alone ? 0 : 1) }' || printf '%s\t%s\n' \
      "$pbd_rel does not carry the slot paragraph verbatim as its own paragraph: Baton matches the whole sentence and then replaces every line up to the next blank one, so a part 3 beginning on the next line is swallowed with it" \
      "make part 2 of the fenced block in $pbd_rel exactly \"$PLANNING_SLOT\", alone on its line with a blank line after it, and commit it on main"
    for pbd_part in 'STARTUP ORDER' 'WHAT TO SETTLE RATHER THAN INHERIT' CONSTRAINTS VERIFICATION CLOSE-OUT; do
      printf '%s\n' "$pbd_block" | grep -Fq "$pbd_part" && continue
      printf '%s\t%s\n' \
        "$pbd_rel has no $pbd_part part in its kickoff prompt, and a prompt run by a session that remembers nothing of the one that wrote it needs all seven" \
        "write the $pbd_part part into the fenced block in $pbd_rel and commit it on main"
    done
  fi

  # The Size the brief declares, read from §1 and not from the whole document: the kickoff prompt
  # states it too, and a brief whose only Size is inside the fenced block has told the session and
  # not the plan. §1 is where a person and a later dispatch both look for it.
  printf '%s\n' "$pbd_text" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^## / { inside = (trim($0) ~ /^## 1\./) ; next }
    inside { print }' | grep -q 'Size:' || printf '%s\t%s\n' \
    "$pbd_rel declares no Size in its ## 1. section, so nothing in the plan says whether the milestone is one session of work or three" \
    "write a Size line into the ## 1. section of $pbd_rel — Small, Medium or Large, with about how many hours — and commit it on main"

  # §5, read by the function that will judge the milestone's completion.
  if ! pbd_scope=$(completion_scope_patterns "$pbd_c" "$pbd_id" 2>/dev/null) || [ -z "$pbd_scope" ]; then
    printf '%s\t%s\n' \
      "$pbd_rel declares no scope: its ## 5. section names no repository path between backticks, and Baton proves a completion by finding one changed path inside that section" \
      "name the paths $pbd_id will change in the ## 5. section of $pbd_rel, each between backticks, and commit it on main"
  fi

  # §11 against the graph.
  if [ -n "$pbd_succ" ]; then
    pbd_eleven=$(printf '%s\n' "$pbd_text" | awk '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      /^## / { inside = (trim($0) ~ /^## 11\./) ; next }
      inside { print }')
    for pbd_s in $pbd_succ; do
      printf '%s\n' "$pbd_eleven" | grep -Fq "$pbd_s" && continue
      printf '%s\t%s\n' \
        "$pbd_rel does not name $pbd_s in its ## 11. section, and $pbd_s depends on $pbd_id: Baton dispatches only what a handover lists, so the chain would stop at $pbd_id" \
        "name $pbd_s as a successor in the ## 11. section of $pbd_rel and commit it on main"
    done
  fi
}

# planning_validate <project key> <checkout>: whether the repository now holds a plan Baton will
# adopt, as `{plan, plan_format, tables, defects: [{what, repair}]}`. An empty `defects` is the
# only thing that admits a plan.
#
# It is one pass and it does not stop at the first defect, for `plan_preconditions_report`'s own
# reason: the defects go back into the next attempt's prompt, and an attempt told about one defect
# at a time costs a session per defect.
#
# **A generated plan must read `native`.** `adapted` means Baton's reader supplied a column the plan
# did not have — which is right for somebody else's plan and wrong for one Baton commissioned with
# the columns named. Adopting it would put an `adaptation` in the registration for a document Baton
# asked for, which is Baton tolerating its own output's deviation, and the repair is one concrete
# column rather than a permission granted for ever (D-166).
planning_validate() {
  pv_key=$1; pv_c=$2
  pv_defects='[]'
  pv_plan=''
  pv_fmt=''
  pv_tables=null

  # The registered pointer first, as `verb_onboard` passes it, so a project whose plan a person put
  # somewhere other than the conventional path is read there rather than searched for again.
  pv_registered=$(jq -r '.plan // ""' "$BATON_HOME/projects/$pv_key/project.json" 2>/dev/null) || pv_registered=''
  if ! pv_plan=$(onboard_plan_find "$pv_c" "$pv_registered") || [ -z "$pv_plan" ]; then
    pv_plan=''
    planning_defect \
      "no file in $pv_c holds a milestone table: Baton looks for a header carrying both ID and Depends on, under docs/ first and then the repository to a depth of three" \
      "write the milestone table into $PLANNING_PLAN with an ID column and a Depends on column, and commit it on main"
    jq -nc --argjson d "$pv_defects" '{plan: "", plan_format: "", tables: null, defects: $d}'
    return 0
  fi

  pv_class=$(onboard_classify "$pv_c" "$pv_plan")
  pv_fmt=$(printf '%s' "$pv_class" | jq -r .plan_format)
  pv_tables=$(printf '%s' "$pv_class" | jq -c .tables)
  case "$pv_fmt" in
    native) ;;
    adapted)
      planning_defect \
        "$pv_plan parses only with Baton's own defaults for $(printf '%s' "$pv_class" | jq -r '(.adaptation.defaults // {}) | keys | join(", ")'), and a plan Baton asked for is read strictly" \
        "give the milestone table in $pv_plan every column the generation prompt names — ID, Depends on, Model, Effort, Remote, Status — and commit it on main" ;;
    unmapped)
      planning_defect \
        "$pv_plan has Status values Baton cannot map to done, held or blank: $(printf '%s' "$pv_class" | jq -r '.unmapped // ""')" \
        "leave every Status cell in $pv_plan blank and commit it on main" ;;
    *)
      planning_defect \
        "$(printf '%s' "$pv_class" | jq -r '.detail // "the milestone table could not be read"')" \
        "repair the cell the reader named in $pv_plan and commit it on main" ;;
  esac
  if [ "$pv_fmt" != native ]; then
    jq -nc --arg p "$pv_plan" --arg f "$pv_fmt" --argjson d "$pv_defects" \
      '{plan: $p, plan_format: $f, tables: null, defects: $d}'
    return 0
  fi

  # The table as a graph. One jq pass over the parsed document, printing `<what>\t<repair>` per
  # defect, because each of these is a question about the whole table rather than about one row.
  pv_lines=$(printf '%s' "$pv_tables" | jq -r --arg plan "$pv_plan" --arg res "$PLANNING_ID" '
    ([ .milestones[] | .id ]) as $ids
    | [ if ($ids | length) == 0
        then ["the milestone table in \($plan) has a header and no rows, so the plan names no work",
              "write one row per milestone into the milestone table in \($plan) and commit it on main"]
        else empty end,
        ( .milestones[] | select(.id == $res)
          | ["\($plan) uses the id \($res), which Baton reserves for the session that writes the plan",
             "rename that row in \($plan) to an id of its own and rename its brief with it"] ),
        ( .milestones[] | select(.status != "")
          | ["\($plan) row \(.row) marks \(.id) \"\(.status)\" before anybody has done it, and Baton never dispatches a row that is not blank",
             "leave every Status cell in \($plan) blank and commit it on main"] ),
        ( .milestones[] | . as $m | .depends[] | select(. == $m.id)
          | ["\($plan) has \($m.id) depending on itself, so nothing can ever make it eligible",
             "remove \($m.id) from its own Depends on cell in \($plan)"] ),
        ( .milestones[] | . as $m | .depends[] | select(. as $d | $ids | index($d) == null)
          | ["\($plan) has \($m.id) depending on \(.), which is not a row in the same table",
              "name only ids the milestone table holds in the Depends on cell of \($m.id) in \($plan)"] ),
        ( .gates[] | select(.cleared == "")
          | ["\($plan) opens the gate \"\(.gate)\", and a gate is a hold only a person clears: a generated plan that carries one stops itself on the first night",
             "remove the gate \"\(.gate)\" from the gates table in \($plan), or clear it with the D-number of the entry that cleared it"] ) ]
    | .[] | @tsv')
  planning_defects_from "$pv_lines"

  pv_eligible=$(printf '%s' "$pv_tables" | plan_eligible) || pv_eligible=''
  [ -n "$pv_eligible" ] || planning_defect \
    "nothing in $pv_plan is eligible: every milestone waits on another, so the first tick would dispatch nothing" \
    "leave at least one row in $pv_plan with a Depends on cell of – and no gate holding it"

  # `CLAUDE.md` names the plan file, which is what REQ-CONTRACT-02 asks of a project Baton drives:
  # the document a person opens has to say where the plan is, or the next person to read the
  # repository learns it from Baton's registration instead of from the project.
  pv_claude=$(git -C "$pv_c" show main:CLAUDE.md 2>/dev/null) || pv_claude=''
  printf '%s\n' "$pv_claude" | grep -Fq "$pv_plan" || planning_defect \
    "CLAUDE.md on main does not name $pv_plan as this project's plan file, so the document a person opens does not say where the plan is" \
    "name $pv_plan in CLAUDE.md as the plan file, with the close-out a session follows, and commit it on main"

  # Each milestone: the dispatch preconditions Baton already reports for a plan it did not author,
  # and the four questions only a generated brief is asked.
  pv_ids=$(printf '%s' "$pv_tables" | jq -r '.milestones[] | .id')
  for pv_id in $pv_ids; do
    pv_succ=$(printf '%s' "$pv_tables" | jq -r --arg m "$pv_id" \
      '[ .milestones[] | select(.depends | index($m) != null) | .id ] | join(" ")')
    if ! pv_pre=$(dispatch_preconditions "$pv_key" "$pv_id"); then
      planning_defect "the dispatch preconditions for $pv_id could not be read: $pv_pre" \
        "look at $PLANNING_BRIEFS/$pv_id.md and $BATON_HOME/projects/$pv_key yourself"
    elif ! printf '%s' "$pv_pre" | jq -e '(.failures | type) == "array"' > /dev/null 2>&1; then
      planning_defect "the dispatch preconditions for $pv_id returned no readable result" \
        "look at $PLANNING_BRIEFS/$pv_id.md yourself"
    else
      pv_fn=$(printf '%s' "$pv_pre" | jq -r '.failures | length'); pv_fi=0
      while [ "$pv_fi" -lt "$pv_fn" ]; do
        pv_one=$(printf '%s' "$pv_pre" | jq -c --argjson n "$pv_fi" '.failures[$n]'); pv_fi=$((pv_fi + 1))
        planning_defect "$(printf '%s' "$pv_one" | jq -r .detail)" \
          "$(printf '%s' "$pv_one" | jq -r '.repair // ""')"
      done
    fi
    planning_defects_from "$(planning_brief_defects "$pv_c" "$pv_id" "$pv_succ")"
  done

  jq -nc --arg p "$pv_plan" --arg f "$pv_fmt" --argjson t "$pv_tables" --argjson d "$pv_defects" \
    '{plan: $p, plan_format: $f, tables: $t, defects: $d}'
}

# planning_prompt <project key> <checkout> <registration json> <defects json> <attempt>: the whole
# text the planning session receives.
#
# It is Baton's own text and not a brief, because the project has no briefs yet — that is what the
# session is for. It is composed here rather than in `lib/templates.sh` so that the rules it states
# and the checks `planning_validate` makes sit in one file: a rule stated in the prompt that nothing
# measures is a rule that quietly stops being true, and a check with no rule in the prompt is a
# session refused for something nobody told it.
#
# The slot paragraph is at column 0, once, as part 2 of any kickoff prompt is, so `slot_line`
# replaces it at dispatch with what else is really in flight. Every other mention of that sentence
# in this text is indented, because `slot_line` anchors its match at the start of a line and would
# otherwise replace the instruction instead of the slot.
planning_prompt() {
  ppt_key=$1; ppt_c=$2; ppt_doc=$3; ppt_defects=$4; ppt_attempt=$5
  ppt_check=$(printf '%s' "$ppt_doc" | jq -r '.check.command // ""')
  [ -n "$ppt_check" ] || ppt_check='(none detected; say so rather than inventing one)'

  printf 'You are writing the milestone plan for %s, the Git repository at %s, and you are implementing none of it.\n\n' \
    "$ppt_key" "$ppt_c"
  printf 'WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.\n\n'

  /bin/cat <<'PLANNING_WHO'
WHO IS ASKING. Baton is a relay on one Mac: every sixty seconds it reads a project's plan file, its
own dispatch log and a mailbox, and starts one Claude Code session per milestone with the kickoff
prompt that milestone's brief carries. It embeds no model call and makes no judgement of its own.
This project is registered with Baton and has no plan Baton can read, so nothing of it can be
dispatched until you write one. Everything you write here is read by sessions that have no memory
of you and no memory of each other.

PLANNING_WHO

  printf 'THE CONFIRMED INTENT, which is the authority and is not yours to revise.\n'
  printf '%s' "$ppt_doc" | jq -r '
    "  Goal:      \(.goal // "")",
    "  Done:      \(.done // "")",
    "  Must hold: \((.constraints // []) | if length == 0 then "nothing recorded" else join("; ") end)",
    "  Not this:  \((.non_goals // []) | if length == 0 then "nothing recorded" else join("; ") end)"'
  /bin/cat <<'PLANNING_INTENT'
The repository's owner confirmed those four lines. Plan the work that gets the repository from where
it is now to Done, inside Must hold, and with none of Not this. Do not ask for them again, do not
widen them, and do not add a milestone whose purpose is to have somebody approve the plan: the goal
was already confirmed, and re-approving its consequences is the review that gets rubber-stamped.

PLANNING_INTENT

  if [ "$(printf '%s' "$ppt_defects" | jq 'length')" -gt 0 ]; then
    printf 'WHAT IS WRONG WITH THE PLAN THAT IS ALREADY THERE. This is attempt %s. A previous session wrote a\nplan and Baton refused it. Repair exactly these, keep everything that is already right, and do not\nstart a second graph.\n' \
      "$ppt_attempt"
    printf '%s' "$ppt_defects" | jq -r --argjson n "$PLANNING_DEFECTS_SHOWN" --argjson c "$PLANNING_DEFECT_CHARS" '
      def cut($k): tostring | if (length <= $k) then . else .[0:$k] + "…" end;
      (.[0:$n] | .[] | "  * \(.what | cut($c))\(if (.repair // "") == "" then "" else "\n    Repair: " + (.repair | cut($c)) end)"),
      (if length > $n then "  * … and \(length - $n) more, of the same kinds." else empty end)'
    printf '\n'
  fi

  /bin/cat <<'PLANNING_STARTUP'
STARTUP ORDER.
1. Read README, CLAUDE.md and AGENTS.md where they exist, then the source tree, the tests and
   whatever build or test command the repository ships. Establish what is already built before you
   plan anything: a milestone that re-does finished work is the expensive kind of wrong, and you
   cannot ask anybody which parts are done.
2. Read the recent history and the working tree — git log --oneline -30 and git status — so the plan
   starts from the repository as it is rather than as a document describes it.
3. If the plan document named below already exists on this branch, it is a previous attempt at this
   same work. Repair it in place — against the defects above where this prompt carries any — and
   keep every milestone and brief that is already right. Do not start a second graph and do not
   renumber what is there.

PLANNING_STARTUP

  printf 'WHAT YOU WRITE, in %s, on this branch.\n' "$ppt_c"
  printf '1. %s — the plan document, holding the milestone table and the gates table below.\n' "$PLANNING_PLAN"
  printf '2. %s/<ID>.md — one brief per milestone, in MILESTONE FORMAT below. The path is fixed:\n' "$PLANNING_BRIEFS"
  printf '   Baton constructs %s/<ID>.md whatever any pointer says, so a brief anywhere else is a\n   brief Baton will not read.\n' "$PLANNING_BRIEFS"
  printf '3. CLAUDE.md — it must name %s as this project'"'"'s plan file. If it does not, add a short\n   section that does and that tells a session to follow its brief'"'"'s close-out; leave the rest of\n   the file alone.\n' "$PLANNING_PLAN"
  printf 'Write nothing under %s except the one handover artifact named in CLOSE-OUT, and change no\nsource file and no test: this session plans, and other sessions build.\n\n' "$BATON_HOME"
  /bin/cat <<'PLANNING_TABLE'
WHAT THE PLAN MUST SATISFY. Baton measures every one of these and refuses the plan whole when one
fails, so they are requirements and not advice.

The milestone table, in the plan document:

    | ID | Title | Depends on | Model | Effort | Remote | Status |
    |---|---|---|---|---|---|---|
    | M01 | Read the configuration file | – | opus | high | | |
    | M02 | Validate it against the schema | M01 | opus | medium | | |

  * The header must carry both an ID cell and a Depends on cell. That pair is how Baton finds this
    table among the document's others, and a table without Depends on is not a table at all to it.
  * ID is M, then digits, then optionally a hyphen and one run of lowercase letters and digits:
    M01, M02, M07-b. M00-plan is reserved for this session and must not appear as a row.
  * Depends on holds ids and ranges only — M05, M06 or M01-M13 — or an en dash for none. Every id
    named must be a row in this same table. Prose is not a token and fails the read.
PLANNING_TABLE

  # The aliases this home actually maps, rather than a list written here: a person who renames one
  # would otherwise get a plan refused for a model the prompt told the session to use, which is the
  # rule-stated-but-not-measured drift this file exists to avoid. A full `claude-…` id is the other
  # thing `parse_model` takes, so the sentence names both.
  printf '  * Model is one of the aliases this Baton knows — %s — or a full model id beginning\n    claude-. Effort is blank or one of low, medium, high, xhigh, max. Remote is blank or yes.\n' \
    "$(jq -r '(.models // {}) | keys_unsorted | join(", ")' "$BATON_HOME/config.json" 2>/dev/null \
       || printf 'the keys of .models in %s/config.json' "$BATON_HOME")"

  /bin/cat <<'PLANNING_TABLE2'
  * Status is blank on every row. Nothing is done yet, and a row that is not blank is a row Baton
    will never dispatch.
  * Columns beyond those six are ignored by Baton and are for people to read; a Title is worth having.
  * At least one row must have no dependency, or the first tick has nothing it can start.

The gates table, after it:

    | Gate | Holds | Cleared |
    |---|---|---|

  * The header must carry both a Gate cell and a Holds cell. The table may have no rows, and
    normally should: a gate is a hold only a person clears, so a plan that invents one stops itself
    on the first night. Write one only if the work genuinely waits on an act outside the repository,
    and then it must already be cleared, or Baton refuses the plan.

Each milestone:
  * is one fresh session of work — roughly two to seven hours — with an objective a session can
    finish and acceptance a session can check for itself;
  * depends only on the milestones that really must precede it. Every edge you add that is not a
    real dependency is a night spent one session at a time that could have been spent two or three
    at a time.
  * names in its section 5, between backticks, at least one repository path its work will change.
    That section is how Baton proves the milestone was done: it checks that the branch changed at
    least one path inside it, so a section 5 that names its paths in prose rather than between
    backticks declares a narrower scope than it means and an honest completion is refused.

MILESTONE FORMAT. Every brief carries exactly these headings, in this order: eleven numbered H2
sections, then three unnumbered ones.

    # M<nn> — <title>

    ## 1. Identity
    - **ID:** M<nn>. **Objective:** <what this milestone is for, bounded>.
    - **User-visible result:** <what is observably true afterwards>.
    - **Size:** <Small|Medium|Large, about <n> hours>; <effort> effort.

    ## 2. Dependencies and entry conditions
    <the predecessor milestones, and the state that must hold before this one starts>

    ## 3. Required reading
    <the exact files and sections a fresh session reads first, by path>

    ## 4. Requirements, scope, non-goals
    - **Scope:** <the work this milestone contains>.
    - **Non-goals:** <the work it does not, and which milestone owns it>.

    ## 5. Expected files (proposed)
    <every path the work will add or change, each between backticks>

    ## 6. Interfaces
    - **Introduces:** <the functions, commands or shapes it adds>.
    - **Consumes:** <what it builds on>.

    ## 7. Implementation checklist (ordered)
    1. <the first concrete act>
    <the last item is verification, review and close-out>

    ## 8. Fixtures, verification, acceptance
    - **Verification:** <the checks to run, by command>.
    - **Acceptance:** <the conditions that must hold, each observable>.

    ## 9. Definition of done and evidence
    <what the completing session records, and where>

    ## 10. Risks and decisions this milestone settles
    - **<the risk or open question>.** <its evidence and who owns it>

    ## 11. Handoff and next milestone
    <every milestone whose Depends on names this one, by id, or "none">

    ## Recovery procedure
    <what a fresh session inspects to find out how far the work got, and the rule that it resumes
    the first unfinished item rather than starting over; no completion claim without section 8>

    ## Completion evidence

    ## Copy-ready session prompt

    ```
    <the seven parts below>
    ```

The Completion evidence section is left empty. The session that does the milestone appends to it,
and the recovery clause reads it: a brief that arrives with anything under that heading tells the
first session to resume work nobody did.

PLANNING_TABLE2

  printf 'The Copy-ready session prompt section holds exactly one fenced code block, and that block is the\nwhole prompt Baton hands the session. Seven parts, in this order:\n'
  /bin/cat <<'PLANNING_SEVEN'
  1. Identity and scope: the milestone, the absolute path of the repository, one line saying what
     the project is, and the Size.
  2. Exactly this paragraph, alone on its own line, with nothing before or after it on that line:
       WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.
     Baton replaces that paragraph whole at dispatch with what is really in flight. A prompt
     without it is refused before anything is created.
  3. STARTUP ORDER: what to read, in what order, what to inspect before writing, and the recovery
     clause — if the brief's Completion evidence is not empty, follow the Recovery procedure and
     resume only the unfinished part.
  4. WHAT TO SETTLE RATHER THAN INHERIT: the open questions this milestone owns, each carrying the
     evidence a fresh session needs to settle it — a path, a measurement, an identifier. Carry the
     evidence and not the topic: "X is wrong because Y matches on the name" lets the next session
     decide, while "look into X" makes it rediscover.
  5. CONSTRAINTS: the language, the packages, the standing check, what not to touch, and how to
     stage and commit.
  6. VERIFICATION: a pointer to the brief's section 8, and the rule that every check is reported as
     passed, failed or unrun with its output, and an unrun check is never reported as passed.
  7. CLOSE-OUT, numbered, ending with the handover artifact written and printed.

Every document a prompt names by a docs/… path must exist on main when you are finished: Baton looks
each one up before it dispatches and refuses a prompt naming one that is not there. A prompt you
write is run by a session that remembers nothing of you — no "as discussed", no "the file we
changed", no "continue the previous plan". Absolute paths and real identifiers only, second person,
imperative, and every instruction that is not self-evident carrying its reason, because a rule whose
reason travels with it survives a session that would otherwise talk itself out of it.

PLANNING_SEVEN

  printf 'THE CLOSE-OUT EACH GENERATED PROMPT MUST CARRY, as its part 7, because this is what keeps the\nchain running after you. Write it into every brief, with the milestone'"'"'s own id in it:\n'
  printf '  1. the milestone'"'"'s own checks, then its review and its fixes;\n'
  printf '  2. completion evidence appended under ## Completion evidence in its own brief; commit on the\n     branch, staging paths by name and never with git add -A;\n'
  printf '  3. merge the branch into main in %s, keeping the branch and its commits — Baton verifies\n     that the branch tip is an ancestor of the commit the artifact names, and a squash merge leaves\n     a tip that is not. If the merge fails, write a stopped artifact with reason merge-failed and go\n     no further;\n' "$ppt_c"
  printf '  4. run the standing check — %s — on main; fix main if it fails, or write a stopped artifact\n     with reason main-broken;\n' "$ppt_check"
  printf '  5. on main, write done in that milestone'"'"'s Status cell in %s and commit;\n' "$PLANNING_PLAN"
  printf '  6. write %s/inbox/<ID>-$CLAUDE_CODE_SESSION_ID.json, as a .tmp first and then renamed,\n     holding:\n' "$BATON_HOME"
  printf '       {"baton": 1, "project": "%s", "milestone": "<ID>",\n' "$ppt_c"
  /bin/cat <<'PLANNING_ARTIFACT'
        "session": "<the value of CLAUDE_CODE_SESSION_ID>", "outcome": "complete",
        "merged_as": "<the merge commit on main>", "written_at": "<now, ISO 8601>",
        "eligible": [ {"milestone": "<OTHER ID>",
                       "brief": {"path": "docs/milestones/<OTHER ID>.md",
                                 "heading": "Copy-ready session prompt"},
                       "disposition": "run"} ]}
     where <ID> is the milestone just finished and each <OTHER ID> is a *different* milestone: one
     entry per milestone the plan then makes eligible, never the finished one itself. Disposition
     run when every dependency of that milestone reads done, wait with wait_for naming the ones
     that do not, and held with held_by naming the gate when an uncleared gate holds it. The
     artifact must never carry baseline, changed_paths or check_result: those three are Baton's
     own, and an artifact carrying one is rejected.
  7. print that file verbatim, last, in a fenced block whose info-string is baton.
Section 11 of each brief names that milestone's direct successors — every milestone whose Depends on
names it. Baton dispatches only what a handover lists, so a close-out that omits a successor stops
the chain there, and section 11 is where the session writing that close-out reads it.

CONSTRAINTS FOR THIS SESSION.
  * You write the plan document, the briefs and at most one section of CLAUDE.md. You implement no
    milestone, you write no source file and you change no test.
  * The intent record above is settled and there is nobody at the terminal. Do not ask a question:
    it would end this session with the plan unwritten. Where the repository leaves something
    genuinely undecided, decide it, write down what you decided and why in the brief that owns it,
    and carry on.
  * Stay inside the confirmed constraints and non-goals when you choose what the milestones are.
  * Between eight and twenty milestones is the usual shape of a plan this size. Fewer means
    milestones too big for one session; more means a graph nobody can hold.

PLANNING_ARTIFACT

  printf 'VERIFICATION, before you close out. Check each of these yourself and report it as passed, failed\nor unrun with its output; an unrun check is never reported as passed.\n'
  printf '  * Every id in every Depends on cell is a row in the milestone table, and every Status cell is\n    blank.\n'
  printf '  * %s/<ID>.md exists for every id, with the eleven numbered sections, the three unnumbered\n    headings, an empty Completion evidence section, and one complete fenced block under\n    ## Copy-ready session prompt whose part 2 is the slot paragraph verbatim.\n' "$PLANNING_BRIEFS"
  printf '  * Every docs/… path any of those prompts names exists in the repository.\n'
  printf '  * Section 5 of every brief names at least one repository path between backticks.\n'
  printf '  * The standing check — %s — passes on main after the merge.\n\n' "$ppt_check"

  printf 'CLOSE-OUT, in this order.\n'
  printf '1. Commit the plan document, the briefs and any CLAUDE.md change on this branch, staging your\n   paths by name. Never git add -A.\n'
  printf '2. Merge this branch into main in %s. Keep the branch and its commits: do not squash and do\n   not delete the branch, because Baton verifies that the branch tip is an ancestor of the commit\n   you name below. If the merge fails, write a stopped artifact with reason merge-failed and go no\n   further.\n' "$ppt_c"
  printf '3. Run the standing check — %s — on main. If it fails, fix main; if that cannot be done,\n   write a stopped artifact with reason main-broken.\n' "$ppt_check"
  printf '4. Write %s/inbox/%s-$CLAUDE_CODE_SESSION_ID.json, as a .tmp first and then renamed, holding:\n' "$BATON_HOME" "$PLANNING_ID"
  printf '     {"baton": 1, "project": "%s", "milestone": "%s",\n' "$ppt_c" "$PLANNING_ID"
  /bin/cat <<'PLANNING_CLOSE'
      "session": "<the value of CLAUDE_CODE_SESSION_ID>", "outcome": "complete",
      "merged_as": "<the merge commit on main>", "written_at": "<now, ISO 8601>",
      "eligible": []}
   The eligible array is empty on purpose: Baton derives the first runnable milestones from the plan
   you have just written, so a list here would be a second answer to a question the plan already
   answers, and the two could disagree. If you could not write the plan, write outcome stopped
   instead, with a reason from unfinished, blocked (with blocked_by) or other, and a detail saying
   what stopped you.
5. Print that file verbatim, last, in a fenced block whose info-string is baton. If anything lands
   after it, deal with that and print it again.
PLANNING_CLOSE
}

# planning_preconditions <project key>: what the planning lane needs before anything is created, in
# `dispatch_preconditions`' own `{failures: [{check, stage, path, detail, repair}]}` shape so that
# `dispatch_one` reads one result whichever lane it is dispatching.
#
# It is the same pass, with the checks that are not this lane's dropped. A shorter list written here
# would be two implementations of two rules — "the checkout has a `main`" and "the rail carries its
# deny classes" — and two implementations of one rule is this codebase's named way of ending up with
# a plan the reporter calls ready and the dispatch refuses. So the one pass runs and its result is
# filtered: what the planning lane keeps is `checkout` and `permissions`, and what it drops is
# everything about a brief and the worktree that would hold it, because the prompt is Baton's own
# text and there is no brief to find, no fenced block to read and no `docs/…` reference to look up.
#
# The filter names the checks it keeps rather than the ones it drops: a check added to
# `dispatch_preconditions` later is one this lane has not been told about, and passing it through
# unexamined would refuse a planning dispatch for a reason nobody decided applies to it.
planning_preconditions() {
  ppc_key=$1
  ppc_all=$(dispatch_preconditions "$ppc_key" "$PLANNING_ID") || { echo "$ppc_all"; return 1; }
  printf '%s' "$ppc_all" | jq -ce '
    .failures |= map(select(.check == "checkout" or .check == "permissions"))
    | .references_inspected = true'
}

# planning_record <project key> <outcome> <attempt> <fields json>: one `plan_generation` event.
# Guarded like every other `log_event` call whose caller has already done its work: a line the log
# refused must not abort a pass that has, say, already written the registration.
planning_record() {
  log_event plan_generation "$1" "$PLANNING_ID" "" "" \
    "$(jq -nc --arg o "$2" --argjson a "$3" --argjson f "$4" '{outcome: $o, attempts: $a} + $f')" \
    || render_failure err "baton: $1 the plan_generation event could not be written"
}

# planning_recorded_since <project key> <outcome>: whether a `plan_generation` event with that
# outcome is already on record since the planning lane's newest dispatch.
#
# A refusal and an exhaustion are both **states** and not acts: they hold until an attempt or a
# person changes them, so a tick that recorded one every time it saw one would write a line every
# sixty seconds through every derivation that reads the log whole, and the second run of a scenario
# would change the state, which INV-05 forbids. The newest dispatch re-arms the key, exactly as it
# re-arms `plan_override_spent`: a fresh attempt is a fresh decision, so its refusal is heard about
# once of its own.
planning_recorded_since() {
  prs_log=$(log_json) || return 1
  printf '%s' "$prs_log" | jq -e --arg p "$1" --arg m "$PLANNING_ID" --arg o "$2" '
    [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch") ] | last | .i // -1) as $reset
    | any($ev[]; .kind == "plan_generation" and .outcome == $o and .i > $reset)' > /dev/null
}

# planning_adopt <project key>: the plan the generator wrote, read, measured and — when it holds —
# adopted. Prints `{adopted, lines}`: whether the project now has a plan, and the lines a person
# reads about it. The lines are returned rather than printed for `render_lines`' stated reason — a
# helper that printed as it went would be writing into the result its caller captures — and here
# that is not a matter of taste: this function's result *is* captured.
#
# Adoption is `onboard_commit` with the seed, which is M11's own write in M11's own order: the rail,
# the registration, then the event. It is called directly rather than through `verb_onboard`, which
# would ask the toolchain again, print a report meant for a person at a terminal and `exit` on
# several paths — and an `exit` inside the tick ends the tick rather than the pass. Eligibility is
# still computed exactly once, by `onboard_start`, which `onboard_commit` calls; nothing here
# computes it a second way.
#
# A refusal writes the defects into `plan_owed` rather than anywhere new, because that is the record
# the next attempt's prompt is composed from and the field M11 already put there for this purpose.
# The partial work stays on the branch and in the repository: the next attempt repairs it.
#
# **This function is the adopted-plan boundary, and M15-c's scope guard goes at the line marked
# below.** It is the one place a plan becomes the project's plan, it is reached once per adoption,
# and it already holds both halves of what that guard is defined to receive: the confirmed intent
# record — `goal`, `done`, `constraints` and `non_goals`, read from the registration a few lines
# down as `pa_intent` — and the work being judged, which is the parsed plan in `pa_res.tables` and
# the documents at `pa_plan` and `$PLANNING_BRIEFS` on `main`. What it does not hold, and must not
# be given, is the plan author's rationale: the generating session's prompt and transcript are not
# read here and nothing passes them on, which is the independence the guard exists for (SCOPE §6
# M15-c, §8 item 6). A refusal from that guard is a refusal to adopt, so it belongs beside the
# defect branch and not after the write. M12 does not implement it.
planning_adopt() {
  pa_key=$1
  pa_lines=''
  pa_f=$BATON_HOME/projects/$pa_key/project.json
  pa_c=$(jq -r '.path // ""' "$pa_f" 2>/dev/null) || pa_c=''
  [ -n "$pa_c" ] || { planning_verdict false; return 0; }
  pa_attempt=$(planning_attempts "$pa_key") || pa_attempt=0

  pa_res=$(planning_validate "$pa_key" "$pa_c") || {
    render_failure err "baton: $pa_key the generated plan could not be measured: $pa_res"
    planning_verdict false
    return 0
  }
  pa_plan=$(printf '%s' "$pa_res" | jq -r .plan)
  pa_defects=$(printf '%s' "$pa_res" | jq -c .defects)
  pa_n=$(printf '%s' "$pa_defects" | jq length)

  if [ "$pa_n" -gt 0 ]; then
    # Nothing to say while no attempt has run: the defects are then only "there is no plan yet",
    # which is what `plan_owed` already says and what the project is parked for.
    [ "$pa_attempt" -gt 0 ] || { planning_verdict false; return 0; }
    pa_plural=s; [ "$pa_n" -ne 1 ] || pa_plural=''
    pa_reason="attempt $pa_attempt wrote a plan Baton will not adopt: $pa_n thing$pa_plural to repair, the first being $(printf '%s' "$pa_defects" | jq -r '.[0].what')"
    pa_doc=$(jq -c --arg r "$pa_reason" --argjson d "$pa_defects" \
      '.plan_owed = ((.plan_owed // {}) + {reason: $r, owner: "M12", defects: $d})' "$pa_f") \
      || { render_failure err "baton: $pa_f does not parse"; planning_verdict false; return 0; }
    onboard_registration_write "$pa_key" "$pa_doc"
    # The registration write above is a compare-then-rename and so is free to repeat; the event and
    # the line are not, and a refusal stands until the next attempt changes it.
    if ! planning_recorded_since "$pa_key" refused; then
      planning_record "$pa_key" refused "$pa_attempt" \
        "$(printf '%s' "$pa_defects" | jq -c --arg p "$pa_plan" --argjson c "$PLANNING_DEFECT_CHARS" '
           def cut($k): tostring | if (length <= $k) then . else .[0:$k] + "…" end;
           {defects: length, first: (.[0].what | cut($c))} | if $p == "" then . else . + {plan: $p} end')"
      pa_lines="$pa_lines$(render_plain 'generate  %s · attempt %s left a plan with %s thing%s to repair · the next attempt carries them' \
        "$pa_key" "$pa_attempt" "$pa_n" "$pa_plural")
"
    fi
    planning_verdict false
    return 0
  fi

  # ---- the adopted-plan boundary: M15-c's scope guard goes here, before anything is written ----
  pa_seed=yes
  ! jq -e '(.start.eligible | type) == "array"' "$pa_f" > /dev/null 2>&1 || pa_seed=no
  pa_tool=$(onboard_toolchain "$pa_c")
  pa_intent=$(jq -c '{goal: (.goal // ""), done: (.done // ""),
                      constraints: (.constraints // []), non_goals: (.non_goals // [])}' "$pa_f") \
    || { render_failure err "baton: $pa_f does not parse"; planning_verdict false; return 0; }
  # The classification `planning_validate` already made, carried through rather than made again: it
  # is a read of the same file at the same moment, and asking twice is one more chance for the two
  # answers to differ. `{}` for the CLI, because nothing here asked the binary anything —
  # `onboard_commit` writes `cli` only when a version is passed, so the registration keeps the
  # `checked_at` of the run that really checked (REQ-ONBOARD-10).
  pa_class=$(printf '%s' "$pa_res" | jq -c '{plan_format, adaptation: {}, tables}')
  onboard_commit "$pa_key" "$pa_c" "$pa_plan" "$pa_tool" "$pa_intent" "$pa_class" '{}' "$pa_seed" \
    || { render_failure err "baton: $pa_key the generated plan could not be adopted"; planning_verdict false; return 0; }
  pa_count=$(printf '%s' "$pa_res" | jq -r '.tables.milestones | length')
  pa_plural=s; [ "$pa_count" -ne 1 ] || pa_plural=''
  pa_start=$(jq -r '[(.start.eligible // [])[] | .milestone] | join(", ")' "$pa_f" 2>/dev/null || true)
  planning_record "$pa_key" adopted "$pa_attempt" \
    "$(jq -nc --arg p "$pa_plan" --argjson n "$pa_count" '{plan: $p, milestones: $n}')"
  pa_lines="$pa_lines$(render_plain 'generated %s · %s · %s milestone%s · the plan owed since onboarding is settled' \
    "$pa_key" "$pa_plan" "$pa_count" "$pa_plural")
"
  [ -z "$pa_start" ] || pa_lines="$pa_lines$(render_plain 'starting  %s · %s' "$pa_key" "$pa_start")
"
  planning_verdict true
}

# planning_verdict <true|false>: `planning_adopt`'s one exit, so that the document it returns and the
# lines it collected leave together however the pass ended. A helper of that function alone, which is
# why it reads its variable.
planning_verdict() {
  jq -nc --argjson a "$1" --arg l "$pa_lines" \
    '{adopted: $a, lines: ($l | split("\n") | map(select(length > 0)))}'
}

# planning_pass <project key> <rows json>: step 1's companion, for a project that owes a plan.
# Prints the dispatch candidates it produces — one, or none — as a JSON array, in the shape
# `dispositions_intersect` produces so that `cap_order`, the holds and the cap read one kind of
# candidate. Status 1 when the pass could not be made, which the tick counts.
#
# It runs beside the self-check and not after it, because a project that owes a plan **fails** the
# self-check and is skipped for the rest of the tick: step 1 reads its registration, finds no plan
# it can parse, parks it `plan-unreadable` and moves on. That park is accurate, and it is exactly
# the condition generation exists to clear, so generation has to run through it rather than behind
# it. Every other project-scope park does hold it: a project whose `main` a person has been asked to
# fix is ground no new session starts on, and that includes this one.
#
# Nothing here waits for the session it asks for. The candidate goes into the same list as every
# other, `dispatch_run` admits it under the same cap, and the answer arrives as a handover the next
# tick reads (D-158).
planning_pass() {
  ppa_key=$1; ppa_rows=$2
  ppa_lines=''
  planning_owed "$ppa_key" > /dev/null 2>&1 || { planning_pass_out '[]'; return 0; }

  # An attempt that is still running is not judged. The session may have merged a first draft of the
  # plan and be repairing it as this tick runs, and measuring that draft would record a refusal
  # against an attempt that has not finished — and then withhold the retry, because a refusal is
  # recorded once per attempt. Liveness is the pid, through the same derivation the cap counts by.
  ppa_flight=$(derive_in_flight "$ppa_key" "$ppa_rows") || { render_failure err "$ppa_flight"; return 1; }
  if printf '%s' "$ppa_flight" | jq -e --arg m "$PLANNING_ID" 'any(.in_flight[]; .milestone == $m)' > /dev/null; then
    planning_pass_out '[]'; return 0
  fi

  # A plan that has arrived and holds is adopted here, in the same tick, so the self-check that
  # follows this call reads it and the park it raised is closed by the ordinary pass that closes it.
  # The order is the whole reason this is a pass of its own and not a branch inside `self_check`.
  ppa_adopt=$(planning_adopt "$ppa_key") || { render_failure err "baton: $ppa_adopt"; return 1; }
  ppa_lines=$(printf '%s' "$ppa_adopt" | jq -r '.lines[]')
  # The collector appends a newline after each line, so the lines carried in from the adoption have
  # to end with one too; without it the next line written would run onto the last one read.
  [ -z "$ppa_lines" ] || ppa_lines="$ppa_lines
"
  if printf '%s' "$ppa_adopt" | jq -e .adopted > /dev/null; then planning_pass_out '[]'; return 0; fi

  # The confirmed goal is the planning input, and there is no second source for it. A registration
  # that owes a plan and carries no goal is one the confirmation never completed or a hand edit
  # emptied, and generating against nothing would produce a plan for a project Baton cannot say the
  # purpose of — which is the one thing the single human touchpoint exists to prevent. Named and not
  # guessed at, with the verb that supplies it.
  if ! jq -e '(.goal // "") != ""' "$BATON_HOME/projects/$ppa_key/project.json" > /dev/null 2>&1; then
    planning_pass_line "$(render_plain 'generate  %s · the registration carries no confirmed goal, so there is nothing to plan against · run baton onboard %s' \
      "$ppa_key" "$(project_path "$ppa_key" 2>/dev/null || printf '<path>')")"
    planning_pass_out '[]'; return 0
  fi

  ppa_parked=$(derive_parked "$ppa_key") || { render_failure err "$ppa_parked"; return 1; }
  ppa_other=$(printf '%s' "$ppa_parked" | jq -r '
    first(.parked[] | select(.scope == "project" and (.class | test("^plan-(unreadable|unparseable)$") | not)) | .class) // empty')
  if [ -n "$ppa_other" ]; then
    planning_pass_line "$(render_plain 'generate  %s · the project is parked (%s), so no planning session starts' \
      "$ppa_key" "$ppa_other")"
    planning_pass_out '[]'; return 0
  fi

  # **A lane park on the planning lane holds it**, exactly as `dispositions_intersect` holds a
  # milestone whose lane is parked (`lib/candidates.sh`). That filter is what makes `dispatch_try`'s
  # own sentence true — "the park is then what stops the retry" — and this lane never reaches it,
  # because a project that owes a plan fails the self-check and is absent from the per-project loop.
  # Without this the candidate is produced over the park every tick: `dispatch_one` fails at the same
  # stage, `dispatch_try` sees two failures or more and escalates *again* — it has no once-key and
  # `escalate` de-duplicates nothing — and a person gets a Mac message a minute about a condition
  # they have already been told about. The attempt bound does not catch it either: a dispatch that
  # produced no session writes `dispatch_failed` and not `dispatch`, so `attempt_of` never moves.
  #
  # **And the `dispatch-failed` park is released here**, which is the other half. A milestone's is
  # released by `edit_reread_check` when a person's edit changes the brief or the plan it hashed;
  # this lane has no brief and its plan is the thing that does not parse, so nothing hashes and
  # nothing would ever release it. What parked it is a condition Baton can read for itself — a
  # checkout with no `main`, or a rail with no deny rules — so the pass that would re-fail on it
  # asks it again instead, and closes the park the way `park_resolve` closes the self-check's own
  # (D-169). Every other class parks a session a person answers, and those keep their own route.
  ppa_lane=$(printf '%s' "$ppa_parked" | jq -r --arg m "$PLANNING_ID" \
    'first(.parked[] | select(.scope == "lane" and .milestone == $m)) as $p
     | if $p == null then "" else "\($p.class) \($p.at)" end')
  if [ -n "$ppa_lane" ]; then
    ppa_class=${ppa_lane%% *}; ppa_at=${ppa_lane#* }
    ppa_cleared=no
    if [ "$ppa_class" = dispatch-failed ] && ppa_pre=$(planning_preconditions "$ppa_key") \
       && printf '%s' "$ppa_pre" | jq -e '(.failures | length) == 0' > /dev/null 2>&1; then
      ppa_cleared=yes
    fi
    if [ "$ppa_cleared" = yes ]; then
      resolve "$ppa_key" "$PLANNING_ID" "" "" "$ppa_at" edit || { render_failure err "baton: $ppa_key the dispatch-failed park on $PLANNING_ID could not be resolved"; return 1; }
      planning_pass_line "$(render_plain 'unparked  %s/%s · the dispatch preconditions hold again · the park raised at %s is closed' \
        "$ppa_key" "$PLANNING_ID" "$ppa_at")"
    else
      planning_pass_line "$(render_plain 'generate  %s/%s · the lane is parked (%s), so no planning session starts' \
        "$ppa_key" "$PLANNING_ID" "$ppa_class")"
      planning_pass_out '[]'; return 0
    fi
  fi

  # A live row under the lane's own name is a session somebody started by hand, and dispatching over
  # one is the mistake with no undo. The same refusal `dispositions_intersect` makes for a milestone.
  if printf '%s' "$ppa_rows" | jq -e --arg n "$(session_name "$ppa_key" "$PLANNING_ID")" \
       'any(.[]; .name == $n and .pid != null)' > /dev/null; then
    planning_pass_out '[]'; return 0
  fi

  ppa_attempts=$(planning_attempts "$ppa_key") || { render_failure err "$ppa_attempts"; return 1; }
  ppa_max=$(planning_attempts_max)
  if [ "$ppa_attempts" -ge "$ppa_max" ]; then
    # The bound, and no new escalation class for it. The project is already parked `plan-unreadable`
    # — raised by the self-check the moment the plan could not be read, notified once, and standing
    # ever since — and that park's own repair is the repair for this: a person writes or fixes the
    # plan and the next tick re-reads it. A second class would need a verb that clears it and would
    # say the same thing twice (D-167). What is recorded here is why Baton stopped spending sessions.
    if ! planning_recorded_since "$ppa_key" exhausted; then
      planning_record "$ppa_key" exhausted "$ppa_attempts" \
        "$(planning_owed "$ppa_key" | jq -c --argjson m "$ppa_max" --argjson c "$PLANNING_DEFECT_CHARS" '
           def cut($k): tostring | if (length <= $k) then . else .[0:$k] + "…" end;
           {max: $m, reason: ((.reason // "") | cut($c))}')"
      planning_pass_line "$(render_plain 'generate  %s · %s generation attempts have not produced a plan Baton will adopt · the project stays parked until the plan is repaired by hand' \
        "$ppa_key" "$ppa_attempts")"
    fi
    planning_pass_out '[]'; return 0
  fi

  planning_pass_out "$(jq -nc --arg p "$ppa_key" --arg m "$PLANNING_ID" --arg model "$(planning_model)" \
    '[{project: $p, milestone: $m, row: 0, model: $model, remote: false, rank: 0, index: 0}]')"
}

# planning_pass_line <text> / planning_pass_out <candidates json>: that function's line collector and
# its one exit, so the candidates and the lines leave together however the pass ended. Helpers of
# `planning_pass` alone, which is why they read its variable.
planning_pass_line() {
  ppa_lines="$ppa_lines$1
"
}
planning_pass_out() {
  jq -nc --argjson c "$1" --arg l "$ppa_lines" \
    '{candidates: $c, lines: ($l | split("\n") | map(select(length > 0)))}'
}
