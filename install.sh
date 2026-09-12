#!/bin/sh
# install.sh — installs the relay under ~/.baton/bin (baton, lib/, the three hooks, and a copy of
# /bin/sh for the Full Disk Access grant), creates the state directories, config.json and Baton's
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
        ) } }' > "$BATON_HOME/projects/$project/permissions.json"
fi

# The launchd agent is copied, never loaded: loading is a person's act, after they have read the
# merge and granted Full Disk Access to the shell the job runs (REQ-SETUP-01, REQ-SETUP-04).
agents=$HOME/Library/LaunchAgents
mkdir -p "$agents"
cp "$here/launchd/com.baton.tick.plist" "$agents/com.baton.tick.plist"

echo "installed the relay under $BATON_HOME/bin; project $project registered at $canonical"
echo "copied the launchd agent to $agents/com.baton.tick.plist; load it with"
echo "  launchctl bootstrap gui/\$(id -u) $agents/com.baton.tick.plist"
