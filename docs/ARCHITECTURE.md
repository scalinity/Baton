# Baton: architecture

The shapes behind `docs/SPEC.md`: the files, the tick's steps, the injected hooks, the verbs, the
states, the log's events and derivations, the testing seams, and the interfaces each milestone
introduces. Sections 6.1 to 6.5 carry the text of "The dispatch log" §1, §2, §5 and §8 as that ticket
wrote them; the rest consolidates the other resolutions. The vocabulary is `CONTEXT.md`.

---

## 1. Stack

`/bin/sh` with `set -eu`; `jq` 1.7.1 at `/usr/bin/jq` with `-e`; `awk` for the slot line; `git`;
`/Users/danny/.local/bin/claude` 2.1.268; launchd; `/usr/bin/caffeinate`; `osascript` for the Mac
notification. No packages, no build step, no compiler: Baton's own milestone sessions never
compile, and its tests are scripts over fixtures. `shellcheck` is optional. Reversal condition,
recorded by "Relay or conductor" §6: a structure `jq` cannot express, or one file past a few
hundred lines, means a Swift command-line tool for that piece.

---

## 2. Repository layout, and the installed relay

```
/Users/danny/Documents/Apps/Baton
├── CLAUDE.md                 the project's own instructions; implements the contract on Baton
├── CONTRACT.md               the six clauses, once
├── CONTEXT.md                the glossary
├── install.sh                copies bin/ lib/ hooks/ to ~/.baton/bin/, creates ~/.baton/* if absent
├── bin/baton                 the script: verb dispatch only; every verb lives in lib/
├── lib/
│   ├── lock.sh               the mkdir lock; every verb enters through it
│   ├── log.sh                the one append function; the envelope; attempt derivation
│   ├── derive.sh             the fifteen recovery derivations, one function each
│   ├── plan.sh               the plan-file reader: locate tables, read columns by name, parse tokens
│   ├── inbox.sh              consume, provenance, merged_as, brief pointers, archive, reject
│   ├── rows.sh               claude agents --json: crash, stall, live prompts, takeover
│   ├── dispatch.sh           worktree, settings, slot line, sidecar, claude --bg, caffeinate
│   ├── stops.sh              the taxonomy: routing per outcome/reason/error; waits; the ladder
│   ├── escalate.sh           escalation and notification events; the Mac message; answer; allow
│   ├── status.sh             the one view
│   └── templates.sh          the continue, finish and ruling texts; the slot line
├── hooks/
│   ├── stop-gate             the Stop gate
│   ├── stop-failure          writes the api-error artifact
│   └── statusline            writes ~/.baton/status/<session_id>.json
├── tests/
│   ├── run.sh                the standing check: every scenario, one line each
│   ├── shim/claude           the claude shim; date and caffeinate shims beside it
│   ├── payloads/             hook payloads copied from .scratch/baton/prototype/obs/
│   └── scenarios/<name>/     a fixture project, an inbox, a log, a rows file, and expected/
└── docs/
    ├── SPEC.md  ARCHITECTURE.md  DECISIONS.md  MILESTONES.md
    ├── adr/0001-baton-never-calls-a-model.md
    └── milestones/M01.md … M08.md
```

**The installed relay.** `sh install.sh` copies `bin/baton`, `lib/` and `hooks/` to `~/.baton/bin/`
(flat: `baton`, `lib/`, `stop-gate`, `stop-failure`, `statusline`) and creates the state directories
and `config.json` if absent. launchd runs the installed copy and every dispatched session's hooks
point at it, so a merge on `main` changes nothing until a person runs the script: a milestone can
never break the tick that dispatched it, and a broken install is undone by checking out an earlier
commit and installing again (D-018). A launchd job cannot execute anything under `~/Documents`,
which is the other reason the running copy lives under `~/.baton/`.

---

## 3. Files under `~/.baton/` and their shapes

```
~/.baton/
├── bin/                     the installed relay (§2); bin/sh is the granted copy of /bin/sh
├── config.json              Baton's numbers (below)
├── projects/<project>/
│   ├── project.json         {"path": "/Users/danny/Documents/Apps/Reclaim", "plan": "docs/MILESTONES.md"}
│   └── permissions.json     {"permissions": {"allow": [...], "deny": [...]}}
├── settings/<project>-<milestone>.json   the composed --settings file (below)
├── prompts/<session>/<n>.txt             prompt sidecars, n from 1 per session
├── inbox/<milestone>-<session>.json      handover artifacts, .tmp then rename
├── archive/<milestone>-<session>-<consumed-at>.json
├── rejected/<milestone>-<session>.json
├── status/<session_id>.json              the status feed, overwritten per turn
├── log.jsonl                             the dispatch log
├── last-tick                             the tick marker: one line, the at of the tick that completed
├── lock/                                 the mkdir lock; holds pid and at
└── launchd.out, launchd.err              the job's streams
```

**`config.json`**, every value a default in the tick overridable by one line:

```json
{ "cap": 2, "fableReserve": 80, "stallMinutes": 30, "longRunningHours": 6,
  "retryMinutes": 15, "caffeinateMaxHours": 6,
  "models": { "fable": "fable", "opus": "opus", "sonnet": "sonnet", "haiku": "haiku" } }
```

