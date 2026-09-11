Title: Hooks in 2.1.268: events and payloads
Labels: wayfinder:research
Status: closed
Assignee: research-hooks
Blocked by: —

## Question

For Claude Code 2.1.268 (the installed version — `claude --version`), what hook events
exist, what each receives on stdin, and what a hook's exit code or JSON output can make the
session do? Specifically:

- **Stop**: does it receive `transcript_path` and `stop_hook_active`? Can a Stop hook
  return `decision: block` with a `reason`, and does the session then continue with that
  reason as its next instruction — a native nudge, which would make "print the handover"
  free? Does it fire once per assistant turn or only at the end of a conversation?
- **Notification**: the `notification_type` values (permission_prompt, idle_prompt, others)
  and their timing — how long idle before `idle_prompt` fires?
- **SessionEnd**: the `reason` values. **SessionStart**: the `source` values (startup,
  resume, clear, compact).
- **UserPromptSubmit**, **PreCompact**, **PostCompact** if it exists, **SubagentStop**.
- Do hooks run in `--bg` sessions and in `-p` sessions?
- Where hooks are configured (`~/.claude/settings.json`, `.claude/settings.json`,
  `.claude/settings.local.json`), and whether a `--settings <file>` passed at dispatch can
  inject hooks so the target repo stays untouched.
- The matcher syntax, the timeout, and whether hooks can be `async`.

Sources: the official Claude Code hooks documentation (cite the URLs); the `claude-code-guide`
agent is the tool for this. Local read-only inspection is allowed (`claude --help`, the
transcripts under `~/.claude/projects/`); do not start sessions.

Deliver a table — event → payload fields → what a return value can do — as
`.scratch/baton/research/hooks.md`, and link it from this ticket's Comments.

## Comments

### 2026-09-11 — research-hooks

- Findings: [`.scratch/baton/research/hooks.md`](../research/hooks.md) — event → payload → return-value table for all 33 events in 2.1.268, then per-question answers, each with the source URL; unverified points listed in its §5.
- Stop fires once per turn (not on user interrupt; API errors fire StopFailure) and receives `transcript_path`, `stop_hook_active`, `last_assistant_message`, `background_tasks`, `session_crons`. `{"decision":"block","reason":…}` or exit 2 keeps the session going with the reason delivered as Claude's next instruction (`hookSpecificOutput.additionalContext` does the same, labelled feedback rather than error) — the native nudge exists; the hook must gate itself on `stop_hook_active`/a sentinel because Claude Code overrides it after 8 consecutive blocks (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`).
- Notification: 12 types; `idle_prompt` ≈60 s after a response with no typing, and SDK/`-p` sessions get only `permission_prompt`, `elicitation_complete`, `elicitation_response`. SessionEnd `reason`: clear, resume, logout, prompt_input_exit, other. SessionStart `source`: startup, resume, clear, compact, fork. PostCompact exists (`trigger`, `compact_summary`).
- `-p` runs settings-file hooks (folder treated as trusted; `--bare` skips them). `--bg` cannot combine with `-p`; docs establish hooks there only indirectly (settings read from the session directory, PreToolUse/PermissionRequest hook output surfaced on agent-view rows, WorktreeCreate for background sessions) — `idle_prompt` inside a detached `--bg` session is unverified.
- `--settings <file>` is a one-session layer above user/project/local that writes no file; `hooks` is an "Any file" key that merges across sources, so a hooks block there injects without touching the repo. No official example shows it; inferred from the two documented statements. Timeouts: 600 s command/http/mcp_tool (30 s on UserPromptSubmit), 30 s prompt, 60 s agent, 1.5 s SessionEnd budget; `async: true` hooks cannot block and deliver on the next turn.
