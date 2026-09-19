# Baton: architecture

The shapes behind `docs/SPEC.md`: the files, the tick's steps, the injected hooks, the verbs, the
states, the log's events and derivations, the testing seams, and the interfaces each milestone
introduces. Sections 6.1 to 6.5 carry the text of "The dispatch log" §1, §2, §5 and §8 as that ticket
wrote them; the rest consolidates the other resolutions. The vocabulary is `CONTEXT.md`.

---

## 1. Stack

`/bin/sh` with `set -eu`; `jq` 1.7.1 at `/usr/bin/jq` with `-e`; `awk` for the slot line; `git`;
`/Users/danny/.local/bin/claude` 2.1.268; launchd; `/usr/bin/caffeinate`; the notifier applet compiled by `/usr/bin/osacompile`, with `osascript` behind it, for the Mac
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
├── install.sh                copies bin/ lib/ hooks/ to ~/.baton/bin/, builds Baton.app, copies the plist to LaunchAgents
├── notify/
│   └── Baton.applescript     the notifier applet's source; install.sh compiles it into ~/.baton/bin/Baton.app
├── bin/baton                 the script: verb dispatch only; every verb lives in lib/
├── lib/
│   ├── render.sh             the one layer between what Baton decides and what a person reads; sourced first
│   ├── permissions.sh        the two deny classes, once, for every caller; install.sh sources this file alone
│   ├── lock.sh               the mkdir lock; every verb enters through it
│   ├── log.sh                the one append function; the envelope; attempt derivation
│   ├── derive.sh             the fifteen recovery derivations, one function each
│   ├── plan.sh               the plan-file reader: locate tables, read columns by name, parse tokens
│   ├── inbox.sh              consume, provenance, merged_as, brief pointers, archive, reject, reconcile
│   ├── completion.sh         the chain a completion claim must hold, and the check Baton runs itself
│   ├── rows.sh               claude agents --json: crash, stall, live prompts, takeover, the gap
│   ├── tick.sh               the eight steps, the self-check, the marker, the stale lock
│   ├── notify.sh             the Mac message, and the notification writer
│   ├── candidates.sh         steps 5 to 7: the dispositions, the plan overrides, the cap's order
│   ├── dispatch.sh           worktree, settings, slot line, sidecar, claude --bg, caffeinate
│   ├── preconditions.sh      what a dispatch needs before it creates anything, read once and shared
│   ├── stops.sh              the taxonomy: routing per outcome/reason/error; the resume; the ladder
│   ├── declared.sh           the declared stops: unfinished, blocked, a distant wait, main-broken's cascade
│   ├── waits.sh              the wait, the rate-limit hold and the reserve
│   ├── escalate.sh           the one escalation writer, the resolutions, the message, the re-read
│   ├── answer.sh             the verbs a person runs: answer and allow
│   ├── status.sh             the one view
│   ├── templates.sh          the continue, finish and ruling texts; the slot line
│   ├── lifecycle.sh          a finished session: the offline rule, the wake verb, the wake session
│   └── onboard.sh            the onboard verb: the repository, the toolchain, the plan as it stands, one confirmation
├── launchd/
│   └── com.baton.tick.plist  the one agent; install.sh copies it, a person loads it
├── hooks/
│   ├── stop-gate             the Stop gate
│   ├── stop-failure          writes the api-error artifact
│   └── statusline            writes ~/.baton/status/<session_id>.json
├── tests/
│   ├── run.sh                the standing check: every scenario, one line each
│   ├── shim/claude           the claude shim; date, caffeinate, osascript and open shims beside it
│   ├── completion-fixture.sh the baseline, candidate and merge commits a completion chain is judged against
│   ├── payloads/             hook payloads copied from .scratch/baton/prototype/obs/
│   └── scenarios/<name>/     a fixture project, an inbox, a log, a rows file, and expected/
└── docs/
    ├── SPEC.md  ARCHITECTURE.md  DECISIONS.md  MILESTONES.md
    ├── adr/0001-baton-never-calls-a-model.md
    └── milestones/M01.md … M08.md
