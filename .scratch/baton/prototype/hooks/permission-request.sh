#!/bin/sh
# PermissionRequest (throwaway fixture). RECORD ONLY — returns no decision.
# This is the item 26 gate: if the prompt is denied rather than left open,
# PermissionRequest cannot be Baton's recorder.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" \
  '{at:$at,event:"PermissionRequest",milestone:$ms,project:$pj,
    tool_name:(.tool_name // null),tool_input:(.tool_input // null),
    permission_suggestions:(.permission_suggestions // null),payload:.}' \
  >> "$OBS/permissionrequest.jsonl"

# No stdout, exit 0: no decision returned.
exit 0
