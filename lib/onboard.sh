#!/bin/sh
# lib/onboard.sh — `baton onboard <path>`: an unfamiliar Git repository becomes a registered target
# project, with its permission rail, its standing check, its plan read as it already stands, and one
# confirmation of what the project is for.
#
# L1 is the limitation this answers: registration presupposed a migrated plan, conforming briefs,
# close-out instructions, a permissions file and a starting artifact, and `install.sh` generated the
# first two of those only for the project it runs in. The recorded symptom is a Reclaim plan whose
# parse failed on a missing `Model` column, and an M08 that asked a *dispatched session* to write
# `projects/<key>/project.json` — a path that session's own deny rules forbid.
#
# Three things follow from that, and they are the shape of this file:
#
#   * **The relay writes Baton's state, never a session.** `onboard` is a verb: it takes the lock,
#     writes the registration itself and records one `onboarded` event. Nothing is widened and no
#     session is asked to write a path it is denied. The tick then picks the project up on its next
#     run, because step 1 iterates `projects/*/project.json` and needs no telling.
#
#   * **The target repository is not written.** Adaptation is recorded in the registration and
#     applied by the reader, so the plan parses as it already stands. A `Model` column Baton chose
#     would be Baton's state inside someone else's document (REQ-CONTRACT-02), and an adaptation
#     that exists only as a registration is undone by deleting it. SCOPE §6 M11's acceptance is
#     that the plan parses "without a human editing anything in that repository first"; nothing
#     else edits it either.
#
#   * **Tolerance is registered, not global.** A project registered `native` is parsed exactly as
#     strictly as before, so a misspelt `Model` cell in Baton's own plan still parks rather than
#     defaulting. A project registered `adapted` is parsed with the defaults and the status map the
#     confirmation accepted. That is the line between "unusable plan input" and "a usable plan
#     needing adaptation", and it is drawn once, by a person's yes.
#
# The one judgement this verb needs — what the project is for — is a **judgment request**: a
# foreground `claude -p` under the verb's own lock, bounded by a deadline, spending no admission
# slot and opening no lane. §4.5 of `docs/ARCHITECTURE.md` writes the role down beside the judgment
# *session* M12 will need, because a role whose result is awaited while it holds a slot is a lane
# nothing closes (D-130's `do_unresolved` counts exactly that).
set -eu

ONBOARD_JUDGE_DEADLINE=${ONBOARD_JUDGE_DEADLINE:-120}

# A table row with an `ID` header cell anywhere in it, which is how the reader locates the milestone
# table (REQ-PLAN-01, and `plan_extract`'s `has_cell`). The cell need not be first: a project whose
# own table opens with `Owner` or `Title` still has an `ID` column, and a search that demanded the
# first cell would say a perfectly readable plan was not one.
ONBOARD_ID_HEADER='^[[:space:]]*\|([^|]*\|)*[[:space:]]*ID[[:space:]]*\|'

# onboard_deny_rules: the two deny classes of REQ-PERM-04 for a project of this home, as a JSON
# array on stdout. Privilege escalation, and Baton's own state by named path — everything under
# `$BATON_HOME` except `inbox/`.
#
# It is here rather than inline in `install.sh` because the rail is the same rail for every target:
# a Reclaim session must no more edit `com.baton.tick.plist` or `log.jsonl` than a Baton session
# may. `install.sh` sources this file for the one function, so there is one recipe with two callers
# rather than two recipes a test compares.
#
# It takes no arguments and reads `$BATON_HOME`, because the rules name Baton's home and not the
# project: the project's own paths are never denied — a session's working directory is its own
# repository, and `worktrees/` is deliberately unnamed for that reason (D-153).
onboard_deny_rules() {
  jq -nc --arg h "/$BATON_HOME" '
    ["Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)", "Bash(osascript * administrator privileges*)"]
    + ["Read(\($h)/log.jsonl)", "Edit(\($h)/log.jsonl)", "Write(\($h)/log.jsonl)"]
    + ([ "archive", "rejected", "prompts", "settings", "projects", "bin", "status", "lock", "notify", "checks" ]
       | map("Edit(\($h)/\(.)/**)", "Write(\($h)/\(.)/**)"))
    + ["Edit(\($h)/config.json)", "Write(\($h)/config.json)", "Edit(\($h)/last-tick)", "Write(\($h)/last-tick)"]
    + ([ "log.jsonl", "archive", "rejected", "prompts", "settings", "projects", "status", "lock", "config.json", "last-tick", "notify", "checks" ]
       | map("Bash(*.baton/\(.)*)"))
    + ["Bash(*.baton/bin/lib*)"]
    + ["Edit(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
       "Write(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
       "Bash(*com.baton.tick*)"]'
}

