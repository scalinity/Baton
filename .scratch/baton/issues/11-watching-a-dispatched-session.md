Title: Watching a dispatched session
Labels: wayfinder:prototype
Status: closed
Assignee: danny
Blocked by: 05

## Question

Before deciding whether a Terminal.app tab per session is still wanted, run one real
dispatch by hand and react to it. In a scratch project — never Reclaim, which has sessions
in flight — run:

    claude --bg -n "Baton trial" --model haiku "<a small, safe task>"

then watch it through `claude agents`, open it with `claude attach <id>`, type something,
drop back with Ctrl+Z, try `claude logs <id>`, and `claude stop` it.

While it runs, work through the eight items in §10 of
`.scratch/baton/research/background-sessions.md` — each names what to record — and the two
questions the other research left unverified: whether `--remote-control` combines with
`--bg` (`research/reaching-you.md` §5) and whether `idle_prompt` fires inside a detached
`--bg` session (`research/hooks.md` §5). This ticket is the only place those get settled,
because it is the only one allowed to start a session.

React to:

- Is the agent view enough on its own, or is a tab per session wanted? A tab is one
  `osascript` away — Terminal.app can open a tab running `claude attach <id>` — and tmux
  and iTerm2 are not installed, so a tab is the only "window per session" available.
- How it feels to take over a session and hand it back, and whether anything tells Baton
  that a human did.
- Whether `Claude.app` (the desktop app, installed) shows these sessions, and whether that
  is a better window than a terminal.
- What the session's name should carry beyond the milestone id — the model? the project?

Output: the watching-and-intervening design, as the resolution comment. Link any
screenshots from the ticket rather than pasting them in; delete them from the project
afterwards.

### Added by "What a project hands to Baton" (2026-09-11)

Also verify, because that decision depends on them: (9) a `hooks.Stop` block passed with
`--settings` runs inside the `--bg` session (the injected Stop gate), and if it does not, a
`.claude/settings.local.json` written into the session's worktree does; (10)
`CLAUDE_CODE_SESSION_ID` is present in the `--bg` session's shell environment and equals the
`sessionId` that `claude agents --json` reports; (11) the session can write
`~/.baton/inbox/<milestone>-<session>.json.tmp` and rename it into place, and the Stop hook sees
the file at the moment it fires.

### Added by "Relay or conductor" (2026-09-11)

The relay is a launchd-run script and dispatched sessions belong to the supervisor, so also prove,
from a launchd context (a LaunchAgent, not a terminal): (12) the CLI is reached by absolute path
(`/Users/danny/.local/bin/claude`; launchd gives the job no shell `PATH`); (13) the background
service starts when it is down (`claude daemon status` reports "not running" between runs;
background-sessions §9); (14) the dispatched session outlives the tick's exit (the plist sets
`AbandonProcessGroup`; the session must still be a live row in `claude agents --json` after the
script has exited); (15) the Keychain is readable in that context, so the supervisor started from
it has credentials (§9: "Background sessions get their credentials from the supervisor"). Also
(16) `claude stop <id>` then `claude --bg --resume <uuid> --settings <gate> "<ruling>"` continues
under the same id, re-injects the Stop gate and lands the ruling as the next user record (extends
§10 item 3); and (17) `caffeinate -i -w <pid>` against the pid `claude agents --json` reports holds
idle sleep for the session's life, and what the row's pid is after the supervisor restarts the
process. A `--bg` session started from inside another session's hook is not needed by the relay
and is not on this list.

### Added by "What stops a session, and what happens next" (2026-09-11)

Also prove, because the rules there key on them: (18) StopFailure fires inside a `--bg` session, the
injected hook writes the `api-error` artifact (fire-and-forget: it may land a beat after the row flips),
and what `error_details` holds for a `rate_limit` — compare it with the transcript's `errorDetails`
(background-sessions §7). (19) A `statusLine` command passed in the same `--settings` file runs inside a
`--bg` session and its stdin carries `rate_limits` with `resets_at` there — the "field later" proof for the
wait; cheap to observe while a session is up. (20) `claude stop <id>` against a session waiting at a
permission prompt, then `claude --bg --resume <uuid> "<text>"`: which marker the pending tool call
receives and that the text lands as the next user record. (21) Whether the supervisor's ~1 h idle stop
applies to a session waiting at AskUserQuestion (`waitingFor: "input needed"`), and whether a stopped one
can be answered on resume — the "prompt lost" rule fires only if it does. (22) Where a session's subagent
transcripts live under 2.1.268 (locally `~/.claude/projects/<slug>/<sessionId>/subagents/agent-*.jsonl`)
and whether they move with the worktree (extends item 4), because the stall stat takes the newest mtime
across them. (23) Resume after a crash: `claude --bg --resume <uuid>` against a session whose process is
gone (row absent, or `state: failed` after a restart) continues under the same id, and what `claude stop`
prints against a dead process. (24) During a wake from sleep and a supervisor restart, how long a live
session's row is absent or `failed` — the margin the two-tick crash confirmation relies on. (25) The
Notification hook's `permission_prompt` type fires inside a `--bg` session and its `message` names the
tool and command.

