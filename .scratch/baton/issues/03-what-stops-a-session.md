Title: What stops a session, and what happens next
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: —

## Question

Enumerate every way a dispatched session stops being productive before its handover, and
for each class decide two things: is it handled or escalated, and if handled, how. The
classes known so far, with the evidence behind each:

- **Usage limit reached mid-milestone.** This is exactly what cut off the GPT-6 scan-clock
  session on Reclaim; the message names the reset time. Candidate handling: read the reset
  time, then `claude --bg --resume <id>` after it. Whether the transcript or the session
  status exposes this stop is a research question ("Background sessions").
- **Turn ended without a handover.** The model said "done" and stopped, or crashed.
  Candidate handling: resume with a one-line nudge ("print the handover"), or dispatch the
  same milestone again — its kickoff prompt's recovery clause (part 3) resumes from the
  brief's Completion evidence, which is what that clause exists for.
- **A question to the human**, by AskUserQuestion or in prose. Escalate; "Relay or conductor"
  settled that Baton never answers a question.
- **A permission prompt.** Policy belongs to "Where an escalation goes"; here decide only that
  it is a class and whether an unanswered prompt times out into an escalation.
- **Context compaction.** Nothing to do; the session continues.
- **A build or test failure the session keeps circling.** The session's problem — but is
  there a wall-clock or turn cap after which Baton escalates rather than lets it burn?
- **The milestone marked complete with a criterion unmet.** The prompt forbids it; Baton
  cannot verify it. Trust the session, and let `/review-2` catch it, or add nothing.
- **Two parallel sessions take the same D-number** or collide in a shared-spine file
  (`docs/STATUS.md`, `docs/DECISIONS.md`, `Reclaim/AppModel.swift`). Detected at merge, if
  at all. Whose job?
- **Baton itself dies** — the Mac sleeps, restarts, or the process is killed. On return it
  must know what was in flight, which needs the run record (fogged: "State Baton keeps").

Facts for the handling, from the closed research tickets:

- `claude agents --json` carries `cwd, kind, startedAt, id, state, pid, status, waitingFor,
  sessionId, name`; a permission prompt is `status: waiting`, `waitingFor: "permission
  prompt"`, `state: blocked`; a question is `waitingFor: "input needed"`; nothing about the
  last message is exposed (`research/background-sessions.md` §3).
- A usage-limit stop is a synthetic assistant record in the transcript —
  `isApiErrorMessage: true`, `error: "rate_limit"`, `stop_reason: "stop_sequence"` — followed
  by a `system/turn_duration` record; the auto-wait is not offered in background sessions,
  and the binary maps the error to `state: blocked` (§7).
- `claude --bg --resume <uuid> "<text>"` continues under the same id only when no process
  holds the session. An idle-but-alive session counts as running: the command starts a copy
  and prints a `note:` line. So text reaches an idle session only after `claude stop <id>`
  first, or after the supervisor's ~1 h idle stop (§5). `claude stop` keeps the
  conversation; `claude respawn` restarts.
- The `Stop` hook is a native nudge: it receives `last_assistant_message` and
  `transcript_path`, and `{"decision":"block","reason":…}` keeps the session going with the
  reason as its next instruction, capped at 8 consecutive blocks (`research/hooks.md`).
  A turn that ended without a handover can therefore be caught inside the session, before
  it ever goes idle.
- Every session has a transcript at `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`;
  where it goes when the session moves into a worktree is one of the live-experiment items.

Output: a table — class, how it is detected, handled or escalated, the handling.

### Premises settled by "What a project hands to Baton" (2026-09-11)

