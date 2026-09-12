#!/bin/sh
# Lifecycle Git operations do not implicitly execute project hooks or filesystem monitors.
# Identity and merge semantics continue to use the existing Git configuration.
baton_git() { command git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