### Added by "Where an escalation goes" (2026-09-11)

Ten more, because the escalation channel and the permission policy both rest on them. **Item 26 is a
gate: it passes before the first unattended night, or the recorder design changes.**

(26) A `PermissionRequest` hook that writes a file and returns **no decision**, inside a `--bg`
session at a real permission prompt: does the prompt stay open for the person, or is the call
denied? The documentation says "if no hook returns a decision, it denies the tool call", and the
hook's decision schema offers only `allow` and `deny` — there is no explicit "ask" — so if it
denies, `PermissionRequest` cannot be a recorder at all and the fallback is the `Notification`
hook's `permission_prompt` type, losing the command text and the suggested rule. (27) What
`permission_suggestions[]` actually holds for a Bash prompt: present or absent, one rule or several,
and in what form — that is the string `baton allow` writes verbatim, and the promise that Baton
never composes a rule depends on it existing. (28) `PermissionDenied` fires inside a `--bg` session
under `auto`, and what `reason` holds: for an ordinary classifier denial, for the context-window
form ("the auto mode classifier transcript exceeded its context window"), and for the "temporarily
unavailable" form on a large session — the three-denials-on-one-command-head threshold and the
classifier-failure notification both key on that payload. (29) Whether the classifier ever routes a
call to a held prompt (a row at `waitingFor: "permission prompt"`) without a `permissions.ask` rule
or a hook `ask`, and whether the auto-mode circuit-breaker string ever appears for a `--bg` session
— its only known occurrence is an IDE startup check.

(30) `permissions.allow` and `permissions.deny` passed in the `--settings` file reach a `--bg`
session and bite: a listed `Bash(xcodebuild:*)` runs without a prompt, an unlisted command does not,
and `Bash(sudo:*)` is refused. (31) Whether `Bash(osascript * administrator privileges*)` matches
when the phrase sits inside a quoted `-e` argument; if it does not, the rule matches nothing — the
silent failure — and that line is carried by the target's hard rules alone.

(32) `osascript` driving Messages **from a launchd context**: whether the Automation (TCC) approval
can be granted at all for a launchd-started process, which app the prompt names, and whether a send
fails silently when it has not been. A script that works in Terminal can fail silently under
launchd, and the escalation channel's floor is this send. (33) Whether iOS raises an alert for an
iMessage the same account sent itself from the Mac (`research/reaching-you.md` §5 item 3) and, if it
does not, whether Mail through `osascript` has a configured sending account on this Mac as the
fallback (§5 item 5). (34) That the row transition is enough to unpark a lane: a `--bg` session at
`waitingFor: "permission prompt"` answered in place — attached, or from the Claude app in a
`--remote-control` session — loses `status: waiting` and `waitingFor` in `claude agents --json`, and
how long that takes. It is the only signal available, no `answeredBy`-style field existing anywhere.
(35) `baton allow --resume` end to end: `claude stop <id>` at a live permission prompt, then
`--bg --resume` with the widened `--settings`, and whether the re-issued command now passes without
a prompt (extends item 20, which covers the marker the dropped call receives).

## Comments

### Resolution — 2026-09-11

Fifteen background sessions were dispatched into a throwaway git checkout, named `Baton trial A`
through `Baton trial S`, on Claude Code 2.1.268. Every item below was observed live; none is
reported from documentation. Hook payloads, row transitions and launchd output are kept under
`.scratch/baton/prototype/obs/`, which M01 can read.

The headline is not on the original list. **A `--bg` session cannot run in `auto` permission mode.**
That invalidates the mechanism half of "Where an escalation goes" and changes what an unattended
night looks like, so it is treated first, below the table.

#### Fixtures

`.scratch/baton/prototype/` holds the throwaway hook scripts (`stop-gate.sh`, `stop-failure.sh`,
`permission-request.sh`, `permission-denied.sh`, `notification.sh`, `statusline.sh`), the
`--settings` file they are injected through (`settings-A.json`), the two launchd probes and their
output, and the observation files. `BATON_MILESTONE=T01` and `BATON_PROJECT=<trial path>` were
passed on each hook's command line and arrived intact. `~/.baton/{inbox,archive,rejected,status}`
was the fixture inbox. The trial checkout, the LaunchAgents plists and `~/.baton` are deleted at
close-out; `.scratch/baton/prototype/` stays.

#### The items

