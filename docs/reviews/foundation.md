# Foundation review closure

Reviewed against original checkout `131205d9e68165cc48215983e30aa8eb2c34c001` on
`codex/architecture-foundation`. Two independent reviewers performed runtime and data-integrity
reviews, followed by verification of the fixes. Reviews were read-only; the implementing session
ran the tests and applied all changes.

## Findings addressed

| Finding | Correction | Evidence |
|---|---|---|
| Incomplete provider rows could hide a live session | Validate fields used by identity/safety decisions; unavailable/incompatible remain tagged | Incomplete-row and observation-failure checks |
| Naming convention could miss another linked worktree | Compare Git common-directory identity; reject duplicate registrations | Unconventional worktree check |
| Reused worktree could be dirty or older than its recorded revision | Require clean state and plan ancestry; record actual starting commit | Runtime guard and dispatch evidence |
| Failed integration pinned an unrecoverable candidate | Explicit --retry creates a new unverified operation; checked receipts cannot be discarded | Failed-check, repaired-candidate and promotion-replay checks |
| Same human text could restore automatic ownership | Bind release to record UUID; require one matching initial record before first release | Same-text/new-UUID refusal |
| Consumed question vanished from status | Render unresolved questions/options and stopped outcomes from the journal | Question-visibility check |
| Graph validation enumerated exponentially many paths | Topological elimination | 32-node converging DAG plus cycle tests |
| Schema admitted forbidden scheduling fields | Reject eligible, wait_for, model and prompt | Four schema cases |
| Timeout killed only the immediate check process | Dedicated process groups, TERM/KILL and watchdog completion | Nested-descendant timeout check |
| Adoption could accept canonical checkout aliases | Compare physical worktree roots and require a linked-worktree root | Canonical-subdirectory rejection |
| Lost promotion acknowledgement failed after main advanced | Acknowledge a verified commit already ancestral to clean main | Human-advance-after-promotion check |

Both reviewers' bounded closure passes reported no remaining actionable findings in their reviewed
scope. The implementation subsequently added and tested refusal of successful checks that leave
background workers, disabled implicit lifecycle Git hooks/fsmonitor, and revalidated canonical state
after promotion. Those final protections were hand-reviewed by the implementing session.

## Verification

- 31 historical read-model/parser regression scenarios: passed.
- 61 contract-2 behavior/fault checks: passed.
- Shell and artifact-schema syntax checks: passed.
- `git diff --check`: passed.
- Full captured fixture output: `docs/validation/foundation.txt`.

The review did not certify live Claude compatibility, TCC/FDA, launchd, remote operation, power-loss
durability or future milestone implementations. Their acceptance requirements remain explicit.
No live installation, real coding-agent session or target-project modification was performed.
