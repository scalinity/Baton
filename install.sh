#!/bin/sh
# install.sh — installs the relay under ~/.baton/bin (baton, lib/, the three hooks, a copy of
# /bin/sh for the Full Disk Access grant, and the notifier applet Baton.app), creates the state directories, config.json and Baton's
# own registration if absent. Idempotent: a second run changes nothing. launchd and every
# dispatched session's hooks run the installed copy, so a merge on main changes nothing until this
# is run (D-018).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
BATON_HOME=${BATON_HOME:-$HOME/.baton}

mkdir -p "$BATON_HOME/bin/lib" "$BATON_HOME/inbox" "$BATON_HOME/archive" "$BATON_HOME/rejected" \
  "$BATON_HOME/status" "$BATON_HOME/settings" "$BATON_HOME/prompts" "$BATON_HOME/projects"

cp "$here/bin/baton" "$BATON_HOME/bin/baton"
cp "$here"/lib/*.sh "$BATON_HOME/bin/lib/"
cp "$here/hooks/stop-gate" "$here/hooks/stop-failure" "$here/hooks/statusline" "$BATON_HOME/bin/"
chmod 755 "$BATON_HOME/bin/baton" "$BATON_HOME/bin/stop-gate" "$BATON_HOME/bin/stop-failure" "$BATON_HOME/bin/statusline"

# Baton's own copy of the shell, which the launchd job runs and which the person grants Full Disk
# Access. A plain copy cannot execute at all: it carries Apple's platform signature, and the kernel
# refuses to run a platform binary from outside its sealed location — the job exits with
# OS_REASON_CODESIGNING and writes nothing, and running the copy by hand is killed with 137. An
# ad-hoc signature replaces the one the copy cannot satisfy. `codesign --verify` passes on the
# unrunnable copy, so the test is the ad-hoc flag and nothing weaker (D-038).
if [ ! -x "$BATON_HOME/bin/sh" ]; then
  cp /bin/sh "$BATON_HOME/bin/sh"
  codesign --force --sign - "$BATON_HOME/bin/sh" > /dev/null 2>&1 \
    || echo "warning: could not sign $BATON_HOME/bin/sh; the launchd job will not run"
  echo "copied /bin/sh to $BATON_HOME/bin/sh and signed it ad hoc — grant it Full Disk Access (REQ-SETUP-01)"
elif ! codesign -d --verbose=2 "$BATON_HOME/bin/sh" 2>&1 | grep -q 'flags=.*adhoc'; then
  codesign --force --sign - "$BATON_HOME/bin/sh" > /dev/null 2>&1 \
    || echo "warning: could not sign $BATON_HOME/bin/sh; the launchd job will not run"
  echo "re-signed $BATON_HOME/bin/sh ad hoc; as it stood it could not have run as a launchd job"
fi

if [ ! -f "$BATON_HOME/config.json" ]; then
  cat > "$BATON_HOME/config.json" <<'JSON'
{ "cap": 2, "fableReserve": 80, "stallMinutes": 30, "longRunningHours": 6,
  "retryMinutes": 15, "caffeinateMaxHours": 6,
  "models": { "fable": "fable", "opus": "opus", "sonnet": "sonnet", "haiku": "haiku" } }
JSON
fi

# Baton registers itself: the canonical checkout is the main worktree of the repository this
# script sits in, never a linked worktree, so an install run from ../Baton-M<nn> still points at it.
canonical=$(git -C "$here" worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')
project=$(basename "$canonical")
mkdir -p "$BATON_HOME/projects/$project"
if [ ! -f "$BATON_HOME/projects/$project/project.json" ]; then
  jq -n --arg p "$canonical" '{path: $p, plan: "docs/MILESTONES.md"}' > "$BATON_HOME/projects/$project/project.json"
fi
if [ ! -f "$BATON_HOME/projects/$project/permissions.json" ]; then
  # Two deny classes and nothing else (REQ-PERM-04): privilege escalation, and Baton's own state by
  # named path — everything under BATON_HOME except inbox/. The // form is an absolute path for the
  # tools that take one; the Bash fragments catch a shell command that names the path, and can
  # never be complete (D-026).
  jq -n --arg h "/$BATON_HOME" '
    { permissions: {
        allow: ["Bash(sh tests/run.sh:*)", "Bash(jq:*)"],
        deny: (
          ["Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)", "Bash(osascript * administrator privileges*)"]
          + ["Read(\($h)/log.jsonl)", "Edit(\($h)/log.jsonl)", "Write(\($h)/log.jsonl)"]
          + ([ "archive", "rejected", "prompts", "settings", "projects", "bin", "status", "lock" ]
             | map("Edit(\($h)/\(.)/**)", "Write(\($h)/\(.)/**)"))
          + ["Edit(\($h)/config.json)", "Write(\($h)/config.json)", "Edit(\($h)/last-tick)", "Write(\($h)/last-tick)"]
          + ([ "log.jsonl", "archive", "rejected", "prompts", "settings", "projects", "status", "lock", "config.json", "last-tick" ]
             | map("Bash(*.baton/\(.)*)"))
          # The launchd agent joins the named paths from M03. It sits outside ~/.baton but is
          # Baton state by every other measure, and what it names is executed every sixty
          # seconds by a shell with Full Disk Access (D-048).
          + ["Edit(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
             "Write(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
             "Bash(*com.baton.tick*)"]
        ) } }' > "$BATON_HOME/projects/$project/permissions.json"
fi

# The wake session's settings (D-087): Remote Control on, so the person can message it from Claude.app
# and the phone, and the same deny list as Baton's own sessions, because it runs `baton wake` under
# bypassPermissions like any dispatched session. On top of that list, every verb but `wake`, `status`
# and `plan`: its standing prompt runs one command, and the deny list rather than the prompt is the
# rail, so a misread message cannot tick, answer, dispatch or widen an allowlist from the phone. With
# no base list there is no rail to add to, so the file carries none and the tick refuses to start the
# session. No hooks: it is not a milestone and owes no handover. Written only when it changes, so a
# second install changes nothing.
mkdir -p "$BATON_HOME/settings"
jq '(.permissions.deny // []) as $base
    | {permissions: {defaultMode: "bypassPermissions", allow: [],
                     deny: (if ($base | length) == 0 then []
                            else $base + ["Bash(*baton tick*)", "Bash(*baton answer*)",
                                          "Bash(*baton dispatch*)", "Bash(*baton allow*)"] end)},
       remoteControlAtStartup: true}' \
  "$BATON_HOME/projects/$project/permissions.json" > "$BATON_HOME/settings/wake.json.tmp"
if cmp -s "$BATON_HOME/settings/wake.json.tmp" "$BATON_HOME/settings/wake.json"; then
  rm -f "$BATON_HOME/settings/wake.json.tmp"
else
  mv "$BATON_HOME/settings/wake.json.tmp" "$BATON_HOME/settings/wake.json"
fi

# The notifier applet (REQ-ESC-02, REQ-SETUP-05): notify/Baton.applescript compiled by the system's
# osacompile into bin/Baton.app, so the Mac message is posted under "Baton" rather than Script Editor
# and a click opens the session. osacompile writes no bundle identifier, which Notification Center
# keys a sender on, and carries its icon twice — applet.icns and an asset catalog that wins over it —
# so the identifier is added, and Claude's icon replaces both when the installed Claude.app has one.
# The icon is Anthropic's mark: it is copied from this Mac's Claude.app here and never committed. The
# edits break osacompile's own signature, so the bundle is signed ad hoc last. Built in a staging
# directory and moved into place, and only when the source or the icon differs from what the installed
# applet holds, so a second install changes nothing. A failed build leaves any applet already installed,
# and without one `notify` posts through osascript, so a failed install never silences the relay.
claude_icon=${BATON_CLAUDE_ICON:-/Applications/Claude.app/Contents/Resources/electron.icns}
app=$BATON_HOME/bin/Baton.app
if ! cmp -s "$here/notify/Baton.applescript" "$app/Contents/Resources/Baton.applescript" \
   || { [ -f "$claude_icon" ] && ! cmp -s "$claude_icon" "$app/Contents/Resources/applet.icns"; }; then
  stage=$BATON_HOME/bin/.Baton-build
  rm -rf "$stage"
  mkdir -p "$stage"
  if /usr/bin/osacompile -o "$stage/Baton.app" "$here/notify/Baton.applescript" > /dev/null 2>&1 \
     && cp "$here/notify/Baton.applescript" "$stage/Baton.app/Contents/Resources/Baton.applescript" \
     && { [ ! -f "$claude_icon" ] \
          || { cp "$claude_icon" "$stage/Baton.app/Contents/Resources/applet.icns" \
               && rm -f "$stage/Baton.app/Contents/Resources/Assets.car" \
               && { /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$stage/Baton.app/Contents/Info.plist" > /dev/null 2>&1 || true; }; }; } \
     && /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.baton.notify' \
          -c 'Add :LSUIElement bool true' "$stage/Baton.app/Contents/Info.plist" > /dev/null 2>&1 \
     && codesign --force --sign - "$stage/Baton.app" > /dev/null 2>&1; then
    rm -rf "$app"
    mv "$stage/Baton.app" "$app"
    if [ -f "$claude_icon" ]; then
      echo "built the notifier applet at $app (com.baton.notify) with Claude's icon"
    else
      echo "built the notifier applet at $app (com.baton.notify); $claude_icon is missing, so it keeps the applet's own icon"
    fi
  else
    echo "warning: could not build the notifier applet at $app; the Mac message goes through osascript"
  fi
  rm -rf "$stage"
fi

# The launchd agent is copied only when none is installed, and never loaded: loading is a person's
# act, after they have read the merge and granted Full Disk Access to the shell the job runs
# (REQ-SETUP-01, REQ-SETUP-04). An installed agent that differs is left in place, because a
# milestone's close-out runs this script (D-079) and launchd reads the agent at every login, so a
# replaced plist would change what the tick runs — and with which shell — without a person choosing
# it (D-048).
agents=$HOME/Library/LaunchAgents
mkdir -p "$agents"
echo "installed the relay under $BATON_HOME/bin; project $project registered at $canonical"
if [ ! -f "$agents/com.baton.tick.plist" ]; then
  cp "$here/launchd/com.baton.tick.plist" "$agents/com.baton.tick.plist"
  echo "copied the launchd agent to $agents/com.baton.tick.plist; load it with"
  echo "  launchctl bootstrap gui/\$(id -u) $agents/com.baton.tick.plist"
elif cmp -s "$here/launchd/com.baton.tick.plist" "$agents/com.baton.tick.plist"; then
  echo "the launchd agent at $agents/com.baton.tick.plist is current"
else
  echo "launchd/com.baton.tick.plist differs from the installed agent at $agents/com.baton.tick.plist, which is left in place; copy it by hand and reload the agent if the change is wanted"
fi
