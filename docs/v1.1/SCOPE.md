# Baton V1.1 — scope

**Status:** proposed, 2026-09-14. Supersedes the V2 effort.
**Language:** POSIX shell, as V1. No rewrite.

## 1. Why this exists

V1 works. It orchestrates milestones inside Baton itself, and it does that well. It cannot do it in a
project that has not first been reshaped for it, and it cannot do it without a person in the loop.
V1.1 fixes exactly those two things and nothing else.

The V2 effort — a Swift core with a SQLite store across 44 milestones and 151,218 words of briefs —
is archived. It was a rewrite nobody asked for. Its `01-findings.md` is a genuine audit of V1 and is
the input to this scope; its decisions, spec and briefs are not.

## 2. Goal statement

> Baton runs a project's milestone chain overnight, unattended, in a repository it has never seen,
> on the Claude subscription, without leaving debris on the filesystem, and without asking anything
> it could answer itself.

Every milestone below serves that sentence. Anything that does not is out of scope.

## 3. Non-goals

Named so they cannot creep back in:

- Non-Git projects and application to arbitrary directories with outside writers. This was V2's
  hardest finding and it is not needed: Baton works on Git repositories it owns worktrees in.
- Swift, SQLite, typed record contracts, a wire protocol version.
- Preparation and review as managed LLM sessions.
- Non-macOS hosts, multiple users, multiple accounts.
- Adversarial containment of a hostile target repository. Targets are the owner's own projects.
- Cross-project dependency graphs. One project's chain at a time.

## 4. What stays exactly as it is

The tick, the inbox/archive/rejected mailbox, dispatch through `claude --bg`, the hooks
(stop-gate, stop-failure, statusline), the escalation and answer machinery, the notifier applet,
launchd scheduling, `install.sh`. V1.1 extends these; it replaces none of them.

**Subscription pricing is a hard constraint.** Dispatch shells out to the `claude` CLI, which is
authenticated against the Claude subscription. No milestone may introduce a direct API call, because
that silently moves execution onto metered pricing.

## 5. Data model additions

Additive only. No existing field changes meaning.

| Location | Field | Purpose |
|---|---|---|
| `projects/<key>/project.json` | `goal` | The confirmed intent statement. The scope guard's only input. |
| | `plan_format` | `native`, `adapted`, or `generated`. How the plan was obtained. |
| | `onboarded_at` | Provenance. |
| `projects/<key>/budget.json` | `window_start`, `sessions_used`, `tier` | Self-pacing against the plan allowance. |
| completion artifact | `baseline` | The dispatch commit. Makes ancestry meaningful. |
| | `changed_paths` | What the branch actually touched. |
| | `check_result` | The standing check's recorded outcome, not the session's claim. |

## 6. Milestones

Twelve, after M15 split into three and M17 split into correctness and rendering during brief authoring. Each
executable in one fresh session with no memory of the others. M17 is numbered last and runs
first, because it is the one milestone whose output conventions every other milestone inherits;
§7 is the authority on order.

### M09 — Where sessions live, and how they surface

Two symptoms, one root cause. `lib/dispatch.sh:32` builds worktrees at `../<Project>-<milestone>`,
which is why `~/Documents/Apps` holds ten of them. `claude_bg` is documented as "the one command,
with the worktree as cwd" — and Claude Code groups sessions in the desktop sidebar by project
directory. Each worktree is a distinct directory that is not a registered project, so every
dispatched session lands under **Other**, mixed with every other project's. Both problems come from
the worktree being both the working directory and an ad-hoc sibling path.

Create new worktrees at `$BATON_HOME/worktrees/<project>/<milestone>`. Preserve existing recorded
session paths, branches and dirty changes; reuse must verify repository and branch identity.

