# Baton architecture — contract 2

## Shape and principles

Baton is a deterministic local controller with a provider adapter and an explicit effect boundary.
The process may restart between invocations; its state persists as identified requests, observations
and receipts. No model is embedded in policy. `docs/SPEC.md` states the current guarantees and limits.
`GOVERNANCE.md` owns P-01–P-12 and document authority. This file describes the foundation worktree;
M03's tick/rows/notification/plist implementation exists separately on `m03` and is still being
completed. See `M03-RECONCILIATION.md` for observed components, overlap decisions and acceptance.
The layer contracts below apply across the product; `AUDIT-COVERAGE.md` is the audit/evidence index.

```text
committed project revision + tagged provider observation + coherent journal snapshot
                                      |
                              deterministic decisions
                                      |
                              identified prepared action
                                      |
                        provider / integration effect executor
                                      |
                           acknowledgement and reconciliation
```

The implementation remains shell plus jq/awk/Git/native macOS lockf. It introduces no compiler,
package, service or database. A future Swift policy core should replace the structured-state/effect
implementation behind these boundaries, preserving the protocol and fault tests. Do not migrate
hooks or add a second runtime solely to reduce line counts.

## Authority boundaries

- The committed plan owns the graph. Person-owned registration owns execution policy and gate approval.
- The journal owns run identity, acknowledged provider sessions, human ownership and integration receipts.
- Immutable messages report observations. They cannot self-register a session, change scheduling
  dependencies, stop a process, release ownership or prove completion without a receipt.
- The adapter validates external observations and bounds calls. Policy does not infer absence from errors.
- Workers own candidate branches. The integration command exclusively owns canonical close-out.
- Installation owns immutable releases. Active sessions use the release captured by their settings.

These are operating boundaries for trusted local code. They are not isolation from an arbitrary
same-user process. The distinction must remain visible when orchestration expands beyond v1.

## Lifecycle facts and layer contracts

Avoid a single state enum that mixes authority, liveness and progress. The current run reducer's
`active` means acknowledged and not terminal; it does not mean a process was observed working.

| Fact | Source and owner | Must not be inferred from |
|---|---|---|
| Planned work/dependencies/done | Committed project revision, interpreted by plan policy | Provider state, a handover's proposed successors, or branch existence |
| Prepared/uncertain/active/complete/abandoned run | Identified journal events and run reducer | PID existence or a file disappearing from the inbox |
| Human/controller ownership | Explicit ownership events and typed-record boundary | Matching text, a successful test, or a running process |
| Observed process liveness | Successful, validated provider observation | A failed query, an acknowledged historical dispatch or transcript existence |
| Execution condition: running/waiting/question | Correlated evidence interpreted by the owning policy | The durable run phase alone; the detailed M03–M05 model is pending |
| Candidate/check/promotion state | Integration operation and exact receipt | Milestone Status alone or an unrelated ancestor |
| Prompt/ruling delivery state | Future identified delivery operation and adapter acknowledgement | Notification intent, CLI exit alone, artifact sort order or current message text |

The plan reader supplies a validated snapshot; it does not launch. Admission consumes the snapshot,
ownership and capacity and prepares a request; both scheduled and manual entry points must use it.
The effect executor records observations/acknowledgements; it does not invent scheduling policy.
The inbox records immutable evidence; it does not perform process actions. Integration owns the
canonical update and verification receipt. Read models render those facts; future management UIs
submit commands to the same owner rather than writing a parallel state file.

Recovery policy belongs above the adapter. The adapter reports evidence and known capabilities,
not an opaque instruction to retry or change models. A cancellation request, if introduced, is a
stop operation awaiting observation; abandonment is an explicit accounting disposition and is not
proof of termination. The detailed delivery, recovery and management operations remain their named
milestones. These boundaries introduce no new runtime command or implicit message-schema revision.

## State layout

