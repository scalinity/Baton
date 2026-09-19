#!/bin/sh
# lib/plan.sh — the plan-file reader. Locates the milestone table by its ID header cell and the
# gates table by its Gate header cell, wherever they sit; reads columns by name; parses tokens.
# A cell that does not parse fails the whole read with the table, row and cell named; the caller
# decides what that means. Also the plan verb.
set -eu

plan_us=$(printf '\037')

# plan_fail <table> <row> <cell> <detail>: the failure, as one JSON object on stdout, status 1.
# Callers render it (baton plan) or carry it whole into an event (the self-check, M03).
plan_fail() {
  jq -nc --arg t "$1" --arg r "$2" --arg c "$3" --arg d "$4" \
    '{error: "plan-unparseable", table: $t, row: $r, cell: $c, detail: $d}'
  return 1
}

# plan_extract <file> [<optional columns, comma-separated>]: the awk pass. One line per body row,
# fields on \037:
#   M <row> <ID> <Depends on> <Model> <Effort> <Remote> <Status>
#   G <row> <Gate> <Holds> <Cleared>
#   T <table>                      the table was found
#   E <table> <row> <cell> <detail> a structural failure: a required column missing, a row short
# Extra columns are ignored; \| inside a cell is an escaped pipe; a row without a trailing pipe
# still counts its last part as a cell; a body row with fewer cells than the header fails; the
# first table with each header cell wins.
#
# A column named in the second argument may be absent from the header, and a row's value for it is
# then empty — which `plan_tables` reads as "take the registered default" and nothing else reads at
# all. `ID` and `Depends on` are never optional whatever is passed, because a plan without them is
# not a graph: there is nothing to default an identity or an edge to.
plan_extract() {
  awk -v OFS="$plan_us" -v optional="${2:-}" '
    function optional_col(name,    i, o, n) {
      if (name == "ID" || name == "Depends on") return 0
      n = split(optional, o, ",")
      for (i = 1; i <= n; i++) if (o[i] == name) return 1
      return 0
    }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function cells(line,    n, i, c, parts) {
      split("", C)
      gsub(/\\\|/, "\001", line)
      n = split(line, parts, "|")
      if (trim(parts[n]) != "") n++
      nc = 0
      for (i = 2; i < n; i++) { c = trim(parts[i]); gsub(/\001/, "|", c); C[++nc] = c }
      return nc
    }
    # The table is located **by** its header cell and not by that cell being first, which is what
    # REQ-PLAN-01 says and what a plan Baton did not author needs: a project whose own table opens
    # with `Owner` or `Title` has an `ID` column all the same, and reading columns by name is
    # pointless if finding the table does not.
    function has_cell(name,    i) {
      for (i = 1; i <= nc; i++) if (C[i] == name) return 1
      return 0
    }
    function header(table, names,    k, i, want) {
      split("", col)
      for (i = 1; i <= nc; i++) col[C[i]] = i
      k = split(names, want, ",")
      for (i = 1; i <= k; i++) if (!(want[i] in col) && !optional_col(want[i])) {
        print "E", table, "header", want[i], "column \"" want[i] "\" is missing from the header"
        exit 0
      }
      need[table] = nc
      print "T", table
    }
    /^[ \t]*\|/ {
      cells($0)
      if (state == "") {
        if (has_cell("ID") && !seen_m) { seen_m = 1; header("milestones", "ID,Depends on,Model,Effort,Remote,Status"); state = "m-sep"; next }
        if (has_cell("Gate") && !seen_g) { seen_g = 1; header("gates", "Gate,Holds,Cleared"); state = "g-sep"; next }
        next
      }
      if (state == "m-sep") { state = "m"; row = 0; next }
      if (state == "g-sep") { state = "g"; row = 0; next }
      row++
      table = (state == "m") ? "milestones" : "gates"
      if (nc < need[table]) {
        print "E", table, (C[1] != "" ? C[1] : "#" row), "-", "the row has " nc " cells and the header has " need[table]
        exit 0
      }
      if (state == "m") print "M", row, C[col["ID"]], C[col["Depends on"]], C[col["Model"]], C[col["Effort"]], C[col["Remote"]], C[col["Status"]]
      if (state == "g") print "G", row, C[col["Gate"]], C[col["Holds"]], C[col["Cleared"]]
      next
    }
    { state = "" }
  ' "$1"
}

