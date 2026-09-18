# Milestones

Eleven milestones, one per fresh session, in one lane; M07-b was split from M07 (D-081), M07-c added after it (D-082), and M07-d after that with M08 behind it (D-083). This file is Baton's **plan file**: the
table under "Order and dependencies" is what `baton plan Baton` parses and what the tick reads, so
its `ID`, `Depends on`, `Model`, `Effort`, `Remote` and `Status` cells hold tokens only (see
`CONTRACT.md` clause 2); the other columns are for people. The gates table follows it.

The build **bootstraps** (D-019). M01 is built by hand on `main` and produces the smallest thing
that can dispatch. From M02 on, each milestone is dispatched by the Baton that exists so far: by a
hand-run `baton dispatch Baton M<nn>` until M03 lands the tick, and by the tick after that. The
order is fixed by one rule: what a milestone needs in order to be dispatched is already built.
M01 to M03 are watched at the keyboard. M04 is the first milestone a tick dispatches, still
watched. **M06 is the first that runs unattended overnight.** Baton drives only itself and fixture
projects until every milestone is done; Reclaim comes after M08 (D-021).

Rules for every session (also in `CLAUDE.md`):
- Read `CLAUDE.md`, `CONTEXT.md`, the active brief, and the SPEC and ARCHITECTURE sections the brief names first; run `baton status` if the relay is installed.
- Implement only the active milestone; do not refactor unrelated areas or start the next one.
- The standing check is `sh tests/run.sh`; every check is reported as passed, failed or unrun with its output, and an unrun check is never reported as passed.
- If the milestone will not fit the session, stop at a coherent point, write the completion evidence, write a `stopped` artifact with reason `unfinished` and the split; do not mark it complete.
- If the spec must change, update `docs/SPEC.md` or `docs/ARCHITECTURE.md` and add a `docs/DECISIONS.md` entry before ending the session; take the next free D-number at the moment it is written.
- Close-out sequence, in order (`CONTRACT.md` clause 3): `/review-2` on the session's changes, then `/address` (local commits, no remote); completion evidence into the brief and the decision entry, committed on the branch; merge into `main`, then `sh tests/run.sh` on `main`; on `main`, refresh only listed milestones with neither an open lane nor an open park, established by baton status and the dispatch-log check in CONTRACT.md clause 3(c), while still naming every eligible milestone with its correct disposition, write `done` in this milestone's `Status` cell, leave the worktree in place, commit; run `sh install.sh` from the canonical checkout; write the handover artifact to `~/.baton/inbox/`; print it verbatim, last, in a `baton` fence. If anything lands after it, deal with that and print it again.
- Hand over every milestone the dependency column now makes eligible with a disposition each; in this plan that is one milestone at a time, and the artifact says so.
- Never use Python. No third-party packages. Never touch a target project's code; Reclaim is read, never written, and never dispatched before M08.

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status | User-visible result | Destroys anything? |
|---|---|---|---|---|---|---|---|---|
| M01 | Plan reader and hand-run dispatch | – | fable | | | done | `baton plan Baton` prints the graph; `baton dispatch Baton M02` creates the worktree, composes the settings file and the slot line, writes the prompt sidecar, runs `claude --bg` and logs the dispatch; the three hooks and the install script exist | No (creates a worktree and a branch) |
| M02 | The inbox and the log | M01 | opus | | | done | The inbox is consumed: provenance, `merged_as`, brief pointers, archive with the consumed-at suffix, rejection; the whole event table and the fifteen derivations exist with fixtures; `baton status` prints the view | No |
| M03 | The tick under launchd | M02 | opus | | | done | `baton tick` runs the eight steps under the lock and writes the marker; rows are reconciled (crash, stall, question, takeover, gap); the plist runs it every minute through the granted shell; caffeinate is armed | No (loads a LaunchAgent) |
| M04 | Waits, the ladder and continuations | M03 | opus | | | done | An API error is waited out and resumed flagless with the continue template; a `no-handover` climbs the ladder; a copy fork is recorded; the per-model hold bites | No |
| M05 | Escalations, answer, allow, takeover | M04 | opus | | | done | Every escalation class parks and reaches the Mac as a three-part message; `baton answer` delivers a ruling; `baton allow` widens in place; a takeover stands Baton off and hands back | No |
| M06 | The cap, the holds and the broken main | M05 | opus | | | done | Two lanes at once under the cap and the order; `fableReserve`; plan overrides; `main-broken` parks the project; leftover worktrees pruned on a verified merge (the prune was removed by M07, D-078); the first unattended night on Baton's own repo | Yes at the time (prunes a worktree, guarded three ways); no longer, since D-078 |
| M07 | Remote dispatch and acceptance | M06 | opus | | | done | `Remote: yes` dispatches as one command with Remote Control in its settings, and a question is answered from the phone; the acceptance evidence of Baton driving itself unattended | No |
| M07-b | A finished session: offline when idle, awake when messaged | M07 | opus | | | done | The three most recently active finished sessions answer a message in their own threads; an older one is taken offline once idle and reached by messaging the `Baton · wake` session from Claude.app or the phone (D-087); the takeover rule sees Remote Control messages (D-085); Claude.app grouping measured as not settable by a session (D-086) | No (takes idle processes of closed lanes offline) |
| M07-c | The Mac message: Claude's icon and a click that opens the session | M07-b | opus | | | done | A park or notification appears under Baton with Claude's icon, and clicking it opens the session in Claude.app | No |
| M07-d | A handover is acted on once | M07-c | opus | | | done | A handover delivered twice changes nothing: no older disposition back in force, no session a newer handover held back | No |
| M08 | Reclaim onboarding | M07-d | opus | | | held | Superseded by docs/v1.1/SCOPE.md M16, which carries its acceptance. Held permanently; the manual Reclaim migration it required is replaced by baton onboard. | No |
| M09 | Where sessions live, and how they surface | M17-b | opus | medium | | | New worktrees live under BATON_HOME; existing recorded session paths remain valid unless supported same-session relocation is proved; branches and dirty changes survive; sessions group under their project | No (creates worktrees; removes none) |
| M10 | Completion that proves the work | M17-b | opus | medium | | | Completion proves dispatch ancestry and in-scope changes, with a standing-check result recorded by Baton | No |
| M11 | baton onboard <path> | M09, M10 | opus | high | | | An unprepared or partly completed repository is registered and its existing plan adapted after one intent confirmation | No |
| M12 | Plan generation from a repository | M11 | opus | high | | | A repository without a usable plan generates conforming briefs and its first milestone dispatches and completes | No |
| M13 | Autonomous handoff, and more than one at a time | M12 | opus | high | | | Newly eligible work runs up to the cap, an independent pair overlaps, and effort follows declared Size | No |
| M14 | Budget-aware pacing | M13 | opus | medium | | | Budget exhaustion produces a visible pause and resume time; work resumes automatically when the window rolls | No |
| M15 | The escalation taxonomy | M12 | opus | high | | | Four dispositions, including HOST-EXPLAINED; solvable parks resolve without notification; replan preserves the goal | No |
| M15-b | Host-explained gaps and wake reconciliation | M15 | opus | high | | | Sleep-explained gaps stay recorded and visible without notifications; unexplained gaps notify; confirmed dead sessions use existing recovery | No |
| M15-c | The independent scope guard | M15-b | opus | high | | | Goal-only checks at plan adoption and close-out; drift always reaches a person | No |
| M16 | Cold live trial on Reclaim | M14, M15-c | opus | medium | | | Unregistered Reclaim completes at least three cold milestones with one intent confirmation and a live budget pause/resume | No |
| M17 | Dispatch preconditions before worktree creation | – | opus | high | | | Plan reports every eligible milestone's unmet dispatch preconditions in one pass; dispatch refuses them before creating a branch, worktree or settings, retaining the existing retry bound | No |
| M17-b | One rendering layer for Baton's output | M17 | opus | high | | | Every verb and Mac message uses lib/render.sh; terminal output is consistent, plain and matchable when piped and under NO_COLOR; behaviour and event-log format stay unchanged | No |