| # | Verdict | Observation |
|---|---|---|
| §10-1 usage-limit row + transcript record | unrun | No plan limit was reached. `rate_limits` read `five_hour 24%`, `seven_day 21%` at the start and the session never approached either. Cannot be forced. |
| §10-2 auto-continue after reset | unrun | Same reason, and confounded regardless: `~/.claude/settings.json` already sets `autoContinueAtUsageLimit: false`, so an absent continuation prompt would prove nothing about `--bg`. |
| §10-3 stop + resume under the same id | verified, and wider than stated | Flagless `claude --bg --resume <uuid> "<text>"` continued under the same id four times out of four, printing `note: woke session <id> with its saved options (-n, --settings, --model, --permission-mode)`. The copy behaviour is **not** limited to an already-running session: passing any flag to a *stopped* session also forked a copy — `note: background session 5b7ffe74 keeps its own saved options, so the flags you passed started a copy as ea4b650c`. |
| §10-4 transcript path after a worktree move | unrun (not triggerable) | No session ever moved into a worktree. `notes.md` was written into the shared checkout by a Bash heredoc: worktree isolation gates the Write/Edit tools, not Bash. Transcript stayed at `~/.claude/projects/<dispatch-cwd-slug>/<sessionId>.jsonl`. `linkScanPath` not inspected. |
| §10-5 `claude logs` output | verified | 135,537 bytes and **zero newlines**, wall-to-wall ANSI cursor and truecolor escapes — a screen-buffer replay, not a log. Unusable as a data source. |
| §10-6 `--append-system-prompt` after restart; `-w`, `--remote-control` under `--bg` | partial | `--remote-control` **does** combine with `--bg`, but the positional prompt is discarded: the dispatch printed `backgrounded · 99be9172 · Baton trial M (idle — send a prompt to start)` and **no transcript was written at all**. `--append-system-prompt` after a supervisor restart and `-w` under `--bg`: unrun. |
| §10-7 the user record a human's typing leaves | verified, and it defeats the obvious use | A typed line in an attached session gives `origin: {"kind":"human"}`, `promptSource: "typed"`. **Baton's own `--bg --resume` text is byte-identical in those fields.** Only hook-injected text differs (`origin: null`). There is no field that separates the relay from the person. |
| §10-8 user-defined subagents in `--bg` | verified | `subagent_type: "code-reviewer"` from `~/.claude/agents/` loaded and ran in a `--bg` session, writing `subagents/agent-af4d52ef3dbdd4a29.jsonl`. Issue #58729 does not reproduce on 2.1.268. |
| 9 `hooks.Stop` via `--settings` in `--bg` | verified | The gate fired in every `--settings` session. Its `{"decision":"block","reason":…}` reached the model as a **`user` record prefixed `Stop hook feedback:`** — a user turn, not a system reminder, settling an open question in `hooks.md §5`. No `.claude/settings.local.json` fallback was needed. |
| 10 `CLAUDE_CODE_SESSION_ID` | verified | `echo $CLAUDE_CODE_SESSION_ID` inside the session printed `28926e91-26fc-4602-9abd-1ce89cefeb28`, exactly the `sessionId` in `claude agents --json`, whose `id` is its first 8 characters. |
| 11 `.tmp` then rename, seen by the hook | verified | The session wrote `…json.tmp` and `mv`d it into place; the next Stop fire recorded `artifact_seen: "yes"` for `~/.baton/inbox/T01-<sessionId>.json`. |
| 12 CLI by absolute path from launchd | verified, with a correction | launchd gives `PATH=/usr/bin:/bin:/usr/sbin:/sbin` — a *minimal* PATH, not none. `command -v claude` → not found; `/Users/danny/.local/bin/claude --version` → `2.1.268`. The absolute path is required, but for the stated reason only by accident. |
| 13 background service starts when down | verified | From the launchd job: `daemon status` before → `not running`; the dispatch printed `Starting background service…`; after → `pid 83297, uptime 0s, origin: transient — started on-demand by \`claude --bg\``. |
| 14 session outlives the tick's exit | verified | The probe exited 09:40:14. At 09:40:56 `Baton trial K` was still a live row (`pid 83310`) and had produced its output (`launchd-ok`). `AbandonProcessGroup` holds. |
| 15 Keychain readable from launchd | verified | The launchd-dispatched session authenticated and completed. No `Could not resolve authentication method`. |
| 16 ruling path with the gate re-injected | **failed as specified; works another way** | `claude stop` then `--bg --resume --settings <gate>` does **not** continue the session — it forks a copy under a new id. The session already **keeps its dispatch-time `--settings`**, so the gate survives a *flagless* resume automatically. Re-passing the settings file is exactly what breaks the id. |
| 17 `caffeinate -i -w <pid>` | verified (first half) | Started from the launchd job against the row's pid: `caffeinate -i -w 83325` ran as pid 83999 with **ppid 1**, surviving the script's exit, and `pmset -g assertions` showed its `PreventUserIdleSystemSleep` assertion named `caffeinate command-line tool`. The pid after a *supervisor* restart of the process: unrun. |
| 18 StopFailure on a rate limit | unrun | No API error occurred in any trial. `stopfailure.jsonl` was never created. Honest per the ticket's instruction. |
| 19 `statusLine` stdin in `--bg` | verified, and richer than the item asks | The command ran in every session and its stdin carried `rate_limits: {five_hour: {used_percentage, resets_at}, seven_day: {…}}` with `resets_at` as **epoch seconds** (`1789128600` → 2026-09-11T12:10:00Z). Also `session_id`, `transcript_path`, `cost`, `context_window.used_percentage`, `prompt_cache`, `model`, `version`. This is the "field later" proof, and a better watch substrate than the agents view. |
| 20 marker the pending call receives | verified, and the two cases differ | A call parked at a **permission prompt** receives **no `tool_result` at all** — the `tool_use` is left orphaned in the transcript, and on resume the model re-issued it as a new call. A call parked at **AskUserQuestion** receives `[Request interrupted by user for tool use]`. The ruling text landed as the next `user` record in both. |
| 21 AskUserQuestion park | partial | A session at AskUserQuestion shows `state: blocked, status: waiting, waitingFor: "input needed"` — distinguishable from a permission prompt in the row. A stopped one **can** be answered on resume: `--bg --resume <uuid> "alpha.txt"` landed and the session used it ("Got it. I'll use **alpha.txt**"). The supervisor's ~1 h idle stop could not be waited out: unrun. |
| 22 subagent transcript location | verified | `~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.jsonl`, beside an `agent-<id>.meta.json`. The slug is the **dispatch** cwd. Whether they move with a worktree: unrun, no worktree occurred. |
| 23 resume after a crash | verified, and the timing is the point | After `kill -9`, the row read **`state: "working"`, `pid: null`, `status: null` for at least 25 s**, flipping to `state: "failed"` between 25 s and 70 s. `claude stop` against the dead process printed plain `stopped cede40d0` — it is not a liveness test. Flagless `--bg --resume` continued under the same id. **The crash tell is `pid: null` while `state` still reads `working`.** |
| 25 `Notification` `permission_prompt` in `--bg` | fires; **content inverts the premise** | It fires. Its `message` is exactly `"Claude needs your permission"` — **no tool name, no command** — and `title` is `null`. "Where an escalation goes" recorded the message as the tool name appended to that string. It carries neither. |
| 26 **the gate**: record-only `PermissionRequest` | **passes** | The hook wrote its file and returned no decision (exit 0, no stdout). The prompt **stayed open**: the row held `waitingFor: "permission prompt"` for 2 m 50 s until it was answered in place. The documented "if no hook returns a decision, it denies the tool call" governs contexts that cannot prompt (`-p`, background subagents), not a `--bg` session that can. |
| 27 `permission_suggestions[]` | measured; **the guarantee does not hold in general** | Four shapes observed, not one. Compound commands (heredoc + `mv` + `cat`): **`[]`**. A simple command: one `addRules` whose `ruleContent` is the **literal command string** `sw_vers -productVersion`, `destination: "localSettings"` — not a `sw_vers:*` glob. `cat ~/.aws/credentials`: a rule for a **different tool** — `{toolName: "Read", ruleContent: "//Users/danny/.aws/**"}`, `destination: "session"`. A `Write` prompt: `{"type":"setMode","mode":"acceptEdits"}` and `{"type":"addDirectories","directories":["/Users/danny/.baton/inbox"]}` — a mode change and a directory grant, **not rules at all**. `baton allow` cannot append a suggestion blindly. |
| 28 `PermissionDenied` reason forms | **unrunnable in `--bg`** | The hook never fired; `permissiondenied.jsonl` was never created across fifteen sessions. It is auto-mode-only and auto mode is unreachable in `--bg` (see below). Recorded for the record, from an interactive session: the reason a denial delivers to the model reads `Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Credential Materialization].` The context-window and "temporarily unavailable" forms cannot be forced: unrun. |
| 29 classifier routing to a held prompt | **unrunnable as posed** | Requires auto mode. What is established instead: a `--bg` session runs in `default`, where every call not covered by an allow rule holds a prompt with no `ask` rule present. The auto-mode circuit-breaker string never appeared. |
| 30 `allow`/`deny` from `--settings` bite in `--bg` | verified, all three | Listed `Bash(xcodebuild:*)` ran with no prompt (`Xcode 27.0`). Unlisted `sw_vers -productVersion` prompted. `Bash(sudo:*)` was refused: `Permission to use Bash with command sudo -n true has been denied.` The permission **rules** travel through `--settings`; the permission **mode** does not. |
| 31 `Bash(osascript * administrator privileges*)` | verified — **it matches** | With the phrase inside a quoted `-e` argument the rule still bit: `Permission to use Bash with command osascript -e 'do shell script "true" with administrator privileges' has been denied.` Refused outright, no prompt. The feared silent failure does not occur, and the line is not carried by the target's hard rules alone. |
| 32 `osascript` → Messages from launchd | verified | The AppleScript `participant` form succeeded from the launchd job: `SENT: participant form succeeded`, exit code 0, and the message arrived. **No TCC Automation dialog appeared** — the grant was already in place for `osascript` on this Mac. The escalation channel's floor holds from a launchd context. |
| 34 row transition on answering in place | verified | **≤1 second.** The row lost `status: waiting` and `waitingFor` within one 1 s poll of the answer, twice (09:08:09→09:08:10, 09:08:34→09:08:35). Ample margin for a 60 s tick. |
| 35 `baton allow --resume` end to end | verified, via the corrected mechanism | `claude stop` at a live prompt; **edit the `--settings` file in place**; flagless `--bg --resume` with the ruling. The re-issued `sw_vers -productVersion` then ran with **no prompt** (`27.0`), and `sudo -n true` was still refused by the unchanged deny line. |
| `--remote-control` + `--bg` (`reaching-you.md §5.1`) | verified | They combine, but the session starts idle and **discards the positional prompt**; no transcript is written. Work cannot be dispatched and remote-controlled in one command. Separately: Remote Control is eligible on this Mac once `DISABLE_TELEMETRY` is unset — `claude doctor` in a clean environment reports "Control this session from claude.ai/code or the Claude mobile app". The sibling vars still exported at `~/.zshrc:11-12` (`CLAUDE_TELEMETRY_DISABLED`, `ANTHROPIC_TELEMETRY_DISABLED`) do not block it; only `DISABLE_TELEMETRY` does, and any process started before that line was commented out still carries it. |
| `idle_prompt` in a detached `--bg` session (`hooks.md §5`) | verified | Fires. `notification_type: "idle_prompt"`, `message: "Claude is waiting for your input"`, at 09:09:49 against a 09:08:49 response — the documented ~60 s. |
| 24 wake from sleep: how long the row is absent or failed | verified — **no margin needed** | A real 55 s suspend (poll gap 09:46:05 → 09:47:00, lid closed). The row either side was **identical**: `state: "working", status: "busy", pid: 84684`. Sleep leaves no trace in the row at all: it can never be mistaken for a crash. |
| 33 iOS alert for a self-sent iMessage | **verified negative** | The message arrives in the Messages thread on the iPhone but the phone **raises no alert** — no banner, no sound — on three sends, including one that fired as the Mac woke. Only the Mac notifies. The ticket's named fallback exists: Mail has a configured sending account (`iCloud`, `scalinity.ai@icloud.com`) reachable through `osascript`. Whether *that* alerts the phone is not yet observed. |