# plan_adaptation <project>: the adaptation the project is registered with, as the document
# `lib/onboard.sh` writes — `{defaults, status_map, gates}` — or `{}` for a project registered
# without one.
#
# A project registered `native` has no adaptation and is therefore read exactly as strictly as
# before: a misspelt `Model` cell in Baton's own plan still parks the project rather than quietly
# taking a default. Tolerance is a thing a person confirmed once, per project, not a property of the
# reader (SCOPE §6 M11's "tolerance can erase intent").
plan_adaptation() {
  [ -n "${1:-}" ] || { echo '{}'; return 0; }
  pa_pj=$BATON_HOME/projects/$1/project.json
  [ -f "$pa_pj" ] || { echo '{}'; return 0; }
  jq -c '.adaptation // {}' "$pa_pj" 2>/dev/null || echo '{}'
}

# parse_id <token>: an id is M followed by digits, with an optional -suffix (M01-b).
parse_id() {
  printf '%s' "$1" | grep -Eq '^M[0-9]+(-[a-z0-9]+)?$' || return 1
  printf '%s\n' "$1"
}

# parse_depends <cell>: ids and ranges (M05, M06; M01–M13 with an en dash or a hyphen) or – for
# none. Prints the expanded ids, one per line. A token that is neither fails.
parse_depends() {
  pd_cell=$(printf '%s' "$1" | sed 's/–/-/g; s/,/ /g')
  case "$pd_cell" in
    -|—) return 0 ;;
    '') return 1 ;;
  esac
  set -f
  for pd_tok in $pd_cell; do
    if printf '%s' "$pd_tok" | grep -Eq '^M[0-9]+-M[0-9]+$'; then
      pd_lo=${pd_tok%-M*}; pd_lo=${pd_lo#M}
      pd_hi=${pd_tok#*-M}
      pd_width=${#pd_lo}
      pd_lo=$(printf '%s' "$pd_lo" | sed 's/^0*//'); pd_lo=${pd_lo:-0}
      pd_hi=$(printf '%s' "$pd_hi" | sed 's/^0*//'); pd_hi=${pd_hi:-0}
      [ "$pd_lo" -le "$pd_hi" ] || { set +f; return 1; }
      pd_i=$pd_lo
      while [ "$pd_i" -le "$pd_hi" ]; do
        printf "M%0${pd_width}d\n" "$pd_i"
        pd_i=$((pd_i + 1))
      done
    else
      parse_id "$pd_tok" || { set +f; return 1; }
    fi
  done
  set +f
}

# parse_model <cell> <models json>: an alias from config.json's models (printed as its value) or a
# full model id (claude-…, printed as given).
parse_model() {
  pm_val=$(printf '%s' "$2" | jq -r --arg a "$1" '.[$a] // empty')
  if [ -n "$pm_val" ]; then printf '%s\n' "$pm_val"; return 0; fi
  printf '%s' "$1" | grep -Eq '^claude-[a-z0-9.-]+$' || return 1
  printf '%s\n' "$1"
}

# parse_effort <cell>: blank or one of the five levels.
parse_effort() {
  case "$1" in ''|low|medium|high|xhigh|max) printf '%s\n' "$1" ;; *) return 1 ;; esac
}

# parse_remote <cell>: blank (false) or yes (true).
parse_remote() {
  case "$1" in '') echo false ;; yes) echo true ;; *) return 1 ;; esac
}

# parse_status <cell> [<status map json>]: blank, done or held — or, for a project registered with a
# status map, one of that map's source words read as the native token it stands for.
#
# The native vocabulary is three words and cannot say "retired", so a richer source vocabulary needs
# the map rather than a wider enum: a word the map does not name still fails, because a status
# guessed at is how tolerance erases intent. What the map may not do is make retired work runnable
# or let it satisfy a dependency, and it cannot: `held` and blank are the only non-`done` tokens it
# can produce, and `plan_eligible` and the `$done` set both key on the native word (SCOPE §6 M11).
parse_status() {
  case "$1" in ''|done|held) printf '%s\n' "$1"; return 0 ;; esac
  [ -n "${2:-}" ] || return 1
  ps_mapped=$(printf '%s' "$2" | jq -r --arg t "$1" '
    (.[$t] // .[$t | ascii_downcase] // empty) | if type == "object" then .status else . end' 2>/dev/null) || return 1
  case "$ps_mapped" in ''|done|held) ;; *) return 1 ;; esac
  printf '%s' "$2" | jq -e --arg t "$1" 'has($t) or has($t | ascii_downcase)' > /dev/null 2>&1 || return 1
  printf '%s\n' "$ps_mapped"
}

