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
├── install.sh                copies bin/ lib/ hooks/ to ~/.baton/bin/ and the plist to LaunchAgents
├── bin/baton                 the script: verb dispatch only; every verb lives in lib/
├── lib/
│   ├── lock.sh               the mkdir lock; every verb enters through it
│   ├── log.sh                the one append function; the envelope; attempt derivation
│   ├── derive.sh             the fifteen recovery derivations, one function each
│   ├── plan.sh               the plan-file reader: locate tables, read columns by name, parse tokens
│   ├── inbox.sh              consume, provenance, merged_as, brief pointers, archive, reject
│   ├── rows.sh               claude agents --json: crash, stall, live prompts, takeover, the gap
│   ├── tick.sh               the eight steps, the self-check, the marker, the stale lock
│   ├── notify.sh             the Mac message, and the two writers that always raise one
│   ├── dispatch.sh           worktree, settings, slot line, sidecar, claude --bg, caffeinate
│   ├── stops.sh              the taxonomy: routing per outcome/reason/error; waits; the ladder
│   ├── escalate.sh           answer, allow, the ruling label, the resolution event
│   ├── status.sh             the one view
│   └── templates.sh          the continue, finish and ruling texts; the slot line
├── launchd/
│   └── com.baton.tick.plist  the one agent; install.sh copies it, a person loads it
├── hooks/
│   ├── stop-gate             the Stop gate
│   ├── stop-failure          writes the api-error artifact
│   └── statusline            writes ~/.baton/status/<session_id>.json
├── tests/
│   ├── run.sh                the standing check: every scenario, one line each
│   ├── shim/claude           the claude shim; date, caffeinate and osascript shims beside it
│   ├── payloads/             hook payloads copied from .scratch/baton/prototype/obs/
│   └── scenarios/<name>/     a fixture project, an inbox, a log, a rows file, and expected/
└── docs/
    ├── SPEC.md  ARCHITECTURE.md  DECISIONS.md  MILESTONES.md
    ├── adr/0001-baton-never-calls-a-model.md
    └── milestones/M01.md … M08.md