# onboard_repo <path>: the canonical checkout and the project key, as `{checkout, key}`; the detail
# and status 1 for anything that is not an owned Git repository.
#
# The canonical checkout is git's own first worktree, as `install.sh` reads it, so onboarding a
# linked worktree registers the checkout it belongs to rather than a second project under a second
# key. The key is that checkout's basename and never a `cwd` (CONTEXT.md, "project key").
onboard_repo() {
  or_in=$1
  [ -n "$or_in" ] || { echo "onboard takes the path of a Git repository"; return 1; }
  [ -d "$or_in" ] || { echo "$or_in is not a directory"; return 1; }
  or_abs=$(cd "$or_in" 2>/dev/null && pwd -P) || { echo "$or_in cannot be entered"; return 1; }
  git -C "$or_abs" rev-parse --git-dir > /dev/null 2>&1 \
    || { echo "$or_abs is not a Git repository, and Baton drives Git repositories (SCOPE §3)"; return 1; }
  or_top=$(git -C "$or_abs" worktree list --porcelain 2>/dev/null \
           | awk '/^worktree / { print substr($0, 10); exit }')
  [ -n "$or_top" ] || { echo "git could not name the canonical checkout of $or_abs"; return 1; }
  or_top=$(cd "$or_top" 2>/dev/null && pwd -P) || { echo "the canonical checkout of $or_abs cannot be entered"; return 1; }
  or_key=$(basename "$or_top")
  case "$or_key" in
    ''|.|..|*/*) echo "\"$or_key\" cannot be a project key" ; return 1 ;;
  esac
  jq -nc --arg c "$or_top" --arg k "$or_key" '{checkout: $c, key: $k}'
}

# onboard_toolchain <checkout>: what the repository is built and tested with, as
# `{toolchain: [...], check: {command, deadline_seconds}, allow: [...]}`.
#
# The check command is the field a completion cannot be proved without (D-147), so it is derived
# here — beside the permission list, from the same evidence — rather than left for a later
# milestone. A project-specific runner wins over a language's canonical command, because a
# repository that ships its own script has already said which one is the standing check.
#
# The allow list is the detected drivers plus `jq`, which is what `install.sh` writes for Baton.
# Under `bypassPermissions` allow rules allow nothing and cost nothing; they are what makes a
# hand-started session passing the same settings file behave as a dispatched one (ARCHITECTURE §3).
# Nothing is derived that needs an access grant: a credential or a private registry is a human fact
# and stays one.
onboard_toolchain() {
  ot_c=$1
  ot_kinds=''
  ot_allow='["Bash(jq:*)"]'
  ot_cmd=''

  # Ordered by how specific the evidence is, and the first match names the check.
  if [ -f "$ot_c/tests/run.sh" ]; then
    ot_kinds="$ot_kinds shell"; ot_cmd='sh tests/run.sh'
  fi
  if [ -f "$ot_c/package.json" ]; then
    ot_kinds="$ot_kinds node"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(npm:*)", "Bash(node:*)"]')
    if [ -z "$ot_cmd" ] && jq -e '.scripts.test // empty' "$ot_c/package.json" > /dev/null 2>&1; then
      ot_cmd='npm test'
    fi
  fi
  if [ -f "$ot_c/Cargo.toml" ]; then
    ot_kinds="$ot_kinds rust"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(cargo:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='cargo test'
  fi
  if [ -f "$ot_c/go.mod" ]; then
    ot_kinds="$ot_kinds go"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(go:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='go test ./...'
  fi
  if [ -f "$ot_c/Package.swift" ]; then
    ot_kinds="$ot_kinds swift"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(swift:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='swift test'
  fi
  if [ -f "$ot_c/pyproject.toml" ] || [ -f "$ot_c/setup.py" ] || [ -f "$ot_c/pytest.ini" ]; then
    ot_kinds="$ot_kinds python"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(python3:*)", "Bash(pytest:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='pytest'
  fi
  # A Makefile is evidence of a driver whichever language sits under it, and it supplies the check
  # only when it really has a `test` target — a grep for the target and not for the word.
  if [ -f "$ot_c/Makefile" ]; then
    ot_kinds="$ot_kinds make"
    ot_allow=$(printf '%s' "$ot_allow" | jq -c '. + ["Bash(make:*)"]')
    if [ -z "$ot_cmd" ] && grep -Eq '^test[[:space:]]*:' "$ot_c/Makefile"; then ot_cmd='make test'; fi
  fi

  # The command's own rule, in the whole-invocation form `install.sh` already writes for Baton
  # (`Bash(sh tests/run.sh:*)`), and only where the driver it starts with is not allowed already:
  # `Bash(cargo test:*)` beside `Bash(cargo:*)` allows nothing the broader rule did not, and a rule
  # that adds nothing is a rule a reader has to work out the purpose of.
  if [ -n "$ot_cmd" ]; then
    ot_first=${ot_cmd%% *}
    printf '%s' "$ot_allow" | jq -e --arg d "Bash($ot_first:*)" 'index($d) != null' > /dev/null \
      || ot_allow=$(printf '%s' "$ot_allow" | jq -c --arg r "Bash($ot_cmd:*)" 'if index($r) == null then . + [$r] else . end')
  fi

  jq -nc --arg k "$ot_kinds" --arg cmd "$ot_cmd" --argjson allow "$ot_allow" '
    {toolchain: ($k | split(" ") | map(select(length > 0))),
     check: (if $cmd == "" then {} else {command: $cmd, deadline_seconds: 1800} end),
     allow: $allow}'
}

# onboard_plan_find <checkout> [<already registered plan>]: the repository-relative path of the file
# holding a milestone table, or nothing with status 1.
#
# A registered plan is kept if it still holds a table, because a person who named one meant it. The
# conventional names are tried next, and then every markdown file within two directories, so an
# unfamiliar repository's plan is found rather than demanded at `docs/MILESTONES.md`. "Holds a
# table" is the same test the reader makes: a row whose first cell is `ID`.
onboard_plan_find() {
  opf_c=$1
  for opf_rel in ${2:+"$2"} docs/MILESTONES.md MILESTONES.md docs/PLAN.md PLAN.md docs/ROADMAP.md ROADMAP.md; do
    [ -f "$opf_c/$opf_rel" ] || continue
    if grep -Eq "$ONBOARD_ID_HEADER" "$opf_c/$opf_rel"; then
      printf '%s\n' "$opf_rel"; return 0
    fi
  done
  opf_hit=$(cd "$opf_c" && find . -name '*.md' -type f -maxdepth 3 2>/dev/null \
            | sed 's|^\./||' | LC_ALL=C sort \
            | while IFS= read -r opf_f; do
                if grep -Eq "$ONBOARD_ID_HEADER" "$opf_f" 2>/dev/null; then
                  printf '%s\n' "$opf_f"; break
                fi
              done)
  [ -n "$opf_hit" ] || return 1
  printf '%s\n' "$opf_hit"
}

# onboard_status_native <token>: whether a status token is already one the plan contract names.
onboard_status_native() {
  case "$1" in ''|done|held) return 0 ;; *) return 1 ;; esac
}

# onboard_status_propose <token>: the native status a source vocabulary's word maps to, as
# `{status, why}` — `why` only where the mapping loses something a reader would want back.
#
# The native vocabulary is three words (`done`, `held`, blank) and it cannot say "retired". So a
# retired or superseded row borrows `held`, with its supersession as prose beside it: never `done`,
# which would let a successor inherit it as a satisfied dependency, and never blank, which would
# make it runnable. No gate is invented for it either — a gate is a hold a person clears, and
# retirement is not waiting for anyone (SCOPE §6 M11).
#
# Anything this does not recognise is left unmapped, and an unmapped token fails the parse. A
# vocabulary word guessed at is the "tolerance erases intent" failure: better to park and be told.
onboard_status_propose() {
  osp_t=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$osp_t" in
    done|complete|completed|shipped|released|merged|closed|finished)
      jq -nc '{status: "done"}' ;;
    retired|superseded|obsolete|abandoned|cancelled|canceled|dropped|wontfix)
      jq -nc --arg t "$1" '{status: "held", why: "\"\($t)\" is retirement, which the native vocabulary cannot say: it reads held, so it never runs and never satisfies a dependency, and no gate waits to clear it"}' ;;
    held|blocked|'on hold'|paused|waiting|deferred|postponed)
      jq -nc --arg t "$1" '{status: "held", why: "\"\($t)\" is a hold the source plan already carries; it reads held"}' ;;
    ''|todo|'to do'|open|planned|pending|backlog|'in progress'|wip|doing|active|next)
      jq -nc '{status: ""}' ;;
    *) return 1 ;;
  esac
}

# onboard_adaptation <file>: the adaptation a plan needs in order to be read as it stands, as
# `{defaults: {<column>: <value>}, status_map: {<token>: {status, why}}, gates: "present"|"absent",
#  unmapped: [<token>]}`; status 1 when the file holds no milestone table at all.
#
# `defaults` keys are column names. A key's presence makes that column optional **and** supplies
# the value where the column is absent or its cell is empty — one rule covering both of L1's
# shapes, a `Model` column missing from the header and a `Model` cell left blank on some rows.
# `Effort`, `Remote` and `Status` are defaulted only when their column is absent, because blank is
# a token those columns really have and defaulting a present blank would be reading a person's
# deliberate blank as an omission.
#
# `unmapped` is what onboarding could not map. It is reported rather than guessed, and it is what
# separates a plan needing adaptation from plan input that is not usable.
onboard_adaptation() {
  oa_f=$1
  oa_head=$(awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*\|/ {
      line = $0; gsub(/\\\|/, "\001", line)
      n = split(line, p, "|"); if (trim(p[n]) != "") n++
      out = ""
      for (i = 2; i < n; i++) { c = trim(p[i]); gsub(/\001/, "|", c); out = out (out == "" ? "" : "\t") c }
      if (out == "ID" || out ~ /^ID\t/ || out ~ /\tID\t/ || out ~ /\tID$/) { print out; exit }
    }' "$oa_f")
  [ -n "$oa_head" ] || return 1

  oa_defaults='{}'
  # The default model: the alias a person would have written, taken from config.json's own map so
  # that the value is one `parse_model` resolves rather than a literal id Baton invented.
  oa_model=$(jq -r '(.models // {}) | if has("opus") then "opus" else (keys_unsorted[0] // "") end' \
               "$BATON_HOME/config.json" 2>/dev/null || echo '')
  [ -n "$oa_model" ] && [ "$oa_model" != null ] || oa_model=opus

  for oa_col in Model Effort Remote Status; do
    if ! printf '\t%s\t' "$oa_head" | grep -Fq "	$oa_col	"; then
      case "$oa_col" in
        Model) oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg m "$oa_model" '. + {Model: $m}') ;;
        *)     oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg c "$oa_col" '. + {($c): ""}') ;;
      esac
    fi
  done
  # A present `Model` column with an empty cell needs the same default, because a blank model is
  # not a token the column has (`parse_model ""` fails) and a plan is allowed to leave it out.
  if printf '\t%s\t' "$oa_head" | grep -Fq "	Model	"; then
    if onboard_cells "$oa_f" Model | grep -q '^$'; then
      oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg m "$oa_model" '. + {Model: $m}')
    fi
  fi

  oa_map='{}'; oa_unmapped='[]'
  if printf '\t%s\t' "$oa_head" | grep -Fq "	Status	"; then
    oa_seen=''
    while IFS= read -r oa_tok; do
      onboard_status_native "$oa_tok" && continue
      case "$oa_seen" in *"|$oa_tok|"*) continue ;; esac
      oa_seen="$oa_seen|$oa_tok|"
      if oa_prop=$(onboard_status_propose "$oa_tok"); then
        oa_map=$(printf '%s' "$oa_map" | jq -c --arg t "$oa_tok" --argjson p "$oa_prop" '. + {($t): $p}')
      else
        oa_unmapped=$(printf '%s' "$oa_unmapped" | jq -c --arg t "$oa_tok" '. + [$t]')
      fi
    done <<TOKENS
$(onboard_cells "$oa_f" Status)
TOKENS
  fi

  if grep -Eq '^[[:space:]]*\|[[:space:]]*Gate[[:space:]]*\|' "$oa_f"; then oa_gates=present; else oa_gates=absent; fi

  jq -nc --argjson d "$oa_defaults" --argjson m "$oa_map" --arg g "$oa_gates" --argjson u "$oa_unmapped" \
    '{defaults: $d, status_map: $m, gates: $g, unmapped: $u}'
}

# onboard_cells <file> <column>: every body cell of that column of the milestone table, one per
# line, trimmed, blanks included. The same table location and the same cell splitting the reader
# uses, so what onboarding inspects and what the reader parses cannot disagree.
onboard_cells() {
  awk -v want="$2" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function cells(line,   n, i, c, p) {
      split("", C); nc = 0
      gsub(/\\\|/, "\001", line)
      n = split(line, p, "|"); if (trim(p[n]) != "") n++
      for (i = 2; i < n; i++) { c = trim(p[i]); gsub(/\001/, "|", c); C[++nc] = c }
      return nc
    }
    /^[ \t]*\|/ {
      cells($0)
      if (state == "") {
        found = 0
        for (i = 1; i <= nc; i++) if (C[i] == "ID") found = 1
        if (found) {
          for (i = 1; i <= nc; i++) if (C[i] == want) col = i
          if (col == 0) exit 0
          state = "sep"
        }
        next
      }
      if (state == "sep") { state = "body"; next }
      if (col <= nc) print C[col]
      next
    }
    { if (state == "body") exit 0 }
  ' "$1"
}

# onboard_cli_shape: the shapes the judgment role consumes, as `{version, ok, detail}`.
#
# M4: nothing anywhere runs `claude --version`, so a CLI change would be found by whatever broke
# first. This asks the one question the new role depends on and records the answer, and it is
# deliberately not a general sweep: a check on an interface this milestone does not consume would
# be a check nothing keeps honest.
onboard_cli_shape() {
  if ! ocs_v=$("$BATON_CLAUDE" --version 2>&1); then
    jq -nc --arg d "$BATON_CLAUDE --version failed: $ocs_v" '{version: "", ok: false, detail: $d}'
    return 0
  fi
  ocs_v=$(printf '%s' "$ocs_v" | head -1)
  jq -nc --arg v "$ocs_v" '{version: $v, ok: true}'
}

# onboard_evidence <checkout> <plan rel>: the bounded repository evidence the judgment request is
# given. The documents a person would read first, cut to a size that keeps the request small, plus
# the plan's own milestone titles, which say what the project thinks it is doing better than any
# prose. Nothing is executed and nothing outside the checkout is read.
onboard_evidence() {
  oe_c=$1; oe_plan=${2:-}
  for oe_f in README.md README CLAUDE.md AGENTS.md; do
    [ -f "$oe_c/$oe_f" ] || continue
    printf '%s\n' "--- $oe_f ---"
    head -60 "$oe_c/$oe_f"
    printf '\n'
  done
  if [ -n "$oe_plan" ] && [ -f "$oe_c/$oe_plan" ]; then
    printf '%s\n' "--- $oe_plan, the milestone table header and rows ---"
    grep -E '^[[:space:]]*\|' "$oe_c/$oe_plan" | head -40
    printf '\n'
  fi
}

# onboard_judge <checkout> <plan rel> <toolchain json>: the confirmed intent record's content, as
# `{goal, done, constraints: [...], non_goals: [...]}`; the detail and status 1 when the request did
# not answer.
#
# This is the one **judgment request** in Baton: `claude -p`, in the foreground, under the verb's
# own lock, against the subscription like every other call Baton makes (SCOPE §4 — a direct API
# call would move execution onto metered pricing silently). It is not a session: it has no name, no
# row, no attempt and no artifact, so derivation 1 cannot see it and the cap is untouched. That is
# what keeps the role from deadlocking the cap — there is no slot to hold (ARCHITECTURE §4.5).
#
# The answer is asked for as four labelled lines rather than JSON, because a label a `sed` can find
# is the smallest shape that can be checked, and a fenced JSON document is one more thing that can
# arrive malformed. A reply that does not carry `GOAL:` is a failure and never a guess: §7 item 4
# says a guessed goal is not silently confirmed.
#
# The deadline exists because the verb holds Baton's lock. A request that never returned would stop
# the relay until someone noticed, which is the one failure that costs a whole night, and it is why
# `lock_stale_break` exists at all. The done-marker is renamed into place for `completion_check_run`'s
# reason: `>` creates a file before anything is in it, so a poll testing only for existence can read
# an empty answer and call a request that succeeded a failure.
onboard_judge() {
  oj_c=$1; oj_plan=${2:-}; oj_tool=${3:-'{}'}
  oj_kinds=$(printf '%s' "$oj_tool" | jq -r '(.toolchain // []) | join(", ")')
  oj_check=$(printf '%s' "$oj_tool" | jq -r '.check.command // ""')

  oj_ask="Read the evidence below from a Git repository at $oj_c and answer in exactly four lines,
each beginning with its label and nothing before it. No preamble, no code fence, no other lines.

GOAL: one sentence saying what this project is for, in the project's own terms.
DONE: one sentence saying what finished looks like for it.
CONSTRAINTS: the technical boundaries the project has committed to, semicolon-separated. Name the
implementation language or runtime it has settled on where the evidence states one.
NON-GOALS: things this project has decided not to do, semicolon-separated. Include a rewrite in
another language or storage engine where the evidence says the current one is settled.

Detected toolchain: ${oj_kinds:-none}. Standing check: ${oj_check:-none detected}.

$(onboard_evidence "$oj_c" "$oj_plan")"

  oj_dir=$BATON_HOME/.judge.$$
  rm -rf "$oj_dir"; mkdir -p "$oj_dir" || { echo "$oj_dir is not a directory Baton can write"; return 1; }
  oj_out=$oj_dir/answer.txt
  # `&& oj_s=0 || oj_s=$?` and not `; printf '%s' "$?"`: `set -eu` is in force inside the subshell
  # too, so a request that exits non-zero would kill the subshell before it wrote its status, the
  # marker would never appear, and a refusal Baton could have quoted would be reported as a request
  # that never answered. The one case this exists to distinguish, read as the other one.
  ( "$BATON_CLAUDE" -p "$oj_ask" > "$oj_out" 2>"$oj_dir/err.txt" && oj_s=0 || oj_s=$?
    printf '%s\n' "$oj_s" > "$oj_dir/exit.tmp"
    mv "$oj_dir/exit.tmp" "$oj_dir/exit" ) > /dev/null 2>&1 &
  oj_pid=$!
  oj_spent=0
  while [ ! -f "$oj_dir/exit" ] && [ "$oj_spent" -lt "$ONBOARD_JUDGE_DEADLINE" ]; do
    sleep 1
    oj_spent=$((oj_spent + 1))
  done
  if [ ! -f "$oj_dir/exit" ]; then
    kill "$oj_pid" 2>/dev/null || true
    kill -- "-$oj_pid" 2>/dev/null || true
    wait "$oj_pid" 2>/dev/null || true
    rm -rf "$oj_dir"
    echo "the judgment request did not answer within ${ONBOARD_JUDGE_DEADLINE}s and was stopped; run baton onboard again"
    return 1
  fi
  wait "$oj_pid" 2>/dev/null || true
  oj_status=$(cat "$oj_dir/exit")
  if [ "$oj_status" -ne 0 ]; then
    oj_detail=$(head -3 "$oj_dir/err.txt" 2>/dev/null | tr '\n' ' ')
    rm -rf "$oj_dir"
    echo "the judgment request exited $oj_status: ${oj_detail:-no output}"
    return 1
  fi

  oj_goal=$(sed -n 's/^[[:space:]]*GOAL:[[:space:]]*//p' "$oj_out" | head -1)
  oj_done=$(sed -n 's/^[[:space:]]*DONE:[[:space:]]*//p' "$oj_out" | head -1)
  oj_con=$(sed -n 's/^[[:space:]]*CONSTRAINTS:[[:space:]]*//p' "$oj_out" | head -1)
  oj_non=$(sed -n 's/^[[:space:]]*NON-GOALS:[[:space:]]*//p' "$oj_out" | head -1)
  rm -rf "$oj_dir"
  if [ -z "$oj_goal" ] || [ -z "$oj_done" ]; then
    echo "the judgment request answered without a GOAL: or DONE: line, so there is no statement to confirm"
    return 1
  fi
  jq -nc --arg g "$oj_goal" --arg d "$oj_done" --arg c "$oj_con" --arg n "$oj_non" '
    def list: split(";") | map(sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) | map(select(length > 0));
    {goal: $g, done: $d, constraints: ($c | list), non_goals: ($n | list)}'
}