# parse_cleared <cell>: blank or a D-number.
parse_cleared() {
  case "$1" in '') echo ;; *) printf '%s' "$1" | grep -Eq '^D-[0-9]+$' || return 1; printf '%s\n' "$1" ;; esac
}

# plan_default <defaults json> <column> <cell>: the cell, or the column's registered default where
# the cell is empty and the column has one. A column with no default is returned untouched, so a
# blank `Effort` in a plan that really has an `Effort` column stays the blank the person wrote.
plan_default() {
  [ -z "$3" ] || { printf '%s' "$3"; return 0; }
  printf '%s' "$1" | jq -r --arg c "$2" 'if has($c) then .[$c] else "" end' 2>/dev/null || printf ''
}

# ids_json: lines of ids on stdin to a JSON array.
ids_json() {
  jq -Rn '[inputs | select(length > 0)]' | jq -c .
}

# plan_tables <file> [<project>] [<adaptation json>]: the parsed plan as one JSON document,
#   {"milestones": [{row, id, depends[], model, effort, remote, status}], "gates": [{row, gate, holds[], cleared}]}
# or, on the first cell that does not parse, plan_fail's object with status 1.
#
# With neither optional argument the read is the strict one the contract describes, and that is what
# every caller got before onboarding existed. A project key makes it read that project's registered
# adaptation; an explicit adaptation document is for onboarding itself, which has to know whether a
# plan is readable *before* there is a registration to read it from.
#
# The adaptation does three things and no more: it makes the columns it names optional and supplies
# their value where the column is absent or its cell is empty; it lets `Status` carry a source
# vocabulary through its map; and it says whether the plan has a gates table at all. Everything else
# — the ids, the edges, every cell that is present and not blank — is parsed exactly as strictly as
# before, so tolerance cannot turn a person's prose into a token.
plan_tables() {
  pt_models=$(jq -c '.models // {}' "$BATON_HOME/config.json" 2>/dev/null || echo '{}')
  pt_adapt=${3:-}
  [ -n "$pt_adapt" ] || pt_adapt=$(plan_adaptation "${2:-}")
  pt_defaults=$(printf '%s' "$pt_adapt" | jq -c '.defaults // {}' 2>/dev/null) || pt_defaults='{}'
  pt_map=$(printf '%s' "$pt_adapt" | jq -c '.status_map // {}' 2>/dev/null) || pt_map='{}'
  pt_gates_optional=$(printf '%s' "$pt_adapt" | jq -r 'if (.gates // "") == "absent" then "yes" else "no" end' 2>/dev/null) || pt_gates_optional=no
  pt_optional=$(printf '%s' "$pt_defaults" | jq -r 'keys_unsorted | join(",")')
  pt_raw=$(plan_extract "$1" "$pt_optional")
  pt_ms='[]'; pt_gs='[]'; pt_seen_m=no; pt_seen_g=no
  while IFS="$plan_us" read -r pt_k pt_a pt_b pt_c pt_d pt_e pt_f pt_g; do
    case "$pt_k" in
      T) [ "$pt_a" = milestones ] && pt_seen_m=yes; [ "$pt_a" = gates ] && pt_seen_g=yes ;;
      E) plan_fail "$pt_a" "$pt_b" "$pt_c" "$pt_d"; return 1 ;;
      M)
        pt_rowname=${pt_b:-"#$pt_a"}
        parse_id "$pt_b" >/dev/null || { plan_fail milestones "$pt_rowname" ID "\"$pt_b\" is not a milestone id"; return 1; }
        pt_dep=$(parse_depends "$pt_c") || { plan_fail milestones "$pt_rowname" "Depends on" "\"$pt_c\" is not ids, ranges or – for none"; return 1; }
        pt_dep=$(printf '%s\n' "$pt_dep" | ids_json)
        # An empty cell in a defaulted column takes the default, which is the same answer an absent
        # column gets: the two are one omission wearing two hats — a plan with no `Model` column and
        # a plan whose `Model` column is blank on some rows are both L1's recorded symptom.
        pt_d=$(plan_default "$pt_defaults" Model "$pt_d")
        pt_e=$(plan_default "$pt_defaults" Effort "$pt_e")
        pt_f=$(plan_default "$pt_defaults" Remote "$pt_f")
        pt_g=$(plan_default "$pt_defaults" Status "$pt_g")
        pt_model=$(parse_model "$pt_d" "$pt_models") || { plan_fail milestones "$pt_rowname" Model "\"$pt_d\" is not a model alias in config.json or a full model id"; return 1; }
        pt_effort=$(parse_effort "$pt_e") || { plan_fail milestones "$pt_rowname" Effort "\"$pt_e\" is not blank or low|medium|high|xhigh|max"; return 1; }
        pt_remote=$(parse_remote "$pt_f") || { plan_fail milestones "$pt_rowname" Remote "\"$pt_f\" is not blank or yes"; return 1; }
        pt_status=$(parse_status "$pt_g" "$pt_map") \
          || { plan_fail milestones "$pt_rowname" Status "\"$pt_g\" is not blank, done or held, and the project's registered status map does not name it"; return 1; }
        printf '%s' "$pt_ms" | jq -e --arg id "$pt_b" 'any(.[]; .id == $id) | not' > /dev/null \
          || { plan_fail milestones "$pt_rowname" ID "\"$pt_b\" appears twice"; return 1; }
        pt_ms=$(printf '%s' "$pt_ms" | jq -c --arg row "$pt_a" --arg id "$pt_b" --argjson dep "$pt_dep" \
          --arg model "$pt_model" --arg effort "$pt_effort" --argjson remote "$pt_remote" --arg status "$pt_status" \
          '. + [{row: ($row | tonumber), id: $id, depends: $dep, model: $model, effort: $effort, remote: $remote, status: $status}]')
        ;;
      G)
        pt_rowname=${pt_b:-"#$pt_a"}
        [ -n "$pt_b" ] || { plan_fail gates "$pt_rowname" Gate "the gate has no name"; return 1; }
        pt_holds=$(parse_depends "$pt_c") || { plan_fail gates "$pt_rowname" Holds "\"$pt_c\" is not ids, ranges or – for none"; return 1; }
        pt_holds=$(printf '%s\n' "$pt_holds" | ids_json)
        pt_cleared=$(parse_cleared "$pt_d") || { plan_fail gates "$pt_rowname" Cleared "\"$pt_d\" is not blank or a D-number"; return 1; }
        pt_gs=$(printf '%s' "$pt_gs" | jq -c --arg row "$pt_a" --arg gate "$pt_b" --argjson holds "$pt_holds" --arg cleared "$pt_cleared" \
          '. + [{row: ($row | tonumber), gate: $gate, holds: $holds, cleared: $cleared}]')
        ;;
    esac
  done <<RAW