**The composed settings file**, `~/.baton/settings/<project>-<milestone>.json`. The mode rides the
flag (`--permission-mode bypassPermissions`); `defaultMode` is repeated as documentation. Allow and
deny are copied from the project's `permissions.json`; no `ask` rules. Three hooks, each carrying
the project key and milestone as environment on its command line, each pointing at the installed
relay. The prototype's `settings-A.json` and `hooks/` under `.scratch/baton/prototype/` are the
working example this is cut from.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Bash(sh tests/run.sh:*)", "Bash(jq:*)"],
    "deny": [
      "Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)",
      "Bash(osascript * administrator privileges*)",
      "Read(//Users/danny/.baton/log.jsonl)", "Edit(//Users/danny/.baton/log.jsonl)", "Write(//Users/danny/.baton/log.jsonl)",
      "Edit(//Users/danny/.baton/archive/**)", "Write(//Users/danny/.baton/archive/**)",
      "Edit(//Users/danny/.baton/rejected/**)", "Write(//Users/danny/.baton/rejected/**)",
      "Edit(//Users/danny/.baton/prompts/**)", "Write(//Users/danny/.baton/prompts/**)",
      "Edit(//Users/danny/.baton/settings/**)", "Write(//Users/danny/.baton/settings/**)",
      "Edit(//Users/danny/.baton/projects/**)", "Write(//Users/danny/.baton/projects/**)",
      "Edit(//Users/danny/.baton/bin/**)", "Write(//Users/danny/.baton/bin/**)"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "BATON_PROJECT=Baton BATON_MILESTONE=M02 /Users/danny/.baton/bin/statusline"
  },
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "BATON_PROJECT=Baton BATON_MILESTONE=M02 /Users/danny/.baton/bin/stop-gate" }] }],
    "StopFailure": [{ "hooks": [{ "type": "command",
      "command": "BATON_PROJECT=Baton BATON_MILESTONE=M02 /Users/danny/.baton/bin/stop-failure" }] }]
  }
}
```

The exact deny-rule forms for Baton's state paths are M01's to settle from the prototype's working
example; the two classes are fixed ("Where an escalation goes" §3): privilege escalation, and
Baton's own state by named path — a session writes `~/.baton/inbox/` and nothing else under
`~/.baton/`. Under `bypassPermissions` the allow rules allow nothing and cost nothing; they are kept
so that a hand-started session under `default` passing the same file behaves as a dispatched one.

**The status feed**, `~/.baton/status/<session_id>.json`: the statusLine command's stdin, verbatim.
The fields the tick reads: `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`
(`resets_at` in epoch seconds), `context_window.used_percentage`, `cost`, `model`, `session_id`,
`transcript_path`. Telemetry, not history: overwritten, never appended, never archived. A captured
example is `.scratch/baton/prototype/obs/28926e91-26fc-4602-9abd-1ce89cefeb28.json`.

**The lock**: `mkdir ~/.baton/lock` succeeds or the verb exits; the directory holds `pid` and `at`
so a stale lock can be reported with its age. Released on exit; the marker is written after.

---

## 4. The tick, the verbs, the templates and the hooks

### 4.1 The tick's eight steps

Written by "Dispatching more than one at once" §3 over the order "What stops a session" §0 fixed.
Every step reads only the five inputs (the dispatch log, `claude agents --json`, the inbox, the
plan file, one git check) and the status feed; nothing is remembered between ticks.

1. **Self-check.** For every `~/.baton/projects/<project>/project.json`: read the plan file in full
   and parse both tables; run `git -C <path> rev-parse HEAD`. Either failing parks the project
   (project scope, `plan-unreadable` or `plan-unparseable`, the path and what failed) and skips it
   for the rest of the tick. A stale lock is reported before this.
2. **Consume the inbox.** For each `*.json` (never `.tmp`): parse; check provenance (the `session`
   has a transcript found by glob, the `project` is a registered checkout); for `complete`, verify
   `merged_as` is an ancestor of `main` in the canonical checkout; verify each `brief` pointer's
   path and heading on `main`. Reject loudly to `~/.baton/rejected/` with a `rejected` event and a
   lane escalation; otherwise archive as `<milestone>-<session>-<consumed-at>.json` and log the
   `consumed` event. `asking` stops the session at once; `stopped` routes by reason.
3. **Reconcile rows** against the log's in-flight sessions: crash (`pid: null`, confirmed on two
   ticks), stall (`stallMinutes` of unchanged transcripts, the session's and its subagents'), live
   questions (`waitingFor: "input needed"`), a takeover (a typed record the log did not send), and
   the gap report. For `Remote: yes` sessions the row is not a park detector: parks are
   artifact-borne only, and an unanswered phone prompt surfaces as a stall.
4. **Waits and resumes.** Retries due (`retryMinutes`); rulings queued by `answer`; `merge-failed`
   and `main-broken` resumes; the `caffeinateMaxHours` bound. Every resume is flagless.
5. **Compute eligibility per project from the plan.** A milestone is eligible when every id in
   `Depends on` reads `done`, its `Status` is blank, and no uncleared gate holds it. `held` and an
   uncleared gate are the same state to the tick.
6. **Intersect with the handover's dispositions.** For each eligible milestone, the disposition in
   force is the one in the newest archived `complete` handover of that project that lists it:
   `run` → a candidate; `wait` → honoured while every `wait_for` is in flight, eligible or done,
   dispatched the moment all read `done`, a distant `wait_for` notifying once; `held` on a gate the
   plan shows cleared → the plan wins, dispatch, `plan_override`; `run` on a milestone the plan
   holds → the plan wins, withheld, `plan_override`. Exactly two things escalate, lane scope, by
   milestone name: a `run` the plan makes ineligible (`disagreement`) and a plan-eligible milestone
   no archived handover lists (`omitted`).
7. **Apply the holds, then the cap.** Drop candidates on a model with an active `rate_limit` or
   `billing_error` wait (every model once a second model is limited). Drop `fable` candidates while
   the freshest status file's `seven_day.used_percentage` is at or above `fableReserve`. Count in
   flight: every logged session with a live row, plus every parked lane holding a live prompt;
   stopped `asking` sessions do not count. Dispatch while the count is below `cap`, in this order:
   the handover's `eligible[]` order within a project; across projects, the project with fewer in
   flight first; then plan row order.
8. **Dispatch**, per candidate:
   - `git -C <path> worktree add ../<Project>-M<nn> -b m<nn> main`; if the worktree exists, reuse it
     and log the reuse with the commit it stands at.
   - Compose the settings file at `~/.baton/settings/<project>-<milestone>.json` (§3).
   - Read the kickoff prompt from the brief on `main` and replace part 2 whole with the slot line
     (§4.3); write the body to `~/.baton/prompts/<session>/<n>.txt` and hash it.
   - Run, with the worktree as `cwd` and `LC_ALL` set:
     `claude --bg -n "Baton · <project> · <milestone>" --model <Model> [--effort <Effort>]
     --permission-mode bypassPermissions --settings <file> "<prompt>"`; parse `backgrounded · <id>`
     from stdout. No line → `dispatch_failed` (§6.2).
   - `Remote: yes`: the same command with `--remote-control` and no prompt, `claude stop <id>`, then
     a flagless `claude --bg --resume <uuid> "<prompt>"`.
   - Read the row's `pid` from `claude agents --json`; start `caffeinate -i -w <pid>` detached.
   - Log the `dispatch` event.

Then the marker, after the lock is released.

### 4.2 The verbs

| Verb | Does | Side effects |
|---|---|---|
| `baton tick` | the eight steps for every registered project | the log, the archive, dispatches, the marker |
| `baton answer <milestone \| project/milestone> <ruling \| n>` | resolves against parked lanes across all projects; one match: `claude stop <id>`, then a flagless resume with the ruling label; `"continue"` is also the takeover hand-back | `resolution`, `resume` events |
| `baton status` | the one view (§5.3), last tick first, whole file | none |
| `baton plan <project>` | the graph as the tick sees it; validates every `Model` cell; lists widenings | none |
| `baton dispatch <project> <milestone>` | step 8 alone, by hand, after checking eligibility and that no live row carries the milestone | worktree, settings, sidecar, session, `dispatch` event |
| `baton allow <milestone> '<rule>' [--resume]` | writes the rule to `permissions.json` and the dispatched settings file in place; refuses an `ask` rule; `--resume` stops and flaglessly resumes | `widening` event; a `resume` event |

Every verb enters through the lock. `status` and `plan` write nothing.

### 4.3 The texts

**The slot line**, composed at dispatch, replacing the paragraph that begins `WHAT ELSE IS IN
FLIGHT.` in the brief's prompt — the only paragraph touched. Example:

> WHAT ELSE IS IN FLIGHT. You are working in /Users/danny/Documents/Apps/Reclaim-M19 on branch
> m19; the canonical checkout is /Users/danny/Documents/Apps/Reclaim — merge there at close-out
> and refresh there. Also in flight: M28 (worktree Reclaim-M28, brief docs/milestones/M28.md).
> Stage only your own paths; never git add -A. This is attempt 2 at this milestone; a previous
> attempt left work on this branch at 1a2b3c4, and the brief may hold completion evidence, which
> the recovery clause covers. Do not start the milestone after this one.

The attempt sentence appears on attempt 2 and later; "Also in flight" lists worktree names and
brief paths, never absolute paths.

**Continue** — after `rate_limit`, `billing_error`, `overloaded`, `server_error`,
`max_output_tokens`, and a crash (`<class>` = the StopFailure `error` or `process gone`):

> Baton resumed this session after a temporary stop (<class>), not a fault in the work. <milestone>,
> attempt <n>, resume <r>. Continue exactly where the last turn ended. If a tool call was
> interrupted, its result was not received — check the state before repeating it. Do not switch
> model or work around a limit. The handover artifact is still owed.

**Finish the close-out** — after `no-handover` only:

> Baton resumed this session because its last turn ended without a handover artifact. <milestone>,
> attempt <n>, resume <r>. Finish the close-out now by the method in CLAUDE.md and write
> ~/.baton/inbox/<milestone>-<session>.json, printing it last. Write the outcome that is true:
> complete if the merge is on main, asking if you need a ruling, otherwise stopped with its reason —
> unfinished carries a split.

**The ruling label** — delivered by `baton answer`:

> Baton resumed this session to deliver a ruling. <milestone>, attempt <n>, resume <r>. You asked
> at <time>: <question>. The ruling below is decided: do not re-open it, do not ask again, and do
> not weigh alternatives against it.
>
> <ruling verbatim>
>
> Continue from where the last turn ended. The handover artifact is still owed.

The merge-failed and main-broken rulings are the same label around "merge resolved; finish the
close-out from step (c)" or "main fixed; finish the close-out from step (c)".

**The copy-fork `note:` line**, from the binary's strings (peer session, 2026-09-11). Variants:
`note: session <X> is already running in the background, so this started a copy as <Y>.`;
`note: session <X> is open in another Claude Code process, so this started a copy as <Y>.`;
`note: session <X> is running, so this started a copy as <Y>.`;
`note: background session <X> keeps its own saved options, so the flags you passed started a copy as <Y>`;
`note: could not read the saved state of background session <X>, so this started a copy …`;
`note: another background session already uses the id <X>, so this started a copy as <Y>.`;
`note: could not check whether session <X> is running, so this started a copy as <Y>.`;
and a generic `note: started a copy of that conversation as <Y>.` **The parse rule that survives
every variant**: the new id is the 8-hex token after `started a copy as `; the original is the token
after `session ` or `background session `. Success prints
`note: woke session <id> with its saved options (-n, --settings, --model, --permission-mode)`. Which
stream the note goes to is live item 46; capture both.

### 4.4 The injected hooks

Three, from `--settings`, each a shell script under `~/.baton/bin/` taking `BATON_PROJECT` and
`BATON_MILESTONE` from its environment and the hook payload on stdin. The prototype's
`.scratch/baton/prototype/hooks/{stop-gate,stop-failure,statusline}.sh` are the working examples
and the captured payloads under `obs/` are their fixtures.

- **`stop-gate`** (`Stop`). Reads `session_id`, `stop_hook_active`, `last_assistant_message`,
  `background_tasks`. If `background_tasks[]` is non-empty: exit 0 (a session waiting on its own
  subagent is not done). If `~/.baton/inbox/<milestone>-<session_id>.json` exists: exit 0. Else if
  `last_assistant_message` holds a `baton` fence that parses and names this session: write it into
  the inbox and exit 0. Else if `stop_hook_active` is false: print
  `{"decision":"block","reason":"…write the handover artifact…"}`. Else: write a `stopped`
  artifact with reason `no-handover` and `detail` = `last_assistant_message`, and exit 0. The block
  reaches the model as a `user` record prefixed `Stop hook feedback:`.
- **`stop-failure`** (`StopFailure`, fires instead of `Stop` on an API error). Writes
  `~/.baton/inbox/<milestone>-<session_id>.json` with `outcome: stopped`, `reason: api-error`,
  `error`, `error_details` when present, `detail` = `last_assistant_message`. Output and exit code
  are ignored by the CLI; fire-and-forget, so the file may land a beat after the row flips.
- **`statusline`** (`statusLine`). Writes stdin whole to `~/.baton/status/<session_id>.json`
  (`.tmp` then rename) and prints `baton <milestone>` for the status line.

Hooks never write the log. Each writes a per-session file.

---

## 5. States

### 5.1 The states a lane can be in

Derived every tick from the log and the rows; nothing stores them.

| State | Derived from | Baton's stance |
|---|---|---|
| **eligible** | the plan: dependencies `done`, `Status` blank, no uncleared gate | a dispatch candidate, subject to the dispositions, the holds and the cap |
| **held** | `Status: held` or an uncleared gate | never dispatched; shown as waiting on a person |
| **in flight** | derivation 1: a `dispatch` with no later `complete` consume and no later `dispatch`, with a live row | watched: crash, stall, long-running, takeover |
| **waiting** | derivation 5: an `api-error` consume with no later session-written consume | stop-then-resume every `retryMinutes`; the model held |
| **parked** | derivation 2: an `escalation` with no later `resolution` | nothing acted on; unparks by ruling, answer in place, or edit |
| **taken over** | derivation 3: the newest typed record is not Baton's | nothing acted on; artifacts still consumed; counts against the cap |
| **blocked, silent** | a `blocked` consume whose `blocked_by` is in flight or eligible | redispatched when the blocker reads `done` |
| **done** | `Status: done` | pruned worktree once `merged_as` is verified |

### 5.2 The stops taxonomy

The two bits per class: retry, and notify now. ("What stops a session" §1, amended.)

| Class | Detected by | Retry | Notify | Handling |
|---|---|---|---|---|
| Wait | `api-error`, `error` ∈ `rate_limit`, `billing_error` | every `retryMinutes` | `rate_limit` after 2 h; `billing_error` now | stop-then-resume, continue template; spends no attempt |
| Transient | `error` ∈ `overloaded`, `server_error`, `max_output_tokens` | every `retryMinutes`; `max_output_tokens` at once | after 1 h | as Wait |
| Unrecoverable | `error` ∈ `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `cloud_credential_error`, `unknown` | every `retryMinutes` | now | as Wait; a fix at the Mac is picked up by the next retry |
| Refused model | `error: model_not_found` | none | now | lane escalation; the plan edit is the ruling; next tick redispatches attempt n+1 |
| Context overflow | `error: invalid_request` | redispatch | no | the ladder's redispatch step; the next failure ending escalates |
| Question | `asking` artifact; or a live row `waitingFor: "input needed"` with no artifact | — | now | (a) stop on consume, escalate, resume with the ruling; (b) escalate at once, process untouched |
| Ended without a handover | `no-handover` artifact | ladder | at escalation | resume with the finish template; then redispatch; then escalate |
| Crash | row absent or `pid: null`, no artifact, two consecutive ticks | ladder | at escalation | stop if a pid remains; resume with continue if a transcript exists, else redispatch |
| Stall | live row, not `waiting`, no artifact, transcripts unchanged for `stallMinutes` | — | once | notify with the row's `state` and the verb; untouched |
| Long-running | `longRunningHours` since the attempt's latest dispatch, resume or takeover | — | once | notify; untouched |
| Declared stop | `unfinished`, `blocked`, `merge-failed`, `main-broken`, `other` | per reason | per reason | REQ-STOP-12 |