# onboard_start <project key> <plan rel> <tables json>: the starting handover — every milestone the
# plan makes eligible now, with a disposition and a brief pointer, in the shape a `complete`
# handover's `eligible[]` carries.
#
# It is here because of what `intersect_verdicts` does with a project no handover has ever named:
# an eligible milestone yields *nothing* — no candidate, no park — which is L1's "registration
# without a seed otherwise dispatches and escalates nothing". The starting handover is the word in
# force until a real one supersedes it, and it says what the plan already says, which is why it is
# derived and not asked for.
#
# The disposition is computed the way every close-out computes one: an open gate first (`held`),
# then unfinished dependencies (`wait`), then `run`. A milestone whose row reads `done` or `held` is
# not named at all, because a starting handover is about what may start.
onboard_start() {
  os_key=$1; os_plan=$2; os_tables=$3
  os_dir=$(dirname "$os_plan")
  [ "$os_dir" != . ] || os_dir=docs
  printf '%s' "$os_tables" | jq -c --arg d "$os_dir/milestones" '
    (.milestones | map(select(.status == "done") | .id)) as $done
    | ([.gates[] | select(.cleared == "")]) as $open
    | [ .milestones[] | select(.status == "")
        | .id as $i
        | ([ $open[] | select(.holds | index($i) != null) | .gate ]) as $gates
        | ([ .depends[] | select(. as $x | $done | index($x) == null) ]) as $undone
        | {milestone: $i, brief: {path: "\($d)/\($i).md", heading: "Copy-ready session prompt"}}
          + (if ($gates | length) > 0 then {disposition: "held", held_by: $gates[0]}
             elif ($undone | length) > 0 then {disposition: "wait", wait_for: $undone}
             else {disposition: "run"} end) ]'
}