$pt_raw
RAW
  [ "$pt_seen_m" = yes ] || { plan_fail milestones - ID "no table has an ID header cell"; return 1; }
  # A plan with no gates table is an ordinary plan: a gate is a hold a person adds when they want
  # one, and most projects never do. It is tolerated only where the registration says the plan has
  # none, so a gates table that disappears from a project that had one still stops dispatch.
  if [ "$pt_seen_g" != yes ] && [ "$pt_gates_optional" != yes ]; then
    plan_fail gates - Gate "no table has a Gate header cell"; return 1
  fi
  jq -nc --argjson m "$pt_ms" --argjson g "$pt_gs" '{milestones: $m, gates: $g}'
}

# The readers below take plan_tables' document on stdin.
plan_row() { jq -ce --arg id "$1" '.milestones[] | select(.id == $id)'; }

# plan_eligible: ids whose dependencies all read done, whose Status is blank, and which no
# uncleared gate holds. One per line, in row order.
plan_eligible() {
  jq -r '
    (.milestones | map(select(.status == "done") | .id)) as $done
    | ([.gates[] | select(.cleared == "") | .holds[]]) as $held
    | .milestones[]
    | select(.status == "" and ((.id as $i | $held | index($i)) | not)
             and all(.depends[]; . as $d | ($done | index($d)) != null))
    | .id'
}

