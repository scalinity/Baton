Title: Permissions for a session nobody is watching
Labels: wayfinder:grilling
Status: closed
Assignee:
Blocked by: 03, 05

## Question

What permission mode and allowlist does a dispatched session run with?

Facts: `~/.claude/settings.json` sets `permissions.defaultMode: auto` today. Reclaim
authorises builds and tests (D-030) but has no `.claude/settings.json` and no allowlist, so
whether `xcodebuild`, `swift test` or `git commit` prompt depends on auto mode's judgement
each time. `--permission-mode` offers acceptEdits, auto, bypassPermissions, manual, dontAsk,
plan; `claude agents --allow-dangerously-skip-permissions` makes bypass *available* to
dispatched sessions without defaulting to it; `--restricted` exists. The principle in the
global CLAUDE.md is that safety must buy capability: cheap undo (git, a worktree per
session, Trash-first removal) beats a prompt nobody is awake to answer.

Decide:

- The mode per target project, and whether it differs for a session in a worktree.
- A project allowlist of tool patterns, and whether Baton passes it with `--settings` at
  dispatch so the target repo is not touched, or whether it belongs in the target's own
  `.claude/settings.json` as part of the project contract.
- What stays forbidden even unattended — network egress, `sudo`, deletion outside the
  worktree — and how that is enforced (allowlist, deny list, or the target's hard rules,
  which for Reclaim already forbid removal on real user data).
- What happens to a prompt that is neither allowed nor denied: it waits and escalates
  (per "What stops a session"), or it is refused and the session told why.

## Comments

### Merged — 2026-09-11

Folded into "Where an escalation goes" (`07-where-an-escalation-goes.md`), points 1–4 of its
Question, by "Relay or conductor": the permission mode, the allowlist, what stays forbidden and the
prompt that is neither allowed nor denied are the front half of the policy whose back half is the
escalation's channel, the lane pause and the ruling's return — one decision, one ticket. Nothing
was decided here.
