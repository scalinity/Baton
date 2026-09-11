Title: Relay or conductor
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: —

## Question

Is Baton a **relay** — deterministic: hooks and a launchd agent detect a handover and run
`claude --bg -n <name> --model <m> "<prompt>"`, nothing more — a **conductor** — a
long-lived Claude session that reads transcripts, decides what an idle session means,
answers a worker's question from the target's `docs/` and escalates only what is the human's
— or a **hybrid**: deterministic mechanics, with a model consulted only at judgement points
through a bounded `claude -p` call?

The judgement points, enumerated so the choice is made against them rather than in the
abstract:

1. **An idle session.** `claude agents --json` carries `state` (working, blocked, done,
   failed, stopped), `status` (busy, waiting, idle) and `waitingFor`: a permission prompt is
   `status: waiting` with `waitingFor: "permission prompt"`, a question is `waitingFor:
   "input needed"`, and a usage-limit stop maps to `state: blocked` (its live `status` is
   unverified) — so those three are told apart without opening a transcript
   (`.scratch/baton/research/background-sessions.md` §3, §7). What the fields cannot tell
   apart is the idle that matters most: a session that printed its handover and one that
   stopped without it are both `idle`. That one needs the handover artifact, the Stop hook's
   `last_assistant_message` (`.scratch/baton/research/hooks.md`), or a reading of prose.
2. **A question.** The kickoff prompt's part 4 ("settle rather than inherit") already pushes
   decisions into the session with their evidence, so questions should be rare. When one
   comes: is its answer in `docs/`, or is it a scope call that is the human's (the three
   open on M28 are that kind)?
3. **A cut-off session.** Resume it under the same id (`--bg --resume`, context intact) or
   dispatch the milestone afresh and let the prompt's recovery clause resume from the
   brief's Completion evidence?
4. **A Fable limit.** Wait for the reset, or dispatch Opus with a record?

Costs to weigh: a conductor session polling all night spends quota and context on nothing;
a `claude -p --model haiku` at each event costs almost nothing and holds no state; hooks
fire only when something happens. The stated ambition is the one Boris Cherny describes —
Claude orchestrating itself — which argues for judgement somewhere in the loop, not for a
session that sits awake.

The choice fixes three fogged areas at once: what state Baton keeps, how it stays alive,
and how it is tested. Decide, and graduate those.

## Comments

### Resolution — 2026-09-11

**Decided: relay.** Baton is deterministic code that runs once per tick, reads the inbox, the plan
file, its own dispatch log and `claude agents --json`, makes one git check, dispatches and escalates,
and decides nothing a session or a person should. The rule is one of placement, not of ceiling:
**Baton embeds no model call. Judgement is dispatched as a session and returns as an artifact; it is
never made inline in the tick.** A session is a model call with the whole project in context, a
transcript a person can attach to, the Stop gate, and an artifact at the end, so anything that needs
judgement later — a morning summary of the night, re-allocating models after a milestone lands, a fix
when main breaks after two lanes merge — is dispatched, not computed in the relay. That rule is ADR
0001 (`docs/adr/0001-baton-never-calls-a-model.md`), with its reversal condition: if the dispatch log
shows the same judgement point recurring — one a session cannot pre-decide and a person tires of
answering — that is the named moment for a bounded model call inline in the tick, and it gets its own
ticket then. Sessions decide at both ends — the kickoff prompt's part 4 pre-authorises rulings on the
way in, the handover's dispositions carry the session's judgement on the way out — and the person
answers everything a session still asks, by any means they choose; "Where an escalation goes" decides
the channel.

#### 1. What judgement was left, and why none of it is a model's

| Point | Status | Why |
|---|---|---|
| 1. An idle session | Retired by the contract | A dispatched session always ends with an artifact in `~/.baton/inbox`: `complete`, `asking`, `stopped`, or the `no-handover` artifact the Stop gate writes on the second stop. The relay reads a file, never a session. |
| 4. A Fable limit | Retired by policy | The plan holds the allocation and a Fable milestone is never downgraded silently (map Notes). A Fable limit means wait. |
| 2. A question | Decided here: always the person's | The session that asked had the whole project in context and a part 4 telling it to settle rather than inherit. A question it still asked is not one a smaller call with less context answers better; "rulings, not stalls" (prior-art §2.3) puts the ruling inside the session before the question, not in Baton after it. The list of what is the person's lives in part 4 of the prompt, not in Baton. |
| 3. A cut-off session | Decided here: a rule, not a judgement | Resume under the same id or redispatch through the recovery clause is a fixed rule over fixed inputs (a transcript on disk, a process gone, an attempt count). "What stops a session, and what happens next" writes the rule. |