Two classes changed. A dispatched session carries an injected Stop gate: on a turn ending without
a handover artifact it blocks once with the reason, and on the next stop writes a `stopped`
artifact with reason `no-handover` itself — so "turn ended without a handover" is caught inside
the session and arrives as an artifact, not as silence. A session that cannot finish writes the
artifact itself: `outcome: asking` (question, options, recommendation, an absolute context pointer
inside its checkout; Baton resumes rather than dispatches) or `outcome: stopped` with a reason
from the fixed set — `unfinished`, `blocked` (with `blocked_by`), `merge-failed`, `no-handover`,
`other` — each of which needs its own Baton action, decided here. `api-error` is reserved for an
artifact Baton's own StopFailure hook would write on a usage limit or other API error; decide here
whether that hook writes one. The run record is now "The dispatch log" (the archive of consumed
handovers plus Baton's dispatch log).

### Premises settled by "Relay or conductor" (2026-09-11)

Baton is a relay and embeds no model call, so every handling decided here is a rule over fixed
inputs, and a question is always escalated: an `asking` artifact is the person's by construction;
the tick stops the session on consume, and a ruling resumes it under the same id with the Stop gate
re-injected, never timing out into a decision. Decide here, as rules: for a session cut off by an
API error, whether it is resumed under the same id (transcript on disk, process gone) or
redispatched through the recovery clause, and after how many attempts one becomes the other; the
API-error wait, which is a fixed-interval retry unless the reset time turns out to be a field the
tick can read (the docs put it in message text only — `resets 3:45pm`, varying by limit,
background-sessions §7; StopFailure carries `error` and an optional `error_details`, hooks.md §3),
in which case the wait runs to it — name the interval and the field, because the `caffeinate -i -t`
duration follows whichever is decided; and whether Baton's StopFailure hook writes the `api-error`
artifact. The tick runs every 60 s and reconciles from the dispatch log, `claude agents --json`,
the inbox, the plan file and one git check, so "Baton itself dies" is the normal path: a crash is a
logged in-flight session with no live row, not a special state.

## Comments

### Resolution — 2026-09-11

**Decided: a fixed taxonomy, and for every class a rule over fixed inputs** — an artifact's `outcome`,
`reason` and `error`; a row's `state`, `status` and `waitingFor` from `claude agents --json`; a
transcript's modification time (a stat, never a read); and the dispatch log. Every ending arrives as a
file: the session's own handover, the Stop gate's `no-handover`, or the `api-error` artifact that
Baton's injected StopFailure hook writes. Every class carries two bits — **retry?** and **notify now?**
— so that a wrong label costs one refused request per interval, never a night. A **notification** is a
message Baton keeps working past; an **escalation** parks the lane until a ruling or an edit resolves
it. A **ladder** — resume, then redispatch, then escalate — governs consecutive failure endings on one
milestone; a **wait** spends no attempt.

#### 0. The tick's order of operations

Every tick runs **consume → reconcile rows → waits and resumes → dispatch**: archive every artifact in
the inbox and log its ending; then compare the log's in-flight sessions against the rows (crash, stall,
live prompts); then act on waits due and resumes owed; then dispatch. Stall, crash and the dispatch hold
all test "no artifact in the inbox for this session", which is true only after the inbox has been read
in the same tick. Reverse any two steps and an artifact that landed a second ago reads as a stall or a
crash, and a crash misread resumes a live session, which forks a copy (background-sessions §5). This
order is the spine "The dispatch log" and the tests inherit.

#### 1. The taxonomy

The field's seven classes (prior-art §2.3: transient, usage limit, unrecoverable, question or
permission, stall, crash, ended without a handover) are the spine. Three of the contract's stopped
reasons — `unfinished`, `blocked`, `merge-failed` — stand alone because each needs its own action.
API errors are split by the StopFailure `error` value, one of twelve fixed strings (hooks.md §3).