### 5.3 What `status` prints, in order

1. the last tick, from the marker; the hardware condition (lid open or clamshell) on the same line;
2. project-scope parks — all dispatch held for a project, with the class and the verb;
3. parked lanes — `<project>/<milestone> · <class> · <the one line the person read> · <the verb>`;
4. taken-over lanes — `taken over at <time>; hand back with baton answer <M> "continue"`;
5. waits and holds — the `error`, the elapsed time from `since`, the next retry, each hold with its
   model and cause;
6. in flight — `<project>/<milestone>`, session, model, attempt, elapsed since the latest
   dispatch-or-resume event, and any live notification (`stalled`, `<n> h`);
7. silent waits — a `blocked_by` whose blocker is in flight or eligible, and a distant `wait_for`;
8. an open gap, if one was reported and nothing has cleared it.

Whole file, every time; no flags; no denials line.

---

## 6. The dispatch log

One append-only JSONL at `~/.baton/log.jsonl`, eighteen event kinds over a five-field envelope,
prompt bodies in per-session sidecars the events point at and hash, every count derived over
`(project, milestone, attempt)`. Sections 6.1, 6.2, 6.4 and 6.5 are "The dispatch log" §1, §2, §5
and §8, copied.

### 6.1 The envelope

Every event is one JSON object on one line, with `at` and `kind` always present.

