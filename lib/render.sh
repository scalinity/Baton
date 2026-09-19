#!/bin/sh
# lib/render.sh — the one layer between what Baton decides and what a person reads.
#
# Every person-facing success, warning, error and Mac message passes through here. Nothing here
# decides anything: the channel, the exit status, the order of the records and the decision that
# chose the message all stay at the caller, and this file only chooses how the words are laid out.
# It reads no file, writes no log and starts no process.
#
# The shape it renders is Baton's own record grammar, which every verb already prints:
#
#     <label>  <lane> · <field> · <field> · <what to type>
#
# a label naming the kind, then fields separated by " · ". A label always carries its meaning as a
# word, so colour is never the thing that says what a line is; it is the thing that says, at a
# glance down a busy `status`, which lanes are waiting on the person. Cyan is identity — lanes,
# milestones, headings. Amber is what needs an act, including the command that resolves it. Dim is
# secondary metadata: a timestamp, a path, a session id. Normal text is the detail itself.
#
# **Plain is the default and the contract.** Through a pipe, into a file, under NO_COLOR, or with a
# dumb terminal, every primitive emits exactly the bytes the caller's own format string produces —
# no escapes, no re-layout, no transliteration. That is not a degraded mode: the tick's streams go
# to `launchd.out`, the test harness diffs captured streams, and people grep both, so the plain
# shape is a contract with readers this repository cannot enumerate. The decoration is what a
# terminal adds on top of it, never something the plain reader loses.
#
# **The stream is an argument, at every call site.** `[ -t 1 ]` asked inside `$(…)` or a pipeline
# answers for that pipe, not for the stream the verb is writing to, so the context is read once by
# `render_init` at the verb boundary in `bin/baton` and every primitive is then told which of the
# two streams its bytes are going to. `baton plan > file` still has a person watching stderr and
# `baton status 2> file` still has one watching stdout; one answer for both would style the stream
# nobody is reading or strip the one somebody is. A primitive called before `render_init` — a
# direct-library scenario, a library sourced on its own — initialises lazily, which inside a
# capture correctly reads "not a terminal": the safe answer, not the styled one.
set -eu

# render_width_ok <text>: a positive, bounded decimal, validated as text before any arithmetic, so
# that an environment carrying `COLUMNS=-1`, `COLUMNS=0`, `COLUMNS=1e9` or a word cannot reach `[`
# as a number at all. Five digits is past any real terminal and short of anything that overflows.
render_width_ok() {
  case "${1-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 5 ] || return 1
  [ "$1" -ge 1 ] || return 1
  [ "$1" -le 10000 ] || return 1
}

# render_init: read the terminal context once. Sets RENDER_TTY_OUT, RENDER_TTY_ERR,
# RENDER_STYLE_OUT, RENDER_STYLE_ERR, RENDER_COLUMNS, RENDER_UTF8 and RENDER_ESC.
render_init() {
  RENDER_ESC=$(printf '\033')

  if [ -t 1 ]; then RENDER_TTY_OUT=yes; else RENDER_TTY_OUT=no; fi
  if [ -t 2 ]; then RENDER_TTY_ERR=yes; else RENDER_TTY_ERR=no; fi

  # NO_COLOR set at all — including set and empty, which is the case a `[ -n ]` test misses — means
  # plain (no-color.org). FORCE_COLOR is deliberately ignored: every process started from inside a
  # Claude Code session inherits it, which is how a coloured id once reached a parser (D-050), and
  # a relay that decorated its output because of an inherited variable would repeat that shape.
  ri_decorate=yes
  [ -z "${NO_COLOR+set}" ] || ri_decorate=no
  case "${TERM-}" in ''|dumb) ri_decorate=no ;; esac

  RENDER_STYLE_OUT=no; RENDER_STYLE_ERR=no
  if [ "$ri_decorate" = yes ]; then
    [ "$RENDER_TTY_OUT" = no ] || RENDER_STYLE_OUT=yes
    [ "$RENDER_TTY_ERR" = no ] || RENDER_STYLE_ERR=yes
  fi

  # The width: COLUMNS if the environment carries a usable one, else the terminal's own answer, and
  # only when there really is a terminal — `/dev/tty` exists inside a pipeline too, and asking it
  # there would lay out for a width nothing is going to display at. `stty size` is in the base
  # system; no `tput`, terminfo package or probing sequence is used anywhere in this file.
  RENDER_COLUMNS=80
  if render_width_ok "${COLUMNS-}"; then
    RENDER_COLUMNS=$COLUMNS
  elif [ "$RENDER_TTY_OUT" = yes ] || [ "$RENDER_TTY_ERR" = yes ]; then
    ri_size=$(stty size < /dev/tty 2>/dev/null) || ri_size=
    ri_cols=${ri_size##* }
    if render_width_ok "$ri_cols"; then RENDER_COLUMNS=$ri_cols; fi
  fi

  # The effective locale, in the order a C library resolves it. An unknown or C locale gets ASCII
  # layout: the renderer adds no multi-byte character of its own there. Data is never transliterated
  # — a separator a caller's own format carries is that caller's bytes and stays as written.
  ri_loc=${LC_ALL:-}
  [ -n "$ri_loc" ] || ri_loc=${LC_CTYPE:-}
  [ -n "$ri_loc" ] || ri_loc=${LANG:-}
  case "$ri_loc" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) RENDER_UTF8=yes ;;
    *) RENDER_UTF8=no ;;
  esac

  RENDER_READY=yes
}

