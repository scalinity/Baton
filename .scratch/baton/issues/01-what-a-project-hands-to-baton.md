Title: What a project hands to Baton
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: —

## Question

In what form does a finished session tell Baton what to run next, and what must that form
carry? This is the root decision: "Dispatching more than one at once" and "Which model runs
which milestone" both wait on it.

Today the handover is prose plus one code block per eligible milestone, printed last
(`/Users/danny/Documents/Apps/Reclaim/CLAUDE.md`, "Handing over at the end of a milestone",
step 3). The prompt's seven parts are fixed, but the judgement of *which may run at once and
which must wait* is a sentence, not a field. The current example of the prose form is the
session prompt in `/Users/danny/Documents/Apps/Reclaim/docs/milestones/M14.md`.

Options:

- **Scrape.** Read the final assistant record of the transcript
  (`~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`, `type: assistant`,
  `message.stop_reason: end_turn`, a `text` block) and take its fenced code blocks. The
  prompts are recoverable; "these two run together, that one waits for M28" is not.
- **Artifact.** Require the session to write a machine-readable handover — a file such as
  `docs/handover/next.json` in the target project, or a fenced block with a known
  info-string — carrying, per entry: milestone id, the prompt (or the path of the brief that
  holds it), model, parallel group, whether a worktree is wanted, and what it is blocked
  until. The close-out already writes `docs/STATUS.md` and the brief's Completion evidence
  in the same breath; one more file costs the session nothing.
- **Both.** The artifact is authoritative; the prose handover stays for the human.

Decide as well: where the convention lives. If it is step 7 of the target project's
kickoff-prompt close-out, then Baton has a *project contract* — the small set of things any
project's `CLAUDE.md` must make its sessions do — and Reclaim is the first project to
implement it. Name the contract's fields here. Whether the model per milestone comes from
this artifact or from a plan file is the later ticket's question; decide here only whether
the artifact carries a `model` field at all.

Recommendation attached, not decided: both. A scrape is a hypothesis about how a model
formats its last message, and it breaks on the night nobody is watching.

## Comments

### Resolution — 2026-09-11

**Decided: both, with the artifact authoritative.** A finished session writes one machine-readable
handover artifact to Baton's inbox and then prints that same file verbatim as its last message. The
artifact is the only thing Baton acts on; the printed block is a guarded fallback, never a second
source. The convention is a project contract (§5) that Reclaim implements first.

#### 1. The form

- The session writes `~/.baton/inbox/<milestone>-<session>.json`, atomically (`.tmp`, then rename),
  after its merge into main has succeeded, and prints the file's content last, in a fenced block whose
  info-string is `baton`, under Reclaim's reprint rule (D-034: if anything lands after it, deal with
  that and print it again).
- The printed block cannot diverge from the file because it *is* the file. If the file is missing and
  the Stop hook's `last_assistant_message` holds a `baton` fence that parses and names the same session,
  Baton writes it into the inbox itself and records the recovery.
- A Stop gate is injected by Baton into every session it dispatches (a `hooks.Stop` block passed with
  `--settings`, carrying the project path and milestone as arguments). It gates on the file, never on
  text: if `~/.baton/inbox/<milestone>-<session_id>.json` exists it exits 0; on the first stop without
  it, it blocks with the reason "write the handover artifact"; on the next stop (`stop_hook_active`
  true) it writes a `stopped` artifact with reason `no-handover` itself and lets go. Hand-started
  sessions carry no gate; the contract in `CLAUDE.md` alone makes them write the artifact.
- Why not a scrape: of the twelve completed Reclaim transcripts, three (M02, M05, M11) end with a
  message that is not the handover, two (M07, M10) carry the wait judgement in prose outside the
  fences, and the transcript entry format is documented as internal and version-dependent. Why not a
  marked block alone: it inherits the displacement failure and exists only while the session's last
  message is the handover.

#### 2. The fields

Keys are named for a reader. No prompt text (prompts live in the briefs) and no model (the allocation
lives with the plan; "Dispatching more than one at once" fixes the shape).

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

