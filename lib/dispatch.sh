#!/bin/sh
# Prepare identified runs, compose pinned settings, validate worktrees and launch through the adapter.
set -eu

# worktree_ensure <path> <milestone>: ../<Project>-<milestone> on branch <milestone lowercased>,
# created from main; reused if it exists, recording the commit it stands at. Prints
# {"worktree","branch","reused","commit"}.
worktree_ensure() {
  we_path=$1; we_id=$2
  we_wt=$(dirname "$we_path")/$(basename "$we_path")-$we_id
  we_branch=codex/$(printf '%s' "$we_id" | tr 'A-Z' 'a-z')
  if [ -d "$we_wt" ]; then
    we_reused=true
    we_commit=$(baton_git -C "$we_wt" rev-parse HEAD 2>&1) || { echo "$we_wt exists but is not a worktree: $we_commit"; return 1; }
    [ "$(baton_git -C "$we_wt" rev-parse --path-format=absolute --git-common-dir)" = "$(baton_git -C "$we_path" rev-parse --path-format=absolute --git-common-dir)" ] \
      && [ "$(baton_git -C "$we_wt" symbolic-ref --short HEAD)" = "$we_branch" ] \
      || { echo "$we_wt belongs to another repository or branch"; return 1; }
  else
    we_reused=false
    if baton_git -C "$we_path" show-ref --verify --quiet "refs/heads/$we_branch"; then
      we_out=$(baton_git -C "$we_path" worktree add "$we_wt" "$we_branch" 2>&1) || { echo "$we_out"; return 1; }
    else
      we_out=$(baton_git -C "$we_path" worktree add "$we_wt" -b "$we_branch" "${3:-main}" 2>&1) || { echo "$we_out"; return 1; }
    fi
    we_commit=$(baton_git -C "$we_wt" rev-parse HEAD)
  fi
  [ -z "$(baton_git -C "$we_wt" status --porcelain)" ] && baton_git -C "$we_wt" merge-base --is-ancestor "${3:-main}" HEAD \
    || { echo "$we_wt must be clean and include the dispatch revision; preserve and reconcile its work first"; return 1; }
  jq -nc --arg w "$we_wt" --arg b "$we_branch" --argjson r "$we_reused" --arg c "$we_commit" \
    '{worktree: $w, branch: $b, reused: $r, commit: $c}'
}