```text
~/.baton/
  bin/baton                       stable wrapper resolving current once
  bin/sh                          optional FDA-granted shell, never silently regranted
  releases/<content-sha>/          immutable bin/, lib/, hooks/
  current                         atomic symlink selecting a release
  mutation.lock                   persistent inode; kernel ownership, not a stale-lock marker
  config.json                     schema, cap, runtime version, trustedLocal, model aliases
  projects/<key>/project.json      canonical path, plan, contract, check argv, checkReplaySafe, gateApprovals
  projects/<key>/permissions.json  best-effort deny rules
  settings/<run>.json              pinned release hooks and immutable dispatch options
  runs/<run>/prompt.txt            exact delivered prompt, recorded by hash
  inbox/<message_id>.json          atomically published immutable message
  processing/<claim-uuid>.json     claimed before validation; replay resumes interrupted work
  archive/<message_id>.json        acknowledged payload
  rejected/<claim-uuid>.json       rejected input, retained without overwriting other claims
  integrations/<run>/<operation>/  integration worktree and check.out/check.err
  log.jsonl                       logically append-only, atomically replaced under the lock
  status/<session>.json            replaceable provider telemetry, never execution authority
  last-tick                       future scheduler's last completed invocation
```

## Implemented interfaces

| Module | Responsibility |
|---|---|
| `bin/baton` | CLI routing; source one release; lock mutating verbs; leave status/plan/publish independent. |
| `lib/lock.sh` | FD 9 plus native `lockf`, lock ownership assertion and release. Child provider processes close FD 9. |
| `lib/log.sh` | Stable event IDs; atomic logical append; coherent log read; IDs, quoting and prompt hashes. |
| `lib/adapter.sh` | Bounded provider calls, configured version check, tagged fleet observations. |
| `lib/git.sh` | Lifecycle Git without implicit project hooks/fsmonitor; preserves configured identity. |
| `lib/plan.sh` | Parse/validate a committed graph, topological cycle check, person-approved gate interpretation. |
| `lib/runs.sh` | Run reduction, prepared capacity, ownership boundaries, acknowledgement, reconciliation, adoption/abandonment. |
| `lib/dispatch.sh` | Validate safety prerequisites, compose exact prompt/settings, prepare, create/validate worktree, launch once. |
| `lib/integrate.sh` | Identified integration attempts, combined-tree checks, guarded promotion and replay. |
| `lib/artifact.jq` | Contract-2 envelope/outcome schema. |
| `lib/inbox.sh` | Claim, bind, deduplicate, acknowledge, archive and recover; no process actions. |
| `lib/status.sh` | One journal snapshot, unavailable observations and pending/user-action details without a writer lock. |
| `lib/derive.sh` | Retained read models; failure ladder now spans attempts. Historical derivations are not authorization checks. |
| `hooks/*` | Immutable publication, stable-identity fallback, and replaceable status telemetry. |
| `install.sh` | Content-addressed release assembly and atomic selection; preserves existing config. |

## Journal and recovery

A new event carries `schema:2`, `event_id`, `at`, `kind` and applicable project/milestone/session/
attempt/run/episode fields. Reusing an event ID with different contents (excluding replay time)
fails. Writing a new event validates the old journal, writes its complete logical successor to a
new temporary file, then renames it. Readers can hold one coherent snapshot without the writer lock.

This is O(n) per event and intentionally favors a simple recoverable local store over append-tail
repair. No arbitrary 4 KB rejection can discard a legitimate decision after an external effect.
Measure journal growth and operation duration before choosing a new storage backend. A Swift store
with file/directory synchronization is the route to stronger power-loss guarantees.

Choose that migration by measured behavior and needed guarantees: growing scan/write latency,
lock contention or blocked diagnostics, memory pressure from JSON transport, and requirements for
synchronized durable commits or finer-grained transactions. Preserve stable IDs and replay semantics
and run conformance/fault tests against both stores. Merely splitting a large file or rewriting it
in a typed language does not establish those properties. Capture a baseline before asserting a
performance improvement; none is claimed by the current fixture result.

A dispatch is `dispatch_prepared → worktree_ready → launch_started → dispatch`. If launch is marked
started but no acknowledgement exists, the run is uncertain. `reconcile` can acknowledge exactly one
row matching its unique name and worktree. It cannot prove that a missing row means launch never
happened. `abandon` is the explicit human disposition, not an automatic retry. A prepared run whose
local preparation failed also remains visible; inspect/repair its files and explicitly abandon it
before a new dispatch. The foundation favors preserved evidence over guessing.

Consumption is `publish → claim → validate → consumed[/escalation] → archive`. A crash before the
journal event leaves a processing file to validate again. A crash after the event leaves a processing
file whose matching identity/hash replays the same decision and finishes archival. A conflicting
payload is rejected. Archive entries lacking journal records remain visible legacy anomalies; the
foundation does not invent their prior decision.

## Integration and ownership