**Do not add a prune.** D-078 is active and deleted `worktree_prune` on purpose: *"A finished
session is worth going back to — to ask what it decided, or to continue by hand — and it cannot be
resumed once its working directory is gone."* Its evidence is measured, not theoretical: on
2026-09-12 the service restart for the 2.1.270 upgrade settled M04's and M05's idle sessions with
`(crashed): working directory no longer exists`, and M06's went the same way a minute after its own
close-out removed `../Baton-M06`. Claude.app then shows each as not connected and a message to it
does not send.

The managed root prevents new sibling clutter in `~/Documents/Apps`. **The legacy siblings move too**
— superseding this section's earlier requirement that a session-bearing worktree be relocated only
after a proof, under D-137, which is the new decision entry the paragraph below asks for. Every
`<checkout>-<milestone>` sibling migrates to the managed root with `git worktree move`, which deletes
nothing: branches, commits, uncommitted changes and ignored build products all survive.

The proof is still attempted, and it is attempted first. M09 is the first work that can run the
fixture, because it is a dispatched session and may start a disposable one. It tries any supported
relocation the installed CLI offers — established by observing `claude --help` and the job and
session records, **never** by editing them, because Claude's private databases stay untouched — and
then a symlink left at the legacy absolute path, whose cost is that ten symlinks still occupy ten
entries in `~/Documents/Apps`. If a mechanism is proved, the migration is lossless. If none is, the
migration happens anyway at the cost D-137 accepts: hand-resume of ten finished, merged milestones.
Transcripts, usage statistics and prompt history are unaffected either way — measured, not assumed.
If disk pressure ever becomes real — a Swift target with DerivedData per worktree — add an explicit
`baton prune` a person runs deliberately, never an automatic one, and record why D-078 no longer
holds for deletion as well.