| Class | Members, and how the tick detects each | Retry | Notify | Handling |
|---|---|---|---|---|
| **Wait** | `api-error` artifact with `error` ∈ `rate_limit`, `billing_error`. `rate_limit` covers the plan limit and a momentary API 429 alike (the one local record carries a 429 body *and* the plan-limit text); only the message text tells them apart, and the tick parses no text. The binary labels `billing_error` "usage limit reached — check plan" (background-sessions §3). | every 15 min | `rate_limit`: after 2 h of waiting; `billing_error`: now | Stop-then-resume with the continue template; spends no attempt; never redispatches (§2d) |
| **Transient** | `api-error` with `error` ∈ `overloaded`, `server_error`, `max_output_tokens`. The CLI retries 5xx and connection errors itself, so a StopFailure means those retries were exhausted. A `server_error` reading "Your computer went to sleep mid-response" is the lid closing, and `status` should show it. | every 15 min; `max_output_tokens` at once | after 1 h | As Wait |
| **Unrecoverable** | `api-error` with `error` ∈ `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `cloud_credential_error`, `model_not_found`, `unknown` | every 15 min | now | As Wait. A fix at the Mac (`/login`, a plan edit) is picked up by the next retry; no `answer` step |
| **Context overflow** | `api-error` with `error: invalid_request` (the only local instances: "Prompt is too long") | redispatch | no | No resume — the same context fails again; redispatch through the recovery clause, taking the ladder's redispatch step; the next failure ending escalates |
| **Question** | (a) an `asking` artifact; (b) a live row with `waitingFor: "input needed"` and no artifact — AskUserQuestion used mid-turn | — | now | (a) stop on consume, escalate, resume with the ruling (settled by "Relay or conductor"); (b) escalate at once, process untouched, never times out |
| **Permission** | a live row with `waitingFor: "permission prompt"` (`status: waiting`, `state: blocked`) | — | now | Escalate at once, process untouched, never stopped, never times out into a denial (§5) |
| **Ended without a handover** | the Stop gate's `stopped` artifact with reason `no-handover` | ladder | at escalation | A failure ending: resume with the finish template; a second from the same attempt redispatches; a third escalates carrying the artifact's detail (the last message) |
| **Crash** | a logged in-flight session with no live process — row absent, or without `pid`, including `state: failed` after a restart — and no artifact in the inbox, observed on two consecutive ticks | ladder | at escalation | `claude stop` if a pid remains; resume under the id at the next tick with the continue template if a transcript exists, else redispatch; a failure ending (§6) |
| **Stall** | a logged in-flight session with a live process, not `waiting`, no artifact in the inbox, and the newest modification time across its transcript and its subagents' transcripts older than 30 min | — | once | Notify with the row's name and `state` and the matching verb; session untouched; resolved by its own artifact (§3) |
| **Long-running** | 6 h since the attempt's latest dispatch-or-resume event in the log | — | once | Notify; session untouched; resolved by its artifact (§4) |
| **Declared stop** | `stopped` with reason `unfinished`, `blocked`, `merge-failed` or `other` | per reason | per reason | §8 |

**Not classes.** Context compaction: the session continues. A milestone marked complete with a
criterion unmet: undetectable by a relay; trusted, and `/review-2` inside the session is the check. Baton's
own death: the tick reconciles from the log, `claude agents --json`, the inbox, the plan file and one
git check ("Relay or conductor" §4), so every tick is a recovery and nothing needs a state of its own.

#### 2. The API-error rules

**(a) The injected StopFailure hook writes the `api-error` artifact, into the inbox.** An API error
fires StopFailure *instead of* Stop (hooks.md §4.1; the binary's own registry text: "Fires instead of
Stop when an API error … ended the turn"), so the Stop gate never sees one and no `no-handover` appears.
StopFailure's output and exit code are ignored, but it can write a file (hooks.md §3). Mechanics:

- Neither hook's payload carries the milestone or the project, so Baton bakes both into the injected
  hook command at dispatch (arguments or environment on the `--settings` hooks block); one mechanism
  serves the Stop gate and the StopFailure hook alike. A hook that cannot name its milestone writes a
  file the tick rejects as orphaned.
- The artifact: `~/.baton/inbox/<milestone>-<session>.json` with `outcome: stopped`, `reason:
  api-error`, `error` (the StopFailure value, the only field a rule keys on), `error_details` when
  present, and `detail` = `last_assistant_message` verbatim, for the person and `status`, never for
  the parser — it is the only place a reset time ever appears ("resets 3:45pm").
- Two endings per session are now normal (an `api-error`, consume, resume, then the real handover
  under the same name), so the archive name carries a suffix: `<milestone>-<session>-<consumed-at>.json`.
  The inbox name stays as the contract fixed it.
- StopFailure is fire-and-forget, so the file may land a beat after the row flips to `blocked`; a
  sixty-second tick absorbs it, and a test must not assert the artifact exists at the instant the row
  changes.

**(b) The split, keyed on `error` alone** — the two-bit table in §1. Nothing under API errors has
retry = no: retrying into a hard block costs a refused request; failing to retry a soft one costs the
night. "Unrecoverable" therefore means *notify now*, not *stop*.

**(c) Resume versus redispatch: the ladder.** An **attempt** is one session's run at a milestone,
numbered per milestone from the first dispatch; a redispatch starts attempt n+1 through the recovery
clause (Reclaim `CLAUDE.md`, part 3: a fresh session resumes only the unfinished part from the brief's
completion evidence); a resume continues the same attempt under the same id — stop-then-resume,
`claude stop <id>` then `claude --bg --resume <uuid> --settings <gate> "<continuation>"`, the path a
ruling takes (background-sessions §5; "Relay or conductor" §7). A **failure ending** is a
`no-handover`, a crash, or a session that cannot be resumed (no transcript on disk, or the resume
refused). The ladder per milestone: failure 1 → resume once; failure 2 → redispatch (attempt n+1);
failure 3 → escalate. Any artifact the session wrote itself resets the count; a wait never counts.
A resume that starts a copy (a `note:` line) has failed to stop the original: `claude stop` the
original before anything else, then log the copy as the session now carrying the attempt under its
new id — two live sessions on one milestone means duplicated work and a merge collision.

**(d) The wait: a fixed interval of fifteen minutes.** Measured (below): no transcript error record
carries a reset time as a field; the one 429's `errorDetails` is the raw body ("try again later"). The
docs place the reset time in message text only (background-sessions §7). The CLI does hold it as a
number — it reads `anthropic-ratelimit-unified-reset` and `retry-after` — but exposes it only in the
status line's stdin JSON, `rate_limits.{five_hour, seven_day, spend_limit}.resets_at`, with **no
per-model window**; "You've reached your Fable limit" is the stop Baton will meet most. So:

- Retry every fifteen minutes, stop-then-resume; limits reset at clock times, so the loss after a
  reset is at most one interval; over a five-hour window that is twenty refused resumes, each one
  error record, one artifact and one log line, no quota.
- Ceilings are when the person hears, never when retries stop: `rate_limit` notifies after two hours
  of continuous waiting, `billing_error` and the unrecoverable set at once, transient after one hour;
  retries continue past every ceiling, up to the weekly horizon, because a weekly limit is legitimate
  to wait for and the person learns by morning that the night went to a limit, not a bug.
- `caffeinate -i -t` is renewed each interval for at most six hours from the wait's first
  `api-error` consume; after that the Mac may sleep and the tick after wake catches up
  (`StartInterval` firings missed during sleep are caught up; "Relay or conductor" §4). A successful
  resume ends the wait; no separate "wait started" event exists.
- **Field later.** The status-line route — a `statusLine` command in the same `--settings` file that
  writes its stdin JSON to `~/.baton/status/<session>.json`, the tick waiting to the earliest future
  `resets_at` of a window at 100 % — is recorded with its moment (the refused resumes annoy, or a
  per-model window appears in the schema) and its proof ("Watching a dispatched session", item 19).

**(e) The continuations.** Two templates, split by what the session must do next, never by what
stopped it; the tick fills the slots from the dispatch log; `<class>` is the StopFailure `error`
value or `process gone`. A ruling is a third text with its own label.

Continue — after `rate_limit`, `billing_error`, `overloaded`, `server_error`, `max_output_tokens`,
and a crash:

> Baton resumed this session after a temporary stop (<class>), not a fault in the work. <milestone>,
> attempt <n>, resume <r>. Continue exactly where the last turn ended. If a tool call was interrupted,
> its result was not received — check the state before repeating it. Do not switch model or work
> around a limit. The handover artifact is still owed.

Finish the close-out — after `no-handover` only:

> Baton resumed this session because its last turn ended without a handover artifact. <milestone>,
> attempt <n>, resume <r>. Finish the close-out now by the method in CLAUDE.md and write
> ~/.baton/inbox/<milestone>-<session>.json, printing it last. Write the outcome that is true:
> complete if the merge is on main, asking if you need a ruling, otherwise stopped with its reason —
> unfinished carries a split.

Why this shape: "<milestone>, attempt <n>" rather than "attempt <n> of <milestone>", which reads as a
fraction; the interrupted-tool sentence says "check before repeating", never "re-run"; the close-out
template asks for the true outcome instead of steering toward `unfinished`, because a session that
forgot the close-out may already have merged; a crashed session was cut off mid-work and must keep
working, not write a stopped artifact. Symphony's rule (prior-art §2.3): a continuation turn sends
guidance, never the original prompt; the "not a fault in the work" clause exists because the model
otherwise works around a limit.

On a **redispatch**, the session learns its attempt from the slot line Baton composes (part 2 is
Baton's paragraph): "This is attempt <n> at this milestone; a previous session may have left completion
evidence in the brief, which the recovery clause covers." The recovery clause keys on the brief, never
on the number.

#### 3. Stall

A **stall** is a logged in-flight session with a live process, not `waiting`, no artifact in the
inbox, whose transcripts have not changed for thirty minutes. The stat covers the newest modification
time across the session's own transcript (found by glob on the session id, contract §4) **and its
subagents' transcripts**: `/review-2` runs two review agents inside every close-out and the parent
sits on one Agent tool call for twenty minutes or more while its own transcript does not move, so
without the subagents the rule reads every close-out as a stall. Locally they are
`~/.claude/projects/<slug>/<sessionId>/subagents/agent-*.jsonl` (42 files across the Reclaim
sessions, the `bugs` and `audit` reviewers among them); hooks.md §3 names `agent_transcript_path`.
Thirty minutes is three times the Bash tool's 600 s cap and past the longest legitimate gap measured
(1,368 s): the file is appended per record and an assistant record lands only when its stream
completes, so the mtime is static for the length of one tool call or one model stream. Wall-clock
alone never marks a stall. The threshold is a Baton default; a plan-file property waits for the first
milestone that asks for its own.

The condition does not depend on `status: busy`, so one rule covers a hung session and an unfired
hook alike: `state: done` with no artifact and static transcripts means "finished a turn, wrote
nothing" — the remedy is `answer <session>` with the finish template, the session alive and its context
intact; `state: blocked` under the same condition means an API error whose StopFailure hook did not
fire — the remedy is the wait path by hand. The notification carries the row's `state` and the matching
verb. The session is never touched; the notification is resolved by the session's own artifact.
Plainly: this rule contains the damage if the hooks do not fire in `--bg` — no finished session is
resumed as a crash — but it is not the design; if the prototype fails that proof, the fix is the
fallback the contract already recorded (`.claude/settings.local.json` written into the session's
worktree), not a Baton that runs on the widened stall rule.

#### 4. Circling

A build or test failure the session keeps retrying is invisible to the stall rule (the transcript
keeps changing) and a relay cannot count turns without reading the transcript, which it never does.
The session's own rule already covers the honest ending: stop at a coherent point with `unfinished`
and a split. Baton adds one default: **six hours since the attempt's latest dispatch-or-resume event
in the log → notify once, session untouched, resolved by its artifact.** The clock starts at the
latest event, not at first dispatch, so a four-hour wait never reads as circling and the row's
`startedAt` resetting on resume is irrelevant — the log is the clock. The cap guards quota, not time:
six hours of a Fable session circling is the expensive night, which is why six and not twelve. A
per-milestone hours field in the plan file waits for the first brief that says it needs ten hours.

#### 5. Permission prompts and in-tool questions

Escalated at once, the process kept alive, never stopped, never timing out into a denial or a
decision. A permission prompt needs attach or Remote Control; stopping the session loses the prompt —
the API requires a tool_result for every tool_use, so a resume must synthesize one and the pending call
is dropped (the binary carries the markers for exactly this). AskUserQuestion used mid-turn
(`waitingFor: "input needed"`, no artifact) has the same shape. The distinction from `asking` holds: an
artifact means the session chose to stop and can be stopped safely; a live prompt means a call is
pending. The supervisor keeps a process paused on a prompt or dialog running (background-sessions §9);
whether its ~1 h idle stop applies to a session waiting at AskUserQuestion is unverified (item 21).

**Prompt lost**, decided now for that unverified case: if a row goes from `waiting` to stopped with no
ruling delivered, Baton logs "prompt lost", and the eventual `answer` resumes the session with the
ruling as text — "the permission you asked for at <time> is granted/denied; the pending call was
dropped, repeat it if still needed" — the continue template's interrupted-tool line, so nothing new is
written. If the prototype shows the idle stop does not apply to a parked prompt, the rule never fires.

**What was asked.** A permission prompt in an unattended session is a policy gap — the allowlist
should already cover what a milestone needs (Reclaim D-030 authorises builds and tests) — and the row
says only `waitingFor: "permission prompt"`. The Notification hook's `permission_prompt` type fires
after the prompt has waited about six seconds with `message`, `title`, `notification_type` (hooks.md
§4.2); an injected Notification hook that writes the prompt's text beside the escalation makes it
specific ("M29 wants to run xcodebuild …") and lets the allowlist be widened by one line the next
morning. That mechanism is "Where an escalation goes"' to design; recorded there as a premise.

#### 6. Crash, and Baton's own death

A **crash** is a logged in-flight session with no live process — the row absent, or present without
`pid` (completed rows carry neither `pid` nor `status`, background-sessions §3), including `state:
failed` after a shutdown (§9: "within 48 hours, the session shows as failed") — and no artifact in the
inbox. The rule acts only when the condition holds on **two consecutive ticks**: the supervisor pauses
sessions when the Mac sleeps and reconnects on wake, and during a wake-up or a supervisor restart a
live session's row can be absent or `failed` for a moment; acting instantly runs stop-then-resume
against a session about to return, and a resume against a live session forks a copy. Two minutes of
latency against a false positive that duplicates a milestone. The first sighting is a log event, because
the tick remembers nothing else. Then: `claude stop <id>` if a pid remains; resume under the id at the
next tick with the continue template (`<class>` = `process gone`) if a transcript exists for the
session id, else redispatch through the recovery clause. A crash is a failure ending on the ladder:
confirmed over two ticks, then resume once, then redispatch, then escalate. Nothing is waited for, so a
crash never enters the retry table.

**Baton dying is not a class.** The tick reconciles from the log, `claude agents --json`, the inbox,
the plan file and one git check and remembers nothing; a sleep, a restart or a killed process leaves the
same inputs for the next tick, so every tick is a recovery.

#### 7. Merge-time collisions and the unmet criterion

Two sessions taking the same D-number or colliding in a shared-spine file is detected at merge, by the
session, if at all; the contract's close-out step (b) then writes `stopped` with reason `merge-failed`
and goes no further. Its class is **merge-failed**: escalate with the detail, no redispatch. It resolves
by a **ruling that resumes the session**, not by a plan-file edit: the person resolving the conflict is
only half the close-out — steps (c), (d) and (e) have not happened, the successor briefs are not
refreshed, no artifact carries dispositions, and marking the milestone complete in the plan file gives
Baton the graph but no advice, so under the two-way rule every eligible successor escalates as omitted.
So: the person resolves the merge and runs `answer <session> "merge resolved; finish the close-out
from step (c)"`; the session (stop-then-resume, gate re-injected) does the refresh, writes the
`complete` artifact with a real `merged_as`, and prints it. The plan-file edit stays as the fallback
when the session is gone and cannot be resumed, with the successor prompts refreshed by hand — the
cost that makes the primary path worth having. Whether Baton detects collisions before merge is
"Dispatching more than one at once"'.