Plan-versus-advice disagreement escalates by rule in both directions (contract, Baton's side).
Nothing remains that a bounded model call inline in the tick would decide better than a rule, a
dispatched session or the person, so the hybrid has no event to serve today; the reversal condition
above names the moment it would.

#### 2. What survives of "Claude orchestrating itself"

The judgement is at both ends of every session, not in a session that sits awake. Going in: part 4
of the kickoff prompt carries the decisions the session is to settle, with their evidence. Coming
out: the handover's `eligible[]` with a disposition per milestone is the finishing session's
conflict check and sequencing call — the next dispatch, written by Claude. Baton executes that call
against the plan file and escalates disagreement. What does not survive is the seat: every design
that put a Claude session in the orchestrator's seat reports needing nudges, waiting for input and
misreporting state (prior-art §2.1 pattern 1: Gas Town's Mayor, Tmux-Orchestrator's PM, twaldin's
persistent orchestrator; §2.2 "waiting for input that never comes"), and every unattended loop that
works is deterministic code around a fresh-context session leaving a structured artefact (§2.1
patterns 1–3; Symphony's tick, Carlini's loop, Anthropic's driver script, §2.3).

#### 3. Session-to-session messaging: considered, unused

Sessions on this Mac can message each other by name (the ListAgents and SendMessage tools; the
research agents reported that way, and the peer session answered this ticket's technical question
that way). A conductor could nudge a worker and a worker could report without parsing terminal
output. It needs a live session at both ends, and the relay is alive only for the length of a tick,
so v1 does not use it. The deterministic route for text into a session is `claude stop <id>` then
`claude --bg --resume <uuid> "<text>"` (background-sessions §5). Recorded so it is not rediscovered;
it returns only if a later design keeps a session alive.

#### 4. How Baton stays alive — decided

- **One launchd agent, `StartInterval` 60 s**, runs one short script — the tick — which exits.
  Hooks fire only inside a running session (hooks.md §4.5), so nothing session-side can wake Baton
  after a usage-limit wait, a sleep or a crash; something outside sessions must own time. Prior art:
  `/loop` is session-scoped and expires in seven days, desktop scheduled tasks skip while the Mac
  sleeps, routines are hosted, launchd is the only option no source caveats (prior-art §2.2
  "schedulers that silently stop", §2.3). `man launchd.plist` on this Mac: `StartInterval` "causes
  the job to be started every N seconds"; a firing during sleep or while the job still runs is
  missed and the next one catches up, which costs nothing because the tick reconciles from
  scratch. `WatchPaths` is rejected by the manual's own words ("highly discouraged … race-prone …
  modifications … missed"); `QueueDirectories` (the spool pattern) is not needed at a minute's
  latency against milestones of hours. Precedent on this Mac:
  `~/Library/LaunchAgents/com.danny.ccstats-backup.plist` and `-ingest.plist`, both `/bin/sh`
  scripts on a calendar interval.
- **The tick remembers nothing.** Every run reconciles from five inputs: the dispatch log,
  `claude agents --json`, the inbox, the plan file and one git check (that a `complete` handover's
  `merged_as` is an ancestor of main). Recovery after a sleep, a restart or a killed process is
  therefore the normal path, and "tick twice, nothing changes" is its test.
- **An atomic `mkdir` lock** serialises a launchd firing against a hand run; `tick`, `answer` and
  `status` are verbs of the same script.
- **caffeinate.** An unattended night needs an awake Mac: a dispatched session pauses while the Mac
  sleeps and reconnects on wake (background-sessions §9), and this MacBook Pro's idle sleep is one
  minute (`pmset -g`). Each dispatch starts `caffeinate -i -w <pid>` against the session's pid from
  `claude agents --json`; each timed wait starts `caffeinate -i -t <seconds>` for its length
  (`man caffeinate`: `-i` prevents idle sleep, `-w` releases when the pid exits, `-t` drops after
  the timeout). Both start detached, with `AbandonProcessGroup` true in the plist
  (`man launchd.plist`: otherwise "when a job dies, launchd kills any remaining processes with the
  same process group ID"), so the holder outlives the tick. Lid open or clamshell (power plus an
  external display) is a hardware condition the plan states; Baton cannot lift it.
- **The API-error wait** is a fixed-interval retry unless the reset time turns out to be a field
  the tick can read, in which case the wait runs to it; the `caffeinate -i -t` duration follows
  whichever "What stops a session, and what happens next" decides, and that ticket names the
  interval and the field. The docs put the reset time in message text (`You've hit your session
  limit · resets 3:45pm`, varying by limit; background-sessions §7, "match on the structure, not
  the text"), StopFailure carries `error` and an optional `error_details` (hooks.md §3), and the
  auto-wait is not offered in background sessions (§7), so Baton owns the wait.

#### 5. Testing without quota — decided

- **One seam per outside thing**: the claude binary, the clock and caffeinate are each reached
  through one variable (defaults `/Users/danny/.local/bin/claude`, `date`, `/usr/bin/caffeinate`),
  and a test points each at a shim. The claude shim plays the roles the tick sees: `--bg` prints
  `backgrounded · <id>` and later writes an inbox artifact; `agents --json` answers from a fixture
  state file; `stop` and `--bg --resume` record what they were asked. Precedent: key-free mock
  agents and `--dry-run` runners (prior-art §2.3).
- **The Stop gate is tested by piping it fixture hook payloads** on stdin (the documented Stop
  input: `session_id`, `stop_hook_active`, `last_assistant_message`; hooks.md §4.1), asserting on
  the artifact it writes and the JSON it prints.
- **Scenarios are fixture directories** — a throwaway target project as a git repo with a plan
  file and briefs, an inbox, a log — and the assertion is a diff of the directory after the tick
  against the expected one. **Idempotence is the recovery test**: tick twice on the same fixture
  and the second tick changes nothing.
- **launchd stays out of the tests**; the tick is invoked directly under the same lock.
- **Rejected**: replayed transcripts, because under the contract the tick parses no transcript (the
  Stop gate's `last_assistant_message` fallback is a hook input, covered above); a `-p` fixture,
  because `--bg` cannot combine with `-p` (background-sessions §2), so it exercises a different path
  and spends quota on every run. The one live proof — that the injected gate fires inside a `--bg`
  session — stays with "Watching a dispatched session", once.

#### 6. Language and the log's writer — decided

- **Shell.** `/bin/sh` with `set -eu`, `jq -e` (jq 1.7.1 at `/usr/bin/jq`), `awk` for the slot
  line, git and claude. The runtime is what ships with the Mac plus claude; no packages. launchd
  runs a script as it runs the two ccstats agents; the Stop gate is a hook that must start in
  milliseconds and is shell whatever the tick is, so one language covers both; no build step, so
  Baton's own milestone sessions never compile; tests are scripts over fixtures, which is the whole
  of what a relay does. `shellcheck` is optional, for the moment a script grows past what a read
  catches. **Reversal condition, recorded**: a structure jq cannot express, or a script past a few
  hundred lines, means a Swift command-line tool. Node is present (v26.7) and has no named moment.
  No language ticket is needed.
- **The tick is the dispatch log's only writer**, under the lock, append-only JSONL. The verbs are
  `tick`, `answer` (deliver a ruling) and `status` (the reconcile with no side effects). The Stop
  gate writes artifacts to the inbox and never the log; the tick logs what it consumes, dispatches,
  resumes, rejects and escalates. The log is the record, so a rejection needs no sidecar: the file
  goes to `~/.baton/rejected/` and its reason is a log event. No rotation until a size is felt.

#### 7. A ruling's delivery

On consuming an `asking` artifact the tick runs `claude stop <id>` at once, so the later resume
continues under the same id instead of forking a copy (background-sessions §5: an idle-but-alive
session counts as running). When the person answers, `answer` resumes the session with
`claude --bg --resume <uuid> --settings <gate> "<ruling>"`: the ruling verbatim, labelled as a
ruling so the session treats it as decided, the Stop gate re-injected. An escalation never times
out into a decision; the lane stays parked. The channel, the record and the lane semantics are
"Where an escalation goes".

#### Evidence

- `.scratch/baton/research/prior-art.md` §1.13 (Symphony), §2.1 (patterns 1–4, 6, 8), §2.2
  (waiting for input; schedulers that silently stop), §2.3 (Relay or conductor; testing).
- `.scratch/baton/research/hooks.md` §3 (Stop, StopFailure, Notification rows), §4.1 (Stop payload
  and block semantics), §4.5 (hooks in `-p` and `--bg`), §4.6 (`--settings` injection).
- `.scratch/baton/research/background-sessions.md` §2 (`--bg` and `-p`), §3 (`claude agents
  --json`), §5 (`--bg --resume` and the copy rule), §7 (usage-limit record, the auto-wait), §9
  (supervisor lifecycle, sleep, credentials).
- `man launchd.plist` on this Mac: `StartInterval`, `WatchPaths`, `QueueDirectories`,
  `AbandonProcessGroup`, `EnvironmentVariables`; `man caffeinate`: `-i`, `-w`, `-t`; `pmset -g`:
  `sleep 1`; `system_profiler SPHardwareDataType`: MacBook Pro, M5 Pro.
- `~/Library/LaunchAgents/com.danny.ccstats-backup.plist`, `com.danny.ccstats-ingest.plist`:
  `/bin/sh` scripts on `StartCalendarInterval`.
- `claude --help` (2.1.268): `--settings`, `--bg`, `-p` with `--max-budget-usd` and
  `--output-format`, `--restricted`.
- Peer session "Milestone Model Audit", asked whether `claude --bg` started from inside another
  session's hook runs independently: not documented either way; the CLI exports `CLAUDECODE=1` and
  `CLAUDE_CODE_CHILD_SESSION=1` into children, so the design that does not depend on the answer —
  the hook writes a file, the dispatch happens outside any session — is the one taken.

#### Unverified

- Dispatched sessions belong to the supervisor, so from a launchd context it is unverified that
  the CLI is reached by absolute path, that the background service starts when it is down, that
  the session outlives the tick's exit, and that the Keychain is readable — "Watching a dispatched
  session", items 12–15; the ruling's resume and the caffeinate pid are its items 16–17.
- Whether StopFailure's `error_details` or the transcript's `errorDetails` carries a reset time as
  a field; the docs place it in message text only.
- That `--settings` combines with `--bg --resume` to re-inject the gate (flags are given anew on an
  explicit resume; §9's persistence facts cover supervisor restarts only).
- The pid `caffeinate -w` holds after the supervisor restarts a session's process (new pid; the
  tick re-arms on its next run because it remembers nothing).

#### Deferred, and to which ticket

- The retry interval, the reset-time field, the resume-versus-redispatch rule and each `stopped`
  reason's handling: "What stops a session, and what happens next".
- The escalation record, the channel, the lane pause and the `answer` verb's input: "Where an
  escalation goes" (now carrying "Permissions for a session nobody is watching").
- The plan file's shape and the tick's reading of it at dispatch: "Dispatching more than one at
  once" (now carrying "Which model runs which milestone, machine-readably").
- The log's events, key and the idempotence test in detail: "The dispatch log".
- Live proofs: "Watching a dispatched session".
- The plist, the seams' names and the first tick: "Baton's plan and its M01 prompt".
- The fogged "Quota across a night" (when Fable dispatch stops for the night and whether Opus lanes
  carry on): moved into "Dispatching more than one at once", under its policy.

### Observed against by "Watching a dispatched session" (2026-09-11)

Not reopened. The launchd context is narrower than this decision assumes.

A LaunchAgent **cannot execute a script stored under `~/Documents`** (`Operation not permitted`,
exit 126); moved to `~/.baton` it ran. From there, under `~/Documents`: `ls` and `cat` fail with
`Operation not permitted`, `git -C … status` fails with `Unable to read current working
directory`, while `test -r` and `stat` **succeed** and `touch` succeeds. Metadata passes and
content reads fail, so a readability guard passes and the read behind it does not.

So of the five inputs the tick reconciles from, **the plan file cannot be read and the git check
cannot be run** while they live in a target project under `~/Documents`. The `claude` binary is
unaffected (it dispatched, worked there and completed) because TCC grants attach per executable —
which argues for granting Full Disk Access to a specific Swift binary, already permitted here,
rather than to `/bin/sh`.

Two smaller corrections: launchd gives `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, a minimal PATH rather
than none, still without `claude`; and it gives **no `LANG`**, so in the C locale a regex `.` fails
to match the two-byte `·` in `backgrounded · <id>` — a parser that works in a terminal fails
silently under launchd.

`caffeinate -i -w <pid>` holds (pid reparented to 1, real `PreventUserIdleSystemSleep` assertion,
surviving the script's exit under `AbandonProcessGroup`), and the dispatched session outlives the
tick. But `caffeinate -i` does not prevent lid-close sleep, and **timers do not run through sleep**:
a `sleep 75` fired 77 s late across a suspend.