```

**The installed relay.** `sh install.sh` copies `bin/baton`, `lib/` and `hooks/` to `~/.baton/bin/`
(flat: `baton`, `lib/`, `stop-gate`, `stop-failure`, `statusline`), copies `launchd/com.baton.tick.plist` to `~/Library/LaunchAgents/` without loading it, and creates the state directories
and `config.json` if absent. launchd runs the installed copy and every dispatched session's hooks
point at it, so a merge on `main` changes nothing until a person runs the script: a milestone can
never break the tick that dispatched it, and a broken install is undone by checking out an earlier
commit and installing again (D-018). A launchd job cannot execute anything under `~/Documents`,
which is the other reason the running copy lives under `~/.baton/`.

---

## 3. Files under `~/.baton/` and their shapes

```
~/.baton/
├── bin/                     the installed relay (§2); bin/sh is the ad-hoc signed, granted copy of /bin/sh
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
Baton's home, the project key and the milestone as environment on its command line, each pointing
at the installed relay. The prototype's `settings-A.json` and `hooks/` under
`.scratch/baton/prototype/` are the working example this is cut from; `settings_compose` in
`lib/dispatch.sh` writes it.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Bash(sh tests/run.sh:*)", "Bash(jq:*)"],
    "deny": [
      "Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)",
      "Bash(osascript * administrator privileges*)",
      "Read(//Users/danny/.baton/log.jsonl)", "Edit(//Users/danny/.baton/log.jsonl)", "Write(//Users/danny/.baton/log.jsonl)",
      "Bash(*.baton/log.jsonl*)",
      "Edit(//Users/danny/.baton/archive/**)", "Write(//Users/danny/.baton/archive/**)",
      "Edit(//Users/danny/.baton/rejected/**)", "Write(//Users/danny/.baton/rejected/**)",
      "Edit(//Users/danny/.baton/prompts/**)", "Write(//Users/danny/.baton/prompts/**)",
      "Edit(//Users/danny/.baton/settings/**)", "Write(//Users/danny/.baton/settings/**)",
      "Edit(//Users/danny/.baton/projects/**)", "Write(//Users/danny/.baton/projects/**)",
      "Edit(//Users/danny/.baton/bin/**)", "Write(//Users/danny/.baton/bin/**)",
      "Edit(//Users/danny/.baton/status/**)", "Write(//Users/danny/.baton/status/**)",
      "Edit(//Users/danny/.baton/lock/**)", "Write(//Users/danny/.baton/lock/**)",
      "Edit(//Users/danny/.baton/config.json)", "Write(//Users/danny/.baton/config.json)",
      "Edit(//Users/danny/.baton/last-tick)", "Write(//Users/danny/.baton/last-tick)",
      "Bash(*.baton/archive*)", "Bash(*.baton/rejected*)", "Bash(*.baton/prompts*)",
      "Bash(*.baton/settings*)", "Bash(*.baton/projects*)", "Bash(*.baton/status*)",
      "Bash(*.baton/lock*)", "Bash(*.baton/config.json*)", "Bash(*.baton/last-tick*)"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' /Users/danny/.baton/bin/statusline"
  },
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' /Users/danny/.baton/bin/stop-gate" }] }],
    "StopFailure": [{ "hooks": [{ "type": "command",
      "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' /Users/danny/.baton/bin/stop-failure" }] }]
  }
}
```

The deny list above is the one `install.sh` writes for Baton (D-026). The two classes are fixed
("Where an escalation goes" §3): privilege escalation, and Baton's own state by named path — a
session writes `~/.baton/inbox/` and nothing else under `~/.baton/`. The path forms are
`Read|Edit|Write(//<absolute path>)` for the tools that take a path and `Bash(*.baton/<name>*)` for
a shell command that names the path (`bin` excepted, so a session can run `baton status`); each
named path is one rule, so a directory the list does not name (one a session creates itself under
`~/.baton/`) is not denied, and a Bash fragment is never complete, which is the stated limit of the
class. A `permissions.json` with no deny rules fails the `settings` stage rather than dispatching
without the rail. Under `bypassPermissions` the allow rules allow nothing and cost nothing; they are kept
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
   for the rest of the tick. A stale lock is reported before this, and one past the interval whose pid answers no signal is cleared by the tick, which then writes the `baton-unhealthy` escalation under the lock it takes (D-039).
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
     `claude --bg -n "<session name>" --model <Model> [--effort <Effort>]
     --permission-mode bypassPermissions --settings <file> "<prompt>"`; parse `backgrounded · <id>`
     from stdout. No line → `dispatch_failed` (§6.2).
   - `Remote: yes`: the same command with `--remote-control` and no prompt, `claude stop <id>`, then
     a flagless `claude --bg --resume <uuid> "<prompt>"`.
   - Read the row's `pid` from `claude agents --json`; start `caffeinate -i -w <pid>` detached.
   - Log the `dispatch` event.

**The session name** is `Baton · <project> · <milestone>`, except when the project key is `Baton`
itself, where the prefix has already named the project and the name is `Baton · M02`. The prefix is
the only ownership marker a row carries and is never dropped; the key is only not repeated
(D-036). `session_name` in `lib/templates.sh` composes it, and the refusal to dispatch over a live
row of the same name reads the same function.

Then the marker, after the lock is released.

### 4.2 The verbs

| Verb | Does | Side effects |
|---|---|---|
| `baton tick` | the eight steps for every registered project | the log, the archive, dispatches, the marker |
| `baton answer <milestone \| project/milestone> <ruling \| n>` | resolves against parked lanes across all projects; one match: `claude stop <id>`, a wait for the stop to land, then a flagless resume with the ruling label, and the resolution once the resume was delivered or forked; several refuse with the candidates; none refuses; an empty ruling refuses; `continue` on a lane taken over and not parked is the hand-back | `resume`, then `resolution` |
| `baton status` | the one view (§5.3), last tick first, whole file | none |
| `baton plan <project>` | the graph as the tick sees it; validates every `Model` cell; lists widenings | none |
| `baton dispatch <project> <milestone>` | step 8 alone, by hand, after checking eligibility and that no live row carries the milestone | worktree, settings, sidecar, session, `dispatch` event |
| `baton allow <milestone \| project/milestone> '<rule>' [--resume]` | writes the rule as typed to `permissions.json` and the dispatched settings file in place, both parsed before either is written; refuses an `ask` form, JSON, a rule over 1 KB or with a newline, and `--resume` on a parked lane; reports a rule the deny list also names as `denied`; `--resume` stops and flaglessly resumes | `widening` event when a file changed; a `resume` event |

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
close-out from step (c)" or "main fixed; finish the close-out from step (c)". `<question>` is the
escalation's `question`, else its `detail`; for a `question` park, whose words no payload carries, it
is "the question you put with AskUserQuestion in this session, whose words no payload carries to
Baton". `<n>` and `<r>` are one reading of derivation 10, the same numbers the `resume` event records.
An option number is expanded from the archived `asking` artifact before delivery.

**The hand-back** after a takeover is the continue template with `<class>` = `handed back`.

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
`note: woke session <id> with its saved options (-n, --effort, --permission-mode, --settings, --model).`

**Both notes go to stderr, and stdout carries a `backgrounded · <id>` line either way** (live item 46,
measured on 2.1.269). So stdout alone can tell neither a fork from a success nor either from a
refusal, and the fork test must come before the success test. The id in the note is the **job** id
and not the session id — a copy announced as `d2007634` has session id
`d2007634-d17b-4b0d-9c67-a0cec9b98ff6`, whose first eight characters it is — so a `copy_fork` event
resolves it through the row, or through the transcript tree when no row answers. A copy's transcript
is filed under the slug of the *resuming* process's working directory, not the original session's,
which is why §6.3 globs the tree and never derives a path from a project. The same capture settled
item 43: `--effort` is among the options a flagless resume restores, and the CLI names it.

A flagless resume forks whenever the original is still running, so `claude stop` preceding it is not
enough on its own: the stop is not synchronous, and a resume issued in the same breath met a session
the CLI still called "already running in the background". So the resume waits for the stop to land
(`stop_settle`): no row carrying the session has a pid, read through `rows_read` so that a listing
that failed is not taken for an empty one, for up to sixty listings half a second apart. Measured on
M05's live `baton answer`: without the wait the ruling landed in a copy whose row the CLI named for
itself rather than `Baton · …`; with it, the same command delivered to the same session.

### 4.4 The injected hooks

Three, from `--settings`, each a shell script under `~/.baton/bin/` taking `BATON_HOME`,
`BATON_PROJECT` and `BATON_MILESTONE` from its environment and the hook payload on stdin. The prototype's
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

1. the last tick, from the marker; the hardware condition (lid open or clamshell) on the same line
   (REQ-SETUP-07);
2. project-scope parks — all dispatch held for a project, with the class and the verb;
3. parked lanes — `<project>/<milestone> · <class> · <the one line the person read> · <the verb>`;
4. taken-over lanes — `taken over at <time>; hand back with baton answer <M> "continue"`;
5. waits and holds — the `error`, the elapsed time from `since`, the next retry, each hold with its
   model and cause;
6. in flight — `<project>/<milestone>`, session, model, attempt, elapsed since the latest
   dispatch-or-resume event, any live notification the tick has written for the attempt (`stalled`,
   `long-running`) and the row's own `waitingFor`. Only lanes with a live row are printed:
   derivation 1's `no_row` is the crash rule's input, not a state, and it holds sessions Baton
   itself stopped;
7. silent waits — a `blocked_by` whose blocker is in flight or eligible, and a distant `wait_for`;
8. an open gap, if one was reported and nothing has cleared it;
9. what is waiting in the inbox — one line per artifact Baton has not acted on, with its outcome.

Whole file, every time; no flags; no denials line. A section with nothing in it prints nothing, so
the file is as short as the state is quiet. Line 9 exists because the move is the consumption: a
file still in the inbox is a handover Baton has not read, and nothing else in the view would say so
(D-035).

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
| `dispatch_failed` | `stage` (`worktree`\|`settings`\|`prompt`\|`launch`\|`service`), `detail`; no `session` | the second consecutive since the pair's newest `dispatch` escalates, lane scope, and that park is then what stops the retry (D-049); `stage: service` escalates, project scope, which is M06's | — |
| `consumed` | `outcome`, `reason` or `error`, `written_by` (`session`\|`stop-gate`\|`stop-failure`), `merged_as`, `blocked_by`, `archive` | every ending's routing; the ladder's reset; the notification keys' reset; the terminal test for in flight; the wait's start before its first retry | — |
| `rejected` | `path` (where the file came to rest: `~/.baton/rejected/` for a rejected file, `~/.baton/archive/` for a rejected `eligible[]` entry of a file that was consumed), `reason` (the rule's name) | the lane escalation that follows a rejection (the log is the record, so no sidecar) | — |
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
| `self_check_failed` | `stage` (`read`\|`parse`\|`git`), `path`, and for `parse` also `table`, `row`, `cell`; `detail` | the stage and cell beside the project-scope escalation the failure raises (`plan-unreadable` or `plan-unparseable`), written once while that park stands (D-041) | — |

**Escalation classes.** Lane: `asking`, `question`, `ladder-end`, `unfinished-twice`, `blocked`,
`merge-failed`, `other`, `disagreement`, `omitted`, `model_not_found`, `dispatch-failed`. Project:
`plan-unreadable`, `plan-unparseable`, `main-broken`, `baton-unhealthy`.

**What `carries` holds, per class.** `asking`: `question`, `options`, `recommendation` and `context`
from the artifact, cut in bytes (D-061), or `detail` and `archive` when those cannot be carried.
`question`: `row`, `job`, `waiting_for`, `detail`. `merge-failed`, `other` from a stopped artifact:
`detail`, `archive`. `other` from a rejection: `rule`, `path`. `ladder-end`: `failures`, `ending`,
`last_detail`, `detail`. `unfinished-twice`: `newest`, `previous`, `detail`. `blocked`: `blocked_by`,
`blocker_state`, `detail`. `model_not_found`: `model` (the attempt's own), `plan`, `detail`.
`dispatch-failed`: `consecutive`, `stage`, `detail`. A project class: the self-check's or the lock's
fields and `detail`. A lane park whose class an edit resolves, or which no ruling can reach — no
project, session and attempt — also carries `reread`: `plan_rows_sha256` over the parsed rows that
answer it (its own, those whose `Depends on` names it, the `blocked_by` row; row numbers removed) and
`brief_sha256` over the kickoff prompt on `main` (D-058). `edit_reread_check` compares the fields the
park carried and writes `resolution` with `how: edit` on a difference.

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

**The contract every derivation keeps** (D-031). One function per sentence in `lib/derive.sh`, each
printing exactly one JSON object on stdout with its result under a named key, so a reader picks a
field and never parses text; a list result is an array under that key. A field a derivation has no
value for is absent, never null, the same discipline the envelope keeps. The rows arrive as a JSON
argument and the transcripts through `BATON_TRANSCRIPTS`, so every fixture is a directory and no
fixture starts a process. An empty `<project>` argument means every registered project, for the
derivations that scan across projects (1 to 5, 7 and 15); the rest name a project, a milestone or a
class and take it as given. All time
arithmetic goes through `iso_epoch`, which converts an ISO 8601 string in `awk`: a string Baton
wrote is not an outside thing, and the date seam answers the scenario's `now` whatever it is asked.

1. **In flight, per project.** Every `dispatch` whose `(project, milestone, attempt)` has no later
   `consumed` with `outcome: complete` and no later `dispatch` for the same `(project, milestone)`,
   resolved through the fork chain to its current session (§6.1), **intersected with rows in
   `claude agents --json` that carry a `pid`**. The document names both halves of that one join —
   `in_flight` and `no_row` — because the crash rule is exactly the complement and rebuilding it
   would replay the fork chain a second time. **Liveness is the `pid` and never the `state`**: a
   crash reads `pid: null` while `state` still reads `working`.
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
   not by reconstruction: the `consumed` event's `archive` holds the archived file's path
   **verbatim**; a reader joins on the field and never rebuilds the name from parts. The name's
   `<consumed-at>` and the event's own `at` are two readings of the clock and can differ by a
   second, which is why nothing joins on them matching. The join runs both ways: the derivation
   also names every file in `archive/` and `rejected/` that no event claims, which is what a tick
   killed between the move and its event leaves behind and which nothing else would show.
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
    `billing_error` hold; on every model once a second model is held. A `fableReserve` hold holds
    its own model and counts toward nothing: the reserve is about one model's share of a window,
    not about the account being unable to answer.
13. **`baton answer <milestone>`**: derivation 2, filtered by milestone across every project. Exactly
    one match acts; more than one refuses and prints `<project>/<milestone>`; none refuses with
    "nothing is waiting on `<milestone>`".
14. **`baton plan`'s provenance of allow rules**: every `widening` for the project, newest first,
    each naming the rule and the milestone that earned it.
15. **The gap**: `now` minus `~/.baton/last-tick`. Reported as a `notification` with class `gap`
    only when derivations 1, 2 or 5 show a lane was in flight, waiting or parked during it. Keyed on
    the marker value it was measured against, so one outage reports once. **The threshold is two
    intervals**, not one: the marker holds the `at` of the tick that completed and is written after
    the lock is released, so at the next tick it is already a full interval old plus that tick's own
    elapsed time, and one interval would report on every tick with an open lane — while the key,
    being the marker value, changes every tick and so would suppress nothing. **"During it" is not
    "now"**: a lane that ran through the outage and finished before the read still means Baton was
    not running while something needed it, so the window counts lanes open now plus anything that
    closed after the marker.

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
{"at":"2026-09-12T08:02:55+01:00","kind":"resume","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "resume_kind":"ruling","resume":1,"class":"asking","outcome":"delivered",
 "prompt_path":"/Users/danny/.baton/prompts/7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9/2.txt",
 "prompt_sha256":"91b3e7c2a04f6d18b5e9c3a7f60d2b48e1c5a9037d6b2e8f4a0c1d7b39e5f8a26"}
{"at":"2026-09-12T08:02:56+01:00","kind":"resolution","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "how":"ruling","escalation_at":"2026-09-12T02:41:18+01:00"}
```

The resolution follows the resume it depends on: a ruling closes its park only once the resume was
delivered or forked, and a refused one leaves the park standing (D-059).

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
| `BATON_CLAUDE` | `/Users/danny/.local/bin/claude` | `--bg` prints `backgrounded · <id>` (and `Starting background service…` on stderr when told to) and later writes an inbox artifact from the scenario; `agents --json` answers from `rows.json`; `stop` and `--bg --resume` append their argv to `calls.log`; `stop` takes the pid off the session's row — after `stop.fail` failed listings and `stop.linger` listings that still show it, when a scenario sets them — and a resume that wakes the session gives it back; `--bg --resume` prints the success note by default, the copy-fork note when the session's row still has a pid, and a scenario's own `note:` line otherwise, on either stream, with its own exit code; `bg.color` wraps every id in the colour escapes the real CLI prints whenever `FORCE_COLOR` is in the environment |
| `BATON_DATE` | `date` | prints the scenario's `now`, one reading for both runs: the clock is frozen, so the second run's diff shows what the run itself changed and nothing the clock did |
| `BATON_CAFFEINATE` | `/usr/bin/caffeinate` | appends its argv to `calls.log` and exits |
| `BATON_HOME` | `~/.baton` | the scenario's own state directory |
| `BATON_DAEMON_LOG` | `~/.claude/daemon.log` | the service's own log, read only for `bg settled <id> (crashed): <detail>` when a backgrounded worker never gets a row (item 47); the claude shim writes the line when told to |
| `BATON_OSASCRIPT` | `/usr/bin/osascript` | the Mac message; records its argv in `calls.log`, so a scenario asserts on the line a person would have read and no notification is raised (D-043) |
| `BATON_TRANSCRIPTS` | `~/.claude/projects` | the tree derivation 3 globs for `*/<session>.jsonl`; a scenario's own `transcripts/` directory, so a transcript read is a file read and no fixture starts a session (D-032) |

**Scenarios** under `tests/scenarios/<name>/`:

```
cmd               the commands to run, sourced twice with $BATON, $ROOT, $SCENARIO and $SHIM set;
                  a scenario testing a library function rather than a verb sources tests/lib-load.sh
home/             the BATON_HOME to start from: config.json, projects/, inbox/, log.jsonl, status/;
                  @TMP@ in any file becomes the scenario's temporary root and @COMMIT@ the fixture
                  project's one commit, which is what a handover's merged_as names
rows.json         what claude agents --json answers first
now               the clock's reading
shim/             optional: the claude shim's knobs (bg.stderr, bg.fail, bg.norow, bg.settled,
                  bg.color, resume.note, resume.stream, resume.status)
project/          optional: a fixture project (CLAUDE.md, docs/MILESTONES.md, docs/milestones/M*.md);
                  tests/project/ otherwise
transcripts/      optional: the tree BATON_TRANSCRIPTS points at, one folder per checkout holding
                  <session>.jsonl; an empty tree otherwise, which is a lane with no transcript
mtimes            optional: "<path under transcripts/> <seconds before now>" per line, for a rule
                  that stats a transcript rather than reading it; without it the age compared
                  against the scenario's frozen now is the time of the copy (D-046)
expected/         home/ (without lock/), out/<run>.{stdout,stderr,status} for both runs, calls.log
```

`tests/run.sh` copies the fixture project to `<tmp>/Fixture` and commits it once on `main` at a
fixed date and identity (so its hash is the same on every run), copies `home/`, points the seams at
the shims, runs `cmd` twice, then diffs the state left behind — `home/` without the lock, both
runs' streams and exit codes, and the shims' `calls.log` — against `expected/` with the temporary
root written as `@TMP@`. A `dispatch` event's `prompt_sha256` is recomputed from its sidecar under
the one rule and replaced by `sha256-matches-sidecar` or a mismatch note before the diff, because
the sidecar carries the temporary path. `BATON_TESTS_FREEZE=yes sh tests/run.sh` rewrites every
`expected/` from the run, for a fixture whose output has been read and judged right. Hook scenarios
pipe `tests/payloads/*.json` (copied from the prototype's `obs/`, two constructed) into a hook
through `cmd`. launchd is never in the tests.

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
| M01 | `bin/baton` (verb dispatch; reads the five seams once and exports them). `lib/lock.sh`: `lock_take`, `lock_release`. `lib/log.sh`: `baton_now`; `log_event <kind> <project> <milestone> <session> <attempt> [<fields json>]` (the one append; an empty envelope argument is absent from the line; refuses without the lock or over 4 KB); `attempt_of <project> <milestone>` (the count of `dispatch` events; the next attempt is that plus one); `prompt_normalise` (stdin to stdout, strips exactly one trailing newline); `prompt_sha256 <file>`; `sidecar_write <session> <text>` (prints `<path> <sha256>`); `widenings_json <project>`. `lib/plan.sh`: `plan_tables <file>` (one JSON document `{milestones: [{row, id, depends[], model, effort, remote, status}], gates: [{row, gate, holds[], cleared}]}`; on the first bad cell prints `{error: "plan-unparseable", table, row, cell, detail}` with status 1); `plan_rows`, `plan_gates`, `plan_row <id>`, `plan_eligible` (ids, one per line) and `plan_render <project> <inflight json>` on that document from stdin; `parse_id`, `parse_depends`, `parse_model <cell> <models json>`, `parse_effort`, `parse_remote`, `parse_status`, `parse_cleared`; `verb_plan`. `lib/dispatch.sh`: `rows_json`; `inflight_json <project>` (a placeholder, removed by M02); `row_for_id <id>`; `worktree_ensure <path> <milestone>` (prints `{worktree, branch, reused, commit}`); `settings_compose <project> <milestone>` (prints the path); `prompt_from_brief <path> <brief> <heading>`; `slot_line <prompt> <paragraph>`; `claude_bg <worktree> <name> <model> <effort> <settings> <prompt>` (sets `bg_status`, `bg_stdout`, `bg_stderr`, `bg_id`); `dispatch_failed_classify <text>`; `caffeinate_hold <pid>`; `dispatch_failed <project> <milestone> <stage> <detail>`; `dispatch_one <project> <milestone> <plan json>`; `verb_dispatch`. `lib/templates.sh`: `slot_line_text <worktree> <branch> <canonical> <also> <attempt> <commit>`. The convention every fallible function follows: its result on stdout on success, its failure detail on stdout with a non-zero status. The hand-run verb reads the brief at `docs/milestones/<milestone>.md` under `## Copy-ready session prompt`. `hooks/stop-gate`, `hooks/stop-failure`, `hooks/statusline`; `install.sh`; `tests/run.sh`, `tests/shim/{claude,date,caffeinate}`, `tests/project/`, `tests/payloads/`, 27 scenarios; the five seams; `~/.baton/` layout, `config.json`, `projects/Baton/`; verbs `plan`, `dispatch`; events `dispatch`, `dispatch_failed` | – |
| M02 | `lib/inbox.sh`: `project_key_of <path>`; `merged_as_verify <path> <sha>`; `brief_pointer_check <path> <brief> <heading>`; `written_by_of <reason>`; `stop_route <reason>` (the REQ-STOP-12 table as data; M04 attaches the actions); `artifact_ids <file>`; `artifact_check <file>` (prints `{artifact, project, written_by, dropped[]}`, or `{rule, detail}` with status 1); `escalate_rejection <project> <milestone> <session> <attempt> <rule> <path>`; `attempt_for_session <project> <milestone> <session>`; `archive_move <file> <consumed-at>`; `reject_move <file>`; `reject <file> <rule> <detail>`; `inbox_consume <rows json>`; `consume_one <file> <check doc> <rows json>`. `lib/derive.sh`: `config_num <key> <default>`; `iso_epoch <timestamp>`; `now_epoch`; `session_id_ok <session>`; `transcript_of <session>`; `orphaned_of <session>`; `typed_hashes <transcript>`; `lanes_open <project> <log json>`; `current_session <project> <milestone> <attempt>`; `lane_of_session <session>`; and the fifteen — `derive_in_flight <project> <rows>` (`{in_flight[], no_row[]}`), `derive_parked <project>`, `derive_taken_over <project> <rows>` (`{taken_over[], orphaned[], unreadable[]}`), `derive_consumed <project>` (`{consumed[], waiting[], unrecorded[]}`), `derive_waits <project>`, `derive_holds`, `derive_caffeinate <project> <rows>` (`{wake[], timed[]}`), `derive_last_tick`, `derive_ladder <project> <milestone> <attempt>`, `derive_attempt <project> <milestone> [<attempt>]`, `derive_key_spent <project> <milestone> <attempt> <class> [<key>]`, `derive_dispatch_hold`, `derive_answer_candidates <milestone>`, `derive_widenings <project>`, `derive_gap <rows>`. Every one prints one keyed JSON object; an empty `<project>` means every project (D-031). `lib/status.sh`: `duration`, `nth`, `field`, `verb_for`, `one_line`, `silent_waits <project> <rows>`, `status_render <rows json>`, `verb_status`. `lib/templates.sh`: `session_name <project> <milestone>` (D-036). `tests/consume-once.sh`, `tests/lib-load.sh`, the `transcripts/` fixture and the `@COMMIT@` substitution in `tests/run.sh`; verb `status`; events `consumed`, `rejected`, `escalation` (class `other`, rejection only); the `written_by` field; the sixth seam `BATON_TRANSCRIPTS`. **Removes** M01's placeholder `inflight_json`: `verb_plan`, `dispatch_one` and `verb_dispatch` read `derive_in_flight`'s `in_flight` instead, which is what the placeholder stood in for | M01 |
| M03 | `lib/rows.sh`: `rows_read` (the rows once per tick, non-zero when the listing could not be read); `inbox_holds <session>`; `ended_on_disk <session>`; `stood_off <session> <list>`; `newest_event_at <project> <milestone> <attempt> <kinds regex>`; `transcript_mtime <session>` (the newest `stat -f %m` across the transcript and `<session>/subagents/agent-*.jsonl`); `takeover_check <project> <rows>` (prints `{stand_off[], lines[]}`); `crash_check <project> <rows> <stand-off> <this tick's clock>`; `stall_check <project> <rows> <stand-off>`; `long_running_check <project> <rows>`; `question_check <project> <rows> <stand-off>`; `gap_check <rows>`. `lib/notify.sh`: `notify_text`, `notify <title> <body>`, `notify_title <project> <milestone> <class>`, `fields_or_fail`, `class_or_fail <kind> <class>`, `escalation_write <project> <milestone> <session> <attempt> <class> <scope> <carries>`, `notification_write <project> <milestone> <session> <attempt> <class> <key> <fields>` — every escalation and notification is written through the last two, which raise the Mac message as they write the event, and the body is `one_line` of the event's own fields. `lib/tick.sh`: `lock_stale_report`, `lock_stale_break` (a rename, so exactly one process can claim a dead lock), `marker_write`, `self_check_failed_once` (the event plus the project-scope escalation of the log's own class), `park_resolve <project> <class regex> <what cleared it>` (REQ-ESC-05's edit route, the one only the tick can see), `self_check <project>` (prints the parsed plan document), `caffeinate_armed`, `caffeinate_timed`, `caffeinate_rearm`, `tick_dispatchable <project> <plan> <rows>` (steps 5 to 7, excluding an open lane, an open lane-scope park and a `Remote: yes` row), `dispatch_try` (step 8 with the two-failure bound), `tick_project` (steps 3 to 8 for one project), `tick_run` (returns 3 when the rows could not be read), `verb_tick` (no marker on a 3). `launchd/com.baton.tick.plist`, copied by `install.sh` to `~/Library/LaunchAgents/` and never loaded by it; the ad-hoc signing of the granted shell (D-038); verb `tick`; the seventh seam `BATON_OSASCRIPT` and `tests/shim/osascript`; the `mtimes` fixture file; twenty-six scenarios — `tick-{quiet,consumes-then-dispatches,long-running,stale-lock,stale-lock-live,no-rows,inbox-not-a-stall,transcript-unscannable,dispatch-fails-twice}`, `tick-self-check-{unparseable,unreadable,no-git,recovers}`, `crash-{first-sighting,two-ticks,confirmed-stands,rejected-ended,sleep-not-a-crash}`, `stall`, `stall-subagent-moving`, `question-row`, `takeover`, `takeover-handback-pending`, `gap-{reported,quiet,key-spent}`. Events `crash_sighting`, `takeover`, `self_check_failed`, `notification` (`stall`, `long-running`, `gap`, `takeover-silent`), `escalation` (`question`, `baton-unhealthy`, and `other` for a transcript that cannot be scanned). **Changes** `escalate_rejection` in `lib/inbox.sh` to go through `escalation_write`, so a rejection reaches the Mac; and `status` line 1 to carry the hardware condition and line 6 the live notifications. `worktree_pruned` stays reserved for M06 | M02 |
| M04 | `lib/stops.sh`: `route_ending <outcome> [<reason>] [<error>]` (the taxonomy of §5.2 as one lookup, printing `{class, action, retry, notify, hold}`); `ceiling_seconds <notify>`; `model_of_attempt <project> <milestone> <attempt>`; `job_of_session <rows> <session>`; `fork_session <short id>`; `artifact_detail <archived path>`; `resume_session <project> <milestone> <attempt> <session> <job> <kind> <class>` (stop, flagless resume, both streams read through `cli_plain`, the fork test before the success test, the `resume` and `copy_fork` events, printing `{outcome, session, note}`); `ladder_position <project> <milestone> <attempt>` (derivation 9 plus the newest ending and whether a step was taken for it); `redispatch <project> <milestone> <plan> <rows> <why>`; `ladder_step`; `declared_open <project>`; `consecutive_run <project> <milestone> <kind>`; `splits_carries`; `blocker_state <plan> <blocker> <in-flight>`; `declared_step`; `distant_wait_for_check`; `stops_standing_by`; `stops_run <project> <plan> <rows> <stand-off>` (step 4 for one project, in the order the facts arrive: the waits, the ladder, the declared stops, the distant wait). `lib/waits.sh`: `wait_run <project> <milestone> <attempt>` (the continuous wait's start and retry count since the attempt's reset, D-052); `wait_due <project>` (derivation 5 with each wait's routing attached); `wait_notify` (the ceilings, once per class per attempt through derivation 11); `wait_retry_run <project> <wait> <rows>`; `holds_apply` (derivation 6 written, once per tick across every project, with the second-model rule); `hold_bites <model>` (derivation 12, read before every dispatch). `lib/templates.sh`: `template_continue <class> <milestone> <attempt> <resume>` and `template_finish <milestone> <attempt> <resume> <session>`, §4.3 verbatim. `lib/dispatch.sh`: `cli_plain` (D-050), which `claude_bg` and `resume_session` read the CLI through. Events `resume`, `copy_fork`, `wait_retry`, `hold` (`rate_limit`, `billing_error`), `hold_lifted`, `notification` (`rate_limit`, `billing_error`, `transient`, `unrecoverable`, `blocked_by`, `distant_wait_for`), `escalation` (`model_not_found`, `unfinished-twice`, `blocked`, `ladder-end`). Twenty-two scenarios — `route-ending`, `wait-{rate-limit,ceiling-2h,transient-1h,unrecoverable-now,max-output-at-once,clears-on-resume}`, `resume-refused`, `hold-second-model`, `no-handover-ladder`, `crash-{resume,redispatch-no-transcript}`, `copy-fork`, `invalid-request-redispatch`, `model-not-found`, `unfinished-{once,twice,twice-long}`, `blocked-{silent,escalates}`, `distant-wait-for`, `dispatch-coloured-id`; the shim's resume roles and its colour knob. **Changes** `lib/rows.sh`'s `crash_check`, which no longer sights a lane dispatched or resumed within two intervals (D-054); `lib/tick.sh`, whose step 4 now has a body, whose step 7 applies the dispatch hold, and which runs `holds_apply` once before the project loop; and `lib/notify.sh`, whose two writers no longer raise the Mac message when `log_event` refused the line, so a message implies a record (D-057) | M03 |
| M05 | `lib/escalate.sh`: `class_unparks_by_edit <class>`; `reread_hashes <project> <milestone> <carries> [<plan>]` (prints `{plan_rows_sha256, brief_sha256}`, each absent when it cannot be read); `person_acted <project> <milestone> <class>` (prints `edit`, `ruling` or nothing, D-059); `escalate <project> <milestone> <session> <attempt> <class> <scope> <carries>` (the one writer of `escalation`, replacing `escalation_write`: class and scope checked, `reread` attached, event before message); `resolve <project> <milestone> <session> <attempt> <escalation at> <how>`; `ruling_target <project> <session> <attempt>`; `escalation_content <class> <carries>`; `escalation_verb <class> <milestone> <carries> [<ruling target>]`; `message_render <project> <milestone> <class> <carries> [<session>] [<attempt>]` (prints `{address, content, verb, body}`, the verb never cut); `asking_carries <artifact>`; `ending_escalate <project> <milestone> <session> <attempt> <artifact> <class> <archive>` (with its fallback carries); `edit_reread_check <project> <plan>`; `question_resolve_check <project> <rows>` (answered in place by the row or by the session's own later artifact, and `prompt-lost`). `lib/answer.sh`: `answer_resolve <milestone> [<project>]`; `answer_candidates_print`; `answer_options` (from the archive); `answer_deliver <park> <ruling \| n> <rows>`; `answer_handback <milestone> [<project>] <rows>`; `verb_answer`; `allow_lane <milestone> [<project>]`; `allow_write <project> <milestone> <rule>`; `verb_allow`. `lib/stops.sh`: `stop_settle <session>`; `resume_count_next <project> <milestone> <attempt>` (prints `<attempt> <resume>`); `resume_session` gains the kind `ruling` and an eighth argument, its text. `lib/templates.sh`: `template_ruling <milestone> <attempt> <resume> <time> <question> <ruling>`, §4.3 verbatim. Verbs `answer`, `allow`. Events `escalation` (`asking`, `merge-failed`, `other` from a stopped artifact), `resolution` (`ruling`, `answered in place`, `edit` on a lane), `widening`, `notification` (`prompt-lost`). The shim's stop, linger, fail and fork roles. Twenty-eight scenarios — `asking-{parks,row-lingers,too-large}`, `answer-{one-match,two-matches,not-parked,option-number,resume-refused,hand-run-session}`, `edit-unparks`, `edit-unparks-no-session`, `ladder-end-edit`, `model-not-found-edit`, `unfinished-twice-ruling`, `merge-failed-ruling`, `other-escalates`, `question-row-answered-in-place`, `question-then-artifact`, `prompt-lost`, `takeover-handback`, `two-projects-refusals`, `allow-{writes,refuses-ask,resume,resume-parked,files}`, `stop-settle-lingers`, `ending-escalate-fallback`. **Changes** every M02–M04 writer of an escalation to call `escalate`, and `park_resolve` to write through `resolve`; `consume_one` to park `asking`, `merge-failed` and `other`; `question_check` to pass by a lane already parked or dispatched or resumed within two intervals; `ladder_step`, `declared_step` and `stops_run` to ask `person_acted` before parking again, and the `model_not_found` detail to name the attempt's model; `verb_for` to print `escalation_verb`; `class_or_fail` to take its caller's name; `tick_project` to run `edit_reread_check` and `question_resolve_check` first | M04 |
| M06 | the cap and its order, `fableReserve` (`hold` with cause `fableReserve`), `plan_override`, `worktree_pruned`, `main-broken` routing and the project park, the `blocked` silent wait | M05 |
| M07 | the `Remote: yes` two-step dispatch (`claude_bg_remote`), live items 39–40, the acceptance evidence of Baton driving itself unattended | M06 |
| M08 | `projects/Reclaim/{project.json,permissions.json}`, the hand-written starting artifact, `baton plan Reclaim` green, item 38 against Reclaim's path | M07 |
