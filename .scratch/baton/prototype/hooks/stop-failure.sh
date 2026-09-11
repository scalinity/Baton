#!/bin/sh
# StopFailure (throwaway fixture). Write the api-error artifact.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"')

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" \
  '{at:$at,event:"StopFailure",milestone:$ms,project:$pj,payload:.}' \
  >> "$OBS/stopfailure.jsonl"

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" --arg sid "$sid" \
  '{milestone:$ms,project:$pj,session:$sid,at:$at,outcome:"stopped",error:(.error // "unknown"),
    detail:(.last_assistant_message // ""),error_details:(.error_details // null)}' \
  > "$HOME/.baton/inbox/${BATON_MILESTONE}-${sid}.api-error.json"
exit 0
