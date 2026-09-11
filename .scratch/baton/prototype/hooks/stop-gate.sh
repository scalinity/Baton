#!/bin/sh
# Stop gate (throwaway fixture). Insist once that a handover artifact exists,
# then record the stop and let the turn end.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"')
active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')
artifact="$HOME/.baton/inbox/${BATON_MILESTONE}-${sid}.json"
if [ -f "$artifact" ]; then seen=yes; else seen=no; fi

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" \
  --arg artifact "$artifact" --arg seen "$seen" --arg active "$active" \
  '{at:$at,event:"Stop",milestone:$ms,project:$pj,artifact:$artifact,artifact_seen:$seen,stop_hook_active:$active,payload:.}' \
  >> "$OBS/stop.jsonl"

if [ "$seen" = yes ]; then
  exit 0
fi

if [ "$active" = "true" ]; then
  # Already insisted once. Record the stop ourselves rather than blocking again.
  printf '{"milestone":"%s","project":"%s","session":"%s","outcome":"no-handover","at":"%s"}\n' \
    "${BATON_MILESTONE-}" "${BATON_PROJECT-}" "$sid" "$now" \
    > "$OBS/no-handover-${sid}.json"
  exit 0
fi

jq -nc --arg r "You have not written your handover artifact yet. Write ${artifact} (write ${artifact}.tmp first, then rename it into place), print its contents verbatim, and then you may stop." \
  '{decision:"block",reason:$r}'
exit 0
