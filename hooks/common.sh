#!/bin/sh
# Hook envelope; turn identity comes from the current assistant UUID, never wall-clock time.
set -eu
BATON_HOME=${BATON_HOME:-$HOME/.baton}
BATON_DATE=${BATON_DATE:-date}
hook_root=$(cd "$(dirname "$0")/.." && pwd -P)
payload=$(cat)
sid=$(printf '%s' "$payload"|jq -er '.session_id|select(type=="string" and test("^[A-Za-z0-9_-]+$"))') || exit 0
[ -n "${BATON_RUN:-}" ] || { echo 'baton: legacy hook has no run identity; migrate the session' >&2; exit 0; }
request=$(jq -sc --arg run "$BATON_RUN" '[.[]|select(.kind=="dispatch_prepared" and .run==$run)]|last // empty' "$BATON_HOME/log.jsonl")
[ -n "$request" ] || { echo 'baton: hook has no prepared run' >&2; exit 0; }
message=$(printf '%s' "$payload"|jq -r '.last_assistant_message // ""')
hook_envelope() {
  he_reason=$1
  he_transcript=$(printf '%s' "$payload"|jq -r '.transcript_path // empty')
  he_turn=''
  if [ -f "$he_transcript" ]; then
    he_turn=$(jq -sr '[.[]|select((.type=="assistant" or .type=="user") and (.uuid|type)=="string")|.uuid]|last // empty' "$he_transcript" 2>/dev/null || true)
  fi
  [ -n "$he_turn" ] || { echo 'baton: stable turn identity unavailable; hook ending requires inspection' >&2; return 1; }
  he_id=$(printf '%s\n' "$BATON_RUN" "$sid" "$he_turn" "$he_reason"|shasum -a 256|awk '{print $1}')
  printf '%s' "$request"|jq -c --arg sid "$sid" --arg id "$he_id" --arg detail "$message" --arg reason "$he_reason" \
    --arg at "$(printf '%s' "$request"|jq -r .at)" \
    '{baton:2,run,message_id:$id,project:.path,milestone,plan_revision,session:$sid,written_at:$at,outcome:"stopped",reason:$reason,detail:$detail}'
}
hook_publish() {
  # A repeated callback uses the first payload for this immutable identity, including written_at.
  hp_json=$1; hp_id=$(printf '%s' "$hp_json"|jq -r .message_id)
  for hp_file in "$BATON_HOME/inbox/$hp_id.json" "$BATON_HOME/archive/$hp_id.json"; do
    if [ -f "$hp_file" ]; then return 0; fi
  done
  hp_existing=$(jq -sc --arg id "$hp_id" 'any(.[];.kind=="consumed" and .message_id==$id)' "$BATON_HOME/log.jsonl")
  [ "$hp_existing" != true ] || return 0
  printf '%s\n' "$hp_json" | "$hook_root/hooks/publish"
}
