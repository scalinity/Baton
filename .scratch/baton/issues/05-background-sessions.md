Title: Background sessions: what --bg, agents and attach actually do
Labels: wayfinder:research
Status: closed
Assignee: research-bg
Blocked by: —

## Question

The facts Baton's dispatch and monitoring rest on, for Claude Code 2.1.268:

- What `claude --bg "<prompt>"` prints — the id's format, and whether it is the
  `sessionId` that `claude agents --json` reports.
- Which flags combine with `--bg`: `-n`, `--model`, `-w`, `--permission-mode`,
  `--session-id`, `--append-system-prompt`, `--settings`, `--remote-control`, `--effort`.
- What `status` means in `claude agents --json`: is a session waiting at a permission
  prompt `idle` or `busy`? One waiting on AskUserQuestion? One stopped by a usage limit?
  Does the JSON carry anything about the last message, or only `cwd, kind, name, pid,
  sessionId, startedAt, status`? What are the `kind` values?
- What `claude logs <id>` returns — terminal output or transcript — and how much.
- Whether `claude --bg --resume <id> "<text>"` delivers new text to a stopped or idle
  session, and what "starts a copy and says so when the session is already running" means
  for a session that is idle but alive.
- How `attach`, `←`, Ctrl+Z, `stop` and `respawn` interact, and whether a human typing into
  an attached session is visible anywhere Baton can read.
- The mapping from id to transcript path, and how a usage-limit stop presents in the
  transcript (record type, text) and in status.
- Whether `--bg` sessions honour hooks and `CLAUDE.md`.

Sources: the official documentation first (cite URLs); then read-only local inspection —
`claude --help`, `claude agents --help`, `claude agents --json`, existing transcripts under
`~/.claude/projects/`. **Do not start, stop or attach to sessions**: three Reclaim sessions
are live on this machine and must not be disturbed. Anything that needs a live experiment
goes to "Watching a dispatched session", which is done by hand.

Deliver `.scratch/baton/research/background-sessions.md`, and link it from this ticket's
Comments.

## Comments

**2026-09-11 — research-bg.** Findings in `.scratch/baton/research/background-sessions.md`
(each bullet answered with its doc URL, local command, or binary-string evidence; unverified items
tagged and listed in §10 for "Watching a dispatched session"). Gist: `claude --bg` prints
`backgrounded · <8-hex id>[ · name]` on stdout, and the id is the first 8 characters of the
`sessionId` UUID; `--session-id` is ignored under `--bg`, `-p` is refused, `--name` is not
de-duplicated. `claude agents --json` carries only `cwd, kind, startedAt, id, state, pid, status,
waitingFor, sessionId, name` — nothing about the last message; a permission prompt is
`status: waiting` + `waitingFor: "permission prompt"` + `state: blocked`, AskUserQuestion is
`waitingFor: "input needed"`. `claude logs` prints recent terminal output (a ~500-line in-memory
tail per the binary), not the transcript. `--bg --resume <uuid>` forks a copy whenever any process
holds the session — an idle-but-alive one included — so text reaches the original only after
`claude stop <id>` or the ~1 h idle stop. A usage-limit stop is a synthetic assistant record
(`isApiErrorMessage: true`, `error: "rate_limit"`, `stop_reason: "stop_sequence"`); the docs say the
auto-wait is not offered in background sessions, and the binary maps the error to `state: blocked`
(status at that moment unverified). Hooks and CLAUDE.md apply; `--bare` is the only opt-out.