# onboard_confirm <lines>: the one routine human touchpoint of V1.1. Three lines and a yes or no.
#
# It is not a plan review, and it does not become one: it is the ten-second check that catches "this
# is a rewrite, and I did not want a rewrite". Anything other than yes is a no, because the
# confirmation is what makes the registration a person's act and a typo must not be read as assent.
onboard_confirm() {
  render_plain '%s\n' "$1"
  render_plain 'Register this project and let Baton run it? [yes/no] '
  read -r oc_answer || oc_answer=''
  case "$oc_answer" in
    yes|Yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# onboard_permissions_write <project key> <allow json>: the project's rail, written only when it
# differs, as `install.sh` writes Baton's own. The deny rules come from the one recipe above.
onboard_permissions_write() {
  opw_f=$BATON_HOME/projects/$1/permissions.json
  jq -nc --argjson a "$2" --argjson d "$(onboard_deny_rules)" \
    '{permissions: {allow: $a, deny: $d}}' | jq . > "$opw_f.tmp"
  if cmp -s "$opw_f.tmp" "$opw_f" 2>/dev/null; then rm -f "$opw_f.tmp"; else mv "$opw_f.tmp" "$opw_f"; fi
}

# onboard_registration_write <project key> <document json>: `project.json`, published by rename so a
# tick reading it mid-write is impossible, and left alone when it already says the same thing.
onboard_registration_write() {
  orw_f=$BATON_HOME/projects/$1/project.json
  printf '%s' "$2" | jq . > "$orw_f.tmp"
  if cmp -s "$orw_f.tmp" "$orw_f" 2>/dev/null; then rm -f "$orw_f.tmp"; else mv "$orw_f.tmp" "$orw_f"; fi
}

# onboard_migrate <project key> <toolchain json> <plan rel>: F11. A registration that predates the
# intent record gains the fields it lacks, additively, without touching what it has.
#
# `install.sh:131-133` writes `{path, plan}` only when `project.json` is absent, so reinstalling
# over a registration can never supply a field registration did not have — and Baton's own
# registration is exactly that case. The migration is therefore this verb's, and it must not reset
# progress: nothing here writes `plan`, `check` or a starting handover over a value already there,
# because the plan's `Status` cells and the archive are where progress lives and a re-seed would
# put a stale word back in force.
onboard_migrate() {
  om_key=$1; om_tool=$2; om_plan=$3
  om_f=$BATON_HOME/projects/$om_key/project.json
  om_doc=$(jq -c . "$om_f") || { echo "$om_f does not parse"; return 1; }
  printf '%s' "$om_doc" | jq -c \
    --argjson check "$(printf '%s' "$om_tool" | jq -c '.check // {}')" --arg plan "$om_plan" '
    . as $d
    | (if (($d.check.command // "") == "") and (($check.command // "") != "")
       then .check = $check else . end)
    | (if $plan != "" then .plan = $plan else . end)'
}

# onboard_report <project key> <document json> [<heading word>]: what the person reads once the registration is
# written — the values stored, how the plan was obtained, the rail's size, and then the plan and its
# dispatch preconditions through the verbs that already print them, so onboarding cannot drift into
# a second way of saying what `baton plan` says.
onboard_report() {
  orp_key=$1; orp_doc=$2
  render_heading out '%s %s\n' "${3:-onboarded}" "$orp_key"
  render_row out record '  checkout    %s\n' "$(render_token out path "$(printf '%s' "$orp_doc" | jq -r .path)")"
  render_row out record '  plan        %s (%s)\n' \
    "$(render_token out path "$(printf '%s' "$orp_doc" | jq -r .plan)")" \
    "$(printf '%s' "$orp_doc" | jq -r .plan_format)"
  render_row out record '  check       %s\n' "$(printf '%s' "$orp_doc" | jq -r '.check.command // "none detected"')"
  render_row out record '  goal        %s\n' "$(printf '%s' "$orp_doc" | jq -r .goal)"
  render_row out record '  constraints %s\n' "$(printf '%s' "$orp_doc" | jq -r '(.constraints // []) | if length == 0 then "none recorded" else join("; ") end')"
  render_row out record '  non-goals   %s\n' "$(printf '%s' "$orp_doc" | jq -r '(.non_goals // []) | if length == 0 then "none recorded" else join("; ") end')"
  render_row out record '  onboarded   %s\n' "$(render_token out timestamp "$(printf '%s' "$orp_doc" | jq -r .onboarded_at)")"
  orp_ad=$(printf '%s' "$orp_doc" | jq -c '.adaptation // {}')
  if [ "$(printf '%s' "$orp_ad" | jq 'length')" -gt 0 ]; then
    if [ "$(printf '%s' "$orp_ad" | jq '(.defaults // {}) | length')" -gt 0 ]; then
      render_row out record '  defaulted   %s\n' \
        "$(printf '%s' "$orp_ad" | jq -r '.defaults | to_entries | map("\(.key)=\(if .value == "" then "blank" else .value end)") | join(", ")')"
    fi
    orp_map=$(printf '%s' "$orp_ad" | jq -c '.status_map // {}')
    orp_n=$(printf '%s' "$orp_map" | jq 'length')
    if [ "$orp_n" -gt 0 ]; then
      printf '%s' "$orp_map" | jq -r 'to_entries[] | "  status      \"\(.key)\" reads \(if .value.status == "" then "blank" else .value.status end)\(if (.value.why // "") == "" then "" else " · " + .value.why end)"' \
        | while IFS= read -r orp_line; do render_row out record '%s\n' "$orp_line"; done
    fi
  fi
  orp_start=$(printf '%s' "$orp_doc" | jq -c '.start.eligible // []')
  if [ "$(printf '%s' "$orp_start" | jq length)" -eq 0 ]; then
    render_row out record '  starting    the plan makes nothing eligible yet\n'
  else
    printf '%s' "$orp_start" | jq -r '.[] | "  starting    \(.milestone) · \(.disposition)\(if .wait_for then " for " + (.wait_for | join(", ")) else "" end)\(if .held_by then " by \"" + .held_by + "\"" else "" end) · \(.brief.path)"' \
      | while IFS= read -r orp_line; do render_row out record '%s\n' "$orp_line"; done
  fi
}

# verb_onboard <path>: the verb. Registration, the rail, the standing check, the plan as it stands,
# one confirmation, the starting handover, one event.
#
# Nothing is written before the yes. Everything after it is written by this process — the relay's
# own, under the lock — and never by a session through its file tools, which is the whole of M08's
# recorded defect (L1). A session may run this verb; what it may not do, and does not need to do, is
# write `projects/<key>/` itself.
verb_onboard() {
  vo_repo=$(onboard_repo "$1") || { render_failure err "baton: $vo_repo"; exit 2; }
  vo_checkout=$(printf '%s' "$vo_repo" | jq -r .checkout)
  vo_key=$(printf '%s' "$vo_repo" | jq -r .key)
  vo_f=$BATON_HOME/projects/$vo_key/project.json

  # A key already registered to another checkout is two projects with one name, and every path
  # Baton keys on that name — the session name, the log's project field, projects/<key>/ — would be
  # shared between them. Refused before anything is read, because there is no repair but a rename.
  if [ -f "$vo_f" ]; then
    vo_have=$(jq -r '.path // ""' "$vo_f" 2>/dev/null) || vo_have=''
    if [ -n "$vo_have" ] && [ "$vo_have" != "$vo_checkout" ]; then
      render_failure err "baton: project key $vo_key is already registered at $vo_have, and $vo_checkout would share its state" \
        "register it under a differently named checkout, or remove $BATON_HOME/projects/$vo_key first"
      exit 1
    fi
  fi

  vo_tool=$(onboard_toolchain "$vo_checkout")
  vo_registered=''
  [ ! -f "$vo_f" ] || vo_registered=$(jq -r '.plan // ""' "$vo_f" 2>/dev/null) || vo_registered=''
  vo_plan=$(onboard_plan_find "$vo_checkout" "$vo_registered") || vo_plan=''

  # A registration that already carries a confirmed goal is not asked again and is not re-seeded.
  # The Recovery procedure says so, and it is what makes a second run of the verb safe: onboarding
  # twice must not duplicate registration, reset progress or seed work a second time.
  if [ -f "$vo_f" ] && [ -n "$(jq -r '.goal // ""' "$vo_f" 2>/dev/null || true)" ]; then
    vo_doc=$(onboard_migrate "$vo_key" "$vo_tool" "$vo_plan") || { render_failure err "baton: $vo_doc"; exit 1; }
    onboard_registration_write "$vo_key" "$vo_doc"
    onboard_permissions_write "$vo_key" "$(printf '%s' "$vo_tool" | jq -c .allow)"
    render_heading out '%s is already onboarded · the confirmed goal stands, nothing was asked again and nothing was seeded twice\n' "$vo_key"
    onboard_report "$vo_key" "$(jq -c . "$vo_f")" registered
    return 0
  fi

  vo_shape=$(onboard_cli_shape)
  if ! printf '%s' "$vo_shape" | jq -e .ok > /dev/null; then
    render_failure err "baton: $(printf '%s' "$vo_shape" | jq -r .detail)"
    exit 1
  fi

  # The plan, strictly first. A plan that parses under the contract's own rules is `native` and is
  # read strictly for ever after, so a misspelt cell in it still parks rather than defaulting.
  vo_format=''; vo_adapt='{}'; vo_tables=''
  if [ -n "$vo_plan" ] && vo_tables=$(plan_tables "$vo_checkout/$vo_plan" 2>/dev/null); then
    vo_format=native
  elif [ -n "$vo_plan" ]; then
    vo_adapt=$(onboard_adaptation "$vo_checkout/$vo_plan") || vo_adapt='{}'
    vo_unmapped=$(printf '%s' "$vo_adapt" | jq -r '(.unmapped // []) | join(", ")')
    if [ -n "$vo_unmapped" ]; then
      render_failure err "baton: $vo_plan has Status values Baton cannot map to done, held or blank: $vo_unmapped" \
        "map them in that column by hand, or onboard again once the plan says done, held or blank"
      exit 1
    fi
    if vo_tables=$(plan_tables "$vo_checkout/$vo_plan" '' "$vo_adapt" 2>/dev/null); then
      vo_format=adapted
    else
      # The reader's own refusal, not a summary of it: a cell that will not parse under the
      # adaptation is the thing that makes this plan input unusable rather than adaptable, and the
      # person is told which cell rather than that the plan "could not be read".
      render_row out record '  plan        %s does not parse even with defaults: %s\n' \
        "$(render_token out path "$vo_plan")" \
        "$(printf '%s' "$vo_tables" | jq -r '"the \(.table) table, row \(.row), cell \(.cell): \(.detail)"' 2>/dev/null \
           || printf '%s' 'no milestone table was found')"
      vo_format=''
    fi
  fi

  if [ -z "$vo_format" ]; then
    verb_onboard_noplan "$vo_key" "$vo_checkout" "$vo_plan" "$vo_tool" "$vo_shape"
    return $?
  fi

  vo_intent=$(onboard_judge "$vo_checkout" "$vo_plan" "$vo_tool") \
    || { render_failure err "baton: $vo_intent"; exit 1; }

  vo_lines=$(onboard_intent_lines "$vo_key" "$vo_checkout" "$vo_intent" "$vo_format" "$vo_tool")
  if ! onboard_confirm "$vo_lines"; then
    render_failure out "baton: not confirmed, so $vo_key is not registered and nothing is dispatched" \
      "run baton onboard $vo_checkout again when the statement above is right"
    exit 1
  fi

  vo_now=$(baton_now)
  vo_start=$(onboard_start "$vo_key" "$vo_plan" "$vo_tables")
  mkdir -p "$BATON_HOME/projects/$vo_key"
  # F11, and the reason the document is built by merging onto whatever is already there rather than
  # written whole: an existing registration is migrated into the intent representation, and a
  # migration that replaced the file would take a `plan` or a `check.command` a person had set by
  # hand with it. `install.sh:131-133` writes `{path, plan}` only when the file is absent, so a
  # registration that predates the intent record can never gain one by reinstalling; this is where
  # it gains one, and nothing it already says is overwritten.
  vo_base='{}'
  [ ! -f "$vo_f" ] || vo_base=$(jq -c . "$vo_f" 2>/dev/null) || vo_base='{}'
  vo_doc=$(jq -nc --argjson base "$vo_base" \
    --arg p "$vo_checkout" --arg plan "$vo_plan" --arg fmt "$vo_format" --arg at "$vo_now" \
    --argjson check "$(printf '%s' "$vo_tool" | jq -c '.check // {}')" \
    --argjson intent "$vo_intent" --argjson adapt "$vo_adapt" --argjson start "$vo_start" \
    --argjson cli "$vo_shape" '
    $base
    + {path: $p}
    # The plan pointer is set to the file that actually holds the table, which is the registered one
    # wherever that still holds it — `onboard_plan_find` tries it first for exactly that reason. It
    # is a pointer and not progress: progress is the `Status` cells and the archive, and pointing at
    # a file that no longer has a table would be the one repair a migration must make.
    + (if $plan != "" then {plan: $plan} else {} end)
    # The standing check is the exception, because a person who changed the command meant it (D-147).
    + (if (($base.check.command // "") == "") and (($check.command // "") != "")
       then {check: $check} else {} end)
    + {goal: $intent.goal, done: $intent.done,
       constraints: $intent.constraints, non_goals: $intent.non_goals,
       plan_format: $fmt, onboarded_at: $at,
       cli: {version: $cli.version, checked_at: $at},
       start: {at: $at, eligible: $start}}
    + (if $fmt == "adapted" then {adaptation: ($adapt | del(.unmapped))} else {} end)')
  onboard_registration_write "$vo_key" "$vo_doc"
  onboard_permissions_write "$vo_key" "$(printf '%s' "$vo_tool" | jq -c .allow)"
  log_event onboarded "$vo_key" "" "" "" "$(jq -nc --arg c "$vo_checkout" --arg plan "$vo_plan" \
    --arg fmt "$vo_format" --argjson tool "$(printf '%s' "$vo_tool" | jq -c '.toolchain // []')" \
    --arg check "$(printf '%s' "$vo_tool" | jq -r '.check.command // ""')" \
    --arg cli "$(printf '%s' "$vo_shape" | jq -r .version)" \
    --argjson start "$(printf '%s' "$vo_start" | jq -c '[.[] | {milestone, disposition}]')" '
    {checkout: $c, plan: $plan, plan_format: $fmt, toolchain: $tool, cli_version: $cli,
     start: $start} + (if $check == "" then {} else {check: $check} end)')"
  onboard_report "$vo_key" "$(jq -c . "$BATON_HOME/projects/$vo_key/project.json")"
  render_heading out 'the next tick reads %s and dispatches what the starting handover says run\n' "$vo_key"
}

# verb_onboard_noplan <key> <checkout> <plan rel> <toolchain json> <cli json>: a repository with no
# plan Baton can read.
#
# This is not a failure and it is not a successful adaptation either: presenting a missing plan as
# one would be the worst of the three outcomes, because the chain would then run against a graph
# nobody wrote. The confirmed goal is still taken and stored — it is the input M12's generator
# needs — and `plan_format` reads `generated` to say the plan is owed. Nothing is seeded, because
# there is no milestone to name, and generation itself is M12's and is not attempted here.
verb_onboard_noplan() {
  vnp_key=$1; vnp_checkout=$2; vnp_plan=$3; vnp_tool=$4; vnp_shape=$5
  vnp_intent=$(onboard_judge "$vnp_checkout" "$vnp_plan" "$vnp_tool") \
    || { render_failure err "baton: $vnp_intent"; exit 1; }
  vnp_lines=$(onboard_intent_lines "$vnp_key" "$vnp_checkout" "$vnp_intent" generated "$vnp_tool")
  if ! onboard_confirm "$vnp_lines"; then
    render_failure out "baton: not confirmed, so $vnp_key is not registered and nothing is dispatched" \
      "run baton onboard $vnp_checkout again when the statement above is right"
    exit 1
  fi
  vnp_now=$(baton_now)
  mkdir -p "$BATON_HOME/projects/$vnp_key"
  vnp_doc=$(jq -nc --arg p "$vnp_checkout" --arg plan "${vnp_plan:-docs/MILESTONES.md}" --arg at "$vnp_now" \
    --argjson check "$(printf '%s' "$vnp_tool" | jq -c '.check // {}')" \
    --argjson intent "$vnp_intent" --argjson cli "$vnp_shape" '
    {path: $p, plan: $plan}
    + (if ($check | length) > 0 then {check: $check} else {} end)
    + {goal: $intent.goal, done: $intent.done,
       constraints: $intent.constraints, non_goals: $intent.non_goals,
       plan_format: "generated", onboarded_at: $at,
       cli: {version: $cli.version, checked_at: $at},
       plan_owed: {reason: "no readable milestone table was found in the repository",
                   owner: "M12"}}')
  onboard_registration_write "$vnp_key" "$vnp_doc"
  onboard_permissions_write "$vnp_key" "$(printf '%s' "$vnp_tool" | jq -c .allow)"
  log_event onboarded "$vnp_key" "" "" "" "$(jq -nc --arg c "$vnp_checkout" --arg cli "$(printf '%s' "$vnp_shape" | jq -r .version)" \
    --argjson tool "$(printf '%s' "$vnp_tool" | jq -c '.toolchain // []')" \
    '{checkout: $c, plan_format: "generated", toolchain: $tool, cli_version: $cli,
      plan_owed: "M12"}')"
  render_heading out 'onboarded %s with no usable plan\n' "$vnp_key"
  render_row out record '  checkout    %s\n' "$(render_token out path "$vnp_checkout")"
  render_row out record '  goal        %s\n' "$(printf '%s' "$vnp_intent" | jq -r .goal)"
  render_row out record '  plan        none readable; plan_format is generated and the plan is owed\n'
  render_row out action '  next        M12 generates the plan from the confirmed goal; nothing is dispatched until one exists\n'
}

# onboard_intent_lines <key> <checkout> <intent json> <plan format> <toolchain json>: the three
# lines a person reads before the yes — what the project is, what done looks like, and what it has
# committed to not doing — with the fourth line saying how the plan was obtained, because a person
# confirming intent is entitled to know whether Baton read a plan or is about to owe one.
#
# Three lines is the requirement and the point: it is a ten-second check, not a plan review. What
# they carry is the whole of the confirmed intent record, so that the yes covers the constraints and
# the non-goals and not the goal alone — one goal admits both a permitted extension and a forbidden
# controller replacement, and a goal-only record cannot tell them apart (SCOPE §8 item 6, F10).
onboard_intent_lines() {
  oil_key=$1; oil_checkout=$2; oil_intent=$3; oil_format=$4; oil_tool=$5
  printf '%s' "$oil_intent" | jq -r --arg k "$oil_key" --arg c "$oil_checkout" --arg f "$oil_format" \
    --arg check "$(printf '%s' "$oil_tool" | jq -r '.check.command // "none detected"')" '
    "\($k) at \($c) — \(.goal)",
    "Done: \(.done)",
    "Must hold: \((.constraints | if length == 0 then "nothing recorded" else join("; ") end)) · Not this: \((.non_goals | if length == 0 then "nothing recorded" else join("; ") end))",
    "Plan: \(if $f == "native" then "read as it stands" elif $f == "adapted" then "read with Baton'"'"'s own defaults, changing nothing in the repository" else "none readable — M12 must generate one" end). Standing check: \($check)."'
}
