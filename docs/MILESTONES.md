# Milestones

M01 and M02 delivered the original prototype. M02-b is the user-authorized foundation correction
from the 2026-09-12 architectural audit. Historical prototype evidence does not satisfy the new
contract's acceptance criteria. M03 is already in progress on `m03`; M02-b is its combined
integration prerequisite, not a retroactive start barrier. M03–M08 preserve the current contract
under `GOVERNANCE.md`. See `M03-RECONCILIATION.md` before merging the workstreams.
The audit applies across all rows and all founding documents. `AUDIT-COVERAGE.md` maps its findings
to current evidence and each milestone's remaining acceptance; M03 does not bound maintenance scope.

| ID | Title | Depends on | Model | Effort | Remote | Status | Progress | User-visible result |
|---|---|---|---|---|---|---|---|---|
| M01 | Original plan and dispatch | – | fable | | | done | Historical | Historical bootstrap |
| M02 | Original inbox and read models | M01 | opus | | | done | Historical | Historical baseline |
| M02-b | Durable orchestration foundation | M02 | opus | | | done | Fixture verified on foundation workstream | Unique runs/messages, explicit ownership, verified integration, fault recovery and migration |
| M03 | Safe reconciliation tick | M02-b | opus | | | | In progress on m03; combined acceptance pending | Scheduled reconciliation with fail-closed observations and no unsafe policy placeholders |
| M04 | Identified deliveries and bounded recovery | M03 | opus | | | | Planned | Recoverable resume/ruling delivery, episodes across runs, proven escalation budget |
| M05 | Human decisions and notifications | M04 | opus | | | | Planned | Questions resolved by stable escalation ID without overwriting human control |
| M06 | Deliberate concurrency and resource policy | M05 | opus | | | | Planned | Optional multiple workers with exclusive integration and measured resource allocation |
| M07 | Remote adapter acceptance | M06 | opus | | | | Planned | Remote behavior verified against the actual provider, preserving run/delivery identities |
| M08 | Target onboarding and v1 acceptance | M07 | opus | | | | Planned | Explicit target migration and an observed unattended acceptance run |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| Reclaim migrated | M08 | |

Clearing a gate requires a committed decision token and the person's matching `gateApprovals`
registration entry. No Baton development session edits or dispatches into Reclaim.

Progress is an ignored descriptive column; Status keeps its machine grammar. A blank M03 Status
means completion is unaccepted, not that no work exists. The graph may identify M03 as eligible;
that is not authorization to duplicate its existing run. Runtime admission and the current-work
handoff must account for it. This documentation task starts no new M03 and changes no live runner.

## Work and verification

Read the current contract/spec/architecture and the active brief. Change only the requested scope.
The foundation correction is explicitly cross-milestone; it does not mark later milestones done.
Do not assume one session is enough: preserve a coherent candidate and describe remaining work.
Split further work into an actual graph row before relying on that split for scheduling.

`sh tests/run.sh` is the standing check. It preserves historical read-only regression cases and
adds contract-2 behavior/fault assertions. Builds and live provider sessions are not part of it.
Use two independent reviewers for significant work and address their concrete findings.

For managed work, completion follows `CONTRACT.md`: candidate evidence and done cell on the branch,
serialized checked integration, immutable handover referencing its receipt. Direct maintenance
without a run ID reports to the person and does not fabricate a handover. Installation stays separate.

## Completion evidence template

Record changes and interfaces; exact checks with outcomes; unrun checks and limitations; relevant
decisions; candidate/integration commit evidence where a managed run exists; observed working-tree
state; and remaining scope. Never record an expected test as passed or an unimplemented milestone
as complete. Stable kickoff rules remain in the contract rather than being copied and refreshed
recursively through every successor brief.

## After version 1

Current acceptance ownership is explicit: M04 proves delivery/recovery semantics; M05 proves
decision/management authority; M06 proves resource accounting and scheduling; M07 proves adapter
conformance; M08 proves target operation and restoration. Their cross-layer cases implement the
applicable F-39–F-45 requirements; those behaviors are not marked done by documentation alone.

The extension target is coding-agent orchestration and management: provider-neutral run identities,
recoverable effect delivery, read models for management interfaces, and explicit human ownership.
Other providers, multi-host coordination, stronger OS isolation and a typed transactional core
need separate acceptance criteria. None may introduce a second scheduling authority or bypass the
verified integration and message protocols to make execution appear more fluid.
