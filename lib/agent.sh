#!/bin/sh
# lib/agent.sh — the two verbs that stand the tick agent down and bring it back: `baton stop` boots
# com.baton.tick out of the login's launchd domain and `baton start` bootstraps the installed plist
# into it again (REQ-VERB-11, REQ-VERB-12, D-217).
#
# Both run under the lock (bin/baton), and for `stop` that is the point: `launchctl bootout` sends a
# running job an untrapped SIGTERM, so a tick caught between its `mkdir` and the writes of `pid` and
# `at` leaves a lock `lock_stale_break` cannot read, and one caught between a dispatch's writes (a
# worktree, settings, a session, an event) leaves the dispatch half done. The verb is reached only
# when no tick holds the lock; a tick that does makes it refuse, and it is run again. The hold is
# seconds: the standing check runs detached and holds no lock (D-187).
#
# A bootout lasts until the next login, which loads the plist again. Nothing here disables the agent
# or edits the plist, so the installed agent is exactly what `install.sh` left.
set -eu

AGENT_LABEL=com.baton.tick

# agent_target: the service target launchctl names the loaded agent by.
agent_target() { printf 'gui/%s/%s' "$(id -u)" "$AGENT_LABEL"; }

# agent_loaded: success when launchd holds the agent in the login's domain.
agent_loaded() { "$BATON_LAUNCHCTL" print "$(agent_target)" > /dev/null 2>&1; }

# verb_stop: boot the agent out. Already out is the state asked for, so it is a success.
verb_stop() {
  if ! agent_loaded; then
    render_row out record '%s is not loaded; nothing to stop\n' "$AGENT_LABEL"
    return 0
  fi
  if ! vs_err=$("$BATON_LAUNCHCTL" bootout "$(agent_target)" 2>&1); then
    render_failure err "baton: could not stop $AGENT_LABEL: $vs_err"
    return 1
  fi
  render_row out record 'stopped %s; no tick fires until baton start, and a restart loads it again\n' "$AGENT_LABEL"
}

# verb_start: bootstrap the installed plist. Already loaded is a success; no plist is a refusal that
# names the script that installs one, because loading is all this verb does.
verb_start() {
  if agent_loaded; then
    render_row out record '%s is already loaded; nothing to start\n' "$AGENT_LABEL"
    return 0
  fi
  vt_plist=$HOME/Library/LaunchAgents/$AGENT_LABEL.plist
  if [ ! -f "$vt_plist" ]; then
    render_failure err "baton: no launchd agent at $vt_plist" 'sh install.sh installs it'
    return 1
  fi
  if ! vt_err=$("$BATON_LAUNCHCTL" bootstrap "gui/$(id -u)" "$vt_plist" 2>&1); then
    render_failure err "baton: could not start $AGENT_LABEL: $vt_err"
    return 1
  fi
  render_row out record 'started %s; its first tick fires within a minute\n' "$AGENT_LABEL"
}
