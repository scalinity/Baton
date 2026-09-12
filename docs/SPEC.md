# Baton specification — foundation baseline

This is the current contract-2 baseline. Historical requirements and prototype observations remain
in Git history, `docs/DECISIONS.md`, and M01/M02 completion evidence. They do not override this file.
The user approved the architecture audit on 2026-09-12 while M03 was already in progress on `m03`.
Document authority and P-01–P-12 principles are in `GOVERNANCE.md`; the observed M03 work and
uncompleted compatibility checks are in `M03-RECONCILIATION.md`.

## Product and scope

Baton carries milestone work between coding-agent sessions on one Mac. Deterministic code owns
execution identity, observation, recovery and integration; agents do coding and judgment. Human
rulings remain explicit. The eventual post-v1 direction is fluid autonomous agent orchestration,
with provider adapters and management features built on these same invariants.

The audit governs the entire product lifecycle and repository. `AUDIT-COVERAGE.md` maps each
finding and improvement opportunity to its owning layer and evidence. M03's active work is a
coordination case, not a restriction on corrections to other founding documents or milestones.

The v1 workflow is: admit work from a committed plan; prepare and acknowledge a run; observe its
progress without inventing liveness; preserve ownership through interruption; deliver any ruling
as an identified operation; verify and integrate a candidate; then accept its immutable completion.
Each stage either has supporting evidence or an explicit pending/unknown condition. An unattended
run succeeds by meeting the project's acceptance and preserving those transitions, not merely by
keeping a process alive or avoiding questions.

V1 remains local and personal. Provider-neutral identities and interfaces are foundations for later
agent management, not a requirement to add a hosted control plane, multi-user authentication, a UI,
multi-host coordination or additional model calls now. Those expansions need their own scope and
proof of the same properties.

Implemented in the foundation worktree: committed plan validation; prepared/acknowledged dispatch; immutable artifact
publication/consumption; explicit ownership; serialized checked integration; uncertain-launch
reconciliation; explicit adoption/abandonment; read-only diagnostics; immutable installation.
M03's separate worktree already contains tick, row reconciliation, notification and launchd code,
with further changes underway. It has not been integrated or verified against this foundation in
this documentation task. Continuations, answer delivery, remote dispatch and multi-lane project
scheduling remain later scope. No combined scheduled behavior is claimed by the foundation-only tests.

## Requirements