## Gates

| Gate | Holds | Cleared |
|---|---|---|

The gate is cleared by the D-number of the entry that records the migration commit in Reclaim
(D-021 says what that commit contains and that a person makes it, after M14 closes).

## Traceability: requirements → milestones

| Requirement family | Requirements | Milestones (primary in bold) |
|---|---|---|
| REQ-CONTRACT | 01–06 | **M01** (03, 06: the slot line, Baton's own CLAUDE.md), **M02** (04), M06 (05), M08 (01, 02 for Reclaim) |
| REQ-ARTIFACT | 01–09 | **M01** (09: the gate; 04: the api-error hook), **M02** (01–08) |
| REQ-TICK | 01–09 | M01 (08: the seams; 09: the installed relay), **M03** (01–07) |
| REQ-STOP | 01–14 | M03 (08, 09, 10, 14), **M04** (01–07, 13), **M05** (11, 14 hand-back), M06 (12), M07-b (14: Remote Control messages) |
| REQ-ESC | 01–11 | M02 (11: `status`), M03 (02: the Mac message; 10: the gap), **M05** (01, 03–07, 09), M06 (04 project scope), M07 (08) |
| REQ-PLAN | 01–08 | **M01** (01–05, 06 for Baton, 07, 08), M08 (06 for Reclaim) |
| REQ-DISPATCH | 01–10 | **M01** (03–06, 08, 10), M03 (03 prune reserved), **M06** (01, 02, 09), **M07** (03 worktrees kept, 07) |
| REQ-PERM | 01–05 | **M01** (01–04), M05 (02: `allow` as writer), M06 (05) |
| REQ-LOG | 01–08 | **M01** (01–03, 05, 08), **M02** (04, 06, 07) |
| REQ-VERB | 01–08 | **M01** (01, 05, 06), M02 (04), M03 (02), M05 (03, 07), M07-b (08) |
| REQ-SETUP | 01–08 | **M01** (05), **M03** (01, 04, 07, 08), M07 (06), M03 (02, 03: checked, recorded) |
| REQ-LIFE | 01–04 | **M07-b** (01–04) |

Every requirement in `docs/SPEC.md` §2 appears above; every milestone owns at least one in bold
except M07 and M08, which are acceptance and onboarding.

## What a person still does by hand, per milestone

| Milestone | The person's part |
|---|---|
| M01 | Starts the session by hand with the kickoff prompt; runs `sh install.sh` and the setup facts REQ-SETUP-01 to 03 after reading the merge; reads the printed handover. |
| M02 | `baton dispatch Baton M02`; watches through `claude agents` and `Claude.app`; on completion reads the handover and runs `sh install.sh`. |
| M03 | `baton dispatch Baton M03`; same; then loads the plist and confirms `baton status` prints a last tick. Runs the live proofs 36–38 the brief names. |
| M04 | The tick dispatches it. The person watches: a stopped session is still theirs to notice from `baton status` and `Claude.app`, because the ladder does not exist yet. Installs after the merge. |
| M05 | The tick dispatches it; the person watches for the same reason; installs after the merge. |
| M06 | The tick dispatches it, unattended. The person reads `baton status` in the morning and installs. |
| M07, M07-b, M07-c, M07-d, M08 | Unattended; each close-out installs its own merge (D-079). M08 waits on the gate, which the person clears after the migration commit. |
| M17 | The one hand-dispatch of V1.1: `baton dispatch Baton M17`, after the V1.1 briefs are on `main`. Nothing else in V1.1 is started by hand. |
| M17-b, M09 … M16 | Unattended; each close-out installs its own merge (D-079). The person answers a park when Baton asks, and nothing else. |

## Split rule

M15 was split before implementation on 2026-09-17: taxonomy/L33/replan stays in M15,
host-explained gaps and wake reconciliation move to M15-b, and the original natural remainder
(independent scope guard) moves to M15-c. M16 waits for M15-c and M14. No part is marked done;
this planning-only split produces no runtime handover or stopped artifact. Recheck the file-count
rule in each part against the actual interfaces before implementation and split further if needed.

A milestone is split before implementation if its checklist has more than about 15 items or
touches more than two counted `lib/` files beyond the ones it introduces. By the owner's amendment
(D-104), a file whose only change is substituting rendering calls for existing output calls does
not count: no change to what the verb decides or what any assertion verifies. A file whose
behaviour or decisions change still counts. This exception is only for rendering-call
substitution, not a general exemption for mechanical refactoring. The natural split point bounds
the session size of the exempt work. Recheck the count per part before implementation.

Briefs already marked with a
"natural split point" name where to stop if the session runs long; the remainder becomes `Mxx-b`
with its own brief written by the session that stops, a row added to the table above with
`Depends on` the milestone it came from, and a `stopped` artifact with reason `unfinished` naming
the split.

## Handoff template (required at the end of every session)

Appended to the milestone brief under "Completion evidence":

1. What changed (bullet list).
2. Files added / modified / deleted (paths).
3. Interfaces introduced or changed (names, with a pointer to ARCHITECTURE §10).
4. Checks run, with outcomes and attached output (`sh tests/run.sh`, the hook fixtures, any live proof).
5. Checks not run, and why.
6. Known limitations.
7. Deviations from the brief and the DECISIONS entry that records them.
8. Commit information (hash, message); the merge commit on `main`, which is the artifact's `merged_as`.
9. Working-tree state as observed (`git status --short` output), never assumed.
10. Exact next step and the next eligible milestone, matching the artifact's `eligible[]`.
