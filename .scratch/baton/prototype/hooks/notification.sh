#!/bin/sh
# Notification (throwaway fixture). Record message, title and type.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

printf '%s' "$payload" | jq -c \
  --arg at "$now" --arg ms "${BATON_MILESTONE-}" --arg pj "${BATON_PROJECT-}" \
  '{at:$at,event:"Notification",milestone:$ms,project:$pj,
    notification_type:(.notification_type // null),title:(.title // null),
    message:(.message // null),payload:.}' \
  >> "$OBS/notification.jsonl"
exit 0
