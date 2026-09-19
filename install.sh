#!/bin/sh
# install.sh — installs the relay under ~/.baton/bin (baton, lib/, the three hooks, a copy of
# /bin/sh for the Full Disk Access grant, and the notifier applet Baton.app), creates the state
# directories, config.json and Baton's own registration; permissions are upgraded. A second run changes
# nothing. launchd and every dispatched session's hooks run the installed copy, so a merge on main
# changes nothing until this is run (D-018).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
BATON_HOME=${BATON_HOME:-$HOME/.baton}

# The harness installs its checkout into a disposable home, including from a linked worktree.
# This explicit seam is forgeable like the other seams, not an authorization boundary (D-113).
canonical=$(git -C "$here" worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')
if [ "${BATON_INSTALL_TEST:-}" != 1 ]; then
  if [ "$here" != "$canonical" ] || [ "$(git -C "$here" symbolic-ref --quiet --short HEAD)" != main ]; then
    echo "install: run from the canonical checkout $canonical with HEAD on main" >&2
    exit 2
  fi
  # A branch name alone cannot certify committed input. Include untracked/ignored shell files
  # that the lib/*.sh copy would otherwise pick up, without requiring unrelated documents clean.
  if ! git -C "$here" diff --quiet main -- install.sh bin/baton 'lib/*.sh' \
       hooks/stop-gate hooks/stop-failure hooks/statusline notify/Baton.applescript launchd/com.baton.tick.plist \
     || ! install_untracked=$(git -C "$here" ls-files --others -- install.sh bin/baton 'lib/*.sh' \
       hooks/stop-gate hooks/stop-failure hooks/statusline notify/Baton.applescript launchd/com.baton.tick.plist) \
     || [ -n "$install_untracked" ]; then
    echo 'install: source inputs must match committed main before installation' >&2
    exit 2
  fi
fi

mkdir -p "$BATON_HOME/bin/lib" "$BATON_HOME/inbox" "$BATON_HOME/archive" "$BATON_HOME/rejected" \
  "$BATON_HOME/status" "$BATON_HOME/settings" "$BATON_HOME/prompts" "$BATON_HOME/projects" "$BATON_HOME/checks"

# The relay is published, not copied over (D-131). `bin/baton` sources its whole library set before
# it takes any lock, so a file-by-file copy landing while a tick starts gave that tick a mixture of two
# library sets — live on every unattended close-out, which runs this script itself (D-079). The
# repair is one immutable set per content, named for it, and one atomic reference change:
#
#   * the set is staged in a directory of its own and published by renaming that directory to a name
#     that does not exist, which is `rename(2)` and cannot be seen half-made;
#   * the name is written into the copy of `bin/baton` installed here, and that file is published by
#     renaming over the old one — also `rename(2)`, so a shell already reading the previous copy
#     holds its inode open, reads it whole, and goes on naming the previous bundle;
#   * the previous bundle is kept, so that reader finds its whole set where it left it.
#
# A symlink flipped by `mv` was the obvious alternative and is wrong on this Mac: `mv new old` where
# `old` is a symlink to a directory does not replace the symlink, it follows it and moves the new
# link inside the directory. Measured, not assumed.
#
# Nothing is written twice: a bundle already published is left alone, and each file is compared
# before it is replaced, so an unchanged reinstall keeps every inode and leaves no temporary file —
# the idiom permissions.json and wake.json already use below.
bundle=$( { shasum -a 256 "$here/bin/baton"; shasum -a 256 "$here"/lib/*.sh; } \
          | awk '{ print $1 }' | LC_ALL=C sort | shasum -a 256 | awk '{ print substr($1, 1, 16) }')
# The bundle the copy being replaced named, read before it is replaced. It is what the reader that
# is mid-source right now is using, so it is the one bundle beside the new one that must survive.
previous=$(sed -n 's/^baton_bundle=\(.*\)$/\1/p' "$BATON_HOME/bin/baton" 2>/dev/null | head -1 || true)

if [ ! -d "$BATON_HOME/bin/lib/$bundle" ]; then
  stage=$BATON_HOME/bin/lib/.stage-$$
  rm -rf "$stage"
  mkdir -p "$stage"
  cp "$here"/lib/*.sh "$stage/"
  mv "$stage" "$BATON_HOME/bin/lib/$bundle"
fi

# publish <source> <destination> [<sed script>]: the file as it should be installed, in place only if
# it differs. The mode is set on the temporary file, so what appears at the destination is already
# executable — a rename publishes the whole file or none of it, never a file that is not yet runnable.
publish() {
  if [ -n "${3:-}" ]; then sed "$3" "$1" > "$2.tmp"; else cat "$1" > "$2.tmp"; fi
  chmod 755 "$2.tmp"
  if cmp -s "$2.tmp" "$2"; then rm -f "$2.tmp"; else mv "$2.tmp" "$2"; fi
  # The mode is set on the destination too, so a reinstall still repairs one that lost it, as the
  # unconditional chmod did before. It changes no inode, so an unchanged file is still the same file.
  chmod 755 "$2"
}

publish "$here/bin/baton" "$BATON_HOME/bin/baton" "s|^baton_bundle=.*|baton_bundle=$bundle|"
publish "$here/hooks/stop-gate" "$BATON_HOME/bin/stop-gate"
publish "$here/hooks/stop-failure" "$BATON_HOME/bin/stop-failure"
publish "$here/hooks/statusline" "$BATON_HOME/bin/statusline"

# Every other bundle goes, and any stage a killed install left behind. The flat set a pre-bundle
# relay installed is the previous set for a reader still sourcing from it, so it is kept until a
# bundled copy has been superseded — one install later, by which time no such reader remains.
for stale in "$BATON_HOME"/bin/lib/*/; do
  [ -d "$stale" ] || continue
  stale=${stale%/}; stale=${stale##*/}
  [ "$stale" != "$bundle" ] && [ "$stale" != "$previous" ] || continue
  rm -rf "${BATON_HOME:?}/bin/lib/$stale"
done
# A stage is named with a leading dot, which the glob above does not match, and it is deliberately
# not swept. This script takes no lock and two close-outs can run it in the same minute (the cap is
# two), so a wildcard over `.stage-*` cannot tell an orphan from the directory a live install is
# filling — deleting one aborts that install under `set -e`, before it publishes anything, and a
# close-out whose install failed hands its successor the previous relay with nothing saying why. A
# run that succeeds leaves no stage: its own is removed by pid before it is created and consumed by
# the rename. An orphan from a killed install costs a few kilobytes and is never read, which is
# strictly better than a sweep that can kill a live install (D-131).
[ -z "$previous" ] || rm -f "$BATON_HOME"/bin/lib/*.sh

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

# Baton registers itself from the source checkout validated above.
project=$(basename "$canonical")
mkdir -p "$BATON_HOME/projects/$project"
if [ ! -f "$BATON_HOME/projects/$project/project.json" ]; then
  jq -n --arg p "$canonical" '{path: $p, plan: "docs/MILESTONES.md"}' > "$BATON_HOME/projects/$project/project.json"
fi
# The standing check, which Baton runs itself on the tree a completion claims to have merged
# (REQ-ARTIFACT-10). It is registered rather than read out of `CLAUDE.md`, which names it in prose,
# and rather than taken from the artifact, which is the thing being checked. The field is added to
# a registration that lacks it and never overwritten, because a person who changed the command
# meant it; the write is additive for the reason F11 gives — `install.sh` wrote `{path, plan}` only
# when the file was absent, so reinstalling over Baton's own registration could never supply a
# field registration did not have (D-147).
if ! jq -e '.check.command // empty' "$BATON_HOME/projects/$project/project.json" > /dev/null 2>&1; then
  jq '. + {check: {command: "sh tests/run.sh", deadline_seconds: 1800}}' \
    "$BATON_HOME/projects/$project/project.json" > "$BATON_HOME/projects/$project/project.json.tmp" \
    && mv "$BATON_HOME/projects/$project/project.json.tmp" "$BATON_HOME/projects/$project/project.json"
fi
# Two deny classes and nothing else (REQ-PERM-04): privilege escalation, and Baton's own state by
# named path — everything under BATON_HOME except inbox/. The // form is an absolute path for the
# tools that take one; the Bash fragments catch a shell command that names the path, and can
# never be complete (D-026).
#
# The rules themselves live in `lib/onboard.sh` as `onboard_deny_rules`, sourced here for that one
# function. The rail is the same rail for every target — a Reclaim session must no more edit
# `log.jsonl` or the launchd agent than a Baton session may — and `baton onboard` writes it for an
# arbitrary repository, so a second copy of the recipe here would be two recipes that a test could
# only compare rather than one that cannot disagree with itself. Nothing else from that library is
# called: sourcing it defines its functions and runs none of them.
. "$here/lib/onboard.sh"
jq -n --argjson deny "$(onboard_deny_rules)" '
  { permissions: { allow: ["Bash(sh tests/run.sh:*)", "Bash(jq:*)"], deny: $deny } }' \
  > "$BATON_HOME/projects/$project/permissions.json.tmp"
# An existing registration needs new rules too; preserve the file when it already matches.
if cmp -s "$BATON_HOME/projects/$project/permissions.json.tmp" "$BATON_HOME/projects/$project/permissions.json"; then
  rm -f "$BATON_HOME/projects/$project/permissions.json.tmp"
else
  mv "$BATON_HOME/projects/$project/permissions.json.tmp" "$BATON_HOME/projects/$project/permissions.json"
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
# directory and swapped into place, so a tick never finds the applet missing mid-install; and only when
# the source, the icon or this script — the recipe, recorded as its checksum in built-by — differs from
# what the installed applet was built from, so a second install changes nothing and a changed step
# reaches an applet already installed. Each key is deleted before it is added, because PlistBuddy's Add
# refuses a key that exists and a later osacompile may write one. A failed build leaves any applet
# already installed, and without one `notify` posts through osascript, so a failed install never
# silences the relay.
claude_icon=${BATON_CLAUDE_ICON:-/Applications/Claude.app/Contents/Resources/electron.icns}
app=$BATON_HOME/bin/Baton.app
recipe=$(cksum < "$here/install.sh")
if ! cmp -s "$here/notify/Baton.applescript" "$app/Contents/Resources/Baton.applescript" \
   || [ "$recipe" != "$(cat "$app/Contents/Resources/built-by" 2>/dev/null)" ] \
   || { [ -f "$claude_icon" ] && ! cmp -s "$claude_icon" "$app/Contents/Resources/applet.icns"; }; then
  stage=$BATON_HOME/bin/.Baton-build
  rm -rf "$stage"
  mkdir -p "$stage"
  plist=$stage/Baton.app/Contents/Info.plist
  if /usr/bin/osacompile -o "$stage/Baton.app" "$here/notify/Baton.applescript" > /dev/null 2>&1 \
     && cp "$here/notify/Baton.applescript" "$stage/Baton.app/Contents/Resources/Baton.applescript" \
     && printf '%s\n' "$recipe" > "$stage/Baton.app/Contents/Resources/built-by" \
     && { [ ! -f "$claude_icon" ] \
          || { cp "$claude_icon" "$stage/Baton.app/Contents/Resources/applet.icns" \
               && rm -f "$stage/Baton.app/Contents/Resources/Assets.car" \
               && { /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$plist" > /dev/null 2>&1 || true; }; }; } \
     && { /usr/libexec/PlistBuddy -c 'Delete :CFBundleIdentifier' "$plist" > /dev/null 2>&1 || true; } \
     && { /usr/libexec/PlistBuddy -c 'Delete :LSUIElement' "$plist" > /dev/null 2>&1 || true; } \
     && /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.baton.notify' \
          -c 'Add :LSUIElement bool true' "$plist" > /dev/null 2>&1 \
     && codesign --force --sign - "$stage/Baton.app" > /dev/null 2>&1; then
    [ ! -e "$app" ] || mv "$app" "$stage/Baton.old.app"
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
