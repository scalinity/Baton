#!/bin/sh
# lib/lifecycle.sh — a finished session's process after its lane has closed: taken offline once it has
# sat idle outside the few most recently active, and woken again on the person's word. Nothing here
# touches an open lane; that is the ladder's.
#
# Why a wake has to be asked for (D-086, D-087): on Claude Code 2.1.270 nothing brings a stopped
# session back when a message is sent to it. The background service's own Remote Control worker is
# compiled off, and a `claude remote-control` server refuses to adopt a `--bg` session, which is
# registered without an environment. A message typed to a stopped session is held on claude.ai and
# delivered only when something on the Mac resumes it. So the most recently active finished sessions
# keep their processes and answer in their own threads, and an older one is reached through one
# always-on Remote Control session, the wake session, which runs `baton wake` for the person.
set -eu

WAKE_SESSION_NAME='Baton · wake'

# lifecycle_finished <log json> <rows json>: every session whose handover Baton consumed as
# `complete`, one per (project, milestone) — the newest — and none for a milestone dispatched again
# since, whose lane is open. Each carries its live row's pid, job and status when a row has a pid.
#
# The session is the one now holding the conversation: the consumed handover's, or the copy a later
# `baton wake` forked into, which the `wake` event names in `copy` — a wake that forked delivered the
# person's words to the copy, so the next wake must address the copy and not start another.
lifecycle_finished() {
  printf '%s' "$1" | jq -c --argjson rows "$2" '
    [ to_entries[] | {i: .key} + .value ] as $ev
    | [ $ev[] | select(.kind == "consumed" and .outcome == "complete" and .session != null) | . as $c
        | select(($ev | any(.kind == "dispatch" and .project == $c.project
                            and .milestone == $c.milestone and .i > $c.i)) | not)
        | ([ $ev[] | select(.kind == "wake" and .project == $c.project and .milestone == $c.milestone
                            and .i > $c.i and .copy != null) ] | last | .copy) as $copy
        | {i, project, milestone, attempt, session: ($copy // .session), consumed_at: .at} ]
    | group_by([.project, .milestone]) | map(max_by(.i))
    | sort_by(.i)
    | map(. as $f | ($rows | map(select(.sessionId == $f.session and .pid != null)) | first) as $row
          | del(.i)
          | if $row == null then . else . + {pid: $row.pid, job: $row.id, status: ($row.status // null)} end
          | with_entries(select(.value != null)))'
}

# offline_check <project> <rows json>: the offline rule. A finished session is taken offline — one
# `claude stop`, one `offline` event — when its row has a pid and reads idle, its transcripts have not
# changed for idleStopMinutes, and it is not among the keepFinished most recently active finished
# sessions with a process. An empty project acts across every project, which is how the tick calls it.
#
# The ranking is across every project, because what it bounds is memory, and memory is the Mac's —
# the cap's reason (D-014). Activity is the newest modification time across the session's transcripts
# (a stat, never a read), so a session a person has just written to, or one `baton wake` has just
# brought back, is recent again and another takes its place at the edge.
#
# A person reading a session changes no transcript, so this rule cannot see a reader; the wake is the
# undo, and idleStopMinutes is an hour so that someone who has just read a handover can follow it up
# without one (D-088). Refused silently: a busy or waiting row, a row with no status, a transcript that
# cannot be stat'd, a recent one, and any lane still open.
#
# Idempotent twice over: the stop takes the pid off the row, and a stop that has not landed by the next
# tick is not repeated, because an `offline` event for the session no older than its transcript already
# stands.
offline_check() {
  oc_log=$(log_json) || { echo "$oc_log" >&2; return 1; }
  oc_fin=$(lifecycle_finished "$oc_log" "$2")
  oc_keep=$(config_num keepFinished 3)
  oc_idle=$(config_num idleStopMinutes 60)
  oc_now=$(now_epoch)

  # The live ones Baton dispatched, each with its activity, newest first; a transcript that cannot be
  # stat'd ranks last. Baton never stops what it did not start (the consume's own rule): a complete
  # handover consumed with no attempt came from a session no dispatch put there — a person's own — so
  # it is neither stopped nor counted against keepFinished, whose slots are for Baton's sessions.
  oc_live='[]'
  oc_n=$(printf '%s' "$oc_fin" | jq 'map(select(has("pid") and has("attempt"))) | length'); oc_i=0
  while [ "$oc_i" -lt "$oc_n" ]; do
    oc_f=$(printf '%s' "$oc_fin" | jq -c --argjson i "$oc_i" 'map(select(has("pid") and has("attempt")))[$i]'); oc_i=$((oc_i + 1))
    oc_mt=$(transcript_mtime "$(printf '%s' "$oc_f" | jq -r .session)") || oc_mt=''
    oc_live=$(printf '%s' "$oc_live" | jq -c --argjson f "$oc_f" --arg mt "$oc_mt" \
      '. + [$f + (if $mt == "" then {} else {mtime: ($mt | tonumber)} end)]')
  done
  oc_live=$(printf '%s' "$oc_live" | jq -c 'sort_by([-(.mtime // -1), .session])')

  oc_n=$(printf '%s' "$oc_live" | jq length); oc_i=0
  while [ "$oc_i" -lt "$oc_n" ]; do
    oc_f=$(printf '%s' "$oc_live" | jq -c --argjson i "$oc_i" '.[$i]'); oc_i=$((oc_i + 1))
    [ "$oc_i" -gt "$oc_keep" ] || continue
    oc_p=$(printf '%s' "$oc_f" | jq -r .project)
    [ -z "$1" ] || [ "$oc_p" = "$1" ] || continue
    [ "$(printf '%s' "$oc_f" | jq -r '.status // ""')" = idle ] || continue
    oc_mt=$(printf '%s' "$oc_f" | jq -r '.mtime // ""')
    [ -n "$oc_mt" ] || continue
    oc_age=$((oc_now - oc_mt))
    [ "$oc_age" -ge $((oc_idle * 60)) ] || continue
    oc_a=$(printf '%s' "$oc_f" | jq -r .attempt)
    oc_s=$(printf '%s' "$oc_f" | jq -r .session)
    ! offline_after "$oc_log" "$oc_s" "$oc_mt" || continue
    oc_m=$(printf '%s' "$oc_f" | jq -r .milestone)
    oc_job=$(printf '%s' "$oc_f" | jq -r .job)
    # The event records a stop the CLI took, never one it refused: the event is what keeps the next tick
    # from stopping again, so recorded over a refusal it would leave the process running for good. A
    # refused stop is said and tried again next tick, which the rank and idle tests bound to the
    # sessions that still qualify.
    if ! oc_err=$("$BATON_CLAUDE" stop "$oc_job" 2>&1 > /dev/null); then
      printf 'offline     %s/%s · %s · the stop was refused, so it is tried again next tick: %s\n' \
        "$oc_p" "$oc_m" "$oc_s" "$(printf '%s' "$oc_err" | cli_plain | head -1)"
      continue
    fi
    log_event offline "$oc_p" "$oc_m" "$oc_s" "$oc_a" "$(jq -nc --arg j "$oc_job" \
      --argjson idle $((oc_age / 60)) --argjson rank "$oc_i" --argjson keep "$oc_keep" \
      '{job: $j, idle_minutes: $idle, rank: $rank, kept: $keep}')"
    printf 'offline     %s/%s · %s · idle %s, not among the %s most recently active\n' \
      "$oc_p" "$oc_m" "$oc_s" "$(duration "$oc_age")" "$oc_keep"
  done
}

# offline_after <log json> <session> <epoch>: whether an `offline` event for the session was written
# at or after the epoch — the stop already issued for the transcript as it now stands.
offline_after() {
  oa_ats=$(printf '%s' "$1" | jq -r --arg s "$2" '.[] | select(.kind == "offline" and .session == $s) | .at')
  [ -n "$oa_ats" ] || return 1
  for oa_at in $oa_ats; do
    [ "$(iso_epoch "$oa_at")" -lt "$3" ] || return 0
  done
  return 1
}

# wake_resume <session> <text>: a flagless `claude --bg --resume`, classified by `resume_classify` as
# every resume is, without the stop, because a session this is asked to wake has no process to stop.
# Prints {outcome, note, copy}.
wake_resume() {
  wr_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-wake.XXXXXX")
  set +e
  "$BATON_CLAUDE" --bg --resume "$1" "$2" > "$wr_tmp" 2> "$wr_tmp.err"
  wr_status=$?
  set -e
  wr_out=$(cli_plain < "$wr_tmp"); wr_err=$(cli_plain < "$wr_tmp.err")
  rm -f "$wr_tmp" "$wr_tmp.err"
  resume_classify "$wr_out" "$wr_err" "$wr_status"
}

# wake_session_prompt: the wake session's standing instruction. It names the relay by absolute path
# and carries Baton's home, as the hooks' command lines do (D-028), so the session reaches the home
# the tick that started it uses.
wake_session_prompt() {
  wsp_baton="BATON_HOME='$BATON_HOME' $BATON_HOME/bin/baton"
  printf '%s\n' "This message is your standing instruction, not a request: reply to it with the single word ready, run nothing, and wait for the person's first message.

You are Baton's wake session. Baton takes a finished milestone's session offline once it has sat idle, and this session is how the person reaches one again from Claude.app or the phone.

Each time the person sends you a message that names a milestone — \"M05: what did you decide about the cap?\", \"wake Reclaim/M19\", \"M07-b\" — run exactly one command:

$wsp_baton wake <milestone> '<the rest of their message, verbatim>'

with the milestone alone when nothing else was said, quoting the message so the shell passes it as one argument. Then reply with the lines the command printed and nothing more. When a message names no milestone, run $wsp_baton wake with no arguments, which lists the finished sessions, and ask which one.

Do nothing else: read no files, edit nothing, run no other command and start no other work. The woken session answers in its own thread in Claude.app."
}

# wake_session_ensure <rows json>: keeps the wake session running once there is something to wake —
# an `offline` event — and not before, because with nothing offline it would be a process with no
# work. The session is identified by the log, never by its name: a stopped session drops out of
# `claude agents --json`, and a tick that started a new one whenever the name was missing would start
# one after every stop. So the session is the newest `wake` event without a milestone that started or
# resumed it; a live row for it means nothing to do; otherwise it is resumed flaglessly, or started
# fresh when it has never been started or its last resume was refused. At most one attempt per
# retryMinutes, so a cause that will not clear costs a line a quarter of an hour, not a minute.
wake_session_ensure() {
  wse_log=$(log_json) || { echo "$wse_log" >&2; return 1; }
  printf '%s' "$wse_log" | jq -e 'any(.[]; .kind == "offline")' > /dev/null || return 0
  wse_last=$(printf '%s' "$wse_log" | jq -c '[ .[] | select(.kind == "wake" and .milestone == null) ] | last // {}')
  wse_cur=$(printf '%s' "$wse_log" | jq -r '[ .[] | select(.kind == "wake" and .milestone == null
                                                 and (.outcome == "delivered" or .outcome == "forked")) ]
                                            | last | .session // empty')
  if [ -n "$wse_cur" ] && printf '%s' "$1" | jq -e --arg s "$wse_cur" 'any(.[]; .sessionId == $s and .pid != null)' > /dev/null; then
    return 0
  fi
  wse_at=$(printf '%s' "$wse_last" | jq -r '.at // empty')
  if [ -n "$wse_at" ] && [ $(( $(now_epoch) - $(iso_epoch "$wse_at") )) -lt $(( $(config_num retryMinutes 15) * 60 )) ]; then
    return 0
  fi
  wse_settings=$BATON_HOME/settings/wake.json
  if [ ! -f "$wse_settings" ]; then
    echo "wake        $wse_settings is missing, so the wake session is not started; sh install.sh writes it"
    return 0
  fi
  wse_text=$(wake_session_prompt)

  if [ -n "$wse_cur" ] && [ "$(printf '%s' "$wse_last" | jq -r '.outcome // ""')" != refused ] \
     && transcript_of "$wse_cur" > /dev/null; then
    # One listing without a pid is not yet a session that is gone: a restart of the background service
    # leaves a live session pid-less for a moment (D-008), and a resume into it forks. So the absence
    # is read again for five seconds, as `stop_settle` reads a stop, before anything is resumed.
    wse_i=0
    while [ "$wse_i" -lt 10 ]; do
      sleep 0.5
      wse_i=$((wse_i + 1))
      wse_again=$(rows_read) || continue
      if printf '%s' "$wse_again" | jq -e --arg s "$wse_cur" 'any(.[]; .sessionId == $s and .pid != null)' > /dev/null; then
        return 0
      fi
    done
    wse_r=$(wake_resume "$wse_cur" "$wse_text")
    wse_o=$(printf '%s' "$wse_r" | jq -r .outcome)
    wse_s=$wse_cur
    if [ "$wse_o" = forked ]; then
      if wse_copy=$(printf '%s' "$wse_r" | jq -re '.copy // empty'); then
        wse_s=$(fork_session "$wse_copy") || wse_s=$wse_copy
      fi
      # The original was running after all: stopped, so two wake sessions do not both answer.
      if wse_again=$(rows_read) && wse_job=$(job_of_session "$wse_again" "$wse_cur") && [ -n "$wse_job" ]; then
        "$BATON_CLAUDE" stop "$wse_job" > /dev/null 2>&1 || true
      fi
    fi
    wse_side=$(sidecar_write "$wse_s" "$wse_text")
    log_event wake "" "" "$wse_s" "" "$(printf '%s' "$wse_r" | jq -c --arg n "$WAKE_SESSION_NAME" \
      --arg f "$wse_cur" --arg s "$wse_s" --arg pp "${wse_side% *}" --arg sha "${wse_side##* }" \
      '{how: "resumed", name: $n, outcome, note} + (if $s != $f then {from_session: $f} else {} end)
       + {prompt_path: $pp, prompt_sha256: $sha}')"
    printf 'wake        %s · resumed · %s\n' "$WAKE_SESSION_NAME" "$wse_o"
    return 0
  fi

  mkdir -p "$BATON_HOME/wake"
  claude_bg "$BATON_HOME/wake" "$WAKE_SESSION_NAME" "$(config_num wakeModel haiku)" "" "$wse_settings" "$wse_text"
  wse_row=''
  [ -z "$bg_id" ] || wse_row=$(row_for_id "$bg_id") || wse_row=''
  if [ -z "$wse_row" ]; then
    wse_detail=$bg_stderr
    [ -n "$wse_detail" ] || wse_detail="exit $bg_status, no session with a pid; stdout: $bg_stdout"
    wse_detail=$(printf '%s' "$wse_detail" | head -c 500)
    log_event wake "" "" "" "" "$(jq -nc --arg n "$WAKE_SESSION_NAME" --arg d "$wse_detail" \
      '{how: "started", name: $n, outcome: "refused", note: $d}')"
    printf 'wake        %s · could not be started: %s\n' "$WAKE_SESSION_NAME" "$wse_detail"
    return 0
  fi
  wse_s=$(printf '%s' "$wse_row" | jq -r .sessionId)
  wse_side=$(sidecar_write "$wse_s" "$wse_text")
  log_event wake "" "" "$wse_s" "" "$(jq -nc --arg n "$WAKE_SESSION_NAME" --arg j "$bg_id" \
    --arg pp "${wse_side% *}" --arg sha "${wse_side##* }" \
    '{how: "started", name: $n, job: $j, outcome: "delivered", prompt_path: $pp, prompt_sha256: $sha}')"
  printf 'wake        %s · started · %s\n' "$WAKE_SESSION_NAME" "$wse_s"
}

# verb_wake [<milestone | project/milestone>] [<text>]: brings a finished session back on the person's
# word, the way the wake session asks for it. With no milestone, lists the finished sessions and
# whether each is running. A running one is not resumed — a resume into a live session starts a copy
# — and is named instead, because the person can message it in its own thread. The text, when given,
# is delivered as the resume's prompt, labelled as the person's; the session answers it in its own
# thread, which the resume makes active again in Claude.app even after the stop archived it.
verb_wake() {
  vw_rows=$(rows_read) || { echo "baton: claude agents --json could not be read, so whether a session is running cannot be told; nothing woken" >&2; exit 1; }
  vw_log=$(log_json) || { echo "baton: $vw_log" >&2; exit 1; }
  vw_fin=$(lifecycle_finished "$vw_log" "$vw_rows")

  if [ -z "${1:-}" ]; then
    vw_n=$(printf '%s' "$vw_fin" | jq length)
    [ "$vw_n" -gt 0 ] || { echo "nothing has finished yet"; return 0; }
    vw_now=$(now_epoch); vw_i=0
    while [ "$vw_i" -lt "$vw_n" ]; do
      vw_f=$(printf '%s' "$vw_fin" | jq -c --argjson i "$vw_i" '.[$i]'); vw_i=$((vw_i + 1))
      vw_state=offline
      printf '%s' "$vw_f" | jq -e 'has("pid")' > /dev/null && vw_state=running
      vw_active=''
      vw_mt=$(transcript_mtime "$(printf '%s' "$vw_f" | jq -r .session)") \
        && vw_active=" · active $(duration $((vw_now - vw_mt))) ago"
      printf '%s' "$vw_f" | jq -r --arg st "$vw_state" --arg a "$vw_active" \
        '"\(.project)/\(.milestone) · \($st)\($a)"'
    done
    return 0
  fi

  case "$1" in
    */*) vw_p=${1%%/*}; vw_m=${1#*/} ;;
    *)   vw_p=''; vw_m=$1 ;;
  esac
  vw_match=$(printf '%s' "$vw_fin" | jq -c --arg p "$vw_p" --arg m "$vw_m" \
    'map(select(.milestone == $m and ($p == "" or .project == $p)))')
  vw_count=$(printf '%s' "$vw_match" | jq length)
  if [ "$vw_count" -eq 0 ]; then
    echo "baton: nothing finished is named $1" >&2
    exit 2
  fi
  if [ "$vw_count" -gt 1 ]; then
    echo "baton: $vw_m finished in more than one project; name one:" >&2
    printf '%s' "$vw_match" | jq -r '.[] | "  baton wake \(.project)/\(.milestone)"' >&2
    exit 2
  fi
  vw_f=$(printf '%s' "$vw_match" | jq -c '.[0]')
  vw_p=$(printf '%s' "$vw_f" | jq -r .project)
  vw_s=$(printf '%s' "$vw_f" | jq -r .session)
  vw_a=$(printf '%s' "$vw_f" | jq -r '.attempt // ""')
  if printf '%s' "$vw_f" | jq -e 'has("pid")' > /dev/null; then
    # A stop the offline rule issued takes a few seconds to land, and the row keeps its pid meanwhile;
    # pointing the person at a thread that is being archived would send their message nowhere.
    if vw_mt=$(transcript_mtime "$vw_s") && offline_after "$vw_log" "$vw_s" "$vw_mt"; then
      echo "$vw_p/$vw_m is being taken offline this minute; send the message again in a minute"
    else
      echo "$vw_p/$vw_m is running; message it in its own thread in Claude.app"
    fi
    return 0
  fi

  if [ -n "${2:-}" ]; then
    vw_text="The person sent this from Claude.app through Baton's wake session:

$2"
  else
    vw_text="Baton woke this session because the person asked for it from Claude.app. Say in one line that you are awake, and wait for their message."
  fi
  vw_r=$(wake_resume "$vw_s" "$vw_text")
  vw_o=$(printf '%s' "$vw_r" | jq -r .outcome)
  vw_copy=''
  if [ "$vw_o" = forked ] && vw_short=$(printf '%s' "$vw_r" | jq -re '.copy // empty'); then
    vw_copy=$(fork_session "$vw_short") || vw_copy=$vw_short
  fi
  vw_side=$(sidecar_write "$vw_s" "$vw_text")
  log_event wake "$vw_p" "$vw_m" "$vw_s" "$vw_a" "$(printf '%s' "$vw_r" | jq -c --arg c "$vw_copy" \
    --arg pp "${vw_side% *}" --arg sha "${vw_side##* }" \
    '{how: "verb", outcome, note} + (if $c != "" then {copy: $c} else {} end)
     + {prompt_path: $pp, prompt_sha256: $sha}')"
  if [ "$vw_o" = forked ]; then
    # The session was running after all, so the copy is a second process beside it, and the copy is
    # the one holding the person's words. The original is stopped, as `resume_session` stops it, so
    # one conversation does not run twice.
    if vw_rows=$(rows_read) && vw_job=$(job_of_session "$vw_rows" "$vw_s") && [ -n "$vw_job" ]; then
      "$BATON_CLAUDE" stop "$vw_job" > /dev/null 2>&1 || true
    fi
  fi
  case "$vw_o" in
    delivered) echo "woke $vw_p/$vw_m; its answer will be in its own thread in Claude.app" ;;
    forked)    echo "woke $vw_p/$vw_m in a copy of its session, which answers in its own thread in Claude.app" ;;
    *)         echo "baton: $vw_p/$vw_m could not be woken: $(printf '%s' "$vw_r" | jq -r .note)" >&2; exit 1 ;;
  esac
}