A milestone marked complete with a criterion unmet is not detectable by a relay. It is trusted;
`/review-2` inside the session is the check (Reclaim `CLAUDE.md`, part 7).

#### 8. What each stopped reason makes Baton do

| Reason | Action | Notify |
|---|---|---|
| `unfinished` | Redispatch through the recovery clause, attempt n+1; not a failure. A second consecutive `unfinished` on one milestone escalates carrying both proposed splits: a split is a plan edit, and plan edits are a person's; otherwise a non-converging milestone would redispatch nightly forever. | at the second |
| `blocked` with `blocked_by` | The milestone leaves the in-flight set; it is redispatched (attempt n+1) once the plan file shows the named milestone complete. Silent only while that milestone is in flight or dependency-eligible now — the wait resolves itself; otherwise escalate, because nothing is coming to unblock it. One once-only log event per wait, so `status` shows what a parked lane waits for. | only when the blocker is neither running nor eligible |
| `blocked` without `blocked_by`, or naming nothing in the plan | Escalate with the detail. | now |
| `merge-failed` | Escalate with the detail; no redispatch; resolved by the ruling in §7. | now |
| `no-handover` | The ladder: resume with the finish template; a second from the same attempt redispatches; a third escalates with the detail. | at escalation |
| `other` | Escalate with the detail. | now |
| `api-error` | §1 and §2. | per `error` |