| ID | Requirement |
|---|---|
| F-01 | The controller embeds no model call. Provider calls occur only through the adapter. |
| F-02 | Each run is uniquely prepared before launch; preparation reserves the project lane and global capacity. |
| F-03 | A launch without acknowledgement is uncertain, never “did not happen”; reconciliation correlates the exact unique run name and worktree. |
| F-04 | Provider observations distinguish ok/unavailable/incompatible. Unavailable/incompatible observations cannot prove absence or advance a crash counter. |
| F-05 | Validate provider IDs, live PID shape, names and absolute working directories before dispatch safety decisions. Bound provider invocations and record the configured/runtime version. |
| F-06 | Read plan, brief and initial base from one committed main revision. Working edits do not change dispatch eligibility. |
| F-07 | Validate unique milestone/gate names, token shapes, all referenced targets and acyclicity. Cycle detection must not enumerate exponentially many graph paths. |
| F-08 | Gates need both their committed decision token and the matching person-owned gateApprovals entry. A session cannot self-authorize a gate under the operating contract. |
| F-09 | The current project concurrency limit is one open run; global cap counts prepared, uncertain, human-owned and active runs. Compare live session repository identity, not a worktree naming convention. |
| F-10 | A reused worktree belongs to the same repository and recorded branch, is clean and contains the plan revision. Record its actual starting commit; never reset away unfinished work. |
| F-11 | Each handover has an immutable message ID and exact run/session/project/milestone/plan-revision binding. Unknown or mismatched authority fails closed. |
| F-12 | The consumer atomically claims before reading. Conflicting publication cannot replace the bytes being validated. |
| F-13 | Canonical payload hash plus message ID identifies a delivery. Duplicate deliveries apply one decision; conflicting reuse is quarantined without overwriting the original archive. |
| F-14 | Journal acknowledgement precedes archival. A retained processing file repairs an interruption before/after acknowledgement by replaying idempotent events and completing archival. |
| F-15 | A message from an unresolved prepared run stays in processing pending acknowledgement; the message itself is not proof of launch ownership. |
| F-16 | Consumption is observational: an asking or stopped artifact cannot stop/resume a session. |
| F-17 | Human claim/release is durable. Release binds a specific typed-record UUID; repeating text cannot release later human input. Missing/unreadable ownership evidence forbids automatic integration. |
| F-18 | Explicit ownership is the supported guarantee. Unannounced direct typing is detected conservatively and remains subject to provider observation races. |
| F-19 | Workers prepare candidate commits and never perform shared canonical close-out. Only explicit integration changes canonical main. |
| F-20 | Integration records expected main and candidate, merges in a separate worktree, checks the combined commit, verifies unchanged HEAD/working tree, then promotes only against expected main. |
| F-21 | The registered check is an argv array, explicitly replay-safe, and synchronous. No shell interpolation composes that argv. A future tick never executes target scripts. |
| F-22 | A check failure preserves main and all candidate/integration work. Explicit --retry creates a new integration operation; checked or possibly promoted operations cannot be discarded. |
| F-23 | Interrupted promotion is reconciled from its checked commit and current main. Completion requires the matching integration receipt and its exact full commit ID on main. |
| F-24 | Completion evidence is nonempty and the candidate marks its own milestone done. An arbitrary main ancestor is insufficient. |
| F-25 | Failure budgets span attempts. Dispatch alone, asking, and unverified session assertions do not reset them. Verified integration progress or explicit recovery reset does. |
| F-26 | The kernel mutation lock is attached to an open file description and is never inferred from file existence. Read-only status takes no mutator lock. |
| F-27 | A journal writer holds that lock; logical append uses atomic physical replacement. A reader sees one coherent old/new journal, never a partial append from the current writer. |
| F-28 | Stable event IDs make replay idempotent; conflicting reuse is an error. Old malformed journals are reported, not silently truncated or guessed. |
| F-29 | Status reads one journal snapshot and exposes uncertain runs, ownership, questions, stopped outcomes, processing leftovers, rejected messages, unmatched archives and pending integration. |
| F-30 | Installations are immutable content-addressed releases, atomically selected; settings pin release-specific hooks. Existing registrations are never silently migrated. |
| F-31 | Trusted local execution is explicit opt-in. Pattern denies are best-effort, not isolation; an allowlist is not advertised as effective containment under bypass mode. |
| F-32 | Version-1 handovers are not automatic authority. Explicit adoption requires a live, uniquely identified session in a linked worktree of the registered repository and starts human-owned. |
| F-33 | Abandonment is a deliberate human disposition with a reason and healthy evidence that the named run has no live matching process. It preserves work and history. |
| F-34 | No automatic worktree deletion, package installation, live session operation, or live deployment occurs during development tests. |
| F-35 | For combined M03 acceptance, tick completion identifies its scope and failed projects. Publish a fully completed marker atomically while holding the writer lock, only after that scope succeeds; replayed observation identity cannot count as a second crash sighting. |
| F-36 | M03 notification intent and delivery result are distinct. Transport is bounded, pending/failed delivery remains visible, and detached processes do not retain the controller's lock descriptor. |
| F-37 | M03 launchd acceptance retains its signed-shell findings and scopes executable/FDA/service-start evidence to the actual host and release. Copying a shell, signature verification alone, or a warm-service observation cannot substitute for the required execution/cold-start proof. |
| F-38 | Cross-workstream integration preserves existing M03 code, tests, decisions and uncommitted work. Foundation-only tests and legacy M03 tests do not certify the combined candidate; overlapping protocol changes require explicit reconciliation. |
| F-39 | Keep plan completion, durable run phase, human ownership, observed process liveness, execution condition and integration phase distinct. An active run is acknowledged, not proof of a currently working process. Views and policies must not collapse these facts into a misleading status. |
| F-40 | Before automatic continuation/ruling delivery, establish explicit delivery identity and ending correlation. Duplicate message identity, filename order, wall-clock order and provider exit status alone do not prove delivery ordering or acknowledgement. Late/obsolete endings cannot control a newer delivery. |
| F-41 | Recovery distinguishes evidenced transient failures, quota waits, human-fixable configuration/authentication failures and incompatible/unknown observations. Record retry policy and limits; unknown classification holds for diagnosis. Preserve work identity and selected model; never infer context overflow from a generic error or silently downgrade to keep execution moving. |
| F-42 | Management interfaces read projections and submit identified commands through the controller. Claim/release, ruling resolution, cancellation and abandonment are distinct operations. A future cancellation requires stop intent and observed outcome before claiming termination; no interface directly edits journal state to simulate success. |
| F-43 | Any replacement of conservative F-09 admission must define execution-resource leases, uncertainty reservations, paused/stopped work accounting and scheduling order. Amend the requirement and tests together; prove no duplicate execution or starvation under the chosen policy. Quota telemetry is scoped/stale evidence, not a fabricated per-model budget. |
| F-44 | Provider capabilities are validated for the adapter/version/environment before use, with conformance cases for unavailable, incompatible, delayed and duplicate responses. Remote transport and new providers preserve run/delivery/ownership identity; extending capability does not silently extend trust or authorization. |
| F-45 | Backup/repair/rollback preserves a coherent journal, payloads, prompts, receipts and release/configuration provenance. Restoration is not permission to replay effects: reconcile current provider and Git state before resuming mutation. Preserve corrupt evidence and unexplained external effects rather than manufacturing acknowledgements. |

