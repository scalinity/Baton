# Background sessions: what `--bg`, `agents`, `attach`, `logs`, `stop`, `respawn` and `rm` do

Resolves `.scratch/baton/issues/05-background-sessions.md`. Written 2026-09-11 against
Claude Code **2.1.268** (`/Users/danny/.local/bin/claude` → `/Users/danny/.local/share/claude/versions/2.1.268`,
`claude --version` prints `2.1.268 (Claude Code)`).

Evidence tags:

- **[D]** official documentation at code.claude.com. Raw markdown was fetched from `<page-url>.md`
  and quoted from there; section anchors are given.
- **[L]** read-only local inspection (the command is given). No session was started, stopped,
  attached, respawned or resumed; three live Reclaim sessions were left untouched.
- **[B]** string constants and minified code found with `strings` in the installed binary. This shows
  what the code does, not what is documented; it is used only where the docs are silent and is
  never presented as a documented fact.
- **[U]** unverified: neither documented nor observed locally. Needs the live experiment owned by
  the "Watching a dispatched session" ticket.

The two background sessions that exist on this machine (`58e52bcf`, `7b97c070`) date from June and
July 2026 and ran under older versions; their transcripts have been cleaned up. No background
session has run under 2.1.268 here, so every runtime observation below comes from docs, from the
binary, or from interactive-session transcripts.

---

## 1. What `claude --bg "<prompt>"` prints, and what the id is