# plan_render <project> <inflight json> [<out|err>]: the graph, one line per milestone, on stdin.
#
# The third argument is how a caller says the lines are going to a terminal. Without it the rows
# are printed plain, because this function has a machine caller as well as a person's: the
# ineligible-dispatch refusal pipes it through `awk '$1 == id'` to show the one row it refused, and
# a first field carrying colour would match nothing (D-050 is the same shape, found in the CLI's
# own output). Nothing here asks the terminal for itself; only the caller knows which use this is.
plan_render() {
  pr_stream=${3:-}
  pr_rows=$(jq -c --argjson inflight "$2" '
    ($inflight | map(.milestone)) as $flying
    | (.milestones | map(select(.status == "done") | .id)) as $done
    | (.gates | map(select(.cleared == ""))) as $open
    | [ .milestones[]
    | .id as $i
    | ( if .status == "done" then "done"
        elif ($flying | index($i)) != null then "in flight"
        elif .status == "held" then "held"
        elif ([$open[] | select(.holds | index($i) != null) | .gate] | length) > 0
          then "held by gate \"" + ([$open[] | select(.holds | index($i) != null) | .gate] | join("\", \"")) + "\""
        elif all(.depends[]; . as $d | ($done | index($d)) != null) then "eligible"
        else "waits on " + ([.depends[] | select(. as $d | ($done | index($d)) == null)] | join(", "))
        end ) as $state
    | {id: .id, state: $state, model: .model,
       effort: (if .effort == "" then "-" else .effort end),
       remote: (if .remote then "yes" else "no" end)} ]')
  pr_n=$(printf '%s' "$pr_rows" | jq length); pr_i=0
  while [ "$pr_i" -lt "$pr_n" ]; do
    pr_r=$(printf '%s' "$pr_rows" | jq -c --argjson n "$pr_i" '.[$n]'); pr_i=$((pr_i + 1))
    pr_id=$(printf '%s' "$pr_r" | jq -r .id)
    pr_state=$(printf '%s' "$pr_r" | jq -r .state)
    pr_model=$(printf '%s' "$pr_r" | jq -r .model)
    pr_effort=$(printf '%s' "$pr_r" | jq -r .effort)
    pr_remote=$(printf '%s' "$pr_r" | jq -r .remote)
    if [ -z "$pr_stream" ]; then
      render_plain '%s  %s  model %s  effort %s  remote %s\n' \
        "$pr_id" "$pr_state" "$pr_model" "$pr_effort" "$pr_remote"
      continue
    fi
    # One state in this column is a thing a person can act on now, and it is the column's whole
    # use: scanning a twenty-row graph for what may be dispatched. The rest report, so they read
    # as ordinary text and the eligible rows stand out without a legend.
    case "$pr_state" in
      eligible) pr_shown=$(render_token "$pr_stream" state "$pr_state") ;;
      *)        pr_shown=$pr_state ;;
    esac
    render_row "$pr_stream" plain '%s  %s  model %s  effort %s  remote %s\n' \
      "$(render_token "$pr_stream" milestone "$pr_id")" "$pr_shown" \
      "$pr_model" "$pr_effort" "$pr_remote"
  done
}

# project_path <project>: the registered canonical checkout.
project_path() {
  jq -er .path "$BATON_HOME/projects/$1/project.json" 2>/dev/null
}

# plan_of_project <project>: project.json → the plan file → plan_tables' document; on failure
# the message a verb prints, with status 2 for a registration problem and 1 for a plan problem.
plan_of_project() {
  pp_pj=$BATON_HOME/projects/$1/project.json
  [ -f "$pp_pj" ] || { echo "baton: no project '$1' registered under $BATON_HOME/projects/"; return 2; }
  pp_path=$(jq -er .path "$pp_pj" 2>/dev/null) && pp_plan=$(jq -er .plan "$pp_pj" 2>/dev/null) \
    || { echo "baton: $pp_pj lacks path or plan"; return 2; }
  pp_file=$pp_path/$pp_plan
  [ -r "$pp_file" ] || { echo "baton: plan file $pp_file cannot be read"; return 1; }
  if ! pp_tables=$(plan_tables "$pp_file" "$1"); then
    printf '%s' "$pp_tables" | jq -r '"baton: plan \(.table) table, row \(.row), cell \(.cell): \(.detail)"'
    return 1
  fi
  printf '%s\n' "$pp_tables"
}

