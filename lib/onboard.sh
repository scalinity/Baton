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

# The judgment request's bound, and the bounds on the evidence it is given. Named here because they
# are the numbers a person would want to change and because a number written twice is a number that
# will one day differ from itself. The standing check's default deadline is `install.sh`'s, for
# Baton's own registration, and is the same value for the same reason.
ONBOARD_JUDGE_DEADLINE=${ONBOARD_JUDGE_DEADLINE:-120}
ONBOARD_CHECK_DEADLINE=1800
ONBOARD_EVIDENCE_LINES=60
ONBOARD_EVIDENCE_ROWS=40

# A literal tab, built rather than typed: the header cells `onboard_adaptation` inspects are joined
# on one, and a tab written into the source is invisible to a reader and the first thing an editor
# turns into spaces.
ONBOARD_TAB=$(printf '\t')

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
# The allow list is the check's own rule, `jq`, then the detected drivers — `install.sh`'s own order,
# which for Baton's own checkout produces exactly the list it writes.
# Under `bypassPermissions` allow rules allow nothing and cost nothing; they are what makes a
# hand-started session passing the same settings file behave as a dispatched one (ARCHITECTURE §3).
# Nothing is derived that needs an access grant: a credential or a private registry is a human fact
# and stays one.
onboard_toolchain() {
  ot_c=$1
  ot_kinds=''
  ot_drivers='[]'
  ot_cmd=''

  # Ordered by how specific the evidence is, and the first match names the check.
  if [ -f "$ot_c/tests/run.sh" ]; then
    ot_kinds="$ot_kinds shell"; ot_cmd='sh tests/run.sh'
  fi
  if [ -f "$ot_c/package.json" ]; then
    ot_kinds="$ot_kinds node"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(npm:*)", "Bash(node:*)"]')
    if [ -z "$ot_cmd" ] && jq -e '.scripts.test // empty' "$ot_c/package.json" > /dev/null 2>&1; then
      ot_cmd='npm test'
    fi
  fi
  if [ -f "$ot_c/Cargo.toml" ]; then
    ot_kinds="$ot_kinds rust"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(cargo:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='cargo test'
  fi
  if [ -f "$ot_c/go.mod" ]; then
    ot_kinds="$ot_kinds go"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(go:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='go test ./...'
  fi
  if [ -f "$ot_c/Package.swift" ]; then
    ot_kinds="$ot_kinds swift"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(swift:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='swift test'
  fi
  if [ -f "$ot_c/pyproject.toml" ] || [ -f "$ot_c/setup.py" ] || [ -f "$ot_c/pytest.ini" ]; then
    ot_kinds="$ot_kinds python"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(python3:*)", "Bash(pytest:*)"]')
    [ -n "$ot_cmd" ] || ot_cmd='pytest'
  fi
  # A Makefile is evidence of a driver whichever language sits under it, and it supplies the check
  # only when it really has a `test` target — a grep for the target and not for the word.
  if [ -f "$ot_c/Makefile" ]; then
    ot_kinds="$ot_kinds make"
    ot_drivers=$(printf '%s' "$ot_drivers" | jq -c '. + ["Bash(make:*)"]')
    if [ -z "$ot_cmd" ] && grep -Eq '^test[[:space:]]*:' "$ot_c/Makefile"; then ot_cmd='make test'; fi
  fi

  # The allow list, in `install.sh`'s own order: the check's whole-invocation rule first, then
  # `Bash(jq:*)`, then the detected drivers. The order is not cosmetic — `baton onboard` on Baton's
  # own checkout and the next close-out's `install.sh` write the same file, and a list in a different
  # order differs by `cmp`, so each would replace the other's every time.
  #
  # The check's own rule is included only where the driver it starts with is not allowed already:
  # `Bash(cargo test:*)` beside `Bash(cargo:*)` allows nothing the broader rule did not, and a rule
  # that adds nothing is a rule a reader has to work out the purpose of.
  ot_allow='[]'
  if [ -n "$ot_cmd" ]; then
    ot_first=${ot_cmd%% *}
    printf '%s' "$ot_drivers" | jq -e --arg d "Bash($ot_first:*)" 'index($d) != null' > /dev/null \
      || ot_allow=$(jq -nc --arg r "Bash($ot_cmd:*)" '[$r]')
  fi
  # Concatenated and not de-duplicated, because the construction cannot repeat a rule: the check's
  # rule is added only when its driver is absent, `Bash(jq:*)` is added once, and each driver arm
  # runs at most once. A `unique` here would sort, and the order is the contract.
  ot_allow=$(jq -nc --argjson a "$ot_allow" --argjson d "$ot_drivers" '$a + ["Bash(jq:*)"] + $d')

  jq -nc --arg k "$ot_kinds" --arg cmd "$ot_cmd" --argjson allow "$ot_allow" \
    --argjson deadline "$ONBOARD_CHECK_DEADLINE" '
    {toolchain: ($k | split(" ") | map(select(length > 0))),
     check: (if $cmd == "" then {} else {command: $cmd, deadline_seconds: $deadline} end),
     allow: $allow}'
}

# onboard_plan_find <checkout> [<already registered plan>]: the repository-relative path of the file
# holding a milestone table, or nothing with status 1.
#
# A registered plan is kept if it still holds a table, because a person who named one meant it. The
# conventional names are tried next, and only then a search — under `docs/` first, then the rest of
# the repository to a depth of three — so an unfamiliar repository's plan is found rather than
# demanded at `docs/MILESTONES.md`.
#
# The search prunes `.git`, `node_modules`, `vendor` and every dot-directory, and it searches `docs/`
# before the root. Without that, a repository's own `CHANGELOG.md` sorts before `docs/` and a
# dependency's bundled `README.md` is in range, and any markdown table in one of them with a column
# called `ID` would be registered as the plan — which the tick then parks on, every minute, naming a
# file nobody thinks of as a plan.
#
# "Holds a table" is asked of `onboard_has_table`, which locates the table exactly as the reader does.
# Asking it rather than matching a regex of its own is what keeps the finder and the reader from
# disagreeing about what a plan is; a file that survives this test is one `plan_tables` will find the
# same table in.
onboard_plan_find() {
  opf_c=$1
  for opf_rel in ${2:+"$2"} docs/MILESTONES.md MILESTONES.md docs/PLAN.md PLAN.md docs/ROADMAP.md ROADMAP.md; do
    [ -f "$opf_c/$opf_rel" ] || continue
    if onboard_has_table "$opf_c/$opf_rel" 2>/dev/null; then
      printf '%s\n' "$opf_rel"; return 0
    fi
  done
  # Three things this line has to get right, each of which fails silently:
  #   * `-maxdepth` first, because it is a global option and belongs before the expression;
  #   * `'.?*'` and not `'.*'`, because the starting point's own name is `.` and `.*` matches it, so
  #     the whole tree is pruned and nothing is found — a failure that looks exactly like a repository
  #     with no plan, which is how it was found;
  #   * the `./` prefix kept until the last moment, because a filename beginning with `-` becomes an
  #     option to whatever reads it and `./-x.md` cannot.
  opf_list=$(cd "$opf_c" && find . -maxdepth 3 \
      \( -name .git -o -name node_modules -o -name vendor -o -name '.?*' \) -prune -o \
      -name '*.md' -type f -print 2>/dev/null | LC_ALL=C sort) || opf_list=''
  # `docs/` before the root, and a header with both cells before one with only `ID`. The loose pass
  # exists so that a plan whose milestone table really has no `Depends on` column is handed to the
  # reader, which names the missing column, rather than reported as no plan at all — the two are
  # different problems and only one of them is M12's.
  for opf_companion in 'Depends on' ''; do
    for opf_where in './docs/' ''; do
      printf '%s\n' "$opf_list" | while IFS= read -r opf_f; do
        [ -n "$opf_f" ] || continue
        case "$opf_f" in "$opf_where"*) ;; *) continue ;; esac
        if ( cd "$opf_c" && onboard_has_table "$opf_f" "$opf_companion" ) 2>/dev/null; then
          printf '%s\n' "${opf_f#./}"; break
        fi
      done
    done
  done | head -1 | grep . || return 1
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
  oa_head=$(onboard_header "$oa_f")
  [ -n "$oa_head" ] || return 1

  oa_defaults='{}'
  # The default model: the alias a person would have written, taken from config.json's own map so
  # that the value is one `parse_model` resolves rather than a literal id Baton invented.
  oa_model=$(jq -r '(.models // {}) | if has("opus") then "opus" else (keys_unsorted[0] // "") end' \
               "$BATON_HOME/config.json" 2>/dev/null || echo '')
  [ -n "$oa_model" ] && [ "$oa_model" != null ] || oa_model=opus

  # `onboard_has_column` rather than a tab-literal grep: the header arrives tab-joined, and a tab
  # typed into the source is invisible to a reader and the first thing an editor turns into spaces.
  for oa_col in Model Effort Remote Status; do
    if ! onboard_has_column "$oa_head" "$oa_col"; then
      case "$oa_col" in
        Model) oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg m "$oa_model" '. + {Model: $m}') ;;
        *)     oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg c "$oa_col" '. + {($c): ""}') ;;
      esac
    fi
  done
  # A present `Model` column with an empty cell needs the same default, because a blank model is
  # not a token the column has (`parse_model ""` fails) and a plan is allowed to leave it out.
  if onboard_has_column "$oa_head" Model && onboard_cells "$oa_f" Model | grep -q '^$'; then
    oa_defaults=$(printf '%s' "$oa_defaults" | jq -c --arg m "$oa_model" '. + {Model: $m}')
  fi

  oa_map='{}'; oa_unmapped='[]'
  if onboard_has_column "$oa_head" Status; then
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

  # The gates table located the way the reader locates it — a header carrying both `Gate` and
  # `Holds`, in any column position — so a gates table whose first column is something else is not
  # recorded as absent while the reader goes on parsing it. `gates: "absent"` is a permission, and a
  # permission granted for a table that is there would hide its later disappearance.
  if [ -n "$(onboard_cells "$oa_f" --header Holds Gate)" ]; then oa_gates=present; else oa_gates=absent; fi

  jq -nc --argjson d "$oa_defaults" --argjson m "$oa_map" --arg g "$oa_gates" --argjson u "$oa_unmapped" \
    '{defaults: $d, status_map: $m, gates: $g, unmapped: $u}'
}