Integration takes the mutation lock, which currently serializes all mutating operations. It creates
an operation-specific detached worktree from expected main, merges the recorded candidate, validates
its graph/done cell/evidence, then runs registered check argv. Checks are explicitly replay-safe and
synchronous. Failed output and trees are preserved. `--retry` opens a fresh operation against a new
candidate/main only while the previous operation is unverified.

Checks have a configurable bound (`BATON_CHECK_SECONDS`, 1800 seconds by default). Their process
groups are terminated on timeout, and a successful parent that leaves background workers is rejected.
Provider calls have their own bound (`BATON_CALL_SECONDS`, 10 seconds by default); a deliberately
detached provider service remains an external effect to reconcile, not a check subprocess.

After success, `integration_checked` stores candidate, expected main, integrated commit and tree.
Only clean canonical main at the expected commit may be fast-forwarded. If promotion happened but
its acknowledgement was lost, replay observes that exact commit or proves it is already an ancestor
of clean main, and records `integrated` without overwriting later human commits. Other unexpected
main changes require inspection; the command never resets them. A complete handover must match this
receipt. No automatic cleanup follows completion.

Human `claim` and `release` are journal events. Release stores the latest typed UUID and hash.
Automatic integration requires the exact released UUID to remain latest; initial dispatch without
release requires exactly one typed message matching the original prompt and an available UUID.
A new record, missing transcript or parse failure denies the action. This binds identity rather than
text. Direct typing can still race a provider observation; explicit claim before manual intervention
is the supported handover protocol. Consumption itself has no stop/resume path.

## Installed and historical compatibility

Install builds a new content-addressed directory and atomically changes `current`. The launcher
resolves that directory once. Dispatch settings embed its absolute hook paths, so an install cannot
change an already running session's hook behavior. Rollback selects a previously validated release;
its protocol compatibility with the current journal must be checked first. No automatic deletion or
in-place replacement of old releases occurs.

Legacy log events remain readable for historical status and derivation regression tests. They do not
create contract-2 run authority. Legacy messages fail schema validation. Adoption is explicit, starts
human-owned, and requires matching repository/session identity. It does not retrofit a provider's
saved hook settings; the person must use the new publication contract or start a new managed run.

Restoration must include the journal's referenced payloads, prompts, configuration and release
provenance. A restored checkpoint can predate effects already visible in the provider or Git.
Read and reconcile those external facts before restarting mutation; an older ledger cannot make
those effects un-happen. MIGRATION.md defines the operator procedure and M08 owns its acceptance.

## Future scheduler and orchestration extension points

M03's existing implementation must be adapted to construct one input snapshot, reconcile uncertain actions, honor ownership, consume messages,
validate candidate policy and prepare actions. It may not infer crash from unavailable data, act on
stale graph revisions, or invoke target checks inside the tick. No safety branch is a temporary
pass-through. The marker belongs to the completed transaction while the writer lock remains held.
Preserve M03's useful timing/notification and signed-shell observations. Its old session-filename
checks, archive-disposition selection, raw provider calls and release-before-marker sequence cannot
be transplanted unchanged. The shared admission boundary must protect CLI and scheduled dispatch.
Keep notification intent separate from delivery proof, propagate partial project failures into tick
completion state, and close FD 9 in detached holders. These are pending combined acceptance checks.

M04 adds identified prompt deliveries and provider acknowledgement. A recovery episode spans runs;
new process creation is not progress. Failed/ambiguous delivery remains pending rather than causing
an untracked duplicate. M05 resolves escalation IDs explicitly; editing unrelated text must not
silently release a question. M06 introduces per-project integration leases only after cross-process
concurrency tests pass; until then one open run per project remains enforced.

After v1, other coding agents implement the same adapter observations/effects and run/message
protocol. Provider-specific session IDs, copy forks, quota fields, transcript metadata and process
lifetime rules remain inside adapters. Management/UI features consume read models and submit
identified commands; they do not become a second writer of state or a second scheduling authority.
Resource allocation, multi-host ownership, real isolation and a transactional typed store each need
explicit requirements and acceptance tests before expanding the trust or failure boundary.

Git integration is the v1 completion mechanism for project milestones, not a universal definition
of every future agent job. A non-Git judgment or management job must gain an explicitly versioned
completion/evidence contract with the same identity and ownership guarantees. It must not fabricate
a merge receipt to fit the coding-milestone schema. This is an extension rule, not a second task
type implemented by the current runtime.
