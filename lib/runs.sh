#!/bin/sh
# Durable run identity. A prepared run reserves its lane even if the launch result is unknown.
set -eu
id_ok() { printf '%s' "$1" | grep -Eq '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$'; }
runs_json() {
  log_json | jq -c '
    . as $events
    | [.[] | select(.kind=="dispatch_prepared") | . as $p
      | [$events[] | select(.run==$p.run)] as $e
      | ($e|map(select(.kind=="dispatch"))|last // {}) as $d
      | ($e|map(select(.kind=="worktree_ready"))|last // {}) as $w
      | ($e|map(select(.kind=="ownership"))|last // {}) as $owner
      | $p + $w + $d + {prepared_at:$p.at, owner:($owner.owner // $p.owner // "baton"),
          release_hash:($owner.release_hash // ""),
          release_uuid:($owner.release_uuid // ""),
          state:(if any($e[]; .kind=="abandoned") then "abandoned"
                 elif any($e[]; .kind=="consumed" and .outcome=="complete") then "complete"
                 elif ($d|length)>0 then "active"
                 elif any($e[]; .kind=="launch_started") then "uncertain" else "prepared" end)}]'
}
run_get() {
  id_ok "$1" || { echo 'baton: invalid run id' >&2; return 2; }
  runs_json | jq -ce --arg r "$1" '.[]|select(.run==$r)'
}
run_open() { runs_json | jq -c '[.[]|select(.state!="complete" and .state!="abandoned")]'; }
run_event() {
  re_kind=$1; re_run=$(run_get "$2") || return 1; re_fields=${3:-'{}'}
  re_fields=$(printf '%s' "$re_run" | jq -c --argjson f "$re_fields" '{run,episode}+$f') || return 1
  log_event "$re_kind" "$(printf '%s' "$re_run"|jq -r .project)" "$(printf '%s' "$re_run"|jq -r .milestone)" \
    "$(printf '%s' "$re_run"|jq -r '.session // ""')" "$(printf '%s' "$re_run"|jq -r .attempt)" "$re_fields"
}
run_guard() {
  rg_run=$(run_get "$1") || return 1
  printf '%s' "$rg_run" | jq -e '.owner=="baton" and (.state=="active")' >/dev/null \
    || { echo 'baton: run is not active and automatically owned; claim/release explicitly' >&2; return 1; }
  rg_sid=$(printf '%s' "$rg_run"|jq -r .session)
  rg_file=$(transcript_of "$rg_sid") || { echo 'baton: transcript unavailable; ownership is uncertain' >&2; return 1; }
  rg_hashes=$(typed_hashes "$rg_file") || { echo 'baton: transcript unreadable; ownership is uncertain' >&2; return 1; }
  rg_latest=$(printf '%s\n' "$rg_hashes"|tail -1|awk '{print $3}')
  rg_uuid=$(printf '%s\n' "$rg_hashes"|tail -1|awk '{print $2}')
  rg_count=$(printf '%s\n' "$rg_hashes"|awk 'NF {n++} END {print n+0}')
  [ -n "$rg_latest" ] || { echo 'baton: no typed record; ownership is uncertain' >&2; return 1; }
  [ -n "$rg_uuid" ] && [ "$rg_uuid" != - ] || { echo 'baton: typed record identity is unavailable' >&2; return 1; }
  printf '%s' "$rg_run" | jq -e --arg h "$rg_latest" --arg u "$rg_uuid" --argjson n "$rg_count" 'if .release_uuid!="" then .release_uuid==$u else $n==1 and .prompt_sha256==$h end' >/dev/null \
    || { echo 'baton: human intervention detected; claim and release the run explicitly' >&2; return 1; }
}
verb_ownership() {
  vo_mode=$1; vo_run=$(run_get "$2") || { echo 'baton: unknown run' >&2; return 1; }
  vo_hash=''; vo_uuid=''
  if [ "$vo_mode" = release ]; then
    vo_sid=$(printf '%s' "$vo_run" | jq -r '.session // empty')
    if [ -n "$vo_sid" ]; then
      vo_file=$(transcript_of "$vo_sid") || { echo 'baton: no transcript; cannot release ownership' >&2; return 1; }
      vo_typed=$(typed_hashes "$vo_file") || return 1
      vo_hash=$(printf '%s\n' "$vo_typed"|tail -1|awk '{print $3}')
      vo_uuid=$(printf '%s\n' "$vo_typed"|tail -1|awk '{print $2}')
      [ -n "$vo_uuid" ] && [ "$vo_uuid" != - ] || { echo 'baton: typed record identity unavailable' >&2; return 1; }
      [ -n "$vo_hash" ] || { echo 'baton: no typed record; cannot release ownership' >&2; return 1; }
    fi
    vo_owner=baton
  else vo_owner=human; fi
  run_event ownership "$2" "$(jq -nc --arg o "$vo_owner" --arg h "$vo_hash" --arg u "$vo_uuid" '{owner:$o,release_hash:$h,release_uuid:$u}')"
  printf '%s owned by %s\n' "$2" "$vo_owner"
}
# No observation can prove that a timed-out launch will never appear. Abandon is an explicit
# human disposition, requires a reason and a healthy absent fleet, and never deletes work.
verb_abandon() {
  va_run=$(run_get "$1") || return 1
  [ -n "$2" ] || { echo 'baton: abandonment requires a reason' >&2; return 2; }
  va_rows=$(rows_json) || return 1
  printf '%s' "$va_rows" | jq -e --arg n "$(printf '%s' "$va_run"|jq -r .name)" --arg s "$(printf '%s' "$va_run"|jq -r '.session // ""')" \
    --arg w "$(printf '%s' "$va_run"|jq -r .worktree)" 'all(.[]; .pid==null or (.name!=$n and .sessionId!=$s and .cwd!=$w))' >/dev/null \
    || { echo 'baton: a matching process is still live' >&2; return 1; }
  run_event abandoned "$1" "$(jq -nc --arg r "$2" --arg e "abandoned:$1" '{reason:$r,event_id:$e}')"
}
dispatch_ack() {
  da_run=$(run_get "$1") || return 1; da_row=$2
  da_fields=$(printf '%s' "$da_run" | jq -c --argjson row "$da_row" \
    '{run,episode,name,model,effort,remote,worktree,branch,base_commit,plan_revision,settings,prompt_path,prompt_sha256,runtime_version}
     + {session:$row.sessionId,job:$row.id,event_id:("dispatch:"+.run)}') || return 1
  log_event dispatch "$(printf '%s' "$da_run"|jq -r .project)" "$(printf '%s' "$da_run"|jq -r .milestone)" \
    "$(printf '%s' "$da_row"|jq -r .sessionId)" "$(printf '%s' "$da_run"|jq -r .attempt)" "$da_fields"
}
reconcile_dispatches() {
  rd_rows=$1; rd_pending=$(run_open | jq -c '.[]|select(.state=="uncertain" or (.state=="prepared" and .adopted==true))')
  while IFS= read -r rd_run; do
    [ -n "$rd_run" ] || continue
    rd_matches=$(printf '%s' "$rd_rows"|jq -c --arg n "$(printf '%s' "$rd_run"|jq -r .name)" \
      --arg w "$(printf '%s' "$rd_run"|jq -r .worktree)" --arg s "$(printf '%s' "$rd_run"|jq -r '.session // ""')" '[.[]|select(.name==$n and .cwd==$w and ($s=="" or .sessionId==$s))]')
    if [ "$(printf '%s' "$rd_matches"|jq length)" -eq 1 ]; then
      dispatch_ack "$(printf '%s' "$rd_run"|jq -r .run)" "$(printf '%s' "$rd_matches"|jq -c '.[0]')" || return 1
    else
      printf 'uncertain %s: %s matching rows; nothing launched\n' "$(printf '%s' "$rd_run"|jq -r .run)" "$(printf '%s' "$rd_matches"|jq length)"
    fi
  done <<ROWS
$rd_pending
ROWS
}

verb_adopt() {
  ad_plan=$(plan_of_project "$1") || { echo "$ad_plan" >&2; return 1; }
  printf '%s' "$ad_plan"|plan_eligible|grep -Fqx "$2" || { echo 'baton: adoption requires an eligible milestone' >&2; return 2; }
  ad_path=$(project_path "$1")
  jq -e '.contract==2' "$BATON_HOME/projects/$1/project.json" >/dev/null || return 2
  run_open|jq -e --arg p "$1" 'all(.[];.project!=$p)' >/dev/null || { echo 'baton: project already has an open run' >&2; return 1; }
  ad_rows=$(rows_json) || return 1
  ad_matches=$(printf '%s' "$ad_rows"|jq -c --arg s "$3" '[.[]|select(.sessionId==$s and .pid!=null)]')
  [ "$(printf '%s' "$ad_matches"|jq length)" -eq 1 ] || { echo 'baton: adoption requires exactly one live row for the session' >&2; return 1; }
  ad_row=$(printf '%s' "$ad_matches"|jq -c '.[0]')
  ad_wt=$(printf '%s' "$ad_row"|jq -er .cwd) || return 1
  ad_top=$(baton_git -C "$ad_wt" rev-parse --show-toplevel) || return 1
  ad_top=$(cd "$ad_top" && pwd -P) || return 1
  ad_canonical=$(baton_git -C "$ad_path" rev-parse --show-toplevel) || return 1
  ad_canonical=$(cd "$ad_canonical" && pwd -P) || return 1
  [ "$ad_top" != "$ad_canonical" ] && [ "$(cd "$ad_wt" && pwd -P)" = "$ad_top" ] && [ "$(baton_git -C "$ad_wt" rev-parse --path-format=absolute --git-common-dir)" = "$(baton_git -C "$ad_path" rev-parse --path-format=absolute --git-common-dir)" ] \
    || { echo 'baton: adopt only a linked worktree of this project; canonical checkout is read-only to sessions' >&2; return 1; }
  ad_branch=$(baton_git -C "$ad_wt" symbolic-ref --short HEAD) || return 1
  transcript_of "$3" >/dev/null || { echo 'baton: adopted session needs an inspectable transcript' >&2; return 1; }
  ad_version=$(adapter_version) || return 1
  ad_id=$(new_id); ad_episode=$(new_id); ad_attempt=$(attempt_of "$1" "$2"); ad_attempt=$((ad_attempt+1))
  ad_fields=$(printf '%s' "$ad_row"|jq -c --arg run "$ad_id" --arg ep "$ad_episode" --arg path "$ad_path" --arg branch "$ad_branch" \
    --arg ver "$ad_version" --arg rev "$(printf '%s' "$ad_plan"|jq -r .revision)" \
    '{run:$run,episode:$ep,path:$path,base_commit:$rev,plan_revision:$rev,worktree:.cwd,branch:$branch,
      name:(.name // ""),session:.sessionId,model:(.model // "unknown"),remote:false,owner:"human",adopted:true,
      runtime_version:$ver,prompt_path:"",prompt_sha256:"",settings:"",event_id:("prepared:"+$run)}')
  log_event dispatch_prepared "$1" "$2" '' "$ad_attempt" "$ad_fields" || return 1
  dispatch_ack "$ad_id" "$ad_row" || return 1
  printf 'adopted %s (human-owned); update the session to contract 2 before release\n' "$ad_id"
}