# plan_preconditions_report <project> <plan json>: the last section of `baton plan`, and the reason
# a person can repair a whole plan's dispatch defects in one pass instead of learning them one
# refused dispatch at a time. Every plan-eligible milestone is inspected — the pass does not stop at
# the first defect, and a defect on one milestone says nothing about its peers — and each failure is
# printed as `<id>  <stage>/<check>  <path>  <detail>` so a person can grep for a milestone, a stage
# or a check and still read the whole repair. A shared defect, such as permission rules without deny
# rules, therefore names every milestone it would refuse rather than only the first.
#
# Writes nothing, dispatches nothing, and promises nothing: the runtime rows, the holds and the cap
# decide admission in their own callers, and a milestone reported ready here is one no *knowable*
# precondition refuses. Prints the count line first; returns 1 if anything is unmet.
plan_preconditions_report() {
  # The stream, so that the report reads the same way as the graph above it. The count line is a
  # heading and has to be printed before the lines it counts, so the lines are rendered as they are
  # collected and held as text; the rendering happens once, here, either way.
  ppr_stream=${3:-out}
  ppr_eligible=$(printf '%s' "$2" | plan_eligible)
  if [ -z "$ppr_eligible" ]; then
    render_heading "$ppr_stream" 'preconditions: no eligible milestone\n'
    return 0
  fi
  ppr_lines=
  ppr_n=0; ppr_unmet=0
  for ppr_id in $ppr_eligible; do
    ppr_n=$((ppr_n + 1))
    ppr_shown=$(render_token "$ppr_stream" milestone "$ppr_id")
    if ! ppr_res=$(dispatch_preconditions "$1" "$ppr_id"); then
      ppr_unmet=$((ppr_unmet + 1))
      ppr_lines="$ppr_lines$(render_row "$ppr_stream" plain '  %s  not inspected  %s\n' "$ppr_shown" "$ppr_res")
"
      continue
    fi
    # The same reading `dispatch_one` makes of the same result: an array, or nothing that may be
    # read as an absence of defects. Two readers of one result that disagreed on what counts as a
    # result would put the report and the refusal back out of step, which is what sharing it avoids.
    if ! printf '%s' "$ppr_res" | jq -e '(.failures | type) == "array"' > /dev/null 2>&1; then
      ppr_unmet=$((ppr_unmet + 1))
      ppr_lines="$ppr_lines$(render_row "$ppr_stream" plain '  %s  not inspected  %s\n' "$ppr_shown" \
        'the precondition result carried no failures array')
"
      continue
    fi
    ppr_count=$(printf '%s' "$ppr_res" | jq -r '.failures | length')
    if [ "$ppr_count" -eq 0 ]; then
      ppr_lines="$ppr_lines$(render_row "$ppr_stream" plain '  %s  ready\n' "$ppr_shown")
"
      continue
    fi
    ppr_unmet=$((ppr_unmet + 1))
    ppr_f=$(printf '%s' "$ppr_res" | jq -c .failures)
    ppr_fi=0
    while [ "$ppr_fi" -lt "$ppr_count" ]; do
      ppr_one=$(printf '%s' "$ppr_f" | jq -c --argjson n "$ppr_fi" '.[$n]'); ppr_fi=$((ppr_fi + 1))
      ppr_detail=$(printf '%s' "$ppr_one" | jq -r .detail)
      ppr_repair=$(printf '%s' "$ppr_one" | jq -r '.repair // ""')
      # The repair is the command the detail already ends with, so marking it is a matter of
      # finding that suffix rather than of rebuilding the sentence. A detail that does not end
      # with its repair — which `not-a-worktree` has none of — is left exactly as it came.
      if [ -n "$ppr_repair" ]; then
        ppr_lead=${ppr_detail%"$ppr_repair"}
        if [ "$ppr_lead" != "$ppr_detail" ]; then
          ppr_detail="$ppr_lead$(render_hint "$ppr_stream" "$ppr_repair")"
        fi
      fi
      ppr_lines="$ppr_lines$(render_row "$ppr_stream" plain '  %s  %s/%s  %s  %s\n' "$ppr_shown" \
        "$(printf '%s' "$ppr_one" | jq -r .stage)" "$(printf '%s' "$ppr_one" | jq -r .check)" \
        "$(render_token "$ppr_stream" path "$(printf '%s' "$ppr_one" | jq -r .path)")" "$ppr_detail")
"
    done
    # Said once, not as a guess per filename: a prompt that could not be read is a prompt whose
    # references nothing can inspect, and inventing the documents it might have named would be
    # reporting defects Baton has not seen.
    printf '%s' "$ppr_res" | jq -e .references_inspected > /dev/null \
      || ppr_lines="$ppr_lines$(render_row "$ppr_stream" plain '  %s  note  %s\n' "$ppr_shown" \
           'the kickoff prompt could not be read, so the documents it names were not inspected')
"
  done
  render_heading "$ppr_stream" 'preconditions: %s eligible, %s with unmet preconditions\n' "$ppr_n" "$ppr_unmet"
  printf '%s' "$ppr_lines"
  [ "$ppr_unmet" -eq 0 ] || return 1
}

