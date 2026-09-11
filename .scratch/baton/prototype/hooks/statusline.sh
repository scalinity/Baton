#!/bin/sh
# statusLine (throwaway fixture). Write stdin to ~/.baton/status/<session>.json
# so the rate_limits / resets_at field can be looked for.
OBS=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs
payload=$(cat)
sid=$(printf '%s' "$payload" | jq -r '.session_id // .sessionId // "unknown"')
printf '%s' "$payload" > "$HOME/.baton/status/${sid}.json"
printf '%s' "$payload" | jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{at:$at,event:"statusLine",keys:(keys),payload:.}' >> "$OBS/statusline.jsonl"
printf 'baton %s' "${BATON_MILESTONE-?}"
exit 0
