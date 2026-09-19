#!/bin/sh
# lib/notify.sh — the Mac message, and the checks both writers of one run first. An escalation
# parks and a notification is kept working past (REQ-ESC-01), but both reach the person the same
# way: one Mac message, posted by the notifier applet and opening the session when clicked, plus one
# log event (REQ-ESC-02). Writing them
# through one function each — `notification_write` here, `escalate` in `lib/escalate.sh` — is what
# makes "every escalation and every notification reaches the Mac" true by construction rather than
# by remembering to add a call.
#
# A notification's body is never composed twice: its fields are read by `one_line`, the same
# function `status` prints from, so the line a person reads on the Mac and the line they read in
# `status` are the same line. An escalation's body is the three-part message instead
# (`message_render`, REQ-ESC-03), because a park is a decision to be made and not a fact to be told.
set -eu

# notify_line <string>: one line of a Mac message, as the applet's spool holds it, where a field is read
# as a value and never parsed as script. Newlines and tabs become spaces (a notification is one line,
# and a newline would forge the spool's next field), and the result is capped because Notification
# Center truncates far shorter than this and an unbounded carries would otherwise be spooled whole.
#
# The cap is jq's and not awk's, and it comes before any escaping. Two measured reasons. Applied after
# `notify_text`'s escaping it would count the escapes and could cut between a backslash and what it
# escapes, leaving the literal ending in a lone backslash, which escapes the closing quote — a syntax
# error osascript reports and `notify` swallows, so the long messages are the ones lost. And this Mac's
# awk (version 20200816) counts bytes, not characters, even under a UTF-8 locale:
# `printf 'a·b' | awk '{print substr($0,1,2)}'` yields `61 c2`, half of the two-byte separator every
# composed message carries. jq slices by code point.
notify_line() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | jq -Rr '.[0:250]' | tr -d '\n'
}