# render_ready: initialise on first use, for a library function called outside `bin/baton`.
render_ready() { [ "${RENDER_READY:-no}" = yes ] || render_init; }

# render_styled <out|err>: whether that stream may carry escapes.
render_styled() {
  render_ready
  case "$1" in
    err) [ "${RENDER_STYLE_ERR:-no}" = yes ] ;;
    *)   [ "${RENDER_STYLE_OUT:-no}" = yes ] ;;
  esac
}

# render_paint <sgr> <text>: one styled run, always closed. Every run resets, so no record can
# leak its colour into the next one or into a person's shell prompt after the last line.
render_paint() { printf '%s[%sm%s%s[0m' "$RENDER_ESC" "$1" "$2" "$RENDER_ESC"; }

RENDER_SGR_IDENTITY=36   # cyan: lanes, milestones, headings
RENDER_SGR_ACTION=33     # amber: a state that needs an act, and the command that resolves it
RENDER_SGR_META=2        # dim: timestamps, paths, session ids

# render_token <out|err> <kind> <text>: one field of a record, styled for that stream by its kind
# and returned as text for the caller to pass as an argument. Kinds: lane, milestone, verb, state,
# path, timestamp, session. It renders the text and never reads it: a kind is the caller's
# statement about what the field is, so nothing here parses a value to decide what it means.
#
# Returned rather than printed, so the caller's own format string stays the literal it always was
# and the styling travels as data through `%s`. An empty field returns empty, so an absent value
# cannot leave a stray escape behind.
render_token() {
  render_ready
  rt_text=${3-}
  [ -n "$rt_text" ] || return 0
  if ! render_styled "$1"; then printf '%s' "$rt_text"; return 0; fi
  case "$2" in
    lane|milestone|verb)    render_paint "$RENDER_SGR_IDENTITY" "$rt_text" ;;
    state)                  render_paint "$RENDER_SGR_ACTION" "$rt_text" ;;
    path|timestamp|session) render_paint "$RENDER_SGR_META" "$rt_text" ;;
    *)                      printf '%s' "$rt_text" ;;
  esac
}

# render_hint <out|err> <text>: the command a person types to resolve what the record just said —
# the verb in a park, the hand-back after a takeover, the way back into an offline session, a
# precondition's repair. Returned like a token, and never cut: a command shortened to fit a width
# is a command that does not work, so a long one overflows the terminal intact.
render_hint() {
  render_ready
  [ -n "${2-}" ] || return 0
  if render_styled "$1"; then render_paint "$RENDER_SGR_ACTION" "$2"; else printf '%s' "$2"; fi
}

# render_heading <out|err> <format> [args…]: a line that names what follows rather than reporting a
# lane — the plan's file, the widening list, the precondition count, the usage summary. Styled
# whole, so a heading carries no tokens; its arguments are plain data.
render_heading() { render_ready; rh_stream=$1; shift; render_emit "$rh_stream" heading "$@"; }

# render_row <out|err> <kind> <format> [args…]: one record. <kind> is `action` for a lane the person
# has to do something about, `record` for one that is only reporting, and `plain` for a line that
# has no label to mark. <format> is the caller's own literal — the same one it printed before this
# layer existed — and the data arrives as arguments, so no value is ever interpreted as a format.
#
# Plain mode is `printf` and nothing more, byte for byte.
render_row() { render_ready; render_emit "$@"; }