# settings_compose <project> <milestone>: the dispatched settings file at
# settings/<project>-<milestone>.json from the project's permissions.json: the mode as
# documentation, allow and deny copied, no ask rules, the three hooks carrying Baton's home, the
# project key and the milestone on their command lines and pointing at the installed relay. A
# permissions.json without deny rules fails the stage: a bypassPermissions session without the
# rail is not dispatched. Prints the path.
settings_compose() {
  sc_perm=$BATON_HOME/projects/$1/permissions.json
  sc_out=$BATON_HOME/settings/$3.json
  [ -f "$sc_perm" ] || { echo "$sc_perm is missing"; return 1; }
  sc_env="BATON_HOME=$(shell_quote "$BATON_HOME") BATON_PROJECT=$(shell_quote "$1") BATON_MILESTONE=$(shell_quote "$2") BATON_RUN=$(shell_quote "$3")"
  sc_json=$(jq -e --arg env "$sc_env" --arg hooks "$BATON_RELEASE_ROOT/hooks" '
    if ((.permissions.deny // []) | type!="array" or length==0 or (all(.[];type=="string")|not))
      then error("permissions.deny must be a nonempty string array") else . end
    | { permissions: { defaultMode: "bypassPermissions",
                       deny: .permissions.deny },
        statusLine: { type: "command", command: ("\($env) " + ($hooks+"/statusline"|@sh)) },
        hooks: {
          Stop:        [{ hooks: [{ type: "command", command: ("\($env) " + ($hooks+"/stop-gate"|@sh)) }] }],
          StopFailure: [{ hooks: [{ type: "command", command: ("\($env) " + ($hooks+"/stop-failure"|@sh)) }] }] } }' \
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
  pb_text=$(baton_git -C "$1" show "${4:-main}:$2" 2>&1) || { echo "brief $2 is not at the dispatch revision: $pb_text"; return 1; }
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
    /^WHAT ELSE IS IN FLIGHT\./ { print ENVIRON["REP"]; skipping = 1; replaced++; next }
    skipping && !/^[ \t]*$/ { next }
    skipping { skipping = 0 }
    { print }
    END { exit (replaced == 1 ? 0 : 1) }') || { echo "the prompt must have exactly one paragraph beginning WHAT ELSE IS IN FLIGHT."; return 1; }
  printf '%s' "$sl_out"
}

# claude_bg <worktree> <name> <model> <effort> <settings> <prompt>: the one command, with the
# worktree as cwd and LC_ALL set. Sets bg_status, bg_stdout, bg_stderr and bg_id (empty when no
# "backgrounded · <id>" line was printed, which is the failure test).
claude_bg() {
  cb_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-bg.XXXXXX")
  set +e
  ( cd "$1" && LC_ALL=en_US.UTF-8 adapter_call --bg -n "$2" --model "$3" ${4:+--effort "$4"} \
      --permission-mode bypassPermissions --settings "$5" "$6" ) > "$cb_tmp" 2> "$cb_tmp.err"
  bg_status=$?
  set -e
  bg_stdout=$(cat "$cb_tmp"); bg_stderr=$(cat "$cb_tmp.err")
  rm -f "$cb_tmp" "$cb_tmp.err"
}

# All dispatch effects follow a durable prepared record. Any ambiguous launch reserves the lane.
dispatch_one() {
  do_project=$1; do_id=$2; do_plan=$3; do_rows=$4
  do_path=$(project_path "$do_project") || return 1
  do_row=$(printf '%s' "$do_plan"|plan_row "$do_id") || return 1
  [ "$(printf '%s' "$do_row"|jq -r .remote)" = false ] || { echo 'baton: remote dispatch awaits the versioned adapter milestone' >&2; return 2; }
  jq -e '.contract==2 and (.check|type)=="array" and (.check|length)>0 and all(.check[];type=="string")' "$BATON_HOME/projects/$do_project/project.json" >/dev/null \
    || { echo 'baton: project needs contract 2 and an explicit standing-check argv' >&2; return 2; }
  jq -e '.trustedLocal==true' "$BATON_HOME/config.json" >/dev/null \
    || { echo 'baton: trustedLocal must be explicitly enabled; deny patterns are not a sandbox' >&2; return 2; }
  do_version=$(adapter_version) || return 1
  do_run=$(new_id)
  do_revision=$(printf '%s' "$do_plan"|jq -r .revision)
  do_attempt=$(attempt_of "$do_project" "$do_id") || return 1
  do_attempt=$((do_attempt+1))
  do_episode=$(log_json|jq -r --arg p "$do_project" --arg m "$do_id" '[.[]|select(.project==$p and .milestone==$m and .kind=="dispatch_prepared")]|last|.episode // empty')
  [ -n "$do_episode" ] || do_episode=$(new_id)
  do_model=$(printf '%s' "$do_row"|jq -r .model)
  do_effort=$(printf '%s' "$do_row"|jq -r .effort)
  do_name="$(session_name "$do_project" "$do_id") · $do_run"
  do_wt_path=$(dirname "$do_path")/$(basename "$do_path")-$do_id
  do_branch=codex/$(printf '%s' "$do_id"|tr 'A-Z' 'a-z')
  do_brief=docs/milestones/$do_id.md
  do_prompt=$(prompt_from_brief "$do_path" "$do_brief" 'Copy-ready session prompt' "$do_revision") || { echo "$do_prompt" >&2; return 1; }
  do_prompt=$(slot_line "$do_prompt" "WHAT ELSE IS IN FLIGHT. Run $do_run; work only in $do_wt_path on $do_branch. Canonical checkout $do_path is read-only to sessions. Do not merge there, refresh successor prompts, or delete worktrees. Prepare your candidate commit including completion evidence and the done cell; request integration with baton integrate $do_run. Publish contract-2 artifacts with run $do_run and a stable message_id. Read CONTRACT.md at the dispatch revision $do_revision. Do not start another milestone.") || return 1
  mkdir -p "$BATON_HOME/runs/$do_run"
  do_prompt_path=$BATON_HOME/runs/$do_run/prompt.txt
  printf '%s\n' "$do_prompt" > "$do_prompt_path"
  do_sha=$(prompt_sha256 "$do_prompt_path")
  do_settings=$(settings_compose "$do_project" "$do_id" "$do_run") || { echo "$do_settings" >&2; return 1; }
  do_fields=$(jq -nc --arg run "$do_run" --arg ep "$do_episode" --arg n "$do_name" --arg model "$do_model" --arg effort "$do_effort" \
    --arg path "$do_path" --arg rev "$do_revision" --arg wt "$do_wt_path" --arg b "$do_branch" --arg set "$do_settings" \
    --arg pp "$do_prompt_path" --arg sha "$do_sha" --arg ver "$do_version" \
    '{run:$run,episode:$ep,name:$n,model:$model,effort:$effort,remote:false,path:$path,base_commit:$rev,plan_revision:$rev,
      worktree:$wt,branch:$b,settings:$set,prompt_path:$pp,prompt_sha256:$sha,runtime_version:$ver,owner:"baton",event_id:("prepared:"+$run)}')
  log_event dispatch_prepared "$do_project" "$do_id" '' "$do_attempt" "$do_fields" || return 1
  do_wt=$(worktree_ensure "$do_path" "$do_id" "$do_revision") || { echo "baton: run $do_run prepared but worktree failed: $do_wt" >&2; return 1; }
  run_event worktree_ready "$do_run" "$(printf '%s' "$do_wt"|jq -c --arg e "worktree:$do_run" '{starting_commit:.commit,event_id:$e}')" || return 1
  run_event launch_started "$do_run" "$(jq -nc --arg id "launch:$do_run" '{event_id:$id}')" || return 1
  claude_bg "$do_wt_path" "$do_name" "$do_model" "$do_effort" "$do_settings" "$do_prompt"
  printf '%s\n' "$bg_stdout" > "$BATON_HOME/runs/$do_run/launch.stdout"
  printf '%s\n' "$bg_stderr" > "$BATON_HOME/runs/$do_run/launch.stderr"
  run_event launch_observed "$do_run" "$(jq -nc --argjson code "$bg_status" --arg out "$BATON_HOME/runs/$do_run/launch.stdout" \
    --arg err "$BATON_HOME/runs/$do_run/launch.stderr" --arg e "launch-observed:$do_run" '{exit:$code,stdout:$out,stderr:$err,event_id:$e}')" || return 1
  do_observation=$(rows_observe)
  if [ "$(printf '%s' "$do_observation"|jq -r .status)" = ok ]; then
    reconcile_dispatches "$(printf '%s' "$do_observation"|jq -c .rows)" || return 1
  fi
  do_state=$(run_get "$do_run")
  if [ "$(printf '%s' "$do_state"|jq -r .state)" != active ]; then
    printf 'baton: run %s launch uncertain; reconcile or explicitly abandon it; never blindly retry (details: %s/runs/%s/launch.stderr)\n' "$do_run" "$BATON_HOME" "$do_run" >&2
    return 1
  fi
  printf 'dispatched %s · %s\n' "$do_run" "$do_name"
}
verb_dispatch() {
  vd_plan=$(plan_of_project "$1") || { echo "$vd_plan" >&2; return 1; }
  printf '%s' "$vd_plan"|plan_row "$2" >/dev/null || { echo 'baton: milestone not found' >&2; return 2; }
  printf '%s' "$vd_plan"|plan_eligible|grep -Fqx "$2" || { echo 'baton: milestone is not eligible' >&2; return 2; }
  vd_rows=$(rows_json) || return 1
  vd_open=$(run_open)
  printf '%s' "$vd_open"|jq -e --arg p "$1" 'all(.[];.project!=$p)' >/dev/null \
    || { echo 'baton: this project has an open or uncertain run; reconcile it first' >&2; return 2; }
  vd_cap=$(config_num cap 2)
  case "$vd_cap" in ''|*[!0-9]*|0) echo 'baton: cap must be positive' >&2; return 2;; esac
  [ "$(printf '%s' "$vd_open"|jq length)" -lt "$vd_cap" ] || { echo 'baton: global run cap reached' >&2; return 2; }
  vd_path=$(project_path "$1")
  vd_common=$(baton_git -C "$vd_path" rev-parse --path-format=absolute --git-common-dir) || return 1
  vd_live=$(printf '%s' "$vd_rows"|jq -r '.[]|select(.pid!=null)|.cwd')
  while IFS= read -r vd_cwd; do
    [ -n "$vd_cwd" ] || continue
    vd_other=$(baton_git -C "$vd_cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      || { echo 'baton: a live session repository cannot be identified; dispatch held' >&2; return 1; }
    [ "$vd_other" != "$vd_common" ] || { echo 'baton: project has a live session; adopt or finish it first' >&2; return 2; }
  done <<ROWS
$vd_live
ROWS
  dispatch_one "$1" "$2" "$vd_plan" "$vd_rows"
}
