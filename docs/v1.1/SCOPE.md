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

Eleven, after M15 split into three during brief authoring and M17 was added on 2026-09-17. Each
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

Move the worktree root to `$BATON_HOME/worktrees/<project>/<milestone>`, migrate the existing ones
with their branches intact, and add a prune.

**Do not add a prune.** D-078 is active and deleted `worktree_prune` on purpose: *"A finished
session is worth going back to — to ask what it decided, or to continue by hand — and it cannot be
resumed once its working directory is gone."* Its evidence is measured, not theoretical: on
2026-09-12 the service restart for the 2.1.270 upgrade settled M04's and M05's idle sessions with
`(crashed): working directory no longer exists`, and M06's went the same way a minute after its own
close-out removed `../Baton-M06`. Claude.app then shows each as not connected and a message to it
does not send.

Relocation alone solves the stated problem. The complaint is Finder clutter in `~/Documents/Apps`;
moving the root to `$BATON_HOME` removes it from view entirely, and worktrees of a shell repository
cost almost nothing. Overturning D-078 would need a new decision entry and a better reason than disk
tidiness. If disk pressure ever becomes real — a Swift target with DerivedData per worktree — add an
explicit `baton prune` a person runs deliberately, never an automatic one, and record why D-078 no
longer holds.

**Done when:** a dispatch creates no path outside `$BATON_HOME`; existing worktrees are relocated
with their branches intact and their sessions still resumable;
and a dispatched session appears in the desktop sidebar grouped under its project rather than under
Other.

### M10 — Completion that proves the work

L13: `merged_as` verification proves only that a hex value resolves to a commit ancestral to `main`.
The findings record that this repository's own first commit passes that check. An autonomous chain
that trusts a session's completion claim compounds errors silently, so this is the foundation
everything else stands on.

Bind completion to the dispatch baseline: the commit must descend from the baseline recorded at
dispatch, the branch must have touched paths within the milestone's declared scope, and the standing
check result must be recorded by Baton rather than asserted by the session.

**Done when:** a completion artifact naming an unrelated ancestral commit is rejected; one whose
branch changed nothing in scope is rejected; the check result in the record was produced by Baton.

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

**Done when:** an unprepared repository is registered and its plan parses, without a human editing
anything in that repository first.

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

### M17 — What Baton says, and how it reads

Baton's output is its whole interface, and it fails in two ways that turn out to be one concern.

It says the wrong things at the wrong time. `dispatch_failed` prints the underlying tool's stderr:
`fatal: path 'docs/milestones/M09.md' exists on disk, but not in 'main'` is git's sentence, not
Baton's, and it names no fix. It arrives one milestone at a time, after the worktree has already been
created, for a condition that was knowable before anything ran.

Under the tick it is worse than cosmetic. `dispatch_try` retries once and escalates `dispatch-failed`
on the second consecutive failure — a bound that is right for a transient cause, and wrong for a
permanent one, which now gets two attempts. The first attempt leaves a branch created from `main`
before the brief was committed. A later dispatch reuses that branch, `prompt_from_brief` succeeds
from `main` because the brief has since landed there, and the session opens in a worktree where its
own brief does not exist — and its prompt's first instruction is to read that file in full. The loud
failure becomes a silent one. This is not hypothetical: it is the state branch `m09` was left in on
2026-09-17, after one hand dispatch.

And it says them in raw shell text. Nothing in the relay has a rendering layer: each verb prints its
own lines its own way, so `status`, `plan` and the dispatch messages do not agree on how a milestone,
a state, a lane or a path is written, and there is nowhere to make them agree.

**In scope.**

1. **One rendering layer.** `lib/render.sh`, designed with the `/terminal-ui-design` skill — which
   the implementing session invokes before it writes any rendering code, not only the authoring
   session that wrote this brief; the brief's copy-ready prompt carries that instruction, and §8
   takes evidence that it happened. Whether a Baton-dispatched session can reach a user-scope skill
   under the composed settings is unverified and is the brief's first check: if it cannot, the
   guidance is carried into the brief instead, and that is a finding worth recording. The layer has
   named primitives for the shapes the relay actually prints: a heading, a lane, a state, a
   milestone, a path, a timestamp, a table, a hint, a failure. Every verb — `status`, `plan`,
   `dispatch`, `answer`, `allow`, `wake` and the usage text — prints through it. POSIX shell only, no
   packages, no new dependency.
2. **Plain when it is not a terminal.** Colour and box drawing only on a TTY, honouring `NO_COLOR`,
   degrading to ASCII where the terminal cannot do better. The tick's output is read by `grep` and by
   the tests, so piped output stays plain and its existing lines stay matchable; `sh tests/run.sh` is
   the contract for that and is not weakened to fit the redesign.
