#!/bin/sh
# The Claude boundary. Every invocation is bounded; unknown is never an empty fleet.
set -eu
bounded_call() (
  ac_seconds=$1; ac_scope=$2; shift 2
  case "$ac_seconds" in ''|*[!0-9]*|0) echo 'invalid BATON_CALL_SECONDS' >&2; exit 2;; esac
  ac_tmp=$(mktemp -d "${TMPDIR:-/tmp}/baton-call.XXXXXX")
  trap 'rm -rf "$ac_tmp"' EXIT
  # macOS /bin/sh monitor mode gives each asynchronous job its own process group, including
  # descendants. The provider may deliberately detach its service; that remains an uncertain
  # external effect. Checks must be synchronous and may not leave workers behind.
  set -m
  "$@" </dev/null 9>&- >"$ac_tmp/out" 2>"$ac_tmp/err" &
  ac_pid=$!
  (
    sleep "$ac_seconds"
    if kill -0 -- "-$ac_pid" 2>/dev/null; then
      : > "$ac_tmp/timeout"
      kill -TERM -- "-$ac_pid" 2>/dev/null || true
      sleep 1
      kill -KILL -- "-$ac_pid" 2>/dev/null || true
    fi
  ) 9>&- >/dev/null 2>&1 &
  ac_timer=$!
  set +m
  trap 'kill -KILL -- "-$ac_pid" "-$ac_timer" 2>/dev/null || true; rm -rf "$ac_tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  ac_status=0
  wait "$ac_pid" || ac_status=$?
  if [ -f "$ac_tmp/timeout" ]; then
    # Do not cancel the watchdog before it has killed remaining descendants.
    wait "$ac_timer" 2>/dev/null || true
  else
    kill -KILL -- "-$ac_timer" 2>/dev/null || true
    wait "$ac_timer" 2>/dev/null || true
  fi
  if [ "$ac_scope" = check ] && kill -0 -- "-$ac_pid" 2>/dev/null; then
    kill -TERM -- "-$ac_pid" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$ac_pid" 2>/dev/null || true
    printf '%s\n' 'check left background workers; refusing verification' >> "$ac_tmp/err"
    ac_status=125
  fi
  trap 'rm -rf "$ac_tmp"' EXIT
  cat "$ac_tmp/out"
  cat "$ac_tmp/err" >&2
  if [ -f "$ac_tmp/timeout" ]; then echo 'provider invocation timed out; result is uncertain' >&2; exit 124; fi
  exit "$ac_status"
)
adapter_call() { bounded_call "${BATON_CALL_SECONDS:-10}" provider "$BATON_CLAUDE" "$@"; }
rows_observe() {
  ro_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-observe.XXXXXX")
  ro_status=0
  ro_out=$(adapter_call agents --json 2>"$ro_tmp") || ro_status=$?
  ro_error=$(cat "$ro_tmp"); rm -f "$ro_tmp"
  if [ "$ro_status" -ne 0 ]; then
    jq -nc --arg e "$ro_error" --argjson s "$ro_status" '{status:"unavailable",exit:$s,error:$e}'
  elif ! printf '%s' "$ro_out" | jq -se 'length == 1 and (.[0] | type == "array" and all(.[]; type == "object" and (.id|type=="string" and length>0) and (.sessionId|type=="string" and test("^[A-Za-z0-9_-]+$")) and (.name|type=="string") and (.cwd|type=="string" and startswith("/")) and has("pid") and (.pid == null or (.pid|type=="number" and .>0 and floor==.))))' >/dev/null 2>&1; then
    jq -nc '{status:"incompatible",error:"agents response does not match the supported schema"}'
  else
    printf '%s' "$ro_out" | jq -c '{status:"ok",rows:.}'
  fi
}
rows_json() {
  rj_observation=$(rows_observe)
  if [ "$(printf '%s' "$rj_observation" | jq -r .status)" != ok ]; then
    printf '%s' "$rj_observation" | jq -r '"baton: provider \(.status): \(.error)"' >&2
    return 1
  fi
  printf '%s' "$rj_observation" | jq -c .rows
}
adapter_version() {
  av_version=$(adapter_call --version) || return 1
  av_expected=$(jq -er '.claudeVersion' "$BATON_HOME/config.json") || { echo 'configure claudeVersion before dispatch' >&2; return 1; }
  av_number=$(printf '%s\n' "$av_version" | awk '{print $1}')
  [ "$av_number" = "$av_expected" ] || { echo "baton: unsupported Claude version $av_version; configured $av_expected" >&2; return 1; }
  printf '%s\n' "$av_version"
}
