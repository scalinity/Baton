#!/bin/sh
# lib/inbox.sh — step 2 of the tick: the inbox consumed the way the tick will consume it. Every
# artifact is parsed, checked for provenance and for the facts it claims, and then either archived
# under its consumed-at name with a consumed event or moved to rejected/ with a rejected event and
# a lane escalation. Consumption is the move (INV-06): a file in the inbox has not been acted on,
# one in the archive has, so a second run over the same inbox does nothing; and a file that repeats a
# handover already consumed is archived with a repeated event and acted on not at all, so a handover is
# acted on once however often it is delivered, for as long as an archived copy of it stands. On failure every function prints its detail on stdout
# and returns non-zero (D-030).
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

# artifact_ids <file>: JSON supplies each identity field when present; the filename supplies a
# missing one. Search the longest parse_id prefix that leaves a complete session id (D-118).
# A failed recovery returns a diagnostic, never guessed identities that could move a live .tmp.
artifact_ids() {
  ai_base=${1##*/}; ai_base=${ai_base%.tmp}; ai_base=${ai_base%.json}
  ai_milestone=; ai_session=; ai_prefix=$ai_base
  while [ "${ai_prefix%-*}" != "$ai_prefix" ]; do
    ai_prefix=${ai_prefix%-*}
    parse_id "$ai_prefix" > /dev/null || continue
    ai_tail=${ai_base#"$ai_prefix"-}
    # UUIDs and the bare hexadecimal ids used by fixtures. Checking the complete shape keeps
    # M02-<uuid>'s first UUID group from becoming a milestone suffix with a truncated session.
    printf '%s\n' "$ai_tail" | grep -Eq '^([0-9a-fA-F]+|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$' || continue
    ai_milestone=$ai_prefix; ai_session=$ai_tail
    break
  done
  ai_ids=$(jq -c --arg m "$ai_milestone" --arg s "$ai_session" \
    '{milestone: (.milestone // $m), session: (.session // $s), project: .project}
     | with_entries(select(.value != null))' "$1" 2>/dev/null) || ai_ids=
  [ -n "$ai_ids" ] || ai_ids=$(jq -nc --arg m "$ai_milestone" --arg s "$ai_session" '{milestone: $m, session: $s}')
  if ai_milestone=$(printf '%s' "$ai_ids" | jq -er '.milestone | select(type == "string")') \
     && ai_session=$(printf '%s' "$ai_ids" | jq -er '.session | select(type == "string")') \
     && parse_id "$ai_milestone" > /dev/null && session_id_ok "$ai_session"; then
    printf '%s\n' "$ai_ids"
    return 0
  fi
  printf 'cannot recover milestone and session from %s; left in inbox\n' "$ai_base"
  return 1
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
  ac_completion='{}'
  case "$ac_outcome" in
    complete)
      ac_detail=$(completion_reserved_check "$ac_a") \
        || { jq -nc --arg d "$ac_detail" '{rule: "reserved-field", detail: $d}'; return 1; }
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
      # Last of the complete checks, because it is the only expensive one: it asks git four
      # questions and then runs the project's standing check on a tree of its own. A file that
      # fails a cheap rule never reaches it, and a file that reaches it is one whose every other
      # rule has held. Its refusals are rejections; a check that ran and failed is not one, and
      # arrives here as a result the consume records and parks on (M10 §7.4).
      ac_completion=$(completion_verify "$ac_path" "$ac_key" \
        "$(printf '%s' "$ac_a" | jq -r .milestone)" "$ac_session" "$ac_merged") || {
        jq -nc --argjson c "$ac_completion" '$c'
        return 1
      }
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
    --argjson d "$ac_dropped" --argjson c "$ac_completion" \
    '{artifact: $a, project: $k, written_by: $w, dropped: $d}
     | if ($c | length) > 0 then . + {completion: $c} else . end'
}

# escalate_rejection <project> <milestone> <session> <attempt> <rule> <path>: the lane escalation
# a rejection raises. The class list is the log's and a rejection is the lane's own "something
# else"; the carries holds the rule's name and the file's path, and the message a person reads is
# composed from that carries by `escalate`, never here and never twice.
escalate_rejection() {
  escalate "$1" "$2" "$3" "$4" other lane "$(jq -nc --arg r "$5" --arg p "$6" \
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
# name. Prints the archived path; on failure prints why and returns 1, having moved nothing.
#
# Each step is checked by hand, because the tick runs its whole call tree where `set -e` does not
# stop a failed command: an unchecked failure here printed an empty path, and the caller wrote a
# consumed event for a file still in the inbox, again on every tick. A name already taken is refused
# rather than overwritten, since the file under it is a record of its own.
archive_move() {
  am_dest=$BATON_HOME/archive/$(basename "$1" .json)-$2.json
  mkdir -p "$BATON_HOME/archive" 2>/dev/null || { echo "$BATON_HOME/archive is not a directory Baton can write"; return 1; }
  [ ! -e "$am_dest" ] || { echo "$am_dest already exists"; return 1; }
  mv "$1" "$am_dest" 2>/dev/null || { echo "$1 could not be moved to $am_dest"; return 1; }
  printf '%s\n' "$am_dest"
}

# reject_move <file>: rejected files move to rejected/ and keep their name. Prints the path; on
# failure prints why and returns 1, for the reason archive_move does.
reject_move() {
  mkdir -p "$BATON_HOME/rejected" 2>/dev/null || { echo "$BATON_HOME/rejected is not a directory Baton can write"; return 1; }
  rm_dest=$BATON_HOME/rejected/$(basename "$1")
  mv "$1" "$rm_dest" 2>/dev/null || { echo "$1 could not be moved to $rm_dest"; return 1; }
  printf '%s\n' "$rm_dest"
}

# reject <file> <rule> <detail>: the move first, then the rejected event and the lane escalation.
# The move leads because the move is what makes the decision once — the file leaves the inbox and
# the next tick's glob cannot find it again (INV-06). A tick killed between the move and the event
# loses the record, and that is the accepted trade: a file sitting in rejected/ with no event is
# visible and harmless, while a file rejected twice would escalate the same lane twice.
reject() {
  rj_ids=$(artifact_ids "$1") || { render_failure err "baton: $rj_ids"; return 1; }
  rj_milestone=$(printf '%s' "$rj_ids" | jq -r .milestone)
  rj_session=$(printf '%s' "$rj_ids" | jq -r .session)
  rj_project=$(project_key_of "$(printf '%s' "$rj_ids" | jq -r '.project // ""')" 2>/dev/null || echo '')
  rj_attempt=''
  if [ -n "$rj_project" ]; then
    rj_attempt=$(attempt_for_session "$rj_project" "$rj_milestone" "$rj_session") \
      || { render_failure err "baton: $rj_attempt"; return 1; }
  else
    # A file that cannot name its own project — truncated, unparseable, or naming a checkout Baton
    # does not know — still belongs to a lane if Baton dispatched the session, and the log says so.
    # Without a lane the escalation has no verb, so this is what makes the rejection answerable.
    rj_lane=$(lane_of_session "$rj_session") || { render_failure err "baton: $rj_lane"; return 1; }
    rj_project=$(printf '%s' "$rj_lane" | jq -r '.project // empty')
    rj_attempt=$(printf '%s' "$rj_lane" | jq -r '.attempt // empty')
  fi
  rj_dest=$(reject_move "$1") || { render_failure err "baton: $rj_dest"; return 1; }
  log_event rejected "$rj_project" "$rj_milestone" "$rj_session" "$rj_attempt" \
    "$(jq -nc --arg p "$rj_dest" --arg r "$2" '{path: $p, reason: $r}')"
  escalate_rejection "$rj_project" "$rj_milestone" "$rj_session" "$rj_attempt" "$2" "$rj_dest"
  render_row out action 'rejected  %s → %s (%s: %s)\n' \
    "$(render_token out path "$(basename "$1")")" "$(render_token out path "$rj_dest")" "$2" "$3"
}

# repeat_of <file>: the consumed event of the handover this file repeats, when it repeats one. A file
# repeats a handover when it holds the same JSON value as the archived file of a `consumed` event for
# the same milestone and session (D-095). The value and not the bytes, because the Stop gate's printed
# fallback writes the fence's text rather than the session's file; `written_at` stays in the value,
# because it is the one field that tells two of the gate's `no-handover` endings with the same words
# apart, and each is a failure ending the ladder counts. The copies compared are every archived file
# the handover left: the first, and each earlier repeat's, so a person moving the first file aside does
# not turn the next delivery into a second consumption. A handover with no archived copy left can no
# longer be recognised, and a file with nothing to compare against is acted on, never skipped on a
# guess. Prints the consumed event and returns 0 for a repeat; prints nothing and returns 1 when the
# file repeats nothing; prints the detail and returns 2 when the log cannot be read, so the caller
# leaves the file for a tick that can read it.
#
# The log is derived again for every file rather than once before the inbox loop, because the loop
# writes to it: a second file holding a handover consumed earlier in the same pass is a repeat only
# once the first one's consumed event can be read.
repeat_of() {
  ro_one='if length == 1 and (.[0] | type) == "object" then .[0] else empty end'
  ro_v=$(jq -cSs "$ro_one" "$1" 2>/dev/null) || return 1
  [ -n "$ro_v" ] || return 1
  # Without both ids as strings the file can name no handover; artifact_check rejects it. The guard
  # sits here because `null == null` holds in jq and would match an event with the same field absent.
  printf '%s' "$ro_v" | jq -e '(.milestone | type) == "string" and (.session | type) == "string"' \
    > /dev/null 2>&1 || return 1
  ro_doc=$(derive_consumed "") || { echo "$ro_doc"; return 2; }
  # Each copy is {file, first}: the archived file to compare and the consumed event of the handover it
  # is a copy of, which is the envelope and the `repeats` a match is recorded under.
  ro_copies=$(printf '%s' "$ro_doc" | jq -c --argjson v "$ro_v" '
    [ .consumed[] | select(.milestone == $v.milestone and .session == $v.session) ] as $mine
    | [ ($mine[] | select(.archive_present) | {file: .archive, first: .}),
        (.repeated[] | select(.archive_present and .milestone == $v.milestone and .session == $v.session)
         | .repeats as $r | first($mine[] | select(.archive == $r)) as $c | {file: .archive, first: $c}) ]' \
    2>/dev/null) || ro_copies='[]'
  ro_n=$(printf '%s' "$ro_copies" | jq length 2>/dev/null) || ro_n=0
  ro_n=${ro_n:-0}; ro_i=0
  while [ "$ro_i" -lt "$ro_n" ]; do
    ro_c=$(printf '%s' "$ro_copies" | jq -c ".[$ro_i]"); ro_i=$((ro_i + 1))
    ro_a=$(printf '%s' "$ro_c" | jq -r .file)
    [ "$(jq -cSs "$ro_one" "$ro_a" 2>/dev/null || true)" = "$ro_v" ] || continue
    printf '%s' "$ro_c" | jq -c .first
    return 0
  done
  return 1
}

# repeat_one <file> <consumed event>: what a repeat writes. The move, as for any handover — out of the
# inbox, so the next tick cannot find it, and into the archive beside the first, because a repeat is
# not a refusal and a rejection would park a lane over a file that asks nothing (INV-06). Then one
# `repeated` event naming the archived file it repeats, under the first one's envelope. No stop, no
# route, no park and no consumed event: every rule that acts on an ending reads `consumed`, and the
# ranking of handovers in force reads only those, so a repeat has no place in either.
repeat_one() {
  rp_first=$(printf '%s' "$2" | jq -r .archive)
  rp_archive=$(archive_move "$1" "$(baton_now)") || { render_failure err "baton: $rp_archive"; return 1; }
  log_event repeated "$(printf '%s' "$2" | jq -r '.project // ""')" "$(printf '%s' "$2" | jq -r .milestone)" \
    "$(printf '%s' "$2" | jq -r .session)" "$(printf '%s' "$2" | jq -r '.attempt // ""')" \
    "$(printf '%s' "$2" | jq -c --arg a "$rp_archive" '{outcome, archive: $a, repeats: .archive}
                                                      | with_entries(select(.value != null))')"
  render_row out record 'repeated  %s → %s (repeats %s, acted on once)\n' \
    "$(render_token out path "$(basename "$1")")" "$(render_token out path "$rp_archive")" \
    "$(render_token out path "$(basename "$rp_first")")"
}

# inbox_consume <rows json> [<rows were read: yes|no>]: every *.json in the inbox, never a .tmp, in
# name order; then the .tmp orphans, but only when the rows were actually read. Prints one line per
# file saying what was decided. The repeat test comes first, so a handover already acted on is not
# checked again: a transcript since removed would otherwise reject it and park its lane.
inbox_consume() {
  ic_status=0
  inbox_reconcile "$1" || ic_status=1
  for ic_f in "$BATON_HOME"/inbox/*.json; do
    [ -f "$ic_f" ] || continue
    # Every branch that leaves work undone is counted, because the pass's status is what decides
    # whether the tick may write its marker (D-115). `consume_one` and `repeat_one` both return 1
    # when `archive_move` refuses, and a refusal is a handover still in the inbox with nothing in the
    # log; a repeat test that could not read the log leaves its file for the next tick in the same
    # way. Reported as success, any of the three would advance `last-tick` over work that did not
    # happen, and the gap that follows would be measured from a tick that did not do it (D-133).
    ic_rc=0; ic_repeat=$(repeat_of "$ic_f") || ic_rc=$?
    if [ "$ic_rc" -eq 0 ]; then
      repeat_one "$ic_f" "$ic_repeat" || ic_status=1
    elif [ "$ic_rc" -eq 2 ]; then
      render_failure err "baton: $ic_repeat"
      ic_status=1
    elif ic_ok=$(artifact_check "$ic_f"); then
      consume_one "$ic_f" "$ic_ok" "$1" || ic_status=1
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
      reject "$ic_f" "$ic_rule" "$ic_detail" || ic_status=1
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
  [ "${2:-yes}" = yes ] || return "$ic_status"
  for ic_t in "$BATON_HOME"/inbox/*.json.tmp; do
    [ -f "$ic_t" ] || continue
    if ! ic_ids=$(artifact_ids "$ic_t"); then
      render_failure err "baton: $ic_ids"
      ic_status=1
      continue
    fi
    ic_sid=$(printf '%s' "$ic_ids" | jq -r .session)
    if printf '%s' "$1" | jq -e --arg s "$ic_sid" 'any(.[]; .sessionId == $s and .pid != null)' > /dev/null; then
      continue
    fi
    reject "$ic_t" orphan-tmp "no live row with a pid carries session $ic_sid" || ic_status=1
  done
  return "$ic_status"
}

# consume_settle <archived path> <artifact json> <project> <written_by> <rows json> <completion json>
# <from>: everything a consumption decides once the artifact is in the archive — the stop an asking
# artifact earns, the note, the `consumed` event, the line a person reads and the ending that needs
# one. Split out because the reconciliation of a lost receipt has to do exactly this and nothing
# else, and a second copy of it would be a second set of rules (D-146).
#
# <from> is the inbox name the file arrived under, for the line; an empty <from> is a reconciliation,
# whose file has no inbox name any more. <completion json> is Baton's evidence for a `complete`
# outcome, `{}` where there is none.
consume_settle() {
  cs_archive=$1; cs_a=$2; cs_project=$3; cs_written_by=$4; cs_rows=$5; cs_completion=$6; cs_from=${7:-}
  cs_milestone=$(printf '%s' "$cs_a" | jq -r .milestone)
  cs_session=$(printf '%s' "$cs_a" | jq -r .session)
  cs_outcome=$(printf '%s' "$cs_a" | jq -r .outcome)
  cs_reason=$(printf '%s' "$cs_a" | jq -r '.reason // ""')
  cs_attempt=$(attempt_for_session "$cs_project" "$cs_milestone" "$cs_session") \
    || { render_failure err "baton: $cs_attempt"; return 1; }
  cs_note=$cs_outcome

  # The three fields an outside process sizes — error, detail's neighbours blocked_by and merged_as
  # — are cut the way dispatch_failed cuts its detail, because log_event refuses a line at 4 KB and
  # a refusal here would leave an archived file with no consumed event, which derivation 1 then
  # reads as a lane still open. Baton's own completion evidence is bounded at its source.
  cs_fields=$(printf '%s' "$cs_a" | jq -c --arg w "$cs_written_by" --argjson c "$cs_completion" '
    (if .outcome == "stopped" then {outcome, reason, error, blocked_by} else {outcome, merged_as} end)
    | with_entries(select(.value != null))
    | with_entries(if (.value | type) == "string" and (.value | length) > 500
                   then .value |= (.[0:500] + "…") else . end)
    | . + {written_by: $w}
    | if ($c | length) > 0 then . + {completion: $c} else . end')

  # An asking session is stopped at once, so that the ruling M05 delivers resumes it under the
  # same id rather than racing a session that is still holding the prompt open. The verb takes the
  # background job's id, which only the row carries; a session with no live row is already stopped.
  # Only a session Baton dispatched is ever stopped: an empty attempt means no dispatch event names
  # this session, and Baton never stops what it did not start.
  if [ "$cs_outcome" = asking ]; then
    cs_job=''
    [ -z "$cs_attempt" ] || cs_job=$(printf '%s' "$cs_rows" | jq -r --arg s "$cs_session" \
      'map(select(.sessionId == $s and .pid != null)) | first | .id // empty')
    if [ -n "$cs_job" ]; then
      "$BATON_CLAUDE" stop "$cs_job" > /dev/null 2>&1 || true
      cs_note="asking, stopped $cs_job"
    else
      cs_note="asking, no live row to stop"
    fi
  fi
  if [ "$cs_outcome" = stopped ]; then
    cs_note="stopped, $cs_reason → $(stop_route "$cs_reason")"
  fi
  if [ "$cs_outcome" = complete ]; then
    cs_note="complete, merged_as $(printf '%s' "$cs_a" | jq -r .merged_as)"
    # `has`, not `//`: jq's alternative operator treats `false` as absent, so `.proved // empty`
    # answers empty for exactly the case this line exists to name.
    cs_proved=$(printf '%s' "$cs_completion" | jq -r 'if has("proved") then (.proved | tostring) else "" end' \
      2>/dev/null || true)
    case "$cs_proved" in
      true) cs_note="$cs_note, $(printf '%s' "$cs_completion" | jq -r '
              "\(.changed_count) path\(if .changed_count == 1 then "" else "s" end) changed, check \(.check.outcome)"')" ;;
      false) cs_note="$cs_note, unproved" ;;
    esac
  fi
  # REQ-ARTIFACT-03: a missing context on an asking artifact is a warning, not a rejection. This is
  # where the person hears it.
  if [ "$cs_outcome" = asking ] && ! printf '%s' "$cs_a" | jq -e 'has("context")' > /dev/null; then
    cs_note="$cs_note, no context"
  fi

  # The receipt is the thing everything after it assumes. A refused line — no lock, or a record past
  # the 4 KB limit — used to be stepped over, and the function went on to park a project and print a
  # line about a consumption the log does not hold; the next tick would then find the file
  # unrecorded, reconcile it, and park the same project again, once a minute. Returning here leaves
  # exactly one thing owed, which `inbox_reconcile` is what finishes (D-152).
  log_event consumed "$cs_project" "$cs_milestone" "$cs_session" "$cs_attempt" \
    "$(printf '%s' "$cs_fields" | jq -c --arg a "$cs_archive" --arg f "$cs_from" \
       '. + {archive: $a} | if $f == "" then . + {reconciled: true} else . end')" || {
    render_failure err "baton: $cs_project/$cs_milestone the consumed event was refused; the archived handover is left for a later tick to reconcile"
    return 1
  }
  if [ -n "$cs_from" ]; then
    render_row out record 'consumed  %s → %s (%s)\n' \
      "$(render_token out path "$cs_from")" "$(render_token out path "$cs_archive")" "$cs_note"
  else
    render_row out action 'reconciled  %s (%s; its consumed event was lost after the move)\n' \
      "$(render_token out path "$(basename "$cs_archive")")" "$cs_note"
  fi

  # The endings that need a person, parked here because here is where the artifact is in hand: the
  # question with its options, or the sentence the session wrote about what it could not do. The
  # class is the taxonomy's — `route_ending`'s, whose `escalate` action names these three plus
  # `model_not_found`, which step 4 parks instead because only the plan tells it which cell to name,
  # and whose `park-project` action is `main-broken`. The consume is once by the move, so the park is
  # written once for the same reason (INV-06); everything else the table routes reads the log rather
  # than the file.
  cs_class=$(route_ending "$cs_outcome" "$cs_reason" | jq -r .class)
  case "$cs_class" in
    asking|merge-failed|other|main-broken)
      ending_escalate "$cs_project" "$cs_milestone" "$cs_session" "$cs_attempt" "$cs_a" \
        "$cs_class" "$cs_archive" ;;
  esac

  # A standing check Baton ran and that did not pass is the broken-main ending, arrived at by
  # Baton's own run rather than by the session's word for it. The class is `main-broken` and not a
  # new one: what failed is the combined tree on `main` that every lane of the project stands on,
  # which is the same fact, found a different way, and it releases through the same ruling and the
  # same re-read. The handover is still consumed — the work really did merge, and leaving it in the
  # inbox would have the next tick check it again — and the park is what stops the chain (D-151).
  cs_check=$(printf '%s' "$cs_completion" | jq -r '.check.outcome // empty' 2>/dev/null || true)
  case "$cs_check" in
    ''|passed) ;;
    *)
      # Guarded, for `ending_escalate`'s reason: a park that could not be written is a chain that
      # goes on running over a tree Baton has just established does not build, with nothing saying
      # so. The carries is a command, a revision and a path, so only a missing lock refuses it.
      escalate "$cs_project" "$cs_milestone" "$cs_session" "$cs_attempt" main-broken project \
        "$(completion_park_carries "$cs_completion" "$cs_archive")" \
        || render_failure err "baton: $cs_project/$cs_milestone the standing check did not pass and the project park could not be written; a later tick owes it"
      render_row out action 'check     %s · %s\n' "$(render_token out milestone "$cs_milestone")" \
        "$(printf '%s' "$cs_completion" | jq -r '"the standing check \(.check.outcome) at \(.check.revision)"')" ;;
  esac
}

# inbox_reconcile <rows json>: the archived artifact whose `consumed` event is missing, finished.
#
# The inbox pass moves a file through `archive_move` before appending its event, because the move
# is the consumption and a file rejected twice would escalate the same lane twice (INV-06). A tick
# killed in that window leaves a file in the archive that no event claims: derivation 4 names it
# under `unrecorded`, derivation 1 reads its lane as still open, and M03's crash rule sights a
# session that ended properly. Nothing advanced and nothing said so (F07).
#
# The receipt is written here, on a later tick, with `reconciled` on the event so the record says
# which consumptions were finished rather than made. This is a receipt write and not a second
# verification: `archive_move` runs only after `artifact_check` passed, so an archived file is a
# checked file by construction, and Baton's completion evidence was written to its own file before
# the move and is read back from there (D-146).
#
# It is the inbox pass's first act, before any file in the inbox is looked at, because every rule
# after that point — the repeat test, the attempt lookup, and outside this file the crash rule and
# the ladder — reads the log this writes into. Finishing the older consumption before reading it is
# what keeps a tick from deciding about a lane that closed minutes ago.
inbox_reconcile() {
  ir_status=0
  # Its own words, not the derivation's verbatim: the repeat test reads the same log a moment later
  # and reports the same failure, and two identical lines about one torn file read as a stutter
  # rather than as two things that could not be done.
  ir_doc=$(derive_consumed "") \
    || { render_failure err "baton: no archived handover can be reconciled this tick: $ir_doc"; return 1; }
  ir_n=$(printf '%s' "$ir_doc" | jq '[ .unrecorded[] | select(.where == "archive") ] | length')
  ir_i=0
  while [ "$ir_i" -lt "$ir_n" ]; do
    ir_name=$(printf '%s' "$ir_doc" | jq -r "[ .unrecorded[] | select(.where == \"archive\") ][$ir_i].file")
    ir_i=$((ir_i + 1))
    ir_file=$BATON_HOME/archive/$ir_name
    [ -f "$ir_file" ] || continue
    # The archived file says what it is. A file that cannot be parsed back into an artifact is left
    # where it is and named: it is already out of the inbox and harmless, and guessing a lane for it
    # would write an event about a milestone nothing establishes.
    ir_a=$(jq -ce 'if type == "object" then . else error("not an object") end' "$ir_file" 2>/dev/null) || ir_a=''
    ir_key=''
    [ -z "$ir_a" ] || ir_key=$(project_key_of "$(printf '%s' "$ir_a" | jq -r '.project // ""')" 2>/dev/null || echo '')
    if [ -z "$ir_a" ] || [ -z "$ir_key" ] \
       || ! printf '%s' "$ir_a" | jq -e '(.milestone | type) == "string" and (.session | type) == "string"
                                          and (.outcome | type) == "string"' > /dev/null 2>&1; then
      # Reported and not counted against the pass. A file that cannot be read back into a lane is
      # left where it is and is harmless there — but counting it as work undone would make every
      # later tick incomplete, so `last-tick` would freeze, `status` would show a gap growing
      # without end, and the marker would never advance again over one stray file nobody has to act
      # on (D-133 counts work that did not happen, and this is work there is none of). A
      # `consume_settle` that failed still counts, because that is a receipt owed and not written.
      render_failure err "baton: $ir_name sits in the archive with no event and cannot be read back into a lane; it is left as it is and nothing waits on it"
      continue
    fi
    # Whose receipt was lost decides what is written. `repeat_one` moves a repeat into the archive
    # before appending its `repeated` event, exactly as `consume_one` does, so the same crash window
    # strands a repeat's copy too — and derivation 4 calls it `unrecorded` either way, because the
    # claim it looks for is over both kinds of event. Settling that copy would write a *second*
    # `consumed` event for a handover already acted on: a second ladder reset, a second park, a
    # second stop of an asking session, the double action D-095 exists to forbid, reached through
    # the very window this recovery was written to heal. So the repeat test comes first here for the
    # same reason it comes first in the pass below, and a copy that repeats a consumed handover gets
    # the `repeated` event it never got and nothing that acts on an ending (D-152).
    ir_rc=0; ir_first=$(repeat_of "$ir_file") || ir_rc=$?
    if [ "$ir_rc" -eq 2 ]; then
      render_failure err "baton: $ir_name sits in the archive with no event and the log cannot be read: $ir_first"
      ir_status=1
      continue
    fi
    if [ "$ir_rc" -eq 0 ]; then
      log_event repeated "$(printf '%s' "$ir_first" | jq -r '.project // ""')" \
        "$(printf '%s' "$ir_first" | jq -r .milestone)" "$(printf '%s' "$ir_first" | jq -r .session)" \
        "$(printf '%s' "$ir_first" | jq -r '.attempt // ""')" \
        "$(printf '%s' "$ir_first" | jq -c --arg a "$ir_file" \
           '{outcome, archive: $a, repeats: .archive, reconciled: true}
            | with_entries(select(.value != null))')" || { ir_status=1; continue; }
      render_row out action 'reconciled  %s (repeats %s, acted on once; its repeated event was lost after the move)\n' \
        "$(render_token out path "$ir_name")" \
        "$(render_token out path "$(basename "$(printf '%s' "$ir_first" | jq -r .archive)")")"
      continue
    fi
    ir_reason=''
    [ "$(printf '%s' "$ir_a" | jq -r .outcome)" != stopped ] || ir_reason=$(printf '%s' "$ir_a" | jq -r '.reason // ""')
    consume_settle "$ir_file" "$ir_a" "$ir_key" "$(written_by_of "$ir_reason")" "$1" \
      "$(reconciled_completion "$ir_key" "$ir_a")" '' || ir_status=1
  done

  # The other thing a killed tick leaves half-done. The `main-broken` park a failing check earns is
  # a second append, a few statements after the `consumed` line that carries the failing result; a
  # tick killed between them, or an `escalate` that refused, leaves a consumed completion whose
  # record says the tree does not build and no park saying so. Nothing else re-derives it —
  # `derive_parked` reads `escalation` events, and the sweep above only finishes files with no
  # receipt at all — so the next tick would dispatch the next milestone onto a `main` Baton has
  # already established is broken, which is the ending this milestone exists to stop (D-152).
  for ir_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$ir_pj" ] || continue
    ir_project=$(basename "$(dirname "$ir_pj")")
    ir_owed=$(completion_park_owed "$ir_project") || { render_failure err "baton: $ir_owed"; ir_status=1; continue; }
    [ -n "$ir_owed" ] || continue
    printf '%s\n' "$ir_owed" | while IFS= read -r ir_one; do
      [ -n "$ir_one" ] || continue
      escalate "$ir_project" "$(printf '%s' "$ir_one" | jq -r '.milestone // ""')" \
        "$(printf '%s' "$ir_one" | jq -r '.session // ""')" \
        "$(printf '%s' "$ir_one" | jq -r '.attempt // ""')" main-broken project \
        "$(completion_park_carries "$(printf '%s' "$ir_one" | jq -c .completion)" \
                                   "$(printf '%s' "$ir_one" | jq -r '.archive // ""')")" || continue
      render_row out action 'reconciled  %s · the standing check did not pass and its project park was never written\n' \
        "$(render_token out milestone "$(printf '%s' "$ir_one" | jq -r '.milestone // ""')")"
    done
  done
  return "$ir_status"
}

# reconciled_completion <project> <artifact>: the completion evidence a reconciliation can still
# read, which is the evidence file `completion_verify` wrote before the move, or `{}` when there is
# none — a stopped or asking ending, a completion Baton did not dispatch, or an evidence file since
# removed. It is read back rather than derived again, because deriving it again would check a
# repository that has moved on since the consumption actually happened.
reconciled_completion() {
  [ "$(printf '%s' "$2" | jq -r .outcome)" = complete ] || { echo '{}'; return 0; }
  rc_milestone=$(printf '%s' "$2" | jq -r .milestone)
  rc_session=$(printf '%s' "$2" | jq -r .session)
  rc_attempt=$(attempt_for_session "$1" "$rc_milestone" "$rc_session") || rc_attempt=''
  [ -n "$rc_attempt" ] || { echo '{}'; return 0; }
  rc_file=$(completion_check_dir "$1" "$rc_milestone" "$rc_attempt")/result.json
  # An evidence file that is gone is said so, rather than left as an absent field: the line would
  # otherwise read "complete, merged_as X" with neither "proved" nor "unproved" against it, and a
  # receipt that says nothing about the thing it is a receipt for is the one shape this milestone
  # is against (D-152).
  [ -f "$rc_file" ] \
    || { jq -nc '{proved: null, why: "the evidence file was not there to read back"}'; return 0; }
  rc_full=$(jq -c . "$rc_file" 2>/dev/null) \
    || { jq -nc '{proved: null, why: "the evidence file could not be read back"}'; return 0; }
  completion_summary "$rc_full" "$rc_file"
}

# consume_one <file> <artifact_check document> <rows json>: the decision for one checked artifact
# — the move, everything `consume_settle` decides once it has moved, and the entry rejections the
# brief pointers earned.
consume_one() {
  co_a=$(printf '%s' "$2" | jq -c .artifact)
  co_project=$(printf '%s' "$2" | jq -r .project)
  co_written_by=$(printf '%s' "$2" | jq -r .written_by)
  co_completion=$(printf '%s' "$2" | jq -c '.completion // {}')

  # The move comes before anything the decision does: a move that fails leaves the file in the
  # inbox for the next tick, and a session stopped ahead of it would be stopped again on every tick.
  co_at=$(baton_now)
  co_archive=$(archive_move "$1" "$co_at") || { render_failure err "baton: $co_archive"; return 1; }

  consume_settle "$co_archive" "$co_a" "$co_project" "$co_written_by" "$3" "$co_completion" \
    "$(basename "$1")" || return 1

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
    render_row out action 'dropped   %s entry of %s (%s)\n' \
      "$(render_token out milestone "$co_dm")" "$(render_token out path "$(basename "$1")")" \
      "$(printf '%s' "$co_d" | jq -r .detail)"
  done
}
