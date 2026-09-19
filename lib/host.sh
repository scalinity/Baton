#!/bin/sh
# lib/host.sh — what the Mac says about the stretch Baton was not running.
#
# `derive_gap` answers one question and answers it well: was a tick due and did none run, while
# something needed one. D-174 narrowed it until it means exactly that and nothing more — the gap is
# measured from the clock the tick started with, so work the tick itself spent under its own lock is
# not a gap at all rather than a gap Baton chose not to send. What that narrowing leaves is a class
# with no cause attached, and this file is the cause: the host's own record of when it was asleep,
# read once, through a seam, and turned into a bounded statement about one window.
#
# **It explains and it never excuses.** Three outcomes, and two of them keep the message:
#
#   * `explained` — the window is covered by proven sleep with no awake stretch long enough to have
#     run a tick. Nothing was missed that Baton could have run, so the event is recorded and no Mac
#     message is raised (REQ-ESC-13, `record_notification`).
#   * `unexplained` — the timeline is complete and it does not cover the window. Unloaded launchd, a
#     stuck lock or a crashing tick are what that can also mean, and none of them is diagnosed here;
#     the person is told, as before.
#   * `unknown` — the read failed, or the history is missing, ambiguous or unparseable. The message
#     stands and says so. **Unknown is never asleep**: claiming the host reported no sleep, or
#     silently suppressing on evidence that was never established, are the two failures this file is
#     built not to make, and every doubtful arm below resolves to `unknown` for that reason.
#
# The evidence is `/usr/bin/pmset -g log`, through `$BATON_PMSET`, read at most once per tick.
# Verified on 2026-09-19 in this Mac's LaunchAgent context — submitted under a temporary label
# through `~/.baton/bin/sh`, the shell the real agent names, exit 0, empty stderr, uid 501, ppid 1,
# 950 transition lines — and again by M15 on 2026-09-17. That is this Mac and this macOS; it is not
# a guarantee about a later one, which is the other reason `unknown` has to stay visible.
set -eu

# How many proven sleep intervals an event keeps. `log_event` refuses a line of 4 KB and a window
# of a few hours holds hundreds of dark wakes, so the evidence is bounded rather than complete:
# `sleep_count` says how many there were and the list says what the first few of them looked like.
BATON_HOST_SLEEPS=6

# Where the parsed history is kept for the length of one tick: inside the lock directory, which
# `lock_take` creates and `lock_release` removes, so the cache lives exactly as long as the verb
# holding the lock and nothing has to remember to clean it up. That is what makes "read once per
# needed tick" true rather than aspirational — a shell variable could not, because every caller
# reads these functions through a command substitution, and a subshell's variable is gone the moment
# it prints. A caller with no lock is not a tick; it reads the host each time, which is slower and
# exactly as correct. The file's first line is `ok` or `failed`, so a read that failed is not
# retried three times in one tick either.
host_cache_file() {
  [ -d "$BATON_HOME/lock" ] || return 1
  printf '%s\n' "$BATON_HOME/lock/host-history"
}

