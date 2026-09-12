#!/bin/sh
# lib/inbox.sh — step 2 of the tick: the inbox consumed the way the tick will consume it. Every
# artifact is parsed, checked for provenance and for the facts it claims, and then either archived
# under its consumed-at name with a consumed event or moved to rejected/ with a rejected event and
# a lane escalation. Consumption is the move (INV-06): a file in the inbox has not been acted on,
# one in the archive has, so a second run over the same inbox does nothing. On failure every
# function prints its detail on stdout and returns non-zero (D-030).
set -eu

# project_key_of <path>: the registered project whose canonical checkout is exactly <path>. The
# project key is the directory name under projects/, which is the basename of that checkout.
project_key_of() {
  [ -n "$1" ] || return 1
  for pk_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$pk_pj" ] || continue
    pk_path=$(jq -r '.path // empty' "$pk_pj" 2>/dev/null) || continue
    if [ "$pk_path" = "$1" ]; then basename "$(dirname "$pk_pj")"; return 0; fi
  done
  return 1
}

# merged_as_verify <path> <sha>: the claim an artifact makes about its own merge, verified and
# never trusted (INV-03). Prints nothing on success; the detail on failure.
#
# The claim must be a commit id, not a name for one. git resolves `main`, `HEAD`, `@` and
# `main~0` as readily as a hash, and every one of them is an ancestor of `main` by definition, so a
# check that only asks git to resolve the string is satisfied by a constant and proves nothing
# about the session's merge (D-037). So: hexadecimal, long enough to name a commit, resolving to a
# commit whose full id it is a prefix of — a ref name can never satisfy the last of those — and
# only then the ancestry, run against the resolved id.
merged_as_verify() {
  case "$2" in
    '') echo "the artifact names no merge commit"; return 1 ;;
    *[!0-9a-f]*) echo "\"$2\" is a name, not a commit id; merged_as must be the merge commit"; return 1 ;;
  esac
  [ "${#2}" -ge 7 ] || { echo "\"$2\" is too short to name a commit"; return 1; }
  mv_full=$(git -C "$1" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null) \
    || { echo "$2 is not a commit in $1"; return 1; }
  case "$mv_full" in
    "$2"*) ;;
    *) echo "$2 resolves to $mv_full, so it is a name and not that commit's id"; return 1 ;;
  esac
  git -C "$1" rev-parse --verify --quiet "main^{commit}" > /dev/null 2>&1 \
    || { echo "$1 has no main branch"; return 1; }
  git -C "$1" merge-base --is-ancestor "$mv_full" main \
    || { echo "$2 is not an ancestor of main in $1"; return 1; }
}

# brief_pointer_check <path> <brief> <heading>: the brief a handover points at, read on main —
# git show, never the working tree. Prints nothing on success; the detail on failure.
brief_pointer_check() {
  bp_text=$(git -C "$1" show "main:$2" 2>&1) || { echo "$2 is not on main: $bp_text"; return 1; }
  printf '%s\n' "$bp_text" | HEADING="## $3" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    trim($0) == ENVIRON["HEADING"] { found = 1; exit }
    END { exit (found ? 0 : 1) }' || { echo "$2 on main has no heading \"## $3\""; return 1; }
}

# written_by_of <reason>: who wrote the artifact, derived from the reason and never stored on the
# file. The Stop gate writes no-handover and the StopFailure hook writes api-error; everything else
# is the session's own word (D-033).
written_by_of() {
  case "$1" in
    no-handover) echo stop-gate ;;
    api-error) echo stop-failure ;;
    *) echo session ;;
  esac
}

# stop_route <reason>: the action a declared stop routes to (REQ-STOP-12). The table is data here
# and M04 attaches the actions; nothing in M02 acts on the name.
stop_route() {
  case "$1" in
    unfinished) echo redispatch ;;
    blocked) echo wait-for-blocker ;;
    merge-failed|other) echo escalate ;;
    main-broken) echo park-project ;;
    no-handover) echo ladder ;;
    api-error) echo wait ;;
    *) echo escalate ;;
  esac
}

