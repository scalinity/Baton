#!/bin/sh
# lib/log.sh — the dispatch log's one writer, the envelope, the one reader, the attempt derivation,
# the rows listing, the prompt sidecar and its hash. Nothing else in Baton writes log.jsonl (INV-02).
set -eu

# Baton's own clock: ISO 8601 with offset, 2026-09-11T23:14:02+01:00.
baton_now() {
  "$BATON_DATE" +%Y-%m-%dT%H:%M:%S%z | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

# log_event <kind> <project> <milestone> <session> <attempt> [<fields json>]
# Composes one line — the envelope plus the event's own fields — and appends it with one write.
# An empty envelope argument is absent from the line, never null. Refuses without the lock, and
# refuses a line of 4 KB or more: a writer bounds its own fields (see dispatch_failed) and this is
# the last defence.
log_event() {
  ev_kind=$1; ev_project=$2; ev_milestone=$3; ev_session=$4; ev_attempt=$5; ev_fields=${6:-'{}'}
  if [ ! -d "$BATON_HOME/lock" ]; then
    echo "log_event: refused, the lock is not held" >&2
    return 1
  fi
  ev_line=$(jq -nc --arg at "$(baton_now)" --arg kind "$ev_kind" \
    --arg p "$ev_project" --arg m "$ev_milestone" --arg s "$ev_session" --arg a "$ev_attempt" \
    --argjson f "$ev_fields" '
    {at: $at, kind: $kind}
    | if $p != "" then . + {project: $p} else . end
    | if $m != "" then . + {milestone: $m} else . end
    | if $s != "" then . + {session: $s} else . end
    | if $a != "" then . + {attempt: ($a | tonumber)} else . end
    | . + $f')
  ev_bytes=$(printf '%s\n' "$ev_line" | wc -c | tr -d ' ')
  if [ "$ev_bytes" -ge 4096 ]; then
    echo "log_event: refused, the line is $ev_bytes bytes and the limit is 4 KB" >&2
    return 1
  fi
  printf '%s\n' "$ev_line" >> "$BATON_HOME/log.jsonl"
}

# log_json: the log as one JSON array; [] when there is no log yet. The one reader every
# derivation goes through. A line that does not parse fails the read naming the line, because a
# derivation over a torn file would be a derivation over a guess.
log_json() {
  lj_log=$BATON_HOME/log.jsonl
  if [ ! -f "$lj_log" ]; then echo '[]'; return 0; fi
  if lj_out=$(jq -sc . "$lj_log" 2>/dev/null); then printf '%s\n' "$lj_out"; return 0; fi
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
    '[ .[] | select(.kind == "dispatch" and .project == $p and .milestone == $m) ] | length'
}

# widenings_json <project>: the project's widening events, newest first, as a JSON array.
widenings_json() {
  wj_log=$(log_json) || { echo "$wj_log"; return 1; }
  printf '%s' "$wj_log" | jq -c --arg p "$1" '[ .[] | select(.kind == "widening" and .project == $p) ] | reverse'
}

# rows_json: claude agents --json as a JSON array; [] when the listing cannot be read or is empty.
rows_json() {
  rj_out=$("$BATON_CLAUDE" agents --json 2>/dev/null) || rj_out='[]'
  [ -n "$rj_out" ] || rj_out='[]'
  printf '%s' "$rj_out" | jq -c 'if type == "array" then . else [] end' 2>/dev/null || echo '[]'
}

# inflight_json <project> <rows json>: the newest dispatch event of every milestone of the project
# whose session has a live row (a pid), as a JSON array. M02's derivation 1 replaces this.
inflight_json() {
  ij_log=$(log_json) || { echo "$ij_log"; return 1; }
  printf '%s' "$ij_log" | jq -c --arg p "$1" --argjson rows "$2" '
    [ .[] | select(.kind == "dispatch" and .project == $p) ]
    | group_by(.milestone) | map(last)
    | map(select(.session as $s | any($rows[]; .pid != null and .sessionId == $s)))'
}

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
