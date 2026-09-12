#!/bin/sh
# Logical append-only journal: one atomic replacement writer, coherent reads and stable event IDs.
# The provider adapter owns observations; nothing else in Baton writes log.jsonl.
set -eu

# Baton's own clock: ISO 8601 with offset, 2026-09-11T23:14:02+01:00.
baton_now() {
  "$BATON_DATE" +%Y-%m-%dT%H:%M:%S%z | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

# log_event <kind> <project> <milestone> <session> <attempt> [<fields json>]
# Composes an event and atomically replaces the journal under the kernel lock. Empty optional
# envelope fields are omitted. Duplicate identity must carry identical content except replay time.
log_event() {
  ev_kind=$1; ev_project=$2; ev_milestone=$3; ev_session=$4; ev_attempt=$5; ev_fields=${6:-'{}'}
  lock_require || return 1
  ev_id=$(printf '%s' "$ev_fields" | jq -r '.event_id // empty')
  [ -n "$ev_id" ] || ev_id=$(new_id)
  ev_line=$(jq -nc --arg at "$(baton_now)" --arg kind "$ev_kind" --arg eid "$ev_id" \
    --arg p "$ev_project" --arg m "$ev_milestone" --arg s "$ev_session" --arg a "$ev_attempt" \
    --argjson f "$ev_fields" '
    {at: $at, kind: $kind}
    | if $p != "" then . + {project: $p} else . end
    | if $m != "" then . + {milestone: $m} else . end
    | if $s != "" then . + {session: $s} else . end
    | if $a != "" then . + {attempt: ($a | tonumber)} else . end
    | . + $f + {event_id:$eid, schema:2}') || return 1
  ev_old=$(log_json) || return 1
  ev_existing=$(printf '%s' "$ev_old" | jq -c --arg id "$ev_id" '[.[]|select(.event_id==$id)]|first // empty')
  if [ -n "$ev_existing" ]; then
    jq -ne --argjson a "$ev_existing" --argjson b "$ev_line" '($a|del(.at)) == ($b|del(.at))' >/dev/null \
      || { echo "baton: conflicting event identity $ev_id" >&2; return 1; }
    return 0
  fi
  # Logical append, atomic physical replacement. A reader sees the old or new complete journal.
  # This deliberately trades O(n) writes for process-crash safety at the current local scale.
  ev_tmp=$(mktemp "$BATON_HOME/.journal.XXXXXX") || return 1
  printf '%s' "$ev_old" | jq -c '.[]' > "$ev_tmp" || { rm -f "$ev_tmp"; return 1; }
  printf '%s\n' "$ev_line" >> "$ev_tmp" || { rm -f "$ev_tmp"; return 1; }
  mv "$ev_tmp" "$BATON_HOME/log.jsonl" || return 1
}

# log_json: the log as one JSON array; [] when there is no log yet. The one reader every
# derivation goes through. A line that does not parse fails the read naming the line, because a
# derivation over a torn file would be a derivation over a guess.
log_json() {
  if [ "${BATON_LOG_SNAPSHOT+x}" ]; then printf '%s\n' "$BATON_LOG_SNAPSHOT"; return; fi
  lj_log=$BATON_HOME/log.jsonl
  if [ ! -f "$lj_log" ]; then echo '[]'; return 0; fi
  if lj_out=$(jq -sce 'if all(.[];type=="object" and (.kind|type)=="string" and (.at|type)=="string") then . else error("invalid event envelope") end' "$lj_log" 2>/dev/null); then printf '%s\n' "$lj_out"; return 0; fi
  lj_n=0
  while IFS= read -r lj_line || [ -n "$lj_line" ]; do
    lj_n=$((lj_n + 1))
    if ! printf '%s' "$lj_line" | jq -e . > /dev/null 2>&1; then
      echo "$lj_log line $lj_n does not parse"
      return 1
    fi
  done < "$lj_log"
  echo "$lj_log does not parse"
  return 1
}

# attempt_of <project> <milestone>: the count of dispatch events for the pair; 0 when none.
# The next dispatch is attempt (attempt_of + 1).
attempt_of() {
  ao_log=$(log_json) || { echo "$ao_log"; return 1; }
  printf '%s' "$ao_log" | jq --arg p "$1" --arg m "$2" \
    '[ .[] | select((.kind == "dispatch_prepared" or (.kind == "dispatch" and .run == null)) and .project == $p and .milestone == $m) ] | length'
}

# widenings_json <project>: the project's widening events, newest first, as a JSON array.
widenings_json() {
  wj_log=$(log_json) || { echo "$wj_log"; return 1; }
  printf '%s' "$wj_log" | jq -c --arg p "$1" '[ .[] | select(.kind == "widening" and .project == $p) ] | reverse'
}

new_id() { /usr/bin/uuidgen | tr 'A-Z' 'a-z'; }
shell_quote() { jq -nr --arg v "$1" '$v|@sh'; }

# prompt_normalise: stdin to stdout, stripping exactly one trailing newline and nothing else.
# The one rule for both sides of the takeover comparison: the sidecar file (which ends in a
# newline because it is a text file) and the transcript record's text (which does not, because
# the CLI stores the argument as given). Proved on the prototype's pairs (M01, item 45; D-025).
prompt_normalise() {
  pn_text=$(cat; printf x)
  pn_text=${pn_text%x}
  pn_nl='
'
  pn_text=${pn_text%"$pn_nl"}
  printf '%s' "$pn_text"
}

# prompt_sha256 <file>: the hash of the file's normalised text.
prompt_sha256() {
  prompt_normalise < "$1" | shasum -a 256 | awk '{ print $1 }'
}

# sidecar_write <session> <text>: writes prompts/<session>/<n>.txt, n = the highest existing
# number + 1, and prints "<path> <sha256>" of the normalised text.
sidecar_write() {
  sw_dir=$BATON_HOME/prompts/$1
  mkdir -p "$sw_dir"
  sw_n=$(ls "$sw_dir" | sed -n 's/^\([0-9][0-9]*\)\.txt$/\1/p' | sort -n | tail -1)
  sw_n=$(( ${sw_n:-0} + 1 ))
  sw_path=$sw_dir/$sw_n.txt
  printf '%s\n' "$2" > "$sw_path"
  printf '%s %s\n' "$sw_path" "$(prompt_sha256 "$sw_path")"
}
