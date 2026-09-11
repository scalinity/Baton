Title: Dispatching more than one at once
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: 01, 05

## Question

What does the plan file hold, how does the tick read it at dispatch, and what policy governs what
runs at once — the file, its reader, then the rules. One conversation, because every field the
reader needs must exist in the file and no field may exist twice.

**The file.** Read first: Symphony's `WORKFLOW.md`, YAML front matter on a repo-owned file with
typed getters, defaults and hot reload, the one machine-readable carrier in prior art that a runner
reads without a model (`.scratch/baton/research/prior-art.md` §1.13, and §2.3 under "Which model
runs which milestone"). The crux carried in from the contract: one source for the graph, never
two — either `docs/MILESTONES.md`'s table is the plan file, or the table derives from it. Decide
the plan file's format and location, named by the project's `CLAUDE.md`; whether model and effort
ride along (the handover carries no model; the allocation lives with the plan, a finishing session
that learns the plan is wrong edits it at refresh time with its reason, and the dispatch log
records what actually ran and why it differed); how Baton knows a milestone is complete for
milestones that predate Baton (a status per milestone, or the brief's completion evidence); how a
gate and its cleared state are written (cleared only by a person's edit committed with a decision
entry); and whether lanes, a per-model cap and a worktree property for spikes are fields of this
file. Candidates seen so far: a `Model` column in the target's `docs/MILESTONES.md`; an
`orchestration.json` beside `ORCHESTRATION.html`, which today holds the allocation only as HTML
(4 Fable, 11 Opus across Reclaim's remaining fifteen); front matter per brief. `--model` accepts
the aliases `fable`, `opus`, `sonnet`, `haiku`; decide whether `--effort` is part of the routing.

**The reader.** The tick reads the plan file on every run, makes one git check, and remembers
nothing. At dispatch it computes dependency-eligibility, intersects it with the handover's `run`
entries, honours the plan's gates even when a handover omits them, and escalates disagreement by
milestone name. Decide: how the slot line is composed from the dispatch log — the milestones in
flight, their worktrees and their briefs, never their paths; how worktrees are created and named
(`-w`, or the project's own `../<Project>-M<nn>` convention — the M10–M13 sessions each ran
`git worktree add ../Reclaim-M<nn> -b m<nn>` themselves and `git worktree remove` at close-out;
check whether `-w` places the worktree where the project's conventions expect it, and carry the
rack's lesson that a running app must be addressed by its DerivedData hash because every worktree
builds something called `Reclaim.app`); and the cap — how many at once, bounded by quota, CPU and
Xcode builds, and whether it is per model (Fable is scarce; Opus is not), with each dispatched
session holding a `caffeinate` of its own.

**The policy.** Quota across a night: when Fable dispatch stops for the night and whether Opus
lanes carry on, and what Baton does when the Fable limit is hit with a Fable milestone next — wait
for the reset (the rack never downgrades a Fable milestone silently), or dispatch Opus and record
that it did. Who merges: today the session merges its branch into `main` at close-out; a failed
merge now writes a `stopped` artifact with reason `merge-failed`, whose handling belongs to "What
stops a session, and what happens next" — decide here whether the merge stays the session's and
what Baton does when the build on `main` breaks after two lanes merge: dispatch a fix session, or
serialise the lane and escalate. Shared-spine collisions: `docs/STATUS.md`, `docs/DECISIONS.md`
(the same D-number taken twice), `docs/ARCHITECTURE.md` §10, `Reclaim/AppModel.swift`,
`Reclaim/Shared/SidebarView.swift` are managed by discipline — stage only your own paths, never
`git add -A`. Baton cannot add discipline; it can detect the aftermath. Decide whether it should.
That Baton records which model ran which milestone is settled: it is the dispatch log's first
required field (grading a milestone's output against the house standard needs the model written
down somewhere the grader does not look until after).

Evidence: `docs/STATUS.md` in Reclaim carries the conflict-check paragraphs for M28 and M19,
including the lesson that a brief's §5 list is proposed rather than exhaustive (M19's §5 omits
`AppModel.swift`; its §7 names it twice). `claude agents --json` showed three Reclaim sessions
running at charting, so parallel sessions are already the practice. The handover is an artifact in
`~/.baton/inbox/` whose `eligible[]` entries carry a `disposition` (`run`; `wait` with `wait_for`;
`held` with `held_by`) and a pointer to the brief, with no worktree field and no model; the kickoff
prompt is read from the brief, and its part 2 is the slot line `WHAT ELSE IS IN FLIGHT. Runs alone
unless the dispatch says otherwise.`, which Baton replaces whole at dispatch; the standing
parallel-run rules live in part 5 and the refusal in part 7.

### Premises settled by "Relay or conductor" (2026-09-11)

"Which model runs which milestone, machine-readably" is folded in here as "The file", because the
reader cannot be decided without the file's shape and the file should carry no field the reader
does not use; the map's fogged "Quota across a night" moved into "The policy". Baton embeds no
model call, so a fix when `main` breaks after two lanes merge is dispatched as a session that
returns an artifact, never computed in the tick.

### Premises settled by "What stops a session, and what happens next" (2026-09-11)

Five rules land here. (1) The dispatch hold: while a `rate_limit` or `billing_error` wait is active for a
session on model X, the tick dispatches nothing on model X; if a second model hits `rate_limit` during
that wait the limit is shared, and every model is held until the wait clears — one refused request to
learn which kind of limit it is, read from the log, no text parsed. The per-model cap and the
which-lanes-run-overnight policy sit beside it. (2) A `blocked` stop with `blocked_by` is a dispatch-time
state: the milestone leaves the in-flight set and is redispatched once the plan file shows the named
milestone complete, silently only while that milestone is in flight or dependency-eligible now;
otherwise it escalates. (3) `merge-failed` resolves by a ruling that resumes the session to finish the
close-out from step (c); the fallback when the session is gone is a person marking the milestone complete
in the plan file with the successor prompts refreshed by hand — so the plan file's completion state must
be a field a person edits, and the reader must accept it. (4) On a redispatch, the slot line Baton composes
carries "This is attempt <n> at this milestone; a previous session may have left completion evidence in the
brief, which the recovery clause covers." — part 2 is Baton's paragraph and the recovery clause keys on the
brief. (5) No per-milestone hours field yet: the six-hour long-running notification is a Baton default until
the first brief says it needs ten hours; whether Baton detects shared-spine collisions before merge is
decided here, the aftermath being the session's `merge-failed`.

### Premises settled by "Where an escalation goes" (2026-09-11)

**The `--settings` file Baton passes at dispatch now carries the permissions as well as the hooks**,
and its composition is a dispatch-time step this ticket specifies. Two parts: the project's
permissions, held as Baton's own state at `~/.baton/projects/<project>/permissions.json`
(`permissions.allow` and `permissions.deny`, nothing else, and `baton allow` is its only writer
besides a person's edit); and Baton's block — `permissions.defaultMode: "auto"` plus the four
injected hooks (the Stop gate, StopFailure, `PermissionRequest`, `PermissionDenied`), each with the
project and milestone baked into its command as arguments. The same file is passed again on every
resume, which is what lets a rule written by `baton allow --resume` take effect for the session
already running. **The permission mode does not vary by worktree** — the worktree is the undo, not a
permission boundary — so nothing in the worktree decision keys on it. The project contract is
unchanged at six clauses: the allowlist is deliberately *not* a clause, so the target repository
needs no `.claude/settings.json`.

**A new plan-file property: `remote`, default false.** A milestone marked `remote: true` is
dispatched with `--remote-control`, so a live permission prompt or in-tool question in it can be
answered from the Claude app. It is off by default and never inferred, because a Remote Control
session's transcript is stored on Anthropic's servers while connected, and that trade is only worth
making for milestones chosen in advance to be answerable away from the Mac.

**The second project-scope escalation is this ticket's to detect.** An escalation parks its lane;
three failures park all dispatch for a project, and one of them is *main does not build after a
merge* — which needs a builder, so under ADR 0001 it is a dispatched fix session, never anything the
tick computes. The merge policy decided here owns both the detection and what is dispatched. The
other two project-scope members (the plan file cannot be read; Baton itself is unhealthy) are
already covered. Note the boundary the escalation ticket drew: `merge-failed` is **lane**-scoped,
because a failed merge lands nothing and main is exactly as it was — the project-scope cousin is a
merge that *succeeded* and left main broken.

**The per-model dispatch hold is not an escalation and does not become one**, nor does
plan-versus-advice disagreement, which stays lane-scoped per milestone name.

### Premises settled by "Watching a dispatched session" (2026-09-11)

- **Quota is observable live, per session.** The statusLine stdin carries
  `rate_limits.five_hour.{used_percentage,resets_at}` and the same for `seven_day`, with
  `resets_at` as epoch seconds. This is the signal a limit-aware dispatcher reads; the agents view
  has nothing like it. (It also settles the "field later" question that the wait was parked on.)
- **Sessions are independent rows and the name is the only ownership marker.** `kind: "background"`
  does not separate Baton's sessions from ones a person backgrounded. Name them
  `Baton · <project> · <milestone>`; the model does not belong in the name because the statusLine
  reports it per session and a resume restores it.
- **Worktree isolation cannot be relied on for file-overlap safety.** It gates the Write and Edit
  tools only: a session wrote into the shared checkout through a Bash heredoc and never moved into
  a worktree. The conflict check stands on the briefs, not on the harness.
- **A concurrent lane is cheap to watch but not to read.** `claude agents --json` is the only
  cross-session view; answering a parked row in place clears `waiting` within one second.
- **`--remote-control` cannot be combined with dispatching work**: the session starts idle and the
  positional prompt is discarded, with no transcript written.

## Comments

### Resolution — 2026-09-11

**Decided: the milestone table in the target project's plan document is the plan file, read as tokens;
the tick reads it and runs its git check through a Baton-owned copy of `/bin/sh` granted Full Disk
Access; every milestone runs in a worktree Baton creates from `main`; the session merges its own branch
and builds `main` afterwards; at most two sessions run at once; the plan's gates win over a handover's
word in both directions and a handover's `wait` is honoured until its targets read `done`.** The plan
file's format (§1), the tick's dispatch algorithm in order (§3) and the `--settings` file's contents
(§4) are written out so that M01 implements them. Every numbered point of the brief and every bullet of
the merged Question is accounted for in §8.

#### 1. The plan file

**One source: the table is the plan file.** For Reclaim it is the "Order and dependencies" table in
`docs/MILESTONES.md`, which people already read and edit and which the tick parses. No generated
second file, no front matter, no per-brief metadata: two hand-maintained sources is the
M27-in-no-row failure with two chances to happen, and one artefact a person edits and a script parses
is the only shape that cannot drift. Symphony's `WORKFLOW.md` (prior-art §1.13) is the precedent for a
repo-owned file a person reads and a runner parses without a model.

The tick locates two tables in the file by their header rows, wherever they sit: the **milestone
table**, whose first header cell is `ID`, and the **gates table**, whose first header cell is `Gate`.
Columns are found by header name; their order and any further columns (`Title`, `User-visible
result`, `Real files changed?`) are ignored by the tick and kept for people.

Three conditions, written into the project contract so the table stays parseable:

1. **Cells hold tokens, never prose.** `Depends on` is milestone ids and ranges (`M05, M06, M27`;
   `M01–M13, M27–M29`, en dash or hyphen), or `–` for none — never `all`, which M14's row once said
   and which a script cannot expand honestly. `Model` is an alias from Baton's own list (`fable`,
   `opus`, `sonnet`, `haiku`, or a full model id; the list lives in `~/.baton/config.json`, so a new
   alias is one line). `Effort` is blank or one of `low`, `medium`, `high`, `xhigh`, `max` (`claude
   --help`, 2.1.268), blank meaning the CLI's default. `Remote` is blank or `yes`. `Status` is blank,
   `done` or `held`. A gate's name is the one non-token: a string, matched by equality against a
   handover's `held_by`. **A cell that does not parse fails the whole read, loudly**: the tick refuses
   to dispatch for that project rather than dispatching on a guess. That is the "plan file cannot be
   read" project-scope escalation already decided, and it is the right outcome for a typo.
2. **`Status` has one writer per transition.** The close-out writes `done` at step (c), on `main`,
   after the merge, in the same commit that refreshes the successor briefs. A person writes `held`
   (the merge-failed fallback, or any deliberate hold without inventing a gate) and clears it. Blank
   means not yet; whether it is in flight is the dispatch log's knowledge, never the column's. The
   brief's Completion evidence stays the human record; the tick reads only the column — M05 left
   evidence when it was cut off, and the recovery clause exists precisely because a non-empty evidence
   section means "worked on", not "done". **The column and `merged_as` are two checks of one fact,
   and both stay**: the column is what eligibility is computed from; `merged_as` on the artifact is
   verified before the handover is acted on, so a close-out that wrote `done` without the merge
   landing fails the second check (the "artifact lies" case from the contract).
3. **The gates table names what each gate holds.** `Gate`, `Holds` (milestone ids), `Cleared` —
   empty, or the D-number of the decision entry that cleared it. Clearing a gate is one cell edit in
   the same commit as the decision, which is the rule the contract already fixed. The tick treats
   `held` in `Status` exactly as an uncleared gate: never dispatched, shown by `status` as waiting on
   a person.

**Milestones that predate Baton** get `done` written once, by hand, during Reclaim's migration, in
the same commit that adds the columns — every milestone whose brief carries completion evidence
(sixteen at the time of writing: M01–M13, M27–M29). A migration step for "Baton's plan and its M01
prompt" to list.

**The example, as a person could write it for Reclaim today** (rows abridged; `Effort` left blank
throughout because the rack allocates models, not effort):

```markdown
## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status | User-visible result | Real files changed? |
|---|---|---|---|---|---|---|---|---|
| M01 | Foundation and permissions | – | opus | | | done | App launches, shows Permissions screen … | No |
| M05 | First real removals | M03, M04 | opus | | | done | Confirmation, results, undo … | **Yes** |
| M13 | Menu-bar monitor | M05 | opus | | | done | Menu-bar extra … | No |
| M14 | Release hardening and acceptance | M01–M13, M27–M29 | opus | | | | Installed Release build … | No |
| M15 | Helper feasibility spike and quarantine engine | M14 | fable | | | | Helper screen installs … | No (fixtures only) |
| M16 | System caches, rotated logs, … | M15 | opus | | | | System category … | **Yes** (root-owned, quarantined) |
| M17 | Root-owned apps, system agents and daemons, snapshots | M16, M10, M12 | fable | | | | … | Yes |
| M19 | AI foundation | M05 | fable | | | | Settings › Intelligence … | No |
| M20 | Explanations | M19, M10 | opus | | | | "What is this?" … | No |
| M28 | What appeared, and the space timeline | M05, M06, M27 | fable | | | done | What's New category … | **Yes** |
| M29 | Live file watch | M28 | opus | | | done | A screen that shows files being created … | No |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| v0.1 ships | M15 | |
| D-026 | M19 | |
```

**What is not a field, and why.** `lane`: derived — a lane is the `wait_for` chain a handover
draws, and the plan's dependency column, never a declaration. `isolate`: every milestone runs in a
worktree (§5), so there is nothing to opt into. A `cap`: a property of the Mac, in Baton's config (§6).
A `check` command: the project's standing check lives in its `CLAUDE.md` (§5). A per-milestone hours
field: still deferred until a brief asks for it, as the stops ticket decided.

**`baton plan <project>`** — one verb added to `tick`, `answer` and `status`: parse the plan file and
print the graph as the tick sees it (complete, eligible, held by which gate, in flight, model and
effort per milestone), and validate every `Model` cell against the alias list. It is `status`
applied to the plan: a person editing the table runs it the way they would run a linter, and a
misspelled model on M19 is found on the day the table is edited, not on the night M19 is dispatched.

**How the tick knows a project.** `~/.baton/projects/<project>/` already holds `permissions.json`;
it gains `project.json` with two fields: `path`, the canonical checkout, and `plan`, the plan file's
path relative to it (`docs/MILESTONES.md`). The tick reconciles every directory under
`~/.baton/projects/`. A person writes the file once; whether M01 adds a verb for it is M01's call.

**The name and the project key.** Confirmed: `Baton · <project> · <milestone>`, the name being the
only ownership marker a row carries (prototype: `kind: "background"` does not separate Baton's rows
from a person's). `<project>` is **the basename of the artifact's `project` field** — the canonical
checkout, never a session's `cwd`, whose basename in `../Reclaim-M28` would put that milestone under
a second project. The same word keys `~/.baton/projects/<project>/`, the escalation address
(`Reclaim M29 · asking`), and the long form `baton answer Reclaim/M29`. A folder rename is a
migration, not a mismatch: the log's old entries keep the old name (the log is history) and `status`
says "no project at this path" rather than silently starting a second project beside the first.

#### 2. The reader's ground: the tick cannot read under `~/Documents`

The prototype found that a launchd-started process cannot read file contents or run git under
`~/Documents` while `stat` and `test -r` succeed, so a readability guard passes right before the read
fails ("Watching a dispatched session", "What a launchd context cannot do"). Every target project
lives there.

**Decided: Full Disk Access for a Baton-owned copy of the shell.** `cp /bin/sh ~/.baton/bin/sh`, add
`/Users/danny/.baton/bin/sh` by hand once in System Settings › Privacy & Security › Full Disk Access,
and run the launchd job with it as its executable
(`ProgramArguments: /Users/danny/.baton/bin/sh /Users/danny/.baton/bin/baton tick`). TCC records a
grant against the executable's path, so the grant is Baton's and `/bin/sh` stays ungranted. The
contract stays at six clauses and the tick keeps verifying `merged_as` itself. Rejected: mirroring
the plan and the merge fact into `~/.baton` at close-out (a seventh clause, and the tick would trust
the session for the one fact it was built to verify, while a hand edit to the plan — a cleared gate,
a `done` — would be invisible until the next session ran); moving the projects out of `~/Documents`
(every absolute path in every Reclaim brief, prompt, decision entry and the rack, for Baton's
convenience).

**The hazard the option does not name, and the proof that matters most.** TCC attributes access to
the responsible process and its children inherit it, so the granted shell covers `cat`, `git`, `jq`
and `claude --bg` as its child. But the background service the tick starts when it is down
(`Starting background service…`) detaches, and whether a detached daemon keeps the parent's
attribution or is judged on its own executable is the kind of thing TCC is subtle about. The
prototype's launchd run C started the daemon itself (`daemon status` before: `not running`) and its
session did no file read (`Say exactly: launchd-ok`), so nothing yet shows that a supervisor started
by the tick can read `~/Documents` inside the sessions it runs. If it cannot, the fallback is
deterministic: grant the `claude` binary as well (its path changes per version, so the grant is
renewed on update), or have the tick never start the daemon and treat "service down" as a
project-scope escalation. Four items go on the prototype's evidence (§9).

**The read is a self-check the tick runs first, every tick**: `cat` the plan file and `git -C <path>
rev-parse HEAD` for each project before anything else. A failure is the "plan file cannot be read"
project-scope escalation, already decided — so a grant revoked by a macOS update is a notification
within a minute, not a silent night of nothing dispatched while `stat` says all is well.

**Two setup facts the plan records**, because neither lives in any repository and a fresh Mac fails
without them: the Full Disk Access grant with its exact path, and the `bypassPermissions` disclaimer
(`claude --dangerously-skip-permissions` once, interactively; accepted on this Mac on 2026-09-11).
Beside them, from the prototype: the plist sets `LC_ALL` (no `LANG` under launchd; `·` is two bytes)
and `AbandonProcessGroup`, and reaches the CLI by absolute path.

#### 3. The dispatch algorithm, in order

The tick runs the stops ticket's spine — consume → reconcile rows → waits and resumes → dispatch —
with the self-check in front and the dispatch step expanded. Every step reads only the five inputs
(the dispatch log, `claude agents --json`, the inbox, the plan file, one git check) and the status
feed; nothing is remembered between ticks.

1. **Self-check.** For every `~/.baton/projects/<project>/project.json`: read the plan file in full
   and parse both tables; run `git -C <path> rev-parse HEAD`. Either failing parks the project
   (project scope, "plan file cannot be read", the path and what failed) and skips it for the rest of
   the tick. A stale lock is reported before this, as decided.
2. **Consume the inbox.** For each `*.json` (never `.tmp`): parse; check provenance (the `session`
   has a transcript found by glob, the `project` is a registered checkout); for `complete`, verify
   `merged_as` is an ancestor of `main` in the canonical checkout; verify each `brief` pointer's path
   and heading on `main`. Reject loudly to `~/.baton/rejected/` with a log event and a lane
   escalation; otherwise archive as `<milestone>-<session>-<consumed-at>.json` and log the ending.
   `asking` stops the session at once; `stopped` routes by reason (§5 adds `main-broken`).
3. **Reconcile rows** against the log's in-flight sessions: crash (`pid: null`, confirmed on two
   ticks), stall (30 min of unchanged transcripts, the session's and its subagents'), live prompts
   and questions (`waitingFor`), a takeover (a typed record the log did not send), and the gap
   report. For `remote: yes` sessions the row is not a park detector (§7): parks are artifact-borne
   only, and an unanswered phone prompt surfaces as a stall.
4. **Waits and resumes.** Fifteen-minute retries due; rulings queued by `answer`; `merge-failed` and
   `main-broken` resumes; the six-hour `caffeinate -i -t` bound. Every resume is flagless.
5. **Compute eligibility per project from the plan.** A milestone is eligible when every id in
   `Depends on` reads `done`, its `Status` is blank, and no uncleared gate holds it. `held` and an
   uncleared gate are the same state to the tick. The plan wins on gates in both directions (step 6).
6. **Intersect with the handover's dispositions.** For each eligible milestone, the disposition in
   force is the one in the newest archived `complete` handover of that project that lists it:
   - `run` → a dispatch candidate.
   - `wait` with `wait_for` → honoured while every named milestone is in flight, eligible or done;
     dispatch the moment they all read `done`, without waiting for a new handover. A `wait_for`
     naming a milestone that is none of those (three gates away, or misnamed) notifies once, like a
     distant `blocked_by`, because it would otherwise park the lane for days on nobody's decision.
   - `held` on a gate the plan shows cleared → the plan wins: dispatch, and log the override
     (`plan overrode disposition: gate v0.1 ships cleared by D-118`). A `run` on a milestone the plan
     holds → the plan wins: not dispatched, logged, not an escalation. A gate is a person's recorded
     act and the session's word about it is always the older of the two.
   - Exactly two things escalate, lane-scoped, by milestone name: a `run` whose milestone the plan
     makes ineligible (a dependency not `done`), and a plan-eligible milestone no archived handover
     lists at all (an omission). Resolution is an edit to the plan or the brief, or a hand-written
     handover artifact in the inbox, re-read on the next tick.
7. **Apply the holds, then the cap.** Drop candidates on a model with an active `rate_limit` or
   `billing_error` wait (every model once a second model is limited). Drop `fable` candidates while
   the freshest status file's `seven_day.used_percentage` is at or above `fableReserve` (§6). Count
   in flight: every logged session with a live row, plus every parked lane holding a live prompt;
   stopped `asking` sessions do not count. Dispatch while the count is below the cap, in this order:
   the handover's `eligible[]` order within a project; across projects, the project with fewer in
   flight first; then plan row order.
8. **Dispatch**, per candidate:
   - `git -C <path> worktree add ../<Project>-M<nn> -b m<nn> main` — from `main` explicitly, never
     from whatever the checkout has checked out. If the worktree exists (a redispatch), reuse it and
     log the reuse with the commit it stands at.
   - Compose the `--settings` file at `~/.baton/settings/<project>-<milestone>.json` (§4), a stable
     path so a later `baton allow` edits it in place and a flagless resume restores it.
   - Read the kickoff prompt from the brief (`brief.path`, the code block under `brief.heading`, on
     `main`) and replace part 2 whole with the slot line: the worktree, the branch and the canonical
     checkout for this session; every other milestone in flight with its worktree name and its
     brief, never its path; the attempt sentence on a redispatch, naming the commit the branch stands
     at; the staging rule; the refusal. For example:

     > WHAT ELSE IS IN FLIGHT. You are working in /Users/danny/Documents/Apps/Reclaim-M19 on branch
     > m19; the canonical checkout is /Users/danny/Documents/Apps/Reclaim — merge there at close-out
     > and refresh there. Also in flight: M28 (worktree Reclaim-M28, brief docs/milestones/M28.md).
     > Stage only your own paths; never git add -A. This is attempt 2 at this milestone; a previous
     > attempt left work on this branch at 1a2b3c4, and the brief may hold completion evidence, which
     > the recovery clause covers. Do not start the milestone after this one.

   - Run, with the worktree as `cwd` and `LC_ALL` set:
     `claude --bg -n "Baton · <project> · <milestone>" --model <Model> [--effort <Effort>]
     --permission-mode bypassPermissions --settings <file> "<prompt>"`. Parse
     `backgrounded · <id>`.
   - `Remote: yes` is the two-step path (§7): the same command with `--remote-control` and **no
     prompt** (the session starts idle), then `claude stop <id>`, then a flagless
     `claude --bg --resume <uuid> "<prompt>"`.
   - Read the row's `pid` from `claude agents --json`; start `caffeinate -i -w <pid>` detached.
   - Log the dispatch: project, milestone, session id, name, model, effort, worktree, reused-at
     commit, attempt number, the prompt text and the time.

Session dispatched inside a linked worktree: the background-isolation guard is documented as skipped
("already inside a linked git worktree, whether Claude created it … or you created it",
background-sessions §9), so `CLAUDE_CODE_BG_ISOLATION` is not set; live confirmation is item 41 (§9).

#### 4. The `--settings` file

Re-decided on the prototype's finding that a `--bg` session cannot run in `auto` (the flag is accepted
and `default` recorded, three ways) and that under `bypassPermissions` the deny rules are enforced and
nothing parks, so `PermissionDenied` never fires and `PermissionRequest` has no prompt to record. The
prototype also showed the permission **rules** travel through `--settings` and the permission
**mode** does not (item 30), and that a flagless resume restores `--permission-mode` (§10-3).

- **The mode is the flag**: `--permission-mode bypassPermissions` on the command line, restored by
  resume. `permissions.defaultMode` is repeated in the file as documentation only.
- **`permissions.allow` and `permissions.deny`** copied from `~/.baton/projects/<project>/permissions.json`.
  Allow rules are kept: they allow nothing under bypass and cost nothing, and a hand-started session
  under `default` passing the same file then behaves as a dispatched one does. **No `ask` rules**:
  under bypass a prompt cannot happen, so an `ask` rule is either auto-allowed or auto-denied and no
  string or document says which (item 42). `baton allow` refuses to write one.
- **Three hooks, the three that fire**: the Stop gate, which stands down while the payload's
  `background_tasks[]` is non-empty (a gate that blocked a session waiting on its own subagent
  manufactured a false handover); `StopFailure`, writing the `api-error` artifact; and the
  `statusLine` command, writing its stdin to `~/.baton/status/<session_id>.json`. Each command carries
  the project and milestone as environment on its command line, as the prototype's fixtures do.
  `Notification`, `PermissionRequest` and `PermissionDenied` are dropped: none fires under bypass.
- **A deny-rule refusal is invisible to Baton, and that is accepted.** A `permissions.deny` match
  under bypass hands the model a refusal and fires nothing; the model works around it or asks, and
  asking arrives as an `asking` artifact through the path that already exists. The deny list is a
  rail the tick cannot see being hit; nobody later builds a watcher for an event that does not exist.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Bash(xcodebuild:*)", "Bash(swift:*)"],
    "deny": [
      "Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)",
      "Bash(osascript * administrator privileges*)",
      "Read(//Users/danny/.baton/log/**)", "Edit(//Users/danny/.baton/log/**)", "Write(//Users/danny/.baton/log/**)",
      "Edit(//Users/danny/.baton/archive/**)", "Write(//Users/danny/.baton/archive/**)"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "BATON_PROJECT=Reclaim BATON_MILESTONE=M19 /Users/danny/.baton/bin/statusline"
  },
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "BATON_PROJECT=Reclaim BATON_MILESTONE=M19 /Users/danny/.baton/bin/stop-gate" }] }],
    "StopFailure": [{ "hooks": [{ "type": "command",
      "command": "BATON_PROJECT=Reclaim BATON_MILESTONE=M19 /Users/danny/.baton/bin/stop-failure" }] }]
  }
}
```

The allow and deny lines shown are illustrative of the two deny classes "Where an escalation goes"
fixed (privilege escalation; Baton's own state by named path); the exact rule forms for the state paths
are M01's to write from the prototype's `settings-A.json`, which is the only working example.

#### 5. Worktrees, merges and the broken `main`

**Every milestone runs in a worktree Baton creates.** `../<Project>-M<nn>` on branch `m<nn>`, the
project's own convention (M10–M13 ran exactly that themselves, with DerivedData beside it), branched
from `main` explicitly, reused on redispatch so an attempt-2 session resumes on the branch that holds
the evidence. Worktree isolation gates only the Write and Edit tools (a session wrote into the shared
checkout through a Bash heredoc), so **the conflict check stands on the briefs, not on the harness**;
the worktree is the undo and the merge boundary, not a permission boundary. The cost is a cold Xcode
build per milestone — Reclaim's rule is DerivedData per worktree, addressed by hash, so there is
nothing to share — and a milestone of hours absorbs a first build of minutes. Rejected: `main` when
alone (two dispatch paths and the isolation guard to switch off); `-w` (placement, branch name and
behaviour under `--bg` all unrun, and the close-out convention would change); the session creating
its own (Baton could not state the worktree as a fact, and the first edit races the guard).

**Who removes it.** The session, at close-out, after its merge — `git worktree remove` and its
DerivedData, as M10–M13 did. The tick **prunes** any worktree left behind only when three things hold:
the milestone's `Status` reads `done`, no live session belongs to it, and the milestone's archived
artifact's `merged_as` is an ancestor of `main`. Never on `Status` alone: a `merge-failed` lane's
worktree is the work, and a close-out that wrote `done` a step early must not cost the only copy of
an unmerged milestone.

**The merge stays the session's**, and **the merging session builds `main` after its merge.** The
contract's close-out step (b) becomes: merge into `main`; if the merge fails, write `stopped` with
reason `merge-failed` and go no further; then run the project's standing check on `main` — the check
is for the combined tree, specifically for another lane's merge, which the worktree's own checks
cannot see (two lanes that each passed alone and do not pass together), not a repeat of the branch's
checks. If it fails, fix it on `main` — the session has the context and just made the change — and
if it cannot, write `stopped` with the new reason **`main-broken`** and the detail. The standing
check comes from the project's `CLAUDE.md` (Reclaim: D-030 authorises builds and tests), not from a
plan-file field: a universal Baton needs no `check` column, and a project with no standing check is,
by its own admission, not driveable unattended.

**What the tick does.** `main-broken` is the project-scope park already named by "Where an
escalation goes": no new dispatch for the project, in-flight lanes run on to their own close-outs
(each will meet the same check), notify now. It resolves exactly as `merge-failed` does — the build
failure happened before step (c), so the refresh and the real artifact are still owed —
by `baton answer <milestone> "main fixed; finish the close-out from step (c)"`, or by a person fixing
`main` at the Mac and ending with the same verb. When several lanes cascade into `main-broken` (the
others merged onto the broken tree and hit the same check), the first fix unparks the project and each
parked session is resumed with the same ruling in turn; their merges landed, so their close-outs just
continue. **A `merged_as` that fails verification on the next tick** stays what the contract says:
the artifact is rejected with its reason and the lane parked.

**Collision detection: no.** Baton detects neither shared-spine collisions before a merge nor their
aftermath; both detectors are the session's and both arrive as artifacts — a conflict at merge as
`merge-failed`, a combined tree that does not build as `main-broken`. A relay that reads no tree
cannot add discipline, and under the contract it never needs to read one.

#### 6. The cap, and Baton's numbers

**A global cap of two sessions in flight across all projects**, a property of the Mac (two Xcode
builds) rather than of a project, held as `cap: 2` in `~/.baton/config.json` and overridable by one
line. No per-model cap: Fable's scarcity is the allocation's job and the hold's, not the cap's. The
count includes every logged session with a live row and every parked lane holding a live prompt (it
still occupies a worktree and a process); stopped `asking` sessions do not count. When the cap bites,
the order is deterministic (§3 step 7). Reclaim has one eligible milestone today, so the first nights
are serial with the cap at two, and the parallel rules are exercised the first time two are eligible
rather than after a config change nobody remembers to make.

`~/.baton/config.json` is the home for every Baton-owned number already decided, each a default in
the tick overridable by one line: `cap` (2), `fableReserve` (80, §7), `stallMinutes` (30),
`longRunningHours` (6), `retryMinutes` (15), `caffeinateMaxHours` (6), and `models` (the accepted
aliases). The tick's interval is the plist's `StartInterval`, not a config value.

#### 7. Policy: quota, remote, the refused model

**Quota across a night — reactive by default.** Dispatch until a request is refused; the wait and
the per-model hold take it from there (a live `rate_limit` or `billing_error` wait on model X holds X;
every model once a second model is limited), and Opus lanes carry on through a Fable-only hold. A
Fable milestone is never silently downgraded, so a Fable limit means Fable waits; Fable never stops
for the night by clock, only by the hold. `used_percentage` and `resets_at` from the status feed
inform `status` and the wait's reset time and never decide a dispatch on their own: the windows
(`five_hour`, `seven_day`, `spend_limit`; peer session, from the embedded schema) are account-wide
with no per-model window, so they cannot see the Fable limit coming, and a session cut off at 100 %
costs one interrupted turn and a resume.

**Plus one optional number, because the pain point is real: `fableReserve`.** Baton at night and the
person by day draw on the same seven-day window, and M28 spent most of a week's Fable in one night.
While the freshest status file shows `seven_day.used_percentage` at or above `fableReserve` (default
80), the tick dispatches no new Fable milestone; Opus lanes and in-flight Fable sessions are
unaffected, and nothing about waits or resumes changes. Set to 100 it is off. Two honest limits: the
window is account-wide, so the reserve reads all use, not Fable's share — a proxy, good enough
because a Fable milestone is the large draw; and it cannot see the model-family limit ("your Fable
limit"), which no field exposes — that one is still the hold's. Staleness is fine for a coarse guard:
the number moves by whole percents over hours, and being an hour late costs one Fable session that
would have started anyway.

**`remote`: the two-step dispatch, verified.** `--remote-control` at dispatch discards the positional
prompt and starts the session idle (prototype, verified), so the flag as first designed is dead. The
prototype verified the alternative: start idle with `--remote-control`, `claude stop <id>`, then a
flagless `claude --bg --resume <uuid> "<prompt>"` restores `--remote-control` among the saved options
and delivers the work; the phone was pushed and answered twice. A mechanism seen working beats one
that might work in one command. One live item (39): that the `--settings` and `--model` given at the
idle start are restored by the flagless resume the same way — the per-session persistence
(`respawnFlags`) that restores `--model` is the reason to expect so; if not, pass `--settings` on the
resume and verify Remote Control survives a flagged resume. `remoteControlAtStartup` exists in the
binary (peer session: read as `remote_control_at_startup`, a persistent remote session forcing it
true) but whether `--settings` carries it, and whether a `--bg` session given a positional prompt
keeps the prompt under it, are unverified both ways — item 40, the simplification to try, not the
design to rest on: if both hold, `remote: yes` becomes one command and the two-step path is deleted.
**For remote sessions the row is not a park detector** (prototype caveat: `working/idle,
waitingFor: null` through a whole park), so their parks are artifact-borne only — `asking`,
`stopped`, the gate's `no-handover`; a live prompt is answered from the phone and never seen by the
tick, which is the point of the flag, and a prompt nobody answers surfaces after thirty minutes as a
stall, not a park. The one place the escalation table differs by dispatch kind.

**Which model runs which milestone.** Confirmed: the plan's `Model` and `Effort` columns are the
source; `--model` and `--effort` are the mechanism; the dispatch log records what ran and why it
differed; a finishing session that learns the plan is wrong edits the table at refresh time with the
reason as a decision entry. **A model the CLI refuses**: the peer session found no dispatch-time
validation — the session is created and its first request fails with StopFailure
`model_not_found`. The stops ticket filed that in the unrecoverable set (resume every fifteen
minutes, a plan edit picked up by the next retry), which was true for a `/login` and is false for a
plan edit, because a flagless resume restores the saved `--model`. So this row leaves the retry
table: **`model_not_found` is a lane escalation at once, no retry** — "M19's model fable was refused
by the account; edit Model in docs/MILESTONES.md and the next tick redispatches" — with no `answer`
step, because the plan file is the ruling: the next tick's re-read redispatches attempt n+1 with the
corrected model, and the log records attempt n as `model_not_found` and attempt n+1 with the model
that ran, which is the record the benchmark practice wants. `baton plan` validates every `Model`
cell before anything is dispatched, so only an account-refused model reaches this path.
`--fallback-model` is rejected by name: it is the silent downgrade the rack forbids, and it will look
attractive on a night Fable is refused at 2 a.m.

#### 8. Every point, and where it landed

| Point | Outcome |
|---|---|
| 1. One source for the graph | **Decided**: the table in `docs/MILESTONES.md` is the plan file; tokens only; parse failure refuses to dispatch; `baton plan`. |
| 2. What it holds per milestone | **Decided**: `ID`, `Depends on`, `Model`, `Effort`, `Remote`, `Status`; gates as a second table with `Cleared`; `isolate` dropped (every milestone isolated); `remote` by the verified two-step dispatch, `remoteControlAtStartup` unverified (item 40). |
| 3. Completion | **Decided**: the `Status` column (`done` by the close-out, `held` by a person), `merged_as` still verifying the transition; the sixteen built milestones marked once in the migration commit. |
| 4. The name | **Decided**: confirmed; `<project>` is the basename of the artifact's canonical `project`. |
| 5. `~/Documents` | **Decided**: Full Disk Access for `~/.baton/bin/sh`; the supervisor-attribution proof is item 38; the read is a per-tick self-check; setup facts recorded in the plan. |
| 6. The intersection | **Decided**: §3, eight steps; the plan wins on gates both ways, waits honoured, two escalations. |
| 7. Worktrees | **Decided**: Baton creates `../<Project>-M<nn>` from `main` for every dispatch, reuses on redispatch; the session removes; the tick prunes on a verified merge only; the slot line states worktree, branch and canonical checkout. |
| 8. The cap | **Decided**: global 2 in `~/.baton/config.json`, counting live rows and parked prompts; no per-model cap; the cap does not read `used_percentage`. |
| 9. Merges and the broken `main` | **Decided**: the session merges and builds `main`; `main-broken` joins the reason set, project scope, resolved by the merge-failed ruling; prune on verified merge; no collision detection by Baton. |
| 10. The `--settings` file | **Decided**: §4; mode on the flag; allow and deny, no `ask`; three hooks; disclaimer recorded as a setup fact. |
| 11. Quota across a night | **Decided**: reactive; Opus carries on through a Fable hold; `fableReserve` 80 on `seven_day` as the one predictive number, Fable only. |
| 12. Which model | **Decided**: plan is the source; `model_not_found` escalates at once and redispatches on edit; `--fallback-model` rejected. |
| Merged Question: lanes, per-model cap, worktree property as fields | **Decided**: none is a field (§1). |
| Merged Question: `--effort` in the routing | **Decided**: yes, an optional column. |
| Merged Question: collision detection by Baton | **Decided**: no (§5). |
| A per-milestone hours field | **Deferred**, unchanged: until a brief asks. |

#### 9. Evidence

- "Watching a dispatched session", resolution: the mode table (`auto` records `default`; `bypassPermissions` after the disclaimer, deny enforced); item 30 (rules travel through `--settings`, the mode does not); §10-3 and item 16 (a flagless resume restores `-n`, `--settings`, `--model`, `--permission-mode`; any flag forks a copy); §10-4 (worktree isolation gates Write/Edit only); item 19 and the addendum (statusLine `rate_limits`; Remote Control two-step and the row caveat); "What a launchd context cannot do" (the `~/Documents` table; `PATH`; no `LANG`); the Stop gate and `background_tasks[]`; run C's `daemon status` before dispatch. Fixtures: `.scratch/baton/prototype/settings-A.json`, `hooks/*.sh`, `com.baton.trial.plist`, `obs/launchd-run.txt`, `obs/launchd-run2.txt`, `obs/statusline.jsonl` (68 records carrying `rate_limits`).
- "What a project hands to Baton" §2 (the artifact's fields; `project` is the canonical checkout), §4 (rejection rules), §5 (the six clauses; Baton's side); "Relay or conductor" §4 (five inputs; caffeinate; launchd), §6 (verbs; the log's only writer), ADR 0001; "What stops a session, and what happens next" §0 (the tick's order), §2c (attempt, ladder), §7 (merge-failed ruling), §8 (the reason table), §9 (the dispatch hold); "Where an escalation goes" §2 (the settings file's two parts), §3 (the two deny classes), §5 (`remote: true`; the escalation table with the deferred detection row), §6 (scope).
- `.scratch/baton/research/prior-art.md` §1.13 (Symphony's `WORKFLOW.md`, hot reload, `max_concurrent_agents`), §2.3 "Dispatching more than one at once" (disjoint file lists; "when overlap is uncertain, serialize"; ~41K tokens per session, "start with 2 workers"; a serial merge step) and "Which model runs which milestone" (Superpowers' rules; front matter as carrier); `.scratch/baton/research/background-sessions.md` §2 (flags that combine with `--bg`; `--effort` persists), §9 (bg isolation skipped inside a linked worktree; `worktree.bgIsolation`; the supervisor's lifecycle).
- Peer session "Milestone Model Audit" (2026-09-11), from the binary [B], docs [D] and local files [L]: `remoteControlAtStartup` read as `remote_control_at_startup` with its precedence chain, `--settings` and `--bg` reach unknown [B/U]; background isolation instruction-based, `EnterWorktree` under `.claude/worktrees/`, `worktree.bgIsolation` ∈ `worktree`/`none`/`default`, env `CLAUDE_CODE_BG_ISOLATION` [B]; `--effort` ∈ `low, medium, high, xhigh, max` [L], persistence via `respawnFlags` [L/U]; no dispatch-time model validation, `model_not_found` at the first request, `--fallback-model` exists [B]; `rate_limits` windows exactly `five_hour`, `seven_day`, `spend_limit`, account-level, shared by concurrent sessions [B/D]; no per-machine session cap [U by absence].
- Reclaim: `docs/MILESTONES.md` (the table; `–` for no dependency; ranges; M14's row), `docs/STATUS.md` "Next action" (M14 alone; M19 held by D-026, "policy, not conflict"), `ORCHESTRATION.html` (the rack: 4 Fable, 11 Opus; the lanes; DerivedData by hash; "dependency-eligible is not the same as should-run"), `CLAUDE.md` ("Handing over": eligible set, conflict check, §5 lists proposed not exhaustive; "What a kickoff prompt contains"), `git worktree list` (none at present), `git log` (M29 closed out at `73c7edf`).
- Local: `~/.claude/settings.json` (`remoteControlAtStartup` unset); the 2.1.268 binary contains the string `remoteControlAtStartup setting — mirrors replBridgeAutoOn`.

#### 10. Unverified, and where each goes

All on "Watching a dispatched session" as items 36–44:

- (36) The Full Disk Access panel accepts `~/.baton/bin/sh`, and `cat` of a file and `git -C … rev-parse HEAD` under `~/Documents` then succeed from a launchd job run with it, while `/bin/sh` from the same job still fails.
- (37) Children of the granted shell (`git`, `jq`, `claude`) inherit the grant.
- (38) **The one that matters most**: a background service started by the tick (not already running from a Terminal context) runs sessions that can read `~/Documents` — a dispatched session `cat`s a file in the project. If not: grant the `claude` binary too, or never start the daemon from the tick.
- (39) `--settings` and `--model` given at an idle `--remote-control` start are restored by the flagless resume that delivers the prompt.
- (40) `remoteControlAtStartup: true` in a `--settings` file starts Remote Control on a `--bg` session, and such a session given a positional prompt keeps the prompt. Not yet mechanisable until proven; the two-step path is the design.
- (41) A session dispatched with `cwd` in a linked worktree (`../<Project>-M<nn>`) receives no worktree-isolation instruction and edits in place.
- (42) What a `permissions.ask` rule does under `bypassPermissions` — auto-allow or auto-deny. Until known, no `ask` rules.
- (43) `--effort` is restored by a flagless resume, as `--model` is.
- (44) A `--bg` dispatch naming a model the account refuses: the session is created, StopFailure fires at the first request with `error: model_not_found`, and the `api-error` artifact lands.

#### 11. Deferred, and to which ticket

- The events this ticket needs recorded — dispatch with model, effort, worktree, reused-at commit and prompt text; plan-overrode-disposition; the distant-`wait_for` notification; `main-broken` and its resolution; worktree prune; self-check failure; `model_not_found` and the redispatch on edit; the `fableReserve` hold, once; the status feed's file per session: **"The dispatch log"**.
- The migration commit in Reclaim (the four columns, the gates table, sixteen `done` marks, the contract's amended close-out and the plan file named in `CLAUDE.md`'s Documents table), `project.json`, `~/.baton/config.json`'s defaults, the plist with the granted shell, and the two setup facts: **"Baton's plan and its M01 prompt"**.
- Items 36–44: **"Watching a dispatched session"**.

### Amended by "The dispatch log" (2026-09-11)

Not reopened. One event kind no ticket had named, found by writing §3 step 8 as a derivation.

**A dispatch that never starts is `dispatch_failed`.** §3's step 8 has five ways to fail before a
session id exists — `git worktree add` fails, the `--settings` file cannot be composed, the brief's
prompt or its heading cannot be read on `main`, `claude --bg` prints no parseable
`backgrounded · <id>`, or the background service is down and does not start. Every other ending in
the taxonomy arrives as an artifact from a session; this one has no session, so it has no artifact
and no row, and without an event the tick retries the same broken dispatch every sixty seconds all
night and leaves no record of why nothing ran.

The event carries `stage` ∈ `worktree` | `settings` | `prompt` | `launch` | `service` and `detail`,
with `project`, `milestone` and `attempt` but **no `session`**. The rule: log every occurrence;
**the second consecutive failure for the same `(project, milestone)` escalates, lane scope** —
mirroring §3's crash rule, where two ticks separate a momentary supervisor restart from a real
failure, since a worktree that cannot be created will not fix itself in sixty seconds but a daemon
mid-restart will. The one exception is **`stage: service`**, which escalates **project** scope,
because §2 already named "service down" as a project-scope escalation in the fallback it weighed for
item 38: nothing can be dispatched for the project until the supervisor is up.

Two live items fill in what the event cannot yet state precisely — 46 (what `--bg --resume` prints
when it forks a copy, byte for byte under `LC_ALL`) and 47 (what a failed `claude --bg` prints, and
on which stream) — on "Watching a dispatched session".

Also recorded, since §3 step 8's log line listed the dispatch event's fields: it carries `name`,
`model`, `effort`, `remote`, `worktree`, `branch`, `worktree_reused`, `worktree_commit`, `settings`,
and — instead of the prompt text inline — `prompt_path` and `prompt_sha256`, the body living at
`~/.baton/prompts/<session>/<n>.txt`. A `Remote: yes` dispatch stays one event under one session id
across its three commands, as §7 requires.