- Top level, always: `baton` (schema version, `1`), `project` (the canonical checkout, never a
  worktree), `milestone` (the milestone the session worked, whatever its outcome), `session` (the
  value of `CLAUDE_CODE_SESSION_ID`), `outcome` (`complete` | `asking` | `stopped`), `written_at`
  (ISO 8601 UTC, for people; never used for freshness).
- `outcome: complete` adds `merged_as` (the commit on main that carries the milestone; the fact Baton
  verifies rather than trusts) and `eligible[]`: one entry for **every** milestone the plan makes
  eligible, each with `milestone`, `brief` (`path` and `heading`, resolved on main), and a
  `disposition`: `run`, `wait` with `wait_for` (milestone ids, the session's conflict check), or
  `held` with `held_by` (a gate name from the plan file). Listing every eligible milestone is what
  makes an omission unambiguous: it can only be a miss.
- `outcome: asking` adds `question` (verbatim, as it would have been printed), `options` and
  `recommendation` when the session has them (so a phone can answer with one character and Baton can
  resume verbatim), and `context` (`path` and `heading`; the path is absolute, inside the session's own
  checkout, because asking happens before the merge).
- `outcome: stopped` adds `reason` from a fixed set and `detail`: `unfinished` (stopped at a coherent
  point, split proposed, per the split rule), `blocked` (with `blocked_by`: a precondition the session
  cannot clear, such as missing upstream evidence or a build broken by a file it does not own),
  `merge-failed`, `no-handover` (written only by the Stop gate), `other` (detail required). `api-error`
  is reserved for an artifact written by Baton's StopFailure hook; "What stops a session, and what
  happens next" decides each reason's handling. Each reason is a different Baton action.
- Dropped on purpose: a `worktree` flag (a dispatch-time decision, or a plan-file property for spikes),
  a `model` field, any per-entry validity field (a pointer is checked by finding its heading on main),
  a "runs alone" flag (implied: an entry is `run` and every other entry waits for it).

#### 3. Where it lives, and versioning

- Baton's own state, outside every target repository: `~/.baton/inbox/` (flat; the file carries the
  project), `~/.baton/archive/` (a handover moves there when Baton has acted on it), and
  `~/.baton/rejected/` (a file Baton refused, kept with the reason recorded beside it, and escalated —
  never skipped). One fixed path for every project's `CLAUDE.md` to name.
- Not versioned in git. The archive is half the run record; Baton's dispatch log is the other half
  ("The dispatch log", graduated from the fog by this ticket).
- Why not in the repo: sessions build in sibling worktrees (`git worktree add ../Reclaim-M19 -b m19`)
  and merge at close-out, so a file inside the checkout reaches main only with the merge; a shared
  `next.json` conflicts on every parallel close-out (M11 was handed over by three sessions); and an
  artifact from a session that stopped short would become project history it does not deserve.

#### 4. Fresh and whole

- **Whole**: the session writes `<name>.json.tmp` and renames it into place (atomic on one
  filesystem); Baton ignores `.tmp` files and anything that fails to parse or lacks a required field.
- **Fresh**: provenance is the id match — for a dispatched session the file's `session` must equal the
  Stop hook's `session_id`. Not-yet-acted-on is a property of Baton's record and the archive, not of
  the file; nothing in the inbox is stale by age, and `written_at` is never consulted. No ordinal, no
  checksum.
- **Rejected**, with the reason, and escalated: no transcript on disk for `session` (found by glob
  `~/.claude/projects/*/<session>.jsonl`, never by a path derived from the project); `project` not a git
  checkout; for `complete`, `merged_as` not an ancestor of main. A `brief` pointer whose path or
  heading is missing on main rejects that one entry, not the file. A missing `context` pointer on an
  `asking` artifact is a warning. A `.tmp` whose session has no live process (no row with a `pid` for
  that `sessionId` in `claude agents --json`) is an orphan and is rejected too.

#### 5. Where the convention lives: the project contract

The convention is a step in the target project's `CLAUDE.md` close-out, so Baton has a **project
contract**: the short list of things any project's `CLAUDE.md` must make its sessions do. Reclaim is
its first implementer. The clauses:

