#!/bin/sh
# PermissionDenied (throwaway fixture). Record the refusal and its reason.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" \
  '{at:$at,event:"PermissionDenied",milestone:$ms,project:$pj,
    tool_name:(.tool_name // null),reason:(.reason // null),
    tool_input:(.tool_input // null),payload:.}' \
  >> "$OBS/permissiondenied.jsonl"
exit 0
