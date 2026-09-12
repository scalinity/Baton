#!/bin/sh
# lib/dispatch.sh — step 8 of the tick as functions: the worktree, the settings file, the prompt
# from the brief on main, the slot line, claude --bg, the row, the sidecar, caffeinate and the
# dispatch event; plus the hand-run dispatch verb. On failure every function prints its detail
# on stdout and returns non-zero, so a caller captures once and branches on the status.
set -eu

# row_for_id <id>: the agents row whose id is <id> and which carries a pid, polled for up to
# thirty seconds because the row appears a beat after backgrounded is printed. A worker that
# crashes before init never gets a row; the service records that in its own log as
# "bg settled <id> (crashed): <detail>" (item 47, D-027), so the poll reads that line and stops
# early. Prints the row, or the failure's detail.
row_for_id() {
  rf_i=0
  while [ "$rf_i" -lt 60 ]; do
    rf_row=$(rows_json | jq -ce --arg id "$1" 'map(select(.id == $id and .pid != null)) | first // empty' 2>/dev/null) \
      && { printf '%s\n' "$rf_row"; return 0; }
    if [ -f "$BATON_DAEMON_LOG" ]; then
      rf_settled=$(grep -F "bg settled $1 (crashed): " "$BATON_DAEMON_LOG" | tail -1 | sed 's/.*(crashed): //') || true
      if [ -n "$rf_settled" ]; then
        echo "session $1 was backgrounded and crashed before init: $rf_settled"
        return 1
      fi
    fi
    rf_i=$((rf_i + 1))
    sleep 0.5
  done
  echo "session $1 was backgrounded but no row with a pid appeared within thirty seconds"
  return 1
}

# worktree_ensure <path> <milestone>: ../<Project>-<milestone> on branch <milestone lowercased>,
# created from main; reused if it exists, recording the commit it stands at. Prints
# {"worktree","branch","reused","commit"}.
worktree_ensure() {
  we_path=$1; we_id=$2
  we_wt=$(dirname "$we_path")/$(basename "$we_path")-$we_id
  we_branch=$(printf '%s' "$we_id" | tr 'A-Z' 'a-z')
  if [ -d "$we_wt" ]; then
    we_reused=true
    we_commit=$(git -C "$we_wt" rev-parse HEAD 2>&1) || { echo "$we_wt exists but is not a worktree: $we_commit"; return 1; }
  else
    we_reused=false
    # core.hooksPath is emptied because `worktree add` runs the repository's post-checkout hook, and
    # from M03 this call is made by a launchd job whose shell has Full Disk Access. A dispatched
    # session runs under bypassPermissions inside that checkout and the deny list does not cover a
    # target's own .git, so a hook written there would be code the tick then executes — which is
    # exactly what INV-12 says never happens (D-048).
    if git -C "$we_path" show-ref --verify --quiet "refs/heads/$we_branch"; then
      we_out=$(git -C "$we_path" -c core.hooksPath=/dev/null worktree add "$we_wt" "$we_branch" 2>&1) \
        || { echo "$we_out"; return 1; }
    else
      we_out=$(git -C "$we_path" -c core.hooksPath=/dev/null worktree add "$we_wt" -b "$we_branch" main 2>&1) \
        || { echo "$we_out"; return 1; }
    fi
    we_commit=$(git -C "$we_wt" rev-parse HEAD)
  fi
  jq -nc --arg w "$we_wt" --arg b "$we_branch" --argjson r "$we_reused" --arg c "$we_commit" \
    '{worktree: $w, branch: $b, reused: $r, commit: $c}'
}