#### The finding that is not on the list

**A `--bg` session cannot run in `auto` permission mode.** `--permission-mode auto` is a documented choice, is accepted without error or warning, and the session then records `permissionMode: "default"`. Established three ways: with a `--settings` file whose `permissions.defaultMode` is also `auto`; with no settings file at all; and against `acceptEdits` and `dontAsk`, which are honoured and record correctly under the identical command. It is a silent downgrade, not an ignored flag.

Everything in "Where an escalation goes" that rests on the classifier follows it down. `PermissionDenied` is auto-mode-only, so it never fires for a dispatched session — `permissiondenied.jsonl` was never created across fifteen sessions. The "long tail of refusals, observable because every classifier refusal is logged" has no mechanism in `--bg`.

The full mode table, all observed:

| `--permission-mode` under `--bg` | honoured | an uncovered call | `deny` rules | `PermissionRequest` fires | parks |
|---|---|---|---|---|---|
| `auto` | **no — records `default`** | — | — | — | — |
| `default` | yes | holds a prompt | enforced | **yes**, with `tool_input` | **yes** |
| `acceptEdits` | yes | holds a prompt (Bash) | enforced | yes | yes |
| `dontAsk` | yes | denied silently | enforced | **no** | no |
| `bypassPermissions` | yes, after a one-time interactive disclaimer | **runs** | **enforced** | no | no |