**Printed output** [D agent-view#from-your-shell, B]:

```text
backgrounded · 7c5dcf5d · flaky-test-fix
  claude agents             list sessions
  claude attach 7c5dcf5d    open in this terminal
  claude logs 7c5dcf5d      show recent output
  claude stop 7c5dcf5d      stop this session
```

- "After backgrounding, Claude prints the session's short ID and the commands for managing it. When
  the service that hosts background sessions isn't already running, `--bg` may first print
  `Starting background service…` above this output. When you pass `--name`, the name appears after
  the short ID." [D https://code.claude.com/docs/en/agent-view#from-your-shell]
- The banner line goes to **stdout** (`process.stdout.write(Mde(...))`); the `Starting …` line goes
  to **stderr** (`process.stderr.write(\`Starting ${tu()}…\`)`), where `tu()` renders as
  `background service` or, on some accounts, `daemon` [B; the docs confirm the daemon/background
  service wording variance at errors#eunknown-when-starting-a-background-session]. When no prompt is
  given the banner carries a dim suffix built from `(idle — <needs>)`, with `needs` =
  `send a prompt to start` [B; exact rendering U].
- Failure form: `Couldn't reach the background service (<reason>) — run 'claude daemon status'`,
  exit code 1 [D errors#background-session-errors; B `process.exitCode=1`].

**Id format and relation to `sessionId`:**

- The printed id is the **short id**: 8 lowercase hex characters (`7c5dcf5d` in every doc example;
  `58e52bcf` and `7b97c070` locally) [D, L `claude agents --json --all`].
- It is the **first 8 characters of the full session UUID**. Locally: `id: "58e52bcf"` ↔
  `sessionId: "58e52bcf-dcfa-474d-9c5a-01e179f71a18"` and `id: "7b97c070"` ↔
  `sessionId: "7b97c070-4729-47dc-9fc7-53c4b0ed28c8"` [L]. In the binary the dispatcher creates the
  job as `LDe(s.slice(0,8), …{sessionId:s})` with `s = o?.sessionId ?? It()` (a fresh UUID), and the
  job record stores `daemonShort: e.sessionId.slice(0,8)` [B]. The docs describe the two ids
  separately: `id` "Short ID, usable with `claude attach`, `claude logs`, and `claude stop`";
  `sessionId` "the full session UUID, usable with `claude --resume`" and "each session's ID is its
  directory name under `~/.claude/jobs/`" [D agent-view#list-sessions-as-json,
  #manage-sessions-from-the-shell].
- The prefix relation is not guaranteed forever: on an id collision the dispatcher starts a copy
  under a new id and prints `note: another background session already uses the id <X>, so this
  started a copy as <Y>.` [B]; `claude agents --json` is the authoritative join between `id` and
  `sessionId`.
- `--session-id` cannot choose the id: `warning: --bg manages the session id; ignoring --session-id
  (use --resume <id> to continue an existing session)` [B, see §2].

---

## 2. Which flags combine with `--bg`

| Flag | Combines with `--bg`? | Evidence |
|---|---|---|
| `-n`, `--name` | Yes. "Pass `--name` to set the session's display name in agent view instead of the auto-generated one." The name is **not** de-duplicated for background sessions: "It doesn't check the `--name` of a background or `-p` session at startup", so two background rows can share a name. Key on `id`/`sessionId`, never on name. | [D agent-view#from-your-shell; sessions#name-your-sessions] |
| `--model` | Yes. "From the shell, pass `--model` with `claude --bg`." Persists across supervisor restarts. | [D agent-view#set-the-model, #what-persists-across-restarts] |
| `--permission-mode` | Yes. "Dispatched from `claude agents` started in a shell, or with `claude --bg`: the new session starts the way a new `claude` session in that directory would" unless the flag sets one; `bypassPermissions` is refused "until you've accepted the bypass disclaimer by running `claude --dangerously-skip-permissions` once interactively". The chosen mode "persist[s] when the supervisor later stops and restarts its process". `--dangerously-skip-permissions`: "For sessions started with `--bg`, the mode persists when the supervisor restarts the session". | [D agent-view#permission-mode, #dispatch-defaults, #what-persists-across-restarts; cli-reference] |
| `--effort` | Yes. Effort "you chose for a background session … persist[s] when the supervisor later stops and restarts its process"; `--effort` is in the dispatcher's value-taking flag set. | [D agent-view#what-persists-across-restarts; B `Rie` set] |
| `--settings` | Yes. Listed among "Configuration flags from the original launch [that] carry through to the backgrounded session" (`--mcp-config`, `--strict-mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`, `--fallback-model`, `--allow-dangerously-skip-permissions`). | [D agent-view#what-carries-over-when-you-background] |
| `--append-system-prompt` | Not documented for `--bg` specifically. The flag is in the dispatcher's value-taking set and in the agent-view dispatch-defaults builder (`N_("--append-system-prompt", e.appendSystemPrompt)`), so it is forwarded to the worker [B]. Whether it survives a supervisor restart of the process is [U]; the system-prompt snapshot mechanism makes the first-request prompt reusable "on every later request and resume … until the conversation is compacted" [D cli-reference#system-prompt-flags-in-resumed-conversations]. |  |
| `--session-id` | **Ignored.** `warning: --bg manages the session id; ignoring --session-id (use --resume <id> to continue an existing session)` [B]. Live confirmation [U]. |  |
| `--resume <uuid>` | Yes, with copy semantics — see §5. | [D agent-view#from-your-shell; `claude --help`] |
| `-w`, `--worktree` | Not documented in combination. Background sessions isolate themselves: "Before editing files, Claude moves the session into an isolated git worktree under `.claude/worktrees/`" and "Claude skips the worktree when: The session is already inside a linked git worktree, whether Claude created it under `.claude/worktrees/` or you created it". `--worktree` is not in either of the dispatcher's known-flag sets, so a non-flag argument following it is consumed as its value; put the prompt last and give `-w` an explicit name. Whether the worker honours `-w` at all: [U]. | [D agent-view#how-file-edits-are-isolated; B argv scanner] |
| `--remote-control` | Not documented in combination. The dispatcher's argv scanner special-cases `--remote-control`/`--rc` so an optional name argument is consumed, i.e. the flag is forwarded [B]. The Remote Control page says renaming from claude.ai "applies the same rename … in the `claude agents` listing when the session runs in the background", so a Remote-Control session can exist in the background (at least via `←`/`/bg`). Whether `--bg --remote-control` enrols on dispatch: [U]. | [D remote-control#connect-from-another-device; B] |
| `-p`, `--print` | **Refused**: "Claude Code rejects `--bg` combined with `-p` or `--print` before any session is created". Error text: `--bg and --print conflict: --print never starts the interactive session that \`claude agents\` attaches to, so the job would be unattachable. The prompt is the positional — drop --print: \`claude --bg '<task>'\`.` | [D agent-view#from-your-shell; errors#conflict-between---bg-and---print] |
| `--agent <name>` | Yes; an unknown name "still reports the session as backgrounded, but the session exits immediately with an `--agent '<name>' not found` error". | [D agent-view#from-your-shell] |
| `--exec '<cmd>'` | Yes: a PTY-backed shell job, no model. Not listed in `claude --help` for 2.1.268 but documented and present in the binary. | [D agent-view#run-a-shell-command; L `claude --help`; B] |

The dispatcher's value-taking flag set (`Rie`) [B] is: `--exec --model -m --permission-mode
--inherit-permission-mode --proactivity --agent --agents --routine --effort --add-dir --mcp-config
--settings --setting-sources --system-prompt --system-prompt-file --append-system-prompt
--append-system-prompt-file --system-prompt-snapshot --append-subagent-system-prompt
--append-subagent-system-prompt-file --fallback-model --advisor --channels --watch-artifact
--watch-artifact-no-autoreact --permission-prompt-tool --permission-prompts --allowed-tools
--allowedTools --disallowed-tools --disallowedTools --tools --session-id --debug-file -n --name
--autocompact --betas --file --max-budget-usd --max-thinking-tokens --max-turns --task-budget
--plan-mode-instructions --plugin-dir --plugin-dir-no-mcp --plugin-url --rewind-files --thinking
--thinking-display --remote-control-session-name-prefix --json-schema`. Its boolean set (`fZe`) is:
`--dangerously-skip-permissions --allow-dangerously-skip-permissions --strict-mcp-config
--dangerously-allow-browser-network-access --restricted --disable-slash-commands --verbose
--reply-on-resume --ide --chrome --no-chrome --bare --brief --remote-control --rc`. Presence in a set
means the dispatcher parses past the flag to find the positional prompt; it does not by itself prove
the worker acts on the flag.

Permission-mode consequence for unattended runs: a background session in a prompting mode stops at
the first prompt and shows `state: blocked` / `waitingFor: "permission prompt"` (§3). "The continued
task runs like any other turn. Claude Code still asks for permissions as usual, so the task can stop
on a prompt while you're away." [D interactive-mode#wait-for-a-usage-limit-to-reset]. A
`PermissionRequest` or `PreToolUse` hook does run in background sessions [D agent-view#peek-and-reply
and version-history v2.1.248].

---

## 3. `claude agents --json`

**Invocation** [L, D]: `claude agents --json` needs no TTY ("for scripting; does not require a
TTY"); plain `claude agents` without a TTY exits with
`'claude agents' requires an interactive terminal (stdout is not a TTY) — use 'claude agents --json'
for a machine-readable listing.` `--all` "also include[s] completed background sessions"; `--cwd
<path>` limits to sessions started at or under that path (locally `--cwd
/Users/danny/Documents/Apps/Baton` returned `[]`). Keep `--add-dir`/`--mcp-config` after `agents`
[D agent-view#settings-plugins-and-mcp-servers]. Output is sorted by `startedAt` ascending [B].

**Exact field set.** The emitter builds each background row as
`{pid?, id, cwd, kind:"background", startedAt, sessionId, name?, status?, waitingFor?, state}` and
each interactive row as `{pid, cwd, kind:"interactive", startedAt, sessionId?, name?, status?,
waitingFor?}` [B `printAgentsJson`]. Documented presence rules [D agent-view#list-sessions-as-json]:

| Field | Present | Meaning |
|---|---|---|
| `cwd`, `kind`, `startedAt` | Always | working directory; `interactive` or `background`; start time in Unix ms |
| `id` | Background sessions | short id for `attach`/`logs`/`stop` |
| `state` | Background sessions | `working`, `blocked`, `done`, `failed`, `stopped` |
| `pid`, `status` | While the process is alive | pid; `busy`, `waiting`, or `idle` |
| `waitingFor` | When `status` is `waiting` | `permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open` |
| `sessionId`, `name` | When set | full UUID; interactive `name` is the default display name until named or a plan is accepted |

**Nothing about the last message is carried.** There is no summary, `detail`, `needs`, last-prompt or
exit-reason field; those live in `~/.claude/jobs/<id>/state.json`, which "are not a stable
interface" [D agent-view#read-session-state-from-a-script]. Interactive rows never carry `id` or
`state`.

Local sample [L `claude agents --json --all`, 2026-09-11]:

```json
{"id":"58e52bcf","cwd":"/Users/danny/Documents/LocalAI","kind":"background","startedAt":1782768744045,
 "sessionId":"58e52bcf-dcfa-474d-9c5a-01e179f71a18","name":"mlx","state":"failed"}
{"pid":94592,"cwd":"/Users/danny/Documents/Apps/Reclaim","kind":"interactive","startedAt":1789087366690,
 "sessionId":"fef27d52-2bfb-4197-924f-021711def7b9","name":"M14","status":"idle"}
```

Completed background rows have no `pid`/`status`; without `--all` a background row whose process has
exited is listed only while `state` is `working` or `blocked` [D agent-view#list-sessions-as-json;
B `if(!s&&!e&&r!=="working"&&r!=="blocked")continue`].

**How `state` is derived** [B, consistent with D]: process `status === "busy"` → `working`;
job settled → `done` / `failed` / `stopped` by outcome; job `tempo === "blocked"` or process
`status === "waiting"` → `blocked`; otherwise `working`. Registry `status` values are
`busy | shell | idle | waiting`; the JSON maps `shell` (a `!` command running) to `busy` [B].
Documented meanings [D agent-view#read-session-state-from-a-script]:

- `working`: "A turn is running, or the session is between steps of work it drives on its own …
  `status` tells you whether its process is `busy` right now"
- `blocked`: "The session is waiting on you: a question it asked, a permission or sandbox decision,
  an error only you can clear such as an expired login, or its first prompt if you started it
  without one. When the wait is an open prompt in a live process, `waitingFor` names it"
- `done`: "The last turn finished what you asked for and the session is ready for your next prompt,
  whether or not its process is still alive"
- `failed`, `stopped`: "The task ended with an error, or the session was stopped"
- "A session that finished its turn and is waiting for your next instruction reads `done`, not
  `blocked`. `blocked` always means the session needs something from you before it can continue."

**The three cases the ticket asks about:**

| Situation | `status` | `waitingFor` | `state` | Evidence |
|---|---|---|---|---|
| Waiting at a permission prompt | `waiting` | `permission prompt` | `blocked` | [D] field table; "Working, paused on a permission prompt or other dialog, or attached: the process keeps running" [D #the-supervisor-process] |
| Waiting on AskUserQuestion | `waiting` | `input needed` | `blocked` | [D] "`input needed` for a question from Claude or an MCP server's input request"; v2.1.212: "a question from Claude reports `waitingFor: input needed` instead of `permission prompt`" [D #version-history]. In the binary, `queuedElicitation` → `input needed` [B] |
| Stopped by a usage limit | expected `idle` (no dialog is opened in a background session) | absent | expected `blocked` | **[U]** — not documented. The binary maps API error kinds to job state: `billing_error` → `{state:"blocked", needs:"usage limit reached — check plan"}`, `rate_limit` → `{state:"blocked", needs:"rate limited — wait and retry"}`, `authentication_failed` → `{state:"blocked", needs:"login required — run /login"}`, `overloaded`/`server_error` → `blocked`, `unknown`/`dlp_request_denied` → `{state:"failed"}` [B]. The docs' `blocked` definition ("an error only you can clear such as an expired login") matches. Which kind a plan limit is classified as, and the live `status`, must be observed. After the ~1 h idle stop the row keeps `state: blocked` with no `pid`/`status` [D #the-supervisor-process, #list-sessions-as-json]. |

Other documented `waitingFor` sources: `sandbox request` (network-host prompt), `worker request`,
`dialog open` (a local dialog such as `/mcp` settings, managed-settings review, or a command that
needs an attached terminal) [D #list-sessions-as-json, #attach-to-a-session; B].

**`kind` values**: JSON `interactive` | `background` [D, B]. The underlying registry files
`~/.claude/sessions/<pid>.json` use `kind` ∈ `interactive | bg | daemon | daemon-worker` [B, L]. A
live registry entry (this session) [L `cat ~/.claude/sessions/11596.json`]:

```json
{"pid":11596,"sessionId":"46240cb0-…","cwd":"/Users/danny/Documents/Apps/Reclaim","startedAt":1789095150202,
 "procStart":"Fri Sep 11 02:52:29 2026","version":"2.1.268","peerProtocol":1,
 "peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"interactive",
 "entrypoint":"cli","pidDomain":"darwin","messagingSocketPath":"/tmp/cc-socks/11596.sock",
 "name":"Milestone Model Audit","nameSource":"user","nameSince":1789098437115,"status":"busy",
 "updatedAt":1789104087327,"statusUpdatedAt":1789104087327}
```

The JSON's interactive rows are these entries filtered to `pid, cwd, kind, startedAt, sessionId,
name, status, waitingFor` [B]. `nameSource` is `user` | `derived` locally; the schema also allows
`auto` and `collision` [B].

---

## 4. What `claude logs <id>` returns

- **Terminal output, not the transcript.** `claude logs --help`: "Print the background session's
  recent terminal output." [L]. Docs: "Print recent output from a background session" [D
  cli-reference], "Print the session's recent output" [D agent-view#manage-sessions-from-the-shell].
- **How much:** the docs do not quantify it. The CLI subscribes to the supervisor with `tail: 500`;
  the supervisor answers with a `snapshot` whose `streamTail` is `n.tail(p.tail ?? 200)` over a
  line-based stream (`{type:"stream", line}` events, pushed to a ring buffer) [B]. Reading: the last
  500 lines of captured output, from an in-memory buffer. Live confirmation of the count and of
  whether the buffer survives a process restart: [U].
- The captured output of `--exec` rows "stays in memory and isn't written to disk. The row and its
  output clean up automatically about five minutes after the command exits" [D
  agent-view#run-a-shell-command]. Whether Claude-session output is kept the same way: [U].
- Attached sessions "always render in fullscreen mode" [D agent-view#attach-to-a-session], so the
  captured stream is a fullscreen TUI's output; its parseability from a script is [U]. For
  structured reading the docs point at `claude agents --json` (state) and the transcript
  (`~/.claude/projects/...jsonl`, §7), not at `logs`.
- Failure text: `Couldn't read logs for <id> — <reason>`; "If attaching, peeking, or `claude logs`
  reports that the background service did not respond, the supervisor process has likely stalled"
  [B; D agent-view#agent-view-says-the-background-service-did-not-respond].

---

## 5. `claude --bg --resume <id> "<text>"`

`claude --help` [L]: "With --resume <session-id>, continues that session in the background under the
same ID, or starts a copy and says so when the session is already running".

Documented behaviour [D agent-view#from-your-shell, #version-history v2.1.257]:

- "To continue an existing conversation in the background, pass its full session ID with
  `--resume`". "Claude Code either continues that session under the same ID, or starts a copy under
  a new ID and prints a `note:` line explaining why it couldn't continue in place. When the session
  continues in place, `claude agents` shows one row for it."
- "When you combine `--bg` with `--continue`, a bare `--resume`, or `--resume` with a name or file
  path, Claude Code always starts such a copy. Add `--fork-session` to start a copy on purpose,
  without the note." So: always pass the full UUID, never a name.

**What "already running" means for an idle-but-alive session.** The check consults the live session
registry for any process holding that `sessionId`; a holder of kind `bg` or `daemon-worker` counts
as `running`, an interactive holder as `open-elsewhere`, and either result starts a copy [B]. The
note texts [B]:

- `note: session <X> is already running in the background, so this started a copy as <Y>.
  \`claude attach <X>\` opens the original.`
- `note: session <X> is open in another Claude Code process, so this started a copy as <Y>. The
  original conversation is unchanged.`
- `note: another background session already uses the id <X>, so this started a copy as <Y>.`
- `note: started a copy of that conversation as <Y>. To continue a session under its own id, pass
  its full session id (lowercase, as \`claude agents --json\` prints it) to --resume.`
- `note: could not check whether session <X> is running, so this started a copy as <Y>.` /
  `note: could not read the saved state of background session <X>, so this started a copy …`

Consequence: a session whose process is alive is "running" whether `status` is `busy` or `idle`;
`--bg --resume` on it forks a copy and the new text goes to the copy, not to the original. The
original receives the text only when no process holds the conversation, i.e. after `claude stop
<id>` ("Its conversation is kept: `claude attach <id>` opens it again, `claude --resume` works once
it is stopped" [L `claude --help`]) or after the supervisor's ~1 h idle stop (§9). The docs' two
"already open" refusals confirm the exclusivity: "Two processes can't write to the same transcript"
[D agent-view#opening-a-session-says-the-conversation-is-already-open]. Live confirmation of the
stop-then-resume route delivering the text as the next prompt under the same id: [U].

No shell command injects a prompt into a live background session. The documented routes are the
agent-view peek-panel reply and attaching; a reply that cannot be delivered "is saved and sent to the
session as its next prompt when its process starts again" [D agent-view#peek-and-reply]. The job
schema has a `queuedPrompt` field and the worker takes a `--reply-on-resume` flag for that path [B].

---

## 6. `attach`, `←`, Ctrl+Z, `stop`, `respawn`, and what a human's typing leaves behind

- `claude attach --help` [L]: "Open the background session in this terminal. ← returns to agent
  view, Ctrl+Z drops back to your shell. The session keeps running either way."
- `←` on an empty prompt, or `/exit`, detaches "and return[s] to agent view, whether you opened the
  session from agent view or with `claude attach <id>` from your shell". `Ctrl+Z` "also detaches but
  goes back to where you started instead: agent view if you attached from there, or your shell if
  you ran `claude attach`". `Ctrl+C` keeps its interrupt meaning; twice on an empty prompt detaches.
  "Detaching never stops a background session: `←`, `Ctrl+Z`, `/exit`, and double `Ctrl+C` or double
  `Ctrl+D` all leave it running. To end a session from inside it, run `/stop`." [D
  agent-view#attach-to-a-session]. In a foreground (non-background) session `Ctrl+Z` is "Suspend
  Claude Code" [D interactive-mode].
- Attaching to a stopped process restarts it: "when you reply or attach, Claude restarts from where
  it left off"; "When you attach, Claude posts a short recap of what happened while you were away."
  [D agent-view#read-session-state, #attach-to-a-session].
- `claude stop <id>` (alias `kill`): stops the process, keeps the conversation; `claude attach <id>`
  reopens it; `claude --resume` works once stopped [L `claude --help`; D]. In agent view `Ctrl+X`
  stops and a second `Ctrl+X` within two seconds deletes.
- `claude respawn <id>` / `--all`: "Restart a session, running or stopped, e.g. to pick up an updated
  Claude Code binary. The restarted session resumes its saved conversation; when none is on disk, it
  runs its original prompt again as a new conversation" [D agent-view#manage-sessions-from-the-shell].
  `claude respawn --help` [L]: "Restart a background session (or all of them) so it picks up the
  current Claude binary." Race: `Session <id> was stopped while the respawn was in flight` [D errors].
- `claude rm <id>`: removes the row; "The conversation transcript stays on your local machine,
  available through `claude --resume`"; keeps the worktree and the row when the worktree has
  uncommitted changes or unpushed commits, printing the exact `--discard-unpushed
  <commit>@<worktree-id>` / `--force-remove-worktree <worktree-id>` to pass on a second run [D
  agent-view#what-deleting-a-session-removes; L `claude rm --help`]. Agent-view deletion removes the
  worktree including uncommitted changes.
- Attach vs. resume are mutually exclusive entrances to one conversation: opening a row whose
  conversation a terminal resumed shows `Can't open — this session is running in another terminal`;
  when a non-interactive process holds it, `This conversation is already open in another running
  Claude session — use that one, or close it and try again` [D errors#this-session-is-running-in-another-terminal].
  `claude --continue` on a conversation still running in the background "exits with `Your most recent
  conversation is running in the background` and that session's ID" [D sessions#resume-a-session].
  `/resume` cannot take over a running background session ("one that is still running can't be
  resumed here, so attach") [D commands].

**Is a human's typing visible anywhere Baton can read?**

- **Transcript** (§7): every prompt is a `type: "user"` record. Locally, typed prompts carry
  `"origin":{"kind":"human"}` and `"promptSource":"typed"`; other observed `promptSource` values are
  `queued` and `system`, other observed `origin.kind` values are `task-notification`,
  `auto-continuation` and `peer` (cross-session message); the binary lists further kinds (`plugin`,
  `channel`, `remote_ref`, `suggestion`, `overlay`, `observer-activity`, `folder`, `composer`,
  `bundle`, `unclassified`) [L jq over `~/.claude/projects/-Users-danny-Documents-Apps-Reclaim/*.jsonl`; B].
  These were observed in interactive sessions; an attached background session "behaves like any
  other Claude Code session" [D agent-view#attach-to-a-session], so the same records are expected
  [U for attached specifically].
- **`claude logs <id>`**: the typed text echoes in the terminal stream (§4) [U as to rendering].
- **`claude agents --json`**: `status` flips to `busy` and `state` to `working` when the human sends
  a prompt; there is no "attached" flag in the JSON. `/status` inside the session shows `Session
  kind: background job · attached` or `background job · unattended` [D commands]; the job record has
  `firstTerminalAt`/`lastTerminalAt` (unstable interface) [L old `state.json`; B schema].
- Agent-view peek replies become the session's next prompt; an undeliverable reply is saved in the
  job record and delivered on the next start [D agent-view#peek-and-reply; B `queuedPrompt`].

---

## 7. Id → transcript path, and how a usage-limit stop presents

**Transcript location** [D sessions#where-transcripts-are-stored]: "Claude Code stores transcripts as
JSONL at `~/.claude/projects/<project>/<session-id>.jsonl`, where `<project>` is your working
directory path with non-alphanumeric characters replaced by `-`" (names over 200 characters are
truncated and hashed; `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_PROJECT_DIR_NAME` override). Locally the
Reclaim project dir is `~/.claude/projects/-Users-danny-Documents-Apps-Reclaim/` and each live
session has `<sessionId>.jsonl` there plus a `<sessionId>/` directory (subagent transcripts, tool
results) [L `ls`]. "Each line is a JSON object for a message, tool use, or metadata entry. The entry
format is internal to Claude Code and changes between versions".

Mapping steps for Baton: short `id` → `sessionId` via `claude agents --json --all` (or the prefix
rule of §1) → `~/.claude/projects/<dispatch-cwd-mangled>/<sessionId>.jsonl`. Caveat [U]: a
background session "moves the session into an isolated git worktree" before editing; the binary then
rewrites the job record's `cwd`/`originCwd` and its `linkScanPath` (the transcript path the
supervisor scans) [B `CRn`, `TRn`; L old `state.json` had
`"linkScanPath": "/Users/danny/.claude/projects/-Users-danny-Documents-Apps-ForestWalk/7b97c070-….jsonl"`
with `bgIsolation: "none"`]. Whether the file stays under the dispatch cwd's project dir after a
worktree move is not documented; the robust lookup is by `sessionId` across all project dirs, which
is what `claude --resume <id>` itself does since v2.1.223 [D sessions#resume-a-session].

**`~/.claude/jobs/<id>/`** [D agent-view#where-state-is-stored; L]: `state.json` (per-session state;
"Read it through `claude agents --json` instead of parsing the file"), `tmp/` (scratch;
`$CLAUDE_JOB_DIR/tmp`), plus, observed on the older entries here, `timeline.jsonl`
(`{"at","state","detail","text"}` lines) and `recap.trigger`. Old `state.json` fields observed:
`state, detail, tempo, needs, output, children, linkScanOffset, linkScanPath, template,
respawnFlags, bgIsolation, providerEnv, intent, name, nameSource, sessionId, resumeSessionId,
daemonShort, cwd, createdAt, updatedAt, firstTerminalAt, backend` [L]. Also `~/.claude/daemon.log`
and `~/.claude/daemon/roster.json` when the supervisor runs; neither exists now and `claude daemon
status` reports `not running` with sock dir `/tmp/cc-daemon-501/4724c2aa` [L].

**Transcript record vocabulary** [L jq over Reclaim transcripts]: top-level `type` values seen:
`user, assistant, attachment, system, permission-mode, mode, last-prompt, custom-title, ai-title,
atis-latch, agent-name, file-history-snapshot, file-history-delta, queue-operation, cost-state`.
`system` subtypes: `turn_duration, stop_hook_summary, away_summary, local_command, agents_killed,
compact_boundary, model_consent_fallback`. Assistant `message.stop_reason`: `tool_use`, `end_turn`,
and `stop_sequence` (only on synthetic error records).

**How an API-side stop presents in the transcript** [L, session `5eb95ab6-…`, version 2.1.267,
interactive]. The turn ends with a synthetic assistant record:

```json
{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,
 "errorDetails":"429 {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"This request would exceed your account's rate limit. Please try again later.\"},\"request_id\":\"req_…\"}",
 "requestId":"req_…","message":{"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"",
   "content":[{"type":"text","text":"You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."}]},
 "timestamp":"2026-09-10T00:19:40.621Z","sessionId":"5eb95ab6-…","version":"2.1.267", …}
```

followed by `{"type":"system","subtype":"turn_duration"}` and then nothing until the next prompt (in
that session the user ran `/model` and re-typed the task). Structural signal for Baton:
`type == "assistant" && isApiErrorMessage == true`, with `error` naming the kind. `error` values
observed across all local transcripts: `rate_limit` (the plan-limit case above), `authentication_failed`
("Failed to authenticate. API Error: 401 OAuth access token has expired. Re-authenticate to
continue."), `server_error` ("API Error: 529 Overloaded…", "API Error: Your computer went to sleep
mid-response…", "Request timed out", "API Error: Unable to connect to API (…)"), `invalid_request`
("Prompt is too long"), `unknown` ("API Error: 400 Output blocked by content filtering policy") [L].
The message text varies by limit: the docs' forms are `You've hit your session limit · resets
3:45pm`, `You've hit your weekly limit · resets Mon 12:00am`, `You've hit your Opus limit · resets
3:45pm`, `You've hit your Sonnet limit · resets 3:45pm` [D errors#youve-hit-your-session-limit]; the
local 2.1.267 record shows the model-family form `You've reached your Fable limit. Run
/usage-credits to continue or switch models with /model.` Match on the structure, not the text.

**What happens after the limit** [D]:

- "Claude Code blocks further requests until the reset time shown in the message. The session and
  weekly limits are shared across all models … The Opus and Sonnet limits each apply only to
  requests to that model family" [D errors#youve-hit-your-session-limit].
- Automatic wait-and-continue (v2.1.234+) applies to **interactive** sessions: "Claude Code waits in
  the open session and continues the task on its own after the limit resets … While Claude Code
  waits, a line at the bottom of the session shows … `Usage limit reached · continuing automatically
  at 3:45pm · esc to cancel`". It is **not offered in background sessions**: "Claude Code doesn't
  offer the wait at all in these cases: Background sessions and `-p` runs: the menu row isn't
  available." The wait also ends when the conversation is handed "to Claude Desktop, a background
  session, or the cloud." Re-arms at most twice; "Automatic continue stopped after repeated
  usage-limit hits · /rate-limit-options to try again" [D interactive-mode#wait-for-a-usage-limit-to-reset;
  settings-reference#autocontinueatusagelimit]. Baton therefore owns the reset wait for
  `--bg` sessions.
- In status: see §3 (`blocked`, `status` expected `idle`, [U]). The wait UI's fixed continuation
  prompt is not present in any local transcript; the record shape of an auto-continued turn is [U].
- Costs page for admins: "You've hit your session limit … a seat-based usage window … shared across
  all models, so the developer can't restore access by switching models with `/model`. The message
  shows when the window resets." [D costs#when-a-developer-asks-about-a-limit]. `/usage` shows plan
  limits and reset times; the status line can expose `rate_limits` fields [D errors].
- Limitations: "Rate limits apply: background sessions consume your subscription usage the same as
  interactive sessions, so running ten agents in parallel uses quota roughly ten times as fast as
  running one." [D agent-view#limitations].

---

## 8. Do `--bg` sessions honour hooks and `CLAUDE.md`?

- **CLAUDE.md: yes.** "CLAUDE.md files are markdown files that give Claude persistent instructions …
  Claude reads them at the start of every session." [D memory]. The agent-view page relies on it for
  background sessions: "Your git instructions take precedence: if the task, `CLAUDE.md`, or memory
  says you handle committing or pushing yourself, Claude leaves git to you." [D
  agent-view#how-file-edits-are-isolated]. "A background session reads its settings from the
  directory it runs in, the same as if you had started `claude` there. This includes `env` values in
  project settings" [D agent-view#settings-and-provider]. The only documented way to skip CLAUDE.md,
  hooks, plugins and auto-memory is `--bare`/`--safe-mode`, neither of which `--bg` adds [L
  `claude --help`; B: `--bare` is merely a pass-through flag in the dispatcher].
- **Hooks: yes, from settings.** Documented evidence that hooks run inside background sessions:
  `PermissionRequest`/`PreToolUse` hook output is validated and surfaced on the row ("When a
  `PermissionRequest` or `PreToolUse` hook returns output Claude Code can't validate … the row shows
  the hook event and `hook output invalid:`"; v2.1.248) [D agent-view#peek-and-reply,
  #version-history]; `WorktreeCreate` runs "for a background session that Claude Code isolates in
  its own worktree" and `WorktreeRemove` "when you delete a background session" [D hooks]; a
  `UserPromptSubmit` hook can block the usage-limit continuation prompt [D interactive-mode]. Local
  interactive transcripts contain `system/stop_hook_summary` records, showing hooks are recorded in
  transcripts generally [L].
- **Hooks that need agent view open**: the `Notification` hook types `agent_needs_input` and
  `agent_completed` fire "only while agent view is open in a terminal" [D hooks#notification;
  agent-view#read-session-state]. They are not a substrate for an unattended watcher.
- **Caveat, historical**: GitHub issue #58729 (reported against 2.1.140, closed) claimed background
  sessions did not load user-defined subagents from `~/.claude/agents/`
  [https://github.com/anthropics/claude-code/issues/58729]. Status in 2.1.268: [U]; the agent-view
  page documents `--agent <name>` and dispatch-time agent lookup in the session's own directory,
  which suggests it was addressed, but a run with a custom subagent would settle it.
- Hooks in a `--bare` or `--settings '{"disableAllHooks": true}'` launch are off [D hooks, cli-reference].

---

## 9. Supervisor facts the dispatch loop depends on

- "The supervisor is a background service that runs your background sessions so they keep working
  after you close agent view or your terminal. Claude Code starts it the first time you background
  a session or open agent view" [D agent-view#the-supervisor-process]. `claude daemon --help` [L]:
  "Service install is disabled in this version — the daemon runs on demand and exits when the last
  client disconnects." `claude daemon status` reports pid, version, uptime, socket dir, roster count
  [L: currently `not running`, roster absent].
- Process lifecycle by state [D #the-supervisor-process]: working / paused on a prompt or dialog /
  attached → keeps running (a running subagent, workflow or monitor counts as working). "Finished or
  waiting for your next message, and unattached for about an hour: the supervisor stops the process
  to free resources. A session that ended its turn by asking you a question counts as waiting for
  your next message. The conversation stays on disk, and the next time you attach or reply, the
  session resumes where it left off. Pin a session with `Ctrl+T` to keep its process running."
  Exited unexpectedly → restarted, except a session backgrounded with `←`/`/background` that was
  killed from outside, which is marked stopped. After an auto-update the supervisor restarts itself
  and moves idle sessions; "Sessions that are working, waiting on you, or attached aren't
  interrupted." Low memory also stops idle sessions.
- What persists across a process restart: permission mode, model, effort, the carried configuration
  flags, `/rename` names, a stashed prompt; effort taken from settings is re-read at each start
  [D #what-persists-across-restarts].
- Shutdown: "Within 48 hours, the session shows as failed. Attach or reply to it and it restarts
  from where it left off. Past 48 hours … the session shows as stopped with `ended while the
  background service was off`" (the 48 h constant is `172800000` ms in the binary); sleep is
  preserved and reconnected on wake [D #sessions-show-as-failed-after-shutdown; B]. When transcript
  cleanup (`cleanupPeriodDays`, default 30) has removed the conversation: `This session's saved
  conversation is no longer on disk … \`claude rm <id>\` deletes the row; \`claude respawn <id>\`
  runs its original prompt again instead.` [D errors].
- Worktrees: every background session "starts in your working directory" and moves into
  `.claude/worktrees/<name>` before its first edit unless already inside a linked worktree, outside a
  git repository, or `worktree.bgIsolation` is `"none"` in the project's `.claude/settings.json`.
  Inside a git repository "Claude Code blocks writes to the shared checkout until Claude moves the
  session into a worktree." When it edited in its own worktree it commits without asking, pushes
  when a remote exists, and may open a draft PR; "if the task, `CLAUDE.md`, or memory says you handle
  committing or pushing yourself, Claude leaves git to you." [D #how-file-edits-are-isolated].
- Environment inside a background session [B, D]: `CLAUDE_CODE_SESSION_KIND=bg`,
  `CLAUDE_JOB_DIR=~/.claude/jobs/<id>`, plus `CLAUDE_BG_SOURCE`, `CLAUDE_BG_ISOLATION`,
  `CLAUDE_BG_BACKEND`, `CLAUDE_CODE_SESSION_NAME`. Fullscreen rendering is forced on for `bg`.
  The session runs with the dispatching shell's `PATH` and provider selection; gateway
  `ANTHROPIC_BASE_URL` exported only in the shell reaches it only under the listed conditions —
  settings-file `env` is the reliable route [D #settings-and-provider, #llm-gateway].
- Credentials: "Background sessions get their credentials from the supervisor"; `Could not resolve
  authentication method` means the supervisor started without a stored credential — fix with `/login`
  then `claude daemon stop --any --keep-workers` [D #dispatch-fails-with-could-not-resolve-authentication-method].

---

## 10. What only the live experiment can settle

Owned by "Watching a dispatched session". Each item names what to record.

1. `status`/`state`/`waitingFor` of a `--bg` session at the moment a plan usage limit is hit, and
   the exact assistant record written to its transcript under 2.1.268 (expected: `state: blocked`,
   `status: idle`, `isApiErrorMessage: true`, `error: "rate_limit"`; see §3, §7).
2. Whether a `--bg` session ever auto-continues after the reset (docs say the wait is not offered;
   confirm no `auto-continuation` prompt appears and the row stays `blocked`).
3. `claude stop <id>` followed by `claude --bg --resume <sessionId> "<text>"`: confirm it continues
   under the same `id` and that `<text>` lands as the next `user` record; confirm that the same
   command against an idle-but-alive session prints the `note: … already running … started a copy`
   line and creates a second row (§5).
4. The transcript's location after the session moves into a worktree (§7), and whether
   `state.json` still exposes `linkScanPath` in the 2.1.268 layout.
5. `claude logs <id>`: line count and whether the output is readable text or fullscreen escape
   sequences (§4).
6. `--append-system-prompt` after a supervisor restart of the process; `-w` and `--remote-control`
   under `--bg` (§2).
7. The `user` record written when a human types into an attached session (`origin.kind`,
   `promptSource`), and whether a peek-panel reply is distinguishable from a typed prompt (§6).
8. Whether user-defined subagents in `~/.claude/agents/` load in a `--bg` session (§8, issue #58729).

---

## Appendix: commands run (all read-only)

```text
claude --version; claude --help; claude agents --help; claude attach --help; claude logs --help
claude respawn --help; claude stop --help; claude rm --help; claude daemon --help; claude daemon status
claude agents --json; claude agents --json --all; claude agents --json --cwd /Users/danny/Documents/Apps/Baton
claude agents            # without a TTY: prints the "requires an interactive terminal" refusal
ls -la ~/.claude ~/.claude/sessions ~/.claude/jobs ~/.claude/jobs/<id> ~/.claude/projects/<project>
cat ~/.claude/sessions/<pid>.json; cat ~/.claude/jobs/<id>/state.json ~/.claude/jobs/<id>/timeline.jsonl
jq over ~/.claude/projects/-Users-danny-Documents-Apps-Reclaim/*.jsonl  (type / subtype / stop_reason /
    isApiErrorMessage / error / origin.kind / promptSource tallies)
rg -a -uu over ~/.claude/projects/**/*.jsonl for isApiErrorMessage records
strings -n 8 /Users/danny/.local/share/claude/versions/2.1.268 | rg …   (binary evidence, tag [B])
curl of code.claude.com/docs/en/{agent-view,cli-reference,sessions,errors,interactive-mode,commands,
    memory,hooks,worktrees,costs,settings-reference,remote-control}.md and docs/llms.txt
```

Docs pages cited: https://code.claude.com/docs/en/agent-view · https://code.claude.com/docs/en/cli-reference ·
https://code.claude.com/docs/en/sessions · https://code.claude.com/docs/en/errors ·
https://code.claude.com/docs/en/interactive-mode · https://code.claude.com/docs/en/commands ·
https://code.claude.com/docs/en/memory · https://code.claude.com/docs/en/hooks ·
https://code.claude.com/docs/en/costs · https://code.claude.com/docs/en/settings-reference ·
https://code.claude.com/docs/en/remote-control · https://github.com/anthropics/claude-code/issues/58729