# worktree_prune <project> <plan json> <rows json>: removes a milestone worktree a close-out left
# behind, and nothing else. The one destructive act Baton performs (REQ-DISPATCH-03, D-013).
#
# A worktree is a candidate only when git lists it at exactly the path `worktree_ensure` makes —
# `../<Project>-<milestone>` beside the canonical checkout, for a milestone the plan names — so a
# worktree a person made anywhere else is never looked at. Then three guards, each of which refuses:
#
#   1. the milestone's `Status` reads `done`;
#   2. no session belongs to it — no open lane for the milestone, whether or not its session has a
#      pid right now (a lane in a wait has none, and its resume lands in this worktree); no live row
#      named for it; and no live row whose working directory is the worktree or under it, which is
#      what a person's own session started there looks like;
#   3. the newest archived `complete` handover for the milestone names a `merged_as` that
#      `merged_as_verify` accepts — a commit id and not a name, and an ancestor of `main` — and no
#      dispatch or consumed ending for the milestone is newer than it, so the merge on `main` is this
#      worktree's last word and not an older attempt's.
#
# Every guard fails closed: a question it could not answer — a jq that errored on a row it did not
# expect — refuses, because the cost of a wrong refusal is a directory left until the next tick and
# the cost of a wrong removal is the work.
#
# Never on `Status` alone: a close-out that wrote `done` a step early and then failed its merge left a
# cell reading `done` over the only copy of the work, and it has no `complete` handover to pass the
# third guard. The removal is `git worktree remove` without `--force`, so git's own refusal of a tree
# with modified or untracked files stands as a fourth; the branch is not deleted, so a commit made
# after the merge is still on it.
#
# The candidate is matched by exact string against the path git prints, as `worktree_ensure` composed
# it from `project.json`. A checkout registered through a symlink never matches, and the prune then
# never acts — the safe direction, and the reason no path is resolved here.
#
# The removal comes before the `worktree_pruned` event, unlike a copy fork's record (D-059): a tick
# killed between them loses the record of a removal the next tick cannot repeat, while an event
# written first would claim a removal that may not have happened.
#
# A worktree git lists whose directory is already gone is passed through the same guards and the same
# command, which then drops the registration and touches nothing on disk. That is `git worktree
# prune`'s own judgement of such an entry — git lists it as `prunable` — applied to this one path
# rather than to every stale registration in the repository, some of which may be a person's.
#
# Prints a line for what it removed, and for a `done` worktree it refused, which is an anomaly worth
# a line in launchd.out; a worktree whose milestone is not `done` is the normal case and says nothing.
worktree_prune() {
  wp_path=$(project_path "$1") || return 0
  wp_prefix=$(dirname "$wp_path")/$(basename "$wp_path")-
  wp_list=$(git -C "$wp_path" worktree list --porcelain 2>&1) \
    || { echo "prune     $1 · git worktree list failed: $wp_list"; return 0; }
  wp_paths=$(printf '%s\n' "$wp_list" | sed -n 's/^worktree //p')
  wp_log=$(log_json) || { echo "$wp_log" >&2; return 1; }
  wp_open=$(lanes_open "$1" "$wp_log") || { echo "$wp_open" >&2; return 1; }
  wp_consumed=$(derive_consumed "$1") || { echo "$wp_consumed" >&2; return 1; }
  while IFS= read -r wp_wt; do
    case "$wp_wt" in "$wp_prefix"*) ;; *) continue ;; esac
    wp_id=${wp_wt#"$wp_prefix"}
    case "$wp_id" in */*) continue ;; esac
    wp_row=$(printf '%s' "$2" | plan_row "$wp_id" 2>/dev/null) || continue
    # 1.
    [ "$(printf '%s' "$wp_row" | jq -r '.status // ""')" = done ] || continue
    # 2. Each answer is read as text and only `false` lets the prune go on.
    wp_lane=$(printf '%s' "$wp_open" | jq -r --arg m "$wp_id" 'any(.[]; .milestone == $m)' 2>/dev/null) || wp_lane=unreadable
    wp_live=$(printf '%s' "$3" | jq -r --arg n "$(session_name "$1" "$wp_id")" --arg w "$wp_wt" '
      if any(.[]; .pid != null and .name == $n) then "named"
      elif any(.[]; .pid != null and (.cwd == $w or ((.cwd // "") | startswith($w + "/")))) then "inside"
      else "false" end' 2>/dev/null) || wp_live=unreadable
    if [ "$wp_lane" != false ]; then
      [ "$wp_lane" = true ] && wp_who="an open lane for $wp_id" || wp_who="the lanes, which could not be read"
    elif [ "$wp_live" != false ]; then
      case "$wp_live" in
        named)  wp_who="a live row named for $wp_id" ;;
        inside) wp_who="a live row working inside it" ;;
        *)      wp_who="the rows, which could not be read" ;;
      esac
    else
      wp_who=''
    fi
    if [ -n "$wp_who" ]; then
      echo "prune     $1/$wp_id · $wp_wt is done but a session may belong to it ($wp_who) · left in place"
      continue
    fi
    # 3.
    wp_archive=$(printf '%s' "$wp_consumed" | jq -r --arg m "$wp_id" \
      '[ .consumed[] | select(.milestone == $m and .outcome == "complete" and .archive_present) ] | last | .archive // empty')
    wp_merged=''
    [ -z "$wp_archive" ] || wp_merged=$(jq -r '.merged_as // empty' "$wp_archive" 2>/dev/null) || wp_merged=''
    if [ -z "$wp_merged" ]; then
      echo "prune     $1/$wp_id · $wp_wt is done but no complete handover for it is archived · left in place"
      continue
    fi
    wp_newer=$(printf '%s' "$wp_log" | jq -r --arg p "$1" --arg m "$wp_id" --arg a "$wp_archive" '
      [ to_entries[] | {i: .key} + .value | select(.project == $p and .milestone == $m) ] as $ev
      | ([ $ev[] | select(.kind == "consumed" and .archive == $a) ] | last | .i) as $at
      | if $at == null then "true"
        else any($ev[]; (.kind == "dispatch" or .kind == "consumed") and .i > $at) | tostring end' 2>/dev/null) \
      || wp_newer=true
    if [ "$wp_newer" != false ]; then
      echo "prune     $1/$wp_id · $wp_wt is done but the milestone has a dispatch or an ending newer than its complete handover · left in place"
      continue
    fi
    if ! wp_why=$(merged_as_verify "$wp_path" "$wp_merged"); then
      echo "prune     $1/$wp_id · $wp_wt is done but its merged_as does not verify: $wp_why · left in place"
      continue
    fi
    wp_gone=no
    [ -e "$wp_wt" ] || wp_gone=yes
    if ! wp_out=$(git -C "$wp_path" worktree remove "$wp_wt" 2>&1); then
      echo "prune     $1/$wp_id · git refused to remove $wp_wt: $wp_out · left in place"
      continue
    fi
    log_event worktree_pruned "$1" "$wp_id" "" "" \
      "$(jq -nc --arg w "$wp_wt" --arg m "$wp_merged" '{worktree: $w, merged_as: $m}')" || return 1
    if [ "$wp_gone" = yes ]; then
      echo "pruned    $1/$wp_id · $wp_wt was already gone; its registration is dropped"
    else
      echo "pruned    $1/$wp_id · $wp_wt removed, merged as $wp_merged"
    fi
  done <<EOF
$wp_paths
EOF
}

# settings_compose <project> <milestone>: the dispatched settings file at
# settings/<project>-<milestone>.json from the project's permissions.json: the mode as
# documentation, allow and deny copied, no ask rules, the three hooks carrying Baton's home, the
# project key and the milestone on their command lines and pointing at the installed relay. A
# permissions.json without deny rules fails the stage: a bypassPermissions session without the
# rail is not dispatched. Prints the path.
settings_compose() {
  sc_perm=$BATON_HOME/projects/$1/permissions.json
  sc_out=$BATON_HOME/settings/$1-$2.json
  [ -f "$sc_perm" ] || { echo "$sc_perm is missing"; return 1; }
  sc_json=$(jq -e --arg env "BATON_HOME='$BATON_HOME' BATON_PROJECT='$1' BATON_MILESTONE='$2'" --arg bin "$BATON_HOME/bin" '
    if ((.permissions.deny // []) | length) == 0
      then error("permissions.deny is empty; a bypassPermissions session needs the two deny classes") else . end
    | { permissions: { defaultMode: "bypassPermissions",
                       allow: (.permissions.allow // []),
                       deny: .permissions.deny },
        statusLine: { type: "command", command: "\($env) \($bin)/statusline" },
        hooks: {
          Stop:        [{ hooks: [{ type: "command", command: "\($env) \($bin)/stop-gate" }] }],
          StopFailure: [{ hooks: [{ type: "command", command: "\($env) \($bin)/stop-failure" }] }] } }' \
    "$sc_perm" 2>&1) || { echo "$sc_perm: $sc_json"; return 1; }
  mkdir -p "$BATON_HOME/settings"
  printf '%s\n' "$sc_json" > "$sc_out.tmp"
  mv "$sc_out.tmp" "$sc_out"
  printf '%s\n' "$sc_out"
}

# prompt_from_brief <path> <brief> <heading>: the first fenced block under the line
# "## <heading>" in the brief as it is on main — git show, never the working tree, so a person
# mid-edit cannot change what a session receives. The search ends at the next "## " heading.
# Prints the block's body.
prompt_from_brief() {
  pb_text=$(git -C "$1" show "main:$2" 2>&1) || { echo "brief $2 is not on main: $pb_text"; return 1; }
  pb_body=$(printf '%s\n' "$pb_text" | HEADING="## $3" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    !found && trim($0) == ENVIRON["HEADING"] { found = 1; next }
    found && !infence && /^## / { exit }
    found && !infence && /^```/ { infence = 1; next }
    found && infence && /^```/ { closed = 1; exit }
    found && infence { print }
    END { exit (closed ? 0 : 1) }') || { echo "no fenced block under \"## $3\" in $2 on main"; return 1; }
  printf '%s' "$pb_body"
}

# slot_line <prompt> <paragraph>: replaces the one paragraph beginning WHAT ELSE IS IN FLIGHT.
# with <paragraph> and prints the result; fails if the prompt has no such paragraph.
slot_line() {
  sl_out=$(printf '%s\n' "$1" | REP="$2" awk '
    /^WHAT ELSE IS IN FLIGHT\./ { print ENVIRON["REP"]; skipping = 1; replaced = 1; next }
    skipping && !/^[ \t]*$/ { next }
    skipping { skipping = 0 }
    { print }
    END { exit (replaced ? 0 : 1) }') || { echo "the prompt has no paragraph beginning WHAT ELSE IS IN FLIGHT."; return 1; }
  printf '%s' "$sl_out"
}

# cli_plain: stdin to stdout with the CLI's colour escapes removed. Everything Baton reads from the
# CLI's own output goes through it first.
#
# Measured while running live item 44 (D-050): with FORCE_COLOR set in the environment — which every
# process started from inside a Claude Code session inherits — `claude --bg` prints
# `backgrounded · <ESC>[36m82b69058<ESC>[39m · …` even with stdout redirected to a file, so the id
# does not match the hexadecimal test and a dispatch that had really started a session was recorded
# as a launch failure. The lane then never opened and the next tick dispatched a second session for
# the same milestone. The launchd job sets only LC_ALL and so never saw it; a hand-run
# `baton dispatch` from inside a session saw it every time.
cli_plain() { sed "s/$(printf '\033')\[[0-9;]*[a-zA-Z]//g"; }

# claude_bg <worktree> <name> <model> <effort> <settings> <prompt>: the one command, with the
# worktree as cwd and LC_ALL set. Sets bg_status, bg_stdout, bg_stderr and bg_id (empty when no
# "backgrounded · <id>" line was printed, which is the failure test).
claude_bg() {
  cb_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-bg.XXXXXX")
  set +e
  ( cd "$1" && LC_ALL=en_US.UTF-8 "$BATON_CLAUDE" --bg -n "$2" --model "$3" ${4:+--effort "$4"} \
      --permission-mode bypassPermissions --settings "$5" "$6" ) > "$cb_tmp" 2> "$cb_tmp.err"
  bg_status=$?
  set -e
  bg_stdout=$(cli_plain < "$cb_tmp"); bg_stderr=$(cli_plain < "$cb_tmp.err")
  rm -f "$cb_tmp" "$cb_tmp.err"
  bg_id=$(printf '%s\n' "$bg_stdout" | LC_ALL=en_US.UTF-8 awk '$1 == "backgrounded" && $3 ~ /^[0-9a-f]+$/ { print $3; exit }')
}

# dispatch_failed_classify <text>: the stage of a dispatch that produced no session, from the
# four strings known from the binary; launch by default. The specific strings are matched before
# the service line because the binary prints "Starting background service…" on the way to them.
dispatch_failed_classify() {
  case "$1" in
    *"Error: Settings file not found:"*) echo settings ;;
    *"requires accepting the disclaimer first"*) echo launch ;;
    *"cannot be combined with --print"*) echo launch ;;
    *"Starting background service"*) echo service ;;
    *) echo launch ;;
  esac
}

# caffeinate_hold <pid>: caffeinate -i -w <pid>, detached, so the Mac stays awake while the
# session's process lives.
caffeinate_hold() {
  "$BATON_CAFFEINATE" -i -w "$1" < /dev/null > /dev/null 2>&1 &
}

# dispatch_failed <project> <milestone> <stage> <detail>: the event and the message. The detail
# is the one field an outside process sizes (a whole stderr), so it is cut to 2000 bytes and
# marked, keeping the line under log_event's 4 KB refusal.
dispatch_failed() {
  df_detail=$4
  df_truncated=false
  if [ "$(printf '%s' "$df_detail" | wc -c | tr -d ' ')" -gt 2000 ]; then
    df_detail=$(printf '%s' "$df_detail" | head -c 2000)
    df_truncated=true
  fi
  log_event dispatch_failed "$1" "$2" "" "" "$(jq -nc --arg s "$3" --arg d "$df_detail" --argjson t "$df_truncated" \
    '{stage: $s, detail: $d} | if $t then . + {detail_truncated: true} else . end')"
  echo "baton: dispatch of $1 $2 failed at $3: $df_detail" >&2
}

# dispatch_one <project> <milestone> <plan json> <rows json>: step 8 for one milestone.
dispatch_one() {
  do_project=$1; do_id=$2; do_plan=$3; do_rows=$4
  do_path=$(project_path "$do_project")
  do_row=$(printf '%s' "$do_plan" | plan_row "$do_id")
  do_model=$(printf '%s' "$do_row" | jq -r .model)
  do_effort=$(printf '%s' "$do_row" | jq -r .effort)
  do_remote=$(printf '%s' "$do_row" | jq -r .remote)
  [ "$do_remote" = false ] || { echo "baton: $do_id is Remote: yes and remote dispatch is not built yet (M07)" >&2; return 2; }
  do_attempt=$(attempt_of "$do_project" "$do_id") || { echo "baton: $do_attempt" >&2; return 1; }
  do_attempt=$((do_attempt + 1))
  do_name=$(session_name "$do_project" "$do_id")

  do_wt=$(worktree_ensure "$do_path" "$do_id") || { dispatch_failed "$do_project" "$do_id" worktree "$do_wt"; return 1; }
  do_wt_path=$(printf '%s' "$do_wt" | jq -r .worktree)
  do_branch=$(printf '%s' "$do_wt" | jq -r .branch)
  do_reused=$(printf '%s' "$do_wt" | jq -r .reused)
  do_commit=$(printf '%s' "$do_wt" | jq -r .commit)

  do_settings=$(settings_compose "$do_project" "$do_id") || { dispatch_failed "$do_project" "$do_id" settings "$do_settings"; return 1; }

  do_brief=docs/milestones/$do_id.md
  do_prompt=$(prompt_from_brief "$do_path" "$do_brief" "Copy-ready session prompt") || { dispatch_failed "$do_project" "$do_id" prompt "$do_prompt"; return 1; }
  do_inflight=$(derive_in_flight "$do_project" "$do_rows") || { echo "baton: $do_inflight" >&2; return 1; }
  do_inflight=$(printf '%s' "$do_inflight" | jq -c .in_flight)
  do_also=$(printf '%s' "$do_inflight" | jq -r --arg me "$do_id" --argjson plan "$do_plan" '
    ($plan.milestones | map(select(.status == "done") | .id)) as $done
    | map(select(.milestone as $m | $m != $me and (($done | index($m)) == null)))
    | map("\(.milestone) (worktree \(.worktree | split("/") | last), brief docs/milestones/\(.milestone).md)")
    | join(", ")')
  do_slot=$(slot_line_text "$do_wt_path" "$do_branch" "$do_path" "$do_also" "$do_attempt" "$do_commit")
  do_body=$(slot_line "$do_prompt" "$do_slot") || { dispatch_failed "$do_project" "$do_id" prompt "$do_body"; return 1; }

  claude_bg "$do_wt_path" "$do_name" "$do_model" "$do_effort" "$do_settings" "$do_body"
  if [ -z "$bg_id" ]; then
    do_detail=$bg_stderr
    [ -n "$do_detail" ] || do_detail="exit $bg_status with nothing on stderr; stdout: $bg_stdout"
    dispatch_failed "$do_project" "$do_id" "$(dispatch_failed_classify "$bg_stderr")" "$do_detail"
    return 1
  fi

  do_agent=$(row_for_id "$bg_id") || { dispatch_failed "$do_project" "$do_id" "$(dispatch_failed_classify "$do_agent")" "$do_agent"; return 1; }
  do_session=$(printf '%s' "$do_agent" | jq -r .sessionId)
  do_pid=$(printf '%s' "$do_agent" | jq -r .pid)

  do_sidecar=$(sidecar_write "$do_session" "$do_body")
  do_prompt_path=${do_sidecar% *}
  do_prompt_sha=${do_sidecar##* }

  caffeinate_hold "$do_pid"

  log_event dispatch "$do_project" "$do_id" "$do_session" "$do_attempt" "$(jq -nc \
    --arg name "$do_name" --arg model "$do_model" --arg effort "$do_effort" \
    --arg wt "$do_wt_path" --arg branch "$do_branch" --argjson reused "$do_reused" --arg commit "$do_commit" \
    --arg settings "$do_settings" --arg pp "$do_prompt_path" --arg sha "$do_prompt_sha" '
    {name: $name, model: $model}
    | if $effort != "" then . + {effort: $effort} else . end
    | . + {remote: false, worktree: $wt, branch: $branch, worktree_reused: $reused}
    | if $reused then . + {worktree_commit: $commit} else . end
    | . + {settings: $settings, prompt_path: $pp, prompt_sha256: $sha}')"

  echo "backgrounded · $bg_id · $do_name"
  echo "session   $do_session (attempt $do_attempt)"
  if [ "$do_reused" = true ]; then
    echo "worktree  $do_wt_path (branch $do_branch, reused at $do_commit)"
  else
    echo "worktree  $do_wt_path (branch $do_branch)"
  fi
  echo "settings  $do_settings"
  echo "prompt    $do_prompt_path"
}

# verb_dispatch <project> <milestone>: refuse unless the plan makes the milestone eligible;
# refuse if a live row already carries its name; then dispatch_one. Rows are read once here.
verb_dispatch() {
  vd_plan=$(plan_of_project "$1") || { vd_st=$?; echo "$vd_plan" >&2; exit $vd_st; }
  printf '%s' "$vd_plan" | plan_row "$2" > /dev/null 2>&1 || { echo "baton: $2 is not in $1's plan" >&2; exit 2; }
  vd_rows=$(rows_json)
  if ! printf '%s' "$vd_plan" | plan_eligible | grep -Fqx "$2"; then
    vd_inflight=$(derive_in_flight "$1" "$vd_rows") || { echo "baton: $vd_inflight" >&2; exit 1; }
    vd_inflight=$(printf '%s' "$vd_inflight" | jq -c .in_flight)
    echo "baton: $2 is not eligible; the plan reads:" >&2
    printf '%s' "$vd_plan" | plan_render "$1" "$vd_inflight" | awk -v id="$2" '$1 == id' >&2
    exit 2
  fi
  vd_name=$(session_name "$1" "$2")
  if printf '%s' "$vd_rows" | jq -e --arg n "$vd_name" 'any(.[]; .name == $n and .pid != null)' > /dev/null; then
    echo "baton: a live session named \"$vd_name\" already exists; nothing dispatched" >&2
    exit 2
  fi
  dispatch_one "$1" "$2" "$vd_plan" "$vd_rows"
}
