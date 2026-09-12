# Project contract, version 2

A project implements this contract to run under Baton. Version 1 artifacts are historical input;
they are never silently promoted into version 2 authority. See `docs/MIGRATION.md`.
Architectural changes follow `docs/GOVERNANCE.md`. For the already-running M03 workstream,
`docs/M03-RECONCILIATION.md` defines the compatibility handoff; it does not retroactively invent a
contract-2 run or require the session to restart. This protocol is required for the combined candidate.
The same obligations apply to all target projects and later milestones. M03-specific coordination
does not restrict their scope. Future protocol extensions must follow governance and a declared
migration; this document does not silently introduce new required message fields.

## 1. Project snapshot and authority

The canonical checkout has a `main` branch and a committed milestone table at the path registered
in `project.json`. Baton reads one commit for the plan, prompt and initial worktree base. Uncommitted
edits are drafts and never affect dispatch. A prepared run records that revision and reserves its lane.

The milestone table has `ID`, `Depends on`, `Model`, `Effort`, `Remote`, `Status` columns. IDs are
`M01` or `M01-b`; dependencies are IDs/ranges or `–`; models resolve through the configured aliases;
effort is blank or low/medium/high/xhigh/max; Remote is blank or yes; Status is blank/done/held.
The gates table has `Gate`, `Holds`, `Cleared`. All referenced IDs exist and the dependency graph is
acyclic. Duplicate milestone or gate names are invalid. A cleared gate names a decision such as
D-044 and also requires the same token in the person's `project.json.gateApprovals[gate]`.
A session may propose a gate change; it never grants that authorization itself. This is a trusted
local operating contract, not protection against a hostile process running as the same user.

The graph is the scheduling authority. Handover artifacts contain no `eligible`, `wait_for`, model,
or prompt fields. Durable dependency changes belong in the committed plan. A stopped session can
report a blocker; future scheduling must validate it against the current graph rather than silently
creating a second dependency graph.

## 2. Brief and prompt

Each milestone has `docs/milestones/<ID>.md` with `## Completion evidence` and
`## Copy-ready session prompt`. The latter contains one fenced block. The block includes exactly
one paragraph beginning `WHAT ELSE IS IN FLIGHT.`; Baton substitutes current run context there.
Stable rules live in `CLAUDE.md` and this contract, not in recursively rewritten successor prompts.
A predecessor records newly learned facts in its completion evidence; successors read those facts.

## 3. Run and ownership

A run has a unique ID assigned before any launch, one project/milestone, an attempt, a recovery
episode, a plan revision, a worktree/branch, an exact prompt and a runtime version. An uncertain
launch remains reserved until reconciled. Never launch a replacement merely because a provider
observation failed. Retries preserve the recovery episode across attempt numbers.

Sessions work only in their recorded linked worktree. Stage named paths. Do not modify the canonical
checkout, run another milestone, clear human gates, remove worktrees, or alter Baton's journal,
processing files, settings or releases. An existing worktree must belong to the right repository
and branch, be clean and contain the dispatch revision before it can be reused.

A person claims a run with `baton claim <run>` before manual control and releases it explicitly with
`baton release <run>`. Release acknowledges one immutable typed-record UUID, not a string such as
“continue”. New or unreadable typed input prevents automatic integration. The provider cannot make
transparent takeover race-free: unannounced direct typing remains conservatively detected,
best-effort evidence. A supported action never intentionally overrides an established human claim.

## 4. Close-out and integration

1. Implement and review the milestone in its worktree. Record actual checks and limitations under
   Completion evidence. Update its own `done` cell on the candidate branch, not on canonical main.
   Do not refresh every successor prompt; change other briefs only when their actual requirements
   changed. Commit the complete candidate using the existing Git identity.
2. Invoke `baton integrate <run>`. Baton serializes integration, prepares a separate integration
   worktree from expected main, merges the candidate, validates the plan and completion evidence,
   runs the registered standing check, and verifies that the check did not change the tree.