```

**The installed relay.** `sh install.sh` refuses before writing unless its source is the canonical
checkout with HEAD on `main` and its install inputs match committed `main`. The scenario harness
sets `BATON_INSTALL_TEST=1` to install the tested checkout into a disposable home from any worktree;
that forgeable test seam is not a security boundary (D-113). It publishes `bin/baton`, `lib/` and `hooks/` to `~/.baton/bin/`
(`baton`, `lib/`, `stop-gate`, `stop-failure`, `statusline`), builds the notifier applet `Baton.app` there from `notify/Baton.applescript` with Claude's icon copied from the installed Claude.app and never committed (D-092), copies `launchd/com.baton.tick.plist` to `~/Library/LaunchAgents/` without loading it, and creates the state directories
and `config.json` if absent. It regenerates Baton's own `permissions.json` on upgrades, replacing it
by rename only when the generated content differs; wake settings inherit that current deny list
(D-111). launchd runs the installed copy and every dispatched session's hooks
point at it. A Baton milestone's close-out runs the script on `main` once the standing check has
passed there, before it writes its handover, so the next dispatch is made by the merged relay; a
milestone can never break the tick that dispatched it, and a broken install is undone by restoring
reviewed earlier code on `main` and installing again (D-018, D-079, D-113). A launchd job cannot execute anything under `~/Documents`,
which is the other reason the running copy lives under `~/.baton/`.

**Nothing is read half-installed** (D-131). `bin/baton` sources its whole library set before it reads
the verb and long before any `lock_take`, and launchd fires every sixty seconds, so a file-by-file
copy could hand a starting tick some libraries from the old set and some from the new — and a lock
in the installer could not have prevented it, because the sourcing is over before the tick takes
one. So a library set is published whole, once per content:

- The set is staged in a directory of its own and published by renaming that directory to
  `~/.baton/bin/lib/<digest>`, a name that does not yet exist. `rename(2)` cannot be seen half-made,
  and a name already present is a set already published, which is left untouched.
- `<digest>` — sixteen hexadecimal characters over `bin/baton` and every `lib/*.sh` — is written
  into the copy of `bin/baton` installed beside it, on its `baton_bundle=` line. That copy is
  published by renaming over the old one, which is the one atomic reference change: a shell already
  reading the previous copy holds its inode open and reads it whole, so it goes on naming the
  previous set; a shell started afterwards opens the new copy and names the new one.
- The previous set is kept for exactly that reader and every older one is removed, so a reader gets
  the whole previous library set or the whole new one and never a mixture. A relay installed before
  this scheme names no set, and its flat `bin/lib/*.sh` is the previous set until one bundled
  install has been superseded.
- The three hooks are published the same way, and every file is compared before it is replaced, so
  an unchanged reinstall keeps each inode and leaves no temporary file.

A symlink flipped by `mv` was the obvious alternative and is wrong on this Mac: `mv new old`, where
`old` is a symlink to a directory, does not replace the symlink but follows it and moves the new
link inside the directory. Measured, not assumed. `~/.baton/bin/sh` is not part of a set and is
neither re-signed nor replaced by the publish (D-038), and the launchd agent's fixed
`ProgramArguments` path is untouched: the reference lives under `~/.baton/`, never in the plist.

---

## 3. Files under `~/.baton/` and their shapes

```
~/.baton/
├── bin/                     the installed relay (§2); bin/sh is the ad-hoc signed, granted copy of /bin/sh; bin/Baton.app the notifier applet
├── notify/spool/<epoch>-<pid>-<n>        a Mac message waiting for the applet: title, body, target, one line each; written as .<name>, then renamed
├── notify/target                         the newest posted message's target, which a click opens (claude://claude.ai/code/session_<id>, or empty)
├── config.json              Baton's numbers (below)
├── projects/<project>/
│   ├── project.json         {"path": "…/Reclaim", "plan": "docs/MILESTONES.md", "check": {"command": "sh tests/run.sh", "deadline_seconds": 1800}} plus what onboarding adds (below)
│   └── permissions.json     {"permissions": {"allow": [...], "deny": [...]}}
├── checks/<project>/<milestone>-<attempt>/
│   ├── tree/                the detached checkout of the claimed merge commit, while the standing check runs there; removed when it ends
│   ├── output.txt           that run's combined output, which the consumed event points at
│   ├── output.txt.exit      the done-marker, renamed into place; present while the check has finished and evidence has not yet been written
│   ├── started_at, pid, revision, deadline, chain.json
│   │                        the start interlock: elapsed time, the recorded pid, the frozen chain a later tick must not re-resolve
│   └── result.json          the completion evidence in full, written before the artifact moves so a lost receipt can be reconciled from it
├── checks/judge/            a judgment request in progress: its settings file, its answer, its stderr and its done marker; one directory, swept at the start of the next request, because the verb holds the lock and anything there is an orphan (§4.5)
├── settings/<project>-<milestone>.json   the composed --settings file (below)
├── settings/wake.json                    the wake session's settings: Remote Control on, the deny list, no hooks; it runs in ~/.baton-wake/
├── worktrees/<project>/<milestone>       the managed root: a milestone worktree Baton created, on branch m<nn>
├── prompts/<session>/<n>.txt             prompt sidecars, n from 1 per session
├── inbox/<milestone>-<session>.json      handover artifacts, .tmp then rename
├── archive/<milestone>-<session>-<consumed-at>.json   handovers acted on, and the repeats of them
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

Three more numbers default in code and are left out of the file an install writes: `keepFinished` 3,
`idleStopMinutes` 60 and `wakeModel` `haiku` (REQ-LIFE-02, REQ-LIFE-04). Three more again for the
planning lane: `planningAttempts` 3, `planningModel` `opus` and `planningEffort` `high`
(REQ-GENERATE-01, REQ-GENERATE-10). Planning is the work every later milestone of that project
inherits, which is why its defaults are the capable model at high effort rather than a plan row's.

**`projects/<project>/project.json`, as onboarding leaves it.** `path`, `plan` and `check` are what
the tick and the completion check read; everything else is what the one confirmation recorded and
what the plan needed in order to be read as it stands. A project registered before onboarding
existed carries only the first two and is read exactly as strictly as it was.

```json
{
  "path": "/Users/danny/Documents/Apps/Reclaim",
  "plan": "docs/MILESTONES.md",
  "check": { "command": "sh tests/run.sh", "deadline_seconds": 1800 },
  "goal": "one sentence saying what the project is for",
  "done": "one sentence saying what finished looks like",
  "constraints": ["the controller stays POSIX shell"],
  "non_goals": ["replacing the controller with Swift or a SQLite store"],
  "plan_format": "adapted",
  "onboarded_at": "2026-09-19T08:00:00+01:00",
  "cli": { "version": "2.1.278 (Claude Code)", "checked_at": "2026-09-19T08:00:00+01:00" },
  "adaptation": {
    "defaults": { "Model": "opus", "Effort": "", "Remote": "" },
    "status_map": { "complete": { "status": "done" },
                    "retired": { "status": "held", "why": "…it never runs and never satisfies a dependency…" } },
    "gates": "absent"
  },
  "start": {
    "at": "2026-09-19T08:00:00+01:00",
    "eligible": [ { "milestone": "M03", "brief": { "path": "docs/milestones/M03.md", "heading": "Copy-ready session prompt" },
                    "disposition": "run" },
                  { "milestone": "M04", "brief": { "path": "docs/milestones/M04.md", "heading": "Copy-ready session prompt" },
                    "disposition": "wait", "wait_for": ["M03"] } ]
  }
}
```

`adaptation` is present only for `plan_format: "adapted"`, and `plan_owed` (`reason`, `owner`)
replaces `start` for `"generated"`, where there is no milestone to name. `start` is the **starting
handover**: `dispositions_in_force` reads it after every archived handover, so the first real one
supersedes it entry by entry and nothing has to remove it (REQ-ONBOARD-07). It is not a completion
claim — it names no merge and is checked as none.

`plan_owed` gains a third field once a generation attempt has run: `defects`, each `{what, repair}`,
which is what the next attempt's prompt is composed from and what a person reads when the bound is
spent. It is Baton's own state, so removing the whole object is what undoes generation's record of
where it got to; the plan and the briefs an attempt wrote stay in the repository, because that is
what the next attempt repairs rather than replaces (REQ-GENERATE-07).

**The composed settings file**, `~/.baton/settings/<project>-<milestone>.json`. The mode rides the
flag (`--permission-mode bypassPermissions`); `defaultMode` is repeated as documentation. Allow and
deny are copied from the project's `permissions.json`; no `ask` rules. `remoteControlAtStartup` is
`true` for every dispatch: Remote Control is what lists a session in Claude.app and on the phone,
and writing it keeps that from depending on the account's default (REQ-ESC-08, D-081). Three hooks,
each carrying
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
      "Edit(//Users/danny/.baton/notify/**)", "Write(//Users/danny/.baton/notify/**)",
      "Edit(//Users/danny/.baton/config.json)", "Write(//Users/danny/.baton/config.json)",
      "Edit(//Users/danny/.baton/last-tick)", "Write(//Users/danny/.baton/last-tick)",
      "Bash(*.baton/archive*)", "Bash(*.baton/rejected*)", "Bash(*.baton/prompts*)",
      "Bash(*.baton/settings*)", "Bash(*.baton/projects*)", "Bash(*.baton/status*)",
      "Bash(*.baton/lock*)", "Bash(*.baton/config.json*)", "Bash(*.baton/last-tick*)",
      "Bash(*.baton/notify*)", "Bash(*.baton/bin/lib*)",
      "Edit(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
      "Write(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)",
      "Bash(*com.baton.tick*)"
    ]
  },
  "remoteControlAtStartup": true,
  "statusLine": {
    "type": "command",
    "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' '/Users/danny/.baton/bin/statusline'"
  },
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' '/Users/danny/.baton/bin/stop-gate'" }] }],
    "StopFailure": [{ "hooks": [{ "type": "command",
      "command": "BATON_HOME='/Users/danny/.baton' BATON_PROJECT='Baton' BATON_MILESTONE='M02' '/Users/danny/.baton/bin/stop-failure'" }] }]
  }
}
```

The deny list above is the one `install.sh` writes for Baton (D-026). The two classes are fixed
("Where an escalation goes" §3): privilege escalation, and Baton's own state by named path — a
session writes `~/.baton/inbox/` and nothing else under `~/.baton/`. The path forms are
`Read|Edit|Write(//<absolute path>)` for the tools that take a path and `Bash(*.baton/<name>*)` for
a shell command that names the path (`bin` excepted except for `bin/lib`, so a session can run
`baton status` but cannot name a write into the sourced libraries; D-112); each
named path is one rule, so a directory the list does not name (one a session creates itself under
`~/.baton/`) is not denied, and a Bash fragment is never complete, which is the stated limit of the
class. `worktrees/` is one of the directories the list does not name, and must stay that way: it
holds the session's own working directory, and a rule denying writes under it would deny the
session its own repository (D-153). A `permissions.json` with no deny rules fails the `settings` stage rather than dispatching
without the rail. Under `bypassPermissions` the allow rules allow nothing and cost nothing; they are kept
so that a hand-started session under `default` passing the same file behaves as a dispatched one.

**The status feed**, `~/.baton/status/<session_id>.json`: the statusLine command's stdin, verbatim.
The fields the tick reads: `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`
(`resets_at` in epoch seconds), `context_window.used_percentage`, `cost`, `model`, `session_id`,
`transcript_path`. Telemetry, not history: overwritten, never appended, never archived. A captured
example is `.scratch/baton/prototype/obs/28926e91-26fc-4602-9abd-1ce89cefeb28.json`.

**The lock**: `mkdir ~/.baton/lock` succeeds or the verb exits; the directory holds `pid` and `at`
so a stale lock can be reported with its age. Released on exit; the marker is written after.
If `at` is missing or cannot be parsed, reporting and rescue read the directory's mtime instead.
Rescue still requires an aged lock and a holder that is gone, claims by rename, and rechecks the
claimed metadata; it never repairs a live lock's files (D-117).

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
   **Before each project's self-check, the generation pass** (`planning_pass`, REQ-GENERATE), for a
   project whose registration carries `plan_owed`. Before, because a project that owes a plan is
   exactly a project this step fails and skips, so nothing later in the tick would ever reach it. It
   measures a plan a planning session has since written and, where it holds, adopts it through
   `onboard_commit`'s own seeding path — after which the self-check on the same project reads the
   plan and the park it raised is closed by the ordinary `park_resolve` below, in the one tick.
   Where no plan holds yet, it produces one candidate, `M00-plan`, which joins step 7's list and is
   admitted under the same cap as any other. It runs only on a tick that could read the rows, for
   the reason step 2's guard gives, and nothing in the tick waits on the session it asks for.
2. **Consume the inbox.** First the reconciliation, before any inbox file is looked at: each file
   in `archive/` that derivation 4 names under `unrecorded` is a consumption a tick was killed in
   the middle of, and it gets the `consumed` event it never got, carrying `reconciled: true`, plus
   the ending escalation that consumption owed. It is a receipt write and not a second check —
   the move only ever follows a passed check, and a completion's evidence was written to
   `checks/<project>/<milestone>-<attempt>/result.json` before the move — and it comes first
   because every rule after it reads the log it writes into (F07, D-146).
   Then, for each `*.json` (never `.tmp`), first the repeat test: a file holding
   the same JSON value, `written_at` included, as an archived copy of a `consumed` handover for its
   milestone and session — its first file or an earlier repeat's — is moved to the archive with a
   `repeated` event naming the first file, and nothing else follows — no check, stop, route, park or
   `consumed` event (D-095, D-097); a log the test cannot read leaves the file in the inbox. Otherwise: parse; check provenance (the `session`
   has a transcript found by glob, the `project` is a registered checkout); for `complete`, refuse
   the fields only Baton writes (`baseline`, `changed_paths`, `check_result` — `reserved-field`),
   verify `merged_as` is an ancestor of `main` in the canonical checkout, and verify each `brief`
   pointer's path and heading on `main`. Then, last because it is the only expensive one, the
   completion chain of REQ-ARTIFACT-10: the attempt's baseline `B` is an ancestor of its branch tip
   `T`, `T` is an ancestor of `merged_as`, the paths `B..T` changed touch the milestone's declared
   scope, and the project's registered standing check, started by Baton on a detached checkout of
   `merged_as` under `$BATON_HOME`. A tick that finds no check directory starts the check detached
   and returns pending, leaving the artifact; a tick that finds the directory and no done-marker
   leaves it running; a tick that finds the marker collects the result. Pending is not a consume
   failure and does not withhold the tick marker (D-184). A chain or scope that does
   not hold is a rejection; a check that ran and did not pass is not — the handover is consumed and
   the project is parked `main-broken` (D-151). A `complete` handover no `dispatch` event names is
   recorded `proved: false`, because Baton proves what Baton dispatched (D-145).
   Reject loudly to `~/.baton/rejected/` with a `rejected` event and a
   lane escalation; otherwise archive as `<milestone>-<session>-<consumed-at>.json` and log the
   `consumed` event. `asking` stops the session at once; `stopped` routes by reason.
   For rejection and the orphan sweep, JSON supplies identity first. Missing identity comes from
   the longest filename milestone prefix accepted by `parse_id` that leaves a complete UUID or
   bare hexadecimal session id. If both ids cannot be recovered, leave the file in the inbox and
   return failure rather than move it under a guessed lane. This keeps hyphenated milestones'
   live `.tmp` writers protected by the same session-row check (D-118).
3. **Reconcile rows** against the log's in-flight sessions: crash (`pid: null`, confirmed on two
   ticks), stall (`stallMinutes` of unchanged transcripts, the session's and its subagents'), live
   questions (`waitingFor: "input needed"`), a takeover (a typed record the log did not send), and
   the gap report. Before any of them, the three unparks only a tick can see, so a lane freed by one
   is a lane step 4 acts on in the same tick: an edit to the readings a park's own class designates
   (`edit_reread_check`), a live question answered in place (`question_resolve_check`), and a fork
   park whose unstopped original no longer has a row with a pid (`fork_resolve_check`, D-135). For
   `Remote: yes` sessions the row is not a park detector: parks are
   artifact-borne only, and an unanswered phone prompt surfaces as a stall.
4. **Waits and resumes.** Retries due (`retryMinutes`); rulings queued by `answer`; `merge-failed`
   and `main-broken` resumes; the `caffeinateMaxHours` bound. Every resume is flagless.
5. **Compute eligibility per project from the plan.** A milestone is eligible when every id in
   `Depends on` reads `done`, its `Status` is blank, and no uncleared gate holds it. `held` and an
   uncleared gate are the same state to the tick. A project with an open project-scope park
   (`main-broken`) skips steps 5 to 7: nothing new starts on ground a person has been asked to fix,
   and every redispatch for the project waits the same way, while steps 3 and 4 run on.
6. **Intersect with the handover's dispositions** (`dispositions_intersect`, D-071). For each
   eligible milestone, and each milestone a handover in force names, the disposition in force is
   the entry in the newest consumed `complete` handover of that project that lists it with `run`,
   `wait` or `held`, newest by the order derivation 4 first recorded each handover, which a repeat
   does not enter (D-096): `run` → a candidate; `wait` → honoured while any `wait_for` is not `done`,
   dispatched the moment all read `done`, a distant `wait_for` notifying once; `held` on a milestone
   the plan makes eligible — its gate cleared, or a gate the plan does not name → the plan wins,
   dispatch, `plan_override` (`dispatched_over_held`, written once the dispatch happened); `run` on a milestone
   the plan holds (`Status: held` or an uncleared gate) → the plan wins, withheld, `plan_override`
   (`withheld_over_run`). An override is written once per milestone, direction and gate since the
   milestone's newest dispatch. Exactly two things escalate, lane scope, by milestone name: a `run`
   the plan otherwise makes ineligible (`disagreement`) and a plan-eligible milestone no archived
   handover lists (`omitted`) — the latter only in a project with at least one archived `complete`
   handover, and not while a dependency's session is mid-run (its newest ending not yet one it wrote itself), because a close-out writes `done` at
   step (c) before its artifact at (d); an omission held back that way neither raises nor clears a park. Either park ends with `how: edit` the tick its condition no
   longer holds; after an edit resolution an omitted milestone still eligible is a candidate and a
   disagreement is withheld silently. A milestone with an open lane, an open lane park, or a live
   row carrying its name is not a candidate; a `Remote: yes` milestone is one like any other.
   Between 6 and 7, once per project and reading only the rows already in hand, the legacy sibling
   worktrees move into the managed root (`worktree_migrate`, REQ-DISPATCH-12): `git worktree move`
   for each `../<Project>-M<nn>` still on branch `m<nn>`, refused silently while a live row's `cwd`
   is that worktree or under it. It is before the dispatch because `worktree_of` resolves from git's
   registration, so a worktree moved here is found at its new path by the same tick's dispatch; and
   before the offline pass, so a worktree freed by a stop is moved on the next tick rather than
   against a listing that stop is not yet in. Nothing is deleted and nothing else in the tick reads
   a worktree's location, so a project whose migration fails costs that project nothing but the move.
7. **Apply the holds, then the cap** (`dispatch_run`, once across every project). Drop candidates on
   a model with an active `rate_limit` or `billing_error` wait (every model once a second model is
   limited). Drop Fable candidates while the `fableReserve` hold stands: `reserve_check` reads the
   newest status file by modification time that carries `seven_day.used_percentage` as a number,
   ignores it when its own `seven_day.resets_at` has passed, and writes `hold` at or above the
   reserve and `hold_lifted` below it (D-073). Count in flight: derivation 1 across every project,
   which counts each open lane whose current session has a live row — a question park included, a
   stopped `asking` session not. The listing it joins against is read here and not carried down from
   the top of the tick: steps 3 and 4 create executions, and a lane a redispatch or a copy fork has
   just moved onto a new session matches no row in the older listing, counts as nothing, and lets the
   cap admit over a worker that is running (D-130). A listing that cannot be read fails the pass
   rather than reading as empty. Dispatch while the count is below `cap`, in `cap_order`'s order:
   within a project, the handover's `eligible[]` order; each slot to the project with fewer in
   flight, counting the dispatches already ordered; then plan row order; then the project key
   (D-072). A dispatch that writes no `dispatch` event takes no slot, unless it could not be proved
   to have started nothing: a launch whose id did not parse or whose row never appeared, and whose
   worker was then neither identified nor stopped, counts against the cap for the rest of the process
   — no `dispatch` event names it, so derivation 1 cannot see it, and only a conservative count keeps
   the cap honest. The next tick reads the listing from nothing and needs no such reservation.
8. **Dispatch**, per candidate:
   - `git -C <path> worktree add $BATON_HOME/worktrees/<project>/M<nn> -b m<nn> main`, the managed
     root; if git has a worktree registered on that branch, reuse it where it stands and log the
     reuse with the commit it is at (REQ-DISPATCH-03, D-153 — the sibling path this step named
     before M09 is no longer where one is created or found).
   - Compose the settings file at `~/.baton/settings/<project>-<milestone>.json` (§3).
   - Read the kickoff prompt from the brief on `main` and replace part 2 whole with the slot line
     (§4.3); write the body to `~/.baton/prompts/<session>/<n>.txt` and hash it. The listing the
     slot line's "also in flight" list is derived from is read again here, for every dispatch after
     this pass's first, so a sibling admitted a moment ago is named; a listing that cannot be re-read
     ends the pass rather than being replaced by the stale one (D-177).
   - Resolve the effort: the `Effort` cell, else the Size the brief declares in its `## 1.` section
     on `main` (`Small` → `medium`, `Medium` or `Large` → `high`), else none, and the flag is left
     off (D-176). The planning lane takes model and effort from `config.json` instead (§6.4).
   - Run, with the worktree as `cwd` and `LC_ALL` set:
     `claude --bg -n "<session name>" --model <Model> [--effort <Effort>]
     --permission-mode bypassPermissions --settings <file> "<prompt>"`; parse `backgrounded · <id>`
     from stdout. No parsed id → the first cleanup in this process inspects fresh live rows with
     the lane's `session_name` and stops their jobs before `dispatch_failed` (§6.2). Later failures
     record `cleanup skipped; budget spent this tick`. Preserve stdout with nonempty stderr too; the
     empty-stderr fallback already preserves it (D-114). A skipped cleanup, a stop that was refused
     or never settled, a listing that could not be read, and an acknowledged launch whose row never
     appeared each leave a worker that may be running under no id Baton holds; each raises this
     process's unresolved count, which step 7 adds to the cap (D-130). A launch that exited non-zero
     printing nothing at all, whose one fresh inspection found no row of the lane's name, is the
     reading that says the CLI never started anything, and raises nothing.
   - `Remote: yes` is the same command. Every settings file carries `remoteControlAtStartup: true`,
     which connects the session and keeps its prompt, and a flagless resume restores it (D-080,
     D-081). `--remote-control` is never passed.
   - Read the row's `pid` from `claude agents --json`; if the row lookup fails, stop the known job
     id before recording failure if this process's cleanup budget is unspent. All jobs in that
     cleanup share one settlement loop. Refused, skipped or unsettled cleanup remains in the
     bounded failure detail. This limits added polling to one lookup and one settlement loop
     per process, not wall-clock time: calls have no timeout and ordinary row discovery remains
     per candidate (D-114). On a valid row, start `caffeinate -i -w <pid>` detached.
   - Log the `dispatch` event.

**The session name** is `Baton · <project> · <milestone>`, except when the project key is `Baton`
itself, where the prefix has already named the project and the name is `Baton · M02`. The prefix is
the only ownership marker a row carries and is never dropped; the key is only not repeated
(D-036). `session_name` in `lib/templates.sh` composes it, and the refusal to dispatch over a live
row of the same name reads the same function.

**A finished session's process**, between steps 6 and 7, once across every project (REQ-LIFE, D-087).
`offline_check` takes offline each finished session Baton dispatched — its `complete` handover consumed with an attempt and its milestone
not dispatched since — whose row has a pid and reads `idle`, whose transcripts are at least
`idleStopMinutes` old, and which ranks past `keepFinished` among the finished sessions with a live
process, newest transcript first: `claude stop <job>`, and one `offline` event when the CLI took the stop
(a refused stop is printed and tried again next tick). It runs across projects because what it bounds
is memory, which is the Mac's, and before the dispatch so a process is gone before a new one starts.
Then `wake_session_ensure` keeps the wake session, `Baton · wake`, once any `offline` event exists:
nothing while its session has a live row; a flagless resume once five seconds of listings show no pid
for it, stopping the original if the resume forked; a fresh `--bg` start in `~/.baton-wake/` with
`settings/wake.json` when it never started, its last resume was refused or its transcript is gone; a
refusal, as a `wake` event, when that file is missing or its deny list is empty; at most once per
`retryMinutes`. Its session is read from the log's `wake`
events, because a stopped session drops out of `claude agents --json` and a search by name would start
a new one after every stop. The two passes read the whole log once each beside the tick's other reads
and scan it for each consumed handover; at today's size that is milliseconds, and it is counted
against REQ-LOG-01's rule that the log is split only once a tick's scan is measurably slow.

Then the marker, after the lock is released, only when every top-level pass completed. A failed
pass is retained as status 3 through the remaining work; it withholds the marker so the next gap
reading still uses the last completed tick (D-115). A handled self-check park is not a failed pass.

### 4.2 The verbs

| Verb | Does | Side effects |
|---|---|---|
| `baton tick` | the eight steps for every registered project | the log, the archive, dispatches, the marker |
| `baton answer <milestone \| project/milestone> <ruling \| n>` | resolves against parked lanes across all projects; one match: `claude stop <id>`, a wait for the stop to land, then a flagless resume with the ruling label, and the resolution once the resume was delivered or forked; several refuse with the candidates; none refuses; an empty ruling refuses; `continue` on a lane taken over and not parked is the hand-back | `resume`, then `resolution` |
| `baton status` | the one view (§5.3), last tick first, whole file | none |
| `baton plan <project>` | the graph as the tick sees it; validates every `Model` cell; lists widenings; then every plan-eligible milestone's unmet dispatch preconditions, one line per failure as `<id>  <stage>/<check>  <path>  <detail>`, and returns 1 if any is unmet | none |
| `baton dispatch <project> <milestone>` | step 8 alone, by hand, after checking eligibility and that no live row carries the milestone | worktree, settings, sidecar, session, `dispatch` event |
| `baton allow <milestone \| project/milestone> '<rule>' [--resume]` | writes the rule as typed to `permissions.json` and the dispatched settings file in place, both parsed before either is written; refuses an `ask` form, JSON, a rule over 1 KB or with a newline, and `--resume` on a parked lane; reports a rule the deny list also names as `denied`; `--resume` stops and flaglessly resumes | `widening` event when a file changed; a `resume` event |

| `baton wake [<milestone \| project/milestone> [<text>]]` | with no milestone, lists every finished session as running or offline with its last activity; with one, refuses a milestone that has not finished, names a running session's thread rather than resuming it, and otherwise resumes the session flaglessly with the text labelled as the person's — the command the wake session runs for each message it receives | a `wake` event with `how: verb` and the prompt sidecar |
| `baton onboard <path>` | resolves the canonical checkout and the project key; detects the toolchain, and from it the standing check and the allow rules; finds and classifies the plan (`native`, `adapted`, `generated`); makes one judgment request for the intent statement; prints three lines and reads a yes or no; on yes writes the registration, the rail and the starting handover, and reports the plan and its dispatch preconditions through `plan_render` and `plan_preconditions_report`. Refuses a path that is not a Git repository, a key already registered elsewhere, and a `Status` word it will not map. On anything but a yes it writes nothing and returns 1 | `projects/<key>/{project.json,permissions.json}`, one `onboarded` event |

Every verb enters through the lock. `status` and `plan` write nothing. `onboard` writes nothing
before the yes, and everything after it in this process — the relay's own, under the lock — because
the paths it writes are ones a dispatched session's deny rules forbid and nothing is widened to let
one write them (REQ-ONBOARD-01).

### 4.3 The texts

**The slot line**, composed at dispatch, replacing the paragraph that begins `WHAT ELSE IS IN
FLIGHT.` in the brief's prompt — the only paragraph touched. Example:

> WHAT ELSE IS IN FLIGHT. You are working in /Users/danny/.baton/worktrees/Reclaim/M19 on branch
> m19; the canonical checkout is /Users/danny/Documents/Apps/Reclaim — merge there at close-out
> and refresh there. Also in flight: M28 (worktree /Users/danny/.baton/worktrees/Reclaim/M28,
> brief docs/milestones/M28.md). Stage only your own paths; never git add -A. This is attempt 2 at
> this milestone; a previous attempt left work on this branch at 1a2b3c4, and the brief may hold
> completion evidence, which the recovery clause covers. Do not start the milestone after this one.

The attempt sentence appears on attempt 2 and later. "Also in flight" lists every other milestone
**of the same project** whose lane is open, with its worktree path and its brief: a path since
D-178, because the basename it named before is the milestone's own id under M09's managed root and
so says nothing. The list is derived against a listing read for this dispatch rather than the one
the pass opened with, so the second of two milestones admitted in one tick names the first; the
first reads "Nothing else is in flight", which at the moment it starts is true (D-177).

**Continue** — after `rate_limit`, `billing_error`, `overloaded`, `server_error`,
`max_output_tokens`, and a crash (`<class>` = the StopFailure `error` or `process gone`):

> Baton resumed this session after a temporary stop (<class>), not a fault in the work. <milestone>,
> attempt <n>, resume <r>. Continue exactly where the last turn ended. If a tool call was
> interrupted, its result was not received — check the state before repeating it. Do not switch
> model or work around a limit. The handover artifact is still owed.

**Finish the close-out** — after `no-handover` only:

> Baton resumed this session because its last turn ended without a handover artifact. <milestone>,
> attempt <n>, resume <r>. Finish the close-out now by the method in CLAUDE.md and write
> <BATON_HOME>/inbox/<milestone>-<session>.json, printing it last. Write the outcome that is true:
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
every variant**: a note saying the CLI `started a copy` is a fork, and the new id is the 8-hex token
after the **last** ` as `; the original is the token after `session ` or `background session `. The
rule is written that way because seven of the eight read "started a copy as <Y>" and the generic one
does not, so a test on that literal reads seven variants and calls the eighth a refusal, which is
the duplicated-session failure the classifier exists to prevent (D-058). Success prints
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

- **Both `stop-gate` and `stop-failure` stand down on a closed lane, as their first rule**: when a
  file in `~/.baton/archive/` has this `session`, this `milestone` and `outcome: complete`, each
  exits 0 having written and printed nothing (D-078). The archive is matched by the file's fields,
  never its name, because a handover is archived under whatever name it arrived with. The session's
  handover has been acted on, so what a person does in it afterwards — a question about what was
  decided, or work continued by hand — is theirs, and neither a demanded handover nor a `no-handover`
  or `api-error` artifact the tick would route follows it. An archived `stopped` handover does not
  close the lane. The way back into a finished session is a flagless resume or Claude.app: a resume
  with any flag starts a copy under a new session id that no archived handover names, and that copy's
  hooks do not stand down.
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


### 4.5 The two session roles

Baton dispatches sessions to work milestones. From M11 it also needs judgement that is not a
milestone's — what a project is for, whether a plan still serves it — and there are two shapes that
can take, with different consequences for the cap. Both are written down here **before the first of
either runs**, because the failure they can cause is not one an implementation discovers gently: a
role that holds an admission slot while its own result is awaited is a lane nothing will close, and
`do_unresolved` counts a launch that could not be proved to have started nothing, so the count stays
open (D-130).

**A judgment request** is a foreground `claude -p` inside a verb.

| | |
|---|---|
| Identity | the project, the role (`intent` is the only one) and the moment; nothing persists it but the `onboarded` event |
| Where it runs | inside the verb, under the verb's own lock, against the subscription like every other call Baton makes |
| Admission slot | **none.** It has no session name, no row, no attempt and no artifact, so derivation 1 cannot see it and the cap is untouched. This is the whole of why the role cannot deadlock the cap: there is no slot to hold |
| Terminal outcomes | `answered`, `unparseable` (no labelled line to read), `refused` (a non-zero exit, whose stderr is quoted), `timed-out` (the deadline, which exists because the verb holds Baton's lock), `unavailable` (the binary will not answer `--version`). Every one is terminal |
| Restart | running the verb again. There is no resume, no attempt count and no ladder: a request is not a session, and nothing owes it a handover |
| Failure posture | nothing is written. A goal Baton guessed at is never put to a person as a statement to confirm |

**A judgment session** is a session Baton dispatches, like a milestone's: plan generation (M12) and
the independent scope guard (M15-c) are the two the plan has.

| | |
|---|---|
| Identity | `(project, role, attempt)`, with a session name, a `dispatch` event and a baseline, exactly as a milestone's attempt has |
| Admission slot | **one**, counted by derivation 1 like any lane, because it is one |
| Terminal outcome | an artifact, with the Stop gate injected to insist on one, and the ladder behind it |
| The rule that keeps the cap honest | **nothing waits on its result inside a verb or a tick.** The verb that needs one records the request and returns; the tick dispatches it; its handover closes the lane and the next tick reads the answer. A verb that blocked on a session it had just dispatched would hold the lock while the session it was waiting for could not be admitted |

Onboarding's intent statement is a request, and deliberately: it is three lines and takes seconds,
and a person is at the terminal waiting for it. Plan generation reads a whole repository and writes
a plan and its briefs, which is a session's work and has a session's cost.

**Plan generation is the first judgment session, and `lib/planning.sh` is it.** Its lane carries the
reserved milestone id `M00-plan` — reserved because a generated plan naming it as a row is refused,
and an id rather than a role name because `artifact_ids` recovers a handover's identity from its
filename through `parse_id`, and a name that function refuses is a handover that can never be
rejected. It is dispatched through `dispatch_one` like every milestone and differs in three places:
its model and effort come from `config.json` rather than a plan row, its preconditions are the
checkout and the rail rather than a brief on `main`, and its prompt is Baton's own text rather than
a brief's fenced block. Its declared scope is Baton's own too — the two paths its prompt named — so
its completion is proved exactly as a milestone's is (REQ-GENERATE-01, 09).

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
| **done** | `Status: done` | nothing on the lane; the worktree is kept and the session's hooks stand down, so the session can be resumed by a person. Its process is kept while the session is among the `keepFinished` most recently active finished sessions, and taken offline once idle past that; `baton wake`, run by the wake session, brings it back (REQ-LIFE) |

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
10. finished sessions taken offline — `offline  <project>/<milestone> · message Baton · wake, or baton wake
    <project>/<milestone>` — and the wake session when its last start or resume was refused, with the
    reason; a running finished session is the ordinary case and prints nothing (REQ-LIFE).

Whole file, every time; no flags; no denials line. A section with nothing in it prints nothing, so
the file is as short as the state is quiet. Line 9 exists because the move is the consumption: a
file still in the inbox is a handover Baton has not read, and nothing else in the view would say so
(D-035).

---

## 6. The dispatch log

One append-only JSONL at `~/.baton/log.jsonl`, twenty event kinds over a five-field envelope,
prompt bodies in per-session sidecars the events point at and hash, every count derived over
`(project, milestone, attempt)`. Sections 6.1, 6.2, 6.4 and 6.5 are "The dispatch log" §1, §2, §5
and §8, copied.

### 6.1 The envelope

Every event is one JSON object on one line, with `at` and `kind` always present.

| Field | Always? | Value |
|---|---|---|
| `at` | yes | ISO 8601 **with offset** (`2026-09-11T23:14:02+01:00`) |
| `kind` | yes | one of the twenty in §6.2 |
| `project` | when the event has one | the project key: the basename of the canonical checkout |
| `milestone` | when the event has one | the plan file's `ID` cell |
| `session` | when the event has one | the `sessionId` — `CLAUDE_CODE_SESSION_ID`, the row's `sessionId`, the transcript's filename |
| `attempt` | when the event belongs to one | the integer the rule below derives |

**A field the event does not have is absent, never null.** A rule keying on a null fails silently;
one keying on an absent field fails at `has()`, in the test. Five kinds can carry no `session`
(`dispatch_failed`, `self_check_failed`, `plan_override`, a `hold` whose cause
is `fableReserve`, which carries no `project` either, and a `wake` that could not start the wake
session), and three carry no `milestone` (`self_check_failed`, `hold`, and a `wake` about the wake
session, which carries no `project` either).

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

Twenty-three kinds. Fields listed are those beyond the envelope.

| Kind | Fields | Which rule reads it | Once-only key |
|---|---|---|---|
| `dispatch` | `name`, `model`, `effort`, `remote`, `worktree`, `branch`, `worktree_reused`, `role` (`planning`, on the planning lane alone; absent elsewhere, because a field an event has no value for is absent from it), `baseline` (the commit the worktree stands at, on every dispatch; it was `worktree_commit` and was written only for a reused worktree — D-145), `settings`, `prompt_path`, `prompt_sha256` | the attempt count; the ladder's reset point; in flight; the long-running clock; the takeover candidate set; the cap; **the model actually run**, for grading after the fact; **the baseline a completion claim has to descend from** (REQ-ARTIFACT-10) | — |
| `dispatch_failed` | `stage` (`worktree`\|`settings`\|`prompt`\|`launch`\|`service`), `detail`; no `session` | the second consecutive since the pair's newest `dispatch` escalates, lane scope, and that park is then what stops the retry (D-049); `stage: service` escalates, project scope, which is M06's | — |
| `consumed` | `outcome`, `reason` or `error`, `written_by` (`session`\|`stop-gate`\|`stop-failure`), `merged_as`, `blocked_by`, `archive`, `completion` (for a `complete` outcome: `proved`, and when proved `attempt`, `baseline`, `candidate`, `branch`, `integration`, `changed_paths` (the first ten), `changed_count`, `check`, `evidence`), `reconciled` (true when the receipt was written by a later inbox pass rather than by the consumption itself) | every ending's routing; the ladder's reset; the notification keys' reset; the terminal test for in flight; the wait's start before its first retry; the completion evidence a person reads and derivation 4 joins on | — |
| `repeated` | `outcome`, `archive` (where the file came to rest), `repeats` (the `archive` of the `consumed` handover it repeats); the envelope is that handover's | derivation 4's join, which claims the archived file; no rule acts on it, so a repeat routes, parks, resets and ranks nothing (D-095) | — |
| `rejected` | `path` (where the file came to rest: `~/.baton/rejected/` for a rejected file, `~/.baton/archive/` for a rejected `eligible[]` entry of a file that was consumed), `reason` (the rule's name) | the lane escalation that follows a rejection (the log is the record, so no sidecar) | — |
| `resume` | `resume_kind` (`continue`\|`finish`\|`ruling`), `resume`, `class`, `outcome` (`delivered`\|`forked`\|`refused`), `prompt_path`, `prompt_sha256` | the resume count; the ladder (`refused` is a failure ending); the long-running clock; the takeover candidate set | — |
| `copy_fork` | `from_session`, `note` | the session currently carrying an attempt | — |
| `wait_retry` | `error`, `since`, `retry` | the dispatch hold; the 1 h and 2 h notification ceilings; the six-hour `caffeinate -i -t` bound; `status`'s next-retry line | — |
| `crash_sighting` | `pid` (null), `state`, `sighting` (1 or 2) | the two-tick confirmation before a crash is acted on | — |
| `takeover` | `first_unmatched_at`, `first_unmatched_uuid`, `typed_count` | stop acting on the lane; restart the long-running clock; reset the attempt's notification keys | per session |
| `escalation` | `class`, `scope` (`lane`\|`project`), `carries`, `channel` | the parked-lane derivation; `status`; `baton answer`'s resolution | — |
| `resolution` | `how` (`ruling`\|`answered in place`\|`edit`), `escalation_at` | the unpark | — |
| `reread_baseline` | `escalation_at`, `version`, `policy`, `hashes` | `edit_reread_check`, for a park whose receipt predates the policy its class now uses: the readings the old receipt never held, taken once so later ticks compare against them rather than rebaselining every minute. It resolves nothing — the park stands the tick it is written (D-134) | per park |
| `notification` | `class`, `key`, and the class's own fields | the once-only rule | per `(project, milestone, attempt, class)`, with the class's extra term where it has one |
| `hold` | `model` (or `all`), `cause` (`rate_limit`\|`billing_error`\|`fableReserve`), `reading`, `status_file` | the dispatch hold; the `fableReserve` guard | per `model` and `cause` |
| `hold_lifted` | `model`, `cause` | closes the hold | — |
| `widening` | `rule`, `permissions_file` | `baton plan`'s provenance of allow rules | — |
| `plan_override` | `direction` (`dispatched_over_held`\|`withheld_over_run`), `gate`, `cleared_by` | `status` showing the plan doing its job; never an escalation | — |
| `self_check_failed` | `stage` (`read`\|`parse`\|`git`), `path`, and for `parse` also `table`, `row`, `cell`; `detail` | the stage and cell beside the project-scope escalation the failure raises (`plan-unreadable` or `plan-unparseable`), written once while that park stands (D-041) | — |
| `offline` | `job`, `idle_minutes`, `rank` (the session's place among the finished sessions with a live process, newest transcript first), `kept` (`keepFinished` as read) | the offline rule's once-only test: no second stop while an `offline` event for the session is no older than its transcript (REQ-LIFE-01) | per session and transcript |
| `wake` | `how` (`verb`\|`started`\|`resumed`) and `outcome` (`delivered`\|`forked`\|`refused`) always; `note` — the CLI's line on a resume, the reason on a refusal, absent on a start that produced a session; `prompt_path` and `prompt_sha256` on every wake that delivered a prompt, absent on a refused start; `copy` on a verb wake that forked (the copy's session id); `from_session` on a wake-session resume that forked; `name` for the wake session, and `job` on its start. A milestone's wake carries its project, milestone, session and attempt; the wake session's carries a session only, and a start that produced none carries neither | which session is the wake session (the newest without a milestone that was `delivered` or `forked`); which session a milestone's later wake addresses (the newest `copy`); its retry bound, one attempt per `retryMinutes` (REQ-LIFE-03, REQ-LIFE-04) | — |
| `worktree_moved` | `from`, `to`, `branch`; no `session` and no `attempt`, because a move belongs to the worktree rather than to any run of the milestone | nothing: the migration re-reads git every tick and is idempotent without it, so this is the record a person reads to find where a worktree went and to pair a transcript directory with its new path | — |
| `onboarded` | `checkout`, `plan`, `plan_format`, `toolchain`, `check`, `cli_version`, `start` (one `{milestone, disposition}` per starting-handover entry) or `plan_owed`; no `milestone`, `session` or `attempt`, because onboarding belongs to the project and not to a run of anything | nothing reads it to decide: the registration is the state and this is the record of who wrote it and when, which is the answer to M08's recorded question of whether a session or the relay wrote the protected paths | one per project for the confirmation, and one more for a run that seeded a starting handover the registration did not have — which is a second `baton onboard` over a project whose plan has since arrived, and the tick adopting a generated plan (REQ-ONBOARD-08, REQ-GENERATE-08). A run that changed nothing material writes none, and an adoption writes no `cli_version`, because nothing asked the binary anything |
| `plan_generation` | `outcome` (`adopted`\|`refused`\|`exhausted`), `attempts` (the planning lane's dispatches so far), and for `adopted` the `plan` and the number of `milestones`, for `refused` the count of `defects` and the `first` of them, for `exhausted` the `max` and the standing `reason`; the milestone is `M00-plan` | nothing reads it to decide — `plan_owed` in the registration is the state — and it is the record of what generation did with each attempt, which is the answer to "why is this project still parked" | `refused` and `exhausted` once each since the planning lane's newest dispatch, which re-arms both: each is a state, and a tick that wrote one per sighting would write one a minute (REQ-GENERATE-07, 10) |

**Escalation classes.** Lane: `asking`, `question`, `ladder-end`, `unfinished-twice`, `blocked`,
`merge-failed`, `other`, `disagreement`, `omitted`, `model_not_found`, `dispatch-failed`. Project:
`plan-unreadable`, `plan-unparseable`, `main-broken`, `baton-unhealthy`.

**What `carries` holds, per class.** `asking`: `question`, `options`, `recommendation` and `context`
from the artifact, cut in bytes (D-063), or `detail` and `archive` when those cannot be carried.
`question`: `row`, `job`, `waiting_for`, `detail`. `merge-failed`, `other` from a stopped artifact:
`detail`, `archive`. `other` from a rejection: `rule`, `path`. `ladder-end`: `failures`, `ending`,
`last_detail`, `detail`. `unfinished-twice`: `newest`, `previous`, `detail`. `blocked`: `blocked_by`,
`blocker_state`, `detail`. `model_not_found`: `model` (the attempt's own), `plan`, `detail`.
`dispatch-failed`: `consecutive`, `stage`, `detail`. `omitted`: `detail`. `disagreement`:
`disposition`, `handover`, `waiting_on`, `detail`. `main-broken`, a project class with a milestone,
session and attempt: `detail`, `archive`. Another project class: the self-check's or the lock's fields
and `detail`. A lane park whose class an edit resolves, or which no ruling can reach — no project,
session and attempt — and a `merge-failed` or `main-broken` park also carry `reread`, an explicitly
versioned receipt: `{version: 2, policy, hashes}`, with `status_at_park` beside them for the two
classes a `done` ends. The policy is the class's own (`class_reread_policy`) and it names the only
fields that are compared (`policy_fields`) — `effective-model`: `model_sha256`; `instructions`:
`brief_sha256` and `work_plan_sha256`; `blocker-and-instructions`: those two and `blocker_sha256`;
`close-out-status`: `status_sha256`. `model_sha256` is over the milestone's effective parsed model,
`work_plan_sha256` over its own execution fields and dependencies plus the ids and dependency edges
of every milestone downstream of it — row position and `Status` excluded, and a downstream row's own
`Model` and `Effort` with them — `blocker_sha256` over the `blocked_by` row's id and status,
`status_sha256` over the milestone's own status, and `brief_sha256` over the kickoff prompt on `main`
(D-060, D-134). The version and the policy say how to read the hashes and are never themselves
evidence. `edit_reread_check` compares the designated fields, counting a field newly present as
changed and a field absent now as no change, and writes `resolution` with `how: edit` on a
difference — for `merge-failed` and `main-broken` only when `status_sha256` changed, the milestone
now reads `done` and `status_at_park` was not `done` — the close-out done by hand (D-074). A receipt
written before the policies carries no `version`; its exact brief digest and its `status_at_park` are
kept and compared, and the readings it never held are taken once into a `reread_baseline` event while
the park stands. An `omitted` or `disagreement` park
also ends with `how: edit` the tick its condition no longer holds (D-071).

**Notification classes.** `rate_limit`, `billing_error`, `unrecoverable`, `transient`, `stall`,
`long-running`, `blocked_by`, `distant_wait_for`, `prompt-lost`, `gap`, `takeover-silent`. Three
carry an extra key term beyond `(project, milestone, attempt, class)`: `distant_wait_for` keys also
on the handover and the named milestone; `blocked_by` on the named blocker; `gap` on the marker
value the gap was measured against, so one outage reports once.

##### Footer: what is a derivation, what folded, and what is gone

- **`worktree_pruned` is historical.** M06's prune wrote it (D-075); the prune is gone (D-078), so no
  tick writes it and no derivation reads it, but a log written before 2026-09-12's M07 merge may
  hold one.

- **The gap report is a derivation, not an event.** The gap is the reading instant minus
  `~/.baton/last-tick` — the tick's own start when the tick reads it, `now` for everyone else (D-174);
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
compares its newest message record against every `dispatch` and
`resume` sidecar for the `(project, milestone)` — not the session alone, because a copy fork's
transcript is a byte-for-byte copy of its parent's rewritten to the new id. The record's text is
normalised and hashed the same way the sidecar was; the normalisation is checked once, offline,
against the prototype's captured pair (live item 45). **The lane is taken over exactly while the
newest message record is one Baton did not send.** If only an `.orphaned-<ts>-<hash>.jsonl` sibling
exists, the lane escalates with the sibling's path rather than being scanned.

**A message record** is whatever a person or Baton put into the session, in the shapes a transcript
gives it (D-085): a `user` record, `isMeta` not true and `isCompactSummary` not true, whose
`promptSource` is `typed` (Baton's own prompts, and a terminal) or `queued` (a message sent from
Claude.app between turns, after a `queue-operation` enqueue and dequeue), or whose `origin.kind` is
`human` (a slash command); or a `queued_command` attachment whose `origin.kind` is `human`, its text
`attachment.prompt` — a message sent from Claude.app while a turn runs, absorbed into it. Every dispatched
session is on Remote Control, so these are how a person types into one. A `queued_command` whose origin
is `peer` (another session) or which carries a task notification, and the Stop gate's `Stop hook
feedback:` record, are not a person's. Compaction appends and never rewrites.

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
3. **Taken over.** Every in-flight lane whose transcript's newest message record is not one Baton sent
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
   killed between the move and its event leaves behind and which nothing else would show; the claims
   are read from every project's events, because `archive/` is one directory for all of them. **A
   handover is listed once while an archived copy of it stands.** A file delivered again holding the
   same value as an archived copy — the first file, or an earlier repeat's — is archived too, claimed
   by a `repeated` event rather than a `consumed` one and listed under `repeated`, so the `consumed`
   list's order — the order each handover was first acted on — is the ranking step 6 reads (D-096).
5. **Each active wait and its first-failure time.** The newest `consumed` with `reason: api-error`
   for a `(project, milestone, attempt)` that has no later `consumed` with `written_by: session` and
   no later `dispatch`. Its start is the `since` its `wait_retry` events carry — and **before the
   first retry exists, `since` is that `consumed` event's own `at`**. The next retry is the newest
   `wait_retry`'s `at` plus `retryMinutes`, **read from the last retry rather than extrapolated from
   the first**, because a lid-close sleep stretches every interval.
6. **Each hold.** Every `hold` with no later `hold_lifted` for the same `model` and `cause`. A
   `rate_limit` or `billing_error` hold lifts when its wait clears; a `fableReserve` hold lifts when
   the freshest reading's `seven_day.used_percentage` falls below the reserve, or when no reading
   stands because the freshest one's window has reset (D-073).
7. **Each caffeinate holder to re-arm.** For each in-flight lane, `caffeinate -i -w <pid>` against
   the pid in the **current row** — the log stores no pid, because a supervisor restart gives the
   session a new one. For each active wait, `caffeinate -i -t` for the remainder of
   `caffeinateMaxHours` measured from its `since`.
8. **The last tick.** `~/.baton/last-tick`, read as a file, not derived from the log. Its
   `age_seconds` is the marker's age as of `now`, which is what `status` prints; derivation 15's
   `gap_seconds` is measured as of the reading instant instead, so inside a tick the two differ by
   the length of the work that tick has done (D-174).
9. **The ladder's position.** For a `(project, milestone, attempt)`, the count of failure endings
   since the newest reset point, where a **failure ending** is a `consumed` with `reason:
   no-handover`, the second `crash_sighting` of a confirmed crash, or a `resume` with `outcome:
   refused` and `resume_kind` other than `ruling`; a person's failed ruling delivery is not a
   session failure. A **reset point** is a `consumed` with `written_by: session` or the attempt's own
   `dispatch`. One resume, then one redispatch, then escalate. `ladder_position` also counts
   ineffective failure endings across attempts since the newest session-written `consumed`;
   dispatches do not reset that count. At three, a failure in the current attempt takes the
   existing `ladder-end` escalation before another recovery; a fresh dispatch alone does not
   trigger it. Recovery requires an identifiable outgoing job, even if its row lacks a pid;
   redispatch stops and settles it first and refuses a failed/unsettled stop (D-110).
10. **The attempt number**: the count of `dispatch` events for the `(project, milestone)`. **The
    resume count for an attempt**: the count of its `resume` events with `outcome` `delivered` or
    `forked`.
11. **Whether a once-only key is spent.** A `notification` with that class and key exists at or
    after the attempt's newest reset point — **the same reset the ladder uses**, plus a `takeover`.
    An artifact the session wrote itself demonstrates it came back, so what it does next is new
    information; an `api-error` artifact is written by the hook and not by the session, so a
    fifteen-minute wait cycle never re-arms wait-ceiling keys. For `stall` and `long-running` only,
    a delivered or forked resume also re-arms the key; a refused resume does not. The long-running
    clock likewise measures from the latest dispatch, successful resume or takeover (D-125).
12. **The dispatch hold**: derivation 6. No dispatch on a model with an active `rate_limit` or
    `billing_error` hold; on every model once a second model is held. A `fableReserve` hold holds
    its own model and counts toward nothing: the reserve is about one model's share of a window,
    not about the account being unable to answer.
13. **`baton answer <milestone>`**: derivation 2, filtered by milestone across every project. Exactly
    one match acts; more than one refuses and prints `<project>/<milestone>`; none refuses with
    "nothing is waiting on `<milestone>`".
14. **`baton plan`'s provenance of allow rules**: every `widening` for the project, newest first,
    each naming the rule and the milestone that earned it.
15. **The gap**: the as-of minus `~/.baton/last-tick`, the as-of defaulting to `now`. Reported as a `notification` with class `gap`
    only when `lanes_open` (including lanes without a live row), parks or waits show work during it. Keyed on
    the marker value it was measured against, so one outage reports once. **The threshold is two
    intervals**, not one: the marker holds the `at` of the tick that completed and is written after
    the lock is released, so at the next tick it is already a full interval old plus that tick's own
    elapsed time, and one interval would report on every tick with an open lane — while the key,
    being the marker value, changes every tick and so would suppress nothing. **"During it" is not
    "now"**: a lane that ran through the outage and finished before the read still means Baton was
    not running while something needed it, so the window counts lanes open now plus anything that
    closed after the marker. Closing events are ordered against the marker by `iso_epoch`, so UTC
    offsets cannot reverse the comparison and an equal instant does not count as later (D-116).
    **The tick measures against its own start**, `tr_now`, when it reads the gap after its lanes;
    every other reader measures against `now`, as does the tick's own early reading on a run that
    could not list the rows, which returns before step 2 and so has spent nothing (D-174). Step 2
    starts a target project's standing check under the tick lock and collects it on a later tick
    (D-184); the lock is no longer held for the run. The marker is the *previous* tick's. The gap
    means "Baton was not running", not "the marker is old", and the tick's own start is where those
    are the same sentence. The closed-lane test stays on the marker, since a lane that closed while
    the tick worked is still one the gap would have covered.

**Recovery is stateless derivation**: each tick reads the current log, agents listing, inbox, plan
file and git check without retained process memory. Every derivation above is a pure function of
its inputs. A tick's writes become inputs to the next tick, so counters and once-only keys can
legitimately advance. The harness checks both runs' output and one final state snapshot after two
fresh-process runs, not an empty second-tick diff (D-126).

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
delivered or forked, and a refused one leaves the park standing (D-061). A sessionless
dispatch-failed park instead accepts a nonempty hand-back ruling without a resume; candidate
admission on the next tick still applies all ordinary gates (D-120).

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
| `BATON_DATE` | `date` | prints the scenario's `now` for both runs: the clock is frozen, so changes arise from scenario activity rather than elapsed real time |
| `BATON_CAFFEINATE` | `/usr/bin/caffeinate` | appends its argv to `calls.log` and exits |
| `BATON_HOME` | `~/.baton` | the scenario's own state directory |
| `BATON_DAEMON_LOG` | `~/.claude/daemon.log` | the service's own log, read only for `bg settled <id> (crashed): <detail>` when a backgrounded worker never gets a row (item 47); the claude shim writes the line when told to |
| `BATON_OSASCRIPT` | `/usr/bin/osascript` | the Mac message when the applet is missing or will not launch; records its argv in `calls.log`, so a scenario asserts on the line a person would have read and no notification is raised (D-043) |
| `BATON_TRANSCRIPTS` | `~/.claude/projects` | the tree derivation 3 globs for `*/<session>.jsonl`; a scenario's own `transcripts/` directory, so a transcript read is a file read and no fixture starts a session (D-032) |
| `BATON_OPEN` | `/usr/bin/open` | the notifier applet's launch; records `open -g <app>` in `calls.log` and plays the applet's posting half — each spooled message recorded as `  posted: <title> \| <body> \| <target>`, removed, and the newest target left in `notify/target` — so a scenario asserts on the link a click would open; `open.fails` makes the launch fail, and `open.running` makes it reach an applet already running, which posts nothing (D-092, D-094) |
| `BATON_JOBS` | `~/.claude/jobs` | a background session's `<job>/state.json`, read for `bridgeSessionId` when its transcript holds no URL; a scenario's own `jobs/` directory (D-093) |

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
project/          optional: a fixture project (CLAUDE.md, docs/MILESTONES.md, docs/milestones/M*.md,
                  check.sh — the standing check Baton runs itself); tests/project/ otherwise
other/            optional: a second fixture project, committed at <tmp>/Other, its commit
                  written @OTHERCOMMIT@, for the rules asked across projects (D-076)
jobs/             optional: the tree BATON_JOBS points at, <job>/state.json per background session
transcripts/      optional: the tree BATON_TRANSCRIPTS points at, one folder per checkout holding
                  <session>.jsonl; an empty tree otherwise, which is a lane with no transcript
mtimes            optional: "<path under transcripts/ or home/> <seconds before now>" per line, for
                  a rule that stats a file rather than reading it — a transcript's age, or which
                  status file is the freshest; without it a transcript's age compared against the
                  scenario's frozen now is the time of the copy (D-046)
expected/         home/ (without lock/), out/<run>.{stdout,stderr,status} for both runs, calls.log
```