1. **Briefs.** One brief per milestone at a path `CLAUDE.md` names (Reclaim:
   `docs/milestones/M<nn>.md`), holding the milestone's completion evidence and its whole kickoff
   prompt as a single code block under a heading the artifact can point at (Reclaim: "Copy-ready
   session prompt"), in the seven-part anatomy. Part 2 is exactly one paragraph, verbatim:
   `WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.` — the slot line. The
   project's standing parallel-run rules (worktree, `-derivedDataPath`, stage by name, never
   `git add -A`) live in part 5, where they apply whether or not anything is in flight; the refusal to
   start the next milestone lives in part 7.
2. **Plan file.** `CLAUDE.md` names it. It holds every milestone, its dependencies, and the gates with
   each gate's cleared state. A gate is cleared only by a person's edit, committed with the decision
   entry that explains it. One source for the graph, never two.
3. **Close-out order**, after the milestone's own checks, its review and its fixes: (a) completion
   evidence into the brief, STATUS, the DECISIONS entry, commit on the branch; (b) merge into main —
   if the merge fails, write a `stopped` artifact with reason `merge-failed` and go no further; (c) on
   main: refresh the prompt of **every** brief the handover will list (parts 1 and 3–7; part 4
   additively, by thread), correct the plan file if the session learned it is wrong, with the reason as
   a decision entry, and commit; (d) write the handover artifact; (e) print it verbatim, last, in a
   `baton` fence, under the reprint rule.
4. **The artifact.** `~/.baton/inbox/<milestone>-<session>.json`, written as `.tmp` then renamed;
   `session` from `CLAUDE_CODE_SESSION_ID`; `project` is the canonical checkout, never a worktree;
   `baton: 1`. No prompt text, no model.
5. **Outcomes.** A session that cannot finish still writes the artifact before ending its turn:
   `asking` with the question, options, recommendation and an absolute context pointer; `stopped` with
   a reason from the fixed set and a detail.
6. **Every eligible milestone listed**, each with a disposition — `run`, `wait` for named milestones,
   or `held` by a named gate — so that an omission can only be a miss.

Baton's side, recorded beside the contract: it injects the Stop gate at dispatch; it verifies
`merged_as`; it computes dependency-eligibility from the plan file, dispatches only the intersection
with the session's advice, honours the plan's gates even when a handover omits them, and escalates
disagreement in both directions by milestone name (a named milestone the plan rejects; a plan-eligible
milestone the session omitted) — resolution is an edit to the plan or the brief, after which Baton
re-reads; it composes part 2 at dispatch from its dispatch log, replacing the slot paragraph whole with
the milestones in flight, their worktrees and their briefs — never their paths; it archives a handover
when it has acted on it; and it records what actually ran, and why it differed from the plan, in the
dispatch log.

**What changes in `/Users/danny/Documents/Apps/Reclaim/CLAUDE.md`** (described here; nothing in
Reclaim is edited by this ticket):

- "Handing over at the end of a milestone", step 3: the copy-ready prompts are no longer printed;
  the session refreshes each listed successor's brief on main, writes the artifact, and prints it
  verbatim last. Steps 1 and 2 (eligible set, conflict check) stay and become the `eligible[]`
  entries and their dispositions.
- "What a kickoff prompt contains": part 2 becomes the slot line; part 5 absorbs the standing
  parallel-run rules; part 7's close-out becomes the order in clause 3.
- The "Documents" table gains the plan file once "Dispatching more than one at once"
  names it.
- `docs/MILESTONES.md`, "Rules for every session": the close-out bullet (D-018, D-034) changes the
  same way. `ORCHESTRATION.html`, stage 5 ("Handoff, then the next prompt"): the wording.
- A `docs/DECISIONS.md` entry at the next free number (D-109 at the time of writing) recording the
  handover artifact, the slot line and the plan file, superseding the printed-prompt part of D-018 and
  amending D-034 and D-035.
- The open briefs' prompts (15 of 29 have empty completion evidence): the slot line and the new
  close-out. Progressive refresh is the migration, not a clause: each close-out refreshes the briefs it
  lists, and the first milestone Baton dispatches must have a conforming brief before dispatch —
  "Baton's plan and its M01 prompt" decides that starting milestone and who refreshes its brief.

#### Evidence

Transcripts under `/Users/danny/.claude/projects/-Users-danny-Documents-Apps-Reclaim/` (written by
Claude Code 2.1.266–2.1.267; read-only), the last `assistant` record with `stop_reason: "end_turn"`
and a `text` block, by 0-based record index:

