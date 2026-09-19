#!/bin/sh
# lib/permissions.sh — the two deny classes of REQ-PERM-04, in one place, for every caller.
#
# The rail is the same rail for every target: a Reclaim session must no more edit `log.jsonl` or the
# launchd agent than a Baton session may, and `baton onboard` writes it for an arbitrary repository
# that `install.sh` knows nothing about. So the rules live here rather than inline in either, and
# there is one recipe with several callers instead of copies a test could only compare.
#
# It is a file of its own, and not a function of `lib/onboard.sh`, because `install.sh` is one of the
# callers: sourcing the onboarding verb for its deny rules would make the installer depend on the
# verb and run every top-level statement in it. The dependency this way round reads installer → rail
# and verb → rail, which is what it is.
#
# Nothing here is sourced for its side effects and nothing here calls anything else, so `install.sh`
# can source it under its own `set -eu` before the library set exists in its destination.
set -eu

# permissions_deny_rules: the deny rules for a project of this home, as a JSON array on stdout.
# Privilege escalation, and Baton's own state by named path — everything under `$BATON_HOME` except
# `inbox/`.
#
# It takes no arguments and reads `$BATON_HOME`, because the rules name Baton's home and not the
# project: a project's own paths are never denied. `worktrees/` is deliberately unnamed, because it
# holds the session's own working directory and a rule denying writes under it would deny the session
# its own repository (D-153). `bin` is denied to Edit and Write but only `bin/lib` to Bash, so a
# session can run `baton status` and cannot name a write into the sourced libraries (D-112).
#
# The `//` form is an absolute path for the tools that take one; the `Bash(*.baton/<name>*)` fragments
# catch a shell command that names the path and can never be complete, which is the stated limit of
# the class (D-026).
permissions_deny_rules() {
  jq -nc --arg h "/$BATON_HOME" '
    ["Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)", "Bash(osascript * administrator privileges*)"]
    + ["Read(\($h)/log.jsonl)", "Edit(\($h)/log.jsonl)", "Write(\($h)/log.jsonl)"]
    + ([ "archive", "rejected", "prompts", "settings", "projects", "bin", "status", "lock", "notify", "checks" ]
       | map("Edit(\($h)/\(.)/**)", "Write(\($h)/\(.)/**)"))
    + ["Edit(\($h)/config.json)", "Write(\($h)/config.json)", "Edit(\($h)/last-tick)", "Write(\($h)/last-tick)"]
    + ([ "log.jsonl", "archive", "rejected", "prompts", "settings", "projects", "status", "lock", "config.json", "last-tick", "notify", "checks" ]
       | map("Bash(*.baton/\(.)*)"))
    + ["Bash(*.baton/bin/lib*)"]
    # The launchd agent joins the named paths from M03. It sits outside ~/.baton but is Baton state by
    # every other measure, and what it names is executed every sixty seconds by a shell with Full Disk
    # Access (D-048).
    + ["Edit(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
       "Write(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
       "Bash(*com.baton.tick*)"]'
}
