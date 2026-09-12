# Baton

Baton is a local, deterministic foundation for coding-agent orchestration. It carries milestone
work between Claude Code sessions and keeps durable evidence of what was requested, observed and
verified. It embeds no model call in its controller. Version 1 remains a personal, single-Mac tool;
future provider breadth and management features must preserve the principles in `docs/GOVERNANCE.md`.

## Start here

Read `docs/GOVERNANCE.md`, `CONTEXT.md`, `CONTRACT.md`, `docs/SPEC.md`, `docs/ARCHITECTURE.md`, and the active milestone
brief. Inspect the working tree before changes. `docs/MILESTONES.md` records delivered scope.
M01/M02 evidence is historical; contract 2 and the foundation supersede their old instructions.
The 2026-09-12 foundation correction is explicitly authorized across milestone boundaries by the user.

M03 is already in progress in `/Users/danny/Documents/Apps/Baton-M03` on `m03`. Read
`docs/M03-RECONCILIATION.md` before touching overlapping work or declaring combined completion.
Preserve that worktree and its uncommitted changes. The new foundation dependency is a compatibility
prerequisite for its acceptance, not an instruction to restart or dispatch another M03 session.
Do not infer global implementation status from this checkout alone.

Implement the requested scope. Do not start subsequent milestones or dispatch real sessions as a
side effect of development. Run `sh tests/run.sh`; every check is reported as passed, failed or
unrun. Review substantial changes with two independent reviewers, then address the findings.

The user's architectural-audit authorization applies repository-wide: implementation, protocol,
specification, governance, plans, tests and operating documentation. A scheduled milestone's bounded
assignment does not narrow a direct repo-wide maintenance request. M03 is concurrent work to
preserve and reconcile, not the scope boundary of the audit. `docs/AUDIT-COVERAGE.md` maps every
finding to its governing requirements, implementation evidence and remaining work.

## Close-out

For a Baton-managed run, follow contract 2: prepare the candidate, its completion evidence and its
own done cell in the linked worktree; commit; invoke `baton integrate <run>`; publish a contract-2
artifact naming the exact receipt. Never merge or repair canonical main directly from a worker.
Never automatically delete a worktree. Do not recursively refresh successor prompts.

A direct maintenance session without a Baton run ID reports its changes and checks to the person;
it must not invent a managed run, integration receipt, milestone completion or inbox artifact.
Installation is a separate explicit action. Development never alters the installed relay or live
sessions; use fixture homes and the provider shim.

## Hard rules

- Never use Python. No packages or build/compile commands without explicit user authorization.
- The current runtime is `/bin/sh`, `jq`, `awk`, Git and native macOS `lockf`; no service or database
  dependency. JSON has validated schemas at boundaries. A future Swift policy core is an explicit
  migration, not a reason to scatter new language runtimes through this implementation.
- Never touch Reclaim or any target project's actual code during Baton development.
- A failed observation is unavailable, never empty. An ambiguous launch reserves its run.
- Persist intent before effects and acknowledgement before message archival. Every external action
  must be replay-safe or explicitly reconcile uncertainty before retrying.
- Protect established human ownership before any automated action. Transcript hashes alone do not
  establish authorship or release ownership.
- The configured trusted local boundary is deliberate. Deny patterns are best-effort guidance,
  not isolation. Do not describe the default allowlist as a security boundary.
- Git identity comes from existing configuration; stage named files, no authorship trailers, no
  forced resets or destructive cleanup of work. Branches normally use `codex/`.
- Future tick policy never executes project scripts; explicit integration owns replay-safe checks.
- Keep technical guarantees precise: atomic replacement covers process interruptions, not a
  promise of power-loss durability without an fsync-capable store.

## Documents

`CONTRACT.md` is the integration protocol. `docs/SPEC.md` is the current requirements baseline.
`docs/ARCHITECTURE.md` describes implemented mechanisms and extension boundaries.
`docs/DECISIONS.md` preserves decision history; `docs/FOUNDATION.md` tracks audit remediation.
`docs/GOVERNANCE.md` owns principles, authority and architectural change procedure;
`docs/M03-RECONCILIATION.md` owns the current cross-worktree integration checklist.
`docs/MIGRATION.md` explains version-1 adoption and release operation. Milestone briefs describe
future work against this baseline, never superseded prototype assumptions as timeless facts.