# verb_plan <project>: the graph as the tick sees it; every Model cell validated by the parse;
# the project's widening events newest first; then every eligible milestone's unmet dispatch
# preconditions. Writes nothing, and returns 1 when a precondition is unmet so that a script can
# branch on a plan that cannot be dispatched from.
verb_plan() {
  # `plan_of_project`'s failure is its returned detail, not a rendered line (D-030): it is printed
  # here, where the stream is known, and carried whole into an event by its other caller.
  vp_tables=$(plan_of_project "$1") || { vp_st=$?; render_failure err "$vp_tables"; exit $vp_st; }
  render_heading out 'plan %s: %s/%s\n' "$1" "$(project_path "$1")" \
    "$(jq -r .plan "$BATON_HOME/projects/$1/project.json")"
  vp_inflight=$(derive_in_flight "$1" "$(rows_json)") || { render_failure err "baton: $vp_inflight"; exit 1; }
  vp_inflight=$(printf '%s' "$vp_inflight" | jq -c .in_flight)
  printf '%s' "$vp_tables" | plan_render "$1" "$vp_inflight" out
  vp_gates=$(printf '%s' "$vp_tables" | jq -c .gates)
  vp_n=$(printf '%s' "$vp_gates" | jq length); vp_i=0
  while [ "$vp_i" -lt "$vp_n" ]; do
    vp_g=$(printf '%s' "$vp_gates" | jq -c --argjson n "$vp_i" '.[$n]'); vp_i=$((vp_i + 1))
    render_row out plain 'gate "%s" holds %s%s\n' \
      "$(render_token out state "$(printf '%s' "$vp_g" | jq -r .gate)")" \
      "$(render_token out milestone "$(printf '%s' "$vp_g" | jq -r '.holds | join(", ")')")" \
      "$(printf '%s' "$vp_g" | jq -r 'if .cleared == "" then "" else ", cleared by " + .cleared end')"
  done
  vp_w=$(widenings_json "$1") || { render_failure err "baton: $vp_w"; exit 1; }
  if [ "$(printf '%s' "$vp_w" | jq length)" -eq 0 ]; then
    render_heading out 'widenings: none\n'
  else
    render_heading out 'widenings, newest first:\n'
    vp_n=$(printf '%s' "$vp_w" | jq length); vp_i=0
    while [ "$vp_i" -lt "$vp_n" ]; do
      vp_one=$(printf '%s' "$vp_w" | jq -c --argjson n "$vp_i" '.[$n]'); vp_i=$((vp_i + 1))
      render_row out plain '  %s  %s  %s\n' \
        "$(render_token out timestamp "$(printf '%s' "$vp_one" | jq -r .at)")" \
        "$(render_token out milestone "$(printf '%s' "$vp_one" | jq -r .milestone)")" \
        "$(printf '%s' "$vp_one" | jq -r .rule)"
    done
  fi
  # Explicitly, rather than on `set -e`: the verb's other failures exit with a status they chose,
  # and a reader should not have to know which shell option carries this one.
  plan_preconditions_report "$1" "$vp_tables" out || exit 1
}