# notify_text <string>: `notify_line`, then safe inside an AppleScript string literal — a backslash and
# a double quote escaped — for the osascript path.
notify_text() {
  notify_line "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# session_url <session>: the claude.ai URL of the session's Remote Control thread — the newest
# `remote_session_change` attachment in its transcript whose url is one, found by the same glob
# derivation 3 uses (SPEC §4 item 7). A connection is first recorded with a null url, and a session
# whose first turn is blocked on a question records nothing more until it is answered — which is the
# moment a `question` park is raised — so without a URL the job state's `bridgeSessionId` is read
# instead: `~/.claude/jobs/<job>/state.json`, the job being the session id's first eight characters,
# holding `cse_<id>` from the session's first turn, the same id as `session_<id>` (D-093). Empty when
# neither has one. Anything that is not exactly a claude.ai session id is not one, because the applet
# opens what this returns.
session_url() {
  session_id_ok "$1" || return 0
  su_url=
  if su_file=$(transcript_of "$1"); then
    su_url=$(grep -F '"remote_session_change"' "$su_file" 2>/dev/null \
      | jq -Rr 'fromjson? | select(.type == "attachment" and .attachment.type == "remote_session_change")
                | .attachment.url | strings' 2>/dev/null \
      | grep -E '^https://claude\.ai/code/session_[A-Za-z0-9_-]+$' | tail -n 1 || true)
  fi
  if [ -z "$su_url" ]; then
    su_url=$(jq -r '.bridgeSessionId | strings' "$BATON_JOBS/$(printf '%s' "$1" | cut -c1-8)/state.json" 2>/dev/null \
      | grep -E '^cse_[A-Za-z0-9_-]+$' | sed 's|^cse_|https://claude.ai/code/session_|' || true)
  fi
  [ -z "$su_url" ] || printf '%s\n' "$su_url"
}

# notify <title> <body> [<session>]: the one Mac message. Through the notifier applet when it is
# installed: the message is spooled as title, body and target — the session's thread as a
# `claude://claude.ai/code/…` link, which Claude.app opens without the feature flag its `claude://code/…`
# form is held behind — and the applet is launched to post it (notify/Baton.applescript). Through
# osascript when the applet is missing or will not launch, so a failed install never silences the
# relay. A failure is swallowed: the channel is how a person hears about the relay, and a relay that
# stopped because it could not raise a notification would be the failure the notification was for.
notify() {
  if [ -d "$BATON_HOME/bin/Baton.app" ]; then
    nt_target=
    [ -z "${3:-}" ] || nt_target=$(session_url "$3" | sed 's|^https://|claude://|')
    # Named so the spool lists in the order the messages were written, which is the order the applet
    # posts them and so which one is the newest a click opens: the counter is padded, because the
    # listing is lexical and `-10` would sort before `-2`. A name already on disk is skipped rather than
    # overwritten, because the counter is a shell variable and a call from a subshell — a rule's
    # `| while read` loop — increments a copy the next call does not see. Written under a dot name the
    # applet's listing skips and renamed, so the applet never reads half a message.
    nt_spool=$BATON_HOME/notify/spool
    nt_epoch=$(now_epoch 2>/dev/null) || nt_epoch=0
    while :; do
      notify_seq=$(( ${notify_seq:-0} + 1 ))
      nt_name=$(printf '%s-%s-%06d' "$nt_epoch" "$$" "$notify_seq")
      [ -e "$nt_spool/$nt_name" ] || [ -e "$nt_spool/.$nt_name" ] || break
    done
    # The spool's three lines are transport, not terminal output: no escape, no width and no reading
    # of this process's streams belongs in a file another program reads and posts (`render_plain`).
    if mkdir -p "$nt_spool" 2>/dev/null \
       && render_plain '%s\n%s\n%s\n' "$(notify_line "$1")" "$(notify_line "$2")" "$nt_target" > "$nt_spool/.$nt_name" 2>/dev/null \
       && mv "$nt_spool/.$nt_name" "$nt_spool/$nt_name" 2>/dev/null; then
      "$BATON_OPEN" -g "$BATON_HOME/bin/Baton.app" > /dev/null 2>&1 && return 0
      rm -f "$nt_spool/$nt_name"
    fi
    rm -f "$nt_spool/.$nt_name"
  fi
  "$BATON_OSASCRIPT" -e \
    "display notification \"$(notify_text "$2")\" with title \"$(notify_text "$1")\"" \
    > /dev/null 2>&1 || true
}

# notify_flush: launch the applet when the spool still holds a message, once, at the start of a tick. A
# launch that reaches the applet while it is quitting posts nothing and the message waits; without this
# it would wait for whatever next launches the applet, and if that is a click, the click would post the
# old message instead of opening a session. So a stranded message is at most a tick late.
notify_flush() {
  [ -d "$BATON_HOME/bin/Baton.app" ] || return 0
  for nf_f in "$BATON_HOME"/notify/spool/*; do
    [ -f "$nf_f" ] || continue
    "$BATON_OPEN" -g "$BATON_HOME/bin/Baton.app" > /dev/null 2>&1 || true
    return 0
  done
}

# notify_title <project> <milestone> <class>: the address, REQ-ESC-03's first part. The lane when
# the event has one, Baton itself when it does not — a stale lock and a gap belong to no milestone.
notify_title() {
  nt_addr=Baton
  if [ -n "$1" ] && [ -n "$2" ]; then nt_addr="Baton · $1/$2"
  elif [ -n "$1" ]; then nt_addr="Baton · $1"
  elif [ -n "$2" ]; then nt_addr="Baton · $2"
  fi
  [ -z "$3" ] || nt_addr="$nt_addr · $3"
  render_plain '%s' "$nt_addr"
}

# fields_or_fail <who> <json>: the guard both writers run first. log_event reads an empty fields
# argument as "no fields", which is right for an event that has none and wrong for one whose fields
# failed to build: the line is then written with its envelope and nothing else, and a notification
# with no class is worse than no notification. So a caller that passed something unparseable is a
# bug, and it fails here where it is visible rather than three derivations later.
fields_or_fail() {
  [ -n "$2" ] || { render_failure err "$1: the event's fields are empty"; return 1; }
  printf '%s' "$2" | jq -e 'type == "object"' > /dev/null 2>&1 \
    || { render_failure err "$1: the event's fields are not a JSON object: $2"; return 1; }
}

# class_or_fail <caller> <kind> <class>: the taxonomy, enforced rather than read. Both lists are fixed
# (REQ-ESC-04 and the notification classes of docs/ARCHITECTURE.md §6.2), and a class outside them
# is a typo that would sit in the log looking like a state nothing can resolve — `baton answer`
# matches on the class, and `status` prints its verb from it. Cheaper to refuse here than to find
# out from a park that no verb clears.
class_or_fail() {
  case "$2:$3" in
    escalation:asking|escalation:question|escalation:ladder-end|escalation:unfinished-twice) ;;
    escalation:blocked|escalation:merge-failed|escalation:other|escalation:disagreement) ;;
    escalation:omitted|escalation:model_not_found|escalation:dispatch-failed) ;;
    escalation:plan-unreadable|escalation:plan-unparseable|escalation:main-broken) ;;
    escalation:baton-unhealthy) ;;
    notification:rate_limit|notification:billing_error|notification:unrecoverable) ;;
    notification:transient|notification:stall|notification:long-running) ;;
    notification:blocked_by|notification:distant_wait_for|notification:prompt-lost) ;;
    notification:gap|notification:takeover-silent) ;;
    *) render_failure err "$1: \"$3\" is not one of the $2 classes"; return 1 ;;
  esac
}

# notification_write <project> <milestone> <session> <attempt> <class> <key> <fields json>:
# the notification event and its Mac message. The once-only rule is the caller's — each class
# spends its key differently — and the fields carry a `detail`, which is the line the person reads.
notification_write() {
  class_or_fail notification_write notification "$5" || return 1
  fields_or_fail notification_write "$7" || return 1
  log_event notification "$1" "$2" "$3" "$4" "$(jq -nc --arg c "$5" --arg k "$6" --argjson f "$7" \
    '{class: $c} | if $k != "" then . + {key: $k} else . end | . + $f')" || return 1
  notify "$(notify_title "$1" "$2" "$5")" "$(one_line "$7")" "$3"
}