| Session | Id | Index | Fences | Ends with fence | Handed over |
|---|---|---|---|---|---|
| M01 | 6584124c | 820 | 2 | yes | M03, M04 (one block) |
| M02 | 903041c2 | 2144 | 0 | — ("Ready.") | displaced |
| M03 | 5eb95ab6 | 1714 | 4 | yes | two prompts |
| M05 | d7f54877 | 2360 | 2 | no | deferred to another session |
| M06 | 83323db1 | 1577 | 4 | yes | M07, M09 |
| M07 | edacfaf3 | 2295 | 4 | no (a heading follows) | M10, M08 |
| M08 | a6b01f05 | 1853 | 4 | yes | M11, M13 |
| M09 | 6d0f52bf | 2234 | 4 | yes | M10, M11 |
| M10 | d22fddda | 2470 | 6 | no ("**M14 waits** …") | M12, M11, M13 |
| M11 | 38865727 | 2694 | 0 | — (a later Q&A) | displaced |
| M12 | bae89688 | 2145 | 2 | yes | M19 |
| M13 | d8ab9333 | 2016 | 2 | yes | M19 |

- The code block arrives intact inside one `text` block; in M13 the final turn is two records (a
  `thinking`-only record, then the `text` record), both `stop_reason: "end_turn"`.
- After the handover in M10, M11 and M13: `queue-operation`, `system/turn_duration`,
  `system/agents_killed`, a `user` record with `promptSource: "system"` and `origin.kind:
  "task-notification"`, and a `user` record "[Request interrupted by user]" — so the last `user`
  record is not a human prompt.