| Field | Always? | Value |
|---|---|---|
| `at` | yes | ISO 8601 **with offset** (`2026-09-11T23:14:02+01:00`) |
| `kind` | yes | one of the eighteen in §6.2 |
| `project` | when the event has one | the project key: the basename of the canonical checkout |
| `milestone` | when the event has one | the plan file's `ID` cell |
| `session` | when the event has one | the `sessionId` — `CLAUDE_CODE_SESSION_ID`, the row's `sessionId`, the transcript's filename |
| `attempt` | when the event belongs to one | the integer the rule below derives |

**A field the event does not have is absent, never null.** A rule keying on a null fails silently;
one keying on an absent field fails at `has()`, in the test. Three kinds carry no `session` at all
(`dispatch_failed`, `self_check_failed`, and a `hold` whose cause is `fableReserve`), and two carry
no `milestone` (`self_check_failed`, `hold`).

**`at` is Baton's own clock and nothing else.** Every timestamp Baton copies out of Claude Code —
an artifact's `written_at`, `rate_limits.*.resets_at` in epoch seconds, a transcript record's
`timestamp` in UTC with milliseconds — is carried in exactly the form it arrived, in a field named
for what it is. The schema converts between them nowhere. The offset is on Baton's own clock because
a person reads the log and because usage limits reset at wall-clock times.

