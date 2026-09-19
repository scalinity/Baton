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

# plan_extract <file>: the awk pass. One line per body row, fields on \037:
#   M <row> <ID> <Depends on> <Model> <Effort> <Remote> <Status>
#   G <row> <Gate> <Holds> <Cleared>
#   T <table>                      the table was found
#   E <table> <row> <cell> <detail> a structural failure: a required column missing, a row short
# Extra columns are ignored; \| inside a cell is an escaped pipe; a row without a trailing pipe
# still counts its last part as a cell; a body row with fewer cells than the header fails; the
# first table with each header cell wins.
plan_extract() {
  awk -v OFS="$plan_us" '
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
    function header(table, names,    k, i, want) {
      split("", col)
      for (i = 1; i <= nc; i++) col[C[i]] = i
      k = split(names, want, ",")
      for (i = 1; i <= k; i++) if (!(want[i] in col)) {
        print "E", table, "header", want[i], "column \"" want[i] "\" is missing from the header"
        exit 0
      }
      need[table] = nc
      print "T", table
    }
    /^[ \t]*\|/ {
      cells($0)
      if (state == "") {
        if (nc >= 1 && C[1] == "ID" && !seen_m) { seen_m = 1; header("milestones", "ID,Depends on,Model,Effort,Remote,Status"); state = "m-sep"; next }
        if (nc >= 1 && C[1] == "Gate" && !seen_g) { seen_g = 1; header("gates", "Gate,Holds,Cleared"); state = "g-sep"; next }
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

# parse_status <cell>: blank, done or held.
parse_status() {
  case "$1" in ''|done|held) printf '%s\n' "$1" ;; *) return 1 ;; esac
}

# parse_cleared <cell>: blank or a D-number.
parse_cleared() {
  case "$1" in '') echo ;; *) printf '%s' "$1" | grep -Eq '^D-[0-9]+$' || return 1; printf '%s\n' "$1" ;; esac
}

# ids_json: lines of ids on stdin to a JSON array.
ids_json() {
  jq -Rn '[inputs | select(length > 0)]' | jq -c .
}