`tests/run.sh` copies the fixture project to `<tmp>/Fixture` and commits it once on `main` at a
fixed date and identity (so its hash is the same on every run), does the same for `other/` at
`<tmp>/Other`, copies `home/`, points the seams at
the shims, runs `cmd` twice, then diffs the state left behind — `home/` without the lock, both
runs' streams and exit codes, and the shims' `calls.log` — against `expected/` with the temporary
root written as `@TMP@`. A scenario that builds commits of its own — `tests/completion-fixture.sh`
does, because a completion chain needs a baseline, a candidate and a merge that the one fixture
commit cannot supply — writes `<NAME> <value>` lines to `<tmp>/subs` and replaces `@NAME@` in its own
`home/` with the value; those values are turned back into `@NAME@` in the result before the diff, so
an expectation holds `@BASELINE@`, `@CANDIDATE@` and `@MERGE@` rather than hashes that would move
whenever `tests/project/` changed. A `dispatch` event's `prompt_sha256` is recomputed from its sidecar under
the one rule and replaced by `sha256-matches-sidecar` or a mismatch note before the diff, because
the sidecar carries the temporary path. `BATON_TESTS_FREEZE=<name>` rewrites that scenario's
`expected/` from the run, for a fixture whose output has been read and judged right, and `all` every
one; `BATON_TESTS_ONLY=<glob>` runs the matching scenarios alone. Hook scenarios
pipe `tests/payloads/*.json` (copied from the prototype's `obs/`, two constructed) into a hook
through `cmd`. launchd is never in the tests.

---

## 8. Data flow

Session → artifact (inbox) → tick consumes → archive + `consumed` event (or, for a repeat, archive +
`repeated` and nothing further) → eligibility (plan) ∩ dispositions (newest consumed handover) → holds, cap → dispatch (worktree, settings, sidecar,
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
| M01 | `bin/baton` (verb dispatch; reads the five seams once and exports them; resolves `BATON_LIB` once, to the library set named on its `baton_bundle=` line when the install wrote one — D-131). `lib/lock.sh`: `lock_take`, `lock_release`. `lib/log.sh`: `baton_now`; `log_event <kind> <project> <milestone> <session> <attempt> [<fields json>]` (the one append; an empty envelope argument is absent from the line; refuses without the lock or over 4 KB); `attempt_of <project> <milestone>` (the count of `dispatch` events; the next attempt is that plus one); `prompt_normalise` (stdin to stdout, strips exactly one trailing newline); `prompt_sha256 <file>`; `sidecar_write <session> <text>` (prints `<path> <sha256>`); `widenings_json <project>`. `lib/plan.sh`: `plan_tables <file>` (one JSON document `{milestones: [{row, id, depends[], model, effort, remote, status}], gates: [{row, gate, holds[], cleared}]}`; on the first bad cell prints `{error: "plan-unparseable", table, row, cell, detail}` with status 1); `plan_rows`, `plan_gates`, `plan_row <id>`, `plan_eligible` (ids, one per line) and `plan_render <project> <inflight json>` on that document from stdin; `parse_id`, `parse_depends`, `parse_model <cell> <models json>`, `parse_effort`, `parse_remote`, `parse_status`, `parse_cleared`; `verb_plan`. `lib/dispatch.sh`: `rows_json`; `inflight_json <project>` (a placeholder, removed by M02); `row_for_id <id>`; `worktree_ensure <path> <milestone>` (prints `{worktree, branch, reused, commit}`); `shell_word <string>` (one single-quoted shell word — D-133); `settings_compose <project> <milestone>` (prints the path; every token of the three composed commands is one shell word — D-133); `prompt_from_brief <path> <brief> <heading>`; `slot_line <prompt> <paragraph>`; `claude_bg <worktree> <name> <model> <effort> <settings> <prompt>` (sets `bg_status`, `bg_stdout`, `bg_stderr`, `bg_id`); `dispatch_failed_classify <text>`; `caffeinate_hold <pid>`; `dispatch_failed <project> <milestone> <stage> <detail>`; `dispatch_one <project> <milestone> <plan json>`; `verb_dispatch`. `lib/templates.sh`: `slot_line_text <worktree> <branch> <canonical> <also> <attempt> <commit>`. The convention every fallible function follows: its result on stdout on success, its failure detail on stdout with a non-zero status. The hand-run verb reads the brief at `docs/milestones/<milestone>.md` under `## Copy-ready session prompt`. `hooks/stop-gate`, `hooks/stop-failure`, `hooks/statusline`; `install.sh` (`publish <source> <destination> [<sed script>]`, the compare-then-rename each installed file goes through, and the staged library set published as `bin/lib/<digest>` — D-131); `tests/run.sh`, `tests/shim/{claude,date,caffeinate}`, `tests/project/`, `tests/payloads/`, 27 scenarios; the five seams; `~/.baton/` layout, `config.json`, `projects/Baton/`; verbs `plan`, `dispatch`; events `dispatch`, `dispatch_failed` | – |
| M02 | `lib/inbox.sh`: `project_key_of <path>`; `merged_as_verify <path> <sha>`; `brief_pointer_check <path> <brief> <heading>`; `written_by_of <reason>`; `stop_route <reason>` (the REQ-STOP-12 table as data; M04 attaches the actions); `artifact_ids <file>`; `artifact_check <file>` (prints `{artifact, project, written_by, dropped[]}`, or `{rule, detail}` with status 1); `escalate_rejection <project> <milestone> <session> <attempt> <rule> <path>`; `attempt_for_session <project> <milestone> <session>`; `archive_move <file> <consumed-at>`; `reject_move <file>`; `reject <file> <rule> <detail>`; `inbox_consume <rows json>` (every branch that leaves work undone is counted into its status — D-133); `consume_one <file> <check doc> <rows json>`. `lib/derive.sh`: `config_num <key> <default>`; `iso_epoch <timestamp>`; `now_epoch`; `session_id_ok <session>`; `transcript_of <session>`; `orphaned_of <session>`; `typed_hashes <transcript>`; `lanes_open <project> <log json>`; `current_session <project> <milestone> <attempt>`; `lane_of_session <session>`; and the fifteen — `derive_in_flight <project> <rows>` (`{in_flight[], no_row[]}`), `derive_parked <project>`, `derive_taken_over <project> <rows>` (`{taken_over[], orphaned[], unreadable[]}`), `derive_consumed <project>` (`{consumed[], waiting[], unrecorded[]}`), `derive_waits <project>`, `derive_holds`, `derive_caffeinate <project> <rows>` (`{wake[], timed[]}`), `derive_last_tick`, `derive_ladder <project> <milestone> <attempt>`, `derive_attempt <project> <milestone> [<attempt>]`, `derive_key_spent <project> <milestone> <attempt> <class> [<key>]`, `derive_dispatch_hold`, `derive_answer_candidates <milestone>`, `derive_widenings <project>`, `derive_gap <rows>`. Every one prints one keyed JSON object; an empty `<project>` means every project (D-031). `lib/status.sh`: `duration`, `nth`, `field`, `verb_for`, `one_line`, `silent_waits <project> <rows>`, `status_render <rows json>`, `verb_status`. `lib/templates.sh`: `session_name <project> <milestone>` (D-036). `tests/consume-once.sh`, `tests/lib-load.sh`, the `transcripts/` fixture and the `@COMMIT@` substitution in `tests/run.sh`; verb `status`; events `consumed`, `rejected`, `escalation` (class `other`, rejection only); the `written_by` field; the sixth seam `BATON_TRANSCRIPTS`. **Removes** M01's placeholder `inflight_json`: `verb_plan`, `dispatch_one` and `verb_dispatch` read `derive_in_flight`'s `in_flight` instead, which is what the placeholder stood in for | M01 |
| M03 | `lib/rows.sh`: `rows_read` (the rows once per tick, non-zero when the listing could not be read); `inbox_holds <session>`; `ended_on_disk <session> [delivered execution json]` (optional `{at, archives}` bound; archives names earlier consumed paths for timestamp ties, D-110); `stood_off <session> <list>`; `newest_event_at <project> <milestone> <attempt> <kinds regex>`; `transcript_mtime <session>` (the newest `stat -f %m` across the transcript and `<session>/subagents/agent-*.jsonl`); `takeover_check <project> <rows>` (prints `{stand_off[], lines[]}`); `crash_check <project> <rows> <stand-off> <this tick's clock>`; `stall_check <project> <rows> <stand-off>`; `long_running_check <project> <rows>`; `question_check <project> <rows> <stand-off>`; `gap_check <rows>`. `lib/notify.sh`: `notify_text`, `notify <title> <body>`, `notify_title <project> <milestone> <class>`, `fields_or_fail`, `class_or_fail <kind> <class>`, `escalation_write <project> <milestone> <session> <attempt> <class> <scope> <carries>`, `notification_write <project> <milestone> <session> <attempt> <class> <key> <fields>` — every escalation and notification is written through the last two, which raise the Mac message as they write the event, and the body is `one_line` of the event's own fields. `lib/tick.sh`: `lock_stale_report`, `lock_stale_break` (a rename, so exactly one process can claim a dead lock), `marker_write`, `self_check_failed_once` (the event plus the project-scope escalation of the log's own class), `park_resolve <project> <class regex> <what cleared it>` (REQ-ESC-05's edit route, the one only the tick can see), `self_check <project>` (prints the parsed plan document), `caffeinate_armed`, `caffeinate_timed`, `caffeinate_rearm`, `tick_dispatchable <project> <plan> <rows>` (steps 5 to 7, excluding an open lane, an open lane-scope park and a `Remote: yes` row), `dispatch_try` (step 8 with the two-failure bound), `tick_project` (steps 3 to 8 for one project), `tick_run` (returns 3 when the rows could not be read), `verb_tick` (no marker on a 3). `launchd/com.baton.tick.plist`, copied by `install.sh` to `~/Library/LaunchAgents/` and never loaded by it; the ad-hoc signing of the granted shell (D-038); verb `tick`; the seventh seam `BATON_OSASCRIPT` and `tests/shim/osascript`; the `mtimes` fixture file; twenty-six scenarios — `tick-{quiet,consumes-then-dispatches,long-running,stale-lock,stale-lock-live,no-rows,inbox-not-a-stall,transcript-unscannable,dispatch-fails-twice}`, `tick-self-check-{unparseable,unreadable,no-git,recovers}`, `crash-{first-sighting,two-ticks,confirmed-stands,rejected-ended,sleep-not-a-crash}`, `stall`, `stall-subagent-moving`, `question-row`, `takeover`, `takeover-handback-pending`, `gap-{reported,quiet,key-spent}`. Events `crash_sighting`, `takeover`, `self_check_failed`, `notification` (`stall`, `long-running`, `gap`, `takeover-silent`), `escalation` (`question`, `baton-unhealthy`, and `other` for a transcript that cannot be scanned). **Changes** `escalate_rejection` in `lib/inbox.sh` to go through `escalation_write`, so a rejection reaches the Mac; and `status` line 1 to carry the hardware condition and line 6 the live notifications. `worktree_pruned` stays reserved for M06 | M02 |
| M04 | `lib/stops.sh`: `route_ending <outcome> [<reason>] [<error>]` (the taxonomy of §5.2 as one lookup, printing `{class, action, retry, notify, hold}`); `ceiling_seconds <notify>`; `model_of_attempt <project> <milestone> <attempt>`; `job_of_session <rows> <session> [any-state]` (default live rows; recovery also accepts identifiable pid-less rows, D-110); `fork_session <short id>`; `artifact_detail <archived path>`; `resume_session <project> <milestone> <attempt> <session> <job> <kind> <class>` (stop, flagless resume, both streams read through `cli_plain`, the fork test before the success test, the `resume` and `copy_fork` events; a fork's compensating stop is settled, and one that no job identifies, that is refused or that leaves a live row parks the lane `other` and adds `unresolved_original` to the printed `{outcome, session, note}` — D-132); `ladder_position <project> <milestone> <attempt>` (derivation 9 plus the newest ending, whether a step was taken for it and ineffective_failures across attempts since session-written consumption, D-110); `redispatch <project> <milestone> <plan> <rows> <why>`; `ladder_step`; `declared_open <project>`; `consecutive_run <project> <milestone> <kind>`; `splits_carries`; `blocker_state <plan> <blocker> <in-flight>`; `declared_step`; `distant_wait_for_check`; `stops_standing_by`; `stops_run <project> <plan> <rows> <stand-off>` (step 4 for one project, in the order the facts arrive: the waits, the ladder, the declared stops, the distant wait). `lib/waits.sh`: `wait_run <project> <milestone> <attempt>` (the continuous wait's start and retry count since the attempt's reset, D-052); `wait_due <project>` (derivation 5 with each wait's routing attached); `wait_notify` (the ceilings, once per class per attempt through derivation 11); `wait_retry_run <project> <wait> <rows>`; `holds_apply` (derivation 6 written, once per tick across every project, with the second-model rule); `hold_bites <model>` (derivation 12, read before every dispatch). `lib/templates.sh`: `template_continue <class> <milestone> <attempt> <resume>` and `template_finish <milestone> <attempt> <resume> <session>`, §4.3 verbatim. `lib/dispatch.sh`: `cli_plain` (D-050), which `claude_bg` and `resume_session` read the CLI through. Events `resume`, `copy_fork`, `wait_retry`, `hold` (`rate_limit`, `billing_error`), `hold_lifted`, `notification` (`rate_limit`, `billing_error`, `transient`, `unrecoverable`, `blocked_by`, `distant_wait_for`), `escalation` (`model_not_found`, `unfinished-twice`, `blocked`, `ladder-end`). Twenty-five scenarios — `route-ending`, `wait-{rate-limit,ceiling-2h,transient-1h,unrecoverable-now,max-output-at-once,clears-on-resume}`, `resume-refused`, `hold-second-model`, `no-handover-ladder`, `crash-{resume,redispatch-no-transcript}`, `copy-fork`, `copy-fork-generic-note`, `invalid-request-{redispatch,twice}`, `model-not-found`, `unfinished-{once,twice,twice-long}`, `blocked-{silent,escalates,done-redispatch}`, `distant-wait-for`, `dispatch-coloured-id`; the shim's resume roles, its colour knob and the `backgrounded` line the real CLI prints on every resume. **Changes** `lib/rows.sh`'s `crash_check`, which no longer sights a lane dispatched or resumed within two intervals (D-054); `lib/tick.sh`, whose step 4 now has a body, whose step 7 applies the dispatch hold, and which runs `holds_apply` once before the project loop; and `lib/notify.sh`, whose two writers no longer raise the Mac message when `log_event` refused the line, so a message implies a record (D-057) | M03 |
| M05 | `lib/escalate.sh`: `class_unparks_by_edit <class>`; `class_reread_policy <class>` and `policy_fields <policy>` (which readings a decision about that park would change, and the only fields compared — D-134); `reread_project <plan> <milestone> <blocker> <what>` (one projection: `model`, `status`, `blocker`, or `work_plan`, the lane own execution fields and dependencies plus the ids and dependency edges downstream of it, row position and `Status` excluded); `reread_hashes <project> <milestone> <class> <carries> [<plan>]` (prints `{version: 2, policy, hashes}`, each hash absent when it cannot be read and `{}` when none can); `reread_changed <was> <now> <fields>`; `reread_baseline_of <project> <milestone> <escalation at>` (prints `{found, hashes}`); `person_acted <project> <milestone> <class>` (prints `edit`, `ruling` or nothing, D-061); `escalate <project> <milestone> <session> <attempt> <class> <scope> <carries>` (the one writer of `escalation`, replacing `escalation_write`: class and scope checked, `reread` attached, event before message); `resolve <project> <milestone> <session> <attempt> <escalation at> <how>`; `ruling_target <project> <session> <attempt>`; `escalation_content <class> <carries>`; `escalation_verb <class> <milestone> <carries> [<ruling target>]`; `message_render <project> <milestone> <class> <carries> [<session>] [<attempt>]` (prints `{address, content, verb, body}`, the verb never cut); `asking_carries <artifact>`; `ending_escalate <project> <milestone> <session> <attempt> <artifact> <class> <archive>` (with its fallback carries); `edit_reread_check <project> <plan>` (compares the policy designated fields only, by presence and value: newly readable or changed inputs release edit parks; unreadable-now inputs do not; done-only classes still require the Status transition; a receipt with no `version` keeps its brief digest and `status_at_park` and has the rest taken once into a `reread_baseline` event, the park standing that tick — D-134); `question_resolve_check <project> <rows>` (answered in place by the row or by the session's own later artifact, and `prompt-lost`); `fork_resolve_check <project> <rows>` (a fork park whose `carries.original` no longer has a row with a pid is resolved `edit`, filtered by that field so a rejection park of the same class is never touched — D-135); `escalation_verb` answers a park carrying `original` with the one act that ends it, stopping that session by hand, before either the ruling or the edit route (D-135). `lib/answer.sh`: `answer_resolve <milestone> [<project>]`; `answer_candidates_print`; `answer_options` (from the archive); `answer_deliver <park> <ruling \| n> <rows>`; `answer_handback <milestone> [<project>] <rows>`; `verb_answer`; `allow_lane <milestone> [<project>]` (each candidate carries `closed`, whether a consumed `complete` has ended that attempt — D-132); `allow_write <project> <milestone> <rule>`; `verb_allow` (refuses `--resume` on a closed candidate before anything is written, because the takeover guard's domain cannot see one — D-132). `lib/stops.sh`: `stop_settle <session>`; `resume_count_next <project> <milestone> <attempt>` (prints `<attempt> <resume>`); `resume_session` gains the kind `ruling` and an eighth argument, its text. `lib/templates.sh`: `template_ruling <milestone> <attempt> <resume> <time> <question> <ruling>`, §4.3 verbatim. Verbs `answer`, `allow`. Events `escalation` (`asking`, `merge-failed`, `other` from a stopped artifact), `resolution` (`ruling`, `answered in place`, `edit` on a lane), `widening`, `notification` (`prompt-lost`). The shim's stop, linger, fail and fork roles. Twenty-eight scenarios — `asking-{parks,row-lingers,too-large}`, `answer-{one-match,two-matches,not-parked,option-number,resume-refused,hand-run-session}`, `edit-unparks`, `edit-unparks-no-session`, `ladder-end-edit`, `model-not-found-edit`, `unfinished-twice-ruling`, `merge-failed-ruling`, `other-escalates`, `question-row-answered-in-place`, `question-then-artifact`, `prompt-lost`, `takeover-handback`, `two-projects-refusals`, `allow-{writes,refuses-ask,resume,resume-parked,files}`, `stop-settle-lingers`, `ending-escalate-fallback`. **Changes** every M02–M04 writer of an escalation to call `escalate`, and `park_resolve` to write through `resolve`; `consume_one` to park `asking`, `merge-failed` and `other`; `question_check` to pass by a lane already parked or dispatched or resumed within two intervals; `ladder_step`, `declared_step` and `stops_run` to ask `person_acted` before parking again, and the `model_not_found` detail to name the attempt's model; `verb_for` to print `escalation_verb`; `class_or_fail` to take its caller's name; `tick_project` to run `edit_reread_check`, `question_resolve_check` and `fork_resolve_check` first | M04 |
| M06 | `lib/candidates.sh`: `project_held <project>` (prints the class of an open project-scope park); `dispositions_in_force <project>` (prints `{has_handover, in_force[]}`, each entry `{milestone, disposition, wait_for, held_by, archive, rank, index}`); `intersect_verdicts <project> <plan> <in force> <has handover> <open lanes> <parks>` (step 6 as data over the log on stdin: `{candidates, overrides, conditions, clears}`); `plan_override_spent <project> <milestone> <direction> <gate>`; `plan_override_once <project> <milestone> <override>`; `dispositions_intersect <project> <plan> <rows>` (acts on the verdicts, prints `{candidates, lines}`); `cap_order <candidates> <in flight per project>`. `lib/tick.sh`: `dispatch_run <candidates> <plans>` (steps 7 and 8 once across every project; it reads the listing itself, after the reconciliation that can replace a lane's session, and returns without one when there is no candidate — D-130); `tick_project` now steps 3 and 4 and the prune; `tick_run` collects every project's candidates before dispatching, and skips steps 5 to 7 for a held project. **Removes** `tick_dispatchable`. `lib/waits.sh`: `is_fable <model>`; `reserve_reading` (prints `{reading, status_file}` or `{}`); `reserve_check` (the `fableReserve` hold and its lift, once per tick); `hold_bites` holds every Fable spelling while that hold stands. `lib/dispatch.sh`: `worktree_prune <project> <plan> <rows>`. `lib/declared.sh` (D-070): M04's `declared_open`, `consecutive_run`, `splits_carries`, `blocker_state`, `declared_step`, `distant_wait_for_check`, moved unchanged from `lib/stops.sh`; `main_broken_cascade <project> <ruling> <rows> <park at> <milestone>`. `lib/escalate.sh`: `class_ends_on_done <class>`; `escalate` attaches `reread` with `status_at_park` to `merge-failed` and `main-broken`; `ending_escalate` parks `main-broken` at project scope; `edit_reread_check` gains a third argument, the rows, resolves those two only on a `done` written after the park, and names a still-live session's job; `escalation_verb` gives `main-broken` its ruling. `lib/answer.sh`: `answer_deliver` gains a fourth argument, the cascade. `lib/stops.sh`: `redispatch` waits while the project is held; `stops_standing_by` stands by a milestone any park names, project scope included. `lib/inbox.sh`: `consume_one` parks `main-broken`. `tests/run.sh`: `other/`, `@OTHERCOMMIT@`, `home/` paths in `mtimes`, `BATON_TESTS_ONLY` (D-076). `tests/shim/claude`: `resume.note.<session>` and `resume.status.<session>`. Events `plan_override`, `worktree_pruned`, `hold` and `hold_lifted` (`fableReserve`), `escalation` (`disagreement`, `omitted`, `main-broken`), `resolution` (`edit` on an `omitted` or `disagreement` whose condition cleared, and on a `merge-failed` or `main-broken` closed by hand). Thirty-eight scenarios — `cap-{two-of-three,order-fewest-in-flight,order-project-key}`, `wait-{honoured,clears-on-done}`, `held-plan-{wins,dispatch-fails}`, `run-plan-holds`, `disagreement`, `disagreement-clears`, `omitted`, `omitted-{dependency-mid-run,dependency-waiting,park-kept-while-dependency-runs,resolves-on-handover,edit-dispatches}`, `fable-reserve-{holds,lifts,window-reset,model-renamed,no-reading}`, `main-broken-{parks,cascade,cascade-refused,done-edit}`, `merge-failed-done-early-edit`, `prune-{verified,directory-gone}`, `prune-refused-{merge-failed,live-row,named-row,unreadable-row,open-lane,not-done,no-handover,newer-ending,off-main,dirty}` | M05 |
| M07 | `lib/dispatch.sh`: `settings_compose <project> <milestone>` now writes `remoteControlAtStartup: true` for every dispatch (D-081); `dispatch_one` dispatches a `Remote: yes` milestone with the ordinary command and records the plan's `remote` on the `dispatch` event (D-080); `worktree_prune` removed (D-078). `lib/candidates.sh`: `dispositions_intersect` no longer skips a remote candidate. `lib/rows.sh`: `stall_check` judges a remote lane whose row reads `waiting`. `lib/tick.sh`: `tick_project` is steps 3 and 4 without the prune. `hooks/stop-gate`, `hooks/stop-failure`: exit 0 writing nothing, as their first rule, when an archived file has this session, this milestone and `outcome: complete`, matched by content (D-078). `lib/rows.sh`: a remote lane's stall key is spent only while its transcript has not moved since the notification. `install.sh`: copies the launchd agent only when none is installed (D-079). Close-out: `sh install.sh` (D-079). Scenarios `remote-dispatch-tick`, `remote-row-not-a-park`, `remote-stall-rearms`, `stop-gate-closed-lane`, `stop-failure-closed-lane`, `stop-gate-closed-lane-misnamed`, `stop-failure-closed-lane-misnamed`, `stop-gate-archived-stopped`, `stop-failure-archived-stopped`, `install-plist-differs`; `dispatch-remote-yes` refrozen on the one-command path; the twelve `prune-*` removed. Live items 39 (superseded) and 40, the phone, and the acceptance write-up in the brief | M06 |
| M07-b | `lib/lifecycle.sh` (D-087): `lifecycle_finished <log json> <rows json>` (every session whose `complete` handover was consumed, one per milestone, none for a milestone dispatched since, following a forked wake to its `copy`, each with its live row's pid, job and status); `offline_check <rows json>` (REQ-LIFE-01, across every project, sessions Baton dispatched only, an event only for a stop the CLI took); `offline_after <log json> <session> <epoch>`; `wake_resume <session> <text>`; `wake_session_prompt`; `wake_session_ensure <rows json>` (REQ-LIFE-04); `verb_wake [<milestone>] [<text> \| -]` (REQ-LIFE-03). `lib/dispatch.sh`: `resume_classify <stdout> <stderr> <status>` (the one classifier of every flagless resume, printing `{outcome, note, copy}` with the note cut to 500 bytes; `resume_session` and `wake_resume` both call it); `claude_env_clean`, which `bin/baton` runs before every verb so nothing Baton starts inherits the `CLAUDE*` variables of a session it runs inside. `bin/baton`: verb `wake`. `lib/tick.sh`: `tick_run` calls `offline_check` and `wake_session_ensure` once, between steps 6 and 7. `lib/derive.sh`: `typed_hashes` reads every message record — a `user` record whose `promptSource` is `typed` or `queued` or whose `origin` is an object with `kind` `human`, and a `queued_command` attachment likewise (D-085). `lib/status.sh`: a tenth section, offline finished sessions and a refused wake session. `install.sh`: writes `settings/wake.json` when it has changed, with four rules refusing the `tick`, `answer`, `dispatch` and `allow` verbs. Config numbers `keepFinished`, `idleStopMinutes`, `wakeModel`, defaulted in code. `tests/lib-load.sh` sources `lib/lifecycle.sh`; `tests/shim/claude` gains `stop.status` and `env.claude`. Events `offline`, `wake`. Scenarios `takeover-{queued-command,queued-between-turns,peer-not-a-person,slash-command,origin-not-an-object}`, `offline-{keeps-recent,refusals,stop-not-landed,stop-fails,refuses-hand-started,refuses-redispatched}`, `wake-verb`, `wake-verb-{stdin,forked,two-projects}`, `wake-session-{resumed,forked,start-refused,settings-missing,unsafe-settings,model-alias}`, `wake-inside-a-session`, `resume-classify`; `install` asserts `wake.json`. The wake-mechanism measurements and the grouping finding (D-086) are in the brief | M07 |
| M07-c | `notify/Baton.applescript`, compiled by `install.sh` into `~/.baton/bin/Baton.app` (`com.baton.notify`, `LSUIElement`, Claude's icon when `BATON_CLAUDE_ICON` — default `/Applications/Claude.app/Contents/Resources/electron.icns` — exists, signed ad hoc, rebuilt only when the source, the icon or `install.sh`'s checksum in `Resources/built-by` differs, swapped in by rename) (D-092, D-094): a launch or a reopen posts every file in `~/.baton/notify/spool/`, a message without a title removed unposted and a failure ending the pass without a dialog, and writes the newest one's target to `~/.baton/notify/target` aside and renamed; a launch with nothing spooled is a click, which clears Baton's delivered notifications and opens the target, or `claude://code/needs-input` when it is empty. `lib/notify.sh`: `notify <title> <body> [<session>]` (spools under a name never reused, counter padded, and runs `$BATON_OPEN -g Baton.app` when the applet is installed, `osascript` otherwise or when the launch fails); `notify_line <string>` (the capped line, unescaped); `notify_flush` (at the start of `tick_run`, launches the applet once when the spool still holds a message); `session_url <session>` (the newest claude.ai session URL among the transcript's `remote_session_change` attachments, else the job state's `bridgeSessionId` as one, else empty; D-093). `escalate` and `notification_write` pass the event's session. The `question` verb reads `answer it in place in Claude.app, or baton answer <milestone> "<ruling>"`. Seams `BATON_OPEN` and `BATON_JOBS`; `tests/shim/open` (knobs `open.fails`, `open.running`); scenarios `notify-session-url`, `notify-job-state`, `notify-no-session-url`, `notify-applet-missing`, `notify-open-fails`, `notify-spool-names`, `notify-spool-stranded`, `notify-stall-session`, `notify-two-in-a-tick`, `install-no-claude-icon`, `install-rebuild`, and the `install` scenario's applet checks | `notify`, `notification_write`, `escalate`, `message_render`, `escalation_verb`, `transcript_of`, `session_id_ok`, `now_epoch`; M07-b |
| M07-d | `lib/inbox.sh`: `repeat_of <file>` (prints the `consumed` event of the handover the file repeats — the same JSON value, `written_at` included, as an archived copy of it for the same milestone and session, its first file or an earlier repeat's — with status 0; nothing with status 1; the log's read failure with status 2); `repeat_one <file> <consumed event>` (the move, the `repeated` event under the first handover's envelope, one line); `inbox_consume` runs the repeat test before `artifact_check` and leaves a file whose test could not read the log for the next tick (D-095, D-097). **Changes** `archive_move` and `reject_move` to print the reason and return 1 on a directory they cannot make, a destination that exists or a move that fails, and `consume_one`, `repeat_one` and `reject` to write nothing then; `consume_one` moves the file before stopping an asking session (D-097). `lib/derive.sh`: `derive_consumed` prints `{consumed[], repeated[], waiting[], unrecorded[]}`, each `repeated` entry `{at, project, milestone, session, attempt, outcome, archive, repeats, archive_present}`; its `unrecorded` join claims names from every project's `consumed` and `repeated` events and binds each name before comparing, where it had compared the list with itself and named nothing. `lib/candidates.sh`: `dispositions_in_force` and `cap_order` unchanged — the ranking is derivation 4's order of first consumption, which a repeat no longer enters (D-096). Event `repeated`. Scenarios `consume-repeat-{identical,reserialised,asking,older-word,two-handovers,new-written-at,derivation,first-archive-moved,archive-gone,log-unreadable}`, `consume-archive-move-fails`, `consume-archive-name-taken`; `derive-consumed` refrozen with the `repeated` list | `consume_one`, `archive_move`, `artifact_check`, `derive_consumed`, `log_event`, `baton_now`; M07-c |
| M08 | `projects/Reclaim/{project.json,permissions.json}`, the hand-written starting artifact, `baton plan Reclaim` green, item 38 against Reclaim's path | M07-d |
| M17 | `lib/preconditions.sh`: `dispatch_preconditions <project> <milestone>` (read-only; prints `{project, milestone, checkout, brief, worktree, branch, references_inspected, failures: [{check, stage, path, detail, repair}]}` with status 0 whatever it found, a failure's `path` being checkout-relative for stage `prompt` and absolute otherwise, and the detail with status 1 when the inspection could not be made at all); `permissions_inspect <project>` (the deny-rule reading `settings_compose` refuses without, inspected without composing); `prompt_references` (a kickoff prompt on stdin, `path <p>` or `ambiguous <t>` per line, deduplicated in first-seen order). Checks, in the order `failures` carries them: `checkout` (stage `worktree`); then `brief`, or `slot` and one `reference` or `reference-ambiguous` per path the prompt names, in the order it names them (stage `prompt`); then `not-a-worktree`, or `behind-brief` and `worktree-brief` (stage `worktree`); then `permissions` (stage `settings`). `behind-brief` is named for what it checks: the branch carries the brief's own latest commit, not every unrelated commit on main. `lib/plan.sh`: `plan_preconditions_report <project> <plan json>` appends the report to `verb_plan`, which now returns 1 when a precondition is unmet. `lib/dispatch.sh`: `worktree_of <path> <milestone>` (prints `{worktree, branch}`, the naming `worktree_ensure` creates from and the preconditions inspect); `dispatch_one` calls `dispatch_preconditions` before `worktree_ensure` and records the first defect through the existing `dispatch_failed` with the defect's existing stage. No new verb, event kind or stage; `dispatch_try`'s retry-then-escalate bound is unchanged (D-138, D-139, D-140). | M07-d |
| M17-b | `lib/render.sh`, the one layer between what Baton decides and what a person reads, sourced first by `bin/baton`, `tests/lib-load.sh` and `tests/consume-once.sh`. `render_init` (read once at the verb boundary, before any pipeline; sets `RENDER_TTY_OUT`, `RENDER_TTY_ERR`, `RENDER_STYLE_OUT`, `RENDER_STYLE_ERR`, `RENDER_COLUMNS`, `RENDER_UTF8`, `RENDER_ESC`, `RENDER_READY`); `render_ready` (lazy init, which inside a capture reads "not a terminal"); `render_styled <out\|err>`; `render_width_ok <text>` (a positive decimal of at most five digits, 1 to 10000, validated as text before any arithmetic); `render_token <out\|err> <kind> <text>` (kinds `lane`, `milestone`, `verb`, `state`, `path`, `timestamp`, `session`; returns the text, styled, for the caller to pass as an argument; empty in, empty out); `render_hint <out\|err> <text>`; `render_heading <out\|err> <format> [args…]`; `render_row <out\|err> <kind> <format> [args…]` with kind `action`, `record` or `plain`; `render_lines <json array> [<kind>]`; `render_failure <out\|err> <message> [<repair>]`; `render_plain <format> [args…]`, the explicit never-styled context for a Mac message and for human lines returned inside JSON; and internally `render_emit`, `render_record`, `render_field`, `render_count`, `render_paint`. Colours are ANSI 16 plus dim: cyan identity, amber for what needs an act, dim for a timestamp, path or session id. `COLUMNS` first, then `stty size < /dev/tty` and only with a TTY, else 80; the effective `LC_ALL`, `LC_CTYPE`, `LANG` decides UTF-8 or ASCII continuation. **Changes** the sixteen person-facing libraries and `bin/baton` to print through it, `plan_render` to take an optional third `<out\|err>` argument and stay plain without one, `answer_candidates_print` to take its stream, `usage` to take its stream, and `lib/log.sh` and `lib/lock.sh` to carry the note that anything sourcing them alone sources `lib/render.sh` first. Three scenarios: `render-matrix`, `verbs-tty`, `notify-tty-plain`, each driving a real pseudo-terminal through the base system's `script` (D-141, D-142, D-143). | M17 |
| M09 | `lib/dispatch.sh`: `worktree_entries <path>` (this repository's registered worktrees, one `<path>\t<branch ref>` line each, from `git worktree list --porcelain`, empty and status 0 for a path that is not a repository); `worktree_registered <path> <branch>`; `worktree_managed <path> <milestone>` (`$BATON_HOME/worktrees/<project key>/<milestone>`); `worktree_legacy_id <checkout> <path>` (the milestone a `<dirname>/<basename>-<id>` sibling names, or empty); `worktree_migrate <project> <rows json>` (the per-project move pass, one guard, silent refusal, one `worktree_moved` event and one line per move). **Changes** `worktree_of` to resolve the path from git's registration and fall back to the managed root, so a moved worktree is found where it now is rather than where its name would put it; and `worktree_ensure` to `mkdir -p` the managed parent, and to refuse a reuse whose `--git-common-dir` is not the checkout's or whose `symbolic-ref HEAD` is not the milestone's branch, each with the repair command. `lib/tick.sh`: the migration pass between steps 6 and 7, per project, before `offline_check`. `tests/run.sh`: `home/worktrees` is dropped from the snapshot as `home/lock` is, because a dispatch now creates a whole worktree inside the scenario's home. Six scenarios: `worktree-managed-new`, `worktree-legacy-reuse`, `worktree-wrong-repository`, `worktree-wrong-branch`, `worktree-migrate`, `worktree-migrate-live-row`. Event `worktree_moved`; REQ-DISPATCH-12; the managed root under `~/.baton/` (D-153). | M17-b |
| M10 | `lib/completion.sh`, what a completion claim has to prove and the evidence Baton produces itself: `completion_baseline <project> <milestone> <attempt>` (prints `{baseline, branch, worktree}`; the baseline is the earliest recorded for the milestone on that attempt's branch, at or before it, so a redispatch is not asked to redo work already on the branch — D-152); `completion_scope_patterns <repo> <milestone>` (the declared scope, one pattern per line, from the brief's `## 5.` on `main` — backticked spans that name a path, `{a,b}` expanded, `$VARIABLE` and prose dropped; status 1 when there is no such section); `completion_in_scope <patterns> <path>` (equality, directory prefix, or the pattern as a glob); `completion_chain <repo> <baseline> <branch> <merged_as>` (prints `{baseline, candidate, integration, branch, changed_paths}`; resolves `T` once and requires `B` ancestor-of `T`, `T` ancestor-of `M`; it takes the baseline already resolved and derives none, because after the merge the branch's merge-base with `main` is the branch tip); `completion_scope_check <repo> <milestone> <changed paths json>` (at least one path inside the scope; the refusal names the patterns); `completion_check_dir <project> <milestone> <attempt>`; `completion_check_command <project>` (prints `{command, deadline}` from `project.json`'s `.check`); `completion_check_run <repo> <project> <milestone> <attempt> <revision>` (detached checkout under `$BATON_HOME`, the tree asked what it stands at and whether it is clean, the command started detached under a done-marker deadline whose marker is renamed into place; prints `{revision, command, outcome, exit, output}` with `outcome: pending` and status 0 while the check runs, collected by a later tick; the tree is removed when the run ends — no duration, because it is the one number the machine decides rather than the repository and a frozen expectation holding it would fail on a loaded Mac); `inbox_consume` leaves a pending complete artifact in the inbox and still returns 0 (D-184); `completion_summary <full document> <evidence path>` (the document as the event carries it, every unbounded field cut in bytes); `completion_park_carries <completion json> <archive>`; `completion_park_owed <project>` (the completions whose failing check earned a `main-broken` park that was never written); `completion_evidence_write <project> <milestone> <attempt> <document>` (writes `result.json` by rename and prints its path, for a proved completion and an unproved one alike, so a receipt reconciled later says what this one says); `completion_verify <repo> <project> <milestone> <session> <merged_as>` (the whole of it, writing `checks/<project>/<milestone>-<attempt>/result.json` before the artifact moves; prints the document, or `{rule, detail}` with status 1 for a rejection); `completion_reserved_check <artifact>`. `lib/inbox.sh`: `artifact_check` gains the `reserved-field` rule and the `completion` key; `consume_settle <archive> <artifact> <project> <written_by> <rows> <completion> [<from>]`, everything a consumption decides once the file has moved, split out of `consume_one` so the reconciliation can do exactly it; `inbox_reconcile <rows>`, the inbox pass's first act, which runs the repeat test and then either writes the `repeated` event an interrupted repeat never wrote or the `consumed` event an interrupted consumption never wrote, applying in the second case the ending it owed (D-152); `reconciled_completion <project> <artifact>`, which reads that evidence file back rather than deriving it again; `inbox_consume` calls the reconciliation before its loop. `lib/dispatch.sh`: the `dispatch` event's `worktree_commit` becomes `baseline` and is written on every dispatch. `install.sh` adds `.check` to a registration that lacks one, additively. `~/.baton/checks/<project>/<milestone>-<attempt>/{tree,output.txt,result.json}`; `CONTRACT.md` clauses 1 and 4 and Baton's side; `REQ-ARTIFACT-10`, `REQ-ARTIFACT-11`, amended `REQ-ARTIFACT-06`, `REQ-LOG-07` and `REQ-DISPATCH-09`. Fixtures `completion-*`. **No new event kind and no new escalation class:** the evidence rides on `consumed` and a check that did not pass is the existing `main-broken` park, found by Baton's own run (D-145 to D-151) | M17-b |
| M10-b | The tick's own clock while it is working. `derive_gap <rows> [<as-of>]` and `gap_check <rows json> [<as-of>]` take an optional as-of that defaults to `now`, and `tick_run` passes `tr_now`, the clock it captured at its top, to step 7's reading; the early reading on the path where the rows could not be read stays on the default, because nothing long has run before it. The closed-lane test stays on the marker. `lock_stale_report` asks the recorded pid `kill -0` and prints `lock held` with the age and no removal advice when it answers, keeping `stale lock` for a holder that cannot be found. `REQ-ESC-10` and `REQ-TICK-03` amended; derivation 15 amended; scenarios `gap-long-check` (a completion whose standing check carries the clock past two intervals, reporting no gap and raising no Mac message), `gap-reported-long-check` (a real outage read from inside such a tick, reported at its own length and not the check’s — D-175), the as-of boundaries in `derive-gap`, and the live-holder arms of `tick-stale-lock-live` and `lock-incomplete-metadata`. **No new seam, event kind or escalation class** (D-174, D-175) | M10 |
| M11 | `lib/permissions.sh`, the two deny classes of REQ-PERM-04 once for every caller: `permissions_deny_rules` (the rules for this home, as a JSON array). It is a file of its own because `install.sh` sources it, so the dependency reads installer → rail and verb → rail rather than installer → onboarding verb. `lib/onboard.sh`, the verb that makes an unfamiliar Git repository a registered target project: `onboard_repo <path>` (`{checkout, key}` from git's first worktree, or the detail with status 1); `onboard_toolchain <checkout>` (`{toolchain, check: {command, deadline_seconds}, allow}` from the files present, a project-specific runner naming the check over a language's canonical command, the allow list in `install.sh`'s own order); `onboard_plan_find <checkout> [<registered plan>]` (the repository-relative path of a file holding a milestone table: the registered one first, then the conventional names, then a pruned search under `docs/` and then the rest to depth three, a header with both cells before one with only `ID`); `onboard_status_native <token>`; `onboard_status_propose <token>` (`{status, why}`, retirement borrowing `held`, status 1 for a word it will not guess at); `onboard_adaptation <file>` (`{defaults, status_map, gates, unmapped}`); `onboard_cells <file> <column> [<companion>] [<locator>]` (that column's body cells, or the header joined on a tab for the column name `--header`, locating the table as `plan_extract` does); `onboard_header <file> [<companion>]`; `onboard_has_table <file> [<companion>]`; `onboard_has_column <header> <name>`; `onboard_cli_shape` (`{version, ok, detail}` — M4's check on what the judgment role consumes); `onboard_evidence <checkout> <plan>`; `onboard_judge <checkout> <plan> <toolchain>` (the judgment request: `claude -p` in the foreground under the verb's lock, with the project's deny rules in a settings file of its own, the target as its working directory and `/dev/null` as its stdin, bounded by `ONBOARD_JUDGE_DEADLINE`, printing `{goal, done, constraints, non_goals}` or the detail with status 1; §4.5); `onboard_classify <checkout> <plan>` (`{plan_format, adaptation, tables}`, or `plan_format: "unmapped"` with the words it will not guess at); `onboard_start <key> <plan> <tables>` (the starting handover's `eligible[]`, with the contract's brief path); `onboard_confirm <lines>`; `onboard_intent_lines`; `onboard_permissions_write <key> <allow>` (the derived rules plus the ones already there, so `baton allow`'s survive); `onboard_registration_write`; `onboard_commit <key> <checkout> <plan> <toolchain> <intent> <classification> <cli> <seed>` (the rail, then the registration, then the event, in that order, once for every path); `onboard_report <key> <doc> [<heading>]` (ending in `plan_preconditions_report`, so contract material Baton cannot author is named with its repair); `verb_onboard <path>`. `lib/plan.sh`: `plan_adaptation <project>` (the registered adaptation, `{}` for a project without one); `plan_default <defaults> <column> <cell>`; `plan_tables` gains `[<project>] [<adaptation json>]` and `plan_extract` an optional-columns argument; both tables are now located by a header carrying their locating cell **and** their companion column (`has_cell`, `locates`), which is also what stops a plan document's other tables being chosen; `parse_status` gains the status map and fails a mapped value of `null`. `lib/candidates.sh`: `dispositions_in_force` reads the registration's `start.eligible` after every archived handover, ranked at the list's length, marked `source: "start"` so a park names it as the starting handover. `lib/tick.sh`: `self_check` passes the project key to `plan_tables`. New event kind `onboarded`; `project.json` gains the confirmed intent record, `plan_format`, `onboarded_at`, `cli`, `adaptation`, `start` and `plan_owed` (§3); `checks/judge/` is new. `docs/SPEC.md` REQ-ONBOARD-01 to 10, REQ-PLAN-09, REQ-PLAN-10, REQ-VERB-10. No new escalation class. | M09, M10 |
| M12 | `lib/planning.sh`, the generation path for a project that owes a plan. Constants: `PLANNING_ID` (`M00-plan`, the reserved lane id — one `parse_id` accepts, because `artifact_ids` recovers a handover's identity from its filename through it), `PLANNING_PLAN` (`docs/MILESTONES.md`) and `PLANNING_BRIEFS` (`docs/milestones`), which together are the role's declared scope. `planning_owed <key>` (the registration's `plan_owed`, or status 1); `planning_attempts <key>` and `planning_attempts_max`; `planning_scope_patterns` (the two paths, in `completion_scope_patterns`' one-per-line shape); `planning_model` and `planning_effort` (from `config.json`, the model resolved through `parse_model`); `planning_prompt <key> <checkout> <registration json> <defects json> <attempt>` (the whole text the session receives, with the slot paragraph at column 0 once); `planning_preconditions <key>` (the checkout and the rail, in `dispatch_preconditions`' `{failures: [...]}` shape); `planning_validate <key> <checkout>` (`{plan, plan_format, tables, defects: [{what, repair}]}`, every defect in one pass); `planning_brief_defects <checkout> <id> <successors>` (the four questions only a generated brief is asked, as `<what>\t<repair>` lines); `planning_adopt <key>` (`{adopted, lines}`, adopting through `onboard_commit` with the seed); `planning_record` and `planning_recorded_since <key> <outcome>` (the `plan_generation` event and its once-per-attempt key); `planning_pass <key> <rows json>` (`{candidates, lines}`, step 1's companion). `lib/dispatch.sh`: `dispatch_one` takes the planning lane through the same worktree, settings, launch, cleanup and event, branching only on model/effort, preconditions and prompt; the `dispatch` event gains `role`. `lib/completion.sh`: `completion_scope_patterns` answers `planning_scope_patterns` for that lane, and the standing check's deadline sweeps the half-written `output.txt.exit.tmp` its kill interrupted (D-172). `lib/tick.sh`: `tick_run` calls `planning_pass` before each project's self-check and collects its candidates. `planning_preconditions` filters `dispatch_preconditions`' own result to the `checkout` and `permissions` checks rather than writing a second copy of those two rules (D-170), and `planning_pass` withholds its candidate while a lane park stands on the lane and releases a `dispatch-failed` one when the preconditions hold again (D-169). `config.json`: `planningAttempts`, `planningModel`, `planningEffort`. Event `plan_generation`. The adopted-plan boundary for M15-c is `planning_adopt`, marked in the source at the line where the guard goes. Scenarios `plan-generate-*` and `planning-completion*`; `tests/completion-fixture.sh` gains the `planning` and `planning-out-of-scope` shapes and a per-shape branch | REQ-GENERATE-01 to 10 |
| M13 | `lib/dispatch.sh`: `brief_size <checkout> <milestone>` (the Size the brief declares in its `## 1.` section on `main`, lowercased and cut at the first comma, semicolon or full stop, empty when it declares none or when the brief cannot be read — the prompt's own copy of the Size is out of range by construction) and `size_effort <size>` (`small` → `medium`, `medium` or `large` → `high`, empty for anything else; the one place the mapping is written, for M14 to consume). **Changes** `dispatch_one` to fall back from a blank `Effort` cell to the Size, inside the branch that already decides the planning lane's model and effort from `config.json`, so the third source of an effort sits where the second one does; and its `do_also` list to name a peer's whole worktree path instead of the basename, which under M09's managed root is the milestone's own id (D-178). `lib/tick.sh`: `dispatch_run` re-reads `rows_read` before every dispatch after the first — tracked by `drn_started`, so a pass that has started nothing asks the CLI nothing extra — and refuses the rest of the pass when that listing cannot be read, which is what lets the second of a co-dispatched pair name the first (D-177, closing `docs/v2/01-findings.md` finding 24). No new event, no new field, no new config key: the `dispatch` event's existing `effort` records whichever of the three sources won. Seven scenarios: `autonomous-pair-join`, `autonomous-join`, `autonomous-cap-one`, `autonomous-omitted-successor`, `autonomous-listing-refused`, `effort-size-mapping`, `effort-size-precedence`, the first five over a fixture project whose graph is an independent pair and a join rather than a lane. `tests/shim/claude` gains `agents.fail-at`, the one listing call of a scenario that fails, because `fail.pending` fails the next n reads from wherever a stop left it and so cannot reach a read mid-pass without failing the ones before it | REQ-DISPATCH-01, -02, -05, -13 |
