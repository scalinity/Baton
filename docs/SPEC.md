# Baton: specification

Baton carries a build from one Claude Code session to the next. This document holds its
requirements as `REQ-*` entries in families, each citing the wayfinder ticket that decided it (the
tickets live under `.scratch/baton/issues/`; the map's "Decisions so far" is the index). It
consolidates; it invents nothing. Specs state the current design only; `docs/DECISIONS.md` holds
the history. The vocabulary is `CONTEXT.md`.

---

## 1. Product definition

### 1.1 User and problem

One person, one Mac, Claude Code 2.1.270 at `/Users/danny/.local/bin/claude` (the version M07 measured on; the CLI updates itself). Projects under
`/Users/danny/Documents/Apps/` are built one milestone per fresh session, each session ending with
a handover that the next session's prompt is made from. Until Baton, a person was the
copy-and-paste step between sessions: reading the handover, choosing what to run next, starting
the session, and dealing with whatever stopped it. Baton is that step, run every sixty seconds by
launchd, unattended and overnight.

### 1.2 What Baton is

A **relay**: deterministic shell that runs once per tick, reads its inbox, its dispatch log, the
target project's plan file, the fleet view and one git check, then dispatches, resumes, waits and
escalates by fixed rules. It embeds no model call (ADR 0001, `docs/adr/0001-baton-never-calls-a-model.md`).
Judgement is dispatched as a session and returns as an artifact; what is left is the person's.

### 1.3 Principal workflows

1. A session finishes a milestone, merges, refreshes the successor briefs, writes a handover
   artifact and prints it. The next tick consumes it, computes what the plan makes eligible,
   intersects that with the handover's dispositions, and dispatches the next session into a fresh
   worktree with the kickoff prompt from its brief.
2. A session stops short — an API error, a question, a turn without a handover, a crash — and the
   tick classifies the ending from a file or a row, then waits, resumes, redispatches or escalates
   by the rule for that class.
3. A person answers what only they can: `baton answer <milestone>` delivers a ruling; an edit to
   the plan file or a brief is re-read by the next tick; `baton status` shows what waits on them.
4. Baton builds itself the same way: from M02 every Baton milestone is dispatched by the Baton
   that exists so far.

### 1.4 Success criteria

- A night with one lane in flight, one usage-limit wait and one `asking` artifact ends with the
  milestone merged, the ruling delivered, and every event in the log — with the person having typed
  one command.
- `baton tick` run twice against the same inputs changes nothing the second time.
- A fresh Mac needs exactly the setup facts in §2.11 and nothing that is not written down.

### 1.5 Non-goals

Baton does no milestone work: it never edits a target project's code, runs its reviews or makes
its scope calls. No cloud or remote execution; no terminal-emulator automation; nothing
multi-user, hosted or commercial. A judgement point that recurs in the log is the named moment to
reopen ADR 0001, not a reason to add one now.

---

## 2. Functional requirements

Conventions: every family names the ticket its entries came from; the `Decided by` column names it
per entry where a family draws on several. Terms are `CONTEXT.md`'s. "The five inputs" are the
dispatch log, `claude agents --json`, the inbox, the plan file and one git check. A "row" is one
entry of `claude agents --json`.

### 2.1 The project contract (REQ-CONTRACT) — "What a project hands to Baton"

The contract's text lives once, in `CONTRACT.md` at Baton's root, so a third project can cite it by
path. These entries bind Baton to it.

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-CONTRACT-01 | A target project's `CLAUDE.md` implements the six clauses of `CONTRACT.md`: briefs with the two exact headings and the slot line; the plan file; the close-out order (a)–(e); the artifact; the outcomes; every eligible milestone listed. Baton drives a project only through those clauses and reads nothing else from it. | Reclaim's and Baton's `CLAUDE.md` each name the brief path, the plan file and the close-out; a fixture project with the six clauses is driven end to end in tests. | What a project hands to Baton §5; amended by Dispatching more than one at once |
| REQ-CONTRACT-02 | The contract has six clauses and gains none for permissions, hooks or Baton's state: those are Baton's own state under `~/.baton/`, so the target repository holds no `.claude/settings.json` for Baton's sake. | No Baton-owned file exists in a target repository. | Where an escalation goes §2 |
| REQ-CONTRACT-03 | The slot line is the whole of part 2 and is replaced whole at dispatch; a person leaves it as written. The standing parallel-run rules live in part 5 and the refusal in part 7. | Every brief's prompt carries the slot line verbatim; `baton dispatch` replaces exactly that paragraph. | What a project hands to Baton §5 clause 1 |
| REQ-CONTRACT-04 | The close-out writes `done` in the milestone's `Status` cell at step (c), on `main`, in the same commit as the refreshed briefs; `merged_as` on the artifact is verified independently, so the column and the commit are two checks of one fact. | A close-out that wrote `done` without the merge landing fails consumption with the reason. | Dispatching more than one at once §1 |
| REQ-CONTRACT-05 | The merging session runs the project's standing check on `main` after its merge and writes `main-broken` if it cannot fix a failure; the standing check is named by the project's `CLAUDE.md`, never by a plan-file field. | Baton's `CLAUDE.md` names `sh tests/run.sh`; Reclaim's names its builds and tests. | Dispatching more than one at once §5 |
| REQ-CONTRACT-06 | A hand-started session carries no injected gate; the contract in `CLAUDE.md` alone makes it write the artifact. | Baton's M01 session, started by hand, writes `~/.baton/inbox/M01-<session>.json`. | What a project hands to Baton §1 |

### 2.2 The handover artifact and its outcomes (REQ-ARTIFACT) — "What a project hands to Baton"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-ARTIFACT-01 | The artifact is `~/.baton/inbox/<milestone>-<session>.json`, written as `.tmp` then renamed. Top level, always: `baton` (1), `project` (canonical checkout), `milestone`, `session` (`CLAUDE_CODE_SESSION_ID`), `outcome` ∈ `complete` \| `asking` \| `stopped`, `written_at` (ISO 8601 UTC, for people, never for freshness). | A file lacking a required field, or failing to parse, is ignored by the gate and rejected by the tick with the reason. | What a project hands to Baton §1, §2, §4 |
| REQ-ARTIFACT-02 | `complete` adds `merged_as` and `eligible[]`: one entry per plan-eligible milestone with `milestone`, `brief` (`path`, `heading`) and `disposition` ∈ `run` \| `wait` (with `wait_for[]`) \| `held` (with `held_by`). No prompt text, no model, no worktree flag, no validity field, no "runs alone" flag. | Schema check in tests; a `run` entry beside other entries means the others wait for it. | What a project hands to Baton §2 |
| REQ-ARTIFACT-03 | `asking` adds `question` verbatim, `options[]` and `recommendation` when the session has them, and `context` (`path` absolute inside the session's own checkout, `heading`). A missing `context` is a warning, not a rejection. | Fixture artifact consumed; the escalation message carries the question, numbered options and the marked recommendation. | What a project hands to Baton §2, §4 |
| REQ-ARTIFACT-04 | `stopped` adds `reason` ∈ `unfinished` \| `blocked` (with `blocked_by`) \| `merge-failed` \| `main-broken` \| `no-handover` \| `api-error` \| `other` and `detail`. `no-handover` is written only by the Stop gate; `api-error` only by the StopFailure hook, with `error` (the StopFailure value), `error_details` when present, and `detail` = `last_assistant_message` verbatim. | Each reason routes to the action in REQ-STOP through `stop_route`. `written_by` is derived from the reason and never stored on the file, so authorship is not decidable from the artifact itself: the rule bites where it can, and an `api-error` carrying no `error` is rejected with the rule `reserved-reason`, because only the hook can supply that field (D-033). | What a project hands to Baton §2; What stops a session §2a; Dispatching more than one at once §5 |
| REQ-ARTIFACT-05 | Provenance is the id match: a dispatched session's `session` must have a transcript found by glob `~/.claude/projects/*/<session>.jsonl`, never by a path derived from the project. Not-yet-acted-on is a property of the inbox, not of the file; nothing is stale by age; no ordinal, no checksum. | A file whose session has no transcript is rejected. | What a project hands to Baton §4 |
| REQ-ARTIFACT-06 | Rejected, with the reason logged and a lane escalation: no transcript for `session`; `project` not a registered checkout; for `complete`, `merged_as` not an ancestor of `main`. A `brief` pointer whose path or heading is missing on `main` rejects that entry, not the file. A `.tmp` whose session has no live row with a `pid` is an orphan and is rejected. Rejected files move to `~/.baton/rejected/` and keep their name. | One fixture per rule: `no-transcript`, `unregistered-project`, `merged-as`, `reserved-reason`, `orphan-tmp`, and REQ-ARTIFACT-01's `unparseable` and `missing-field`, all ending in `rejected/`; `brief-pointer` consumes the file and rejects the entry, whose `rejected` event names the entry's milestone and the archived path (D-034). `merged-as` needs three, because a claim can be a name git resolves, a commit that does not exist, or a real commit that is not on `main` (D-037), and only the last reaches the ancestry check INV-03 names. | What a project hands to Baton §4; Dispatching more than one at once §3 step 2 |
| REQ-ARTIFACT-07 | Consumed files move to `~/.baton/archive/<milestone>-<session>-<consumed-at>.json`; the suffix exists because one session may end more than once (an `api-error`, then its real handover under the same inbox name). The move is the consumption: a file in the inbox has not been acted on, one in the archive has. | The archived name is carried verbatim on the `consumed` event's `archive` field. | What stops a session §2a; The dispatch log §5 derivation 4 |
| REQ-ARTIFACT-08 | The printed fallback: if the file is missing and the Stop hook's `last_assistant_message` holds a `baton` fence that parses and names the same session, the gate writes it into the inbox and records the recovery. A guarded fallback, never a second source. | Fixture Stop payload with a fence and no file produces the file; one naming another session does not. | What a project hands to Baton §1 |
| REQ-ARTIFACT-09 | The Stop gate gates on the file, never on text: exit 0 when `~/.baton/inbox/<milestone>-<session_id>.json` exists; on the first stop without it, block with the reason "write the handover artifact"; on the next stop (`stop_hook_active` true) write a `stopped` artifact with reason `no-handover` and let go. It stands down while the payload's `background_tasks[]` is non-empty, because a session waiting on its own subagent is not done. The gate and the StopFailure hook both stand down, writing and printing nothing, once `archive/` holds this session's `complete` handover for the milestone: the lane is closed, and a person who resumes the session later to ask or to continue is not held to a handover it already gave, nor turned into an ending the tick would act on (D-078). | Three fixture payloads (no file, `stop_hook_active`, running subagent) produce block, `no-handover`, and pass-through respectively; with an archived `complete` handover both hooks pass through, and with an archived `stopped` one the gate still blocks. | What a project hands to Baton §1; Watching a dispatched session (the false handover) |

### 2.3 The tick (REQ-TICK) — "Relay or conductor"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-TICK-01 | One launchd agent with `StartInterval` 60 runs one short script that exits. `WatchPaths` and `QueueDirectories` are not used. A firing missed during sleep or while the job still runs is caught up by the next. | The plist has `StartInterval`, `AbandonProcessGroup`, `EnvironmentVariables` with `LC_ALL`, and a `ProgramArguments` of the granted shell and the installed script. | Relay or conductor §4 |
| REQ-TICK-02 | The tick remembers nothing. Every run reconciles from the five inputs and the status feed; a sleep, a restart or a killed process leaves the same inputs for the next tick, so every tick is a recovery. | Idempotence: tick twice on the same fixture and the second changes nothing. | Relay or conductor §4; What stops a session §6 |
| REQ-TICK-03 | An atomic `mkdir` lock serialises a launchd firing against a hand run; every verb runs under it and the log is written only under it. A stale lock is reported first by `status`, before anything else, and is the `baton-unhealthy` project-scope escalation. The tick clears a lock past the interval whose pid answers no signal and writes that escalation under the lock it then takes; one whose holder is alive is left and the verb refuses (D-039). | A held lock makes a second tick exit without acting; the age of a stale lock is printed. | Relay or conductor §4, §6; Where an escalation goes §5 |
| REQ-TICK-04 | The order is self-check → consume → reconcile rows → waits and resumes → dispatch. Stall, crash and the dispatch hold all test "no artifact in the inbox for this session", which is true only after the inbox has been read in the same tick. | A fixture with an artifact that landed a second ago is neither a stall nor a crash. | What stops a session §0; Dispatching more than one at once §3 |
| REQ-TICK-05 | The self-check, first, per registered project: read the plan file in full, parse both tables, run `git -C <path> rev-parse HEAD`.  Either failing parks the project — a project-scope escalation, `plan-unreadable` for a read or a git failure and `plan-unparseable` for a parse failure, carrying the path and for a parse failure the table, row and cell — and skips it for the rest of the tick. The first self-check that passes writes the `resolution`, which is REQ-ESC-05's edit route and the only one the tick itself can see (D-041). | A plan file with one bad cell parks its project and dispatches nothing; the event names the cell. | Dispatching more than one at once §2, §3 step 1 |
| REQ-TICK-06 | `~/.baton/last-tick` is written last and atomically (`.tmp` then rename), after the work and after the lock is released,  so it means "a tick completed". A tick that could not read the rows writes none: it ran the self-check and stopped, so saying it completed would advance the clock the gap is measured against (D-049). `status` prints it first; the gap is measured against it and never against the newest event. | A tick that dies halfway leaves the previous value. | The dispatch log §3 |
| REQ-TICK-07 | Each dispatch starts `caffeinate -i -w <pid>` against the row's pid, detached; each active wait holds `caffeinate -i -t` renewed per interval for at most `caffeinateMaxHours` from the wait's start. The plist sets `AbandonProcessGroup` so holders outlive the tick. `caffeinate -i` does not prevent lid-close sleep, and timers stretch by any sleep; the plan states lid open or clamshell as a hardware condition. | Prototype item 17: the holder reparented to pid 1 with a `PreventUserIdleSystemSleep` assertion. | Relay or conductor §4; Watching a dispatched session |
| REQ-TICK-08 | The tick reaches the CLI by absolute path (`/Users/danny/.local/bin/claude`), sets `LC_ALL` before parsing `backgrounded · <id>` (the separator is two bytes and launchd sets no `LANG`), and every outside thing — the claude binary, the clock, caffeinate, Baton's home, the service's log, the transcripts — is reached through one variable so a test can point it at a shim or a directory. | The seams are named in `docs/ARCHITECTURE.md` §7 and every test uses them. | Relay or conductor §5; Watching a dispatched session |
| REQ-TICK-09 | The tick is a launchd job whose executable is `/Users/danny/.baton/bin/sh`, an ad-hoc signed copy of `/bin/sh` granted Full Disk Access, because a launchd job run by `/bin/sh` cannot execute a script under `~/Documents`, read a file there, or run git there. Nothing under `~/Documents` is executed by the job; the installed relay lives under `~/.baton/bin/`. | Prototype run C: `Operation not permitted` on `cat` and `git` under `~/Documents`; items 36–38 prove the granted copy. | Dispatching more than one at once §2 |

### 2.4 Stops and the ladder (REQ-STOP) — "What stops a session, and what happens next"

Every ending arrives as a file: the session's own handover, the Stop gate's `no-handover`, or the
`api-error` artifact. Every class carries two bits, retry and notify-now, so a wrong label costs one
refused request per interval, never a night.

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-STOP-01 | The taxonomy is fixed: wait, transient, unrecoverable, context overflow, question, ended without a handover, crash, stall, long-running, declared stop. Every class is detected from an artifact's `outcome`/`reason`/`error`, a row's `state`/`status`/`waitingFor`/`pid`, a transcript's modification time (a stat, never a read), and the log. Context compaction, an unmet criterion, and Baton's own death are not classes. | The table in `docs/ARCHITECTURE.md` §5 has one row per class with its detection and handling; each row has a fixture. | What stops a session, and what happens next §1 |
| REQ-STOP-02 | API errors split on `error` alone. `rate_limit`, `billing_error`: wait. `overloaded`, `server_error`, `max_output_tokens`: transient, as wait, `max_output_tokens` retried at once. `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `cloud_credential_error`, `unknown`: as wait, notify now. `invalid_request`: no resume, redispatch through the recovery clause, taking the ladder's redispatch step. `model_not_found`: a lane escalation at once, no retry; the plan edit is the ruling and the next tick redispatches attempt n+1. `--fallback-model` is never passed. | One fixture per `error` value routes as stated. | What stops a session, and what happens next §1, §2b; amended by Dispatching more than one at once §7 |
| REQ-STOP-03 | The wait is stop-then-resume every `retryMinutes` (15) with the continue template, spending no attempt, never redispatching, continuing past every ceiling up to the weekly horizon. Ceilings are when the person hears, never when retries stop: `rate_limit` after 2 h, transient after 1 h, `billing_error` and the unrecoverable set at once. The next retry is the newest `wait_retry` plus the interval, read from the last retry rather than extrapolated, because sleep stretches every interval. | A fixture log with an `api-error` consume and `n` retries yields the right next-retry time and the right notification at the ceiling. | What stops a session, and what happens next §2d; The dispatch log §5 derivation 5 |
| REQ-STOP-04 | The ladder per `(project, milestone, attempt)`: failure 1 → resume once; failure 2 → redispatch (attempt n+1) through the recovery clause; failure 3 → escalate (`ladder-end`). A failure ending is a `no-handover`, a confirmed crash, or a `resume` with `outcome: refused`. The reset point is a `consumed` with `written_by: session` or the attempt's own `dispatch`; a wait never counts and never re-arms. | Derivation 9 over fixture logs. | What stops a session, and what happens next §2c; The dispatch log §5 derivations 9, 11 |
| REQ-STOP-05 | A resume is `claude stop <id>`, a wait until no row carrying the session has a pid (a failed listing is not a landed stop; bounded), then a flagless `claude --bg --resume <uuid> "<continuation>"`; any flag forks a copy, and so does a resume into a session the stop has not yet reached. A resume that prints a copy-fork `note:` has failed to stop the original: stop it, log `resume` with `outcome: forked` and a `copy_fork` event, and the new id carries the attempt. | Prototype §10-3 and item 16; the parse rule for the `note:` line is in `docs/ARCHITECTURE.md` §4. | What stops a session, and what happens next §2c; Watching a dispatched session; The dispatch log §1 |
| REQ-STOP-06 | Two continuation templates, split by what the session must do next: *continue* (after a wait, a transient, an unrecoverable, a crash) and *finish the close-out* (after `no-handover` only), each carrying `<milestone>, attempt <n>, resume <r>` and the interrupted-tool sentence "check the state before repeating it". The texts are in `docs/ARCHITECTURE.md` §4 verbatim. | The delivered prompt equals the template with slots filled from the log. | What stops a session, and what happens next §2e |
| REQ-STOP-07 | A redispatch's slot line carries "This is attempt <n> at this milestone; a previous attempt left work on this branch at <commit>, and the brief may hold completion evidence, which the recovery clause covers." The recovery clause keys on the brief, never on the number. | The composed slot line on attempt 2 names the branch's commit. | What stops a session, and what happens next §2e; Dispatching more than one at once §3 step 8 |
| REQ-STOP-08 | Stall: a logged in-flight session with a live process, not `waiting`, no artifact in the inbox, and the newest modification time across its transcript and its subagents' transcripts (`~/.claude/projects/<slug>/<sessionId>/subagents/agent-*.jsonl`) older than `stallMinutes` (30). Notify once with the row's `state` and the matching verb; the session is untouched and the notification is resolved by its own artifact. `state: done` under the condition means "finished a turn, wrote nothing": the remedy is `answer` with the finish template. | Fixture with static transcripts past the threshold notifies once; a subagent transcript newer than the threshold does not. | What stops a session, and what happens next §3 |
| REQ-STOP-09 | Long-running: `longRunningHours` (6) since the attempt's latest `dispatch`, `resume` or `takeover` event → notify once, session untouched. | Derivation over a fixture log. | What stops a session, and what happens next §4; The dispatch log §4 |
| REQ-STOP-10 | Crash: a logged in-flight session whose row is absent or carries `pid: null` (the tell, while `state` may still read `working`), with no artifact in the inbox, on two consecutive ticks. First sighting is a `crash_sighting` event; the second confirms: `claude stop <id>` if a pid remains, then resume under the id with the continue template (`<class>` = `process gone`) if a transcript exists, else redispatch. A sleep leaves the row byte-identical and is never a crash. | Prototype item 23 and 24; two-tick fixture. | What stops a session, and what happens next §6; Watching a dispatched session |
| REQ-STOP-11 | A question is either an `asking` artifact (stop the session on consume, escalate, resume with the ruling) or a live row with `waitingFor: "input needed"` and no artifact (escalate at once, process untouched, never stopped, never timing out). A stopped `AskUserQuestion` call can be answered on resume; `prompt-lost` names only a closed resolution path, and its ruling carries no dropped-call sentence. | Fixture row with `input needed` escalates class `question`. | What stops a session, and what happens next §5; amended by The dispatch log |
| REQ-STOP-12 | Declared stops: `unfinished` → redispatch attempt n+1, not a failure; a second consecutive `unfinished` escalates with both splits. `blocked` with `blocked_by` → leaves the in-flight set, silent while the blocker is in flight or eligible, redispatched when the plan shows it `done`, otherwise escalates; a distant `wait_for` notifies once the same way. `blocked` naming nothing, `merge-failed`, `other` → escalate with the detail. `merge-failed` and `main-broken` resolve by a ruling that resumes the session to finish the close-out from step (c); the plan-file edit is the fallback when the session is gone, and the edit that ends them is the milestone's `Status` changed to `done` after the park — the close-out done by hand (D-074). `main-broken` parks the project; in-flight lanes run on, and no new dispatch or redispatch starts for the project while it stands; a ruling delivered to one `main-broken` park is delivered in turn to every other `main-broken` park of the project. | One fixture per reason. | What stops a session, and what happens next §7, §8; amended by Dispatching more than one at once |
| REQ-STOP-13 | The dispatch hold: no dispatch on a model with an active `rate_limit` or `billing_error` wait; every model held once a second model is limited; both lift when the wait clears. Opus lanes carry on through a Fable-only hold; a Fable milestone is never downgraded. | `hold` and `hold_lifted` events over a fixture. | What stops a session, and what happens next §9; Dispatching more than one at once §7 |
| REQ-STOP-14 | Takeover: a lane is taken over exactly while its transcript's newest message record is one Baton did not send, matched by hash against every prompt sidecar of that `(project, milestone)`. A message record is a `user` record, not `isMeta`, not `isCompactSummary`, whose `promptSource` is `typed` (Baton's own prompts, and a terminal) or `queued` (a message sent from Claude.app between turns), or whose `origin.kind` is `human` (a slash command); or a `queued_command` attachment whose `origin.kind` is `human` (a message sent from Claude.app mid-turn). A peer session's message, a task notification and the Stop gate's feedback are not one (D-085). Baton then stops acting on the lane — no resume, redispatch, ruling or ladder step — still consumes an artifact that lands, still counts the lane against the cap, notifies once on the Mac, and restarts the long-running clock. Release: a `resume` makes Baton's prompt the newest typed record, or the row goes idle and a handover for the milestone has been consumed. Not a park. | Live item 45 (hash normalisation) passes before the rule is trusted; a fixture transcript with a foreign typed record reads as taken over and a later Baton prompt releases it. | The dispatch log §4; Watching a dispatched session |

### 2.5 Escalation and notification (REQ-ESC) — "Where an escalation goes"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-ESC-01 | A notification is a message Baton keeps working past; an escalation parks a lane or a project until a ruling or an edit resolves it. Nothing times out into a decision or a denial. | Every class in §2.4 is one or the other, per `docs/ARCHITECTURE.md` §5. | Where an escalation goes §5, §6 |
| REQ-ESC-02 | Both reach the Mac as a `display notification` through `osascript` plus a log event. Baton itself sends nothing to the phone — a self-sent iMessage raises no iOS alert — but every dispatched session is on Remote Control (REQ-ESC-08), so the Claude mobile app lists it, pushes its questions, and can answer them. | Prototype items 32, 33 and the addendum. | Where an escalation goes §5; Watching a dispatched session; The dispatch log §2 footer |
| REQ-ESC-03 | The message has three fixed parts — address (`<project> <milestone> · <class>`), content (the deterministic content itself: the question with numbered options and the marked recommendation, or the detail; never a pointer), verb (the `baton` command that resolves it). | Rendered fixtures for `asking`, `merge-failed`, `ladder-end`. | Where an escalation goes §5 |
| REQ-ESC-04 | Scope is a property of what failed. Lane classes: `asking`, `question`, `ladder-end`, `unfinished-twice`, `blocked`, `merge-failed`, `other`, `disagreement`, `omitted`, `model_not_found`, `dispatch-failed`. Project classes, exactly: `plan-unreadable`, `plan-unparseable`, `main-broken`, `baton-unhealthy`, and `dispatch_failed` with `stage: service`. | The class list is the log's; every escalation event carries `scope`. | Where an escalation goes §6; The dispatch log §2 |
| REQ-ESC-05 | A parked lane unparks in exactly three ways, each a `resolution` event: `baton answer` delivers a ruling; a live question was answered in place, which the row leaving `waiting` or the session's own later artifact shows; a person edits the plan rows or the brief a park answers to and the next tick re-reads it. A resolution ends the park: the rule that raised it does not raise it again for the same ending — after an edit it takes the next step, after a ruling it waits for the session's next ending. | Derivation 2 over fixtures. | Where an escalation goes §6 |
| REQ-ESC-06 | `baton answer <milestone> <ruling \| option number>` resolves against parked lanes across all projects: one match acts; more than one refuses and prints `<project>/<milestone>` candidates, which is also the accepted long form; a milestone not parked is refused ("nothing is waiting on M19"). An option number expands to the option's text, from the archived artifact, before delivery. Delivery is stop-then-flagless-resume with the ruling label in `docs/ARCHITECTURE.md` §4, and the `resolution` is written only once the resume was delivered or forked; a refused resume leaves the park standing. A ruling reaches only a session Baton dispatched: a park with no project, session or attempt is refused and resolved by an edit. `baton answer <milestone> "continue"` is also the hand-back after a takeover. | Fixtures for one, two and zero matches. | Where an escalation goes §7; The dispatch log §4 |
| REQ-ESC-07 | The escalation record is the `escalation` event (`class`, `scope`, `carries`, `channel`) and the `resolution` event (`how` ∈ `ruling` \| `answered in place` \| `edit`, `escalation_at`); `status` shows the open ones; nothing else is stored. | Derivation 2. | Where an escalation goes §6; The dispatch log §2 |
| REQ-ESC-08 | Every dispatched session is on Remote Control: the settings file writes `remoteControlAtStartup: true`, so each is listed in Claude.app and on the phone and can be typed into there, and its transcript is stored on Anthropic's servers while connected (D-081). A plan-file `Remote: yes` marks the lane whose questions are answered from the phone: for it the row is not a park detector, parks are artifact-borne, and a prompt nobody answers surfaces as a stall whether the row reads waiting or not. | Composed settings carry `true`; fixture row `working/idle` for a remote lane is not read as a park, and a remote lane whose row reads `waiting` stalls; live: a session started with the key `false` is absent from Claude.app. | Where an escalation goes §5; Dispatching more than one at once §7 |
| REQ-ESC-09 | `baton allow <milestone> '<rule>'` writes exactly the rule given to the project's `permissions.json` and the dispatched settings file in place, logs a `widening` event with the rule and the milestone that earned it when a file changed, and refuses to write an `ask` rule, JSON, a rule over 1 KB or with a newline, and `--resume` on a parked lane; both files parse before either is written. Baton never composes a rule. `--resume` stops and flaglessly resumes the session so the re-issued command passes. | Prototype item 35. | Where an escalation goes §4; amended by The dispatch log |
| REQ-ESC-10 | The gap report: `now` minus `~/.baton/last-tick`, reported as a notification with class `gap` only when the log shows a lane in flight, waiting or parked during the gap, keyed on the marker value so one outage reports once. A second watchdog is not built. | Fixture marker older than the interval with an in-flight lane notifies once. | Where an escalation goes §5; The dispatch log §2 footer |
| REQ-ESC-11 | `baton status` is one view, no flags, whole file, ordered: last tick; project-scope parks; parked lanes (`<project>/<milestone> · <class> · <one line> · <verb>`); taken-over lanes with the hand-back; waits and holds; in flight with elapsed and live notifications; silent waits; an open gap; what is waiting in the inbox (D-035). A section with nothing in it prints nothing. | Rendered fixtures: one with nothing but the marker line, one with all nine sections. | The dispatch log §6 |

### 2.6 The plan file (REQ-PLAN) — "Dispatching more than one at once"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-PLAN-01 | The plan file is the milestone table in the project's plan document, located by its `ID` header cell, and the gates table located by its `Gate` header cell, wherever they sit. Columns are read by name — `ID`, `Depends on`, `Model`, `Effort`, `Remote`, `Status` — and every other column is ignored. | Reclaim's and Baton's `docs/MILESTONES.md` parse; a table with extra columns parses. | Dispatching more than one at once §1 |
| REQ-PLAN-02 | Cells hold tokens: `Depends on` is ids and ranges (`M05, M06`; `M01–M13` with en dash or hyphen) or `–` for none, never `all`; `Model` an alias from `~/.baton/config.json`'s `models` or a full model id; `Effort` blank or `low\|medium\|high\|xhigh\|max`; `Remote` blank or `yes`; `Status` blank, `done` or `held`. A gate's name is a string matched by equality against `held_by`; `Cleared` is blank or a D-number. | One fixture per token kind, plus one per malformed cell. | Dispatching more than one at once §1 |
| REQ-PLAN-03 | A cell that does not parse fails the whole read: the project parks (`plan-unparseable`, naming the table, row and cell) and nothing is dispatched on a guess. | A misspelled model on one row dispatches nothing for the project. | Dispatching more than one at once §1, §2 |
| REQ-PLAN-04 | `Status` has one writer per transition: `done` by the close-out at step (c); `held` and its clearing by a person. In flight is the log's knowledge, never the column's. `held` and an uncleared gate are the same state to the tick. | Eligibility fixtures. | Dispatching more than one at once §1 |
| REQ-PLAN-05 | A milestone is eligible when every id in `Depends on` reads `done`, its `Status` is blank, and no uncleared gate holds it. | Derivation over Baton's own plan yields M02 after M01 is `done`. | Dispatching more than one at once §3 step 5 |
| REQ-PLAN-06 | `~/.baton/projects/<project>/project.json` holds `path` (the canonical checkout) and `plan` (the plan file's path relative to it); the tick reconciles every directory under `~/.baton/projects/`. `<project>` is the project key. A renamed folder is a new key; `status` says "no project at this path" for the old one. | Registration fixture. | Dispatching more than one at once §1 |
| REQ-PLAN-07 | `~/.baton/config.json` holds Baton's numbers as defaults overridable by one line: `cap` 2, `fableReserve` 80, `stallMinutes` 30, `longRunningHours` 6, `retryMinutes` 15, `caffeinateMaxHours` 6, `keepFinished` 3, `idleStopMinutes` 60, `wakeModel` `haiku`, `models` (`fable`, `opus`, `sonnet`, `haiku`). The tick's interval is the plist's, not a config value. | Every number in the tick reads from the file with the default as fallback. | Dispatching more than one at once §6 |
| REQ-PLAN-08 | `baton plan <project>` parses the plan file, prints the graph as the tick sees it (done, eligible, held by which gate, in flight, model and effort per milestone), validates every `Model` cell, and lists the project's `widening` events newest first. | Run against Baton's own plan on the first tick. | Dispatching more than one at once §1; The dispatch log §5 derivation 14 |

### 2.7 Dispatch, worktrees and merges (REQ-DISPATCH) — "Dispatching more than one at once"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-DISPATCH-01 | For each eligible milestone the disposition in force is the one in the newest archived `complete` handover of that project that lists it: `run` → candidate; `wait` → honoured while any `wait_for` is not `done`, dispatched the moment all read `done`, a `wait_for` that is neither in flight, eligible nor done notifying once; `held` on a gate the plan shows cleared → dispatched with a `plan_override`; `run` on a milestone the plan holds → withheld with a `plan_override`. Exactly two things escalate, lane scope, by name: a `run` the plan makes ineligible (`disagreement`) and a plan-eligible milestone no handover lists (`omitted`) — judged once the project has an archived `complete` handover, and not while a dependency's session is mid-run. Either park also ends when its condition no longer holds (D-071). | Six fixtures, one per branch. | Dispatching more than one at once §3 step 6 |
| REQ-DISPATCH-02 | Then the holds and the cap: drop candidates on a held model; drop `fable` candidates while the freshest status file's `seven_day.used_percentage` ≥ `fableReserve` — the newest by modification time that carries the number, and no reading once its own `seven_day.resets_at` has passed (D-073); count in flight as every logged session with a live row plus every parked lane holding a live prompt (stopped `asking` sessions do not count); dispatch while below `cap`, in the handover's `eligible[]` order within a project, then the project with fewer in flight, then plan row order (D-072). | Cap fixture with three candidates dispatches two in the stated order. | Dispatching more than one at once §3 step 7, §6, §7 |
| REQ-DISPATCH-03 | Every milestone runs in `../<Project>-M<nn>` on branch `m<nn>`, created by `git -C <path> worktree add ../<Project>-M<nn> -b m<nn> main` — from `main` explicitly — and reused on redispatch with the reuse and its commit logged. It outlives the milestone: the session removes only its build products at close-out, and nothing in Baton removes a worktree, because a session whose working directory is gone cannot be resumed and a service restart ends its process for good (D-078). | Fixture repo; a redispatch reuses the worktree; no code path runs `git worktree remove`. | Dispatching more than one at once §5; amended by D-078 |
| REQ-DISPATCH-04 | The settings file is composed at `~/.baton/settings/<project>-<milestone>.json`, a stable path, per REQ-PERM. | Path equality in the `dispatch` event. | Dispatching more than one at once §3 step 8, §4 |
| REQ-DISPATCH-05 | The kickoff prompt is read from the brief on `main` (`brief.path`, the code block under `brief.heading`) and part 2 replaced whole with the slot line: this session's worktree, branch and canonical checkout; every other milestone in flight with its worktree name and brief, never paths; the attempt sentence on a redispatch; the staging rule; the refusal. The body is written to `~/.baton/prompts/<session>/<n>.txt` and hashed. | `awk` fixture: the paragraph beginning `WHAT ELSE IS IN FLIGHT.` is the only thing replaced. | Dispatching more than one at once §3 step 8; The dispatch log §4 |
| REQ-DISPATCH-06 | The command, with the worktree as `cwd` and `LC_ALL` set: `claude --bg -n "<session name>" --model <Model> [--effort <Effort>] --permission-mode bypassPermissions --settings <file> "<prompt>"`; the id is parsed from `backgrounded · <id>` on stdout. The name is `Baton · <project> · <milestone>`, and `Baton · <milestone>` when the project key is `Baton` itself, where the prefix has already named the project (D-036). The prefix is the only ownership marker a row carries; the model is not in it. Then the row's `pid` is read and `caffeinate -i -w <pid>` started detached; then the `dispatch` event. | Shim-backed fixture. | Dispatching more than one at once §3 step 8; Watching a dispatched session |
| REQ-DISPATCH-07 | `Remote: yes` is dispatched by the REQ-DISPATCH-06 command unchanged, prompt included; the settings file every dispatch passes carries `remoteControlAtStartup: true` (REQ-PERM-03), which connects the session and keeps its prompt. `--remote-control` is never passed, because at dispatch it discards the positional prompt. One `dispatch` event with `remote: true`. A flagless resume restores `--settings`, so Remote Control survives every wait and ruling (D-080). | Shim fixtures for the hand-run verb and the tick; live item 40 (the prompt kept and Remote Control connected on one command) and its resume check. | Dispatching more than one at once §7; amended by D-080 |
| REQ-DISPATCH-08 | A dispatch that produces no session is a `dispatch_failed` event with `stage` ∈ `worktree` \| `settings` \| `prompt` \| `launch` \| `service` and `detail`, no `session`. The test is the absence of a `backgrounded · <id>` line on stdout, or a line that names a worker no row ever carries; the text matched is stderr, or for the second case the service's own line `bg settled <id> (crashed): <detail>` in `~/.claude/daemon.log`, because a worker that crashes before init (a `--settings` path that does not exist) prints `backgrounded`, exits 0 and writes nothing to stderr (item 47). The text is matched against the known strings (`Error: Settings file not found:`, `requires accepting the disclaimer first`, `cannot be combined with --print`, then `Starting background service…`) and defaults to `stage: launch` with the whole text as `detail`. The second consecutive failure for a `(project, milestone)` escalates lane scope; `stage: service` escalates project scope. | Shim fixtures per stage. | Amended by The dispatch log; peer session (binary strings) |
| REQ-DISPATCH-09 | The merge stays the session's, the standing check on `main` afterwards is the session's, and Baton detects neither shared-spine collisions nor their aftermath: both arrive as artifacts (`merge-failed`, `main-broken`). | No code path reads a target's tree. | Dispatching more than one at once §5 |
| REQ-DISPATCH-10 | `baton dispatch <project> <milestone>` performs step 8 alone, by hand, for the bootstrap: it checks the milestone is eligible by the plan, refuses if a live row already carries it, and does everything REQ-DISPATCH-03 to 08 say. | Baton's own M02 is dispatched with it. | Baton's plan and its M01 prompt |

### 2.8 Permissions (REQ-PERM) — "Where an escalation goes", re-decided by "Watching a dispatched session" and "Dispatching more than one at once" §4

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-PERM-01 | The permission mode is `bypassPermissions`, given on the flag at dispatch and restored by a flagless resume. `auto` is unreachable in a `--bg` session (accepted, recorded as `default`), `dontAsk` denies silently, `default` parks on the first uncovered command. The cost is stated: nothing prompts, so `PermissionRequest`, `PermissionDenied` and `Notification` never fire and the channel carries only endings. | Prototype mode table. | Watching a dispatched session; Dispatching more than one at once §4 |
| REQ-PERM-02 | The project's allowlist is Baton's state at `~/.baton/projects/<project>/permissions.json`, holding `permissions.allow` and `permissions.deny` and nothing else; `baton allow` and a person's edit are its only writers. The target repository is untouched. | File shape check. | Where an escalation goes §2 |
| REQ-PERM-03 | The dispatched settings file carries `permissions.defaultMode` (documentation only), the project's `allow` and `deny` copied, no `ask` rules, `remoteControlAtStartup: true` (REQ-ESC-08), and three hooks — `Stop` (the gate), `StopFailure`, `statusLine` — each command carrying `BATON_HOME`, `BATON_PROJECT` and `BATON_MILESTONE` as environment on its command line and pointing at the installed relay under `~/.baton/bin/`. A hand-started session passing the same file behaves as a dispatched one. | Composed file equals the fixture shape in `docs/ARCHITECTURE.md` §3. | Dispatching more than one at once §4; What stops a session §2a |
| REQ-PERM-04 | Two deny classes and nothing else: privilege escalation (`Bash(sudo:*)`, `Bash(su:*)`, `Bash(doas:*)`, `Bash(osascript * administrator privileges*)` — plain `osascript` stays), and Baton's own state by named path (everything under `~/.baton/` except `inbox/`). Deny rules are enforced under `bypassPermissions`, including the `osascript` phrase inside a quoted `-e` argument. Installs and writes outside the working tree are not denied; the target's hard rules are prose a session obeys by reading, and the limit is stated. | Prototype items 30, 31 and the bypass run. | Where an escalation goes §3; Watching a dispatched session |
| REQ-PERM-05 | A deny-rule refusal is invisible to Baton and that is accepted: the model works around it or asks, and asking arrives as an `asking` artifact. No watcher is built for an event that does not exist. | No denial event in the log's schema. | Dispatching more than one at once §4; The dispatch log §2 footer |

### 2.9 The log and recovery (REQ-LOG) — "The dispatch log"

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-LOG-01 | One append-only JSONL at `~/.baton/log.jsonl`, written only by the tick's verbs under the lock; hooks never write it. Each append is one `write(2)` of one line under 4 KB. No index, no rotation, no split until a tick's scan is measurably slow. | The only writer is the one function in `lib/log.sh`; a line over 4 KB is a test failure. | The dispatch log §3 |
| REQ-LOG-02 | The envelope: `at` (ISO 8601 with offset, Baton's own clock) and `kind` always; `project`, `milestone`, `session`, `attempt` when the event has them. A field the event does not have is absent, never null. Every timestamp copied out of Claude Code is kept in the form it arrived, in a field named for what it is. | Schema check over every event a fixture tick writes. | The dispatch log §1 |
| REQ-LOG-03 | `attempt` is the count of `dispatch` events for the `(project, milestone)`, computed before the dispatch and stamped for the reader; the count wins over the stamp. The resume count is the count of the attempt's `resume` events with `outcome` `delivered` or `forked`. Neither is stored anywhere else. Every count keys on `(project, milestone, attempt)`; the session id is the join key, never a counting key. | Derivation 10 over a log with a copy fork. | The dispatch log §1 |
| REQ-LOG-04 | Nineteen event kinds, exactly the table in `docs/ARCHITECTURE.md` §6, with the fields, the rule each serves and the once-only key each carries. Where the table drops something an earlier ticket's prose asks for, the table wins and its footer says why. | Every kind has a writer or is marked "not yet written" per milestone in `docs/MILESTONES.md`. | The dispatch log §2 |
| REQ-LOG-05 | Prompt bodies live in `~/.baton/prompts/<session>/<n>.txt`, `<n>` from 1 per session in delivery order; the `dispatch` and `resume` events carry `prompt_path` and `prompt_sha256`. The hash normalisation is the same on both sides (sidecar and transcript record) and is checked offline against the prototype's captured pair before the takeover rule is trusted. | Live item 45. | The dispatch log §4 |
| REQ-LOG-06 | The fifteen recovery derivations in `docs/ARCHITECTURE.md` §6 are each a pure function of the five inputs; each is a fixture in tests; idempotence is the recovery test. | Fifteen fixtures; the double-tick diff is empty. | The dispatch log §5 |
| REQ-LOG-07 | The archive, not the log, says what was consumed; the `consumed` event's `archive` field holds the archived file's path verbatim and a reader joins on the field, both ways — a file in `archive/` or `rejected/` that no event claims is what a tick killed between the move and its event leaves behind, and derivation 4 names it. The status feed (`~/.baton/status/<session_id>.json`, overwritten per turn) and the tick marker are beside the log and never rotated. | Derivation 4. | The dispatch log §5, §7 |
| REQ-LOG-08 | The log records the model and effort actually run on every `dispatch`, so a milestone's output can be graded against the house standard after the fact. | Field presence. | The dispatch log §2; Dispatching more than one at once §7 |

### 2.10 The verbs (REQ-VERB) — "Relay or conductor" §6, "Dispatching more than one at once" §1, "Where an escalation goes" §4, §7

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-VERB-01 | One script, `baton`, with the verbs `tick`, `answer`, `status`, `plan`, `dispatch`, `allow`, `wake`; every verb takes the lock; `status` and `plan` have no side effects. | `baton` with no verb prints the seven. | Relay or conductor §4, §6 |
| REQ-VERB-02 | `baton tick` runs REQ-TICK-04's order for every registered project and writes the marker last. | Fixture double-tick. | Relay or conductor |
| REQ-VERB-03 | `baton answer <milestone \| project/milestone> <ruling \| n>` per REQ-ESC-06. | Fixtures. | Where an escalation goes §7 |
| REQ-VERB-04 | `baton status` per REQ-ESC-11, the last tick first. | Rendered fixture. | The dispatch log §6 |
| REQ-VERB-05 | `baton plan <project>` per REQ-PLAN-08. | Baton's own plan. | Dispatching more than one at once §1 |
| REQ-VERB-06 | `baton dispatch <project> <milestone>` per REQ-DISPATCH-10. | Baton's own M02. | Baton's plan and its M01 prompt |
| REQ-VERB-07 | `baton allow <milestone> '<rule>' [--resume]` per REQ-ESC-09. | Fixture. | Where an escalation goes §4 |
| REQ-VERB-08 | `baton wake [<milestone \| project/milestone> [<text>]]` per REQ-LIFE-03. | Fixture `wake-verb`. | D-087 |

### 2.11 Setup facts (REQ-SETUP) — what a fresh Mac needs a person to do once

Each is recorded because it lives in no repository and a fresh Mac fails silently without it.

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-SETUP-01 | **Full Disk Access for the granted shell.** `sh install.sh` copies `/bin/sh` to `/Users/danny/.baton/bin/sh` and signs it ad hoc (`codesign --force --sign -`), without which the copy cannot execute at all (D-038); then System Settings › Privacy & Security › Full Disk Access › **+** › add `/Users/danny/.baton/bin/sh` (press ⌘⇧G in the file dialog and paste the path) and turn it on. The launchd job's `ProgramArguments` is that path. The tick's self-check reports a revoked grant within a minute. | Live items 36–38: `cat` and `git rev-parse` under `~/Documents` succeed from the job; a session dispatched by a service the tick started can read the project. | Dispatching more than one at once §2 |
| REQ-SETUP-02 | **The `bypassPermissions` disclaimer**, accepted once interactively: run `claude --dangerously-skip-permissions` in a terminal and accept. Accepted on this Mac on 2026-09-11. Until then a `--bg` dispatch with that mode is refused with "requires accepting the disclaimer first". | A dispatch after acceptance starts. | Watching a dispatched session; Dispatching more than one at once §2 |
| REQ-SETUP-03 | **`cleanupPeriodDays`** in `~/.claude/settings.json`. It defaults to 30 days and sweeps transcripts, `~/.claude/tasks/`, `shell-snapshots/`, `backups/` and job worktrees. "A transcript exists for this session id" is the resume-versus-redispatch test and the substrate of the takeover rule, so a Mac at the default silently changes both after thirty days. This Mac sets `3650`; check with `grep cleanupPeriodDays ~/.claude/settings.json`. | The value is present and large. | The dispatch log §10 |
| REQ-SETUP-04 | **The plist** at `~/Library/LaunchAgents/com.baton.tick.plist`: `ProgramArguments` `/Users/danny/.baton/bin/sh /Users/danny/.baton/bin/baton tick`, `StartInterval` 60, `AbandonProcessGroup` true, `EnvironmentVariables` `LC_ALL=en_US.UTF-8`, stdout and stderr under `~/.baton/`. Loaded with `launchctl bootstrap gui/$(id -u) <plist>`. The job reaches the CLI by absolute path because launchd's `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`. | Prototype run C. | Relay or conductor §4; Watching a dispatched session |
| REQ-SETUP-05 | **The installed relay.** `sh install.sh` from the checkout copies `bin/`, `lib/` and `hooks/` to `~/.baton/bin/` and creates `~/.baton/{inbox,archive,rejected,status,settings,prompts,projects}` and `config.json` if absent, and writes `settings/wake.json` for the wake session (REQ-LIFE-04) when it has changed. A Baton milestone's close-out runs it from the canonical checkout on `main`, after the standing check passes there and the `done` commit lands, and before the handover artifact is written, so the tick that consumes the handover runs the merged relay (D-079). A milestone cannot break the tick that dispatched it. The launchd agent is copied only when none is installed; one that differs from the repository's is left in place with a line saying so, because launchd reads it at every login and replacing it would change what the tick runs without a person choosing it. | Idempotent; a second run changes nothing; an installed agent that differs survives an install. | Baton's plan and its M01 prompt (D-018); amended by D-079 |
| REQ-SETUP-06 | **Remote Control** needs `DISABLE_TELEMETRY` (and `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`) unset in the launching environment (`DISABLE_TELEMETRY` commented out at `~/.zshrc:10` on 2026-09-11; processes started earlier still carry it) and the Claude mobile app signed in to the same account; `claude doctor` confirms eligibility. For the phone to be pushed, `agentPushNotifEnabled: true` is set in `~/.claude/settings.json` (this Mac sets it; `/config` › Push when Claude decides) and the app has notification permission. Every dispatched session relies on it (REQ-ESC-08). | `claude doctor` reports Remote Control available; `grep agentPushNotifEnabled ~/.claude/settings.json` reads `true`. | Reaching you when you're not at the Mac; Watching a dispatched session |
| REQ-SETUP-07 | **Hardware.** An unattended night needs the lid open or clamshell (power plus an external display): `caffeinate -i` does not prevent lid-close sleep, and timers stretch by any sleep. Baton cannot lift this. | Stated in `baton status`'s header once per run. | Relay or conductor §4; Watching a dispatched session |
| REQ-SETUP-08 | **Automation for `osascript` → System Events** is granted on this Mac; a `display notification` from a launchd context needs no further grant (prototype: no TCC dialog). A fresh Mac approves the one dialog on the first notification. | The first notification appears. | Watching a dispatched session item 32 |

### 2.12 A finished session (REQ-LIFE) — D-086 to D-088

A finished session is one whose `complete` handover Baton consumed and whose milestone has not been
dispatched since. Its process is worth keeping — a person goes back to ask what it decided or to carry
on by hand (D-078) — and costs 0.35–0.8 GB idle. On Claude Code 2.1.270 nothing wakes a stopped session
when a message is sent to it (D-086), so the few most recent keep their processes and the rest are
reached through one session that is always there.

| ID | Requirement | Acceptance | Decided by |
|---|---|---|---|
| REQ-LIFE-01 | The offline rule, once per tick across every project, before the dispatch: a finished session Baton dispatched (its `consumed` event carries an attempt; a person's own session never does and is neither stopped nor counted) is taken offline — `claude stop <job>` and one `offline` event with `job`, `idle_minutes`, `rank` and `kept` — when its row has a pid and reads `status: idle`, its transcripts (its own and its subagents', by modification time) are at least `idleStopMinutes` old, and it ranks past `keepFinished` among the finished sessions with a live process, newest transcript first. An open lane is never touched. A refused stop writes no event and is tried again next tick; a stop the CLI took is not repeated while an `offline` event for the session is no older than its transcript. | `offline-keeps-recent` stops the least recently active of four; `offline-refusals` refuses an open lane, a busy row, a waiting row, a recent transcript, a row with no status and a session with no transcript; `offline-stop-not-landed` does not stop twice; `offline-stop-fails` records nothing over a refused stop and retries it; `offline-refuses-hand-started` leaves a session no dispatch named alone. | D-087 |
| REQ-LIFE-02 | `keepFinished` (3) and `idleStopMinutes` (60) are config numbers. Reading a session changes no transcript, so the rule cannot see a reader; the wake is the undo. | Defaults in code and `config.json`. | D-087, D-088 |
| REQ-LIFE-03 | `baton wake` with no milestone lists every finished session as `running` or `offline` with its last activity. With a milestone (or `project/milestone`, required when the name finished in more than one project) it refuses one that has not finished; names a running one's thread rather than resuming it, because a resume into a live session starts a copy; and otherwise resumes the session flaglessly with the text, labelled as the person's, or a one-line wake when none is given, writing a `wake` event with `how: verb`, the outcome classified as a resume's is, and the prompt sidecar. The woken session answers in its own thread, which the resume makes active again in Claude.app. | `wake-verb`. | D-087 |
| REQ-LIFE-04 | The wake session, `Baton · wake`: a `--bg` session in `~/.baton/wake/` with `settings/wake.json` (Remote Control on, Baton's deny list, no hooks) and the model `wakeModel`, whose standing prompt is to run `baton wake <milestone> '<message>'` for each message the person sends it and reply with what it printed. The tick keeps it once an `offline` event exists: nothing while its session has a live row; a flagless resume when its process is gone; a fresh start when it has never started or its last resume was refused; at most one attempt per `retryMinutes`. Its session is the newest `wake` event without a milestone whose outcome was `delivered` or `forked`, never a row found by name, because a stopped session leaves `claude agents --json`. | `offline-keeps-recent` starts it; `wake-session-resumed` resumes it under its own id; `offline-stop-not-landed` leaves a live one alone. | D-087 |

---

## 3. The tick, as policy

The order is REQ-TICK-04; the eight steps are written out in `docs/ARCHITECTURE.md` §2 and are not
restated here. Three policies sit over them:

1. **Reactive quota.** Dispatch until a request is refused; the wait and the hold take it from
   there. `fableReserve` is the one predictive number, Fable only, a proxy over an account-wide
   window; set to 100 it is off. The status feed informs `status` and the wait's reset time and never
   decides a dispatch on its own. ("Dispatching more than one at once" §7.)
2. **The plan wins on gates, both ways; a handover's `wait` is honoured; two things escalate.**
   (§2.7 REQ-DISPATCH-01.)
3. **A person is never prompted over.** A taken-over lane is left alone; a ruling is never delivered
   into a working session. ("The dispatch log" §4; "Where an escalation goes" §7.)

---

## 4. What Baton never does

1. Calls a model inline in the tick (ADR 0001). A morning summary, a re-allocation, a fix for a
   broken `main` are dispatched sessions.
2. Edits a target project's code, runs its reviews, or makes its scope calls. `/review-2` and
   `/address` run inside the session.
3. Trusts a session's word for the one fact it was built to verify: `merged_as` is checked against
   `main` before a `complete` handover is acted on.
4. Composes a permission rule. `baton allow` writes the rule a person typed.
5. Downgrades a Fable milestone. A Fable limit means Fable waits; `--fallback-model` is never passed.
6. Times out an escalation into a decision, or a prompt into a denial.
7. Reads a transcript for anything but its modification time and its message records' hashes.
8. Writes the log from a hook, or from anywhere but the one function under the lock.
9. Starts, stops, attaches to or types into a session a person has taken over.
10. Uses Python, a third-party package, or a language other than `/bin/sh` with `jq` and `awk` —
    until a structure `jq` cannot express or a file past a few hundred lines names the moment for a
    Swift command-line tool ("Relay or conductor" §6).

---

## 5. Invariants

| ID | Invariant | Enforced by |
|---|---|---|
| INV-01 | The tick embeds no model call. | `grep` in review for `claude -p`, `--print`, an API key or a model id outside `config.json`'s alias list; ADR 0001 |
| INV-02 | The log has one writer: the one append function, called only with the lock held. | `grep` for `log.jsonl` outside `lib/log.sh`; a test that runs a verb without the lock and asserts no line was written |
| INV-03 | An artifact's `merged_as` is verified as a commit id — not a name that resolves to one (D-037) — and as an ancestor of `main` before a `complete` handover is acted on. | Three fixtures, one per way of lying: a ref name, a commit that does not exist, and a real commit off `main`; each ends in `rejected/` |
| INV-04 | A session nobody typed into is never prompted over: a taken-over lane receives no resume, redispatch or ruling. | Fixture transcript with a foreign typed record; the tick writes only `takeover` and a notification |
| INV-05 | The tick remembers nothing between runs: every fact it acts on is a derivation over the five inputs. | Idempotence: the double-tick diff is empty on every scenario fixture |
| INV-06 | Consumption is the move: a file is acted on exactly once, because it leaves the inbox when it is. | Double-tick over an inbox fixture archives once |
| INV-07 | Every count keys on `(project, milestone, attempt)`, never on a session id. | Fixture with two projects each holding an M01 and a copy fork |
| INV-08 | Every resume is flagless. | `grep` for `--resume` with any following flag; shim records the argv |
| INV-09 | The dispatched settings file holds no `ask` rule and exactly three hooks. | Composed-file fixture |
| INV-10 | Hooks write per-session files (an artifact in the inbox, a status file), never a shared one. | Hook fixtures; `grep` in the hooks for `>>` |
| INV-11 | The marker is written after the lock is released and never before the work. | Fixture tick killed mid-run leaves the old marker |
| INV-12 | Nothing under a target project is executed by the launchd job; only read, and only through the granted shell. | The plist names only paths under `~/.baton/`; review |

---

## 6. Verification strategy

- **One seam per outside thing** (REQ-TICK-08): `BATON_CLAUDE` (default `/Users/danny/.local/bin/claude`),
  `BATON_DATE` (`date`), `BATON_CAFFEINATE` (`/usr/bin/caffeinate`), `BATON_HOME` (`~/.baton`),
  `BATON_DAEMON_LOG` (`~/.claude/daemon.log`), `BATON_OSASCRIPT` (`/usr/bin/osascript`, the Mac message), `BATON_TRANSCRIPTS` (`~/.claude/projects`, the tree
  derivation 3 globs for `*/<session>.jsonl`; D-032).
  The claude shim plays the roles the tick sees: `--bg` prints `backgrounded · <id>` and later writes
  an inbox artifact; `agents --json` answers from a fixture state file; `stop` and `--bg --resume`
  record their argv. ("Relay or conductor" §5.)
- **Hooks are tested by piping fixture payloads** on stdin — the prototype's captured payloads under
  `.scratch/baton/prototype/obs/` are the source — and asserting on the file written and the JSON
  printed.
- **Scenarios are fixture directories**: a fixture project as a git repository with a plan file and
  briefs, an inbox, a log, a rows file; the assertion is a diff of `BATON_HOME` after the tick
  against the expected directory. **Idempotence is the recovery test**: every scenario is ticked
  twice and the second diff is empty.
- **launchd stays out of the tests**; the tick is invoked directly under the same lock. The live
  proofs — items 36–47 on "Watching a dispatched session" — are run once, by hand, by the milestone
  that owns each, and recorded in that brief's completion evidence.
- **The standing check** is `sh tests/run.sh`, which runs every fixture and prints one line per
  scenario. It is what the close-out runs on `main`.
- **Reporting rule.** A check is reported as passed only with its output attached in the brief's
  completion evidence; an unrun check is listed as unrun with the reason. An unrun check is never
  reported as passed.

---

## 7. Delivery

### 7.1 Install and run

1. The setup facts, §2.11, in order: the granted shell, the disclaimer, `cleanupPeriodDays`.
2. `sh install.sh` from `/Users/danny/Documents/Apps/Baton`.
3. Register a project: write `~/.baton/projects/<project>/project.json` and `permissions.json`
   (`docs/ARCHITECTURE.md` §3 has both shapes). Baton registers itself in M01.
4. `baton plan <project>` until it prints the graph without complaint.
5. Load the plist (REQ-SETUP-04). `baton status` prints the last tick within a minute.

### 7.2 Operational limitations

- The channel carries endings only: under `bypassPermissions` nothing prompts, so a deny-rule refusal
  is seen only if the session asks.
- The phone hears Baton's own escalations only through the session itself: every session is on
  Remote Control and the mobile app pushes what Claude Code decides to push; a self-sent iMessage
  raises no alert.
- A session whose process has stopped cannot be woken by a message sent to it in Claude.app or on the
  phone; a message typed to it there is held and delivered when it is resumed. An offline finished
  session is reached through the wake session instead (REQ-LIFE-03, REQ-LIFE-04), and Baton's own
  stops archive a session on claude.ai until a flagless resume brings it back.
- Claude.app lists Baton's sessions under "Other": its sidebar groups by a session's repository, which a
  `--bg` session in a repository with no remote cannot carry (D-086).
- A lid-close sleep pauses everything and stretches every timer; the tick catches up on wake.
- The Fable-family limit is invisible to every field; it is met by a refused request and a wait.
- A row for a `Remote: yes` session is not a park detector.

### 7.3 Rollback

The installed relay is a copy: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.baton.tick.plist`
stops the tick, and `git checkout <commit> && sh install.sh` reinstalls any earlier version.
No verb deletes anything under `~/.baton/`, and nothing in Baton removes a milestone worktree
(REQ-DISPATCH-03).

---

## 8. Open questions and live proofs

Every item is a fact about the CLI or macOS, not a decision, and is owned by a milestone in
`docs/MILESTONES.md`. Numbers are "Watching a dispatched session"'s.

| Item | Question | Owner |
|---|---|---|
| 36–37 | The Full Disk Access panel accepts `~/.baton/bin/sh`; `cat`, `git`, `jq`, `claude` under it succeed from launchd. | M03 |
| 38 | A background service started by the tick runs sessions that can read `~/Documents`. Fallbacks: grant the `claude` binary too, or never start the service from the tick and escalate `stage: service`. | M03 |
| 39–40 | Settled by M07 on 2.1.270 (D-080): `remoteControlAtStartup: true` in `--settings` connects a `--bg` session and keeps its positional prompt, and a flagless resume restores `--settings` and reconnects the same claude.ai session. The idle `--remote-control` start item 39 asked about is no longer used. | M07 |
| 41 | A session dispatched with `cwd` in a linked worktree receives no isolation instruction and edits in place. | M01 |
| 42 | What a `permissions.ask` rule does under `bypassPermissions`. Until known, none is written. | M05 |
| 43 | `--effort` is restored by a flagless resume (peer session: it is in `respawnFlags` on this Mac). | M04 |
| 44 | A refused model: the session is created and StopFailure fires with `model_not_found`. | M04 |
| 45 | The hash normalisation: a sidecar and the `user` record it produced hash equal. Offline. | M01 |
| 46 | What `--bg --resume` prints on a copy fork, byte for byte, and on which stream. | M04 |
| 47 | What a failed `--bg` prints, on which stream, with which exit code. | M01 |
| 18 | StopFailure fires inside a `--bg` session on a rate limit and what `error_details` holds. | M04 |
| 21 | Whether the supervisor's ~1 h idle stop applies to a session parked at `AskUserQuestion`. | M05 |