# plan_tables <file>: the parsed plan as one JSON document,
#   {"milestones": [{row, id, depends[], model, effort, remote, status}], "gates": [{row, gate, holds[], cleared}]}
# or, on the first cell that does not parse, plan_fail's object with status 1.
plan_tables() {
  pt_models=$(jq -c '.models // {}' "$BATON_HOME/config.json" 2>/dev/null || echo '{}')
  pt_raw=$(plan_extract "$1")
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
        pt_model=$(parse_model "$pt_d" "$pt_models") || { plan_fail milestones "$pt_rowname" Model "\"$pt_d\" is not a model alias in config.json or a full model id"; return 1; }
        pt_effort=$(parse_effort "$pt_e") || { plan_fail milestones "$pt_rowname" Effort "\"$pt_e\" is not blank or low|medium|high|xhigh|max"; return 1; }
        pt_remote=$(parse_remote "$pt_f") || { plan_fail milestones "$pt_rowname" Remote "\"$pt_f\" is not blank or yes"; return 1; }
        pt_status=$(parse_status "$pt_g") || { plan_fail milestones "$pt_rowname" Status "\"$pt_g\" is not blank, done or held"; return 1; }
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
  [ "$pt_seen_g" = yes ] || { plan_fail gates - Gate "no table has a Gate header cell"; return 1; }
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

# plan_render <project> <inflight json>: the graph, one line per milestone, on stdin.
plan_render() {
  jq -r --argjson inflight "$2" '
    ($inflight | map(.milestone)) as $flying
    | (.milestones | map(select(.status == "done") | .id)) as $done
    | (.gates | map(select(.cleared == ""))) as $open
    | .milestones[]
    | .id as $i
    | ( if .status == "done" then "done"
        elif ($flying | index($i)) != null then "in flight"
        elif .status == "held" then "held"
        elif ([$open[] | select(.holds | index($i) != null) | .gate] | length) > 0
          then "held by gate \"" + ([$open[] | select(.holds | index($i) != null) | .gate] | join("\", \"")) + "\""
        elif all(.depends[]; . as $d | ($done | index($d)) != null) then "eligible"
        else "waits on " + ([.depends[] | select(. as $d | ($done | index($d)) == null)] | join(", "))
        end ) as $state
    | "\(.id)  \($state)  model \(.model)  effort \(if .effort == "" then "-" else .effort end)  remote \(if .remote then "yes" else "no" end)"'
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
  if ! pp_tables=$(plan_tables "$pp_file"); then
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
  ppr_eligible=$(printf '%s' "$2" | plan_eligible)
  if [ -z "$ppr_eligible" ]; then
    echo "preconditions: no eligible milestone"
    return 0
  fi
  ppr_lines=
  ppr_n=0; ppr_unmet=0
  for ppr_id in $ppr_eligible; do
    ppr_n=$((ppr_n + 1))
    if ! ppr_res=$(dispatch_preconditions "$1" "$ppr_id"); then
      ppr_unmet=$((ppr_unmet + 1))
      ppr_lines="$ppr_lines  $ppr_id  not inspected  $ppr_res
"
      continue
    fi
    ppr_count=$(printf '%s' "$ppr_res" | jq -r '.failures | length' 2>/dev/null) || ppr_count=
    if [ -z "$ppr_count" ]; then
      ppr_unmet=$((ppr_unmet + 1))
      ppr_lines="$ppr_lines  $ppr_id  not inspected  the precondition result did not parse
"
      continue
    fi
    if [ "$ppr_count" -eq 0 ]; then
      ppr_lines="$ppr_lines  $ppr_id  ready
"
      continue
    fi
    ppr_unmet=$((ppr_unmet + 1))
    ppr_lines="$ppr_lines$(printf '%s' "$ppr_res" | jq -r --arg id "$ppr_id" \
      '.failures[] | "  \($id)  \(.stage)/\(.check)  \(.path)  \(.detail)"')
"
    # Said once, not as a guess per filename: a prompt that could not be read is a prompt whose
    # references nothing can inspect, and inventing the documents it might have named would be
    # reporting defects Baton has not seen.
    printf '%s' "$ppr_res" | jq -e .references_inspected > /dev/null \
      || ppr_lines="$ppr_lines  $ppr_id  note  the kickoff prompt could not be read, so the documents it names were not inspected
"
  done
  echo "preconditions: $ppr_n eligible, $ppr_unmet with unmet preconditions"
  printf '%s' "$ppr_lines"
  [ "$ppr_unmet" -eq 0 ] || return 1
}

# verb_plan <project>: the graph as the tick sees it; every Model cell validated by the parse;
# the project's widening events newest first; then every eligible milestone's unmet dispatch
# preconditions. Writes nothing, and returns 1 when a precondition is unmet so that a script can
# branch on a plan that cannot be dispatched from.
verb_plan() {
  vp_tables=$(plan_of_project "$1") || { vp_st=$?; echo "$vp_tables" >&2; exit $vp_st; }
  echo "plan $1: $(project_path "$1")/$(jq -r .plan "$BATON_HOME/projects/$1/project.json")"
  vp_inflight=$(derive_in_flight "$1" "$(rows_json)") || { echo "baton: $vp_inflight" >&2; exit 1; }
  vp_inflight=$(printf '%s' "$vp_inflight" | jq -c .in_flight)
  printf '%s' "$vp_tables" | plan_render "$1" "$vp_inflight"
  printf '%s' "$vp_tables" | jq -r '.gates[] | "gate \"\(.gate)\" holds \(.holds | join(", "))\(if .cleared == "" then "" else ", cleared by " + .cleared end)"'
  vp_w=$(widenings_json "$1") || { echo "baton: $vp_w" >&2; exit 1; }
  if [ "$(printf '%s' "$vp_w" | jq length)" -eq 0 ]; then
    echo "widenings: none"
  else
    echo "widenings, newest first:"
    printf '%s' "$vp_w" | jq -r '.[] | "  \(.at)  \(.milestone)  \(.rule)"'
  fi
  plan_preconditions_report "$1" "$vp_tables"
}