`bypassPermissions` is refused outright until the disclaimer is accepted — `--bg with bypassPermissions requires accepting the disclaimer first. Run \`claude --dangerously-skip-permissions\` once interactively.` — and works once it has been. Its deny rules still bite: under `bypassPermissions`, `uname -a` ran while `sudo -n true` was refused by the same `--settings` file.

The choice for unattended dispatch is therefore between parking and seeing, or running on and not seeing. Nothing offers both. **`bypassPermissions` plus the deny list is the chosen path**, because a night that parks on its first uncovered command has not run at all, and the deny list is enforced regardless of mode. The cost is stated plainly: with nothing prompting, `PermissionRequest` and `Notification` never fire, so Baton records no permission events and the escalation channel carries only *endings*. Item 26's recorder, which passes, is therefore moot for unattended runs and matters only if a dispatch chooses `default`.

#### What a launchd context cannot do

The relay is a launchd job, and two of the five inputs the tick reconciles from are unreachable from one.

A launchd job cannot execute a script stored under `~/Documents` at all: the first probe died with `/bin/sh: …/launchd-probe.sh: Operation not permitted`, exit 126. Moved to `~/.baton`, it ran. From there, under `~/Documents`:

- `ls` a directory — **Operation not permitted**
- `cat` a file — **Operation not permitted**
- `test -r` the same file — **YES**
- `stat` the same file — **129 bytes**
- `git -C … status` / `log` — **fatal: Unable to read current working directory: Operation not permitted**
- `touch` a new file — **OK**

