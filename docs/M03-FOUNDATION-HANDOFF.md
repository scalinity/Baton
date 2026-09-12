# User-directed foundation handoff for the active M03 work

The user confirmed on 2026-09-12 that M03 is already in progress and asked for the architectural audit
to govern the program's backbone. Continue the existing `m03` worktree and preserve its committed
and uncommitted implementation. Do not restart M03 or launch a duplicate session.

The foundation is committed on `codex/architecture-foundation` at
`48cab089dbac1f6de9c9a29b01d1ddcea8ef853e`. The canonical checkout can now return to clean `main`
for M03 to land; its working files must not be mistaken for the separate foundation checkpoint.

Read these repository-relative files from that commit:

- `docs/GOVERNANCE.md` — principles, document authority and evidence.
- `docs/AUDIT-COVERAGE.md` — repository-wide findings, evidence and remaining acceptance.
- `docs/M03-RECONCILIATION.md` — concrete preserve/adapt matrix and combined acceptance.
- `docs/SPEC.md` and `CONTRACT.md` — required protocol for the combined candidate.
- `docs/ARCHITECTURE.md` and `docs/MIGRATION.md` — mechanisms and activation boundary.

For example, from this worktree:

```sh
git show 48cab089dbac1f6de9c9a29b01d1ddcea8ef853e:docs/M03-RECONCILIATION.md
```

The foundation and M03 remain separate commits/workstreams. A clean M03 merge into `main` does
not integrate or validate the foundation automatically. Preserve both histories and reconcile them
deliberately; do not bulk-copy or reset either side.

M03's original D-038 onward decisions and measured shell-signing/cold-start/notification findings
are preserved. The foundation's colliding decisions have been renamed FND-001–FND-006; GOV-001
records this reconciliation. Re-read both decision logs before allocating a canonical D-number.

Before close-out, reconcile existing tick/rows/notification/install changes with the foundation.
In particular: immutable messages replace session-filename authority; the committed graph replaces
historical handover dispositions; all dispatch admission checks remain active; kernel locking replaces
stale-directory recovery; completion markers stay under the lock and do not hide project failures;
notification intent is not delivery proof; detached holders close FD 9. Preserve M03's useful work
and tests while adapting these boundaries. The matrix names the specific functions and cases.

The older contract-1 close-out below the CLAUDE.md notice is superseded where it conflicts with the
current user-directed requirements. The new foundation dependency governs combined acceptance, not
whether M03 was allowed to start. No contract-2 run/receipt is retroactively invented for this session.
Record a coherent checkpoint and combined evidence before activation; do not treat either branch's
passing tests alone as proof for the other.

This handoff does not interrupt the session, change its code, deploy a release, or grant new live
or build permissions. Existing explicit user authorization continues to apply. The documentation
update has not been assumed read or acknowledged by the running session merely because this file exists.