**`attempt` is stamped for the reader and derived for the rule.** The authority is the count of
`dispatch` events for the `(project, milestone)`; the tick computes that count before it dispatches,
so writing it onto the event costs nothing and makes "the events of attempt 3" a filter instead of a
replay of the file. If a stamp ever disagrees with the count, **the count wins** and the
disagreement is a bug the log itself makes visible. The resume count is the same shape: stamped on
the `resume` event as `resume`, derived as the count of that attempt's resumes. Neither number is
stored anywhere but here — no counter file, no field on an artifact, no state directory.

**The counting key is `(project, milestone, attempt)`.** Every target project has an M01, and Baton
drives its own repository beside Reclaim, so a count keyed on the milestone alone merges two
projects' attempts into one the first night both run. The envelope already carries `project`; the
derivations use it. `baton answer <milestone>` refusing on ambiguity and printing
`<project>/<milestone>` candidates is the person-facing half of the same fact.

**After a copy fork the count is still right, and these are the events that make it so.** A copy
fork happens on a resume, not a dispatch: the tick issues a flagless `claude --bg --resume <uuid>
"<text>"`, the CLI prints a `note:` line naming a new id, and the original — which was supposed to
have been stopped — is stopped first. Two events must exist:

1. the **`resume`** event, addressed to the original id, with `outcome: forked`; and
2. a **`copy_fork`** event carrying `from_session` (the original), `session` (the new id) and the
   `note` line verbatim.

The attempt count is unchanged because a fork writes no `dispatch` event, so the new id carries
attempt *n*. The resume count is right because resumes are counted per attempt whatever id they
named. And **the session currently carrying an attempt** is the newest of that attempt's
`dispatch.session` and every later `copy_fork.session` for the same `(project, milestone, attempt)`
— the one sentence every derivation that needs a live session id goes through.

### 6.2 The event table

Eighteen kinds. Fields listed are those beyond the envelope.

| Kind | Fields | Which rule reads it | Once-only key |
|---|---|---|---|
| `dispatch` | `name`, `model`, `effort`, `remote`, `worktree`, `branch`, `worktree_reused`, `worktree_commit`, `settings`, `prompt_path`, `prompt_sha256` | the attempt count; the ladder's reset point; in flight; the long-running clock; the takeover candidate set; the cap; **the model actually run**, for grading after the fact | — |
| `dispatch_failed` | `stage` (`worktree`\|`settings`\|`prompt`\|`launch`\|`service`), `detail`; no `session` | the second consecutive for a `(project, milestone)` escalates, lane scope; `stage: service` escalates, project scope | — |
| `consumed` | `outcome`, `reason` or `error`, `written_by` (`session`\|`stop-gate`\|`stop-failure`), `merged_as`, `blocked_by`, `archive` | every ending's routing; the ladder's reset; the notification keys' reset; the terminal test for in flight; the wait's start before its first retry | — |
| `rejected` | `path` (under `~/.baton/rejected/`), `reason` | the lane escalation that follows a rejection (the log is the record, so no sidecar) | — |
| `resume` | `resume_kind` (`continue`\|`finish`\|`ruling`), `resume`, `class`, `outcome` (`delivered`\|`forked`\|`refused`), `prompt_path`, `prompt_sha256` | the resume count; the ladder (`refused` is a failure ending); the long-running clock; the takeover candidate set | — |
| `copy_fork` | `from_session`, `note` | the session currently carrying an attempt | — |
| `wait_retry` | `error`, `since`, `retry` | the dispatch hold; the 1 h and 2 h notification ceilings; the six-hour `caffeinate -i -t` bound; `status`'s next-retry line | — |
| `crash_sighting` | `pid` (null), `state`, `sighting` (1 or 2) | the two-tick confirmation before a crash is acted on | — |
| `takeover` | `first_unmatched_at`, `first_unmatched_uuid`, `typed_count` | stop acting on the lane; restart the long-running clock; reset the attempt's notification keys | per session |
| `escalation` | `class`, `scope` (`lane`\|`project`), `carries`, `channel` | the parked-lane derivation; `status`; `baton answer`'s resolution | — |
| `resolution` | `how` (`ruling`\|`answered in place`\|`edit`), `escalation_at` | the unpark | — |
| `notification` | `class`, `key`, and the class's own fields | the once-only rule | per `(project, milestone, attempt, class)`, with the class's extra term where it has one |
| `hold` | `model` (or `all`), `cause` (`rate_limit`\|`billing_error`\|`fableReserve`), `reading`, `status_file` | the dispatch hold; the `fableReserve` guard | per `model` and `cause` |
| `hold_lifted` | `model`, `cause` | closes the hold | — |
| `widening` | `rule`, `permissions_file` | `baton plan`'s provenance of allow rules | — |
| `plan_override` | `direction` (`dispatched_over_held`\|`withheld_over_run`), `gate`, `cleared_by` | `status` showing the plan doing its job; never an escalation | — |
| `worktree_pruned` | `worktree`, `merged_as` | — (the record of a destructive act) | — |
| `self_check_failed` | `stage` (`read`\|`parse`\|`git`), `path`, and for `parse` also `table`, `row`, `cell`; `detail` | the project-scope park, every tick, for each registered project | — |