3. **Preconditions stated once, up front.** `baton plan <project>` already validates every Model
   cell. It grows to check every dispatch precondition, for every eligible milestone, in one pass,
   before any dispatch is attempted: the brief present on `main` at the heading a dispatch reads;
   every `docs/…` path that brief's own prompt names present on `main`; an existing branch for the
   milestone containing that brief at the commit `main` now holds; `permissions.json` present with
   deny rules. One report, naming each affected milestone, what is missing, and the single command
   that fixes it. A reused worktree whose branch predates the brief's commit is the same defect
   arriving silently rather than loudly, and is covered by the same check.
4. **A precondition is checked before the first attempt, not after the second.** `dispatch_try` is
   right to bound retries and right to escalate `dispatch-failed` on the second consecutive failure;
   what is wrong is that a knowable, permanent precondition is attempted at all, and that the attempt
   leaves a branch behind that will silently lack the brief. A precondition failure is recognised
   before `worktree_ensure` runs, escalates on its first occurrence rather than its second, and
   creates nothing. Transient causes keep the existing retry and the existing bound unchanged.
5. **Baton's words, not the tool's.** A failure on the terminal says what Baton needed, what it found
   instead, and the one thing to do about it. The underlying stderr stays in the log, where it is
   already kept in full.

**Not in scope.** No new verbs, no change to what any verb decides, no change to the plan format, and
no change to the on-`main` rule itself — reading a brief from `main` is what keeps a person's
half-finished edit out of a running session, and what guarantees the brief exists inside the worktree
the session is handed. This milestone changes what Baton says and when it says it, not what it does.

**Done when:** `baton plan Baton` against a checkout whose briefs are uncommitted names every
affected milestone and its fix in one pass, and no dispatch is attempted; every verb prints through
one layer, plain and matchable when piped and under `NO_COLOR`, with `sh tests/run.sh` passing
unchanged; a precondition failure under the tick escalates on its first occurrence and leaves no
branch or worktree behind; and no raw tool stderr reaches the terminal.

**Why it is the root.** It has no dependencies, and M09 and M10 depend on it — not for machinery, but
because their output is the first output written after the layer exists, and a convention adopted at
the root propagates down the chain by the close-out rule that carries interfaces forward into each
successor's prompt. Retrofitting it after nine merged branches would mean editing nine milestones'
output by hand.

## 7. Order and dependencies

    M17 ─┬─→ M09 ─┐
         │        ├─→ M11 ─→ M12 ─┬─→ M13 ─→ M14 ─────────────┐
         └─→ M10 ─┘               │                           ├─→ M16
                                  └─→ M15 ─→ M15-b ─→ M15-c ──┘

M17 is the single root. M09 and M10 depend on it and are independent of each other, so they run
together under the cap of two once M17 lands. The M15 family runs in parallel with M13 and M14 once
M12 lands. M16 waits on M14 and M15-c.

M09 and M10 were roots in the first draft of this scope, which meant two hand-dispatches and, for
whichever root the operator did not reach first, a park. Depending them on M17 is not bookkeeping:
their output is the first written after the rendering layer exists, and it makes the graph single-
rooted, which is what reduces kickoff to one command.

**Kickoff instructions.** One hand-dispatch, ever:

```sh
BATON_HOME=/Users/danny/.baton baton dispatch Baton M17
```

M17 is the only milestone with no predecessor handover to name it, so it is the only one a person
starts. Everything after it is admitted by the tick. M17's close-out lists M09 and M10 as its direct
successors with disposition `run` — both are plan-eligible the moment M17 is marked done — and
refreshes both of their prompts on `main` with the rendering layer's actual interface, by the
standing close-out rule that carries interfaces forward. From there each close-out lists every direct
successor and derives its disposition from the plan as it reads then: an open gate means `held` with
`held_by`; otherwise any dependency not done means `wait` with those IDs in `wait_for`; otherwise
`run`. Both M09 and M10 name M11, and both M14 and M15 name M16, regardless of which sibling finishes
first. No new gate is needed.

If M17's session dies before writing its handover, M09 and M10 are plan-eligible and unlisted, and
each parks as `omitted` on the next tick. That is the intended failure: it stops and says so, rather
than starting work against conventions that do not exist yet.

## 8. Acceptance for V1.1 as a whole

1. An unprepared repository is onboarded and runs, with exactly one human interaction: the intent
   confirmation.
2. No Baton artifact appears outside `$BATON_HOME` and the target repository, and dispatched
   sessions group under their project in the desktop sidebar rather than under Other.
3. A completion claim that did not do the work is rejected.
4. A run pauses on budget and resumes without help.
5. Two independent milestones run concurrently.
6. A milestone that drifts from the stated goal trips the scope guard and reaches a person.
7. Execution stays on subscription pricing throughout.
8. Baton's terminal output is Baton's own: one rendering layer, no raw tool stderr on the
   terminal, and an unmet dispatch precondition stated once for every affected milestone
   before any dispatch is attempted.

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
