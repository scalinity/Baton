#!/bin/sh
# lib/derive.sh — the fifteen recovery derivations of docs/ARCHITECTURE.md §6.4, one function per
# sentence. Each is a pure function of the five inputs — the dispatch log, the rows from
# claude agents --json, the inbox and archive, the plan file and one git check — plus the tick
# marker, the status feed and the transcripts, and each prints exactly one JSON object on stdout
# with its result under a named key, so a reader picks a field and never parses text (D-031).
# Nothing here writes. The rows arrive as a JSON argument and the transcripts through
# BATON_TRANSCRIPTS, so every fixture is a directory and no fixture starts a process.
set -eu

# The tick's interval, the same sixty seconds the launchd job carries as StartInterval (M03).
# A gap is a marker two intervals old (see derivation 15); M03 must keep the plist and this equal.
BATON_TICK_SECONDS=60

# config_num <key> <default>: one number out of config.json.
config_num() {
  jq -r --arg k "$1" --arg d "$2" '.[$k] // $d | tostring' "$BATON_HOME/config.json" 2>/dev/null || printf '%s\n' "$2"
}

# iso_epoch <timestamp>: epoch seconds from an ISO 8601 timestamp, whether it carries an offset
# (Baton's own at), a Z (an artifact's written_at) or milliseconds and a Z (a transcript record's
# timestamp). Converting a string Baton wrote is not an outside thing, so this is arithmetic and
# not the date seam — the seam answers the scenario's now whatever it is asked.
iso_epoch() {
  printf '%s\n' "$1" | awk '
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
      if (m <= 2) y -= 1
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    {
      s = $0
      if (substr(s, 5, 1) != "-" || substr(s, 8, 1) != "-" || substr(s, 11, 1) != "T" \
          || substr(s, 14, 1) != ":" || substr(s, 17, 1) != ":") exit 1
      y = substr(s, 1, 4) + 0; mo = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
      hh = substr(s, 12, 2) + 0; mi = substr(s, 15, 2) + 0; ss = substr(s, 18, 2) + 0
      rest = substr(s, 20)
      if (substr(rest, 1, 1) == ".") { i = 2; while (substr(rest, i, 1) ~ /^[0-9]$/) i++; rest = substr(rest, i) }
      off = 0
      if (rest != "" && rest != "Z") {
        sign = (substr(rest, 1, 1) == "-") ? -1 : 1
        if (substr(rest, 1, 1) != "+" && substr(rest, 1, 1) != "-") exit 1
        # +HH, +HHMM and +HH:MM. Reading the last two characters as minutes would read the hours
        # twice for the first of those.
        om = (length(rest) == 3) ? 0 : (substr(rest, length(rest) - 1, 2) + 0)
        off = sign * ((substr(rest, 2, 2) + 0) * 3600 + om * 60)
      }
      printf "%d\n", days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss - off
      exit 0
    }' || { echo "iso_epoch: \"$1\" is not an ISO 8601 timestamp"; return 1; }
}

# now_epoch: Baton's own clock, in seconds.
now_epoch() { iso_epoch "$(baton_now)"; }

# epoch_iso <epoch seconds>: the inverse of `iso_epoch` — an ISO 8601 timestamp of the same shape
# Baton writes everywhere else, carrying the offset the clock itself reports. A boundary Baton
# computed by arithmetic (a window's start, the instant a pause lifts) has to be written down and
# read by a person, and the same reasoning that keeps `iso_epoch` in `awk` keeps this here: it is a
# string Baton is writing, not a question about the outside, so it never goes near the date seam
# and a fixture's frozen clock cannot make it disagree with the timestamps beside it.
#
# The offset is taken from `baton_now` rather than from the host's zone, so the value is the same
# on any Mac a scenario runs on and a person reads a boundary in the same reckoning as the `at` of
# the event that recorded it. `Z` and a bare offset are both accepted, as `iso_epoch` accepts them.
epoch_iso() {
  # Everything after `YYYY-MM-DDTHH:MM:SS`, which is where every timestamp Baton writes puts its
  # offset. Cut by position rather than matched: `sed`'s basic expressions have no alternation, so
  # one pattern cannot read both `Z` and `+01:00` and a pattern that read only one of them would
  # silently call the other no offset at all.
  ei_off=$(baton_now | cut -c20-)
  [ -n "$ei_off" ] || ei_off=Z
  if [ "$ei_off" = Z ]; then ei_shift=0; else
    ei_shift=$(( $(iso_epoch "1970-01-01T00:00:00$ei_off") * -1 ))
  fi
  printf '%s\n' "$(( $1 + ei_shift ))" | awk -v off="$ei_off" '
    # Howard Hinnant’s `civil_from_days`, the published inverse of the `days_from_civil` above,
    # transcribed rather than derived. Its constants are days per 400-year era (146097), per
    # century (36524) and per four years (1460), and the shift from the 1970 epoch to an era
    # beginning on 0000-03-01 (719468). Named so a reader can check it against the original
    # instead of taking four bare numbers on trust.
    function civil_from_days(z,   era, doe, yoe, y, doy, mp, d, m) {
      z += 719468
      era = int((z >= 0 ? z : z - 146096) / 146097)
      doe = z - era * 146097
      yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
      y = yoe + era * 400
      doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
      mp = int((5 * doy + 2) / 153)
      d = doy - int((153 * mp + 2) / 5) + 1
      m = mp + (mp < 10 ? 3 : -9)
      return sprintf("%04d-%02d-%02d", y + (m <= 2 ? 1 : 0), m, d)
    }
    {
      s = $0 + 0
      days = int(s / 86400); rem = s - days * 86400
      if (rem < 0) { days -= 1; rem += 86400 }
      printf "%sT%02d:%02d:%02d%s\n", civil_from_days(days), int(rem / 3600), int((rem % 3600) / 60), rem % 60, off
    }'
}