# onboard_cells <file> <column>: every body cell of that column of the milestone table, one per
# line, trimmed, blanks included; nothing at all when the file holds no milestone table or that
# table has no such column.
#
# It locates the table the way `plan_extract` does — a header carrying both `ID` and `Depends on`,
# in any column position — and splits cells the way `plan_extract` does, escaped pipes included.
# **They are two implementations of one rule, not shared code**, and that is a known cost: awk
# programs cannot be composed in POSIX shell without building them as strings, and the reader's is
# already a large one. What keeps them from drifting is that onboarding asks this function rather
# than a regex of its own for every question it has about a plan's shape, so there are two copies
# and not four, and a fixture that reads a plan one way and parses it the other would catch a
# divergence in either.
onboard_cells() {
  awk -v want="$2" -v companion="${3-Depends on}" -v locator="${4:-ID}" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function cells(line,   n, i, c, p) {
      split("", C); nc = 0
      gsub(/\\\|/, "\001", line)
      n = split(line, p, "|"); if (trim(p[n]) != "") n++
      for (i = 2; i < n; i++) { c = trim(p[i]); gsub(/\001/, "|", c); C[++nc] = c }
      return nc
    }
    function has(name,   i) { for (i = 1; i <= nc; i++) if (C[i] == name) return 1; return 0 }
    /^[ \t]*\|/ {
      cells($0)
      if (state == "") {
        # Both cells by default, as the reader requires: a traceability table with an ID column is
        # not the milestone table, and treating it as one is how a readable plan comes to look
        # unreadable. An empty companion asks the looser question — is there a header with an ID
        # cell at all — which is what the finder falls back to, so that a plan whose table really
        # does lack Depends on reaches the reader and is refused in the words the reader has for it.
        if (has(locator) && (companion == "" || has(companion))) {
          if (want == "--header") {
            out = ""
            for (i = 1; i <= nc; i++) out = out (i == 1 ? "" : "\t") C[i]
            print out
            exit 0
          }
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

# onboard_header <file> [<companion>]: the milestone table's header cells, joined on a tab; nothing
# when the file holds no milestone table. `onboard_cells` with the column name `--header`, so the
# header and the cells are found by one program: a table with a header and no body rows is still a
# table, which a column's cells cannot say and this can.
onboard_header() { onboard_cells "$1" --header "${2-Depends on}"; }

# onboard_has_column <header> <name>: whether that tab-joined header carries that column. The header
# is data and the name is a literal, so the comparison walks the fields rather than matching a pattern
# — a column called `M*` would otherwise be a glob.
onboard_has_column() {
  ohc_head=$1$ONBOARD_TAB
  while [ -n "$ohc_head" ]; do
    case "$ohc_head" in
      "$2$ONBOARD_TAB"*) return 0 ;;
    esac
    ohc_head=${ohc_head#*"$ONBOARD_TAB"}
  done
  return 1
}

# onboard_has_table <file> [<companion>]: whether the file holds a milestone table the reader would
# locate. The one question the plan search asks of every candidate.
onboard_has_table() { [ -n "$(onboard_header "$1" "${2-Depends on}")" ]; }

# onboard_cli_shape: the shapes the judgment role consumes, as `{version, ok, detail}`.
#
# M4: nothing anywhere runs `claude --version`, so a CLI change would be found by whatever broke
# first. This asks the one question the new role depends on and records the answer, and it is
# deliberately not a general sweep: a check on an interface this milestone does not consume would
# be a check nothing keeps honest.
# The message names what failed and quotes what it said, and does **not** name the binary's path.
# `$BATON_CLAUDE` is a seam whose value is the machine's, so a message carrying it is a message that
# differs between one checkout and another — which is a location-dependent person-facing string, and
# an expectation that pins it fails the moment the suite is run somewhere else. No other message in
# Baton names it, and this one does not either.
onboard_cli_shape() {
  if ! ocs_v=$("$BATON_CLAUDE" --version 2>&1); then
    jq -nc --arg d "the Claude CLI would not answer --version, so the judgment request cannot be made against a binary Baton could not interrogate: $ocs_v" \
      '{version: "", ok: false, detail: $d}'
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
    head -"$ONBOARD_EVIDENCE_LINES" "$oe_c/$oe_f"
    printf '\n'
  done
  if [ -n "$oe_plan" ] && [ -f "$oe_c/$oe_plan" ]; then
    printf '%s\n' "--- $oe_plan, the milestone table header and rows ---"
    grep -E '^[[:space:]]*\|' "$oe_c/$oe_plan" | head -"$ONBOARD_EVIDENCE_ROWS"
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

  # Under `checks/`, which is Baton's own scratch for work it runs on a project's behalf, already
  # denied to sessions by name and already documented as a place Baton writes and clears.
  #
  # One directory and no pid in its name. The verb holds the lock, so only one judgment request can be
  # running at a time; whatever is there is an orphan of one that was killed, and removing it first is
  # therefore an exact sweep rather than a guess at an age — unlike `install.sh`'s stages, where two
  # close-outs can race and a wildcard cannot tell an orphan from a live one. A pid in the path would
  # also put a number that changes every run into the settings path the CLI is called with, which is a
  # line a fixture records and cannot pin.
  oj_dir=$BATON_HOME/checks/judge
  rm -rf "$oj_dir"
  mkdir -p "$oj_dir" || { echo "$oj_dir is not a directory Baton can write"; return 1; }
  oj_out=$oj_dir/answer.txt

  # The request runs behind the same deny rules a dispatched session does. Every other `claude` Baton
  # starts carries the rail in its settings file, and this is the one invocation that would not: print
  # mode has tool access, the prompt body is a repository's own README and `CLAUDE.md`, and the rail's
  # whole value is that it is per-invocation rather than a property of the account. The allow list is
  # empty because nothing is being asked for; the deny list is the rail.
  jq -n --argjson d "$(permissions_deny_rules)" \
    '{permissions: {defaultMode: "bypassPermissions", allow: [], deny: $d}}' > "$oj_dir/settings.json"
  # The same three-part idiom `completion_check_run` uses, for the same three reasons.
  #
  # `set +e` inside the subshell, which inherits this file's `set -e`: a request that exits non-zero
  # would otherwise kill the subshell at that command, the marker would never appear, and the poll
  # would run to the deadline and report a refusal Baton could have quoted as a request that never
  # answered — the one case this exists to distinguish, read as the other one.
  #
  # `< /dev/null`, because the person's yes is waiting on this process's stdin. A child that read it
  # would leave `onboard_confirm` at end-of-file, which it reads as a no, and the answer a person
  # typed would be spent on the request that came before the question.
  #
  # The subshell's own stderr goes nowhere, and only the subshell's — the request's own streams are
  # redirected inside it, before this applies. What is discarded is the shell's job-control notice
  # when it reaps a child the deadline killed, which is the shell's bookkeeping rather than the
  # request's output and whose appearance depends on the timing of the kill (D-152).
  # `cd` into the target, as `dispatch_one` does for a session: the CLI reads the project context of
  # the directory it starts in, and starting it in whatever directory the person happened to type the
  # verb from would hand it that project's instructions to read a different project by.
  ( set +e
    cd "$oj_c" || exit 127
    "$BATON_CLAUDE" -p --settings "$oj_dir/settings.json" "$oj_ask" < /dev/null > "$oj_out" 2>"$oj_dir/err.txt"
    printf '%s\n' "$?" > "$oj_dir/exit.tmp" && mv "$oj_dir/exit.tmp" "$oj_dir/exit" ) 2>/dev/null &
  oj_pid=$!
  oj_spent=0
  oj_timedout=no
  while [ ! -f "$oj_dir/exit" ]; do
    if [ "$oj_spent" -ge "$ONBOARD_JUDGE_DEADLINE" ]; then oj_timedout=yes; break; fi
    sleep 1
    oj_spent=$((oj_spent + 1))
  done
  if [ "$oj_timedout" = yes ]; then
    # Children first and then the subshell, never a negative pid: `$!` is not a process-group leader
    # in a shell without job control, so `kill -- -$!` names a group this process does not own and
    # could reach something that has nothing to do with the request.
    pkill -TERM -P "$oj_pid" 2>/dev/null || true
    kill -TERM "$oj_pid" 2>/dev/null || true
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
# The brief pointer is the contract's path, `docs/milestones/<ID>.md`, and not one derived from where
# the plan was found. It is what `dispatch_one` constructs whatever a pointer says — `01-findings.md`
# finding 3 records that the two are not yet unified, and unifying them is not this milestone's — so a
# pointer at any other path would be a pointer Baton will not read, and a brief the precondition report
# calls present while the dispatch calls it missing. Where a project files its briefs elsewhere, the
# report names the contract's path as the one that is missing, which is the truth about it.
onboard_start() {
  os_key=$1; os_plan=$2; os_tables=$3
  printf '%s' "$os_tables" | jq -c --arg d "docs/milestones" '
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
# The allow rules a person earned are kept. `baton allow` writes a typed rule into this same file and
# records a `widening` event as its provenance (REQ-PERM-02, REQ-ESC-09), so rebuilding the list from
# the detected toolchain alone would delete each of those on the second `baton onboard` — silently,
# while the live settings file still carried it and `baton plan`'s widening list still said the
# allowlist had grown. The derived rules come first so the order stays `install.sh`'s, and the earned
# ones follow in the order they were written.
#
# One `jq`, not two in a pipeline: a pipeline's status is its last command's, so a first `jq` that
# failed would be masked and an empty file would be published over a rail that was there.
onboard_permissions_write() {
  opw_f=$BATON_HOME/projects/$1/permissions.json
  opw_have=$(jq -c '.permissions.allow // []' "$opw_f" 2>/dev/null) || opw_have='[]'
  [ -n "$opw_have" ] || opw_have='[]'
  jq -n --argjson a "$2" --argjson had "$opw_have" --argjson d "$(permissions_deny_rules)" \
    '{permissions: {allow: ($a + [$had[] | select(. as $r | $a | index($r) | not)]), deny: $d}}' \
    > "$opw_f.tmp"
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
  orp_plan_format=$(printf '%s' "$orp_doc" | jq -r '.plan_format // ""')
  orp_start=$(printf '%s' "$orp_doc" | jq -c '.start.eligible // []')
  if [ "$(printf '%s' "$orp_start" | jq length)" -eq 0 ]; then
    render_row out record '  starting    the plan makes nothing eligible yet\n'
  else
    printf '%s' "$orp_start" | jq -r '.[] | "  starting    \(.milestone) · \(.disposition)\(if .wait_for then " for " + (.wait_for | join(", ")) else "" end)\(if .held_by then " by \"" + .held_by + "\"" else "" end) · \(.brief.path)"' \
      | while IFS= read -r orp_line; do render_row out record '%s\n' "$orp_line"; done
  fi

  # What the project still needs before the milestones above can be dispatched, through the pass
  # `baton plan` already prints. This is where a brief that carries no fenced kickoff prompt, or a
  # `CLAUDE.md` with no close-out instructions for its sessions, is named with its repair: Baton can
  # read a plan it did not author, but it cannot write a milestone's brief, and the honest thing to do
  # about contract material that is missing is to say which and where rather than to invent it. Its
  # status is not the verb's: a project with unmet preconditions is still registered, and the person
  # has been told what to fix.
  [ "$orp_plan_format" != generated ] || return 0
  # No `2>/dev/null`: `plan_of_project` returns its refusal as its own detail on stdout (D-030), so
  # what the `else` branch prints is the sentence, and anything that did reach stderr would be a
  # surprise worth seeing rather than one worth hiding.
  if orp_tables=$(plan_of_project "$orp_key"); then
    plan_preconditions_report "$orp_key" "$orp_tables" out || true
  else
    render_row out action '  plan        %s\n' "$orp_tables"
  fi
}


# onboard_classify <checkout> <plan rel>: how the plan can be read, as `{plan_format, adaptation,
# tables, detail}` — `native`, `adapted`, `unmapped`, or `generated` with no tables at all.
#
# `detail` carries the reader's own refusal where a plan was found and cannot be read even with
# defaults, because the reader names the cell and "no usable plan" does not. It is **returned and not
# printed**: a helper that printed as it went would be writing into the result its caller captures,
# which is the same rule `render_lines` exists for, and the first thing it costs is every `jq` the
# caller then runs on that result.
#
# Strictly first. A plan that parses under the contract's own rules is `native` and is read as
# strictly for ever after, so a misspelt cell in it still parks rather than silently defaulting.
# A `Status` word Baton will not map refuses the whole classification with the word named: that is
# the line between plan input that is not usable and a usable plan needing adaptation, and guessing
# at the word is how tolerance erases intent.
onboard_classify() {
  ocl_c=$1; ocl_plan=${2:-}
  if [ -z "$ocl_plan" ]; then
    jq -nc '{plan_format: "generated", adaptation: {}, tables: null}'
    return 0
  fi
  if ocl_tables=$(plan_tables "$ocl_c/$ocl_plan" 2>/dev/null); then
    jq -nc --argjson t "$ocl_tables" '{plan_format: "native", adaptation: {}, tables: $t}'
    return 0
  fi
  ocl_adapt=$(onboard_adaptation "$ocl_c/$ocl_plan") || ocl_adapt='{}'
  ocl_unmapped=$(printf '%s' "$ocl_adapt" | jq -r '(.unmapped // []) | join(", ")')
  if [ -n "$ocl_unmapped" ]; then
    jq -nc --arg u "$ocl_unmapped" '{plan_format: "unmapped", adaptation: {}, tables: null, unmapped: $u}'
    return 0
  fi
  if ocl_tables=$(plan_tables "$ocl_c/$ocl_plan" '' "$ocl_adapt" 2>/dev/null); then
    jq -nc --argjson t "$ocl_tables" --argjson a "$ocl_adapt" \
      '{plan_format: "adapted", adaptation: ($a | del(.unmapped)), tables: $t}'
    return 0
  fi
  ocl_why=$(printf '%s' "$ocl_tables" | jq -r '"the \(.table) table, row \(.row), cell \(.cell): \(.detail)"' 2>/dev/null) \
    || ocl_why='no milestone table was found'
  [ -n "$ocl_why" ] || ocl_why='no milestone table was found'
  jq -nc --arg p "$ocl_plan" --arg why "$ocl_why" \
    '{plan_format: "generated", adaptation: {}, tables: null,
      detail: "\($p) does not parse even with defaults: \($why)"}'
}

# onboard_commit <key> <checkout> <plan rel> <toolchain json> <intent json> <classification json>
# <cli json> <seed: yes|no>: everything the confirmation authorises, written once.
#
# One function for both the first onboarding and a later run, because the write order matters and an
# order that exists twice is an order that will differ from itself. It is:
#
#   1. the rail, because an allowlist without a registration is inert while a registration whose rail
#      is missing fails the `settings` stage at the next dispatch;
#   2. the registration, which is the state and is what makes the project real to the tick;
#   3. the event, guarded, because `log_event` refuses a line of 4 KB or more and a refused line must
#      not abort a verb whose work is done. `onboarded_at` carries the when either way.
#
# The document is built by merging onto whatever is already there. F11 is the reason: `install.sh`
# wrote `{path, plan}` only when the file was absent, so a registration that predates the intent
# record can never gain one by reinstalling, and a migration that replaced the file would take a
# `check.command` a person had set by hand with it.
onboard_commit() {
  oc_key=$1; oc_checkout=$2; oc_plan=$3; oc_tool=$4; oc_intent=$5; oc_class=$6; oc_cli=$7; oc_seed=$8
  oc_f=$BATON_HOME/projects/$oc_key/project.json
  oc_now=$(baton_now)
  oc_fmt=$(printf '%s' "$oc_class" | jq -r .plan_format)
  oc_start='[]'
  if [ "$oc_seed" = yes ]; then
    oc_start=$(onboard_start "$oc_key" "$oc_plan" "$(printf '%s' "$oc_class" | jq -c .tables)")
  fi
  oc_base='{}'
  [ ! -f "$oc_f" ] || oc_base=$(jq -c . "$oc_f" 2>/dev/null) || oc_base='{}'
  mkdir -p "$BATON_HOME/projects/$oc_key"
  oc_doc=$(jq -nc --argjson base "$oc_base" --arg p "$oc_checkout" --arg plan "$oc_plan" \
    --arg fmt "$oc_fmt" --arg at "$oc_now" --arg seed "$oc_seed" \
    --arg detail "$(printf '%s' "$oc_class" | jq -r '.detail // ""')" \
    --argjson check "$(printf '%s' "$oc_tool" | jq -c '.check // {}')" \
    --argjson intent "$oc_intent" --argjson adapt "$(printf '%s' "$oc_class" | jq -c .adaptation)" \
    --argjson start "$oc_start" --argjson cli "$oc_cli" '
    $base
    + {path: $p}
    # The plan pointer names the file that actually holds the table, which is the registered one
    # wherever that still holds it — `onboard_plan_find` tries it first for exactly that reason. It is
    # a pointer and not progress: progress is the `Status` cells and the archive, and pointing at a
    # file that no longer has a table is the one repair a later run must make.
    + (if $plan != "" then {plan: $plan} else {} end)
    # The standing check is the exception, because a person who changed the command meant it (D-147).
    + (if (($base.check.command // "") == "") and (($check.command // "") != "")
       then {check: $check} else {} end)
    + {goal: $intent.goal, done: $intent.done,
       constraints: $intent.constraints, non_goals: $intent.non_goals,
       plan_format: $fmt, onboarded_at: ($base.onboarded_at // $at)}
    + (if ($cli.version // "") != "" then {cli: {version: $cli.version, checked_at: $at}} else {} end)
    # The adaptation is replaced whole for an `adapted` plan and removed for any other, because it is
    # a statement about one file read one way: carrying yesterday'"'"'s defaults onto a plan that has since
    # gained its `Model` column would be applying a permission nothing asked for any more.
    + (if $fmt == "adapted" then {adaptation: $adapt} else {} end)
    | (if $fmt == "adapted" then . else del(.adaptation) end)
    # `plan_owed` is the record M12 reads, and it goes when a plan arrives. Where a plan was found and
    # would not parse, the reason is the one the reader gave: "no readable milestone table was found"
    # would send the generator looking for a file that is right there.
    | (if $fmt == "generated"
       then .plan_owed = {reason: (if $detail == "" then "no readable milestone table was found in the repository"
                                   else $detail end),
                          owner: "M12"}
       else del(.plan_owed) end)
    # The seed is written once. A registration that already has one keeps it: the archive and the
    # handovers carry the current word, and putting a fresh seed in front of them would be Baton
    # deciding again what a session has since decided.
    | (if $seed == "yes" then .start = {at: $at, eligible: $start} else . end)')
  onboard_permissions_write "$oc_key" "$(printf '%s' "$oc_tool" | jq -c .allow)"
  onboard_registration_write "$oc_key" "$oc_doc"
  # The event records the act, so it is written when there was one: the first onboarding of a project,
  # whether or not it had a plan to seed from, and a later run that gave the registration a starting
  # handover it did not have. A run that changed nothing material writes none, which is what "no
  # second `onboarded` event" means. "First" is the absence of a confirmed goal in what was there
  # before, which is the same test the verb uses to decide whether to ask.
  oc_first=no
  printf '%s' "$oc_base" | jq -e '(.goal // "") != ""' > /dev/null 2>&1 || oc_first=yes
  [ "$oc_first" = yes ] || [ "$oc_seed" = yes ] || return 0
  log_event onboarded "$oc_key" "" "" "" "$(jq -nc --arg c "$oc_checkout" --arg plan "$oc_plan" \
    --arg fmt "$oc_fmt" --argjson tool "$(printf '%s' "$oc_tool" | jq -c '.toolchain // []')" \
    --arg check "$(printf '%s' "$oc_tool" | jq -r '.check.command // ""')" \
    --arg cli "$(printf '%s' "$oc_cli" | jq -r '.version // ""')" \
    --argjson start "$(printf '%s' "$oc_start" | jq -c '[.[] | .milestone]')" '
    {checkout: $c, plan_format: $fmt, toolchain: $tool, start: $start}
    + (if $plan == "" then {} else {plan: $plan} end)
    + (if $check == "" then {} else {check: $check} end)
    + (if $cli == "" then {} else {cli_version: $cli} end)')" \
    || render_failure err "baton: $oc_key is registered, but the onboarded event could not be written"
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
  vo_class=$(onboard_classify "$vo_checkout" "$vo_plan")
  vo_format=$(printf '%s' "$vo_class" | jq -r .plan_format)
  # The reader's refusal, where there was one: rendered here, where the stream is known, and not by
  # the helper whose result this is.
  vo_detail=$(printf '%s' "$vo_class" | jq -r '.detail // ""')
  [ -z "$vo_detail" ] || render_row out record '  plan        %s\n' "$vo_detail"

  if [ "$vo_format" = unmapped ]; then
    render_failure err "baton: $vo_plan has Status values Baton cannot map to done, held or blank: $(printf '%s' "$vo_class" | jq -r .unmapped)" \
      "map them in that column by hand, or onboard again once the plan says done, held or blank"
    exit 1
  fi

  # A registration that already carries a confirmed goal is never asked again — the Recovery
  # procedure says so, and it is what makes a second run of the verb safe. It is still *read* again,
  # because the repository may have moved on: a project onboarded before it had a plan gains one, and
  # a plan that grew a `Model` column stops needing the default. What is not repeated is the
  # judgement and the question, and what is not overwritten is a starting handover that already
  # exists — a registration with a `start` has had its word superseded by whatever has happened
  # since, and putting a fresh seed in front of that would be Baton deciding again.
  if [ -f "$vo_f" ] && [ -n "$(jq -r '.goal // ""' "$vo_f" 2>/dev/null || true)" ]; then
    vo_intent=$(jq -c '{goal: (.goal // ""), done: (.done // ""),
                        constraints: (.constraints // []), non_goals: (.non_goals // [])}' "$vo_f") \
      || { render_failure err "baton: $vo_f does not parse"; exit 1; }
    vo_seed=no
    if [ "$vo_format" != generated ] && ! jq -e '(.start.eligible | type) == "array"' "$vo_f" > /dev/null 2>&1; then
      vo_seed=yes
    fi
    onboard_commit "$vo_key" "$vo_checkout" "$vo_plan" "$vo_tool" "$vo_intent" "$vo_class" \
      "$(jq -nc --arg v "$(jq -r '.cli.version // ""' "$vo_f" 2>/dev/null || true)" '{version: $v}')" "$vo_seed"
    if [ "$vo_seed" = yes ]; then
      render_heading out '%s was already onboarded and had no starting handover · its plan reads %s now, and the milestones it makes eligible are seeded\n' \
        "$vo_key" "$vo_format"
    else
      render_heading out '%s is already onboarded · the confirmed goal stands, nothing was asked again and nothing was seeded twice\n' "$vo_key"
    fi
    onboard_report "$vo_key" "$(jq -c . "$vo_f")" registered
    return 0
  fi

  vo_shape=$(onboard_cli_shape)
  if ! printf '%s' "$vo_shape" | jq -e .ok > /dev/null; then
    render_failure err "baton: $(printf '%s' "$vo_shape" | jq -r .detail)"
    exit 1
  fi

  vo_intent=$(onboard_judge "$vo_checkout" "$vo_plan" "$vo_tool") \
    || { render_failure err "baton: $vo_intent"; exit 1; }

  vo_lines=$(onboard_intent_lines "$vo_key" "$vo_checkout" "$vo_intent" "$vo_format" "$vo_tool")
  if ! onboard_confirm "$vo_lines"; then
    render_failure out "baton: not confirmed, so $vo_key is not registered and nothing is dispatched" \
      "run baton onboard $vo_checkout again when the statement above is right"
    exit 1
  fi

  # A repository with no plan Baton can read is neither a failure nor a successful adaptation, and
  # presenting it as the second would be the worst of the three: the chain would run against a graph
  # nobody wrote. The confirmed goal is stored — it is the input M12's generator needs — and
  # `plan_format` reads `generated` with `plan_owed` beside it. Nothing is seeded, because there is no
  # milestone to name, and generation itself is M12's and is not attempted here.
  if [ "$vo_format" = generated ]; then
    onboard_commit "$vo_key" "$vo_checkout" "$vo_plan" "$vo_tool" "$vo_intent" "$vo_class" "$vo_shape" no
    render_heading out 'onboarded %s with no usable plan\n' "$vo_key"
    render_row out record '  checkout    %s\n' "$(render_token out path "$vo_checkout")"
    render_row out record '  goal        %s\n' "$(printf '%s' "$vo_intent" | jq -r .goal)"
    render_row out record '  plan        none readable; plan_format is generated and the plan is owed\n'
    render_row out action '  next        the next tick dispatches the session that writes the plan from the confirmed goal\n'
    return 0
  fi

  onboard_commit "$vo_key" "$vo_checkout" "$vo_plan" "$vo_tool" "$vo_intent" "$vo_class" "$vo_shape" yes
  onboard_report "$vo_key" "$(jq -c . "$vo_f")"
  render_heading out 'the next tick reads %s and dispatches what the starting handover says run\n' "$vo_key"
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