Metadata succeeds while content reads fail, so a readability guard passes and the read that follows it fails. Git does not work. The `claude` binary is unaffected — it dispatched, worked in that directory and completed — because TCC grants attach per executable.

So the tick cannot read a target project's plan file and cannot run its git check, while `claude` can. Either the relay's executable is granted Full Disk Access (which argues for the Swift binary the Relay decision already permits, granted specifically, rather than granting `/bin/sh`), or those two inputs move out of `~/Documents`.

Two smaller launchd facts: the job gets `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, a minimal PATH rather than none, which still excludes `claude`; and it gets **no `LANG`**, so in the C locale a regex `.` matches one byte of the two-byte `·` in `backgrounded · <id>`. A parser that works in a terminal silently fails under launchd. Baton must set `LC_ALL` or match bytes.

And timers do not run through sleep: a `sleep 75` armed at 09:53:19 fired at 09:55:51, 77 s late, because the Mac slept. `caffeinate -i` does not prevent lid-close sleep. A fixed-duration wait stretches by the sleep.

#### The watching-and-intervening design

**The agents view is enough; no tab per session.** `claude agents --json` carries what Baton needs to decide — `state`, `status`, `waitingFor`, `pid` — and `claude logs` carries nothing usable (135 KB, no newlines, pure escape sequences). What the row cannot give a *person* is what is being asked, and the answer to that is not a terminal tab: **`Claude.app` lists background sessions, shows the whole conversation, renders hook events as their own entries ("Hook re-prompted Claude"), names the mode and model, and has an input box that answers a prompt in place.** It is the better window, it costs nothing to open, and Baton opens nothing. `claude attach <id>` stays available for when a terminal is already in hand; `←` returns to the agent view and Ctrl+Z drops to the shell, both confirmed. Terminal-emulator automation stays out of scope: a tab per session is machinery Baton would then have to close.

Answering in place needs no relay involvement: the row loses `status: waiting` and `waitingFor` **within one second**, so the next tick sees a live lane with no state to reconcile.

**The session's name is `Baton · <project> · <milestone>`.** The name is the only field that marks ownership: `kind: "background"` does not distinguish Baton's sessions from ones a person backgrounded, and this session's own safety rule — touch only rows whose name begins with `Baton trial` — is the evidence that a fixed prefix is load-bearing. The project belongs in it because the name is what a person reads in Claude.app's sidebar and in `--resume`, where `cwd` is not shown. The model does **not** belong in it: it is restored automatically on resume, it is visible in Claude.app, and the statusLine payload reports it per session, so putting it in the name would only mean rewriting the name whenever the model changes. The attempt number stays in the slot line, as already decided; `startedAt` separates two rows for one milestone.

**A human's takeover shows in exactly one place, and not the one expected.** There is no field: a line typed into an attached session and a line delivered by Baton's own `--bg --resume` are both `origin: {"kind":"human"}, promptSource: "typed"`. Only hook-injected text differs (`origin: null`). The discriminator has to be knowledge, not observation — **a `user` record with `promptSource: "typed"` that Baton did not itself send is a person**, and Baton can tell because it is the dispatch log's only writer and knows every prompt it delivered, with its text and its time. When it finds one, it stops acting on that lane until the row goes idle *and* a handover artifact appears; it never re-prompts over a person. This resolves the map's "Knowing a human took over".

**Rulings are delivered flagless.** `claude stop <id>`, then `claude --bg --resume <uuid> "<ruling>"` with **no flags at all**. The session restores `-n`, `--settings`, `--model` and `--permission-mode` by itself and says so. Passing `--settings` to re-inject the gate is precisely what forks a copy under a new id and loses the lane. To widen an allowlist, Baton **edits the settings file in place** at the path it dispatched with; the running session picks it up, and the re-issued command then passes. That is `baton allow --resume`, and it is simpler than the mechanism the closed decision assumed.

**A dropped call is detectable.** A tool call parked at a permission prompt when `claude stop` arrives receives no `tool_result` at all — an orphaned `tool_use` in the transcript. That orphan is the signature the prompt-lost rule keys on; an AskUserQuestion call instead receives `[Request interrupted by user for tool use]`, and a stopped one can be answered on resume, so the rule fires only for the permission case.

**Crash, sleep and stall are separable.** A crash shows `pid: null` while `state` still reads `working`, for up to about a minute before it becomes `failed`; a sleep changes nothing in the row at all. So `pid: null` alone is decisive and the two-tick confirmation is not needed to tell them apart — it is needed only against a momentary read. `claude stop` against a dead process prints an ordinary `stopped <id>`, so it is never a liveness test.

**The statusLine is the watch substrate, not the agents view.** Passed in the same `--settings` file, its command runs in every `--bg` session and receives, per turn, `rate_limits.five_hour.{used_percentage,resets_at}` and the same for `seven_day` with `resets_at` in epoch seconds, plus `context_window.used_percentage`, `cost`, `model`, `transcript_path` and `session_id`. Writing that to `~/.baton/status/<sessionId>.json` gives Baton a per-session feed containing every number the agents view lacks — which is where the usage-limit wait gets its reset time, and where a context-exhaustion warning would come from. Hooks should write **per-session files**: concurrent appends from several sessions into one file interleaved during this run.

**The Stop gate must not fire into a running subagent.** The gate's payload carries `background_tasks[]`, and a session that ended a turn only because a subagent was still working was blocked by the gate and complied — writing a handover artifact that recorded the milestone as `in-progress` with step one still `pending`. It never corrected it. The gate must let the stop through when `background_tasks` is non-empty, or it manufactures false handovers.

#### Where a closed decision now has to change

1. **Where an escalation goes** — `auto` is unreachable in `--bg`, so the mode half of "`auto` plus a per-project allowlist, both in the `--settings` file" cannot be delivered. `PermissionDenied` never fires. The `Notification` message is `"Claude needs your permission"` with no tool name and no title, so the documented fallback recorder is emptier than recorded. `permission_suggestions[]` comes in four shapes — absent, a literal-command rule, a rule for a different tool, and `setMode`/`addDirectories` entries that are not rules — so `baton allow` must discriminate rather than write verbatim. The escalation channel does not reach the phone: a self-sent iMessage never alerts iOS.
2. **Relay or conductor** — a launchd-run tick cannot read the plan file or run the git check while they live under `~/Documents`.
3. **What stops a session** — the crash rule should key on `pid: null`, not `state: failed`, which arrives up to ~70 s late; the ruling delivery must be flagless or it forks the lane; and a fixed-duration wait stretches by any sleep.
4. **What a project hands to Baton** — the Stop gate must stand down while `background_tasks` is non-empty.

#### Addendum, same day: Remote Control is a two-way channel

Run after the table, because item 33 resolved negative and left the escalation channel with no way
to reach the phone. It has one.

- **Dispatch is two steps.** `claude --bg --remote-control -n "<name>"` starts the session **idle**
  and discards any positional prompt, writing no transcript at all. Work is delivered by
  `claude stop <id>` followed by a **flagless** `claude --bg --resume <uuid> "<work>"`, which wakes
  it under the same id and names `--remote-control` among the restored saved options. A flagless
  resume against the *live* idle session instead forks a copy, so the stop is required.
- **The phone is pushed, and can answer.** With the session parked on `AskUserQuestion`, the Claude
  mobile app raised a notification for the question itself — confirmed twice, the second time with
  the session-ready ping deliberately excluded by re-prompting the same session. Both questions were
  answered from the phone and the session carried on ("Got it! I'll use **alpha.txt**", then
  "Perfect! I'll create **alpha.txt** with a newline at the end").
- **Answering from the phone clears the row in ≤1 s** — `blocked/waiting` at 10:09:51 to
  `working/busy` at 10:09:52 — the same margin as answering in an attached terminal.
- **The row cannot be trusted to show the park.** On the first question the row read
  `blocked/waiting, waitingFor: "input needed"`. On the second, it read
  `state: "working", status: "idle", waitingFor: null` **for the entire time the session was parked
  and the phone was being pushed**. A remote-controlled session also stays at `state: "working"`
  rather than reaching `done`. So for these sessions the row is not a reliable park detector; the
  `Notification` hook and the transcript are.

This makes Remote Control the only channel where the phone both hears an escalation and resolves it,
which no SMS or mail route can. Its costs are unchanged and still real: it needs the two-step
dispatch, `DISABLE_TELEMETRY` unset in the launching environment, and it stores the session on
Anthropic's servers — so it belongs to a per-dispatch opt-in, as "Where an escalation goes" already
decided, not to every session by default.

### Added by "Dispatching more than one at once" (2026-09-11)

Nine live items, numbered after the last, none observed yet. Item 38 gates the first unattended
night: it is the fact the `~/Documents` decision rests on and the prototype's own launchd run did
not test (run C started the daemon itself and its session read no file).

(36) The Full Disk Access panel accepts `/Users/danny/.baton/bin/sh` (a copy of `/bin/sh`), and a
launchd job whose executable is that copy can `cat` a file and run `git -C … rev-parse HEAD` under
`~/Documents/Apps/…`, while the same job run with `/bin/sh` still fails with `Operation not permitted`.
(37) Children of the granted shell — `git`, `jq`, `/Users/danny/.local/bin/claude` — inherit the grant
(TCC's responsible-process attribution). (38) **A background service started by the tick itself**
(`daemon status` reads `not running` before the dispatch) runs sessions that can read `~/Documents`:
a dispatched session `cat`s a file inside the project and reports its content. If it cannot, either
grant the `claude` binary too (its path is per version and the grant is renewed on update) or never
start the daemon from the tick and treat "service down" as a project-scope escalation. (39) `--settings`
and `--model` given at an idle `--remote-control` start are restored by the flagless
`--bg --resume` that delivers the prompt, as `--remote-control` and `-n` were seen to be; if not,
whether Remote Control survives a resume that passes `--settings`. (40) `remoteControlAtStartup:
true` in a `--settings` file starts Remote Control on a `--bg` session, and a session started that
way with a positional prompt keeps the prompt — if both, `Remote: yes` becomes one command. (41) A
session dispatched with `cwd` inside a linked worktree (`../<Project>-M<nn>`, made by `git worktree
add`) receives no worktree-isolation instruction and edits in place; the transcript slug is the
worktree path. (42) What a `permissions.ask` rule does under `bypassPermissions` — auto-allow or
auto-deny; until known, no `ask` rules are written. (43) `--effort` is restored by a flagless resume
as `--model` is (`respawnFlags`). (44) A `--bg` dispatch naming a model the account refuses: the row
is created, StopFailure fires at the first request with `error: model_not_found`, and the `api-error`
artifact lands in the inbox.

### Amended by "The dispatch log" (2026-09-11)

Not reopened. The takeover discriminator this ticket found is now a rule, and writing it as one
exposed a bug in the form it was recorded in, plus three transcript facts it rests on.

1. **The rule is a comparison against the newest typed record, not a scan of all of them.** As
   written — "a `user` record with `promptSource: "typed"` that Baton did not itself send is a
   person" — the condition is set membership over the whole transcript, and a transcript only ever
   grows: a line the person typed on Tuesday stays unmatched forever, so the lane could never be
   handed back. The rule is therefore **a lane is taken over exactly while the transcript's newest
   typed record is one Baton did not send.** That form self-releases, which is what makes
   `baton answer <milestone> "continue"` the hand-back: it writes a `resume` event and delivers a
   prompt Baton *did* send, which becomes the newest typed record. The scan of every record survives
   only as what fills the event's `typed_count`.
2. **The match runs across the whole milestone, not this session.** Verified here, from the same
   trial project: **a forked copy's transcript is a byte-for-byte copy of its parent's, with every
   record rewritten to the new `sessionId`** — `ea4b650c-…jsonl` contains the prompt Baton delivered
   to session `5b7ffe74` at 09:14:43, stamped `sessionId: ea4b650c`, and its first record is a
   `custom-title`. A per-session match would therefore report a false takeover across the entire
   inherited history on every copy fork, which §10-3's flag rule makes a routine event. A transcript
   only ever holds its own lineage and a lineage is one milestone, so the candidate set is every
   `dispatch` and `resume` for that `(project, milestone)`.
3. **Which records the scan admits**, from the peer session "Milestone Model Audit" [B, D, L]:
   `type == "user"` and `promptSource == "typed"` and neither `isMeta` nor `isCompactSummary` true —
   the filter the CLI's own reader applies. **Compaction appends and never rewrites or truncates**
   (measured: 97 typed records survive a boundary two hours later; a `type: "system", subtype:
   "compact_boundary"` record marks where the summary takes over), so every typed record ever
   written is still in the file. **`.orphaned-<ts>-<hash>.jsonl` is a set-aside copy from a wake
   whose transcript probe misread the file** — "the file is now set aside, never deleted" — not a
   compaction product; the glob takes the un-suffixed file, and a lane with only the sibling
   escalates rather than being scanned. **`cleanupPeriodDays` defaults to 30 days** and sweeps
   transcripts among other things, while this Mac sets `3650`; since "a transcript exists" is the
   resume-versus-redispatch test, that is a setup fact in Baton's plan.
4. **A takeover is not a park**, and it ends two ways: the row goes idle and a handover artifact for
   the milestone has been consumed, or a `resume` makes Baton's prompt the newest typed record. The
   `takeover` event restarts the six-hour long-running clock, so an abandoned lane notifies once on
   the Mac; `status` prints the hand-back on the lane's own line.

Three live items, numbered after the last:

(45) **The hash normalisation.** Take a prompt Baton wrote to `~/.baton/prompts/<session>/<n>.txt`
and the `user` record it produced, and confirm the two hash equal under the normalisation M01
chooses — a trailing newline, a `\r\n`, or a stripped leading blank line handled differently on the
two sides makes every one of Baton's own dispatches read as a takeover on the first night. This one
is **offline**: the prototype's captured pairs under `obs/` and the trial project's transcripts are
enough, and it can be done at any time. The takeover rule is not trusted until it passes.
(46) **What `claude --bg --resume` prints when it forks a copy**, byte for byte, under `LC_ALL` — the
`copy_fork` event's new `session` is parsed from that `note:` line, and the `·` separator is two
bytes in a locale launchd does not set.
(47) **What a failed `claude --bg` prints, and on which stream**, for each way step 8 of the dispatch
algorithm can fail before a session id exists, so `dispatch_failed`'s `stage` and `detail` are filled
from what the CLI says rather than guessed.