# host_transitions: the normalised record stream, one line each, in the order `pmset` printed them:
#
#   T <epoch> sleep|wake      an actual transition, its timestamp read with its own UTC offset
#   A <reason>                something that breaks the timeline, positioned between its neighbours
#
# Prints them; status 1 when the history could not be read at all. `DarkWake` is a `wake`, because
# the machine is running during one and Baton sometimes ticks in one — treating a lid-closed stretch
# as continuous sleep is the over-claim that would silence a real outage. `Wake Requests` is a
# *scheduled* request and not a wake at all, so the domain is read whole: it is everything between
# the timestamp and the tab, and `Wake Requests`, `WakeTime` and `WakeDetails` are none of them
# `Wake`.
#
# A successful read with nothing in it is not proof of no sleep, so an empty stream is not an empty
# history; the window's own assessment turns it into `unknown` (§4, "A successful command with empty
# or partial history does not prove no sleep").
host_transitions() {
  ht_cache=$(host_cache_file) || ht_cache=''
  if [ -n "$ht_cache" ] && [ -f "$ht_cache" ]; then
    [ "$(head -1 "$ht_cache")" = ok ] || return 1
    tail -n +2 "$ht_cache"
    return 0
  fi
  if ht_raw=$("$BATON_PMSET" -g log 2>/dev/null); then ht_ok=1; else ht_ok=0; ht_raw=''; fi
  ht_recs=''
  if [ "$ht_ok" -eq 1 ]; then
    ht_recs=$(printf '%s\n' "$ht_raw" | awk '
        function days_from_civil(y, m, d,   era, yoe, doy, doe) {
          if (m <= 2) y -= 1
          era = int((y >= 0 ? y : y - 399) / 400)
          yoe = y - era * 400
          doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
          doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
          return era * 146097 + doe - 719468
        }
        # The fixed shape pmset prints: "YYYY-MM-DD HH:MM:SS ±HHMM". Every field is range-checked as
        # well as shaped, so 2026-13-45 and -04X0 are both a timestamp Baton cannot place rather
        # than one it places wrongly.
        function stamp_ok(ts,   mo, d, hh, mi, ss, oh, om) {
          if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [-+][0-9][0-9][0-9][0-9]$/) return 0
          mo = substr(ts, 6, 2) + 0; d = substr(ts, 9, 2) + 0
          hh = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; ss = substr(ts, 18, 2) + 0
          oh = substr(ts, 22, 2) + 0; om = substr(ts, 24, 2) + 0
          if (mo < 1 || mo > 12 || d < 1 || d > 31) return 0
          if (hh > 23 || mi > 59 || ss > 59 || oh > 23 || om > 59) return 0
          return 1
        }
        function stamp_epoch(ts,   off) {
          off = (substr(ts, 21, 1) == "-" ? -1 : 1) * ((substr(ts, 22, 2) + 0) * 3600 + (substr(ts, 24, 2) + 0) * 60)
          return days_from_civil(substr(ts, 1, 4) + 0, substr(ts, 6, 2) + 0, substr(ts, 9, 2) + 0) * 86400 \
                 + (substr(ts, 12, 2) + 0) * 3600 + (substr(ts, 15, 2) + 0) * 60 + (substr(ts, 18, 2) + 0) - off
        }
        {
          # The reboot marker, which carries no timestamp of its own: "Sleep/Wakes since boot:<n>"
          # counts up within one boot, so a value below the previous one is a boot between the two
          # records around it. It is read before the transition test because its own first token is
          # the word Sleep.
          if (match($0, /Sleep\/Wakes since boot:[0-9]+/)) {
            b = substr($0, RSTART, RLENGTH); sub(/.*:/, "", b); b = b + 0
            if (seen_boot && b < boot) print "A boot-boundary"
            boot = b; seen_boot = 1
            next
          }
          head = $0
          ti = index(head, "\t"); if (ti > 0) head = substr(head, 1, ti - 1)
          nf = split(head, tok, " ")
          if (nf < 4) next
          domain = tok[4]
          for (i = 5; i <= nf; i++) domain = domain " " tok[i]
          if (domain != "Sleep" && domain != "Wake" && domain != "DarkWake") next
          ts = tok[1] " " tok[2] " " tok[3]
          if (!stamp_ok(ts)) { print "A malformed-timestamp"; next }
          e = stamp_epoch(ts)
          # The log is chronological, so a record older than the one before it is the clock having
          # moved — a UTC offset change is not one, because the offset is read rather than assumed.
          if (seen_t && e < prev) print "A clock-discontinuity"
          prev = e; seen_t = 1
          print "T " e " " (domain == "Sleep" ? "sleep" : "wake")
        }')
  fi
  if [ -n "$ht_cache" ]; then
    # Written under a dot name and renamed, so a reader never sees half of it. Nothing else holds
    # this lock, so the only reader is this process, but the cost of the rename is nothing and the
    # habit is the one every other file Baton writes follows.
    { [ "$ht_ok" -eq 1 ] && echo ok || echo failed; [ -z "$ht_recs" ] || printf '%s\n' "$ht_recs"; } \
      > "$ht_cache.tmp" && mv "$ht_cache.tmp" "$ht_cache"
  fi
  [ "$ht_ok" -eq 1 ] || return 1
  [ -z "$ht_recs" ] || printf '%s\n' "$ht_recs"
}

