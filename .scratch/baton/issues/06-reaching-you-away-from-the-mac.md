Title: Reaching you when you're not at the Mac
Labels: wayfinder:research
Status: closed
Assignee: research-reach
Blocked by: —

## Question

The facts behind the escalation channel, for Claude Code 2.1.268:

- **Remote Control** (`--remote-control [name]`,
  `--remote-control-session-name-prefix`): what it is; whether a session can be driven from
  claude.ai on a phone; whether a permission prompt or an AskUserQuestion can be answered
  from there; whether it combines with `--bg`; what it needs (login, network, the desktop
  app); whether it can be switched on for a session that is already running.
- **Notifications from a script without third-party packages**: `osascript -e 'display
  notification'` (its limits — no actions, no reply), Shortcuts automation, whether the
  Claude desktop app (`/Applications/Claude.app` is installed) shows Claude Code sessions or
  their prompts, and whether Claude Code has any built-in notification setting or channel
  (a `Notification` hook that could call a script is the hooks ticket's territory; here, what
  the script could call).
- What reaches a phone with nothing installed: iMessage via `osascript` to Messages, a mail
  draft, or nothing.

Sources: official documentation (cite URLs), then local read-only inspection. Do not start
sessions.

Deliver `.scratch/baton/research/reaching-you.md`, and link it from this ticket's Comments.

## Comments

**2026-09-11 — research-reach.** Findings in `.scratch/baton/research/reaching-you.md`.
Remote Control (`--remote-control [name]`, `/remote-control` in a running session, or
`remoteControlAtStartup`) is the one documented channel where a phone both hears and acts:
permission prompts and `AskUserQuestion` stay open until answered from the Claude app, with
push via `inputNeededNotifEnabled`; it needs an interactive session (no `-p`), and on this
Mac it is blocked by `export DISABLE_TELEMETRY=1` at `~/.zshrc:10` until that is unset for
the process (login is claude.ai/Max, otherwise eligible). Whether it combines with `--bg` is
undocumented — unverified. `display notification` has only title/subtitle/sound (no
actions, no reply) and stays on the Mac; the desktop app does not see CLI sessions. With
nothing installed, `osascript` can send an iMessage (self-chat syncs to the phone; alert
behaviour unverified) or an email — both one-way; two-way iMessage needs the official
channel plugin plus Bun, which relays tool approvals but not, per the docs, questions.

**2026-09-11 — unblocked.** `~/.zshrc:10` now reads `#export DISABLE_TELEMETRY=1`. The other
two exports beside it (`CLAUDE_TELEMETRY_DISABLED`, `ANTHROPIC_TELEMETRY_DISABLED`) are not on
the documented blocker list (`DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`) and stay. The change
reaches new shells only; sessions already running were started with the variable exported.
Eligibility is confirmed with `claude doctor` from a fresh terminal — the research file's §5
item 2.