**Escalation classes.** Lane: `asking`, `question`, `ladder-end`, `unfinished-twice`, `blocked`,
`merge-failed`, `other`, `disagreement`, `omitted`, `model_not_found`, `dispatch-failed`. Project:
`plan-unreadable`, `plan-unparseable`, `main-broken`, `baton-unhealthy`.

**Notification classes.** `rate_limit`, `billing_error`, `unrecoverable`, `transient`, `stall`,
`long-running`, `blocked_by`, `distant_wait_for`, `prompt-lost`, `gap`, `takeover-silent`. Three
carry an extra key term beyond `(project, milestone, attempt, class)`: `distant_wait_for` keys also
on the handover and the named milestone; `blocked_by` on the named blocker; `gap` on the marker
value the gap was measured against, so one outage reports once.

##### Footer: what is a derivation, what folded, and what is gone

- **The gap report is a derivation, not an event.** The gap is `now` minus `~/.baton/last-tick`;
  whether it is *reported* is the log's question — only when a lane was in flight, waiting or
  parked during it, which the log knows because it knows what was in flight. The report itself is a
  `notification` with class `gap`.
- **The cap queue is a derivation, not an event.** The order when the cap bites — the handover's
  `eligible[]` order within a project, then the project with fewest in flight, then plan row order
  — is computed from the plan, the archive and the rows, and needs no record.
- **A `blocked_by` wait needs no kind of its own.** The `consumed` event with `reason: blocked`
  already carries `blocked_by`, which is what `status` reads; the once-only notification is a class.
- **`main-broken` and `model_not_found` are not kinds.** Each arrives as a `consumed` event — the
  first a `stopped` reason, the second a StopFailure `error` — and each is followed by an
  `escalation` whose `class` names it. One ending, one event; the escalation is the second.
- **`omitted` and the plan-versus-advice disagreement are escalation classes**, not kinds: they are
  the exactly two things step 6 of the dispatch algorithm escalates, both by milestone name.
- **The permission-denial event is dropped, and this is why.** "Where an escalation goes" §4–5
  designed a `PermissionDenied` event carrying `tool_name`, `tool_input` and `reason`, and two
  once-only notification keys read from it: three denials sharing a command head within one attempt
  (per attempt and head), and the classifier failing rather than judging (per attempt). The hook is
  **auto-mode only**, and "Watching a dispatched session" measured that a `--bg` session cannot run
  in `auto` — `--permission-mode auto` is accepted and the session records `default`, established
  three ways — after which "Dispatching more than one at once" §4 chose `bypassPermissions` and
  dropped the hook from the `--settings` file. Under the mode Baton dispatches with, **nothing can
  ever write a denial event**, so the kind, both notification keys and `status`'s denials line are
  not in this schema. **Revival condition**: a dispatch that chooses `default` (which no plan-file
  field selects today), or `auto` becoming reachable in `--bg`. The `widening` event is unaffected —
  `baton allow <milestone> '<rule>'` still writes a rule and still logs its provenance; what it
  loses is the half that read `permission_suggestions[]` off a permission escalation, because there
  are none.
- **The `permission` escalation class is dropped for the same reason.** Under `bypassPermissions`
  nothing prompts, so a row can never read `waitingFor: "permission prompt"` and the class cannot
  occur. Same revival condition. **`question` stays** — `AskUserQuestion` is a tool waiting for
  input, not a permission, and a live row reading `waitingFor: "input needed"` was observed
  repeatedly in the prototype. **`prompt-lost` stays, for the question case only**, and it now means
  something narrower than it did: a row that went from `waiting` to stopped with no ruling delivered
  has lost its *resolution path* — the row transition that would have unparked the lane by an
  answer in place can no longer happen, so `baton answer` is the only route. It has **not** lost the
  call: a call parked at `AskUserQuestion` when the session stops receives
  `[Request interrupted by user for tool use]` and **can be answered on resume**. So the ruling that
  follows a `prompt-lost` notification **does not carry** the dropped-call sentence.

### 6.3 Prompt sidecars and the takeover rule

Prompt bodies live in `~/.baton/prompts/<session>/<n>.txt`, `<n>` counting from 1 per session in
delivery order; the event carries `prompt_path` and `prompt_sha256`. For each in-flight lane the tick
locates the current session's transcript by glob — `~/.claude/projects/*/<session>.jsonl` — and
compares its newest typed record (`type == "user"`, `promptSource == "typed"`, `isMeta` not true,
`isCompactSummary` not true; compaction appends and never rewrites) against every `dispatch` and
`resume` sidecar for the `(project, milestone)` — not the session alone, because a copy fork's
transcript is a byte-for-byte copy of its parent's rewritten to the new id. The record's text is
normalised and hashed the same way the sidecar was; the normalisation is checked once, offline,
against the prototype's captured pair (live item 45). **The lane is taken over exactly while the
newest typed record is one Baton did not send.** If only an `.orphaned-<ts>-<hash>.jsonl` sibling
exists, the lane escalates with the sibling's path rather than being scanned.

### 6.4 The recovery derivations

Each is one sentence over §6.2's table; M01's and M02's tests are these sentences turned into
fixtures.