**Done when:** new worktrees use the managed root; every legacy sibling has moved there with its
branch and dirty changes intact, or is named in the completion evidence as one of the two residuals
that cannot move (M09's own worktree, and a sibling lane still live); the fixture's result is
recorded either way; each migrated worktree's legacy absolute path is recorded beside its milestone,
so its transcript directory is still findable by slug. A dispatched session appears in the desktop
sidebar grouped under its project rather than under Other.

### M10 — Completion that proves the work

L13: `merged_as` verification proves only that a hex value resolves to a commit ancestral to `main`.
The findings record that this repository's own first commit passes that check. An autonomous chain
that trusts a session's completion claim compounds errors silently, so this is the foundation
everything else stands on.

Bind completion to the dispatch baseline: the commit must descend from the baseline recorded at
dispatch, the branch must have touched paths within the milestone's declared scope, and the standing
check result must be recorded by Baton rather than asserted by the session.

**F07 comes before F09 in this milestone's lead-in.** `inbox_consume` moves an artifact through
`archive_move` before appending `consumed`, so a tick killed between them leaves an archived file no
event claims, with no advancement and a suppressed crash path. Recovery for an archived artifact
whose consumed receipt is missing is established **first**; only then does F09 settle the standing
check's command, working directory, pinned revision, deadline and result-to-revision binding. The
order is the point: adding more completion-result semantics on top of a receipt that can go missing
puts the new evidence in the same hole as the old.

**Done when:** a completion artifact naming an unrelated ancestral commit is rejected; one whose
branch changed nothing in scope is rejected; the check result in the record was produced by Baton;
and an archived artifact whose `consumed` event is missing is reconciled on a later tick rather than
stranded.

### M11 — `baton onboard <path>`

L1: registration presupposes a migrated plan, conforming briefs, close-out instructions, a
permissions file and a starting artifact. `install.sh:48–76` already generates `project.json` and
`permissions.json` for the project it runs in — this generalises that to an arbitrary path.

Register the project, derive its permission list from the detected toolchain, and parse an existing
plan tolerantly. L1's recorded symptom is a Reclaim parse that failed on a missing Model column;
column presence must not be load-bearing. M08 also records registration writes that a dispatched
session's own deny rules forbid — onboarding runs from the tick, outside those rules.

**Status vocabulary.** The native plan has exactly three Status tokens: `done`, `held`, or blank.
It cannot express retirement, so a retired milestone such as M08 must borrow `held`, with its
supersession recorded in a prose column. Onboarding will encounter richer status vocabularies;
M11's tolerant parse must map them without making retired work runnable or treating it as completed.

This is where the **intent confirmation** happens, and it is the only routine human touchpoint in
V1.1: Baton states what it thinks the project is and what done looks like, in about three lines, and
takes a yes or no. It is not a plan review. It is the check that catches "this is a rewrite, and I
did not want a rewrite" in ten seconds.

**The confirmation produces a record, and the record carries constraints.** F10 is settled here, not
carried to M15-c as a reminder: the same confirmation that takes the yes writes a **confirmed intent
record** holding the existing `goal` *and* explicit constraints and non-goals. For Baton that record
names the controller's POSIX-shell boundary and excludes a Swift/SQLite replacement. The independent
guard (M15-c) receives that record and the work being evaluated — never the plan author's rationale,
which is the thing it exists to be independent of. This adds no second plan-approval gate: one
confirmation, one record, a wider record. The regression it owes is one goal paired with two
proposals — a permitted extension and the forbidden controller replacement — which the constraint
record must distinguish and a goal-only check cannot.

**F11 settles with F10, here.** Existing registrations must migrate into the new intent
representation without resetting progress. `install.sh:131-133` writes `{path, plan}` **only when
`projects/<key>/project.json` does not already exist**, so reinstalling over a registration writes
nothing and can never supply a field that registration lacks; Baton's own registration is exactly
that case. Migration is M11's, not the installer's.

**F03 is settled here too, before M11's first judgment session.** Request identity, terminal
outcomes, restart behaviour and admission-slot ownership for planning and judgment sessions belong
to the first special session, not to a later guard that inherits them undefined. A guard session
holding an admission slot while its own result is awaited can deadlock the cap, and D-130 now bears
on this directly: `do_unresolved` counts a launch that could not be proved to have started nothing,
so a special session's slot is counted conservatively and a role with no terminal outcome holds that
count open.

**M4 moves here** (V1 review, minor): there is no version pin, fingerprint or canary anywhere and
`claude --version` is never run, so a prose-in-JSON match such as `(.row.waitingFor // "") == "input
needed"` would cost the `question` park silently if its casing changed. No present-day CLI
incompatibility is verified — the concern is the missing detector as this interface widens, so the
checks belong to the shapes the new session roles actually consume rather than to a general sweep.

**Done when:** an unprepared repository is registered and its plan parses, without a human editing
anything in that repository first; the confirmation writes an intent record carrying goal,
constraints and non-goals; an existing registration migrates into it without losing progress; and
the session-role lifecycle is written down before the first judgment session runs.

### M12 — Plan generation from a repository

When a target has no usable plan, dispatch a Claude Code session that reads the repository and
writes one, plus conforming briefs, using the skeleton `01-findings.md` already reverse-engineered
from the existing briefs. The confirmed goal from M11 is the input. There is no approval gate: the
goal was already confirmed, and re-approving its consequences is the review that gets rubber-stamped.

**Done when:** a repository with no `docs/MILESTONES.md` is onboarded and produces a plan whose
first milestone dispatches and completes.

### M13 — Autonomous handoff, and more than one at a time

Close-out of N dispatches everything newly eligible, up to the concurrency cap, with no human gate.
Parallelism falls out of this rather than being a separate feature: the plan is already a dependency
graph, and independent milestones have no reason to run serially. Fourteen milestones at an hour
each is fourteen hours serial and about five at three-wide — the difference between "ran overnight"
and "did not finish".

Dispatch also picks the reasoning effort from the brief's declared Size, so a two-hour mechanical
milestone does not run at the same effort as a hard design one. This is smaller than it sounds:
`claude_bg <worktree> <name> <model> <effort> <settings> <prompt>` already takes model and effort as
parameters, so this feeds an existing seam rather than building one.

**Done when:** a chain of three milestones with one independent pair runs start to finish with no
human action, and the independent pair overlaps in time.

### M14 — Budget-aware pacing

An autonomous runner that does not know its own allowance will exhaust the 5-hour window at 2am and
sit stalled until morning, looking like it is working. Track the window and sessions used, pace
against the tier, stop cleanly before exhaustion, and resume when the window rolls.

**Done when:** a simulated exhausted window produces a clean pause and a recorded resume time rather
than a failed dispatch, and the pause is visible in `baton status`.

### M15, M15-b, M15-c — The escalation taxonomy, host-explained gaps, and the scope guard

Authoring split this into three: **M15** the taxonomy, the L33 classes and replan; **M15-b**
host-explained gaps and wake reconciliation; **M15-c** the independent scope guard.

`escalate.sh`, `answer.sh` and `notify.sh` are 1,102 lines — about a fifth of Baton — and every line
exists to ask a question. Hands-free is not deleting them; it is classifying each escalation class
as **AI-resolvable** (ambiguity in a brief, a judgment call between two valid readings → route to a
model), **human-required** (a credential, an access grant, an external fact), or **replan** (the
plan was wrong → re-plan rather than ask). L33 records parks with no usable operator resolution;
those are the first candidates.

A **fourth disposition** the original three missed: **host-explained — record it, do not notify.**
The `Baton · gap` notification is the case that proves it. `derive_gap` reports a marker older than
two tick intervals whenever a lane was open through it, and `gap_check` keys it on the marker so one
outage notifies once. Both are correct. But the cause is almost always the laptop sleeping, and
REQ-SETUP-07 already states that Baton cannot prevent it: *"`caffeinate -i` does not prevent
lid-close sleep, and timers stretch by any sleep. Baton cannot lift this."* So the monitor fires,
once per sleep, on a condition its own specification says is unfixable and that carries no action
for anyone. Seven of them arrived on 2026-09-17 alone. A notification that cannot be acted on
teaches its reader to dismiss the channel, which is the one outcome a system with real escalations
cannot afford.

The fix is not to silence the check but to make the gap explain itself: ask the host whether it was
asleep across the interval, and if it was, write the event and stay quiet. An unexplained gap —
ticks stopped with a lane open and the host reporting no sleep — is a genuine stall and must still
reach a person, because that is launchd unloaded, a stuck lock or a crashing tick.

Two corrections from the brief-authoring session, which checked rather than took this on trust:

**Sleep is not continuous.** The measured intervals were mostly sleep *interrupted by short dark
wakes*, not one unbroken stretch. So the suppression rule cannot ask "was the host asleep the whole
time" — the answer is no, and a naive check would notify on every gap anyway. It has to decide
whether sleep accounts for *enough* of the interval to explain the missing ticks. That threshold is
the hard part of M15-b and the place an implementation will go wrong.

**Sleep does not kill sessions.** D-078's crash records establish restart and missing-directory
failures, not sleep-caused deaths, so the claim that a lane open across a sleep probably holds a
dead session was wrong. Wake reconciliation is still worth having — confirming liveness is cheap
and the answer is the one thing a person would actually want on waking — but it is justified by
cheapness, not by an expected failure.

**Suppression alone would hide the gap, not quieten it.** `baton status` shows only an *active* gap,
so a silently recorded one becomes invisible. Persistent historical visibility is therefore a
requirement of M15-b, not a property already held.

The **scope guard** is the one escalation that must always reach a person. At plan time and at each
close-out, an independent check receives only the stored `goal` and the work just done, and answers
whether the work still serves it. This exists because the most expensive error in this project's
history — a 151,000-word plan to rewrite a working tool in a language nobody asked for — was
produced by an AI, reviewed by an AI, and passed. Review inherits the premise. Only a check holding
the goal and nothing else can see that class of drift.

**Done when:** every escalation class carries a disposition; at least the L33 classes resolve without
a notification; a sleep-explained gap records an event and sends no notification while an unexplained
one still does; a lane open across a sleep is reconciled on wake; and a deliberately drifted
milestone trips the guard.

This milestone was already the largest in the set and this addition may push it past one session.
Apply the split rule before continuing rather than running long.

### M16 — Cold live trial on Reclaim

Onboard Reclaim from scratch with no manual migration commit, and run at least three milestones
unattended across a window boundary. Each dispatched session is cold — no memory of this plan, no
memory of its siblings.

**Done when:** Reclaim goes from unregistered to three milestones completed with no human action
beyond the single intent confirmation, and the run survives at least one pause and resume.

### M17 — Dispatch preconditions before worktree creation

Baton's output defect has two parts: it discovers knowable dispatch failures after creating a
worktree, and each verb prints its own lines its own way. M17 owns the first; M17-b owns the
rendering system. They run in that order because both change `lib/plan.sh`.

**Already built.** Commit `7dd3ee6` gave `prompt_from_brief` three Baton-authored failure messages:
a brief absent everywhere, written on disk but not on `main`, and on `main` without a complete
fenced block at the requested heading. `dispatch_one` also refuses a worktree without its own
readable brief. The three new scenarios are `dispatch-brief-absent`, `dispatch-brief-uncommitted`
and `dispatch-worktree-missing-brief`. These changes prevent a bad session; their checks still
follow `worktree_ensure` and settings creation. Extend them rather than rewrite working code.

**In scope.** `baton plan <project>` already validates every Model cell. It grows a read-only
report of every eligible milestone's unmet dispatch preconditions in one pass: the committed
brief and complete fenced kickoff prompt, its replaceable slot paragraph, every literal `docs/…`
reference in that prompt present on `main`, an existing milestone branch containing the brief's
latest change on `main`, an existing worktree's readable brief, and permissions with deny rules.
Each report names the affected milestone, what Baton needed, what it found and a concrete repair
command. The shared check also runs in `dispatch_one` **before** `worktree_ensure`, so refusal
creates no branch, worktree, settings, sidecar or session. Existing failure records remain.

Two existing libraries change behaviour: `lib/plan.sh` and `lib/dispatch.sh`. A new read-only
helper may share their checks. `dispatch_try` deliberately keeps its retry-then-escalate bound;
first-occurrence escalation is a classification question for M15, not part of M17. D-098's
unification with the inbox's brief-pointer checker remains deferred, including its archived
strings. There is no archive migration and no change to `lib/inbox.sh` for M17.

**Done when:** a fixture plan with multiple eligible milestones and multiple defects reports
all inspectable defects and repairs without dispatch; the same preconditions refuse before
creation; the existing retry bound, plan format, on-main rule and unrelated admission decisions
remain intact; the standing check and the added no-creation fixtures pass. D-101/D-102 record
no-pause and working-tree plan authority as findings; neither is fixed by this milestone.

### M17-b — One rendering layer for Baton's output

Each verb prints its own lines its own way, so status, plan and dispatch do not agree on how a
milestone, state, lane or path is written, and there is nowhere to make them agree. Introduce
`lib/render.sh` and convert **every** person-facing verb and Mac-message printing site: status,
plan, dispatch, answer, allow, wake, usage and the tick. The inventory in the brief distinguishes
those sites from machine-return JSON, session prompts, archived text and the event log, whose
formats do not change. The layer has reusable heading, row/table, lane, state, milestone, path,
timestamp, hint and failure primitives derived from that inventory, not one wrapper per call site.

Invoke `/terminal-ui-design` in the implementing session **before rendering code**, with the step
in its copy-ready startup order and actual invocation evidence required by §8. The brief's first
check inspects user-scope skill reachability under the composed dispatch settings; authoring
found the installed skill readable, with no skill restriction in the launch flags or Baton deny
rules. Recheck the effective configuration directory at implementation. If unreachable, carry
the substantive guidance inline and record the inspected limitation under the next free D-number;
do not claim the skill ran or widen permissions.

Use colour only on a capable TTY, honor `NO_COLOR`, provide ASCII fallback, and keep pipes plain
and grep-matchable. Below 60 columns retain all identifiers, paths and commands with a compact
layout. The tick's stdout/stderr are captured by fixtures and searched by people; no new terminal
escape sequences go into those streams when redirected. Failures explain Baton's need, the
observed condition and the repair. The useful three-case messages from `7dd3ee6` already do this.
Other raw tool stderr remains diagnostic data for the existing bounded log field, not the
terminal's explanation: dispatch detail is capped at 2,000 bytes and marked when truncated,
not kept in full. No new classifier or change to what any verb decides belongs in the renderer.

The inventory spans sixteen existing library files plus `bin/baton`. Under the owner's D-104
amendment, only rendering-call substitutions with unchanged decisions and assertion meaning are
exempt from the two-file count. The new renderer does not count; behavioural changes still do.
Size is Large, about 5–7 hours, high effort. Convert status and plan first, then the remaining
whole files. The **natural split point** is status and plan complete with the full suite green;
subsequent stopping points are whole-file boundaries with the suite green. If the session must
stop, it writes completion evidence, `stopped`/`unfinished` and a bounded M17-c brief and plan
entry under the existing split mechanism. Reconcile scope, graph and handover explicitly when
splitting. A partial conversion is a temporary state for the chain to finish, never an end state;
the unsplit milestone is not done until every person-facing printing site uses the layer.

**Done when:** every verb and Mac message uses the same layer; plain/TTY/NO_COLOR/narrow/ASCII
behaviour has evidence; no raw tool stderr substitutes for Baton's explanation; every behaviour
assertion still verifies the same contract and the full suite passes. Presentation expectations
are reviewed and updated where necessary, never the checks weakened to fit a redesign.

**Non-goals for both parts.** No packages, new dependencies, new verbs, language rewrite, plan
format change, on-main rule change or event-log line-format change. POSIX shell with `set -eu`.
M17 changes precondition reporting and refusal timing only; M17-b changes presentation only.
D-098's unification and archive-text changes remain deferred. There is no permanent rendering
deferral and no pre-authored M17-c through M17-i.

## 7. Order and dependencies

    M17 ─→ M17-b ─┬─→ M09 ─┐
                  │        ├─→ M11 ─→ M12 ─┬─→ M13 ─→ M14 ─────────────┐
                  └─→ M10 ─┘               │                           ├─→ M16
                                           └─→ M15 ─→ M15-b ─→ M15-c ──┘

M17 is the single root. M17-b depends on M17; M09 and M10 depend on M17-b and are independent
of each other. The cap remains two. The M15 family runs alongside M13/M14 after M12;
M16 waits for M14 and M15-c. No new gate is needed.

**Kickoff instructions.** The only milestone a person hand-dispatches is M17:

```sh
BATON_HOME=/Users/danny/.baton baton dispatch Baton M17
```

M17's close-out lists M17-b with disposition `run` and refreshes its prompt with the actual
precondition interface. M17-b's close-out lists **both M09 and M10 as `run`**: both are
plan-eligible once M17-b is done. On main it refreshes **both copy-ready prompts with render.sh's
actual interface**, source/init order and output policy. They carry that interface onward through
the normal handover chain. No milestone after M17 is started by hand.

At every close-out re-read current Status cells, dependencies and gates. Name every direct
successor and all other eligible work: an open gate takes precedence (`held`, with `held_by`),
otherwise unfinished dependencies mean `wait` with all their IDs in `wait_for`, otherwise `run`.
Both M09 and M10 name M11; both M14 and M15-c name M16, without assuming which sibling finishes
first. Refresh a listed prompt on main before writing the artifact only if its milestone has
neither an open lane nor an open park. Run `baton status` to identify lanes and parks, and check
the dispatch log as `CONTRACT.md` clause 3(c) specifies;
absence from status does not prove closure. Still name every eligible milestone with its correct
disposition and brief pointer, including those whose refresh is withheld. The M17/M17-b refreshes
above have the same no-open-lane-or-park condition. If a formal M17-b split
exists, its remainder must be named and the actual revised graph used; never silently drop it.

Marking a milestone done without its handover can leave the newly eligible successor unlisted
and parked as `omitted`. There is also an existing live-state exception to the intended single
hand-dispatch startup: editing the plan can resolve an omitted park and let the tick admit M17
before a hand-dispatch (D-102). During authoring, pause the launchd agent before changing the live
plan, verify the marker stays fixed with `baton status`, and restore it only after publishing;
restoration can then admit M17 automatically. This operational fact is recorded, not fixed here.

## 8. Acceptance for V1.1 as a whole

1. An unprepared repository is onboarded and runs, with exactly one human interaction: the intent
   confirmation.
2. New Baton artifacts stay under `$BATON_HOME` and the target repository, and the legacy sibling
   worktrees have moved there too, with branches and dirty changes intact — superseding the earlier
   grandfathering criterion under D-137. The only paths left outside are the two residuals M09 names
   and cannot move: its own worktree, and a sibling lane still live. Dispatched sessions
   group under their project in the desktop sidebar rather than under Other.
3. A completion claim that did not do the work is rejected.
4. A run pauses on budget and resumes without help.
5. Two independent milestones run concurrently.
6. A milestone that drifts from the stated goal trips the scope guard and reaches a person. The
   guard is given M11's confirmed intent record — goal, constraints and non-goals — and the work,
   never the plan author's rationale; a goal-only check does not meet this item, because one goal
   admits both a permitted extension and a forbidden controller replacement (F10, settled in M11).
7. Execution stays on subscription pricing throughout.
8. M17 reports every eligible milestone's unmet dispatch preconditions together and refuses them
   before branch/worktree/settings creation, retaining the existing retry bound. M17-b gives all
   verbs and Mac messages one rendering layer, plain and matchable when piped and under NO_COLOR;
   Baton's explanation replaces raw tool stderr on the terminal, with unchanged event-log format
   and behaviour assertions. A partial conversion is not final acceptance.

## 9. What happens to M08

M08 — Reclaim onboarding — is **superseded, not rescheduled**. It exists only because onboarding was
manual: its scope is a hand-migrated plan, hand-written registration files and a hand-written seed
artifact, all behind a `Reclaim migrated` gate that a person clears. M11 and M12 automate every one
of those steps, and M16 is the same goal reached without a person.

Moving it later would mean building the manual path in order to test the automatic one. Retire the
row, drop the gate, and let M16 carry its acceptance. Its one requirement that was not otherwise
covered — joining a project that is already partway through its plan — is now part of M11.

## 10. Deferred, with reasons

From `01-findings.md`, deliberately not in V1.1: L6 and L42 (host portability and install
versioning — one machine), L11 and L50 (containment and secrecy — the owner's own projects), L12
(remote reachability — it works), L34, L35 and L41 (lock, hung command, history growth — real, but
fix them when they bite), and the durability findings behind them. These are recorded so a later
scope can pick them up knowingly rather than rediscovering them.

D-098's unification of the dispatch and inbox brief-on-main checks is deferred, including any
change to the detail persisted with rejected handover entries. It is not in M17 or M17-b;
their work preserves the existing inbox checker and archive strings. First-occurrence escalation
for precondition failures is assigned to M15's classification scope, not implemented by M17.
