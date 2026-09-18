# The project contract

The short list of things a target project's `CLAUDE.md` makes its sessions do so that Baton can
drive the project. Six clauses. A target project cites this file by path; nothing in it names a
project. Reclaim is the first implementer and Baton itself the second. The clauses were settled by
the ticket "What a project hands to Baton" and amended by "Dispatching more than one at once"; the
requirements that restate them are `REQ-CONTRACT-01` to `REQ-CONTRACT-06` in `docs/SPEC.md`.

1. **Briefs.** One brief per milestone at a path `CLAUDE.md` names (`docs/milestones/M<nn>.md`),
   holding the milestone's completion evidence under a heading `## Completion evidence` and its
   whole kickoff prompt as a single code block under a heading `## Copy-ready session prompt`, in
   the seven-part anatomy. Part 2 is exactly one paragraph, verbatim:
   `WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.` — the slot line, which
   Baton replaces whole at dispatch. The project's standing parallel-run rules (worktree, stage by
   name, never `git add -A`) live in part 5, where they apply whether or not anything is in flight;
   the refusal to start the next milestone lives in part 7.

2. **Plan file.** `CLAUDE.md` names it. It is the milestone table in the project's plan document
   (`docs/MILESTONES.md`), found by its `ID` header cell, plus a gates table found by its `Gate`
   header cell. Columns are read by name — `ID`, `Depends on`, `Model`, `Effort`, `Remote`,
   `Status` — and cells hold tokens, never prose: ids and ranges in `Depends on` (`M05, M06`;
   `M01–M13`; `–` for none), a model alias in `Model`, `low|medium|high|xhigh|max` or blank in
   `Effort`, `yes` or blank in `Remote`, `done`, `held` or blank in `Status`. The gates table is
   `| Gate | Holds | Cleared |`, `Cleared` blank or the D-number of the decision entry that cleared
   it. A gate is cleared only by a person's edit, committed with that decision entry. A cell that
   does not parse stops dispatch for the project. One source for the graph, never two.

3. **Close-out order**, after the milestone's own checks, its review and its fixes:
   (a) completion evidence into the brief, the decision entry, commit on the branch;
   (b) merge into `main` — if the merge fails, write a `stopped` artifact with reason `merge-failed`
   and go no further; then run the project's standing check on `main`, the combined tree; if it
   fails, fix it on `main`, and if that cannot be done, write `stopped` with reason `main-broken`;
   (c) on `main`: refresh the prompt only of a listed milestone with neither an open lane nor an open park (parts 1 and
   3–7; part 4 additively, by thread; part 2 stays verbatim). Run `baton status` to identify
   in-flight lanes and open parks: an `in flight` line names a running milestone and a `parked`
   line names a park that has not been resolved. Withhold the refresh of either milestone.
   Then check the dispatch log (`$BATON_HOME/log.jsonl`, normally
   `~/.baton/log.jsonl`) for each listed milestone: its newest `dispatch` opens a lane unless a
   later `consumed` with outcome `complete` names the same project, milestone and attempt.
   Use log order, not timestamps. A lane missing from status can still be open while its process
   is gone; withhold its refresh too. If the log cannot be read, do not assume the lane is closed.
   Still name every eligible milestone with its correct disposition and brief pointer under
   clause 6; withholding a refresh changes neither eligibility nor disposition nor the artifact.
   Write `done` in this milestone's `Status` cell, correct the plan file if
   the session learned it is wrong with the reason as a decision entry, remove the build products
   from the session's worktree and leave the worktree in place — it is the working directory that
   lets the session be resumed later — and commit;
   (d) write the handover artifact;
   (e) print it verbatim, last, in a fenced block whose info-string is `baton`; if anything lands
   after it, deal with that and print it again.

4. **The artifact.** `~/.baton/inbox/<milestone>-<session>.json`, written as `.tmp` then renamed;
   `session` from `CLAUDE_CODE_SESSION_ID`; `project` is the canonical checkout, never a worktree;
   `baton: 1`. No prompt text, no model.

5. **Outcomes.** A question for the person is asked in the session itself, with the session's own
   question tool, so the session keeps running: Remote Control carries it to Claude.app and the phone,
   the answer arrives in place, and Baton parks the lane as `question` meanwhile. A session that cannot
   finish still writes the artifact before ending its turn:
   `asking` with the question, options, recommendation and an absolute context pointer inside its
   own checkout; `stopped` with a reason from the fixed set — `unfinished`, `blocked` (with
   `blocked_by`), `merge-failed`, `main-broken`, `other` — and a detail. `no-handover` and
   `api-error` are reserved for artifacts Baton's own hooks write.

6. **Every eligible milestone listed.** A `complete` handover lists every milestone the plan makes
   eligible, each with a disposition — `run`, `wait` for named milestones, or `held` by a named
   gate — and a pointer to its brief, so that an omission can only be a miss.

## Baton's side, recorded beside the contract

Baton creates the milestone worktree from `main`, dispatches with it as `cwd` and never removes it;
injects the Stop gate, the StopFailure hook and the status-feed command at dispatch, the first two
standing down once the session's `complete` handover is archived; verifies `merged_as` before a
`complete` handover is acted on; computes eligibility from the plan file, dispatches only the
intersection with the handover's dispositions, honours the plan's gates even when a handover omits
them, and escalates disagreement in both directions by milestone name; composes part 2 at dispatch
from its log; archives a handover when it has acted on it; and records what actually ran, and why
it differed from the plan, in the dispatch log.

## The artifact, by example

```json
{
  "baton": 1,
  "project": "/Users/danny/Documents/Apps/Reclaim",
  "milestone": "M13",
  "session": "d8ab9333-db88-48e4-9ff7-b166dc1549ce",
  "outcome": "complete",
  "merged_as": "b76c86d",
  "written_at": "2026-09-10T23:02:17Z",
  "eligible": [
    { "milestone": "M28", "brief": { "path": "docs/milestones/M28.md", "heading": "Copy-ready session prompt" },
      "disposition": "run" },
    { "milestone": "M29", "brief": { "path": "docs/milestones/M29.md", "heading": "Copy-ready session prompt" },
      "disposition": "wait", "wait_for": ["M28"] },
    { "milestone": "M19", "brief": { "path": "docs/milestones/M19.md", "heading": "Copy-ready session prompt" },
      "disposition": "held", "held_by": "v0.1 ships" }
  ]
}
```

`outcome: asking` replaces `merged_as` and `eligible` with `question` (verbatim), `options` and
`recommendation` where the session has them, and `context` (`path`, absolute, and `heading`).
`outcome: stopped` replaces them with `reason` and `detail`, plus `blocked_by` for `blocked`.
