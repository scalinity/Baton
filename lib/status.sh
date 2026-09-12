#!/bin/sh
# Status uses one atomic journal snapshot and a tagged provider observation. It never locks.
set -eu
verb_status() {
  BATON_LOG_SNAPSHOT=$(log_json) || { echo "$BATON_LOG_SNAPSHOT" >&2; return 1; }
  vs_rows=$(rows_observe)
  printf '%s' "$vs_rows" | jq -r 'if .status=="ok" then "provider: available" else "provider: \(.status) — \(.error)" end'
  if [ -f "$BATON_HOME/last-tick" ]; then printf 'last tick: '; cat "$BATON_HOME/last-tick"; else echo 'last tick: not installed'; fi
  echo 'host: lid open or clamshell; gap reporting works only after the controller recovers'
  runs_json | jq -r '.[] | "\(.project)/\(.milestone) · run \(.run) · \(.state) · owner \(.owner) · attempt \(.attempt) · \(.session // "session unacknowledged")"'
  printf '%s' "$BATON_LOG_SNAPSHOT"|jq -r '. as $e | .[] | select(.kind=="escalation") | . as $a
    | select(any($e[];.kind=="resolution" and .escalation_id==$a.event_id)|not)
    | select(any($e[];.kind=="consumed" and .run==$a.run and .outcome=="complete")|not)
    | "attention: \(.run // .milestone) · \(.class) · \(.carries.question // .carries.detail // "inspect artifact")\(if .carries.options then " · options: "+(.carries.options|join(" / ")) else "" end)"'
  printf '%s' "$BATON_LOG_SNAPSHOT"|jq -r '[.[]|select(.kind=="consumed")]|group_by(.run)|map(last)|.[]|select(.outcome=="stopped")|"stopped: \(.run // .milestone) · \(.reason) · \(.archive)"'
  printf '%s' "$BATON_LOG_SNAPSHOT"|jq -r '. as $log | .[]|select(.kind=="dispatch" and .run==null) | select(. as $d|any($log[];.kind=="consumed" and .session==$d.session and .outcome=="complete")|not) | "legacy: \(.project)/\(.milestone) · \(.session) · explicit adoption required"'
  for vs_dir in inbox processing rejected; do
    for vs_file in "$BATON_HOME/$vs_dir"/*; do
      [ -f "$vs_file" ] || continue
      printf '%s: %s\n' "$vs_dir" "$(basename "$vs_file")"
    done
  done
  for vs_file in "$BATON_HOME"/archive/*.json; do
    [ -f "$vs_file" ] || continue
    if ! printf '%s' "$BATON_LOG_SNAPSHOT"|jq -e --arg p "$vs_file" 'any(.[];.kind=="consumed" and .archive==$p)' >/dev/null; then
      printf 'unrecorded archive: %s · manual migration/inspection required\n' "$vs_file"
    fi
  done
  printf '%s' "$BATON_LOG_SNAPSHOT"|jq -r '. as $e | .[]|select(.kind=="integration_prepared")|. as $i|select(any($e[];.run==$i.run and .kind=="integrated")|not)|"integration pending: \(.run) · \(.integration_worktree)"'
  unset BATON_LOG_SNAPSHOT
}