F-39–F-45 specify repository-wide interpretation and upcoming behavior. Their implementation owners
are M03–M05 (state/delivery/management), M04 (recovery), M06 (resource policy), M07 (adapter
conformance) and M08 (operating recovery/onboarding). They are not claimed implemented or tested
merely by this specification. `AUDIT-COVERAGE.md` separates existing foundation evidence from these
pending acceptance cases. Cancellation is conditional future behavior, not a new promised v1 command.

## Guarantees and limitations

The supported storage guarantee is recovery from process interruption at the tested boundaries.
Atomic rename and kernel locking are not a promise of power-loss durability; a stronger guarantee
requires an fsync-capable transactional store. A future Swift core must provide it before advertising
power-loss recovery. The native shell implementation remains intentionally bounded to personal use.

A process running as the same macOS account can violate the operating contract. Real containment
requires an OS-enforced boundary. Full Disk Access and `bypassPermissions` are explicit environmental
choices, not automatically enabled by installation. `trustedLocal` defaults to false.

Provider compatibility is checked against the configured version and response schema. The original
2.1.268 prototype evidence is not a promise about future CLI releases. A mismatch requires validating
and updating the adapter, not merely suppressing the check.

Usage feeds are telemetry. An account-wide percentage is not a per-model remaining budget. No
predictive per-model guarantee is implemented. Lid-close sleep stretches timers; a self-reported gap
is only visible when the controller recovers. Immediate outage alerts require an independent watcher,
which is not part of this personal foundation.

## Verification

`sh tests/run.sh` performs shell syntax/schema checks, retained historical read-only regression
scenarios and contract-2 behavior/fault tests. Repeating an expected directory snapshot alone does
not establish idempotence. The new tests assert identities, durable ordering, duplicate counts,
main revisions, and replay outcomes independently of golden snapshots.

Required cases include unavailable/malformed observations; graph defects; interrupted journal and
archive boundaries; killed lock owners; ambiguous launches; duplicate and conflicting messages;
old-ancestor completion; mismatched sessions; failed checks and corrected integration retries;
interrupted promotion; ownership transfer and new human records; immutable release selection.

Before each owning milestone completes, add the applicable cross-layer cases: acknowledged but
stopped runs; late endings after a newer delivery; false-positive error classification; ruling
intent versus delivery; paused versus uncertain capacity; unsupported adapter capabilities; and
restoration after an external effect happened beyond the restored checkpoint. Assertions must
observe independent outcomes and exact identities, not mirror the implementation's branch choices.

Tests use temporary homes, repositories and provider shims. They do not build, use model quota,
modify live Baton state, load launchd, or dispatch into Reclaim. The existing Git identity is used.

## Delivery order

Reconcile the foundation with the M03 scheduling work already underway, then M04 recovery/delivery identities, M05
ruling transport, M06 deliberately enabled project concurrency, M07 remote adapter acceptance,
and M08 target onboarding. Each milestone follows the applicable F-01–F-45 obligations and the
implementation ownership above. F-35–F-38 add combined M03 acceptance obligations; later acceptance
requirements are not a claim of implementation in this foundation checkout. Missing functionality is not
implemented as a permissive pass-through that temporarily violates an invariant.