# render_emit <stream> <kind> <format> [args…]: the one emission path both of the above share.
render_emit() {
  re_stream=$1; re_kind=$2; re_fmt=$3; shift 3
  if ! render_styled "$re_stream"; then
    case "$re_stream" in
      err) printf "$re_fmt" "$@" >&2 ;;
      *)   printf "$re_fmt" "$@" ;;
    esac
    return 0
  fi
  case "$re_kind" in
    heading) re_out=$(render_paint "$RENDER_SGR_IDENTITY" "$(printf "$re_fmt" "$@")") ;;
    *)       re_out=$(render_record "$re_kind" "$(printf "$re_fmt" "$@")") ;;
  esac
  case "$re_stream" in
    err) printf '%s\n' "$re_out" >&2 ;;
    *)   printf '%s\n' "$re_out" ;;
  esac
}

# render_count <text> <needle>: how many times the needle occurs. Parameter expansion only, so a
# multi-byte value in the text is walked by the shell's own pattern matching and never by an offset.
render_count() {
  rn_n=0; rn_s=$1
  while :; do
    case "$rn_s" in
      *"$2"*) rn_s=${rn_s#*"$2"}; rn_n=$((rn_n + 1)) ;;
      *) break ;;
    esac
  done
  printf '%s' "$rn_n"
}

# render_field <text>: the first field of a record, as rf_seg, with the rest as rf_rest.
#
# A separator inside a styled run is not a field boundary. `Baton · wake` is the name of one
# session, not two fields, and `message Baton` on one line and `wake, or …` on the next would send
# a person looking for something that does not exist. Every run this layer opens is closed by its
# own reset, so a candidate field holding more openers than resets is one that ends mid-run, and
# the separator that ended it belongs to the value rather than to the record.
render_field() {
  rf_acc=''; rf_rest=$1
  while :; do
    case "$rf_rest" in
      *' · '*) rf_try=${rf_rest%%' · '*} ;;
      *) rf_seg="$rf_acc$rf_rest"; rf_rest=''; return 0 ;;
    esac
    rf_cand="$rf_acc$rf_try"
    rf_rest=${rf_rest#"$rf_try"}; rf_rest=${rf_rest#' · '}
    # A reset is itself an introducer, so a balanced candidate has exactly twice as many of the
    # one as of the other: counting introducers alone would read every closed run as still open.
    rf_close=$(render_count "$rf_cand" "$RENDER_ESC[0m")
    if [ "$(render_count "$rf_cand" "$RENDER_ESC[")" -eq "$((rf_close * 2))" ]; then
      rf_seg=$rf_cand
      return 0
    fi
    rf_acc="$rf_cand · "
  done
}

# render_record <kind> <line>: the terminal layout of one already-composed record, printed whole.
#
# The label is the run of words before the first double space, which is this grammar's own gap and
# not a guess about the data: a line with no such gap has no label and is printed as it came. A
# candidate holding a separator, an escape from a token, or more than fourteen characters is not a
# label either, so a line whose first field merely happens to contain two spaces is left alone.
render_record() {
  rc_line=$2
  case "$1" in
    action) rc_sgr=$RENDER_SGR_ACTION ;;
    plain)  rc_sgr='' ;;
    *)      rc_sgr=$RENDER_SGR_IDENTITY ;;
  esac

  rc_indent=''; rc_rest=$rc_line
  while :; do
    case "$rc_rest" in
      ' '*) rc_indent="$rc_indent "; rc_rest=${rc_rest#?} ;;
      *) break ;;
    esac
  done

  rc_label=''
  if [ -n "$rc_sgr" ]; then
    case "$rc_rest" in
      *'  '*)
        rc_try=${rc_rest%%'  '*}
        case "$rc_try" in
          ''|*'·'*|*"$RENDER_ESC"*) ;;
          *) if [ "${#rc_try}" -le 14 ]; then rc_label=$rc_try; fi ;;
        esac
        ;;
    esac
  fi
  if [ -n "$rc_label" ]; then rc_tail=${rc_rest#"$rc_label"}; else rc_tail=$rc_rest; fi

  # A terminal wide enough for the record keeps the single-line shape a person already knows.
  if [ "${RENDER_COLUMNS:-80}" -ge 60 ]; then
    if [ -n "$rc_label" ]; then
      printf '%s%s%s\n' "$rc_indent" "$(render_paint "$rc_sgr" "$rc_label")" "$rc_tail"
    else
      printf '%s%s\n' "$rc_indent" "$rc_rest"
    fi
    return 0
  fi

  # Below sixty columns the padding stops earning its space: the fields go onto continuation lines
  # at the separator the record already uses, which keeps every path, command and identifier whole
  # rather than folding one mid-token. An unbreakable field longer than the terminal overflows as
  # it is — the renderer never truncates a person's words or a command they have to type. The split
  # is parameter expansion over a literal three-byte separator, never a byte offset, so a multi-byte
  # value in the data cannot be cut in half by it.
  rc_body=$rc_tail
  while :; do
    case "$rc_body" in ' '*) rc_body=${rc_body#?} ;; *) break ;; esac
  done
  if [ "${RENDER_UTF8:-no}" = yes ]; then rc_cont="$rc_indent      · "; else rc_cont="$rc_indent        "; fi
  rc_first=yes
  while :; do
    render_field "$rc_body"; rc_seg=$rf_seg; rc_body=$rf_rest
    if [ "$rc_first" = yes ]; then
      rc_first=no
      if [ -n "$rc_label" ]; then
        printf '%s%s  %s\n' "$rc_indent" "$(render_paint "$rc_sgr" "$rc_label")" "$rc_seg"
      else
        printf '%s%s\n' "$rc_indent" "$rc_seg"
      fi
    else
      printf '%s%s\n' "$rc_cont" "$rc_seg"
    fi
    [ -n "$rc_body" ] || break
  done
}