1. **In flight, per project.** Every `dispatch` whose `(project, milestone, attempt)` has no later
   `consumed` with `outcome: complete` and no later `dispatch` for the same `(project, milestone)`,
   resolved through the fork chain to its current session (§6.1), **intersected with rows in
   `claude agents --json` that carry a `pid`**.
2. **Parked, and why.** Every `escalation` with no later `resolution` naming its `at`. Its `scope`
   says whether the lane or every lane of that project is held; its `class`, the first line of its
   `carries`, and the verb for that class are what `status` prints and what `baton answer` resolves
   against across projects.
3. **Taken over.** Every in-flight lane whose transcript's newest typed record is not one Baton sent
   (§6.3), which is a live read each tick; the `takeover` event is the record and the notification
   key, not the state.
4. **Which handovers were consumed.** **The archive is the answer, not the log.** Consumption is
   idempotent *by the move*: a file still in `~/.baton/inbox/` has not been acted on, and one in
   `~/.baton/archive/` has. The log records what each consumption *decided*. The join is by field,
   not by reconstruction: the `consumed` event's `archive` holds the archived filename **verbatim**,
   and the event's own `at` is that `<consumed-at>`; a reader joins on the field and never rebuilds
   the name from parts.
5. **Each active wait and its first-failure time.** The newest `consumed` with `reason: api-error`
   for a `(project, milestone, attempt)` that has no later `consumed` with `written_by: session` and
   no later `dispatch`. Its start is the `since` its `wait_retry` events carry — and **before the
   first retry exists, `since` is that `consumed` event's own `at`**. The next retry is the newest
   `wait_retry`'s `at` plus `retryMinutes`, **read from the last retry rather than extrapolated from
   the first**, because a lid-close sleep stretches every interval.
6. **Each hold.** Every `hold` with no later `hold_lifted` for the same `model` and `cause`. A
   `rate_limit` or `billing_error` hold lifts when its wait clears; a `fableReserve` hold lifts when
   the freshest status file's `seven_day.used_percentage` falls below the reserve.
7. **Each caffeinate holder to re-arm.** For each in-flight lane, `caffeinate -i -w <pid>` against
   the pid in the **current row** — the log stores no pid, because a supervisor restart gives the
   session a new one. For each active wait, `caffeinate -i -t` for the remainder of
   `caffeinateMaxHours` measured from its `since`.
8. **The last tick.** `~/.baton/last-tick`, read as a file, not derived from the log.
9. **The ladder's position.** For a `(project, milestone, attempt)`, the count of failure endings
   since the newest reset point, where a **failure ending** is a `consumed` with `reason:
   no-handover`, the second `crash_sighting` of a confirmed crash, or a `resume` with `outcome:
   refused`; and a **reset point** is a `consumed` with `written_by: session` or the attempt's own
   `dispatch`. One resume, then one redispatch, then escalate.
10. **The attempt number**: the count of `dispatch` events for the `(project, milestone)`. **The
    resume count for an attempt**: the count of its `resume` events with `outcome` `delivered` or
    `forked`.
11. **Whether a once-only key is spent.** A `notification` with that class and key exists at or
    after the attempt's newest reset point — **the same reset the ladder uses**, plus a `takeover`.
    An artifact the session wrote itself demonstrates it came back, so what it does next is new
    information; an `api-error` artifact is written by the hook and not by the session, so a
    fifteen-minute wait cycle never re-arms anything.
12. **The dispatch hold**: derivation 6. No dispatch on a model with an active `rate_limit` or
    `billing_error` hold; on every model once a second model is held.
13. **`baton answer <milestone>`**: derivation 2, filtered by milestone across every project. Exactly
    one match acts; more than one refuses and prints `<project>/<milestone>`; none refuses with
    "nothing is waiting on `<milestone>`".
14. **`baton plan`'s provenance of allow rules**: every `widening` for the project, newest first,
    each naming the rule and the milestone that earned it.
15. **The gap**: `now` minus `~/.baton/last-tick`. Reported as a `notification` with class `gap`
    only when derivations 1, 2 or 5 show a lane was in flight, waiting or parked during it. Keyed on
    the marker value it was measured against, so one outage reports once.

**The recovery test is idempotence**: tick twice against the same log, agents listing, inbox, plan
file and git check, and the second tick changes nothing. Every derivation above is a pure function
of those inputs.

### 6.5 Example lines

A dispatch, an escalation and its resolution, and a takeover — the fixture to copy. Wrapped here
for reading; each is one line in the file.

```json
{"at":"2026-09-11T23:14:02+01:00","kind":"dispatch","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "name":"Baton · Reclaim · M19","model":"fable","remote":false,
 "worktree":"/Users/danny/Documents/Apps/Reclaim-M19","branch":"m19","worktree_reused":false,
 "settings":"/Users/danny/.baton/settings/Reclaim-M19.json",
 "prompt_path":"/Users/danny/.baton/prompts/7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9/1.txt",
 "prompt_sha256":"4f9a1c07b3e5d8206f1a4c9b7e02d35a8c6f1b490d2e7a3c5b8f0d1e6a4c9b72"}
```

```json
{"at":"2026-09-12T02:41:18+01:00","kind":"escalation","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "class":"asking","scope":"lane",
 "carries":{"question":"Should ReclaimCore expose FileSizeFormatter, or keep it internal and duplicate it in the app?",
            "options":["expose","internal"],"recommendation":"expose"},
 "channel":["notification"]}
```

```json
{"at":"2026-09-12T08:02:55+01:00","kind":"resolution","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "how":"ruling","escalation_at":"2026-09-12T02:41:18+01:00"}
{"at":"2026-09-12T08:02:56+01:00","kind":"resume","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "resume_kind":"ruling","resume":1,"outcome":"delivered",
 "prompt_path":"/Users/danny/.baton/prompts/7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9/2.txt",
 "prompt_sha256":"91b3e7c2a04f6d18b5e9c3a7f60d2b48e1c5a9037d6b2e8f4a0c1d7b39e5f8a26"}
```

