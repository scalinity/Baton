#!/bin/sh
# Run C (throwaway fixture): what a launchd-started script can reach.
# Deliberately sets no PATH, so item 12 is a real observation.
OUT=/Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/obs/launchd-run.txt
exec > "$OUT" 2>&1

CLAUDE=/Users/danny/.local/bin/claude
TRIAL=/Users/danny/Documents/Apps/Baton/.scratch/trial/project

echo "=== Run C: launchd context ==="
echo "at:    $(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "PATH:  [${PATH-UNSET}]"
echo "HOME:  [${HOME-UNSET}]"
echo "USER:  [${USER-UNSET}]"
echo "SHELL: [${SHELL-UNSET}]"
echo "uid:   $(/usr/bin/id -u)  ppid: $PPID"
echo

echo "--- item 13: daemon status BEFORE dispatch ---"
"$CLAUDE" daemon status 2>&1 | /usr/bin/head -12
echo

echo "--- item 12 + 15: dispatch by absolute path (no PATH, needs Keychain) ---"
cd "$TRIAL" || echo "cd FAILED"
DISPATCH=$("$CLAUDE" --bg -n "Baton trial K" --model haiku --permission-mode bypassPermissions "Say exactly: launchd-ok" 2>&1)
echo "$DISPATCH"
ID=$(printf '%s' "$DISPATCH" | /usr/bin/grep -o 'backgrounded · [0-9a-f]*' | /usr/bin/awk '{print $3}')
echo "parsed id: [$ID]"
echo

echo "--- item 13: daemon status AFTER dispatch ---"
"$CLAUDE" daemon status 2>&1 | /usr/bin/head -6
echo

echo "--- item 17: caffeinate -i -w <pid> ---"
/bin/sleep 8
PID=$("$CLAUDE" agents --json 2>/dev/null | /usr/bin/jq -r --arg id "$ID" '.[]|select(.id==$id)|.pid')
echo "row pid: [$PID]"
if [ -n "$PID" ] && [ "$PID" != "null" ]; then
  /usr/bin/caffeinate -i -w "$PID" &
  CAFF=$!
  echo "caffeinate pid: $CAFF (watching $PID)"
  /bin/sleep 3
  if /bin/ps -p "$CAFF" >/dev/null 2>&1; then echo "caffeinate alive after 3s: YES"; else echo "caffeinate alive after 3s: NO"; fi
else
  echo "no pid in row - cannot caffeinate"
fi
echo

echo "--- row as the script sees it ---"
"$CLAUDE" agents --json 2>/dev/null | /usr/bin/jq -c '.[]|select(.name=="Baton trial K")'
echo

echo "--- item 32: osascript -> Messages ---"
/usr/bin/osascript /Users/danny/Documents/Apps/Baton/.scratch/baton/prototype/send-imessage.applescript 2>&1
echo "osascript exit code: $?"
echo

echo "=== script exiting at $(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) ==="