# host_window <from epoch> <to epoch> <offset seconds> <interval seconds>: what the host says about
# one window, as one JSON object. The offset is the UTC offset every timestamp in the answer is
# rendered in — the marker's own, so the evidence reads in the same zone as the gap it explains.
#
# **The window is `[from, to]` and nothing else.** `to` is the measured endpoint, `epoch(marker) +
# gap_seconds`, and never the instant the event is written: the 1h09m gap M15 measured was written
# at 16:37:50 and ended at 16:21:03, and an endpoint taken from the write time would have asked the
# host to account for sixteen minutes the gap never covered.
#
# The coverage policy, which is bounded explanation and not a proof that the relay was healthy:
#
#   * A proven sleep interval is a `Sleep` record whose next record is a wake. Nothing else proves
#     sleep — in particular a `Sleep` followed by another `Sleep` proves nothing about the stretch
#     between them, because Baton cannot tell an aborted sleep from a wake the history lost.
#   * Proven sleep is clipped to the window and never counted twice.
#   * An awake portion is any stretch of the window no proven sleep covers, the leading and trailing
#     ones included. `explained` needs some proven sleep **and** every awake portion strictly under
#     two intervals — the same threshold `derive_gap` reports at, so a stretch too short to have
#     held a tick is not asked to hold one, while a stretch long enough to have run one is an outage
#     whatever else overlaps it. Disconnected dark wakes are not summed: two short awake portions
#     are two short scheduling opportunities and not one long one.
#   * Anything that breaks the timeline inside the window is `unknown`, with the reason recorded.
host_window() {
  hw_from=$1; hw_to=$2; hw_off=$3; hw_interval=$4
  # A read that failed goes through the same program as one that succeeded, rather than answering
  # beside it, so that every outcome carries the measured endpoint — the field a person reads to
  # know which window was assessed, and the one §4 asks for on both outcomes alike.
  hw_fail=0
  hw_recs=$(host_transitions) || hw_fail=1
  printf '%s\n' "$hw_recs" | awk -v from="$hw_from" -v to="$hw_to" -v off="$hw_off" \
    -v interval="$hw_interval" -v keep="$BATON_HOST_SLEEPS" -v fail="$hw_fail" '
    function civil_from_days(z,   era, doe, yoe, y, doy, mp, d, m) {
      z += 719468
      era = int((z >= 0 ? z : z - 146096) / 146097)
      doe = z - era * 146097
      yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
      y = yoe + era * 400
      doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
      mp = int((5 * doy + 2) / 153)
      CD = doy - int((153 * mp + 2) / 5) + 1
      CM = mp + (mp < 10 ? 3 : -9)
      CY = y + (CM <= 2 ? 1 : 0)
    }
    # The same shape `baton_now` writes, in the offset the caller named, so an evidence timestamp
    # and the marker it is measured against are read in one zone.
    function iso_of(ep,   t, days, rem, sgn, ao) {
      t = ep + off
      days = int(t / 86400); rem = t - days * 86400
      if (rem < 0) { days -= 1; rem += 86400 }
      civil_from_days(days)
      sgn = (off < 0) ? "-" : "+"; ao = (off < 0) ? -off : off
      return sprintf("%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d", CY, CM, CD,
                     int(rem / 3600), int((rem % 3600) / 60), rem % 60,
                     sgn, int(ao / 3600), int((ao % 3600) / 60))
    }
    function unknown(reason) {
      printf "{\"assessed\":\"unknown\",\"reason\":\"%s\",\"endpoint\":\"%s\",\"history_records\":%d}\n",
             reason, iso_of(to), n
      exit 0
    }
    # A bracket is the stretch a positioned anomaly could have happened in: between the transition
    # before it and the one after it. One outside the window says nothing about the window.
    function touches(lo, hi,   a, b) {
      a = (lo < hi) ? lo : hi; b = (lo < hi) ? hi : lo
      return (a <= to && b >= from)
    }
    /^T / { n++; te[n] = $2 + 0; tk[n] = $3; next }
    /^A / { an++; ar[an] = $2; ab[an] = n; next }
    END {
      INF = 9999999999
      if (fail) unknown("history-unreadable")
      if (n == 0) unknown("no-transitions")
      # The anomalies first, in the order pmset printed them, so one reason is reported and it is
      # always the same one for the same history.
      for (j = 1; j <= an; j++) {
        lo = (ab[j] >= 1) ? te[ab[j]] : -INF
        hi = (ab[j] + 1 <= n) ? te[ab[j] + 1] : INF
        if (touches(lo, hi)) unknown(ar[j])
      }
      # Identical records collapse; the sequence is chronological by construction, because anything
      # that broke that order is already an anomaly above.
      m = 0
      for (i = 1; i <= n; i++) {
        if (m > 0 && te[i] == se[m] && tk[i] == sk[m]) continue
        m++; se[m] = te[i]; sk[m] = tk[i]
      }
      # The state at the marker, which is what makes the window readable at all: without a record at
      # or before it the history does not reach back far enough to say whether the machine was
      # asleep when the gap began.
      at_marker = 0
      for (i = 1; i <= m; i++) if (se[i] <= from) at_marker = i
      if (at_marker == 0) unknown("no-state-at-marker")
      # Asleep and awake at one instant is not a timeline. It disqualifies the window when it is in
      # it, and when it is the record the state at the marker is read from.
      for (i = 2; i <= m; i++) {
        if (se[i] == se[i - 1] && sk[i] != sk[i - 1]) {
          if ((se[i] >= from && se[i] <= to) || se[i] == se[at_marker]) unknown("conflicting-transitions")
        }
      }
      # The sleep intervals, and the two ways a Sleep fails to close: another Sleep with no wake
      # between them, and a Sleep that is the last thing the history holds although Baton is
      # demonstrably awake, because it is running. Either is a record the history lost.
      #
      # **An unclosed stretch is never sleep.** It is not added below, so it falls out as an awake
      # portion, which is the conservative direction in both senses — it can only count against an
      # explanation, never towards one. Whether it is also reported as a doubt depends on whether
      # the doubt could have changed the answer: a stretch of two intervals or more inside the
      # window is `unknown` with its reason, because "the host was awake for forty minutes" and
      # "the history lost forty minutes" are different things to be told; a shorter one is not,
      # because it could not have held a tick whichever it was, and the real history carries a
      # handful of twelve-second ones that would otherwise make a whole night unreadable. Several
      # short ones stay several short awake portions and are never summed into one.
      k = 0
      for (i = 1; i <= m; i++) {
        if (sk[i] != "sleep") continue
        lo = (se[i] > from) ? se[i] : from
        if (i == m) {
          if (se[i] < to && to - lo >= 2 * interval) unknown("trailing-sleep-unmatched")
          continue
        }
        if (sk[i + 1] == "wake") { k++; sa[k] = se[i]; sb[k] = se[i + 1]; continue }
        hi = (se[i + 1] < to) ? se[i + 1] : to
        if (hi - lo >= 2 * interval) unknown("missing-wake")
      }
      cursor = from; slept = 0; longest = 0; shown = 0; count = 0
      sleeps = ""
      for (i = 1; i <= k; i++) {
        a = (sa[i] > from) ? sa[i] : from
        b = (sb[i] < to) ? sb[i] : to
        if (b <= a) continue
        if (a - cursor > longest) longest = a - cursor
        slept += b - a
        count++
        if (shown < keep) {
          sleeps = sleeps (shown > 0 ? "," : "") sprintf("{\"from\":\"%s\",\"to\":\"%s\"}", iso_of(a), iso_of(b))
          shown++
        }
        cursor = b
      }
      if (to - cursor > longest) longest = to - cursor
      if (slept <= 0) assessed = "unexplained"
      else if (longest < 2 * interval) assessed = "explained"
      else assessed = "unexplained"
      printf "{\"assessed\":\"%s\",\"endpoint\":\"%s\",\"window_seconds\":%d,\"sleep_seconds\":%d,\"longest_awake_seconds\":%d,\"sleep_count\":%d,\"sleeps\":[%s],\"history_records\":%d}\n",
             assessed, iso_of(to), to - from, slept, longest, count, sleeps, n
    }'
}