```json
{"at":"2026-09-12T09:17:03+01:00","kind":"takeover","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "first_unmatched_at":"2026-09-12T09:15:44.812Z",
 "first_unmatched_uuid":"b67d02df-c685-4a56-ada2-faa626f97905","typed_count":2}
```

Note the two clocks side by side in the last one: `at` is Baton's, with offset; `first_unmatched_at`
is the transcript record's own `timestamp`, carried exactly as it arrived.

---

## 7. Testing seams and the fixture layout

**Seams**, one variable per outside thing, read once at the top of `bin/baton` and the hooks:

| Variable | Default | The shim's role |
|---|---|---|
| `BATON_CLAUDE` | `/Users/danny/.local/bin/claude` | `--bg` prints `backgrounded · <id>` (and `Starting background service…` on stderr when told to) and later writes an inbox artifact from the scenario; `agents --json` answers from `rows.json`; `stop` and `--bg --resume` append their argv to `calls.log`; a scenario can make `--bg --resume` print a `note:` copy-fork line |
| `BATON_DATE` | `date` | prints the scenario's `now`, advanced per tick by the runner |
| `BATON_CAFFEINATE` | `/usr/bin/caffeinate` | appends its argv to `calls.log` and exits |
| `BATON_HOME` | `~/.baton` | the scenario's own state directory |

**Scenarios** under `tests/scenarios/<name>/`:

```
project/          a fixture project: a git repo with docs/MILESTONES.md, docs/milestones/M*.md, CLAUDE.md
home/             the BATON_HOME to start from: projects/, inbox/, log.jsonl, status/, last-tick
rows.json         what claude agents --json answers
now               the clock's first reading
expected/         the BATON_HOME after one tick (diffed), and calls.log
```

`tests/run.sh` copies `home/` to a temporary directory, points the seams at it, runs `baton tick`,
diffs against `expected/`, then runs `baton tick` again and asserts an empty diff. Hook tests pipe
`tests/payloads/*.json` (copied from the prototype's `obs/`) into each hook and diff the file it
wrote. launchd is never in the tests.

---

## 8. Data flow

Session → artifact (inbox) → tick consumes → archive + `consumed` event → eligibility (plan) ∩
dispositions (newest archived handover) → holds, cap → dispatch (worktree, settings, sidecar,
`claude --bg`, caffeinate) → `dispatch` event → session. Rows are read once per tick and never
written. The status feed is read for two numbers. The person enters through `answer`, `allow`, an
edit, or by typing into a session, and `status` is the view.

---

## 9. Invariants

`docs/SPEC.md` §5, INV-01 to INV-12. Not restated here.

---

## 10. Interfaces by milestone

| Milestone | Introduces | Consumes |
|---|---|---|
| M01 | `bin/baton` (verb dispatch), `lib/lock.sh`, `lib/log.sh` (`log_event`, `attempt_of`, the envelope), `lib/plan.sh` (`plan_tables`, `plan_row`, `plan_eligible`, token parsers), `lib/dispatch.sh` (`worktree_ensure`, `settings_compose`, `slot_line`, `prompt_from_brief`, `sidecar_write`, `claude_bg`, `caffeinate_hold`), `lib/templates.sh` (the slot line), `hooks/stop-gate`, `hooks/stop-failure`, `hooks/statusline`, `install.sh`, `tests/run.sh`, `tests/shim/claude`, the seams, `~/.baton/` layout, `config.json`, `projects/Baton/`; verbs `plan`, `dispatch`; events `dispatch`, `dispatch_failed` | – |
| M02 | `lib/inbox.sh` (`inbox_consume`, `artifact_check`, `merged_as_verify`, `brief_pointer_check`, `archive_move`, `reject_move`), `lib/derive.sh` (derivations 1–15), `lib/status.sh`, verb `status`; events `consumed`, `rejected`; the `written_by` field; the first `escalation` writer (rejection) | M01 |
| M03 | `lib/rows.sh` (`rows_read`, `crash_check`, `stall_check`, `question_check`, `takeover_check`, `gap_check`), the tick verb with the eight steps, the marker, `com.baton.tick.plist`, the granted shell, `caffeinate` re-arming, `notify` (the Mac message); events `crash_sighting`, `takeover`, `notification` (`stall`, `long-running`, `gap`, `takeover-silent`), `self_check_failed`, `worktree_pruned` (reserved) | M02 |
| M04 | `lib/stops.sh` (`route_ending`, `wait_due`, `ladder_position`, `resume_session`, the api-error split, the continue and finish templates), `lib/templates.sh` (continue, finish); events `resume`, `copy_fork`, `wait_retry`, `hold` (`rate_limit`, `billing_error`), `hold_lifted`, `notification` (`rate_limit`, `transient`, `unrecoverable`, `billing_error`, `blocked_by`, `distant_wait_for`) | M03 |
| M05 | `lib/escalate.sh` (`escalate`, `resolve`, `message_render`, `answer_resolve`, `allow_write`), verbs `answer`, `allow`, the ruling label; events `escalation` (every class), `resolution`, `widening`, `notification` (`prompt-lost`); the `question` class from rows | M04 |
| M06 | the cap and its order, `fableReserve` (`hold` with cause `fableReserve`), `plan_override`, `worktree_pruned`, `main-broken` routing and the project park, the `blocked` silent wait | M05 |
| M07 | the `Remote: yes` two-step dispatch (`claude_bg_remote`), live items 39–40, the acceptance evidence of Baton driving itself unattended | M06 |
| M08 | `projects/Reclaim/{project.json,permissions.json}`, the hand-written starting artifact, `baton plan Reclaim` green, item 38 against Reclaim's path | M07 |