The **attempt counter** lives nowhere but the dispatch log: the attempt is the count of dispatch events
for the milestone; the resume count is the count of resume events for the attempt. Both are derived
on every tick.

#### 9. The dispatch hold

While a `rate_limit` or `billing_error` wait is active for a session on model X, the tick dispatches
nothing on model X; other models are unaffected. `rate_limit` names two different limits — the per-model
limit ("your Fable limit"), for which holding the same model is right, and the session and weekly
limits, shared across all models (background-sessions §7) — and only the text says which. The
deterministic refinement: **if a second model hits `rate_limit` while the first is waiting, the limit is
shared — hold every model until the wait clears**; one refused request is the price of learning which
kind of limit it is, paid once, read from the log rather than from a sentence. When the wait clears on
either, both holds lift. Which lanes carry on across a night is "Dispatching more than one at once"'.

#### Evidence

- **Measured this session**, transcripts under `/Users/danny/.claude/projects/` (read-only): 49
  files contain `isApiErrorMessage`; 42 records have it `true`. By `error`: `authentication_failed`
  ×19 (401, "OAuth access token has expired", one "API key is invalid"), `server_error` ×13 (529
  "Overloaded" ×6; "Your computer went to sleep mid-response" ×5; "Request timed out"; "Unable to
  connect to API"), `unknown` ×5 (400 "Output blocked by content filtering policy"),
  `invalid_request` ×4 ("Prompt is too long" ×3; one malformed `CLAUDE_CODE_OAUTH_TOKEN`),
  `rate_limit` ×1. The rate-limit record (2.1.267, session `5eb95ab6-…`, 2026-09-10T00:19:40Z):
  `apiErrorStatus: 429`, `errorDetails` = `429 {"type":"error","error":{"type":"rate_limit_error",
  "message":"This request would exceed your account's rate limit. Please try again later."},…}`,
  text "You've reached your Fable limit. Run /usage-credits to continue or switch models with
  /model." No record carries a key matching reset, retry-after or rate_limits beyond the common set
  plus `session_id` and `truncatedAfterOutput`; every 529 record's `errorDetails` is null.
- **Subagent transcripts**: `~/.claude/projects/-Users-danny-Documents-Apps-Reclaim/<sessionId>/
  subagents/agent-<id>-<name>-<hash>.jsonl`, 42 files (e.g. `agent-adb1-bugs-…`, `agent-aca1-audit-…`).
- `.scratch/baton/research/hooks.md` §3 (StopFailure: matcher values, payload `error`,
  `error_details`, `last_assistant_message`; output ignored; Stop payload and the 8-block cap), §4.1
  ("API errors fire StopFailure instead"; `stop_hook_active`), §4.2 (`permission_prompt`: fires after
  about six seconds; payload `message`, `title`, `notification_type`), §5 (not verified).
- `.scratch/baton/research/background-sessions.md` §3 (row fields; `state` derivation; the binary's
  error-kind → state map; completed rows without `pid`/`status`), §5 (resume continues in place only
  when no process holds the session; the `note:` copy), §7 (the synthetic record; observed `error`
  values; the docs' message forms; auto-wait not offered in `--bg`), §9 (supervisor keeps a paused
  process running; ~1 h idle stop for a session waiting for the next message; 48 h `failed`; sleep
  preserved and reconnected), §10 (the live list).
- `.scratch/baton/research/prior-art.md` §2.3 ("What stops a session": the taxonomy, LeiShi's
  wording, continuation guidance, `attempt`, backoff and the consecutive-failure limit; "Where an
  escalation goes": parked lanes, no silent retry after ageing out).
- Peer session "Milestone Model Audit", from the 2.1.268 binary's strings [B] and local files [L]:
  StopFailure registry text "Fires instead of Stop…"; headers `anthropic-ratelimit-unified-reset`,
  `-overage-reset`, `retry-after` read and kept as `resets_at`; the status-line schema
  `rate_limits.{five_hour,seven_day,spend_limit}.{used_percentage,resets_at}`, "present only for
  subscribers … after first API response", no per-model window; no cache of reset values anywhere
  under `~/.claude` outside transcripts; `state.json`'s `needs` is a one-line human string;
  `CLAUDE_CODE_MAX_RETRIES` and "Retrying in …" strings (built-in retries exist; count and schedule
  unknown); synthetic markers `[Request interrupted by user for tool use]` and `toolDenialKind`;
  transcript append timing measured per record with an assistant record written at stream end and
  gaps of up to 1,368 s; `max_output_tokens` a hard end of the turn with process and transcript intact.
- `/Users/danny/Documents/Apps/Reclaim/CLAUDE.md`, "What a kickoff prompt contains": part 2 (the
  slot), part 3 (the recovery clause), part 7 (`/review-2`, "do not mark this one complete unless every
  acceptance criterion holds"). "What a project hands to Baton" §5 clause 3: close-out steps (a)–(e).
- "Relay or conductor" §4 (the tick's five inputs; caffeinate `-i -t`; `StartInterval` catch-up), §7
  (a ruling's delivery: stop on consume, `--bg --resume` with `--settings`).
- The Bash tool's documented maximum timeout, 600 s.

#### Deferred, and to which ticket

- The escalation record, the channel, what each notification and escalation carries, the
  `answer` verb's inputs (a ruling; the finish template for a done-idle stall; "merge resolved; finish
  the close-out from step (c)"; the prompt-lost ruling) and the injected Notification hook: "Where an
  escalation goes".
- The log's events (endings, first sighting, resume kind and count, wait retries, once-only
  notifications, `blocked_by` waits, copies, escalations), the archive suffix, the clocks, and the tick
  order as the spine of the recovery test: "The dispatch log".
- The dispatch hold's place beside the per-model cap and the overnight policy; the `blocked_by` wait as
  a dispatch-time state; the plan file's person-editable completion state (the merge-failed fallback);
  the slot line's attempt sentence; a per-milestone hours field, deferred until a brief needs one;
  collision detection before merge: "Dispatching more than one at once".
- Live proofs, items 18–25: "Watching a dispatched session".

#### Unverified

- StopFailure fires inside a `--bg` session, and what `error_details` holds for a `rate_limit`
  (expected: the transcript's `errorDetails` string; no reset field).
- The row after a rate-limit stop in `--bg` (expected `state: blocked`, `status: idle`, no
  `waitingFor`, process alive until the idle stop).
- A `--settings`-injected `statusLine` command runs inside `--bg` and its stdin carries `rate_limits`.
- Which marker a pending tool call receives after `claude stop` at a permission prompt and a resume.
- Whether the supervisor's ~1 h idle stop applies to a session waiting at AskUserQuestion.
- The built-in retry count and backoff before a transient StopFailure.
- How long a live session's row is absent or `failed` during a wake-up or a supervisor restart.
- Whether the 429 response itself refreshes the status line's `resets_at`.

### Observed against by "Watching a dispatched session" (2026-09-11)

Not reopened. Three rules key on signals that behave differently than assumed.

1. **The crash tell is `pid: null`, not `state: failed`.** After `kill -9`, the row read
   `state: "working", status: null, pid: null` for at least 25 s, flipping to `failed` only
   between 25 s and 70 s. A rule waiting for `failed` waits up to a minute. `claude stop` against
   a dead process prints an ordinary `stopped <id>`, so it is never a liveness test.
   A wake from sleep is **not** a confounder: across a real 55 s suspend the row was byte-identical
   either side (`working/busy`, same pid), so sleep never produces the crash signature and the
   two-tick confirmation guards only against a momentary read.
2. **The ruling must be delivered flagless.** `claude stop <id>` then
   `--bg --resume <uuid> --settings <gate> "<ruling>"` does **not** continue the session: any flag
   forks a copy under a new id (`note: … the flags you passed started a copy as ea4b650c`).
   A flagless `--bg --resume <uuid> "<ruling>"` continues under the same id and restores
   `-n`, `--settings`, `--model` and `--permission-mode` by itself, so the Stop gate survives
   automatically. To widen an allowlist, edit the settings file **in place** at the dispatched
   path; the re-issued command then passes.
3. **A fixed wait is not fixed.** A 75 s timer fired 77 s late across a lid-close suspend, and
   `caffeinate -i` does not prevent lid-close sleep. The fifteen-minute stop-then-resume wait and
   the `caffeinate -i -t` renewals both stretch by however long the Mac sleeps.

Also settled: a call parked at a **permission prompt** when `claude stop` arrives receives **no
`tool_result` at all** — an orphaned `tool_use` is the prompt-lost signature — while a call parked
at **AskUserQuestion** receives `[Request interrupted by user for tool use]`, and a stopped one
**can** be answered on resume, so the prompt-lost rule fires only for the permission case.
Subagent transcripts are at `~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.jsonl`
beside an `agent-<id>.meta.json`, as the stall stat assumes.
Unrun and still open: StopFailure on a rate limit (item 18) — no API error occurred.

### Amended by "Dispatching more than one at once" (2026-09-11)

Not reopened. Three rows change, each for a reason found after this ticket closed.

1. **`main-broken` joins the fixed reason set** (§8). Written by the finishing session when its
   merge landed and the project's standing check on `main` then fails and it cannot fix it — the
   check is for the combined tree, the other lane's merge. Scope: project (all dispatch for the
   project held; in-flight lanes run on to their own close-outs); notify now; resolved exactly as
   `merge-failed` is, by a ruling that resumes the session to finish the close-out from step (c),
   and when several lanes cascaded into it each is resumed in turn after the first fix.
2. **`model_not_found` leaves the unrecoverable retry row** (§1, §2b). "A fix at the Mac is picked
   up by the next retry" holds for `/login` and not for a plan edit: a flagless resume restores the
   saved `--model`, so no retry can pick up a corrected `Model` cell. It is now a lane escalation at
   once, no retry, no `answer` — the plan edit is the ruling and the next tick redispatches attempt
   n+1 with the model that the plan now names.
3. **A distant `wait_for` is handled like a distant `blocked_by`** (§8): a handover `wait` whose
   target is neither in flight, eligible nor `done` notifies once, so a lane is not parked for days
   on nobody's decision.

### Amended by "The dispatch log" (2026-09-11)

Not reopened. Writing the derivations for §2c's ladder, §8's reset rule and §9's hold found that two
of them read a fact no event carried, and that two counters were keyed one term short.

1. **Two fields, added because a rule here needs them.** The ladder's reset — "any artifact the
   session wrote itself resets the count" — cannot be computed from a `consumed` event that records
   only `outcome` and `reason`, because the `api-error` artifact is written by the injected
   StopFailure hook and the `no-handover` artifact by the Stop gate, and neither is the session's own
   word. The `consumed` event therefore carries **`written_by` ∈ `session` | `stop-gate` |
   `stop-failure`**. Likewise §2c's copy rule and the failure ending "a session that cannot be
   resumed" need to distinguish three outcomes of one command, so the **`resume` event carries
   `outcome` ∈ `delivered` | `forked` | `refused`**; `forked` is followed by a `copy_fork` event
   naming the original and the new id, and `refused` is a failure ending on the ladder.
2. **The counters key on `(project, milestone, attempt)`, not on the milestone.** §8's "the attempt
   is the count of dispatch events for the milestone" is right for one project and wrong the night
   Baton drives its own repository beside Reclaim, because every project has an M01. The envelope
   carries `project`; the derivation uses it. The session id is the join key to the transcript, the
   archive, the status feed and the prompt sidecars — never a counting key, which is what lets a
   copy fork carry an attempt under a new id without disturbing either count.
3. **One reset rule, shared.** §4's six-hour long-running notification and every other once-only
   key now reset at the same point the ladder does — a `consumed` with `written_by: session`, or
   the attempt's own `dispatch` — plus a takeover. A session that stalls, is noticed, recovers,
   writes an artifact and stalls again in the same attempt notifies twice, because the second stall
   is new information. A wait never re-arms anything, because the `api-error` artifact is not the
   session's own word.
4. **A takeover restarts the long-running clock, not just its key.** §4 measures the six hours from
   the attempt's latest dispatch-or-resume event, and a takeover is neither, so clearing the key
   alone would fire six hours from the old start — possibly minutes after the person typed. The
   `takeover` event is a clock point for that rule.
5. **`prompt-lost` is narrower than §5 wrote it, and the continuation sentence is gone.** Under
   `bypassPermissions` a `--bg` session never holds a permission prompt, so the permission case the
   rule was written for cannot occur; it survives for the `AskUserQuestion` case, where "Watching a
   dispatched session" measured that the call receives `[Request interrupted by user for tool use]`
   and **can be answered on resume**. So nothing is lost but the *resolution path* — the row
   transition that would have unparked the lane by an answer in place can no longer happen, leaving
   `baton answer` as the only route — and the ruling that follows **does not carry** §5's
   dropped-call sentence.
