Title: Baton's plan and its M01 prompt
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: 01, 02, 03, 07, 09, 11

## Question

With every decision above closed, write Baton's founding document set the way Reclaim's
was written — an end-to-end specification first, then the plan that breaks it into
milestones — and only then the M01 kickoff prompt. The set, in the order it is written:

- `docs/SPEC.md`: the requirements, as `REQ-*` entries the way Reclaim's are, drawn from
  the closed tickets' resolutions — the six-clause project contract, the artifact and its
  outcomes, the tick's inputs and order, the two-bit API-error table and the ladder, the
  escalation policy, the plan-file format, the worktree and merge rules, the permission
  file — plus the setup facts a fresh Mac needs a person to do once (the Full Disk Access
  grant, the bypass disclaimer). It consolidates; it invents nothing, and every entry
  cites the ticket it came from.
- `docs/ARCHITECTURE.md`: the tick's eight steps, the files under `~/.baton/` and their
  shapes, the injected hooks, the verbs, the states a lane can be in, the dispatch log's
  events, and the interfaces per milestone (§10 the way Reclaim's has one).
- `docs/DECISIONS.md`: seeded from the resolutions, ADR 0001 first, each with its
  rationale and the ticket it came from; the next free number is where M01 starts.
- `docs/MILESTONES.md`: Baton's own plan file, in the format "Dispatching more than one
  at once" decided — the milestone table with Dependencies, Model, Effort and Status
  columns, and the gates table — so Baton is the second project to implement the contract.
  The build bootstraps: M01 is built by hand and produces the smallest thing that can
  dispatch (`baton plan`, `baton dispatch <milestone>` — worktree, settings file, slot
  line, one `claude --bg`; no tick, no waits, no escalations); from M02 each milestone is
  dispatched by the Baton that exists so far, by a hand-run `baton dispatch`, and the plan
  is ordered so that what a milestone needs in order to be dispatched is already built.
  Baton runs itself unattended from the milestone that lands the tick, on its own repo,
  before it ever drives Reclaim. Decide that ordering here, and say plainly which
  milestones a person still watches by hand. Milestones sized to one session, with
  dependencies, expected files and whether each destroys anything.
- `docs/milestones/M01.md` … `Mnn.md`: a brief per milestone in Reclaim's shape, each with
  its "Completion evidence" section and a "Copy-ready session prompt" whose part 2 is the
  slot line.
- `CLAUDE.md` at Baton's root: the project's own instructions, implementing the contract.
- Then the M01 kickoff prompt in the seven-part anatomy recorded in
  `/Users/danny/Documents/Apps/Reclaim/CLAUDE.md` ("What a kickoff prompt contains"):
  self-contained, absolute paths, one code block, copy-ready, the handover last.

Decide M01's scope. The likely shape is the project contract plus a single dispatch
triggered by hand — `baton next` reads the handover artifact and runs one `claude --bg` —
before any loop exists, so the first milestone proves the contract and the dispatch and
nothing else. Decide when Baton first drives Reclaim: from M29, from M14, or later — never
from a milestone already in flight — and from which of its own milestones Baton dispatches
the next (the fogged dogfooding question graduates here).

This is the map's destination, and the one deliverable the Notes allow.

### Premises settled by "What a project hands to Baton" (2026-09-11)

The project contract is settled (six clauses on that ticket). Three things are left here: the
migration in Reclaim — which open briefs are refreshed by hand before the first dispatch, the
rest progressively by each close-out; the starting milestone, which must have a conforming brief
and a handover artifact in the inbox, hand-written if its predecessor ran under the old rules;
and where the contract's text lives in Baton's own repository.

### Premises settled by "Watching a dispatched session" (2026-09-11)

M01 builds from `.scratch/baton/prototype/` — the hook fixtures, the `--settings` file, the two
launchd probes and every payload captured under `obs/`. These are the facts the first milestone
must not re-derive.

- **Permission mode.** A `--bg` session cannot run in `auto`: the flag is accepted and the session
  records `default`. `bypassPermissions` is refused until `claude --dangerously-skip-permissions`
  is accepted once interactively (now done on this Mac), then works, and **its deny rules are still
  enforced**. That is the chosen unattended mode; the cost is that nothing prompts, so
  `PermissionRequest`, `Notification` and `PermissionDenied` are all silent.
- **Dispatch and resume.** Dispatch with `--settings <stable path>`; the session saves it. Resume
  **flagless** — any flag forks a copy under a new id; a flagless resume prints
  `woke session <id> with its saved options` and restores `-n`, `--settings`, `--model`,
  `--permission-mode`. Widen an allowlist by editing the settings file in place.
- **The launchd job must live outside `~/Documents`** — it cannot even execute a script there — and
  cannot read file contents or run git under `~/Documents` (metadata succeeds, content fails).
  It gets `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and **no `LANG`**, so set `LC_ALL` before parsing
  `backgrounded · <id>`, whose separator is a two-byte character.
- **The Stop gate** fires from `--settings` in `--bg` and its reason arrives as a `user` record
  prefixed `Stop hook feedback:`. It must stand down while the payload's `background_tasks[]` is
  non-empty, or it manufactures a premature handover.
- **Escalation reaches the Mac, not the phone**: a self-sent iMessage raises no iOS alert. Mail has
  an iCloud sending account as the untested fallback.

## Comments

### Premises settled by "Dispatching more than one at once" (2026-09-11)

Now unblocked: every ticket in "Blocked by" is closed. M01 implements these rather than interprets
them; the detail and the reasons are in that ticket's resolution (§1 the plan file, §3 the algorithm,
§4 the settings file, §5 worktrees and merges, §2 the `~/Documents` decision).

- **The plan file is the milestone table in the target's plan document** (Reclaim:
  `docs/MILESTONES.md`, the "Order and dependencies" table). The tick finds the milestone table by
  its `ID` header cell and the gates table by its `Gate` header cell, reads columns by name — `ID`,
  `Depends on`, `Model`, `Effort`, `Remote`, `Status` — and ignores the rest. Cells hold tokens:
  ids and ranges (`M05, M06`; `M01–M13`; `–` for none), a model alias from `~/.baton/config.json`'s
  list, `Effort` blank or `low|medium|high|xhigh|max`, `Remote` blank or `yes`, `Status` blank,
  `done` or `held`. Gates: `| Gate | Holds | Cleared |`, `Cleared` blank or a D-number. **A cell
  that does not parse fails the whole read**: the project parks (project scope) and nothing is
  dispatched on a guess. `baton plan <project>` prints the graph as parsed and validates every
  `Model` cell; it is a fourth verb beside `tick`, `answer`, `status`.
- **Completion is the `Status` column**: `done` written by the close-out at step (c) on `main` in the
  refresh commit; `held` and its clearing by a person. `merged_as` is still verified before a
  `complete` handover is acted on — two checks of one fact.
- **The tick knows a project from `~/.baton/projects/<project>/project.json`** (`path`: the
  canonical checkout; `plan`: the plan file's relative path) and reconciles every directory under
  `~/.baton/projects/`. `<project>` is the basename of the canonical checkout, never a session's
  `cwd`.
- **The `~/Documents` decision**: the launchd job runs `/Users/danny/.baton/bin/sh` (a copy of
  `/bin/sh`) granted Full Disk Access by hand, once. Every tick starts with a self-check — `cat` the
  plan file and `git -C <path> rev-parse HEAD` per project — whose failure is the "plan file cannot
  be read" project-scope escalation. Two setup facts belong in Baton's plan with the words to do
  them: that grant with its exact path, and the `bypassPermissions` disclaimer (accepted on this Mac
  on 2026-09-11). The proofs are items 36–38 on "Watching a dispatched session"; item 38 — a
  supervisor started by the tick can read `~/Documents` in its sessions — is the one M01 must run
  before the first unattended night, with the two fallbacks named there.
- **The dispatch algorithm, in order** (the ticket's §3, eight steps): self-check → consume the
  inbox (provenance, `merged_as`, brief pointers; reject loudly; archive with the consumed-at
  suffix) → reconcile rows (crash on `pid: null` over two ticks, stall, live prompts, takeover, gap)
  → waits and resumes (all flagless) → eligibility from the plan (dependencies `done`, `Status`
  blank, no uncleared gate) → intersect with the newest archived `complete` handover's dispositions
  (`run` dispatches; `wait` honoured until every `wait_for` reads `done`, a distant `wait_for`
  notifies once; the plan wins on gates both ways and logs the override; escalate only a `run` the
  plan makes ineligible and a plan-eligible milestone no handover lists) → holds and cap (per-model
  limit hold, all models once a second is limited, `fableReserve`, cap of 2 counting live rows and
  parked prompts, order by the handover then fewest-in-flight then row order) → dispatch.
- **Dispatch**: `git -C <path> worktree add ../<Project>-M<nn> -b m<nn> main`, reused if present
  (log the commit it stands at); compose `~/.baton/settings/<project>-<milestone>.json`; read the
  kickoff prompt from the brief on `main` and replace part 2 whole with the slot line (own worktree,
  branch and canonical checkout; other milestones in flight with worktree name and brief, never
  paths; the attempt sentence naming the branch's commit; the staging rule; the refusal); run
  `claude --bg -n "Baton · <project> · <milestone>" --model <Model> [--effort <Effort>]
  --permission-mode bypassPermissions --settings <file> "<prompt>"` with the worktree as `cwd` and
  `LC_ALL` set; `Remote: yes` is three commands — the same with `--remote-control` and no prompt,
  `claude stop <id>`, flagless `claude --bg --resume <uuid> "<prompt>"`; then `caffeinate -i -w
  <pid>` detached; then the dispatch event.
- **The `--settings` file**: `permissions.allow` and `permissions.deny` from the project's
  `permissions.json` (no `ask` rules); `defaultMode` repeated as documentation only — the mode is
  `--permission-mode bypassPermissions` on the flag, restored by resume; hooks `Stop` (standing down
  while `background_tasks[]` is non-empty), `StopFailure`, and `statusLine` writing
  `~/.baton/status/<session_id>.json`, each with `BATON_PROJECT` and `BATON_MILESTONE` on its
  command line. `Notification`, `PermissionRequest`, `PermissionDenied` are gone. The prototype's
  `settings-A.json` and `hooks/` are the working example.
- **Worktrees and merges**: the session merges its own branch at close-out, then runs the project's
  standing check on `main` (from its `CLAUDE.md`; no plan-file field), fixes `main` if it can, else
  writes `stopped` with reason `main-broken`; the session removes its worktree and DerivedData at
  close-out; the tick prunes a leftover worktree only when `Status` is `done`, no live session
  belongs to it, and the archived artifact's `merged_as` is an ancestor of `main`. `main-broken`
  parks the project, in-flight lanes run on, and it resolves by the merge-failed ruling ("finish
  the close-out from step (c)").
- **`~/.baton/config.json`** holds Baton's numbers as defaults overridable by one line: `cap` 2,
  `fableReserve` 80, `stallMinutes` 30, `longRunningHours` 6, `retryMinutes` 15,
  `caffeinateMaxHours` 6, `models` (`fable`, `opus`, `sonnet`, `haiku`, or a full id).
- **The migration in Reclaim**, in one commit: add `Model`, `Effort`, `Remote`, `Status` to the
  table and the gates table (`v0.1 ships` holds M15; `D-026` holds M19); write `done` on the sixteen
  milestones with completion evidence (M01–M13, M27–M29); replace M14's `all` with `M01–M13,
  M27–M29` if it reappears; name the plan file in `CLAUDE.md`'s Documents table; amend the close-out
  clause (merge, then the standing check on `main`, then `Status` `done` at step (c)); the
  `docs/DECISIONS.md` entry the contract ticket already called for. The example table is in the
  ticket's §1.
- **`model_not_found`** at a session's first request is a lane escalation at once, no retry; the plan
  edit is the ruling and the next tick redispatches attempt n+1. `--fallback-model` is never passed.

### Premises settled by "The dispatch log" (2026-09-11)

**The text `docs/ARCHITECTURE.md` carries is that ticket's §1 (the envelope), §2 (the event table
with its footer), §5 (the fifteen recovery derivations) and §8 (the example lines), copied rather
than paraphrased.** §5's sentences are what M01's tests turn into fixtures, and §8 is the fixture to
copy. `docs/SPEC.md` draws its log requirements from §3 (the layout and the append), §4 (prompt
bodies and the takeover rule), §6 (`status`) and §7 (the three things beside the log).

- **The event table is the authority.** Where it drops something an earlier ticket's prose still
  asks for, the table wins and its footer says why. Two things were dropped for a mechanism that no
  longer exists — the permission-denial event with its two once-only notification keys, and the
  `permission` escalation class — and both are still described as live in "Where an escalation goes"'
  own resolution, which `docs/DECISIONS.md` is seeded from. Do not re-derive them from that prose.
  Each carries a revival condition; neither is implemented now.
- **Which milestone must land it.** The log's dispatch-side half — the envelope, the append (one
  `write(2)` per line under 4 KB under the lock), the `dispatch` and `dispatch_failed` events, the
  prompt sidecars with `prompt_path` and `prompt_sha256`, and the attempt derivation — lands in
  **M01**, because `baton dispatch <milestone>` cannot state an attempt number, compose a slot line
  or be run twice without it. **The whole table and all fifteen derivations must land no later than
  the milestone that lands the tick**: the tick's first act is to reconcile from the log, and every
  rule it runs is a derivation over it, so the first tick cannot run without the complete schema.
  There is no milestone between those two in which a partial log is coherent.
- **The files M01 creates under `~/.baton/`**, beside those already listed: `log.jsonl`,
  `last-tick`, and `prompts/<session>/<n>.txt`. `last-tick` is written last and atomically
  (`.tmp` then rename) so its meaning is *a tick completed*; `status` prints it first, and the gap
  report measures against it rather than against the newest event.
- **A third setup fact**, beside the Full Disk Access grant and the `bypassPermissions` disclaimer:
  **`cleanupPeriodDays`**. It defaults to **30 days** and sweeps transcripts, `~/.claude/tasks/`,
  `shell-snapshots/`, `backups/` and job worktrees; this Mac sets `3650` in
  `~/.claude/settings.json`. "A transcript exists for this session id" is the resume-versus-redispatch
  test and the substrate of the takeover rule, so a fresh Mac at the default silently changes both
  after thirty days. The plan records the setting with the words to check it.
- **Three live proofs (45–47)** on "Watching a dispatched session" gate parts of this: the hash
  normalisation (45) must pass before the takeover rule is trusted, and 46 and 47 fill in the
  `copy_fork` and `dispatch_failed` events' parsing. 45 is offline and can be done at any time.

### Resolution — 2026-09-11

**Decided: the founding document set is written, eight milestones bootstrapped in one lane, M01 on
Fable and the rest on Opus, Baton driving only itself and fixture projects until every milestone is
done, and Reclaim after that.** The one ruling given at the keyboard while resolving this ticket:
Baton does not take over Reclaim until Baton is complete; until then it runs on test content. The
other decisions below were made against the tickets' own terms.

#### Files written

- `CONTRACT.md` — the six clauses once, Baton's side beside them, the artifact by example.
- `docs/SPEC.md` — 95 REQ entries in eleven families, each citing its ticket by name; what Baton never does; twelve invariants; the verification strategy; delivery; the live-proof table.
- `docs/ARCHITECTURE.md` — the repository layout and the installed relay; `~/.baton/` and every file's shape; the tick's eight steps; the verbs; the slot line, the two continuations, the ruling label and the copy-fork parse rule; the three hooks; the lane states and the stops taxonomy; the log's envelope, event table with its footer, sidecars and the takeover rule, the fifteen derivations and the example lines, copied from "The dispatch log"; the seams and the fixture layout; §10 interfaces per milestone.
- `docs/DECISIONS.md` — D-001 (ADR 0001) to D-017 seeded from the resolutions, D-018 to D-024 made here; next free D-025.
- `docs/MILESTONES.md` — the plan file: the eight-row table with `Depends on`, `Model`, `Effort`, `Remote`, `Status` and the gates table (`Reclaim migrated` holds M08); the rules for every session; traceability REQ family → milestone; what a person still does by hand per milestone; the split rule; the handoff template.
- `docs/milestones/M01.md` … `M08.md` — a brief each in M28's shape with `## Completion evidence` (empty) and `## Copy-ready session prompt` whose part 2 is the slot line verbatim.
- `CLAUDE.md` — the start-every-session list, the handing-over method, what a kickoff prompt contains, the hard rules, the documents table.
- `CONTEXT.md` — nine terms added: verb, prompt sidecar, copy fork, tick marker, gap report, fixture project, installed relay, bootstrap, project key.

#### The decisions, points 1–6

1. **M01's scope.** `baton plan` and `baton dispatch <project> <milestone>`, run by hand, plus the log's dispatch-side half (the envelope, the one append under the lock, `dispatch` and `dispatch_failed`, the prompt sidecars with their hash, the attempt derivation), the three hooks cut from the prototype, the seams and the fixture runner, and `install.sh`. Consumption is M02, because a hand-run dispatch of M02 needs only a plan reader and a dispatcher — the person reads M01's handover — while `baton dispatch Baton M03` needs M02's `done` trusted through `merged_as`, which is consumption. "The dispatch log" §12 required the dispatch-side half in M01 for the same reason: a dispatch cannot state an attempt number or compose a slot line without it.
2. **The sequence** (D-019): M01 plan reader and dispatch; M02 the inbox and the whole log (event table, fifteen derivations, `status`); M03 the tick under launchd with the lock, the marker, the self-check, the granted shell and rows; M04 waits, the ladder, continuations, the api-error routing; M05 escalations, the Mac message, `answer`, `allow`, takeover; M06 the cap, the holds, `fableReserve`, pruning, `main-broken`; M07 remote dispatch and acceptance; M08 Reclaim onboarding. The event table sits in M02 rather than M03 because the schema must exist no later than the milestone that lands the tick. **Watched by hand: M01–M03** (M01 built by hand on `main`; M02 and M03 dispatched by `baton dispatch`). **M04 is the first a tick dispatches**, still watched because the ladder does not exist while it runs; **M06 is the first unattended night**, on Baton's own repo, after M04 and M05 have put recovery and the channel underneath it.
3. **Model and effort** (D-020): M01 Fable — it sets every idiom the rest inherit; M02–M08 Opus; `Effort` blank throughout; `/review-2` pinned to Fable on M02 (the derivations) and M03 (the tick), the two things every later rule reads, so the scarce model reviews rather than authors there.
4. **Reclaim** (D-021): after every Baton milestone is done, never before, and never a milestone in flight — M14 is in flight at the time of writing. M08 is held by the gate `Reclaim migrated`. The migration commit is a person's act in an interactive Reclaim session (it edits Reclaim's plan and `CLAUDE.md`, which the contract makes a person's documents), containing the four columns, the gates table with the built milestones `done`, the slot line and the two headings in every dispatchable brief, the close-out step in `CLAUDE.md`, the plan file named in its Documents table, and Reclaim's next free D-number taken at the moment it is written. M08 then registers Reclaim (`project.json`, `permissions.json`), checks the plan parses, proves item 38 on its path, and writes the hand-written starting artifact. The first Reclaim milestone is whichever gate the person clears first; M19 is recommended over M15 because it changes no real files.
5. **The contract's text** (D-022): once, in `CONTRACT.md` at the root; `docs/SPEC.md`'s REQ-CONTRACT family binds Baton to it; a target's `CLAUDE.md` cites it by path.
6. **Baton's `CLAUDE.md`**: written; `docs/MILESTONES.md` is the plan file in the decided format. Two further calls made here: no `docs/STATUS.md` (D-023 — the plan file, the briefs and `baton status` are the state), and the running relay is the copy installed under `~/.baton/bin/` by `install.sh`, so a merge changes nothing until a person installs and a milestone cannot break the tick that dispatched it (D-018). The repository layout is D-024.

#### Checks

- **Every REQ cites a ticket by name, and no REQ exists that no ticket decided — checked.** 95 rows; each row's `Decided by` cell names one of the eight tickets (three name "Baton's plan and its M01 prompt" for what this ticket decided: REQ-DISPATCH-10, REQ-VERB-06, REQ-SETUP-05). REQ-DISPATCH-08 also cites the peer session's binary strings for the four stderr forms, which the log ticket's amendment left as item 47.
- **`docs/MILESTONES.md` parses under the plan-file rules by inspection — checked.** Eight rows; `Depends on` is `–` or a single id; `Model` is `fable` or `opus`; `Effort`, `Remote`, `Status` blank; the gates table `| Gate | Holds | Cleared |` present with one row, `Cleared` blank.
- **Every brief has the two exact headings and the slot line verbatim — checked.** Eight briefs, each with exactly one `## Completion evidence`, one `## Copy-ready session prompt`, one `WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.`, and seven part markers.
- **The M01 prompt has its seven parts in order and ends with the handover — checked.** Identity, slot line, startup order with the recovery clause, what to settle with the prototype's evidence, constraints, verification pointing at §8, numbered close-out whose last item writes and prints the artifact.
- **Unchecked:** nothing was executed. No parser exists yet; "parses by inspection" is a read, and `baton plan Baton` on the first tick is the real check.

#### Peer session

"Milestone Model Audit" answered three questions from the binary's strings, carried into `docs/ARCHITECTURE.md` §4.3 and `docs/SPEC.md` REQ-DISPATCH-08: `--effort` is a top-level flag restored by a flagless resume; the copy-fork `note:` line has eight variants and one parse rule; a failed `--bg` is detected by the absence of the `backgrounded · <id>` line and classified by four known stderr strings, streams and exit codes left as item 47.