# artifact_ids <file>: the milestone and session an artifact belongs to, best effort — from the
# file when it parses and from its <milestone>-<session>.json name when it does not, so that even
# a rejected file that is not JSON is recorded against a lane.
artifact_ids() {
  ai_base=$(basename "$1" .json); ai_base=${ai_base%.json.tmp}; ai_base=${ai_base%.tmp}
  ai_milestone=${ai_base%%-*}
  ai_session=${ai_base#*-}
  jq -c --arg m "$ai_milestone" --arg s "$ai_session" \
    '{milestone: (.milestone // $m), session: (.session // $s), project: .project}
     | with_entries(select(.value != null))' "$1" 2>/dev/null \
    || jq -nc --arg m "$ai_milestone" --arg s "$ai_session" '{milestone: $m, session: $s}'
}

# artifact_check <file>: every rule REQ-ARTIFACT-01 to 06 states, in order. On success prints
# {artifact, project, written_by, dropped[]} — the parsed file, the project key, who wrote it, and
# the eligible entries whose brief pointer is not on main, which reject the entry and not the file.
# On a rejection prints {rule, detail} with status 1; the rule's name is what the event carries.
artifact_check() {
  ac_a=$(jq -ce 'if type == "object" then . else error("the artifact is not a JSON object") end' "$1" 2>/dev/null) \
    || { jq -nc '{rule: "unparseable", detail: "the file is not a JSON object"}'; return 1; }

  ac_bad=$(printf '%s' "$ac_a" | jq -r '
    if (.baton != 1) then "baton is not 1"
    elif ((.project // "") == "") then "project is missing"
    elif ((.milestone // "") == "") then "milestone is missing"
    elif ((.session // "") == "") then "session is missing"
    elif ((.written_at // "") == "") then "written_at is missing"
    elif ((.outcome // "") == "") then "outcome is missing"
    # index() on an array with an array argument is a subsequence search, so ["asking"] would
    # satisfy it; the type test is what makes this an enum check.
    elif ((.outcome | type) != "string") then "outcome is \(.outcome | type), not a string"
    elif (.outcome as $o | (["complete", "asking", "stopped"] | index($o)) == null)
      then "outcome \"\(.outcome)\" is not complete, asking or stopped"
    else "" end')
  [ -z "$ac_bad" ] || { jq -nc --arg d "$ac_bad" '{rule: "missing-field", detail: $d}'; return 1; }

  ac_session=$(printf '%s' "$ac_a" | jq -r .session)
  transcript_of "$ac_session" > /dev/null \
    || { jq -nc --arg d "no transcript for session $ac_session under $BATON_TRANSCRIPTS" \
           '{rule: "no-transcript", detail: $d}'; return 1; }

  ac_path=$(printf '%s' "$ac_a" | jq -r .project)
  ac_key=$(project_key_of "$ac_path") \
    || { jq -nc --arg d "\"$ac_path\" is not a registered checkout" \
           '{rule: "unregistered-project", detail: $d}'; return 1; }

  ac_outcome=$(printf '%s' "$ac_a" | jq -r .outcome)
  # A reason belongs to a stopped artifact and to no other. Read on a complete one it would make
  # written_by read stop-failure and derive_waits report a wait on a lane that finished.
  ac_reason=''
  [ "$ac_outcome" != stopped ] || ac_reason=$(printf '%s' "$ac_a" | jq -r '.reason // ""')
  ac_dropped='[]'
  case "$ac_outcome" in
    complete)
      ac_merged=$(printf '%s' "$ac_a" | jq -r '.merged_as // ""')
      [ -n "$ac_merged" ] || { jq -nc '{rule: "missing-field", detail: "complete without merged_as"}'; return 1; }
      printf '%s' "$ac_a" | jq -e 'has("eligible") and (.eligible | type) == "array"' > /dev/null \
        || { jq -nc '{rule: "missing-field", detail: "complete without an eligible array"}'; return 1; }
      ac_detail=$(merged_as_verify "$ac_path" "$ac_merged") \
        || { jq -nc --arg d "$ac_detail" '{rule: "merged-as", detail: $d}'; return 1; }
      ac_n=$(printf '%s' "$ac_a" | jq '.eligible | length')
      ac_i=0
      while [ "$ac_i" -lt "$ac_n" ]; do
        ac_e=$(printf '%s' "$ac_a" | jq -c "(.eligible[$ac_i] | if type == \"object\" then . else {} end)")
        ac_i=$((ac_i + 1))
        # The optional form, because // catches a null but not an error: .brief.path on a string
        # brief raises one, which under set -eu would kill the whole check and reject the file
        # rather than the entry.
        ac_bp=$(printf '%s' "$ac_e" | jq -r '(.brief?.path? // "") | if type == "string" then . else "" end')
        ac_bh=$(printf '%s' "$ac_e" | jq -r '(.brief?.heading? // "") | if type == "string" then . else "" end')
        ac_em=$(printf '%s' "$ac_e" | jq -r '(.milestone? // "") | if type == "string" then . else "" end')
        if [ -z "$ac_em" ]; then
          ac_detail="the entry names no milestone"
        elif [ -z "$ac_bp" ] || [ -z "$ac_bh" ]; then
          ac_detail="the entry carries no brief path and heading"
        elif ac_detail=$(brief_pointer_check "$ac_path" "$ac_bp" "$ac_bh"); then
          continue
        fi
        ac_dropped=$(printf '%s' "$ac_dropped" | jq -c --argjson e "$ac_e" --arg d "$ac_detail" \
          '. + [{milestone: ($e.milestone? // null), path: ($e.brief?.path? // null),
                 heading: ($e.brief?.heading? // null), detail: $d}
                | with_entries(select(.value != null))]')
      done
      ;;
    asking)
      printf '%s' "$ac_a" | jq -e '(.question // "") != ""' > /dev/null \
        || { jq -nc '{rule: "missing-field", detail: "asking without a question"}'; return 1; }
      ;;
    stopped)
      case "$ac_reason" in
        unfinished|blocked|merge-failed|main-broken|no-handover|api-error|other) ;;
        '') jq -nc '{rule: "missing-field", detail: "stopped without a reason"}'; return 1 ;;
        *) jq -nc --arg r "$ac_reason" '{rule: "missing-field", detail: "reason \($r) is not one of the seven"}'; return 1 ;;
      esac
      if [ "$ac_reason" = blocked ]; then
        printf '%s' "$ac_a" | jq -e '(.blocked_by // "") != ""' > /dev/null \
          || { jq -nc '{rule: "missing-field", detail: "blocked without blocked_by"}'; return 1; }
      fi
      # api-error is the StopFailure hook's word and carries the hook's error; without it the file
      # claims a reason reserved for Baton's own hooks and is rejected (REQ-ARTIFACT-04).
      if [ "$ac_reason" = api-error ]; then
        printf '%s' "$ac_a" | jq -e '(.error // "") != ""' > /dev/null \
          || { jq -nc '{rule: "reserved-reason", detail: "api-error without the hook'"'"'s error field"}'; return 1; }
      fi
      ;;
  esac

  jq -nc --argjson a "$ac_a" --arg k "$ac_key" --arg w "$(written_by_of "$ac_reason")" \
    --argjson d "$ac_dropped" '{artifact: $a, project: $k, written_by: $w, dropped: $d}'
}

# escalate_rejection <project> <milestone> <session> <attempt> <rule> <path>: the lane escalation
# a rejection raises. The class list is the log's and a rejection is the lane's own "something
# else"; the carries holds the rule's name and the file's path, and the message a person reads is
# composed from that carries by escalation_write, never here and never twice.
escalate_rejection() {
  escalation_write "$1" "$2" "$3" "$4" other lane "$(jq -nc --arg r "$5" --arg p "$6" \
    '{rule: $r, path: $p}')"
}

# attempt_for_session <project> <milestone> <session>: the attempt a session belongs to, found by
# the dispatch or copy_fork event that names it. A session Baton never dispatched — M01, run by
# hand — belongs to no attempt, and the field is then absent from the event rather than guessed.
attempt_for_session() {
  afs_log=$(log_json) || { echo "$afs_log"; return 1; }
  printf '%s' "$afs_log" | jq -r --arg p "$1" --arg m "$2" --arg s "$3" '
    [ .[] | select(.project == $p and .milestone == $m and .session == $s
                   and (.kind == "dispatch" or .kind == "copy_fork")) ]
    | last | .attempt // empty'
}

# archive_move <file> <consumed-at>: the move that is the consumption. The suffix exists because
# one session may end more than once — an api-error, then its real handover under the same inbox
# name. Prints the archived path.
archive_move() {
  am_dest=$BATON_HOME/archive/$(basename "$1" .json)-$2.json
  mkdir -p "$BATON_HOME/archive"
  mv "$1" "$am_dest"
  printf '%s\n' "$am_dest"
}

# reject_move <file>: rejected files move to rejected/ and keep their name. Prints the path.
reject_move() {
  mkdir -p "$BATON_HOME/rejected"
  rm_dest=$BATON_HOME/rejected/$(basename "$1")
  mv "$1" "$rm_dest"
  printf '%s\n' "$rm_dest"
}

# reject <file> <rule> <detail>: the move first, then the rejected event and the lane escalation.
# The move leads because the move is what makes the decision once — the file leaves the inbox and
# the next tick's glob cannot find it again (INV-06). A tick killed between the move and the event
# loses the record, and that is the accepted trade: a file sitting in rejected/ with no event is
# visible and harmless, while a file rejected twice would escalate the same lane twice.
reject() {
  rj_ids=$(artifact_ids "$1")
  rj_milestone=$(printf '%s' "$rj_ids" | jq -r .milestone)
  rj_session=$(printf '%s' "$rj_ids" | jq -r .session)
  rj_project=$(project_key_of "$(printf '%s' "$rj_ids" | jq -r '.project // ""')" 2>/dev/null || echo '')
  rj_attempt=''
  if [ -n "$rj_project" ]; then
    rj_attempt=$(attempt_for_session "$rj_project" "$rj_milestone" "$rj_session") \
      || { echo "baton: $rj_attempt" >&2; return 1; }
  else
    # A file that cannot name its own project — truncated, unparseable, or naming a checkout Baton
    # does not know — still belongs to a lane if Baton dispatched the session, and the log says so.
    # Without a lane the escalation has no verb, so this is what makes the rejection answerable.
    rj_lane=$(lane_of_session "$rj_session") || { echo "baton: $rj_lane" >&2; return 1; }
    rj_project=$(printf '%s' "$rj_lane" | jq -r '.project // empty')
    rj_attempt=$(printf '%s' "$rj_lane" | jq -r '.attempt // empty')
  fi
  rj_dest=$(reject_move "$1")
  log_event rejected "$rj_project" "$rj_milestone" "$rj_session" "$rj_attempt" \
    "$(jq -nc --arg p "$rj_dest" --arg r "$2" '{path: $p, reason: $r}')"
  escalate_rejection "$rj_project" "$rj_milestone" "$rj_session" "$rj_attempt" "$2" "$rj_dest"
  printf 'rejected  %s → %s (%s: %s)\n' "$(basename "$1")" "$rj_dest" "$2" "$3"
}

# inbox_consume <rows json> [<rows were read: yes|no>]: every *.json in the inbox, never a .tmp, in
# name order; then the .tmp orphans, but only when the rows were actually read. Prints one line per
# file saying what was decided.
inbox_consume() {
  for ic_f in "$BATON_HOME"/inbox/*.json; do
    [ -f "$ic_f" ] || continue
    if ic_ok=$(artifact_check "$ic_f"); then
      consume_one "$ic_f" "$ic_ok" "$1"
    else
      # jq answers an empty document with an empty string and a zero status, so a check that died
      # without naming a rule would reject the file under a blank rule and say nothing useful. Name
      # that case instead, so a bug in the checks is visible in the log rather than silent.
      ic_rule=$(printf '%s' "$ic_ok" | jq -r '.rule // empty' 2>/dev/null || true)
      ic_detail=$(printf '%s' "$ic_ok" | jq -r '.detail // empty' 2>/dev/null || true)
      if [ -z "$ic_rule" ]; then
        ic_rule=check-failed
        ic_detail="the checks ended without naming a rule; they printed: $ic_ok"
      fi
      reject "$ic_f" "$ic_rule" "$ic_detail"
    fi
  done
  # A .tmp is a handover half-written. Its session having no live row with a pid says the writer
  # is gone and the file will never be completed, which is an orphan.
  #
  # Only when the rows were read, though. A listing the service could not produce arrives here as
  # an empty array, under which every session reads as gone — and a session in the window between
  # writing its .tmp and renaming it would have its handover moved to rejected/, its own `mv` would
  # then fail, and the handover would be lost. The window is milliseconds and the loss is
  # unrecoverable, so the sweep waits for a tick that can see the rows.
  [ "${2:-yes}" = yes ] || return 0
  for ic_t in "$BATON_HOME"/inbox/*.json.tmp; do
    [ -f "$ic_t" ] || continue
    ic_sid=$(artifact_ids "$ic_t" | jq -r .session)
    if printf '%s' "$1" | jq -e --arg s "$ic_sid" 'any(.[]; .sessionId == $s and .pid != null)' > /dev/null; then
      continue
    fi
    reject "$ic_t" orphan-tmp "no live row with a pid carries session $ic_sid"
  done
}

# consume_one <file> <artifact_check document> <rows json>: the decision for one checked artifact
# — the stop an asking artifact earns, the routing a declared stop earns, the move, the consumed
# event, and the entry rejections the brief pointers earned.
consume_one() {
  co_a=$(printf '%s' "$2" | jq -c .artifact)
  co_project=$(printf '%s' "$2" | jq -r .project)
  co_written_by=$(printf '%s' "$2" | jq -r .written_by)
  co_milestone=$(printf '%s' "$co_a" | jq -r .milestone)
  co_session=$(printf '%s' "$co_a" | jq -r .session)
  co_outcome=$(printf '%s' "$co_a" | jq -r .outcome)
  co_reason=$(printf '%s' "$co_a" | jq -r '.reason // ""')
  co_attempt=$(attempt_for_session "$co_project" "$co_milestone" "$co_session") \
    || { echo "baton: $co_attempt" >&2; return 1; }
  co_note=$co_outcome

  # An asking session is stopped at once, so that the ruling M05 delivers resumes it under the
  # same id rather than racing a session that is still holding the prompt open. The verb takes the
  # background job's id, which only the row carries; a session with no live row is already stopped.
  # Only a session Baton dispatched is ever stopped: an empty attempt means no dispatch event names
  # this session, and Baton never stops what it did not start.
  if [ "$co_outcome" = asking ]; then
    co_job=''
    [ -z "$co_attempt" ] || co_job=$(printf '%s' "$3" | jq -r --arg s "$co_session" \
      'map(select(.sessionId == $s and .pid != null)) | first | .id // empty')
    if [ -n "$co_job" ]; then
      "$BATON_CLAUDE" stop "$co_job" > /dev/null 2>&1 || true
      co_note="asking, stopped $co_job"
    else
      co_note="asking, no live row to stop"
    fi
  fi
  if [ "$co_outcome" = stopped ]; then
    co_note="stopped, $co_reason → $(stop_route "$co_reason")"
  fi
  if [ "$co_outcome" = complete ]; then
    co_note="complete, merged_as $(printf '%s' "$co_a" | jq -r .merged_as)"
  fi
  # REQ-ARTIFACT-03: a missing context on an asking artifact is a warning, not a rejection. This is
  # where the person hears it.
  if [ "$co_outcome" = asking ] && ! printf '%s' "$co_a" | jq -e 'has("context")' > /dev/null; then
    co_note="$co_note, no context"
  fi

  # The event is composed before the move, and the three fields an outside process sizes — error,
  # detail's neighbours blocked_by and merged_as — are cut the way dispatch_failed cuts its detail.
  # log_event refuses a line at 4 KB, and a refusal after the move would leave an archived file
  # with no consumed event, which derivation 1 then reads as a lane still open.
  co_fields=$(printf '%s' "$co_a" | jq -c --arg w "$co_written_by" '
    (if .outcome == "stopped" then {outcome, reason, error, blocked_by} else {outcome, merged_as} end)
    | with_entries(select(.value != null))
    | with_entries(if (.value | type) == "string" and (.value | length) > 500
                   then .value |= (.[0:500] + "…") else . end)
    | . + {written_by: $w}')

  co_at=$(baton_now)
  co_archive=$(archive_move "$1" "$co_at")
  log_event consumed "$co_project" "$co_milestone" "$co_session" "$co_attempt" \
    "$(printf '%s' "$co_fields" | jq -c --arg a "$co_archive" '. + {archive: $a}')"
  printf 'consumed  %s → %s (%s)\n' "$(basename "$1")" "$co_archive" "$co_note"

  # A brief pointer that is not on main rejects that entry, not the file: the handover is still
  # the session's word about its own milestone, and only the entry it cannot support is dropped.
  co_dn=$(printf '%s' "$2" | jq '.dropped | length')
  co_i=0
  while [ "$co_i" -lt "$co_dn" ]; do
    co_d=$(printf '%s' "$2" | jq -c ".dropped[$co_i]")
    co_i=$((co_i + 1))
    co_dm=$(printf '%s' "$co_d" | jq -r '.milestone // ""')
    log_event rejected "$co_project" "$co_dm" "" "" \
      "$(jq -nc --arg p "$co_archive" '{path: $p, reason: "brief-pointer"}')"
    escalate_rejection "$co_project" "$co_dm" "" "" brief-pointer "$co_archive"
    printf 'dropped   %s entry of %s (%s)\n' "$co_dm" "$(basename "$1")" "$(printf '%s' "$co_d" | jq -r .detail)"
  done
}