# host_sleep_proven <from epoch> <to epoch> <interval>: the seconds of proven sleep inside a window,
# for a caller that is measuring elapsed time rather than explaining a gap. Prints nothing when the
# host cannot say — which is the conservative answer, because a caller that subtracts nothing keeps
# the behaviour it had before this file existed.
#
# Its one caller is the stall rule. A transcript that has not moved since before a night's sleep is
# not a session that has stopped working; it is a session that has not been running. Subtracting
# proven sleep from that age is the whole of it, and the subtraction is only ever as large as the
# sleep the host proved.
host_sleep_proven() {
  hs_w=$(host_window "$1" "$2" 0 "$3") || return 0
  printf '%s' "$hs_w" | jq -r 'if .assessed == "unknown" then empty else .sleep_seconds end' 2>/dev/null || true
}

# host_gap_evidence <marker iso> <gap seconds>: the `host` object a gap event carries, for the
# window the gap actually measured. The endpoint is derived here, from the marker and the duration,
# so it is the same instant `derive_gap` measured and not the instant this runs.
host_gap_evidence() {
  hg_from=$(iso_epoch "$1") || { echo "$hg_from"; return 1; }
  hg_off=$(printf '%s' "$1" | awk '{
    if (match($0, /[+-][0-9][0-9]:?[0-9][0-9]$/)) {
      o = substr($0, RSTART, RLENGTH); gsub(/:/, "", o)
      print (substr(o, 1, 1) == "-" ? -1 : 1) * ((substr(o, 2, 2) + 0) * 3600 + (substr(o, 4, 2) + 0) * 60)
    } else print 0 }')
  host_window "$hg_from" "$((hg_from + $2))" "$hg_off" "$BATON_TICK_SECONDS"
}