3. Only after checking that exact combined commit does Baton fast-forward clean canonical main.
   The durable receipt binds run, candidate, expected main, integrated commit and verified tree.
   If checking fails, fix the candidate and invoke `baton integrate <run> --retry`. This explicitly
   supersedes an unverified operation and preserves its work and output. A checked/possibly promoted
   operation cannot be superseded; repeat normal integration to reconcile it.
4. Publish a complete artifact naming the receipt's `integrated_commit` as `merged_as`. Baton
   rejects an unrelated old ancestor, a different session/run, or a completion without a receipt.
5. Keep both worktrees until a person deliberately cleans them up. This foundation never prunes.

The registered check is an argv array and must be replay-safe and produce no tracked/untracked tree
changes. Registration requires `checkReplaySafe: true`. The check runs only through the explicit
integration command; a future launchd tick must not execute target code itself. Building a project
requires that project's/user's authorization. Baton's standing check is shell fixtures only.

## 5. Immutable handover

Publish a single JSON object through `baton publish`, or use the same no-clobber publication protocol.
Generate `message_id` once and preserve the same full JSON on retries and in the printed fallback.
Never rewrite a published identity with different contents. A new ending gets a new identity.

Message identity deduplicates content; it does not establish chronological order between different
endings. Filename sorting and `written_at` cannot decide which delivery an ending belongs to. M04
must define and validate delivery correlation before automating continuations or using older
endings as current execution state. Current consumption records observations and has no such
automatic continuation path.

```json
{
  "baton": 2,
  "message_id": "one-stable-uuid-for-this-ending",
  "run": "run-id-from-dispatch",
  "project": "/absolute/canonical/checkout",
  "milestone": "M03",
  "session": "claude-session-id",
  "plan_revision": "full-commit-id-recorded-at-dispatch",
  "written_at": "2026-09-12T10:00:00Z",
  "outcome": "complete",
  "merged_as": "full-integrated-commit-id-from-the-receipt"
}
```

The example commit placeholders stand for actual hexadecimal hashes. `message_id` and `run` are
restricted filename-safe tokens; the published filename is `<message_id>.json`. `written_at` is
context, not freshness or identity. The receiver claims the file before reading it, records one
decision by message identity, then archives it. Re-delivery is harmless; conflicting reuse is rejected.
Print the same complete JSON last in a `baton` fence. Consumption never stops a session.

## 6. Other outcomes and hooks

`asking` replaces `merged_as` with a nonempty `question`, optional string `options[]`, recommendation,
and context. `stopped` carries `reason` and string `detail`; reasons are unfinished, blocked,
merge-failed, main-broken, no-handover, api-error, other. Blocked requires `blocked_by`; api-error
requires `error`. No-handover and api-error are hook conventions, not cryptographic authorship.
A stopped/asking artifact is not verified progress and does not reset the recovery budget.

Hooks know the prepared run through `BATON_RUN`. Their fallback endings use a conversational record
UUID and stable dispatch timestamp, so callback replay cannot manufacture new identity from the
clock. Missing record identity yields a diagnostic, not a guessed ending. Printed fallback preserves
the session's message ID. Future resume support must correlate each delivery to its typed record and
reject stale delivery observations; it must not revive the version-1 per-session mutable mailbox.

## 7. Extensions, cancellation and project migration

Provider output and artifact text remain data, not instructions to the controller. A session may
request a judgment, blocker change or cancellation, but only the owning policy/command path can
authorize the resulting action. `abandon` deliberately closes tracking after its safety checks;
it does not stop a process or prove that a cancellation request was delivered. Any future cancel
operation needs its own intent, observation and terminal-state rules.

Preserve the selected model and explicit scope across retry unless a person or an already-authorized
policy changes them. A provider fallback or opaque error label is not authority to downgrade a
milestone, widen permissions or reinterpret a configuration error as context exhaustion.

Changing required fields or their meaning requires a protocol-version/migration decision and
tests for both accepted and rejected versions. Readability of legacy records does not authorize
acting on them. Other projects follow the same contract; onboarding must prove it with their actual
paths, graph, check, provider and execution environment rather than copying Baton's assumptions.
