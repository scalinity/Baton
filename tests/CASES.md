# Test coverage

Run `sh tests/run.sh`. No build or live provider process is involved.

The runner checks shell/schema syntax, then executes:

- `legacy-read.sh`: 31 historical read-model, parser and journal-error scenarios. These preserve
  useful regression coverage for v1 history. Historical row fixtures are fed directly to read-model
  tests; they are not treated as valid current provider observations.
- `foundation.sh`: contract-2 behavior and fault assertions. These use temporary repositories,
  the existing Git identity, an isolated home and a provider shim. A failed fixture is preserved
  with its path printed for debugging. Successful fixtures are removed.

Original contract-1 mutation snapshots remain under `scenarios/` as historical evidence, but are
not executed against the new protocol. The old lock/no-handover/dispatch/consume/status/install
expectations would encode the flaws being removed. Their current guarantees are tested by behavior
assertions in foundation.sh rather than re-freezing outputs to whatever the implementation emits.
The standing suite has no snapshot-freeze side effect.

## Independent properties

The full audit-to-requirement map is `docs/AUDIT-COVERAGE.md`. The table below describes foundation
coverage; the future cases listed afterward are required by their milestones and are not already
included in the captured foundation result.

| Area | Assertions |
|---|---|
| Graph and authority | Committed plan ignores drafts; cycles/dangling references fail; converging DAG stays tractable; gate needs person approval. |
| Observation | Failing, malformed and incomplete provider rows block dispatch; status reports unavailable. |
| Processes and lock | Concurrent mutation refuses; status stays readable; SIGKILL releases the owner's kernel lock; timed-out descendant groups cannot write later. |
| Journal | Requires lock; duplicate event identity applies once; conflicting identity refuses. |
| Dispatch | Prepared request precedes start and acknowledgement; project reservation prevents duplicates; unconventional worktree names do not evade repository identity. |
| Messages | Session binding; integration receipt required; forbidden scheduling fields; duplicate/conflicting delivery; immutable printed fallback; questions stay visible. |
| Crash/interleaving | Failure before acknowledgement retains processing; failure after acknowledgement replays once; replacing the inbox path cannot alter claimed bytes. |
| Ownership | Human claim blocks integration; a new UUID with the same text remains unreleased; canonical aliases/subdirectories cannot be adopted. |
| Integration | Failed check leaves main intact; repaired candidate gets a new operation; lost promotion acknowledgement recovers even after human main advancement; receipt is unique. |
| Recovery | Lost launch acknowledgement is reconciled without another launch; redispatch does not reset the failure budget. |
| Release | Repeated install selects the same immutable content; new installation does not assume trusted execution consent. |

These tests establish the simulated boundaries they exercise. They do not certify actual Claude
CLI compatibility, TCC/FDA, launchd, remote operation or power-loss durability. Those are explicit
live-acceptance or future-storage requirements, not implied by a passing fixture suite.

## Pending cross-layer acceptance

M04 adds late/duplicate ending correlation, lost delivery acknowledgement and evidence-based error
classification without model changes. M05 adds command/ruling resolution separated from ownership
and honest requested-versus-observed state. M06 adds resource-lease accounting and fairness under
paused/unknown capacity. M07 adds adapter/version/remote conformance with delayed or incompatible
responses. M08 adds restoration after effects beyond a saved checkpoint and target-specific operation.
Each suite must identify independent observable outcomes and preserve its own checkpoint/evidence;
adding a requirement row is not a passing test.