# host_gap_detail <base detail> <host evidence json>: the line a person reads, in `status` and — for
# the two outcomes that still reach the Mac — in the message. The base is the sentence `gap_check`
# has always written; this adds what the host did or did not account for, and the `unknown` arm says
# that in as many words rather than letting silence read as "the host reported no sleep".
#
# No apostrophe appears in any of these sentences, and that is not a style choice: a message built
# inside a nested command substitution is parsed by /bin/sh — bash 3.2 on this Mac — with the
# quoting state mistracked, so an apostrophe silently ends a quoted jq program and the event loses
# its fields. `stall_check` carries the same note over the same hazard.
host_gap_detail() {
  hd_a=$(field "$2" .assessed unknown)
  hd_slept=$(field "$2" .sleep_seconds 0)
  hd_awake=$(field "$2" .longest_awake_seconds 0)
  case "$hd_a" in
    explained)
      printf '%s; the host was asleep for %s of it, awake at most %s at a stretch, so there was no tick to run — recorded, not sent\n' \
        "$1" "$(duration "$hd_slept")" "$(duration "$hd_awake")" ;;
    unexplained)
      if [ "$hd_slept" -eq 0 ]; then
        printf '%s; the sleep history is complete and shows no sleep in that window, so sleep does not explain it\n' "$1"
      else
        printf '%s; the host was asleep for only %s of it and awake %s at a stretch, so sleep does not explain it\n' \
          "$1" "$(duration "$hd_slept")" "$(duration "$hd_awake")"
      fi ;;
    *)
      printf '%s; the sleep history could not explain it (%s), which is not a claim that the host stayed awake\n' \
        "$1" "$(field "$2" .reason unknown)" ;;
  esac
}

# host_gap_recorded: the newest gap event in the log, whatever channel it went out on, as one JSON
# object; nothing when there is none. `status` reads this and never the host: a record already made
# is a fact about the past, and re-reading `pmset` to print it would be a second opinion about a
# window that has been assessed once.
host_gap_recorded() {
  hr_log=$(log_json) || { echo "$hr_log"; return 1; }
  printf '%s' "$hr_log" | jq -c '[ .[] | select(.kind == "notification" and .class == "gap") ] | last // empty'
}

# host_gap_status_line <out|err> <gap event json>: `status`'s line for a gap already recorded.
# `record` and not `action` for one the event says was recorded rather than delivered, because there
# is nothing for anyone to do about a Mac that was asleep; `action` otherwise, for the same reason
# the message was sent.
host_gap_status_line() {
  # The row kind comes from `channel`, which is the fact of what happened, and not from
  # `disposition`, which is the table's answer written down. The two cannot disagree today —
  # `gap_check` writes both in one breath — but reading the disposition back to decide anything
  # would be the shape `record_only` exists to prevent, even for a colour. The disposition is still
  # the word printed, because that is the word a person reads about it everywhere else.
  hl_d=$(field "$2" .disposition human-required)
  if printf '%s' "$2" | jq -e '(.channel // []) | index("record")' > /dev/null 2>&1
  then hl_kind=record; else hl_kind=action; fi
  # A gap recorded before the host was ever consulted carries no `host` object at all, and every
  # such event is still in the log. Defaulting its `assessed` to `unknown` would print "the sleep
  # history could not account for it: unknown" about a reading that never happened — a claim, in
  # the one file whose whole stance is that unknown is never one. Absence is its own arm, decided
  # before the table is asked: the reason token is what tells a real `unknown` from this, because
  # an assessment that returns `unknown` always carries one and an absent object can only default.
  if ! printf '%s' "$2" | jq -e 'has("host")' > /dev/null 2>&1; then
    hl_why="recorded before the host was consulted"
  else
    case "$(field "$2" .host.assessed unknown)" in
      explained)   hl_why="the host was asleep for $(duration "$(field "$2" .host.sleep_seconds 0)") of it" ;;
      unexplained) hl_why="the sleep history does not account for it" ;;
      *)           hl_why="the sleep history could not account for it: $(field "$2" .host.reason unknown)" ;;
    esac
  fi
  render_row "$1" "$hl_kind" 'gap  recorded %s against %s · %s · %s\n' \
    "$(duration "$(field "$2" .gap_seconds 0)")" \
    "$(render_token "$1" timestamp "$(field "$2" .marker '?')")" \
    "$hl_d" "$hl_why"
}