- Printed prompt versus stored prompt: the M19 prompt printed by M13 has 12 paragraphs, 4 verbatim in
  `docs/milestones/M19.md`'s 6; by M12, 11 paragraphs, 4 verbatim; the two printed M19 prompts share 5
  of 12 paragraphs. The M12 prompt printed by M10: 11 paragraphs, 2 verbatim in `M12.md`'s 6. The
  variable content is part 2 ("M11 and M12 are running in parallel in their own worktrees … `git
  worktree add ../Reclaim-M19 -b m19`") and part 4's evidence.
- Worktrees: `git worktree list` in Reclaim shows `/Users/danny/Documents/Apps/Reclaim-M28 [m28]`;
  the M10–M13 transcripts contain `git worktree add`, `git merge m12 --no-edit` /
  `git merge --ff-only m13` / `git merge m11 --no-ff`, and `git worktree remove`; every record's `cwd`
  stays `/Users/danny/Documents/Apps/Reclaim` (plus `…/ReclaimCore`), and `~/.claude/projects/` holds
  one Reclaim directory — so a session's transcript slug is the checkout it was started in, not the
  worktree it builds in.
- Session id inside a session: `CLAUDE_CODE_SESSION_ID=4510a2ed-…` present in this session's shell
  environment (interactive, 2.1.268). Presence inside a `--bg` session: unverified.
- Hooks (`.scratch/baton/research/hooks.md`, quoting https://code.claude.com/docs/en/hooks):
  `transcript_path` is a common field on every event, "written asynchronously and may lag the
  in-memory conversation"; Stop receives `stop_hook_active` and `last_assistant_message`;
  `{"decision":"block","reason":…}` keeps the session going with the reason as its next instruction,
  capped at 8 consecutive blocks; `--settings <file-or-json>` is in `claude --help` for 2.1.268 and
  https://code.claude.com/docs/en/cli-reference, and hooks merge across settings levels. That a
  `--settings` hooks block reaches a `--bg` session is established indirectly
  (https://code.claude.com/docs/en/agent-view: "Configuration flags from the original launch carry
  through", `PermissionRequest`/`PreToolUse` hook output surfaced on background rows) — unverified
  live; "Watching a dispatched session" verifies it, with a worktree-local settings file as the
  fallback.
- Transcript format: https://code.claude.com/docs/en/sessions ("The entry format is internal to
  Claude Code and changes between versions"), via `.scratch/baton/research/background-sessions.md` §7.
- Reclaim conventions: `CLAUDE.md` ("Handing over at the end of a milestone" steps 1–3; "What a
  kickoff prompt contains" parts 2 and 7); `docs/MILESTONES.md` (close-out bullet; D-018, D-034,
  D-035); `docs/DECISIONS.md` D-018, D-026, D-034, D-035 (last entry D-108); `docs/STATUS.md` "Next
  action" (M28 beside M19: dependency-eligible, held by D-026 — "policy, not conflict"); 29 briefs, 28
  with "## Copy-ready session prompt" (M27 lacks it), 14 with completion evidence;
  `ORCHESTRATION.html` "The rack" holds the model per milestone as HTML only.

#### Deferred, and to which ticket

- The plan file's format and location, whether model and effort ride along, how completion is known
  for milestones that predate Baton, and how a gate's cleared state is written:
  "Dispatching more than one at once".
- How Baton composes part 2, chooses and names worktrees, caps concurrency and handles merges:
  "Dispatching more than one at once".
- Who answers an `asking` artifact and how the answer is delivered: "Relay or conductor" and "Where
  an escalation goes".
- The handling per `stopped` reason and the `api-error` artifact: "What stops a session, and what
  happens next".
- Live verification of the injected Stop gate, of `CLAUDE_CODE_SESSION_ID` inside `--bg`, and of the
  worktree-local fallback: "Watching a dispatched session".
- The dispatch log's events, key and recovery test: "The dispatch log".
- The starting milestone, the brief-refresh migration, and where the contract's text lives in Baton's
  own repository: "Baton's plan and its M01 prompt".

#### Unverified

- Whether the file-writing tool a session uses writes whole files in one operation (moot under the
  rename rule).
- The name of the target project's main branch is assumed `main` (true for Reclaim); a project with
  another name would state it in `CLAUDE.md`.

### Observed against by "Watching a dispatched session" (2026-09-11)

Not reopened. The injected Stop gate works exactly as specified — it fires inside a `--bg` session
from a `--settings` file, and its `{"decision":"block","reason":…}` reaches the model as a **`user`
record prefixed `Stop hook feedback:`**. The session then wrote `…json.tmp` and renamed it into
place, and the next Stop fire saw the file. `CLAUDE_CODE_SESSION_ID` equals the row's `sessionId`.

One correction. **The gate must stand down while a subagent is still running.** A session ended a
turn only because it was waiting on a subagent; the gate blocked it, and the session complied by
writing a handover artifact recording the milestone as `"status": "in-progress"` with step one
still `"pending"` — and never corrected it. The gate manufactured a false handover. The Stop
payload carries `background_tasks[]` naming the running subagent, so the gate can tell "waiting on
a subagent" from "done" and should let the stop through when it is non-empty.

Also: worktree isolation gates the Write/Edit tools, not Bash — a session wrote into the shared
checkout with a Bash heredoc without ever moving into a worktree.

### Amended by "Dispatching more than one at once" (2026-09-11)

Not reopened; still six clauses. Three clauses gain wording that the plan file's shape fixed:

- **Clause 2, the plan file**, is the milestone table in the project's plan document (Reclaim:
  `docs/MILESTONES.md`), with the gates as a second table. Cells hold tokens: ids and ranges in
  `Depends on`, a model alias in `Model`, an effort level or blank in `Effort`, `yes` or blank in
  `Remote`, and `done`, `held` or blank in `Status`; the gates table is `Gate`, `Holds`, `Cleared`
  (a D-number). A cell that does not parse stops dispatch for the project.
- **Clause 3, the close-out order**, step (b): merge into `main`; if the merge fails, `stopped` with
  `merge-failed` and go no further; then run the project's standing check on `main` (the combined
  tree); if it fails, fix it on `main`, and if that cannot be done, `stopped` with reason
  `main-broken`. Step (c) also writes `done` in the milestone's `Status` cell, in the same commit as
  the refreshed briefs. Step (c) also removes the session's worktree (`../<Project>-M<nn>`) and its
  DerivedData once the merge is on `main`.
- **Clause 5, outcomes**: the `stopped` reason set gains `main-broken`.

Baton's side: it creates the worktree and branch before dispatch and dispatches with the worktree
as `cwd`; the slot line it composes names the worktree, the branch and the canonical checkout.