# session_id_ok <session>: a session id is hexadecimal and hyphens, nothing else. The provenance
# check is an id match (REQ-ARTIFACT-05), so a string that is not an id cannot be one: `..` is not
# a glob character, and without this an artifact naming `../<folder>/<other session>` would find a
# transcript by path traversal and pass a check that is supposed to prove the id exists.
session_id_ok() {
  case "$1" in
    ''|*[!0-9a-fA-F-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# transcript_of <session>: the transcript found by glob — never a path derived from the project
# (REQ-ARTIFACT-05). Prints the path, or nothing with status 1.
transcript_of() {
  session_id_ok "$1" || return 1
  for to_f in "$BATON_TRANSCRIPTS"/*/"$1".jsonl; do
    if [ -f "$to_f" ]; then printf '%s\n' "$to_f"; return 0; fi
  done
  return 1
}

# orphaned_of <session>: the .orphaned-<ts>-<hash>.jsonl sibling, when that is all there is.
orphaned_of() {
  session_id_ok "$1" || return 1
  for oo_f in "$BATON_TRANSCRIPTS"/*/"$1".orphaned-*.jsonl; do
    if [ -f "$oo_f" ]; then printf '%s\n' "$oo_f"; return 0; fi
  done
  return 1
}

# typed_hashes <transcript>: one line per message a person or Baton put into the session — "<at>
# <uuid> <sha256>" in file order. That is a user record, not meta and not a compact summary, that
# was typed (promptSource typed, Baton's own prompts among them), queued from Remote Control
# between turns (promptSource queued), or carries origin human (a slash command); or a
# queued_command attachment with origin human, which is how a message sent from Claude.app arrives
# mid-turn. A peer session's message, a task notification and the Stop gate's feedback are none of
# these (D-085). Compaction appends and never rewrites. The text is normalised and hashed the one
# way the sidecar was (D-025).
# A transcript that does not parse — a line half-written while the session was mid-append — fails
# the read rather than returning what parsed so far: a truncated list can lose the newest typed
# record, and the newest typed record is the whole of the takeover decision. Reading it short would
# report a lane a person is typing into as clean, which is the one thing INV-04 forbids.
typed_hashes() {
  th_recs=$(jq -c 'def text_of: if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("")) end;
                   if .type == "user" and (.promptSource == "typed" or .promptSource == "queued" or (.origin | objects | .kind) == "human")
                      and (.isMeta != true) and (.isCompactSummary != true)
                   then {at: .timestamp, uuid: .uuid, text: (.message.content | text_of)}
                   elif .type == "attachment" and .attachment.type == "queued_command" and (.attachment.origin | objects | .kind) == "human"
                   then {at: .timestamp, uuid: .uuid, text: (.attachment.prompt | text_of)}
                   else empty end' \
             "$1" 2>/dev/null) || return 1
  [ -n "$th_recs" ] || return 0
  # Three fixed columns: a record missing its timestamp or uuid prints a dash rather than nothing,
  # because an empty leading field would shift the columns and put the hash where awk reads the
  # uuid — and the hash column is the whole of the takeover comparison.
  printf '%s\n' "$th_recs" | while IFS= read -r th_rec; do
    th_sum=$(printf '%s' "$th_rec" | jq -r .text | prompt_normalise | shasum -a 256 | awk '{ print $1 }')
    printf '%s %s %s\n' "$(printf '%s' "$th_rec" | jq -r '(.at // "") | if . == "" then "-" else . end')" \
      "$(printf '%s' "$th_rec" | jq -r '(.uuid // "") | if . == "" then "-" else . end')" "$th_sum"
  done
}

# lanes_open <project> <log json>: every dispatch whose (project, milestone, attempt) has no later
# consumed with outcome complete and no later dispatch for the same (project, milestone), each
# resolved through the fork chain to the session currently carrying the attempt (§6.1) and stamped
# with the newest dispatch-or-resume of the attempt as its since. An empty project means every
# registered project. The pre-intersection half of derivation 1; derive_in_flight splits it.
lanes_open() {
  printf '%s' "$2" | jq -c --arg p "$1" '
    [ to_entries[] | {i: .key} + .value | select($p == "" or .project == $p) ] as $ev
    | [ $ev[] | select(.kind == "dispatch") | . as $d
        | select(($ev | any(.kind == "dispatch" and .project == $d.project
                            and .milestone == $d.milestone and .i > $d.i)) | not)
        | select(($ev | any(.kind == "consumed" and .project == $d.project
                            and .milestone == $d.milestone and .attempt == $d.attempt
                            and .outcome == "complete" and .i > $d.i)) | not)
        | { project: $d.project, milestone: $d.milestone, attempt: $d.attempt,
            dispatch_at: $d.at, model: $d.model, effort: $d.effort, remote: $d.remote,
            worktree: $d.worktree, branch: $d.branch,
            session: ([ $ev[] | select((.kind == "dispatch" or .kind == "copy_fork")
                                       and .project == $d.project and .milestone == $d.milestone
                                       and .attempt == $d.attempt) ] | last | .session),
            since: ([ $ev[] | select((.kind == "dispatch" or .kind == "resume")
                                     and .project == $d.project and .milestone == $d.milestone
                                     and .attempt == $d.attempt) ] | last | .at) } ]
    | map(with_entries(select(.value != null)))'
}

# current_session <project> <milestone> <attempt>: the session currently carrying the attempt —
# the newest of that attempt's dispatch.session and every later copy_fork.session (§6.1). The
# rule lanes_open applies inline for every open lane; this is the same sentence for one lane.
current_session() {
  cs_log=$(log_json) || { echo "$cs_log"; return 1; }
  printf '%s' "$cs_log" | jq -r --arg p "$1" --arg m "$2" --argjson a "$3" '
    [ .[] | select(.project == $p and .milestone == $m and .attempt == $a
                   and (.kind == "dispatch" or .kind == "copy_fork")) ]
    | last | .session // empty'
}

# lane_of_session <session>: the lane a session belongs to, from the newest dispatch or copy_fork
# that names it — {project, milestone, attempt}, or an empty object for a session Baton never
# dispatched. The log's answer to "whose was this?", for a file that cannot say so itself.
lane_of_session() {
  los_log=$(log_json) || { echo "$los_log"; return 1; }
  printf '%s' "$los_log" | jq -c --arg s "$1" '
    [ .[] | select(.session == $s and (.kind == "dispatch" or .kind == "copy_fork")) ]
    | last | {project, milestone, attempt} | with_entries(select(.value != null))'
}

# 1. In flight, per project. lanes_open intersected with rows carrying a pid. The rows a lane has
# no live row for are the other half of the same read — the crash rule is exactly that complement
# — so both are named in the one document. Liveness is the pid and never the state: a crash reads
# pid null while state still reads working.
derive_in_flight() {
  di_log=$(log_json) || { echo "$di_log"; return 1; }
  di_lanes=$(lanes_open "$1" "$di_log")
  printf '%s' "$di_lanes" | jq -c --argjson rows "$2" '
    map(. as $l | ($rows | map(select(.sessionId == $l.session)) | first) as $row
        | if $row == null then $l else $l + {row: $row} end
        | if ($row.pid // null) == null then . else . + {pid: $row.pid} end)
    | { in_flight: [ .[] | select(has("pid")) ], no_row: [ .[] | select(has("pid") | not) ] }'
}

# 2. Parked, and why. Every escalation with no later resolution naming its at. Its scope says
# whether the lane or every lane of that project is held; status prints its class and the first
# line of its carries, and baton answer resolves against it across projects.
derive_parked() {
  dp_log=$(log_json) || { echo "$dp_log"; return 1; }
  printf '%s' "$dp_log" | jq -c --arg p "$1" '
    [ to_entries[] | {i: .key} + .value | select($p == "" or .project == $p) ] as $ev
    | { parked: [ $ev[] | select(.kind == "escalation") | . as $e
                  | select(($ev | any(.kind == "resolution" and .escalation_at == $e.at
                                      and .project == $e.project and .milestone == $e.milestone
                                      and .i > $e.i)) | not)
                  | {at: $e.at, project: $e.project, milestone: $e.milestone, session: $e.session,
                     attempt: $e.attempt, class: $e.class, scope: $e.scope,
                     carries: $e.carries, channel: $e.channel}
                  | with_entries(select(.value != null)) ] }'
}

# 3. Taken over. Every in-flight lane whose transcript's newest typed record is not one Baton
# sent: the record's normalised text hashed the one way and compared against prompt_sha256 of
# every dispatch and resume of the (project, milestone) — not the session alone, because a copy
# fork's transcript is a byte-for-byte copy of its parent's rewritten to the new id. A lane whose
# only transcript is an .orphaned- sibling is not scanned; it escalates with the sibling's path. A
# lane whose transcript will not parse is named too, rather than counted as not taken over.
derive_taken_over() {
  dt_log=$(log_json) || { echo "$dt_log"; return 1; }
  dt_flight=$(derive_in_flight "$1" "$2") || { echo "$dt_flight"; return 1; }
  dt_flight=$(printf '%s' "$dt_flight" | jq -c '.in_flight')
  dt_over='[]'; dt_orphan='[]'; dt_unreadable='[]'
  dt_n=$(printf '%s' "$dt_flight" | jq length)
  dt_i=0
  while [ "$dt_i" -lt "$dt_n" ]; do
    dt_lane=$(printf '%s' "$dt_flight" | jq -c ".[$dt_i]")
    dt_i=$((dt_i + 1))
    dt_project=$(printf '%s' "$dt_lane" | jq -r .project)
    dt_milestone=$(printf '%s' "$dt_lane" | jq -r .milestone)
    dt_session=$(printf '%s' "$dt_lane" | jq -r .session)
    if ! dt_file=$(transcript_of "$dt_session"); then
      if dt_file=$(orphaned_of "$dt_session"); then
        dt_orphan=$(printf '%s' "$dt_orphan" | jq -c --argjson l "$dt_lane" --arg f "$dt_file" \
          '. + [{project: $l.project, milestone: $l.milestone, attempt: $l.attempt, session: $l.session, path: $f}]')
      fi
      continue
    fi
    dt_sent=$(printf '%s' "$dt_log" | jq -r --arg p "$dt_project" --arg m "$dt_milestone" '
      .[] | select((.kind == "dispatch" or .kind == "resume") and .project == $p and .milestone == $m)
      | .prompt_sha256 // empty')
    if ! dt_typed=$(typed_hashes "$dt_file"); then
      dt_unreadable=$(printf '%s' "$dt_unreadable" | jq -c --argjson l "$dt_lane" --arg f "$dt_file" \
        '. + [{project: $l.project, milestone: $l.milestone, attempt: $l.attempt, session: $l.session, path: $f}]')
      continue
    fi
    [ -n "$dt_typed" ] || continue
    dt_count=$(printf '%s\n' "$dt_typed" | wc -l | tr -d ' ')
    dt_newest=$(printf '%s\n' "$dt_typed" | tail -1 | awk '{ print $3 }')
    if printf '%s\n' "$dt_sent" | grep -Fqx "$dt_newest"; then continue; fi
    dt_first=$(printf '%s\n' "$dt_typed" | SENT="$dt_sent" awk '
      BEGIN { n = split(ENVIRON["SENT"], parts, "\n"); for (i = 1; i <= n; i++) if (parts[i] != "") sent[parts[i]] = 1 }
      !($3 in sent) { print $1, $2; exit }')
    dt_over=$(printf '%s' "$dt_over" | jq -c --argjson l "$dt_lane" --argjson c "$dt_count" \
      --arg f "$dt_file" --arg a "${dt_first% *}" --arg u "${dt_first#* }" '
      . + [ {project: $l.project, milestone: $l.milestone, attempt: $l.attempt, session: $l.session,
             transcript: $f, first_unmatched_at: $a, first_unmatched_uuid: $u, typed_count: $c}
            | with_entries(select(.value != "" and .value != "-")) ]')
  done
  jq -nc --argjson o "$dt_over" --argjson r "$dt_orphan" --argjson u "$dt_unreadable" \
    '{taken_over: $o, orphaned: $r, unreadable: $u}'
}

# 4. Which handovers were consumed. The archive is the answer, not the log: a file still in the
# inbox has not been acted on, one in the archive has, and the move is the consumption. The log
# records what each consumption decided; the join is by field — the consumed event's archive holds
# the archived file's path verbatim and a reader never rebuilds the name from parts. The join runs
# both ways: `unrecorded` names every file in archive/ and rejected/ that no event claims, which is
# what a tick killed between the move and its event leaves behind, and which nothing else would
# show — derivation 1 would read such a lane as still open and M03's crash rule as a crash. A repeat
# sits in archive/ too, claimed by its `repeated` event and listed under `repeated`, and is not a
# consumed handover: `consumed` lists each handover once while an archived copy of it stands, in the
# order it was first acted on (D-095).
derive_consumed() {
  dc_log=$(log_json) || { echo "$dc_log"; return 1; }
  dc_waiting='[]'
  for dc_f in "$BATON_HOME"/inbox/*.json; do
    [ -f "$dc_f" ] || continue
    # -s so a file holding more than one JSON document yields one value rather than two, which
    # --argjson refuses; an unreadable file contributes its name alone.
    dc_waiting=$(printf '%s' "$dc_waiting" | jq -c --arg f "$(basename "$dc_f")" \
      --argjson a "$(jq -cs 'if (.[0] | type) == "object" then .[0] | {milestone, session, outcome} else {} end' \
                       "$dc_f" 2>/dev/null || echo '{}')" \
      '. + [ ({file: $f} + $a) | with_entries(select(.value != null)) ]')
  done
  printf '%s' "$dc_log" | jq -c --arg p "$1" --argjson w "$dc_waiting" \
    --argjson present "$(ls "$BATON_HOME/archive" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    --argjson rejects "$(ls "$BATON_HOME/rejected" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')" '
    [ .[] | select(.kind == "consumed" and ($p == "" or .project == $p))
      | {at, project, milestone, session, attempt, outcome, reason, error,
         written_by, merged_as, blocked_by, archive}
      | with_entries(select(.value != null))
      | . as $c
      | (($c.archive // "") | sub("^.*/"; "")) as $name
      | $c + {archive_present: (($present | index($name)) != null)} ] as $consumed
    | [ .[] | select(.kind == "repeated" and ($p == "" or .project == $p))
        | {at, project, milestone, session, attempt, outcome, archive, repeats}
        | with_entries(select(.value != null))
        | ((.archive // "") | sub("^.*/"; "")) as $name
        | . + {archive_present: (($present | index($name)) != null)} ] as $repeated
    | [ .[] | select(.kind == "rejected") | (.path // "") | sub("^.*/"; "") ] as $claimed
    # Claimed from the events of every project, as `rejected` is: archive/ is one directory for all of
    # them, so a claim read through the project filter would call the handovers of another unrecorded.
    | [ .[] | select(.kind == "consumed" or .kind == "repeated") | (.archive // "") | sub("^.*/"; "") ] as $archived
    | { consumed: $consumed,
        repeated: $repeated,
        waiting: $w,
        # The name is bound before the pipe: inside `$archived | index(.)` the dot is $archived itself,
        # which finds itself at 0 and never names a file.
        unrecorded: ( [ $present[] | . as $f | select(($archived | index($f)) == null) | {file: ., where: "archive"} ]
                    + [ $rejects[] | . as $f | select(($claimed  | index($f)) == null) | {file: ., where: "rejected"} ] ) }'
}

# 5. Each active wait and its first-failure time. The newest consumed with reason api-error for a
# (project, milestone, attempt) that has no later consumed written_by session and no later
# dispatch. Its start is the since its wait_retry events carry, and before the first retry exists
# that is the consumed event's own at. The next retry is read from the last retry rather than
# extrapolated from the first, because a lid-close sleep stretches every interval.
derive_waits() {
  dw_log=$(log_json) || { echo "$dw_log"; return 1; }
  dw_now=$(now_epoch)
  dw_every=$(printf '%s' "$dw_log" | jq -c --arg p "$1" '
    [ to_entries[] | {i: .key} + .value | select($p == "" or .project == $p) ] as $ev
    | [ $ev[] | select(.kind == "consumed" and .reason == "api-error") | . as $c
        | select(($ev | any(.kind == "consumed" and .project == $c.project
                            and .milestone == $c.milestone and .attempt == $c.attempt
                            and .written_by == "session" and .i > $c.i)) | not)
        | select(($ev | any(.kind == "dispatch" and .project == $c.project
                            and .milestone == $c.milestone and .i > $c.i)) | not)
        | ([ $ev[] | select(.kind == "wait_retry" and .project == $c.project
                            and .milestone == $c.milestone and .attempt == $c.attempt
                            and .i > $c.i) ]) as $retries
        | { project: $c.project, milestone: $c.milestone, attempt: $c.attempt, session: $c.session,
            error: $c.error, retries: ($retries | length),
            since: ($retries | last | .since // $c.at),
            last_at: ($retries | last | .at // $c.at) }
        | with_entries(select(.value != null)) ]
    | group_by([.project, .milestone, .attempt]) | map(last)')
  dw_out='[]'
  dw_n=$(printf '%s' "$dw_every" | jq length)
  dw_retry=$(( $(config_num retryMinutes 15) * 60 ))
  dw_i=0
  while [ "$dw_i" -lt "$dw_n" ]; do
    dw_w=$(printf '%s' "$dw_every" | jq -c ".[$dw_i]")
    dw_i=$((dw_i + 1))
    dw_since=$(iso_epoch "$(printf '%s' "$dw_w" | jq -r .since)") || { echo "$dw_since"; return 1; }
    dw_last=$(iso_epoch "$(printf '%s' "$dw_w" | jq -r .last_at)") || { echo "$dw_last"; return 1; }
    dw_out=$(printf '%s' "$dw_out" | jq -c --argjson w "$dw_w" \
      --argjson elapsed "$((dw_now - dw_since))" --argjson next "$((dw_last + dw_retry))" \
      --argjson due "$([ $((dw_last + dw_retry)) -le "$dw_now" ] && echo true || echo false)" \
      '. + [ $w + {elapsed_seconds: $elapsed, next_retry_epoch: $next, due: $due} ]')
  done
  jq -nc --argjson w "$dw_out" '{waits: $w}'
}

# 6. Each hold. Every hold with no later hold_lifted for the same model and cause. A rate_limit or
# billing_error hold lifts when its wait clears; a fableReserve hold lifts when the freshest status
# file's seven_day.used_percentage falls below the reserve; a budget hold lifts when neither pacing
# guard bites, which its `resumes_at` says Baton expects at the five-hour window's boundary.
derive_holds() {
  dh_log=$(log_json) || { echo "$dh_log"; return 1; }
  printf '%s' "$dh_log" | jq -c '
    [ to_entries[] | {i: .key} + .value ] as $ev
    | { holds: [ $ev[] | select(.kind == "hold") | . as $h
                 | select(($ev | any(.kind == "hold_lifted" and .model == $h.model
                                     and .cause == $h.cause and .i > $h.i)) | not)
                 | {at: $h.at, project: $h.project, model: $h.model, cause: $h.cause,
                    reading: $h.reading, status_file: $h.status_file, resumes_at: $h.resumes_at,
                    reason: $h.reason}
                 | with_entries(select(.value != null)) ] }'
}

# 7. Each caffeinate holder to re-arm. For each in-flight lane, -i -w against the pid in the
# current row — the log stores no pid, because a restart of the background service gives
# the session a new one.
# For each active wait, -i -t for the remainder of caffeinateMaxHours measured from its since.
derive_caffeinate() {
  dcf_max=$(( $(config_num caffeinateMaxHours 6) * 3600 ))
  # Capture before piping: a derivation that fails prints its detail on stdout with a non-zero
  # status (D-030), and a pipe straight into jq would hand that detail to jq and lose it.
  dcf_flight=$(derive_in_flight "$1" "$2") || { echo "$dcf_flight"; return 1; }
  dcf_waits=$(derive_waits "$1") || { echo "$dcf_waits"; return 1; }
  dcf_wake=$(printf '%s' "$dcf_flight" | jq -c '[ .in_flight[] | {project, milestone, session, pid} ]')
  dcf_timed=$(printf '%s' "$dcf_waits" | jq -c --argjson max "$dcf_max" '
    [ .waits[] | {project, milestone, attempt, since,
                  remaining_seconds: ([$max - .elapsed_seconds, 0] | max)} ]')
  jq -nc --argjson w "$dcf_wake" --argjson t "$dcf_timed" '{wake: $w, timed: $t}'
}

# 8. The last tick. ~/.baton/last-tick, read as a file and never derived from the log: a quiet
# tick writes no event, so the newest event cannot be the clock.
derive_last_tick() {
  dlt_marker=$BATON_HOME/last-tick
  if [ ! -f "$dlt_marker" ]; then echo '{"present":false}'; return 0; fi
  dlt_at=$(head -1 "$dlt_marker")
  dlt_epoch=$(iso_epoch "$dlt_at") || { echo "$dlt_epoch"; return 1; }
  jq -nc --arg at "$dlt_at" --argjson age "$(( $(now_epoch) - dlt_epoch ))" \
    '{present: true, last_tick: $at, age_seconds: $age}'
}

# 9. The ladder's position for a (project, milestone, attempt): the count of failure endings since
# the newest reset point. A failure ending is a consumed with reason no-handover, the second
# crash_sighting of a confirmed crash, or an automatic resume with outcome refused; a reset point is a
# consumed written_by session or the attempt's own dispatch. One resume, then one redispatch, then
# escalate.
derive_ladder() {
  dl_log=$(log_json) || { echo "$dl_log"; return 1; }
  printf '%s' "$dl_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" '
    [ to_entries[] | {i: .key} + .value
      | select(.project == $p and .milestone == $m and .attempt == $a) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch" or (.kind == "consumed" and .written_by == "session")) ]
       | last) as $reset
    | ([ $ev[] | select(.i > ($reset.i // -1))
         | select((.kind == "consumed" and .reason == "no-handover")
                  or (.kind == "crash_sighting" and .sighting == 2)
                  or (.kind == "resume" and .outcome == "refused" and .resume_kind != "ruling")) ] | length) as $failures
    | {project: $p, milestone: $m, attempt: $a, reset_at: $reset.at, failures: $failures,
       next: (if $failures == 0 then "none" elif $failures == 1 then "resume"
              elif $failures == 2 then "redispatch" else "escalate" end)}
    | with_entries(select(.value != null))'
}

# 10. The attempt number: the count of dispatch events for the (project, milestone). The resume
# count for an attempt: the count of its resume events with outcome delivered or forked. Neither
# is stored anywhere else, and the count wins over the stamp.
derive_attempt() {
  da_log=$(log_json) || { echo "$da_log"; return 1; }
  printf '%s' "$da_log" | jq -c --arg p "$1" --arg m "$2" --arg a "${3:-}" '
    ([ .[] | select(.kind == "dispatch" and .project == $p and .milestone == $m) ] | length) as $n
    | (if $a == "" then $n else ($a | tonumber) end) as $of
    | {project: $p, milestone: $m, attempt: $n, resumes_for: $of,
       resumes: ([ .[] | select(.kind == "resume" and .project == $p and .milestone == $m
                                and .attempt == $of
                                and (.outcome == "delivered" or .outcome == "forked")) ] | length)}'
}

# 11. Whether a once-only key is spent. A notification with that class and key exists at or after
# the attempt's newest reset point — the same reset the ladder uses, plus a takeover. Stall and
# long-running also re-arm on a delivered or forked resume, which starts another stretch of activity.
# Refused resumes reset nothing. An artifact
# the session wrote itself demonstrates it came back, so what it does next is new information; an
# api-error artifact is written by the hook and not by the session, so a fifteen-minute wait cycle
# never re-arms a wait-ceiling key.
derive_key_spent() {
  dks_log=$(log_json) || { echo "$dks_log"; return 1; }
  printf '%s' "$dks_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" --arg c "$4" --arg k "${5:-}" '
    [ to_entries[] | {i: .key} + .value
      | select(.project == $p and .milestone == $m and .attempt == $a) ] as $ev
    | ([ $ev[] | select(.kind == "dispatch" or .kind == "takeover"
                        or (($c == "stall" or $c == "long-running") and .kind == "resume"
                            and (.outcome == "delivered" or .outcome == "forked"))
                        or (.kind == "consumed" and .written_by == "session")) ] | last) as $reset
    | ([ $ev[] | select(.kind == "notification" and .class == $c and ($k == "" or .key == $k))
         | select(.i > ($reset.i // -1)) ] | last) as $spent
    | {project: $p, milestone: $m, attempt: $a, class: $c, key: (if $k == "" then null else $k end),
       reset_at: $reset.at, spent: ($spent != null), at: $spent.at}
    | with_entries(select(.value != null))'
}

# 12. The dispatch hold: derivation 6, read for dispatch. No dispatch on a model with an active
# rate_limit or billing_error hold; on every model once a second model is held. A fableReserve
# hold holds its own model — every spelling of it, which `hold_bites` asks `is_fable` about — and
# counts toward nothing else. A `budget` hold holds every model, because the allowance it paces
# against is the account's and not any one model's: it is the same shape of answer as a shared
# limit, and saying so here is what lets every caller of `hold_bites` — step 7's filter loop and a
# redispatch alike — be paced without knowing pacing exists (M14).
derive_dispatch_hold() {
  ddh_holds=$(derive_holds) || { echo "$ddh_holds"; return 1; }
  printf '%s' "$ddh_holds" | jq -c '
    ([ .holds[] | select(.cause == "rate_limit" or .cause == "billing_error") | .model ] | unique) as $limited
    | { held_models: ([ .holds[] | .model ] | unique),
        all: (($limited | length) >= 2 or ($limited | index("all")) != null
              or any(.holds[]; .cause == "budget")),
        causes: [ .holds[] | {model, cause} ] }'
}

# 13. baton answer <milestone>: derivation 2, filtered by milestone across every project. Exactly
# one match acts; more than one refuses and prints <project>/<milestone>; none refuses with
# "nothing is waiting on <milestone>".
derive_answer_candidates() {
  dac_parked=$(derive_parked "") || { echo "$dac_parked"; return 1; }
  printf '%s' "$dac_parked" | jq -c --arg m "$1" '
    [ .parked[] | select(.milestone == $m) ] as $c
    | {milestone: $m, count: ($c | length), candidates: $c}'
}

# 14. baton plan's provenance of allow rules: every widening for the project, newest first, each
# naming the rule and the milestone that earned it.
derive_widenings() {
  dwd=$(widenings_json "$1") || { echo "$dwd"; return 1; }
  printf '%s' "$dwd" | jq -c '{widenings: [ .[] | {at, project, milestone, rule, permissions_file}
                                            | with_entries(select(.value != null)) ]}'
}

# 15. The gap: the as-of minus the marker, the as-of defaulting to now. Reported only when open
# lanes, parks or waits show work during it, including a lane whose process died — a gap with
# nothing to do is not one — keyed on the marker value it was measured against, so one outage
# reports once.
#
# The as-of exists because a tick can now spend minutes inside its own step 2: it runs the target
# project's standing check on the commit a completion claims, under the lock (D-148), measured at
# 652 s for Baton's own suite. Measured against the wall clock at the end of that, the marker — the
# previous tick's, already an interval old — is past the threshold, and the `consumed` event the
# same tick just wrote counts as a lane closed after it, so the tick reports itself as an outage
# for the length of the work it was doing. The gap means "Baton was not running", not "the marker
# is old", and the tick's own start is the instant at which those are the same sentence.
#
# The threshold is two intervals, not one. The marker holds the at of the tick that completed and
# is written after the lock is released, so at the next tick it is already a full interval old
# plus that tick's own elapsed time; one interval would report on every tick that has any open
# lane, and the once-only key is the marker value, which changes every tick, so nothing would
# suppress it. Two intervals means a tick was actually missed.
#
# "During it" is not "now": a lane that was in flight through the outage and finished before this
# read still means Baton was not running while something needed it. So the window counts lanes open
# now, plus anything that closed after the marker.
derive_gap() {
  dg_as_of=${2:-$(baton_now)}
  dg_tick=$(derive_last_tick) || { echo "$dg_tick"; return 1; }
  if [ "$(printf '%s' "$dg_tick" | jq -r .present)" != true ]; then
    echo '{"present":false,"report":false}'
    return 0
  fi
  dg_marker=$(printf '%s' "$dg_tick" | jq -r .last_tick)
  dg_log=$(log_json) || { echo "$dg_log"; return 1; }
  dg_f=$(lanes_open "" "$dg_log") || { echo "$dg_f"; return 1; }
  dg_p=$(derive_parked "") || { echo "$dg_p"; return 1; }
  dg_w=$(derive_waits "") || { echo "$dg_w"; return 1; }
  dg_open=$(( $(printf '%s' "$dg_f" | jq length) \
            + $(printf '%s' "$dg_p" | jq '.parked | length') \
            + $(printf '%s' "$dg_w" | jq '.waits | length') ))
  dg_marker_epoch=$(iso_epoch "$dg_marker") || { echo "$dg_marker_epoch"; return 1; }
  dg_as_of_epoch=$(iso_epoch "$dg_as_of") || { echo "$dg_as_of_epoch"; return 1; }
  dg_age=$((dg_as_of_epoch - dg_marker_epoch))
  # The closed-lane test stays on the marker and not on the as-of: a lane that closed between them
  # is still a lane the gap would have covered, which is the whole of "during it is not now".
  dg_closed_ats=$(printf '%s' "$dg_log" | jq -r '
    .[] | select((.kind == "consumed" and (.outcome == "complete" or .written_by == "session"))
                  or .kind == "resolution") | .at') || return 1
  dg_closed=0
  for dg_at in $dg_closed_ats; do
    dg_epoch=$(iso_epoch "$dg_at") || { echo "$dg_epoch"; return 1; }
    [ "$dg_epoch" -le "$dg_marker_epoch" ] || dg_closed=$((dg_closed + 1))
  done
  printf '%s' "$dg_tick" | jq -c --argjson interval "$BATON_TICK_SECONDS" \
    --argjson lanes "$((dg_open + dg_closed))" --argjson age "$dg_age" '
    {present: true, marker: .last_tick, gap_seconds: $age, had_lane: ($lanes > 0),
     report: ($age >= 2 * $interval and $lanes > 0)}'
}
