#!/bin/sh
# Integration is an exclusive, journaled operation. Workers prepare commits; only this command
# changes the canonical checkout. The exact combined commit is checked before promotion.
set -eu
integration_record() {
  log_json | jq -ce --arg r "$1" --arg k "$2" '
    [to_entries[]|{i:.key}+.value|select(.run==$r)] as $e
    | ($e|map(select(.kind=="integration_retry"))|last|.i // -1) as $reset
    | [$e[]|select(.kind==$k and .i>$reset)]|last|if .==null then empty else del(.i) end'
}
canonical_ready() {
  [ "$(baton_git -C "$1" symbolic-ref --short HEAD)" = main ] && [ -z "$(baton_git -C "$1" status --porcelain)" ] \
    || { echo 'baton: canonical checkout must be clean and on main' >&2; return 1; }
}
integration_check() (
  ci_dir=$1; ci_check=$2
  set --
  while IFS= read -r ci_arg; do set -- "$@" "$ci_arg"; done <<ARGS
$(printf '%s' "$ci_check"|jq -r '.[]')
ARGS
  [ "$#" -gt 0 ] || exit 2
  cd "$ci_dir"
  bounded_call "${BATON_CHECK_SECONDS:-1800}" check "$@"
)
verb_integrate() {
  vi_run=$(run_get "$1") || return 1
  run_guard "$1" || return 1
  if [ "${2:-}" = --retry ]; then
    if integration_record "$1" integrated >/dev/null || integration_record "$1" integration_checked >/dev/null; then
      echo 'baton: checked or promoted integration cannot be superseded; reconcile it first' >&2; return 1
    fi
    run_event integration_retry "$1" '{"reason":"explicit retry of unverified integration"}' || return 1
  fi
  vi_path=$(printf '%s' "$vi_run"|jq -r .path)
  vi_wt=$(printf '%s' "$vi_run"|jq -r .worktree)
  vi_branch=$(printf '%s' "$vi_run"|jq -r .branch)
  vi_project=$(printf '%s' "$vi_run"|jq -r .project)
  vi_milestone=$(printf '%s' "$vi_run"|jq -r .milestone)
  if vi_done=$(integration_record "$1" integrated); then printf '%s\n' "$vi_done"; return; fi
  canonical_ready "$vi_path" || return 1
  if ! vi_intent=$(integration_record "$1" integration_prepared); then
    vi_op=$(new_id)
    vi_dir=$BATON_HOME/integrations/$1/$vi_op
    mkdir -p "$vi_dir"
    [ "$(baton_git -C "$vi_wt" symbolic-ref --short HEAD)" = "$vi_branch" ] && [ -z "$(baton_git -C "$vi_wt" status --porcelain)" ] \
      || { echo 'baton: candidate worktree must be clean on the recorded branch' >&2; return 1; }
    vi_candidate=$(baton_git -C "$vi_path" rev-parse "refs/heads/$vi_branch^{commit}") || return 1
    vi_expected=$(baton_git -C "$vi_path" rev-parse main)
    vi_check=$(jq -ce 'select(.checkReplaySafe==true)|.check|select(type=="array" and length>0 and all(.[];type=="string" and (contains("\n")|not) and (contains("\u0000")|not)))' "$BATON_HOME/projects/$vi_project/project.json") || return 1
    vi_fields=$(jq -nc --arg c "$vi_candidate" --arg m "$vi_expected" --arg w "$vi_dir/worktree" --argjson check "$vi_check" --arg eid "integration-prepared:$vi_op" \
      '{candidate:$c,expected_main:$m,integration_worktree:$w,check:$check,event_id:$eid}')
    run_event integration_prepared "$1" "$vi_fields" || return 1
    vi_intent=$(integration_record "$1" integration_prepared)
  fi
  vi_candidate=$(printf '%s' "$vi_intent"|jq -r .candidate)
  vi_expected=$(printf '%s' "$vi_intent"|jq -r .expected_main)
  vi_iwt=$(printf '%s' "$vi_intent"|jq -r .integration_worktree)
  vi_dir=$(dirname "$vi_iwt"); vi_op=$(basename "$vi_dir")
  if ! vi_checked=$(integration_record "$1" integration_checked); then
    [ "$(baton_git -C "$vi_path" rev-parse main)" = "$vi_expected" ] || { echo 'baton: main changed; integration requires inspection' >&2; return 1; }
    if [ ! -d "$vi_iwt" ]; then baton_git -C "$vi_path" worktree add --detach "$vi_iwt" "$vi_expected" || return 1; fi
    [ "$(baton_git -C "$vi_iwt" rev-parse --path-format=absolute --git-common-dir)" = "$(baton_git -C "$vi_path" rev-parse --path-format=absolute --git-common-dir)" ] \
      && [ -z "$(baton_git -C "$vi_iwt" status --porcelain)" ] || { echo 'baton: integration worktree is dirty or foreign; inspect it' >&2; return 1; }
    baton_git -C "$vi_iwt" merge --no-ff --no-edit "$vi_candidate" || { echo 'baton: integration conflict preserved for inspection' >&2; return 1; }
    vi_commit=$(baton_git -C "$vi_iwt" rev-parse HEAD)
    vi_planpath=$(jq -r .plan "$BATON_HOME/projects/$vi_project/project.json")
    vi_plan=$(plan_tables "$vi_iwt/$vi_planpath") || { echo "$vi_plan" >&2; return 1; }
    printf '%s' "$vi_plan"|plan_row "$vi_milestone"|jq -e '.status=="done"' >/dev/null \
      || { echo 'baton: candidate does not mark its milestone done' >&2; return 1; }
    awk '/^## Completion evidence/ {found=1;next} found && /^## / {exit} found && /[^[:space:]]/ {evidence=1} END {exit !evidence}' "$vi_iwt/docs/milestones/$vi_milestone.md" \
      || { echo 'baton: candidate has no completion evidence' >&2; return 1; }
    # Checks must be replay-safe: an interrupted check has no success receipt and runs again.
    integration_check "$vi_iwt" "$(printf '%s' "$vi_intent"|jq -c .check)" > "$vi_dir/check.out" 2> "$vi_dir/check.err" \
      || { echo "baton: standing check failed; see $vi_dir/check.err" >&2; return 1; }
    [ "$(baton_git -C "$vi_iwt" rev-parse HEAD)" = "$vi_commit" ] && [ -z "$(baton_git -C "$vi_iwt" status --porcelain)" ] \
      || { echo 'baton: standing check changed the verified tree; refusing promotion' >&2; return 1; }
    vi_fields=$(jq -nc --arg c "$vi_commit" --arg candidate "$vi_candidate" --arg m "$vi_expected" \
      --arg tree "$(baton_git -C "$vi_iwt" rev-parse HEAD^{tree})" --arg e "integration-checked:$vi_op" \
      '{integrated_commit:$c,candidate:$candidate,expected_main:$m,verified_tree:$tree,event_id:$e}')
    run_event integration_checked "$1" "$vi_fields" || return 1
    vi_checked=$(integration_record "$1" integration_checked)
  fi
  vi_commit=$(printf '%s' "$vi_checked"|jq -r .integrated_commit)
  canonical_ready "$vi_path" || return 1
  vi_main=$(baton_git -C "$vi_path" rev-parse main)
  if ! baton_git -C "$vi_path" merge-base --is-ancestor "$vi_commit" "$vi_main"; then
    [ "$vi_main" = "$vi_expected" ] || { echo 'baton: main changed since verification; refusing promotion' >&2; return 1; }
    run_guard "$1" || return 1
    baton_git -C "$vi_path" merge --ff-only "$vi_commit" || return 1
  fi
  canonical_ready "$vi_path" || return 1
  baton_git -C "$vi_path" merge-base --is-ancestor "$vi_commit" main || return 1
  vi_fields=$(printf '%s' "$vi_checked"|jq -c --arg e "integrated:$vi_op" '{integrated_commit,candidate,expected_main,verified_tree} + {event_id:$e}')
  run_event integrated "$1" "$vi_fields" || return 1
  integration_record "$1" integrated
}