# render_lines <json array of strings> [<kind>]: the lines a helper returned inside its result,
# rendered on stdout in order. A helper that has two halves to report — human lines and machine
# data — returns both and prints neither, so these arrive already composed and already plain; this
# is where they meet a stream and acquire a layout.
render_lines() {
  rl_n=$(printf '%s' "$1" | jq length); rl_i=0
  while [ "$rl_i" -lt "$rl_n" ]; do
    rl_line=$(printf '%s' "$1" | jq -r --argjson i "$rl_i" '.[$i]'); rl_i=$((rl_i + 1))
    render_row out "${2:-record}" '%s\n' "$rl_line"
  done
}

# render_failure <out|err> <message> [<repair>]: a failure, on the stream the caller already chose.
# <message> is the whole sentence the caller composed from facts it already had; nothing here
# classifies an error, invents wording or reads a tool's stderr to explain itself. <repair> is the
# command to type when the caller has it as a separate thing, appended in plain mode and given its
# own line on a terminal, never shortened. Plain keeps the failure to one line, so that a person or
# a script grepping `launchd.err` finds the whole of it in the hit rather than the half of it.
#
# It writes no log and claims no event. A message and a record are two different acts, and a
# failure renderer that implied the second would say a park exists that nothing wrote (D-057).
render_failure() {
  render_ready
  rf_stream=$1; rf_msg=$2; rf_repair=${3-}

  if ! render_styled "$rf_stream"; then
    if [ -n "$rf_repair" ]; then rf_out="$rf_msg; $rf_repair"; else rf_out=$rf_msg; fi
  else
    case "$rf_msg" in
      'baton: '*) rf_out="$(render_paint "$RENDER_SGR_ACTION" 'baton:') ${rf_msg#baton: }" ;;
      *)          rf_out=$rf_msg ;;
    esac
    if [ -n "$rf_repair" ]; then
      rf_out="$rf_out
    $(render_hint "$rf_stream" "$rf_repair")"
    fi
  fi

  case "$rf_stream" in
    err) printf '%s\n' "$rf_out" >&2 ;;
    *)   printf '%s\n' "$rf_out" ;;
  esac
}

# render_plain <format> [args…]: the explicit plain context, for text that is not terminal output
# at all and must never acquire an escape, a width or a TTY reading — a Mac message's title and
# body, and the human `lines[]` a helper returns inside a JSON result for a caller to print later.
# It takes no stream, because the caller is placing the bytes somewhere that is not a stream of
# this process. Its job is to be the thing an audit can grep for, so that "this is deliberately
# never styled" is written at the site rather than inferred from the absence of a call.
render_plain() {
  rp_fmt=$1; shift
  printf "$rp_fmt" "$@"
}
