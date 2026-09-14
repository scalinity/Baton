# Baton V2 specification

**Status: implementation contract for C01–C12 and user rulings O1–O8. No unresolved product decision is carried by this specification.** Claude Code is the default; automatic Codex fallback is permitted on confirmed exhaustion of Claude Code's usage allocation. This document describes required behaviour, not an implemented or live-verified release.

This specification is self-contained. A coding agent does not need conversation history, V1 briefs, or the separate foundation tree. `02-decisions.md`, including subsequent user rulings, takes precedence if a conflict is found. Stop and record any additional necessary policy decision in its OPEN DECISIONS section rather than silently changing the selected policies. No milestones or implementation schedule are defined here.

MUST/MUST NOT are requirements. Types and signatures below are contract notation, not implementation code. Internal factoring and physical table normalization may vary without changing these contracts. External runtime flags and supported versions require adapter evidence; historical V1 captures are not current compatibility proof.

## 1. PRODUCT BEHAVIOUR

### 1.1 Purpose and universal input

Baton is a personal local macOS controller that carries requested project work through coding sessions, interruptions, handoffs, verification, local application, and dependent work. The ordinary input is **a project directory plus requested work**, supplied directly or through an existing work source. Baton discovers the project, captures its actual starting state, prepares a workspace, creates a work definition, starts managed sessions, independently verifies their proposed results, and automatically applies verified local changes within the request.

An arbitrary project needs no Baton conventions: no Git requirement, `main` branch, milestone table, brief headings, registration JSON, permission file, seed handover, preinstalled hook, target service, test suite, or migration commit. Baton keeps generated control records and runtime instructions outside the target. Existing documents need not be renamed or rewritten. A plain request may produce one unit; a larger graph must be justified by the requested work.

Git projects with different branch names, dirty/untracked changes, detached HEAD, or unborn branches, and non-Git directories, are admissible. Intake acceptance is not a claim that every operation is possible. Missing information must be concrete: an inaccessible SDK, credential reference, hardware observation, ambiguous desired behaviour, or authority for an external action. Baton performs the remaining discoverable preparation. “Prepare your project for Baton” is not a recovery instruction.

Project selection carries the standing trusted-host policy. Ordinary in-scope setup, native tools, local services, checks, and coding require no additional Baton trust questionnaire. Runtime/OS policy and explicit user restrictions remain binding. Project instructions guide execution but cannot authorize changes to Baton's graph, accept results, release another reservation, or widen the request. Workspace isolation separates edits; it is not adversarial containment against same-user host code.

### 1.2 Visible behaviour

Every accepted request immediately receives a durable run ID. Status shows project/location, understood scope and sources, runtime, progress, owner, workspace, verification and application state, and the exact reason the next action is waiting. Imported scope is visible without a mandatory approval screen. Authorized unambiguous work proceeds; conflicting intentions produce an addressed question while independent work can continue.

Local completion distinguishes a session's candidate claim, an accepted frozen result, application to the requested destination, and termination of execution. Do not collapse these into a single “done.” An accepted isolated result remains useful during an application conflict. Dependencies may consume it only if their declared requirement is that accepted result rather than applied destination state. A run cannot claim successful requested application while it is partial or conflicted.

All required controls are local: inspect, preview admission, answer, recheck, pause, drain, cancel, take over, hand back, follow up, adopt/observe a session, relocate/retire a project, and maintain retained state. Human and machine-readable views derive from the same records.

### 1.3 Runtime choice

Claude Code and Codex are both implemented V2 adapters, each supporting unfamiliar-project intake under the same core lifecycle. A hypothetical second adapter does not satisfy this requirement.

Without explicit selection use Claude Code. Current supported evidence of exhaustion of that Claude account's applicable allocation permits Codex fallback. Missing/stale quota telemetry is unknown, not exhaustion. Binary, authentication, permission, generic network, overload, or ambiguous-launch failures do not independently permit this fallback. A short request-rate refusal qualifies only when provider evidence identifies allocation exhaustion rather than transient request throttling.

An explicit runtime-only selection or data restriction overrides fallback. The alternative profile must already have applicable authorization and capabilities. Baton never creates credentials, purchases capacity, or consumes reset credits automatically. If Codex cannot be used, preserve automatic Claude wait/probe recovery. Optional telemetry absence never blocks productive work.

Fallback from existing work starts a **fresh managed conversation** with accessible work, checkpoint, decisions, evidence, and reconciled unfinished actions. Confirm the previous execution cannot still perform productive work before replacement. Human ownership and uncertain effects cannot be bypassed. There is no live conversation or private model-state transfer claim. Do not interrupt a productive Codex continuation when Claude allocation resets; subsequent default selections reevaluate current evidence.

### 1.4 Autonomy and communication

Verified in-scope changes apply locally without routine merge/review approval, subject to preservation and destination checks. Explicit patch-only instructions or actions reserved for the person override that default. Push, deployment, external publication/messages, unrelated destructive changes, and new scope require their actual authority; local application does not grant it.

No default personal reserve, cost/token ceiling, total-work timer, lifetime retry limit, or budget setup step applies. Productive overnight work continues. Common admission adapts concurrency to host pressure, resource conflicts, ownership, and real provider limits. Incident-level circuit breakers bound bursts of ineffective actions, then observe, back off, probe prerequisites, or use a meaningfully different supported path. A fresh attempt alone does not clear failure history.

Mac notifications address durable attention records. Runtime-native remote access is opt-in where supported; questions are interpreted regardless of transport. Phone/network/optional-channel failure does not block local work. A simple independent notification/watchdog transport may use an existing supported service; no custom mobile app or hosted control plane is required. Unproved off-host delivery/outage detection is shown as unavailable, never promised.

Prompts, rulings, messages, rejected reports, evidence, checkpoints, and closed workspaces remain until explicit deletion. No expiry or pin renewal. Notify about storage pressure; actual inability to persist suspends writes instead of triggering deletion or unrecorded effects.

### 1.5 V1 inheritance

Only these semantic boundaries are **UNCHANGED FROM V1**; their implementation can change:

| Boundary | Meaning in V2 |
|---|---|
| **UNCHANGED FROM V1 — deterministic relay** | No model inference embedded in control decisions. Judgment occurs in managed sessions returning claims. |
| **UNCHANGED FROM V1 — personal macOS operation** | Local personal tool; V2 must also work for another Mac user and relocated home. |
| **UNCHANGED FROM V1 — periodic restartable tick** | Scheduler runs reconciliation; V2 removes long shared locks and adds independent health observation. |
| **UNCHANGED FROM V1 — retained closed workspaces** | Continuity after close-out; V2 formalizes explicit deletion. |
| **UNCHANGED FROM V1 — exact continuation input** | Preserve exact kickoff/ruling/follow-up text; V2 does so privately before delivery. |
| **UNCHANGED FROM V1 — truthful check reporting** | Unrun checks are never passed; V2 adds independent, destination-bound evidence. |

All other contracts below are V2 contracts. V1 file-mailbox authority, project table protocol, fixed paths/branches, model-driven wake routing, global notification target, and historical CLI flags are not implicitly inherited. Historical records do not authorize a V2 lane or prove a migration of a live session.

## 2. ARCHITECTURE

### 2.1 Components and communication

```text
Person / local tools                 macOS notification response
        | command/query                        | notification ID
        v                                      v
   CLI + native attention presenter / typed command boundary
        | validated data + expected revision
        v
   Swift semantic core <---------------- bounded reconciliation tick
    | intake, graph, lifecycle, ownership              ^
    | admission, recovery, verification                | health
    v                                                  | observation
   SQLite current state + audit + inbox/outbox    independent watchdog
        | pending durable intents     | references
        v                             v
   Effect workers               private objects / retained workspaces
    |         |        |        prompts, evidence, checkpoints, profiles
    |         |        +------ macOS host adapter: notify/process/schedule
    |         +--------------- preparation/check/integration executor
    +------------------------- Claude Code adapter / Codex adapter
                                      |
                                managed sessions
                                      |
                           scoped reports / result observations
                                      +--------> transactional inbox
```

No target-side service or HTTP API server is required. Structured CLI input is the local public boundary; a private report spool permits durable retry. Adapters feed reports/observations through the same receiver. Notification clicks resolve their own IDs, never the newest session globally.

| Component | Responsibility |
|---|---|
| Command/query boundary | Validate versioned inputs, identities/revisions, persist commands, render durable results; no shell interpolation. |
| Intake/graph | Discover sources and actual project identity, capture provenance, request managed interpretation when needed, validate graph and authorized scope. |
| Swift semantic core | Pure typed decisions over validated state/observations, returning transitions, explanations, effect intents. One finite lifecycle taxonomy. |
| Run store | Short SQLite transactions, monotonic sequence, deduplication, authoritative ownership/reservations and audit. JSONL is diagnostic export only. |
| Object/workspace store | Immutable durable evidence, pinned profiles/releases, owned retained workspaces, integrity checks. Existence alone is not identity. |
| Reconciler | Ingest, observe and reconcile effects, maintain waits/incidents, schedule eligible operations; external calls never run inside a transaction. |
| Admission | One operation-specific result for starts, retries, resumes, replies, preparation, checks, integration, and follow-ups; same function for preview. |
| Runtime adapters | Versioned capabilities, coherent environment, start/lookup/observe/input/stop/continuation/remote interfaces; runtime-specific parsing stays here. |
| Preparation executor | Consistent baseline capture, input/tool/service discovery, automatic setup, readiness and invalidation; cannot expand scope. |
| Verification/integration | Freeze candidates, independently execute fixed recipes, serialize combined-result verification and publication, journal per-file application. |
| Host adapter | Scheduler, deadlines/process observation, sleep assertions, host resource observations, notifications with addressed responses. |
| Independent watchdog | Observe useful reconciliation progress and scheduler state; raise local attention without restarting uncertain target work. |
| Maintenance | Immutable releases, compatibility checks/migrations, consistent backups/restores, explicit deletion, permanent retired-namespace fences. |

### 2.2 Durable effects

Before any effect: durably store its required objects; transactionally validate authority/revision, reserve resources, record exact intent and input references, update state; commit; then execute. Acknowledgement/observations commit afterward. A lost reply or timeout does not prove the effect failed.

Message bytes, logical digest, receipt disposition, resulting transition and outbox intents commit together. File moves do not determine consumption. Retransmission with the same ID and same parsed envelope returns the original receipt without consequences, independent of JSON formatting. A changed logical envelope under that ID is a conflict. Retain each submission's exact raw bytes separately. Producer timestamps are descriptive, not ordering or identity, but changing one in a retransmission changes that envelope and is a conflict.

Worker claims have controller epoch and expiry. Claim expiry authorizes reconciliation by another worker, not external replay. Resource reservations survive missing fleet rows, elapsed time, or controller restarts. Replay requires native idempotency with the same operation ID or authoritative evidence the prior effect did not occur. Otherwise preserve uncertainty and obtain an explicit evidence-based resolution.

Use durable SQLite transactions, foreign keys, uniqueness constraints, bounded busy waits and short readers on the local filesystem. Never disable durability for speed. WAL is optional; if selected it requires measured reader behaviour and correct checkpoint/backup handling. Database sequence/revision orders accepted decisions. No Git, runtime, file-copy, notification or network operation occurs inside a state transaction.

### 2.3 Reconciliation and health

A pass records `started`, claims bounded due work, and independently processes receipts, effect reconciliation, runtime/host observations, ownership, preparation invalidation, waits/incidents, graph/dependency admission, verification/application queues, delivery, and process cleanup. Component failures isolate dependent projects/profiles. Unreadable authority/resource state holds effects depending on it; optional quota failure does not.

Peer context includes committed reservations from the current batch. Every non-admission has a structured reason. End the pass as `completed`, `partial`, or `failed` with component freshness. A fresh PID/start timestamp is not proof of useful progress. Long productive sessions are observed on subsequent passes rather than awaited inside a tick.

Control/probe calls have finite wall-clock deadlines and bounded outputs. Caller termination does not prove descendants stopped. Productive work has no default total-work timer. Engine timing settings are versioned and visible; deadline tuning cannot turn into a user budget prerequisite.

## 3. DATA MODEL

### 3.1 Types, shared fields and persistence

This is the complete logical model; implementations may normalize storage without changing its meaning. All entities below persist in `H/state.sqlite` unless a different location is specified. `H` is resolved from the host configuration, default `~/.baton`. V2 detects incompatible state and never interprets V1 files as V2 authority.

`ID` = opaque UUID, never a name/path/native session ID/timestamp. `Rev` and `Seq` = nonnegative signed 64-bit integers, represented as decimal strings in JSON. `Instant` = RFC 3339 UTC. `Duration` = nonnegative integer milliseconds. `Digest` = lowercase SHA-256 of exact bytes. `Path` = absolute local path; `RelPath` = relative, without traversal or absolute components. `Text`, `Bool`, `Int`, `Bytes`, `T?`, `[T]`, `Map<Text,T>` mean string, boolean, integer, raw byte sequence, nullable, array, and map. Bytes use SQLite BLOB internally and base64 when explicitly exported as JSON. Missing required fields are invalid; null is not zero. Unrecognized enums are invalid for protocol 2.

Every database entity has `id:ID`, `recordVersion:Int`, `revision:Rev`, `createdAt:Instant`, `updatedAt:Instant`, `createdSeq:Seq`, `updatedSeq:Seq`, **in addition to** its listed fields. Initial recordVersion is 1. Mutable updates increment revision and add AuditEvent in the same transaction; immutable records never update. Fields named `…Id` reference the stated entity, enforced by type/foreign key. `ObjectRef` is an Object ID whose digest is verified before use.

`Scope` is one tagged form: `controller`, `project(projectId)`, `run(runId)`, `unit(unitId)`, `execution(executionId)`, `operation(operationId)`, `profile(profileId)`, `resource(resourceId)`, `attention(attentionId)`, `conversation(conversationId)`, `budget(budgetId)`, `release(releaseId)`, or `unassigned`. Its JSON encoding is `{kind:Text,id:ID|null}`, with null only for controller/unassigned; kind is one of these literal tags. `Reason = {code:FailureCode, summary:Text, detailObject:ObjectRef?, prerequisiteRefs:[ID], retryable:Bool}`. FailureCode is defined in section 8; descriptive details cannot introduce new lifecycle semantics.

| Location | Contents |
|---|---|
| `H/state.sqlite` and SQLite companions | Authoritative entities, mode 0600. |
| `H/objects/<object-id>` | Immutable exact bytes, mode 0600, durable before DB reference. |
| `H/workspaces/<workspace-id>/` | Retained owned workspace, root 0700; required file executable bits preserved. |
| `H/releases/<release-id>/` | Immutable installed core/adapters/resources. |
| `H/current` | Atomic active release selection reconciled with Controller. |
| `H/profiles/<profile-id>/<revision>/` | Private generated settings, pinned by digest and execution. |
| `H/spool/reports/<submission-id>.json` | Immutable reports pending durable receipt; `.tmp` means unpublished staging. |
| `H/tmp/<operation-id>/` | Disposable execution temporaries; evidence is promoted before cleanup. |
| `H/diagnostics/` | Bounded redacted diagnostics, not authoritative or retained evidence. |
| User-selected backup path | Consistent database, referenced objects/workspaces, integrity manifest; no credential values. |

Private directories are 0700 independent of umask. Reject unexpected state-root symlink substitution. Secrets resolve privately by reference, never public JSON, telemetry, notifications or argv. Exact user prompts are private even when they contain confidential text; redaction cannot guarantee arbitrary prose is secret-free. These modes do not contain unrestricted same-user host code.

### 3.2 Work and authorization entities

| Entity | Fields beyond shared fields | Meaning / invariant |
|---|---|---|
| Controller | `epoch:ID`, `activeReleaseId:ID`, `schemaVersion:Int`, `protocolVersions:[Int]`, `intent:ControlIntent`, `configurationId:ID`, `lastPassId:ID?`, `restoreId:ID?` | Restore creates a new epoch and fences older execution authority. |
| EngineConfiguration | `controlDeadline:Duration`, `probeDeadline:Duration`, `queryDeadline:Duration`, `tickInterval:Duration`, `watchdogThreshold:Duration`, `backoffInitial:Duration`, `backoffMaximum:Duration`, `burstLimit:Int`, `freshness:Map<Text,Duration>`, `checkpointInterval:Duration`, `pressurePolicy:ObjectRef` | Positive finite deadlines/intervals and burst limit; max backoff >= initial. Engine settings, not lifetime work budgets. |
| Project | `displayName:Text`, `location:Path`, `locationRevision:Rev`, `identityKind:git\|directory\|unresolved`, `identityEvidence:ObjectRef`, `gitCommonDirectory:Path?`, `selectedRootRelative:RelPath?`, `status:active\|retiring\|retired`, `retiredAt:Instant?` | Stable across reconciled move; names/remotes alone cannot unify identity. Unresolved records retain access/discovery evidence and cannot authorize target writes. Nested selection does not widen scope. |
| Source | `projectId:ID`, `kind:request\|file\|url\|session\|discovery`, `locator:Text`, `content:ObjectRef`, `capturedAt:Instant`, `sourceRevision:Text?`, `digest:Digest`, `authority:user_request\|user_ruling\|project_instruction\|context`, `accessProfileId:ID?` | Immutable source snapshot/provenance. Locator is data. |
| Run | `projectId:ID`, `requestSourceId:ID`, `sourceIds:[ID]`, `graphRevisionId:ID?`, `authorizationId:ID`, `runtimePolicy:RuntimePolicy`, `state:RunState`, `intent:ControlIntent`, `owner:Ownership`, `resultIds:[ID]`, `attentionIds:[ID]`, `closedAt:Instant?` | One requested outcome; fresh productive follow-up has its own run. |
| Authorization | `runId:ID`, `sourceIds:[ID]`, `scopeText:Text`, `restrictions:[Text]`, `reservedActions:[Text]`, `applicationMode:automatic_local\|patch_only`, `allowedRuntimes:[RuntimeKind]`, `secretReferenceIds:[ID]`, `remoteOptIn:Bool`, `budgetIds:[ID]` | Versioned snapshot. Empty budget list means no budget, not zero capacity. |
| WorkGraphRevision | `runId:ID`, `number:Rev`, `previousId:ID?`, `unitDefinitionIds:[ID]`, `dependencies:[Dependency]`, `gates:[Gate]`, `sourceIds:[ID]`, `commandId:ID?`, `proposalId:ID?`, `digest:Digest` | Immutable accepted graph; unique references, acyclic, no self-edge, gate authority required. |
| WorkUnit | `runId:ID`, `definitionId:ID`, `state:UnitState`, `intent:ControlIntent`, `owner:Ownership`, `activeAttemptId:ID?`, `acceptedResultId:ID?`, `requiredApplication:Bool`, `incidentIds:[ID]`, `closedAt:Instant?` | Stable across revisions and attempts. |
| UnitDefinition | `unitId:ID`, `graphRevisionNumber:Rev`, `title:Text`, `objective:Text`, `scope:[Text]`, `sourceIds:[ID]`, `contextObjects:[ObjectRef]`, `acceptanceRecipeId:ID`, `destinationId:ID`, `resourceRequirements:[ResourceRequirement]` | Immutable dispatch contract, exact context. |
| GraphProposal | `runId:ID`, `expectedGraphRevision:Rev`, `proposedDefinitions:ObjectRef`, `sourceIds:[ID]`, `executionId:ID?`, `commandId:ID?`, `state:pending\|accepted\|rejected\|superseded`, `reason:Reason?` | In-scope/unambiguous changes can apply automatically; expansion/conflict needs ruling. |
| Destination | `projectId:ID`, `kind:git_ref\|checkout\|directory\|patch`, `location:Path`, `gitRef:Text?`, `identityEvidence:ObjectRef`, `locationRevision:Rev`, `sourceId:ID` | Selected actual destination, never guessed main. Internal ref alone is not application to requested checkout. |
| Ruling | `attentionId:ID?`, `commandId:ID`, `scope:Scope`, `text:ObjectRef`, `kind:answer\|scope_change\|waiver\|ownership\|uncertainty_resolution`, `evidenceIds:[ID]`, `dependencyScope:[ID]`, `expectedRevision:Rev` | Immutable explicit user decision; waiver names missing guarantee and affected dependencies. |

`RuntimeKind = claude_code | codex`. `RuntimePolicy = {preferred:RuntimeKind, selectionSource:default|explicit, fallback:claude_exhaustion_to_codex|none}`. Default is Claude with exhaustion fallback. An explicit runtime-only choice suppresses automatic switching; additional explicit authority can change that policy.

`ControlIntent = run | pause | drain | cancel`. Ancestor restrictions intersect child intent; a child cannot unpause its parent. `Ownership = {mode:baton|human|uncertain, commandId:ID?, observationId:ID?, changedAt:Instant}`; human ownership does not expire.

`Dependency = {id:ID, predecessorId:ID, successorId:ID, required:accepted_result|applied_result, artifactSelectors:[RelPath], acceptedWaiverIds:[ID]}`. Empty selectors means the whole accepted result. `Gate = {id:ID, unitIds:[ID], criterion:Text, authoritySourceIds:[ID], state:open|satisfied, evidenceIds:[ID], rulingId:ID?}`. Gates are conditions with evidence, not arbitrary project strings impersonating user decisions.

### 3.3 Workspace, runtime, and execution entities

| Entity | Fields beyond shared fields | Meaning / invariant |
|---|---|---|
| Object | `kind:prompt\|source\|report\|output\|snapshot_manifest\|checkpoint\|settings\|evidence\|diagnostic\|backup_manifest`, `path:Path`, `digest:Digest`, `byteLength:Int`, `mediaType:Text`, `retention:retained\|disposable`, `integrity:unchecked\|valid\|missing\|changed`, `deletedByMaintenanceId:ID?` | Bytes live in object store, metadata in DB. Referenced retained content cannot silently become disposable. |
| Baseline | `projectId:ID`, `sourceLocationRevision:Rev`, `kind:git\|snapshot`, `gitCommit:Text?`, `gitRef:Text?`, `manifest:ObjectRef`, `dirtyManifest:ObjectRef`, `capturedAt:Instant`, `consistencyEvidence:ObjectRef`, `parentResultIds:[ID]` | Immutable actual selected state, including relevant uncommitted/untracked inputs separately from Git history. |
| Workspace | `projectId:ID`, `runId:ID`, `baselineId:ID`, `path:Path`, `kind:worktree\|clone\|copy`, `gitIdentity:ObjectRef?`, `branch:Text?`, `purpose:preparation\|coding\|verification\|integration\|followup`, `ownerExecutionId:ID?`, `state:creating\|preparing\|ready\|in_use\|reconciling\|closed\|quarantined\|deleted`, `preparationId:ID?`, `inventory:ObjectRef`, `closedAt:Instant?` | Opaque managed path. Reuse proves project/workspace/baseline/ownership and current inventory. |
| Preparation | `workspaceId:ID`, `inputDigest:Digest`, `instructionSourceIds:[ID]`, `recipe:ObjectRef`, `capabilities:[Readiness]`, `activityIds:[ID]`, `serviceIds:[ID]`, `inputBindings:[InputBinding]`, `state:discovered\|running\|ready\|waiting\|invalidated\|failed`, `reason:Reason?` | Reuse only while relevant tools/configuration/inputs/services still match. |
| Service | `workspaceId:ID`, `resourceId:ID`, `startOperationId:ID`, `processIdentity:ProcessIdentity?`, `endpoint:Text?`, `state:starting\|running\|stopping\|stopped\|uncertain`, `disposable:Bool`, `healthObservationId:ID?` | Track services Baton creates, use isolated instances/ports where possible. Do not stop unrelated host services. |
| SecretReference | `profileId:ID?`, `runId:ID?`, `resolver:Text`, `privateLocator:ObjectRef`, `purpose:Text`, `status:unresolved\|available\|unavailable\|revoked` | No secret value in entity; private locator does not export to ordinary backup. |
| RuntimeProfile | `runtime:RuntimeKind`, `binary:Path`, `binaryVersion:Text`, `configurationRoot:Path`, `accountIdentityId:ID`, `environmentPolicy:ObjectRef`, `effectiveSettings:ObjectRef`, `secretReferenceIds:[ID]`, `capabilityEvidenceIds:[ID]`, `state:usable\|degraded\|unavailable\|invalid`, `releaseId:ID` | Immutable revision pinned by execution. Environment is deliberately constructed, not blanket prefix deletion. |
| AccountIdentity | `runtime:RuntimeKind`, `provider:Text`, `providerAccountKey:Text?`, `accountingGroupId:ID`, `identityEvidence:ObjectRef?`, `identityConfidence:confirmed\|unknown` | Profiles are not necessarily different accounts. Unknown overlap grouped for accounting without manufacturing a hold. |
| CapabilityEvidence | `profileId:ID?`, `hostCapability:Text?`, `name:CapabilityName`, `support:available\|unavailable\|unknown`, `guarantee:Text`, `limitations:[Text]`, `capture:ObjectRef?`, `observedAt:Instant`, `validUntil:Instant?`, `environmentDigest:Digest` | Version/environment-specific proof. `unknown` is not supported. |
| Conversation | `runId:ID`, `runtime:RuntimeKind`, `profileId:ID`, `nativeId:Text?`, `parentConversationId:ID?`, `relation:original\|native_resume\|native_fork\|checkpoint_continuation\|followup\|import`, `purpose:preparation\|coding\|review\|followup`, `workspaceId:ID?`, `continuity:native\|checkpoint\|observe_only`, `availability:available\|unavailable\|unknown`, `contextObjects:[ObjectRef]` | Conversation lifetime differs from active process lifetime. Cross-runtime fallback is checkpoint_continuation. |
| Attempt | `unitId:ID`, `ordinal:Int`, `definitionId:ID`, `baselineId:ID`, `recipeId:ID`, `workspaceId:ID`, `conversationId:ID`, `state:open\|succeeded\|replaced\|failed\|cancelled`, `executionIds:[ID]`, `predecessorAttemptId:ID?`, `reason:Reason?` | Recipe is the baseline-bound immutable version of the definition's accepted recipe. New attempt does not reset unit incidents. |
| Execution | `runId:ID`, `unitId:ID?`, `attemptId:ID?`, `conversationId:ID`, `generation:Int`, `controllerEpoch:ID`, `profileId:ID`, `releaseId:ID`, `workspaceId:ID`, `purpose:preparation\|coding\|review\|followup`, `state:ExecutionState`, `owner:Ownership`, `launchOperationId:ID`, `promptObject:ObjectRef`, `nativeIdentity:NativeIdentity?`, `reservationIds:[ID]`, `reportGrantId:ID`, `lastObservationId:ID?`, `latestCheckpointId:ID?`, `endingMessageId:ID?`, `terminalReason:Reason?`, `terminatedAt:Instant?` | Each successful start/resume has a new generation even if native ID is unchanged. Pending generation is allocated before effect; it becomes running only with evidence. |
| ReportGrant | `executionId:ID`, `controllerEpoch:ID`, `generation:Int`, `allowedKinds:[ReportKind]`, `privateBinding:ObjectRef`, `state:active\|retired`, `retiredSeq:Seq?` | Scoped accidental-misrouting/staleness protection, not same-user adversarial authentication. |
| Observation | `scope:Scope`, `operationId:ID?`, `executionId:ID?`, `kind:runtime\|process\|progress\|actor\|capability\|quota\|resource\|destination\|integrity`, `value:ObjectRef`, `observedAt:Instant`, `receivedAt:Instant`, `freshness:current\|stale\|unknown`, `confidence:authoritative\|inferred\|unknown`, `adapterVersion:Text` | Immutable. Missing data remains unknown; one absent fleet row does not prove death. |
| Checkpoint | `executionId:ID`, `definitionId:ID?`, `baselineId:ID`, `inventory:ObjectRef`, `summary:ObjectRef`, `decisionIds:[ID]`, `verificationIds:[ID]`, `unfinishedActionIds:[ID]`, `contextSources:[ObjectRef]`, `trigger:periodic\|boundary\|pause\|failure\|handoff\|operator`, `completeness:complete_inventory\|partial`, `capturedAt:Instant` | Records accessible state, not hidden model memory. Partial inventory is explicit. |
| UnfinishedAction | `executionId:ID`, `operationId:ID?`, `description:Text`, `effectScope:Text`, `evidenceIds:[ID]`, `state:pending\|in_progress\|occurred\|not_occurred\|uncertain\|resolved`, `resolutionRulingId:ID?` | Uncertain side effects must be reconciled before repetition. |

`Readiness = {name:Text, state:ready|missing|unknown|invalidated, requiredFor:[OperationKind], evidenceIds:[ID], reason:Reason?}`. Preparation must not require coding-readiness before it can prepare coding-readiness. `InputBinding = {source:InputSource, destination:RelPath, purpose:Text, capturedDigest:Digest?, copyPolicy:private_copy|reference|generated, evidenceIds:[ID]}` where `InputSource = {kind:path,path:Path} | {kind:secret,secretReferenceId:ID} | {kind:generated,operationId:ID}`; external symlink targets and ignored trees require deliberate discovered bindings rather than wholesale copying.

`ProcessIdentity = {pid:Int, startedAt:Instant, hostBootId:Text, nativeJobId:Text?}`; PID alone is insufficient. `NativeIdentity = {nativeSessionId:Text, nativeJobId:Text?, process:ProcessIdentity?, operationKey:Text?}`. CapabilityName is one of `start`, `operation_lookup`, `native_idempotency`, `observe`, `report`, `input`, `stop`, `termination_proof`, `native_resume`, `native_fork`, `actor_attribution`, `mediated_ownership`, `remote_access`, `quota`, `descendants`, `effective_settings`, `notification_delivery`, `snapshot`, `exclusive_application`.

### 3.4 Commands, handoffs, and effect entities

| Entity | Fields beyond shared fields | Meaning / invariant |
|---|---|---|
| Command | `commandId:ID`, `kind:CommandKind`, `scope:Scope`, `expectedRevision:Rev?`, `payload:ObjectRef`, `digest:Digest`, `state:accepted\|rejected\|pending\|completed\|uncertain\|cancelled`, `result:ObjectRef?`, `operationIds:[ID]`, `reason:Reason?` | Unique commandId and canonical logical request digest; retries preserve value/identity. Completed means command disposition settled, not necessarily run complete. |
| Submission | `submissionId:ID`, `messageId:ID?`, `raw:ObjectRef`, `digest:Digest`, `receivedAt:Instant`, `receiptId:ID` | Every received submission, including malformed bytes, is retained under its own immutable identity. |
| Message | `messageId:ID`, `protocol:Int`, `executionId:ID`, `generation:Int`, `controllerEpoch:ID`, `kind:ReportKind`, `payload:ObjectRef`, `envelopeBytes:Bytes`, `digest:Digest`, `writtenAt:Instant`, `receiptId:ID` | First accepted envelope bytes and canonical logical digest commit with receipt; Submission retains every raw encoding. Explicit body deletion replaces this with a tombstone, not an empty valid message. |
| Receipt | `submissionId:ID`, `messageId:ID?`, `disposition:accepted\|duplicate\|rejected\|conflict\|stale`, `originalReceiptId:ID?`, `reason:Reason?`, `handoffId:ID?`, `transitionSeq:Seq?`, `operationIds:[ID]` | Immutable, unique original receipt per accepted logical message ID. Duplicate receipt references original, no new effects. |
| Handoff | `executionId:ID`, `endingMessageId:ID`, `definitionId:ID`, `baselineId:ID`, `checkpointId:ID?`, `candidateId:ID?`, `state:HandoffState`, `verificationId:ID?`, `resultId:ID?`, `integrationId:ID?`, `successorOperationIds:[ID]`, `reason:Reason?` | One semantic close-out proposal for that ending/generation, not authority over successors. |
| Operation | `kind:OperationKind`, `scope:Scope`, `commandId:ID?`, `messageId:ID?`, `executionId:ID?`, `controllerEpoch:ID`, `input:ObjectRef`, `inputDigest:Digest`, `state:planned\|claimed\|in_progress\|observing\|succeeded\|failed\|uncertain\|cancelled`, `reservationIds:[ID]`, `claimOwner:ID?`, `claimExpiresAt:Instant?`, `deadline:Instant?`, `nativeIdempotencyKey:Text?`, `nativeLookupKey:Text?`, `result:ObjectRef?`, `reason:Reason?`, `predecessorOperationId:ID?` | Effects execute outside transaction after committed intent. Wall deadline is paired with in-process monotonic elapsed timer. |
| Resource | `scope:Scope`, `kind:project_writer\|workspace\|destination\|account\|host_capacity\|port\|database\|device\|service`, `identity:Text`, `capacity:Int?`, `observationId:ID?` | Unknown resource effects serialize work within affected project. |
| Reservation | `operationId:ID`, `executionId:ID?`, `resourceId:ID`, `mode:exclusive\|shared`, `quantity:Int`, `state:reserved\|active\|uncertain\|released`, `releasedByObservationId:ID?`, `releaseReason:Text?` | Pending and uncertain starts, waiting live sessions and replacement overlap count. No time-only release. |
| AdmissionDecision | `operationKind:OperationKind`, `scope:Scope`, `expectedGraphRevision:Rev?`, `allowed:Bool`, `reasons:[AdmissionReason]`, `reservationIds:[ID]`, `dependencyResultIds:[ID]`, `profileId:ID?`, `evaluatedAt:Instant`, `preview:Bool` | Actual verdict persisted; preview is an ephemeral query value with no entity write. |
| Incident | `unitId:ID?`, `scope:Scope`, `fingerprint:Digest`, `cause:Reason`, `state:active\|open_circuit\|probing\|attention\|resolved`, `ineffectiveCount:Int`, `actionHistory:[ID]`, `lastProgressObservationId:ID?`, `nextProbeAt:Instant?`, `resolutionEvidenceIds:[ID]` | Across attempts; productive progress or repaired-cause evidence closes, process start alone does not. |
| Wait | `incidentId:ID`, `scope:Scope`, `cause:Reason`, `dueAt:Instant?`, `state:scheduled\|claimed\|observing\|cancelled\|satisfied`, `recoveryOperationId:ID?`, `resetEvidenceId:ID?` | Due wait creates one operation; accepted delivery cancels timer and changes to observing. |
| QuotaObservation | `accountIdentityId:ID`, `limitScope:Text`, `allocationExhausted:Bool?`, `remaining:Text?`, `resetAt:Instant?`, `observedAt:Instant`, `expiresAt:Instant?`, `sourceEvidence:ObjectRef`, `confidence:confirmed\|unknown` | Native units retained. No alias-based or two-model account inference. |
| UserBudget | `scope:Scope`, `kind:cost\|tokens\|elapsed\|concurrency\|resource`, `limit:Text`, `unit:Text`, `sourceRulingId:ID`, `enforcement:provider\|observed_local`, `limitations:[Text]`, `state:active\|removed` | Exists only after explicit request; telemetry limits are disclosed. |

`ReportKind = checkpoint | question | candidate | stopped | progress | graph_proposal`. `OperationKind = capture | prepare | start | resume | deliver | stop | observe | verify | integrate | apply | checkpoint | notify | probe | adopt | release | backup | restore | delete | migrate`. `ResourceRequirement = {kind:Resource.kind, identity:Text, mode:exclusive|shared, quantity:Int, sourceIds:[ID], discovered:Bool}`.

`AdmissionReason = {code:dependency|gate|ownership|intent|resource|capability|policy|uncertain_effect|integrity|preparation|quota|revision|destination|retired, blockingId:ID?, summary:Text, recheckCondition:Text}`. A quota reading that is merely unknown does not create a blocking quota reason.

### 3.5 Verification, application, attention, and maintenance entities

| Entity | Fields beyond shared fields | Meaning / invariant |
|---|---|---|
| VerificationRecipe | `definitionId:ID`, `baselineId:ID?`, `criteria:[Criterion]`, `checks:[CheckSpec]`, `sourceIds:[ID]`, `digest:Digest`, `supersedesId:ID?`, `changeProposalId:ID?` | Fixed before coding dispatch; later change uses reviewed proposal, never silently adopted from candidate. |
| Candidate | `handoffId:ID`, `executionId:ID`, `definitionId:ID`, `baselineId:ID`, `snapshotId:ID`, `diff:ObjectRef`, `changedPaths:[RelPath]`, `explanation:ObjectRef`, `claimEvidenceIds:[ID]`, `noChange:Bool`, `frozenAt:Instant` | Frozen snapshot is a Baseline entity rooted in owned output. Candidate never directly merges destination. |
| Verification | `candidateId:ID`, `recipeId:ID`, `workspaceId:ID`, `combinedBaselineId:ID?`, `checkResults:[CheckResult]`, `reviewExecutionIds:[ID]`, `criterionResults:[CriterionResult]`, `state:pending\|running\|passed\|failed\|unavailable\|waived\|cancelled`, `waiverIds:[ID]`, `evidenceIds:[ID]` | Independent of coding process; combined result tied to exact destination base. |
| AcceptedResult | `unitId:ID`, `candidateId:ID`, `verificationId:ID`, `snapshotId:ID`, `definitionId:ID`, `level:verified\|waived`, `waiverIds:[ID]`, `dependencyScope:[ID]`, `acceptedSeq:Seq` | Immutable acceptance fact. Waived is never rendered verified. |
| Integration | `resultId:ID`, `destinationId:ID`, `expectedDestination:ObjectRef`, `combinedSnapshotId:ID?`, `verificationId:ID?`, `operationId:ID`, `state:queued\|composing\|verifying\|ready\|applying\|uncertain\|conflicted\|applied\|failed\|cancelled`, `applicationEntryIds:[ID]`, `observedDestination:ObjectRef?`, `reason:Reason?` | Exclusive queue per actual destination across all runs. Recompose/reverify when base changes. |
| ApplicationEntry | `integrationId:ID`, `relativePath:RelPath`, `action:add\|replace\|delete\|rename\|metadata`, `sourcePath:RelPath?`, `before:ObjectRef?`, `after:ObjectRef?`, `expectedBeforeDigest:Digest?`, `expectedAfterDigest:Digest?`, `state:planned\|applied\|not_applied\|uncertain\|conflicted\|restored`, `evidenceIds:[ID]` | Per-path durable before/after and reconciliation; null digest represents absence, not unreadability. |
| Attention | `scope:Scope`, `cause:Reason`, `question:ObjectRef?`, `state:open\|resolving\|resolved\|dismissed`, `availableCommands:[CommandKind]`, `relatedIds:[ID]`, `resolutionCommandId:ID?`, `resolutionEvidenceIds:[ID]` | Stable ID usable even for unassigned/projectless failures; dismissal cannot waive a blocker. |
| Notification | `attentionId:ID`, `transport:macos\|native_remote\|independent`, `payload:ObjectRef`, `state:intended\|queued\|accepted\|failed\|acted`, `deliveryOperationIds:[ID]`, `transportReceipt:Text?`, `actionCommandId:ID?`, `lastFailure:Reason?` | Intent, OS acceptance, transport failure, and observed operator action are distinct. |
| AuditEvent | `sequence:Seq`, `scope:Scope`, `entityId:ID`, `fromRevision:Rev?`, `toRevision:Rev`, `transition:Text`, `commandId:ID?`, `messageId:ID?`, `operationId:ID?`, `evidenceIds:[ID]`, `summary:Text` | Append-only control audit, not event-replay authority. |
| ReconciliationPass | `controllerEpoch:ID`, `state:started\|partial\|failed\|completed`, `startedAt:Instant`, `endedAt:Instant?`, `components:[ComponentHealth]`, `lastUsefulProgressAt:Instant?` | Each component has its own completion/error/freshness. |
| WatchdogObservation | `passId:ID?`, `schedulerLoaded:Bool?`, `lastUsefulProgressAt:Instant?`, `state:healthy\|late\|stuck\|unloaded\|unknown`, `evidence:ObjectRef`, `attentionId:ID?` | Local independent health, not off-host guarantee. |
| Release | `version:Text`, `path:Path`, `manifest:ObjectRef`, `digest:Digest`, `readSchemas:[Int]`, `writeSchema:Int`, `protocols:[Int]`, `adapterVersions:Map<Text,Text>`, `state:staged\|active\|retained\|retired` | Remains while pinned; incompatible rollback refused. |
| Maintenance | `kind:backup\|restore\|migrate\|delete\|relocate\|retire`, `scope:Scope`, `commandId:ID`, `state:planned\|running\|reconciling\|completed\|failed\|uncertain`, `manifest:ObjectRef?`, `sourcePath:Path?`, `destinationPath:Path?`, `newControllerEpoch:ID?`, `affectedIds:[ID]`, `reason:Reason?` | Durable external maintenance intent and reconciliation. |
| Tombstone | `namespace:controller_epoch\|execution\|message\|command\|project`, `retiredIdentity:Text`, `digest:Digest?`, `terminalDisposition:Text`, `retiredSeq:Seq`, `maintenanceId:ID?` | Minimal non-reusable identity retained even after authorized body deletion. |

`Criterion = {id:ID, description:Text, method:deterministic|review|human_observation, required:Bool, checkIds:[ID], sourceIds:[ID]}`. `CheckSpec = {id:ID, argv:[Text], cwd:RelPath, environmentRef:ObjectRef, successExitCodes:[Int], evidencePaths:[RelPath], applicability:Text, requiredCriterionIds:[ID]}`. Commands are argv, not shell source; explicitly discovered script commands can invoke the appropriate interpreter as an argument-vector operation.

`CheckResult = {checkId:ID, operationId:ID, testedSnapshotId:ID, state:passed|failed|unrun|unavailable|cancelled, exitCode:Int?, output:ObjectRef?, baselineResultRef:ID?, classification:baseline_failure|introduced_failure|unchanged_failure|success|unknown}`. `CriterionResult = {criterionId:ID, state:satisfied|unsatisfied|unobserved|waived, evidenceIds:[ID], rulingId:ID?}`. `ComponentHealth = {name:Text, scope:Scope, state:completed|failed|skipped|pending, observedAt:Instant?, reason:Reason?}`. Ephemeral query composites below persist only if explicitly exported; they are not another source of state.

### 3.6 Snapshot and identity rules

A snapshot manifest is an ordered list of `{path:RelPath, kind:file|directory|symlink, digest:Digest?, objectId:ID?, mode:Int, symlinkTarget:Text?, size:Int}` with `{format:2, projectId:ID, capturedFrom:Path, sourceIdentity:ObjectRef, entries:[…], exclusions:[{path:RelPath, reason:Text}], consistencyEvidence:ObjectRef}`. Directory digest is null. Symlink entries preserve link text without following external targets implicitly. Non-regular devices/sockets are not copied as source files; required services/devices become discovered input/resource bindings.

Capture relevant source and user dirty/untracked changes without blindly copying ignored trees, secrets, caches or external links. Detect changes during capture by filesystem observations and repeated inventory comparison or a supported consistent snapshot primitive. An unstable capture is `waiting` for stable input, never `ready`. Filenames, modes, binary contents, case sensitivity and Unicode identity must survive capture; if the destination filesystem cannot represent them, retain the original snapshot and report the exact collision.

A move updates Project.location only after identity reconciliation against retained evidence. Same basename, same remote URL, or matching commit alone is insufficient to merge two independently selected copies. An ambiguous move needs a specific identity ruling. Existing arbitrary directories cannot become workspaces merely by passing `git rev-parse`.

## 4. STATE TRANSITIONS

### 4.1 Transition discipline

Every transition checks current entity revision, controller epoch, applicable graph definition, ownership and parent intents. It commits state, AuditEvent, receipts, reservations and outbox intents atomically where applicable. The effect itself occurs afterward. A failed guard returns a typed rejection without changing state. Unlisted transitions are forbidden. Updating an observation, checkpoint or explanatory reason without changing lifecycle state is a recorded self-transition; it does not repeat a prior effect.

Terminal records never reopen. A later request creates a linked run/attempt/execution as appropriate. A duplicate report returns its receipt even after closure; a novel report from a retired generation is stale and cannot affect current work. A terminal execution and terminal work unit are different facts. Execution termination may precede acceptance or integration; a accepted work result may coexist briefly with process cleanup, whose reservation remains until proven terminated.

### 4.2 Run lifecycle

`RunState = intake | active | waiting | attention | paused | draining | cancelling | completed | completed_with_waiver | failed | cancelled`.

| From | Trigger / guard | To and required action |
|---|---|---|
| Absent | Valid intake command and accessible location or actionable access failure | `intake`: create Project/Run/request/authorization; discovery intents or an addressed access attention. No model launch before intent. |
| `intake` | Sources understood, valid authorized graph accepted | `active`: persist graph and immutable definitions; prepare/admit ready work. |
| `intake` / `active` | All productive next actions wait on observable prerequisite | `waiting`: preserve graph and reasons; schedule probes for transient causes. |
| Any nonterminal except `cancelling` | Missing user fact/authority, unreconcilable ambiguity, exhausted meaningful recovery paths | `attention`: durable addressed item; independent unaffected units can still progress. |
| `waiting` / `attention` | Actual prerequisite/ruling resolved and permitted work exists | `active` or `intake` if graph not yet accepted: reevaluate, never unconditional dispatch. |
| Any nonterminal except `cancelling` | Pause command | `paused`: apply pause intention to scope, request safe checkpoint/quiescence where supported; no new productive actions. Observe remaining processes. |
| Any nonterminal except `cancelling` | Drain command | `draining`: no new coding/preparation/review executions; already admitted activities may settle and produce evidence/application under existing authority. |
| `draining` | All currently admitted work/effects settled and no execution active | `paused`: preserve remaining queued graph. If all required outcomes completed, complete instead. |
| `paused` / `draining` | Continue command and ancestor intents permit | `active` or `intake`: revalidate sources, readiness, ownership, resources, unresolved effects. |
| Any nonterminal | Cancel command | `cancelling`: suppress automatic recovery/starts, cancel unissued productive intents, stop only Baton-controlled execution, reconcile issued effects. |
| `cancelling` | All controlled execution/effects are settled, no unknown side effect is hidden | `cancelled`: retain work, partial application, evidence and human-owned residuals explicitly. An unresolved human/uncertain active execution keeps cancellation pending. |
| `active` / `waiting` / `attention` / `paused` / `draining` | Accepted graph exists, every required unit completed, requested applications settled, no active/uncertain required effects | `completed` or `completed_with_waiver`: summary includes results and verification levels. |
| Nonterminal except `cancelling` | Required objective is confirmed nonrecoverable and controlled processes/effects settled | `failed`: report exact unmet objectives; no automatic retry. If a meaningful recovery remains, use wait/attention instead. |

Terminal run states are **completed, completed_with_waiver, failed, cancelled**. A failed/cancelled dependency does not silently cancel siblings. Its dependents wait with a dependency reason while independent authorized work can finish; if the required overall objective is confirmed impossible, the run can fail after settling executions. A user may revise scope through an explicit graph proposal/ruling rather than relabel a failure as success.

### 4.3 Work-unit and attempt lifecycle

`UnitState = defined | blocked | preparing | ready | executing | waiting | attention | verifying | accepted | applying | completed | completed_with_waiver | failed | cancelled | superseded`.

| From | Trigger | To / action |
|---|---|---|
| Absent | Accepted graph introduces unit | `defined`, with fixed objective/recipe/source references. |
| `defined` / `ready` / `waiting` / `attention` | Dependency, gate, intent or resource guard not satisfied | `blocked` for graph/intent guards, `waiting` for recoverable runtime/resource prerequisites, `attention` for required ruling. Preserve actionable reason. |
| `defined` / `blocked` / `ready` / `waiting` / `attention` | Preparation needed/invalidated and guards for it satisfied | `preparing`; reserve preparation activities. Preparation is allowed before coding readiness. |
| `preparing` | Required preparation and baseline checks pass | `ready`; recipe and actual baseline are fixed before coding. |
| `preparing` | Setup failure or unavailable prerequisite | `waiting` for observable recovery, `attention` for required input/authority; retain completed setup evidence and unfinished effects. |
| `ready` | Coding start intent admitted | `executing`; create Attempt and pending Execution with prompt/profile/ownership/reservations before launch. |
| `executing` | Question, exhausted quota, recoverable stop, ambiguous effect | `attention` or `waiting`; preserve attempt and current execution facts. |
| `waiting` / `attention` | Existing attempt's authorized continuation/replacement admitted after cause resolved and coding readiness revalidated | `executing`; new execution generation or replacement attempt; incidents remain until progress. Without a prior coding attempt, use preparation then ready/start. |
| `executing` | Valid candidate ending frozen | `verifying`; Handoff created; coding claims do not close unit. |
| `verifying` | Verification fails with repair possible | `waiting` or `attention`; failed handoff closes as rejected, repair continuation uses evidence and new ending ID. |
| `verifying` | Required criteria passed or specifically waived | `accepted`; create immutable AcceptedResult, close successful attempt after its execution is terminal. |
| `accepted` | Requested application required and admission permits | `applying`; durable Integration intent and destination reservation. |
| `applying` | Conflict/partial/uncertain application | Remain `applying` with attention/wait reason until reconciliation, never complete. |
| `accepted` | Patch-only/no application requested | `completed` or `completed_with_waiver`; accepted result remains available. |
| `applying` | Requested destination state independently observed applied | `completed` or `completed_with_waiver`; dependency `applied_result` becomes satisfied. |
| Any nonterminal | Confirmed nonrecoverable objective, no meaningful recovery and all effects settled | `failed`; dependents see failure explicitly. |
| Any nonterminal | Cancellation intention and all controlled effects settled | `cancelled`; applied changes are retained, not automatically undone. |
| `defined` / `blocked` / `ready` / `waiting` / `attention` | Accepted graph revision replaces/removes this unit and no execution/effect is active or uncertain | `superseded`; link replacement definition/unit and retain prior history. |

Terminal unit states: **completed, completed_with_waiver, failed, cancelled, superseded**. Pause/drain are orthogonal ControlIntent, not additional success/failure states. A unit with active effects cannot be superseded until it has quiesced and the effects are reconciled. A new graph does not silently mutate a running UnitDefinition; unchanged units can retain their contract and changed units must explicitly transition at a safe boundary.

Attempt states: `open` starts before launch; `succeeded` requires accepted result and terminal contributing execution; `replaced` requires a recorded continuation link and proven predecessor quiescence; `failed` requires confirmed abandonment/nonrecoverability of that attempt; `cancelled` requires intentional cancellation and settlement. All except `open` are terminal. Replacement creates a new ordinal, retains baseline/workspace lineage and incident history. A failed launch may close an attempt without ever reaching a native running session.

### 4.4 Session/execution lifecycle

The product's “session” view displays Conversation plus its ordered Execution records. A conversation is retained context, not a slot or ownership lease.

`ExecutionState = reserved | starting | running | waiting_input | waiting_worker | waiting_provider | waiting_capability | checkpointing | recovering | stopping | uncertain | ended | stopped | failed | cancelled`.

| From | Trigger / evidence | To / durable action |
|---|---|---|
| Absent | Admitted start/resume with exact context and profile | `reserved`: allocate next generation, grant, prompt, launch operation and resource claims. |
| `reserved` | Worker claims and invokes recorded start/resume | `starting`; no second start on claim timeout. |
| `starting` | Authoritative launch acknowledgement/lookup binds unique identity | `running` for fresh start, `recovering` for a recovery resume; confirm generation and native identity, activate reservation. |
| `starting` | Definitive refusal with proof no execution began | `failed`; retire grant, release proven unused claims, incident/recovery evaluation. |
| `starting` | Lost ack, conflicting identity, timed-out call with possible live effect | `uncertain`; retain claims; lookup/observe only. |
| `running` / `recovering` / any waiting state | Explicit current-generation input question | `waiting_input`; create stable attention with exact question, owner still explicit. |
| `running` / `recovering` / any waiting state | Known outstanding worker/tool action | `waiting_worker`; track action; inspect progress without pretending it is a human question. |
| `running` / `recovering` / any waiting state | Supported provider-limit observation | `waiting_provider`; record actual account/limit scope, wait/probe and possible O8 fallback. |
| `running` / `recovering` / any waiting state | Permission, local dialog, required tool/hook unavailable | `waiting_capability`; report precise capability and specific resolution; remote setting does not suppress it. |
| Any live nonterminal | Actor/observation ambiguity prevents safe classification | `uncertain`; owner becomes uncertain where appropriate; no autonomous prompting/killing on silence alone. |
| `running` / any waiting state | Admitted checkpoint request | `checkpointing`; track request while retaining previous state as operation input. |
| `checkpointing` | Snapshot/checkpoint captured or bounded request conclusively failed | Prior observed live/wait state; retain partial checkpoint or incident. No default termination on checkpoint failure. |
| Any live nonterminal | Valid current-generation candidate/stopped ending and runtime turn ended | `ended`; retire productive reporting grant after accepted ending processing; retain slot until termination is separately observed. Runtime process may still be alive idle. |
| Any nonterminal except `reserved` | Authorized stop/cancel/replacement, safely established ownership | `stopping`; issue single stop intent; cancellation suppresses recovery. |
| `reserved` | Cancel before start was claimed/issued | `cancelled`; cancel operation and release unused resources. |
| `stopping` | Confirmed termination | `cancelled` for cancellation, otherwise `stopped`; retire grant, release execution/resource claims whose effects ended. |
| `stopping` | Timeout/unknown descendants | `uncertain`; preserve reservations and stop intent for reconciliation. |
| `running` / waiting / `recovering` / `checkpointing` | Confirmed crash or irrecoverable startup/runtime failure | `failed`; checkpoint available state; incident belongs to unit, not attempt. |
| `uncertain` | Authoritative observation settles identity/status/effect | Observed `running`, specific waiting state, `ended`, `stopped`, `failed`, or `cancelled`; settle reservations only on matching evidence. |
| waiting state | Wait resolved and runtime itself resumes existing uninterrupted turn | `running`; no synthetic generation or delivery. |

Terminal execution states: **ended, stopped, failed, cancelled**. Terminal means this generation cannot receive a productive Baton delivery or new ending. A later start/resume creates a distinct Execution, even under the same native conversation ID. A response delivered as a native resume therefore terminates/settles the waiting generation, records input intent, and creates the new generation as `reserved → starting → recovering` after accepted delivery; subsequent productive observation changes `recovering → running` and closes the incident. Where the runtime supports input to the same still-active turn, `waiting_input → recovering` is allowed with a deliver operation and unchanged generation; the adapter must distinguish this from resume explicitly.

Checkpoint periodically and at observable impending context/compaction/session boundaries. An adapter that cannot expose an impending boundary reports that limitation; periodic and observed-ending inventory capture still applies. Context exhaustion or an unfinished ending does not complete the unit: settle the generation, retain work and unresolved actions, and admit supported native continuation or a fresh same-runtime checkpoint continuation. A justified in-scope graph split is a revisioned proposal, not an unbounded automatic addition of tasks. Repeated unfinished/context failures without useful progress share the unit incident and its circuit breaker; they do not reset merely because a new context window exists. These causes do not authorize the Claude-to-Codex exhaustion fallback unless Claude usage allocation is separately confirmed exhausted.

An `ended` generation may leave an idle native process. Track cleanup as a stop operation with process observations without reopening the terminal generation; keep reservations until termination is confirmed. If a new generation reuses that reserved process, transactionally transfer its reservation, do not briefly free it. Native fork creates a new Conversation lineage record and execution; no stale hooks impose old unit obligations on follow-up work.

### 4.5 Ownership, pause, drain and cancellation

Explicit takeover changes owner to `human` before allowing native interaction through Baton's controls; pending unissued deliveries are cancelled. Already issued delivery can be uncertain and must be shown as such. Observed outside input also triggers human stand-off; absent/ambiguous actor evidence produces `uncertain`, never assumed Baton ownership. Human ownership survives missing rows, ended processes and restart. Hand-back names the exact scope and expected revision, reconciles external changes and unfinished actions, then restores Baton ownership and evaluates admission.

If the runtime cannot atomically order direct human input against delivery, expose that limitation before offering native interaction as protected. Baton-channel takeover/hand-back is the supported mediated path. No absolute non-overlap claim can be made for unmediated racing external input.

Pause stops admission of new productive actions and requests safe checkpoint/quiescence for Baton-owned active work. It does not immediately free reservations or kill a stalled process without evidence. Status says “pause requested; execution still active” until observed. Drain lets already admitted activities settle (including their queued verification/application) but starts no new model executions or successor units; if settling requires one, remain paused with that reason. Observations, receipts, stop/reconciliation, persistence and operator replies needed to settle ownership are allowed while paused/draining. Cancellation is sticky until terminal cancellation; it prevents automatic retry/fallback and does not roll back already applied work. Only explicit new work creates a continuation after terminal cancellation.

Retiring a project first prevents new requests/admission, preserves records and asks existing runs to drain. Project becomes retired when active ownership/effects settle. Explicit cancellation can shorten productive work but cannot waive uncertainty. History and closed workspaces remain; deregistration is not deletion.

### 4.6 Handoff lifecycle

A handoff is the processing of one candidate ending from a managed execution into accepted work and any required application/successor admission. Checkpoints and questions are reports but not completion handoffs. A coding session reports its own work; it does not publish authoritative successor dispositions or merge the user's checkout.

`HandoffState = received | validating | frozen | verifying | accepted | integrating | reconciling | attention | completed | completed_with_waiver | rejected | superseded | failed | cancelled`.

| From | Condition | To / action |
|---|---|---|
| No published message | Session is still writing `.tmp` or disconnected while staging | No Handoff yet. Preserve staged bytes; do not consume partial JSON or assume no work happened. |
| Absent | Schema-valid candidate envelope bound to active grant/generation received | `received`, receipt and complete DB bytes in same transaction; persist Handoff identity. |
| `received` | Validation operation claims | `validating`: verify authority, expected definition/baseline, candidate inventory and object integrity. |
| `validating` | Invalid candidate, missing provenance, different unit, impossible claim | `rejected`: immutable diagnosis/bytes; unit repair incident or attention, no dependent dispatch. |
| `validating` | Snapshot and change inventory match claimed baseline/scope | `frozen`: create immutable Candidate and freeze accepted recipe/context references. |
| `frozen` | Verification admitted | `verifying`: independent workspace and recorded checks/review. |
| `verifying` | New failure, unsatisfied criterion, required check unavailable | `attention` if awaiting a specific observation/waiver/repair decision; `rejected` when candidate needs repair. Preserve outputs and failed guarantees. |
| `attention` | Missing check/observation becomes available or precise waiver supplied | `verifying` (rerun needed checks) or `accepted` only when every required criterion is now satisfied/covered by that waiver. No generic “continue anyway.” |
| `verifying` | Required criteria satisfied, candidate unchanged | `accepted`: AcceptedResult committed once. `accepted_result` dependencies may now be admitted against that snapshot. |
| `accepted` | No requested destination application | `completed` or `completed_with_waiver`; close unit through same accounting transition. |
| `accepted` | Requested integration/application | `integrating`: queue destination-specific Integration. |
| `integrating` | Destination changed before application | Recompose/reverify under Integration; Handoff remains integrating, never substitute stale evidence. |
| `integrating` | Lost ack, interrupted apply, uncertain ref/tree, partial file changes | `reconciling`: inspect intent and actual destination before further mutation. |
| `reconciling` | All effects classified and safe remaining application possible | `integrating`: continue only not-applied entries, reverify if combined content changed. |
| `reconciling` / `integrating` | Conflict or exclusive application unavailable | `attention`: retain accepted isolated result and exact partial/conflicting paths; dependencies needing application remain blocked. |
| `attention` | Actual application conflict resolved and authority/current destination checked | `integrating` or `reconciling`, as evidence requires. |
| `integrating` / `reconciling` | Entire requested destination result verified as applied | `completed` or `completed_with_waiver`: settle unit/application accounting and enqueue eligible successors transactionally. |
| Nonterminal before accepted | Authorized new definition/candidate replaces this one, no unresolved effects | `superseded`: retain original, create new handoff for new ending; do not reuse message ID. |
| `integrating` / `reconciling` / `attention` after acceptance | Required application confirmed nonrecoverable, no meaningful recovery remains and all issued effects settled | `failed`: preserve AcceptedResult, failed Integration and exact destination state; required unit/run failure follows their settlement rules. |
| Any nonterminal | Cancellation and all issued effects settled | `cancelled`: preserve accepted result and any applied/partial work; do not hide it as rolled back. |

Terminal handoff states: **completed, completed_with_waiver, rejected, superseded, failed, cancelled**. Permanent verification failure is `rejected`; confirmed unrecoverable required application is `failed` after effect settlement, retaining the accepted isolated result and failed Integration. Cancellation is an intentional disposition, not a synonym for application failure. A handoff cannot be terminal while its external effect is still uncertain. Receipt `rejected/conflict/stale` for a malformed or unauthorized transport submission may have no Handoff at all.

A completed handoff does not require successors to have launched successfully. It requires durable publication of their eligibility/effect intents where appropriate. Successor kickoff has its own operation, attempt, generation and uncertainty. If Baton dies after handoff commit but before successor launch, reconciliation finds the pending intent; if it dies after launch but before receipt, it finds an uncertain kickoff rather than reconsuming the handoff.

### 4.7 Operation, wait and reservation lifecycle

Operation transitions: `planned → claimed → in_progress → succeeded|failed|observing|uncertain`; `observing → succeeded|failed|uncertain`; `uncertain → observing → succeeded|failed` only through evidence; `planned|claimed → cancelled` only with proof invocation has not begun. Claimed workers mark invocation intent before external action so the gap itself is treated conservatively. Terminal operations are succeeded, failed and cancelled. A failed operation requiring retry creates a new operation linked by predecessorOperationId; an uncertain operation never receives a blind new retry ID.

A scheduled Wait becomes claimed with one recovery operation in the same transaction. Accepted resume/delivery changes it to observing and removes its due timer. Productive progress marks satisfied and resolves the incident. Productive progress requires a supported observation of useful work, such as a completed tool/check, verified work inventory advance, accepted preparation capability or resolved work decision; a PID, transcript mtime, token stream or repeated promise alone does not qualify. A later generation failure produces a new incident observation, not another use of the old timer. Open circuits stop identical action bursts, retain scheduled probes with capped backoff, and can close automatically on productive progress or changed-cause proof. Cancellation cancels scheduled waits; owner changes suspend productive recovery.

Reservation transitions: `reserved → active|uncertain|released`, `active → uncertain|released`, `uncertain → active|released`. Release requires proof the resource is no longer occupied or the effect never began. A waiting live runtime, cleanup process, descendant or uncertain start remains counted. Replies to a reserved active session do not take a duplicate slot; fresh model review/preparation/follow-up and replacement overlap do.

### 4.8 Interrupted kickoff decision table

| Interruption point | Durable record / recovery |
|---|---|
| Before command commit | No accepted request/effect. Retrying the same command ID is safe. |
| After command commit, before source/context capture finishes | Run remains intake; reconcile capture operation; preserve partial objects until referenced state settled. |
| After prompt objects durable, before intent commit | No launch authorized. Unreferenced objects can be classified only after reconciliation; never dispatch from their existence. |
| After start intent/reservation commit, before known invocation | If operation proves never invoked, execute recorded intent. If claim died in invocation gap, lookup first. |
| Runtime accepted launch, reply lost | `uncertain`; retain slot, exact prompt, operation key and profile; unique lookup or native idempotent replay only. |
| Reply received, before DB identity binding | Same as uncertain kickoff; adapter lookup binds actual session without fabricating a second dispatch. |
| Process alive but first model request failed | Observe explicit failed state/error immediately; live PID is not productive success. Route provider/capability incident. |
| Process never reports expected capability | Bounded probe/observed stream alternative; attention only if required control/evidence truly unavailable. |
| Controller dies after input delivery | Reconcile exact operation ID/receipt before any repeat. A new ruling ID is not a retry of the old one. |
| Restore sees an old live execution | New controller epoch fences its reports. Reconcile/adopt/quiesce through supported adapter before any replacement; no automatic replay. |

## 5. PREPARATION, VERIFICATION AND APPLICATION CONTRACTS

### 5.1 Intake and preparation

Intake resolves the selected directory and captures the request before any model action. Determine whether it is a Git checkout, linked worktree, nested project, unborn/detached state or ordinary directory. Discover existing instructions, manifests, lockfiles, CI definitions, local scripts and requested work sources as evidence, not mandatory formats. Interpret prose through a managed preparation session only where deterministic discovery is insufficient. That session has the same identity, admission, trusted-host, checkpoint and reporting controls as coding.

Structural graph validation rejects missing references, duplicate unit/gate IDs, self-dependencies, cycles and gates without authority. Semantic interpretation retains provenance and uncertainty. A request to change scope or resolve conflicting intended behaviours goes to an addressed user question; ordinary unambiguous scope needs no approval. A changed source creates a proposal against the expected graph revision. Previously dispatched context stays reproducible; uncommitted target text does not silently change that execution's instructions.

Capture the actual selected checkout, including relevant dirty/untracked inputs. Distinguish user-owned baseline changes from Baton output. Choose a managed Git worktree only if shared administration and effective Git configuration are suitable; otherwise create a separate clone/copy. Do not initialize Git in a non-Git target. Names use opaque workspace IDs and Baton-owned branches, never milestone-derived sibling paths. A retained workspace is reused only after ownership, baseline and preparation inputs are revalidated.

Prepare discovered dependencies, native tooling, needed private local inputs and isolated services automatically within authority. Inspect and record scripts before executing them as tracked activities; respect explicit restrictions on builds or tooling. Capture effective runtime settings, hooks/plugins/MCP configuration, Git filters and relevant environment. Environment propagation classifies required tool/auth variables versus session-only variables explicitly; no blanket prefix deletion. Do not depend on whichever environment first launched a shared runtime service.

Missing documentation is not missing capability. Discover or derive a readiness check. An absent inaccessible external input becomes a concrete question/reference request while independent setup continues. A setup action's external side effect is journaled like coding activity; interrupted setup is reconciled before rerun. Input or lockfile/tool/settings/service changes invalidate only dependent readiness evidence. Toolchain installation that exceeds the request or actual host authority is a named prerequisite, not invented permission.

### 5.2 Verification

Before coding, bind a VerificationRecipe to the accepted definition and captured baseline. An intake recipe may initially have a null baselineId; create a baseline-bound immutable version for Attempt.recipeId before dispatch, preserving the accepted criteria/checks. Changing their meaning requires the reviewed proposal path. Discover available checks and derive task-specific observable criteria from the request; no existing suite is required. Baseline check outputs distinguish prior failures from introduced failures. A failing baseline does not universally refuse work, but a required criterion still needs evidence or a specific user waiver. A pass of unrelated checks cannot substitute for the requested behaviour.

Freeze candidate contents, actual changed paths, baseline, definition, originating execution and explanation. Reject a purported completion backed only by a commit's existence/ancestry or self-authored check claims. Run applicable checks under Baton control in a separate verification workspace against the frozen candidate and fixed recipe. A candidate editing tests cannot silently replace the previously accepted recipe; test/recipe changes require a reviewed proposal retaining the prior evidence. Semantic review is another admitted managed session. Its judgment cannot manufacture deterministic evidence that was not collected.

A criterion is satisfied only by evidence tied to the tested snapshot. No-code-change results are valid when they satisfy the objective with evidence. Flaky checks retain every failed/passed observation and diagnosis; repeated reruns do not erase earlier failure. If confidence cannot be established under the recipe, keep the criterion unsatisfied/unobserved and request the specific missing observation or ruling. A waiver must be an explicit user ruling naming the criterion, missing guarantee and dependency scope. It produces `waived`, never `verified`.

### 5.3 Integration and partial application

Serialize integration for the same Destination/resource across units and runs. Bind the queued item to the AcceptedResult, destination identity, current expected state and fixed recipe. Compose candidate changes with the current destination in a controlled workspace. Verify the combined result. If destination changes, recompose and reverify; do not reuse evidence for a different tree. Previously accepted isolated result remains immutable even if application needs a new composition.

For Git, distinguish a safe non-checked-out ref update from application to a user's checkout. Use expected-old-ref comparison for supported ref publication. A checked-out branch must not move beneath a dirty index/worktree. Preserve unrelated dirty changes and index state; apply only the requested candidate delta after conflict checks and coordinated checkout access. Record ref/tree/index observations. Successful internal ref publication alone does not mark a requested checkout applied. If safe checkout application cannot be established, retain the verified result and report the exact conflict.

For non-Git or snapshot application, persist the full application plan and each path's preimage/postimage before mutation. Acquire the discovered application ownership mechanism and prove its applicable exclusivity; an advisory lock plus hashes does not exclude an uncooperative writer. If exclusive application cannot be established, retain the result/patch and expose conflict rather than claiming safe multi-file publication. This does not prevent continued work against isolated accepted snapshots.

For each application entry, classify observed content as expected-before, expected-after, absent as expected, or divergent. Continue only proven not-applied entries while exclusivity and expected destination still hold. Mark expected-after entries applied without repeating mutation. A divergent file is conflicted, not overwritten. An interrupted rename/delete/metadata change is reconciled by its before/after plan, including both paths. Never imply a sequence of file writes is atomic repository publication.

On partial application, display every applied, pending and conflicting path, preserve preimages, retain destination reservation where effects/ownership remain uncertain, and offer a concrete recheck or user-directed resolution. Automatic rollback is not assumed: a requested restore must verify the destination still matches Baton's postimage before restoring the preimage, and must preserve subsequent user changes. Cancellation retains already applied content and records its exact state.

Acceptance and application commits enqueue resulting dependency availability transactionally. Reconciliation after a lost Git/file acknowledgement observes actual state before closing Integration. A successor consumes the AcceptedResult snapshot or observed applied result named by its Dependency, never whichever branch happens to exist later.

## 6. INTERFACES

### 6.1 Public boundary and common wire types

The local CLI is the public API; no daemon socket/HTTP server is required. All commands have a structured equivalent through `baton api`, which reads **one UTF-8 JSON request from stdin**, writes **one JSON response to stdout**, and sends human diagnostics only to stderr. No interactive text parsing is required for machine clients. `baton --help` and `baton --version` perform no state mutation.

Exact functional signatures:

```text
execute(request: CommandRequest) -> CommandResponse
query(request: QueryRequest) -> QueryResponse
submit(envelopeBytes: Bytes, binding: PrivateReportBinding) -> ReceiptResponse
```

These are semantic signatures implemented by the CLI boundary, not a requirement to export a Swift library. All wire objects use `api:2`. A command request is `{api:2, commandId:ID, kind:CommandKind, target:Scope, expectedRevision:Rev|null, arguments:CommandArguments}`. A query request is `{api:2, queryId:ID, kind:QueryKind, arguments:QueryArguments}`. Responses echo identity and kind.

`CommandResponse = {api:2, commandId:ID, status:accepted|pending|completed|rejected|uncertain, recordId:ID, revision:Rev, operationIds:[ID], result:CommandResult|null, error:APIError|null}`. `CommandResult = {entityRefs:[{type:EntityName,id:ID}], summary:Text, objectRefs:[ObjectRef]}`. `APIError = {code:invalid_input|not_found|revision_conflict|identity_conflict|not_authorized|unsupported|unavailable|integrity_failure|persistence_failure|uncertain_effect, message:Text, attentionId:ID|null, currentRevision:Rev|null}`. “Accepted” proves durable command acceptance, not effect success. Querying the command resolves later disposition.

`QueryResponse = {api:2, queryId:ID, snapshotSeq:Seq, observedAt:Instant, stale:Bool, nextCursor:Text|null, result:QueryResult|null, error:APIError|null}`. `QueryResult` is the exact query-specific shape in the table below. nextCursor is null for non-list queries and exhausted pages. Secret values, private credential locators and raw prompts are not included by default. Objects containing exact user data require an explicit `object` query and owner-local access.

New object IDs and creation commands may use `expectedRevision:null`. Mutations of existing targets require expectedRevision; mismatches return revision_conflict without effects. CLI human verbs may first read the target and submit that revision, but must expose a race conflict rather than silently retry changed intentions. Idempotent retries reuse commandId and identical canonical request bytes; a changed logical request under the same ID returns identity_conflict. Queries change no control state and perform no productive runtime/project effects, including preview. The explicit object export writes only its user-selected output file.

### 6.2 Commands and CLI signatures

All mutating verbs accept optional `--command-id <ID>`; absence creates an ID that is printed before pending work is returned. Existing-target mutations accept `--expect <Rev>`; omission uses a bounded read as described above. `--json` selects the common machine response. `--home <Path>` is a global host override and must resolve the entire coherent installation/profile; it is not an independent runtime-state seam. No model-authored shell is involved.

`TEXT_INPUT` in signatures is exactly one of `--text-file <Path>` or `--stdin`; strings are read as exact UTF-8 bytes, not interpolated, stripped or reparsed as commands. `SOURCE_INPUT` is exactly one of TEXT_INPUT, `--source-file <Path>`, or `--source-url <URL>`. Secret material should be supplied by private references rather than putting values in CLI arguments.

| CommandKind / exact CLI | CommandArguments (exact fields) and behaviour |
|---|---|
| `setup` / `baton setup [--json]` | `{}`; create validated default host configuration, discover both runtime profiles, surface actual OS/provider prerequisites. Does not launch arbitrary project work or purchase/install external services. |
| `intake` / `baton start <Path> SOURCE_INPUT [--runtime claude-code\|codex] [--patch-only] [--remote] [--json]` | `{location:Path, source:SourceInput, runtime:RuntimeKind\|null, application:automatic_local\|patch_only, remote:Bool}`. Default Claude/exhaustion fallback; explicit runtime is runtime-only. Remote is opt-in. Creates durable run and automatic intake. |
| `propose` / `baton propose <run-id> --file <Path> [--json]` | `{proposal:GraphProposalInput}`; validate expected revision, authority and graph. No direct edit of current DB graph. |
| `answer` / `baton answer <attention-id> TEXT_INPUT [--json]` | `{text:Text}`; exact addressed ruling, resolves only through cause-specific transition/delivery receipt. Cannot generically waive verification. |
| `waive` / `baton waive <attention-id> --file <Path> [--json]` | `{criterionIds:[ID], explanation:Text, dependencyIds:[ID]}`; explicit user waiver, same closure/accounting transitions, distinct evidence level. |
| `recheck` / `baton recheck <attention-id> [--json]` | `{}`; rerun failed prerequisite/capability or reconciliation, not hash unrelated plan files. |
| `pause` / `baton pause <scope> [--json]` | `{}`; set pause intent, request safe quiescence; response shows pending live processes. |
| `drain` / `baton drain <scope> [--json]` | `{}`; settle admitted work, no new model executions/successors. |
| `continue` / `baton continue <scope> [--json]` | `{}`; lift own pause/drain intention, reevaluate guards. Cannot reopen terminal work or override human ownership. |
| `cancel` / `baton cancel <scope> [--json]` | `{}`; suppress recovery, stop/reconcile controlled work, retain evidence and applied changes. |
| `takeover` / `baton takeover <scope> [--json]` | `{}`; durable human ownership before interaction; surface any already-issued uncertain delivery. |
| `handback` / `baton handback <scope> [--json]` | `{}`; revalidate workspace and external actions before automation. |
| `followup` / `baton wake <conversation-id> TEXT_INPUT [--json]` | `{text:Text}`; admitted follow-up purpose in native lineage where supported, otherwise checkpoint continuation. Productive requested changes enter a new run/definition; old completed unit stays terminal. |
| `adopt` / `baton adopt --runtime claude-code\|codex --session <native-id> --project <Path> [--observe-only] [--json]` | `{runtime:RuntimeKind,nativeSessionId:Text,location:Path,observeOnly:Bool}`; capture existing context; manage only with identity/exclusive-control/report proof. Otherwise return observe-only result and fresh-continuation option. No forged historical dispatch. |
| `resolve_operation` / `baton resolve-operation <operation-id> --file <Path> [--json]` | `{observedDisposition:occurred\|not_occurred, evidenceIds:[ID], explanation:Text}`; explicit resolution of otherwise ambiguous effect; record different evidence level and remaining limitations. Does not override observed live ownership. |
| `relocate` / `baton relocate <project-id> <Path> [--json]` | `{location:Path}`; identity reconciliation before location revision changes. |
| `retire` / `baton retire <project-id> [--json]` | `{}`; block new admission, drain and retire identity; retain history. |
| `dismiss` / `baton dismiss <attention-id> [--json]` | `{}`; only non-blocking informational attention, or already resolved cause. Dismissal is not waiver/recovery. |
| `budget` / `baton budget <scope> --file <Path> [--json]` | `{kind:UserBudget.kind,limit:Text,unit:Text}`; explicit optional policy; validate enforceability and report observation limitations. |
| `remove_budget` / `baton remove-budget <budget-id> [--json]` | `{}`; remove that user policy, not provider limits. Target is budget scope with expected budget revision. |
| `tick` / `baton tick [--json]` | `{}`; request one bounded reconciliation pass, no long foreground wait for productive work. |
| `backup` / `baton backup <Path> [--json]` | `{destination:Path}`; consistent manifest-verified backup, no credential values. |
| `restore` / `baton restore <Path> [--json]` | `{source:Path}`; validated restore under maintenance, new epoch and old-execution fencing; no immediate replay. |
| `activate_release` / `baton activate-release <release-id> [--json]` | `{releaseId:ID}`; compatible atomic switch or explicit drain/suspension with migration, never mixed files. |
| `delete` / `baton delete --manifest <Path> [--json]` | `{manifest:DeletionManifest}`; explicit listed retained-content deletion after reachability and live-reference checks; keep tombstones. No wildcard expiry. |

`<scope>` syntax is `controller`, `project:<ID>`, `run:<ID>`, `unit:<ID>`, or `execution:<ID>` for intent/ownership commands. Invalid scope-command combinations are rejected. Adopting an observed native session requires source access and runtime authorization; naming its ID alone grants neither. Protocol-only commands for reports use the separate scoped receiver, never operator command authority.

`SourceInput = {kind:text,value:Text} | {kind:file,path:Path} | {kind:url,url:Text}`. File/URL sources are captured with revisions/digests; inaccessible sources produce precise attention. Intake does not require issue-tracker integration: an accessible URL/text source suffices. No background polling of arbitrary external sources is implied.

### 6.3 Queries and exit behaviour

| QueryKind / CLI | QueryArguments / QueryResult |
|---|---|
| `status` / `baton status [--project <ID>] [--json]` | `{projectId:ID\|null}` → `{controller:ControllerSummary, projects:[ProjectSummary], runs:[RunSummary], health:[ComponentHealth], attentionIds:[ID]}`. Summaries defined below. |
| `inspect` / `baton inspect <entity-type>:<ID> [--json]` | `{entity:EntityName,id:ID}` → `{entity:PublicEntity,related:[{type:EntityName,id:ID}],admission:AdmissionDecision\|null}`. Exact entity schema from section 3 with private fields replaced by object references. |
| `preview` / `baton preview <operation-kind> <scope> [--json]` | `{operationKind:OperationKind,scope:Scope}` → `{decision:AdmissionDecision}`. No reservation, promise of future availability, or model call. |
| `attention` / `baton attention [--all] [--json]` | `{includeClosed:Bool}` → `{items:[Attention]}`. |
| `capabilities` / `baton capabilities [--runtime claude-code\|codex] [--json]` | `{runtime:RuntimeKind\|null}` → `{profiles:[RuntimeProfile],evidence:[CapabilityEvidence]}` with private settings/locators redacted. No live probe in a query; use recheck/setup for probes. |
| `history` / `baton history <scope> [--cursor <Text>] [--limit <Int>] [--json]` | `{scope:Scope,cursor:Text\|null,limit:Int}` → `{events:[AuditEvent]}`. Default limit 100, valid 1–1000; cursor ordered by sequence. |
| `command` / `baton command <command-id> [--json]` | `{commandId:ID}` → `{command:CommandResponse}`. |
| `object` / `baton object <object-id> --output <Path> [--json]` | `{objectId:ID,output:Path}` → `{object:Object,output:Path}`; explicit local export of requested retained bytes, refuse overwrite. It creates only the named export, not control state. |
| `deletion_preview` / `baton deletion-preview <scope> [--json]` | `{scope:Scope}` → `{manifest:DeletionManifest,blockedBy:[ID]}`; exact body/workspace targets and protected identities. |

`EntityName` is a section-3 entity name. `PublicEntity` is that entity's fields excluding private locator/settings bytes and authentication bindings. `ControllerSummary = {epoch:ID,intent:ControlIntent,releaseId:ID,lastPassId:ID|null}`. `ProjectSummary = {id:ID,name:Text,location:Path,status:Project.status}`. `RunSummary = {id:ID,projectId:ID,state:RunState,intent:ControlIntent,owner:Ownership,unitIds:[ID],runtime:RuntimeKind|null,admissionReasons:[AdmissionReason],acceptedResultIds:[ID],integrationIds:[ID],attentionIds:[ID]}`. Native session URLs are optional adapter-resolved capabilities, not permanent identity fields.

All list queries accept pagination through `baton api` arguments `cursor:Text|null` and `limit:Int` with the same defaults/range as history; these fields are optional additions to the listed query arguments. QueryResponse.nextCursor carries the continuation for that query and snapshot, ordered by entity type and creation sequence (AuditEvent.sequence for history). An expired/unavailable snapshot cursor returns revision_conflict, never silent gaps. Status lists active records by default; retained history is addressed/paginated, never whole-history scanned. Query deadlines produce unavailable with freshness/last-known data where valid, not an empty fleet implying nothing runs.

Exit codes: `0` = valid successful query or durably accepted/pending command; `2` = invalid input/schema; `3` = not found; `4` = revision/identity conflict; `5` = policy/capability/authority rejection; `6` = persistence/integrity failure; `7` = effect outcome uncertain; `8` = temporarily unavailable/deadline. A command accepted for asynchronous execution can later fail; clients inspect its ID. Errors never masquerade as successful empty output.

### 6.4 Session reporting and file formats

Exact receiver CLI: `baton report --binding-file <Path> --stdin [--json]`. The private binding file is injected by Baton from ReportGrant; the target does not create or install it. `PrivateReportBinding = {format:2,reportGrantId:ID,executionId:ID,generation:Int,controllerEpoch:ID,receiverHome:Path,releaseId:ID,nonce:Text}`; the receiver compares this to the pinned grant and current epoch, never adopts authority from the file alone. It is a private accidental-misrouting capability, not same-user containment. Runtime hooks, if supported, or adapter result streams use the same envelope and semantic receiver. The receiver supplies/validates run, unit, attempt, workspace and profile from the bound Execution rather than trusting model-provided identities.

`ReportEnvelope = {protocol:2,messageId:ID,executionId:ID,generation:Int,controllerEpoch:ID,kind:ReportKind,writtenAt:Instant,payload:ReportPayload}`. Producer encoding is UTF-8 JSON without duplicate keys; preserving exact bytes is the preferred retry path, but formatting-only retransmission deduplicates. Receiver rejects duplicate JSON keys, unknown fields/semantics, invalid types, trailing non-whitespace, and unsupported protocol versions. A copied message with a new timestamp under the same ID is conflict, not a new ending. Only a genuinely distinct report receives a new ID.

Logical message/command equality compares validated JSON values: object key order, insignificant whitespace and equivalent JSON string escapes do not matter; array order, every field value, null/omission and exact decoded text do. No Unicode normalization or trimming of user text is allowed. Canonical digests serialize keys in lexicographic UTF-8 byte order, arrays in original order, with no insignificant whitespace; strings use literal UTF-8 except quote/backslash escapes and lowercase `\u00xx` for U+0000–U+001F; integers use shortest decimal form with zero normalized to `0`. Protocol numeric fields accept integer values only; floating/exponent tokens and invalid Unicode are rejected. Hash these canonical bytes for Command.digest/Message.digest and identity tombstones. Raw Object/Submission digests always hash their original bytes. This makes deduplication survive formatting changes without conflating different messages.

| Report kind | Exact payload |
|---|---|
| `checkpoint` | `{summary:Text,inventoryObject:ID,decisionIds:[ID],verificationIds:[ID],unfinishedActions:[{description:Text,effectScope:Text,evidenceIds:[ID],state:UnfinishedAction.state}],contextObjectIds:[ID],completeness:complete_inventory\|partial,trigger:Checkpoint.trigger}` |
| `question` | `{question:Text,contextObjectIds:[ID],blocking:Bool,relatedCriterionIds:[ID]}` |
| `candidate` | `{definitionId:ID,baselineId:ID,workspaceId:ID,inventoryObject:ID,changedPaths:[RelPath],explanation:Text,claimEvidenceIds:[ID],checkpointId:ID\|null,noChange:Bool}` |
| `stopped` | `{reason:FailureCode,detail:Text,checkpointId:ID\|null,unfinishedActionIds:[ID]}` |
| `progress` | `{summary:Text,evidenceObjectIds:[ID],unfinishedActionIds:[ID]}` |
| `graph_proposal` | `{expectedGraphRevision:Rev,proposal:GraphProposalInput}` |

`GraphProposalInput = {runId:ID,expectedGraphRevision:Rev,definitions:[ProposedDefinition],dependencies:[Dependency],gates:[Gate],sourceIds:[ID],explanation:Text}`. `ProposedDefinition = {unitId:ID,title:Text,objective:Text,scope:[Text],sourceIds:[ID],contextObjects:[ObjectRef],criteria:[Criterion],checks:[CheckSpec],destinationId:ID,resourceRequirements:[ResourceRequirement]}`. Receiver derives immutable UnitDefinition/VerificationRecipe IDs after validation; the proposal cannot claim its own acceptance. Existing unit IDs preserve identity; new unit IDs are checked unique. Replacing a running definition requires the safe boundary in section 4.

`ReceiptResponse = {api:2,submissionId:ID,messageId:ID|null,disposition:accepted|duplicate|rejected|conflict|stale,receiptId:ID|null,originalReceiptId:ID|null,reason:Reason|null}`. Failure to persist returns exit 6 with null receiptId and no accepted disposition; transport retries the same bytes. The failure response uses `APIError` instead of ReceiptResponse when no durable receipt exists. A rejected submission with no usable execution still gets an unassigned Attention and immutable raw bytes if persistence works.

Producer writes an exclusive `.tmp` file, flushes it, atomically publishes `<submission-id>.json`, and retains it until durable receipt. The adapter manages transport retry; the project never needs a preexisting hook. An orphan `.tmp` is an incomplete submission, not an outcome. Observe its writer/operation before classifying it; preserve bytes and diagnostic evidence if interrupted. If a stop occurs without a valid report, record a generation-bound missing-report incident through observed termination, attempt checkpoint recovery, and route through the bounded recovery state machine. Do not make an existing file path sufficient to suppress future endings.

Object references in reports must resolve to allowed current execution/workspace objects and match digests. Producers can send evidence through `baton evidence --binding-file <Path> --file <Path> --kind source|output|snapshot_manifest|checkpoint|evidence`, returning `{api:2,objectId:ID,digest:Digest,byteLength:Int}` after durable copy. This scoped interface accepts only readable allowed execution evidence, records provenance, and does not give object bytes scheduling authority. It is not containment against unrestricted host code. A candidate inventory is independently captured/compared; the producer's inventory does not freeze a still-changing workspace by assertion.

Generated kickoff context is a retained UTF-8 text object assembled from the fixed definition and current admitted environment. It contains: run/unit/attempt/execution generation; scope/objective and explicit restrictions; exact source/context snapshots; baseline/workspace/destination; recipe/criteria; current peer reservations/resources; checkpoint and unresolved actions; reporting instructions and available control capabilities; required refusal to claim acceptance/apply the target itself. It contains no mandatory project-heading anatomy and no successor disposition list. Secret values are resolved through private channels, not added to this generic prompt.

`BackupManifest = {format:2,backupId:ID,controllerEpoch:ID,databaseSchema:Int,protocols:[Int],databaseDigest:Digest,capturedSeq:Seq,createdAt:Instant,releaseIds:[ID],objects:[{id:ID,digest:Digest,size:Int}],workspaces:[{id:ID,manifestObjectId:ID}],excludedSecretReferenceIds:[ID],runtimeContinuity:Text,integrityResults:[Text]}`. A workspace changing during backup must be consistently captured or explicitly reported as an unavailable consistent snapshot; do not label an inconsistent backup complete.

`DeletionManifest = {format:2,scope:Scope,expectedSnapshotSeq:Seq,entityRevisions:[{id:ID,revision:Rev}],objectIds:[ID],workspaceIds:[ID],releaseIds:[ID],retainedTombstoneIds:[ID],description:Text}`. Revalidate current reachability and live references at execution, refuse expanded/stale targets, and record every deleted body. No active recovery evidence/workspace can be silently deleted. Tombstones are outside deletable bodies. Ordinary temporary cleanup cannot remove anything referenced by retained evidence or a kept workspace.

### 6.5 Runtime and host adapter contracts

These are exact semantic ports. An adapter must return `unsupported`/`unknown` honestly where a guarantee is absent; core must use an evidenced alternative or block only the dependent operation. Do not invent native flags, private database writes or session IDs to simulate missing capabilities.

```text
RuntimeAdapter.describe(profileId: ID) -> CapabilitySet
RuntimeAdapter.probe(profileId: ID, names: [CapabilityName], call: CallContext) -> [CapabilityEvidence]
RuntimeAdapter.start(input: StartInput, call: CallContext) -> EffectReply
RuntimeAdapter.resume(input: ResumeInput, call: CallContext) -> EffectReply
RuntimeAdapter.deliver(input: DeliverInput, call: CallContext) -> EffectReply
RuntimeAdapter.stop(identity: NativeIdentity, call: CallContext) -> EffectReply
RuntimeAdapter.lookup(operationId: ID, profileId: ID, call: CallContext) -> LookupReply
RuntimeAdapter.observe(identities: [NativeIdentity], profileId: ID, call: CallContext) -> ObservationBatch
RuntimeAdapter.captureContext(identity: NativeIdentity, call: CallContext) -> ContextCapture
RuntimeAdapter.remoteTarget(conversationId: ID, call: CallContext) -> RemoteTarget
HostAdapter.observeResources(call: CallContext) -> ObservationBatch
HostAdapter.captureSnapshot(location: Path, call: CallContext) -> SnapshotReply
HostAdapter.invoke(argv: [Text], cwd: Path, environmentRef: ObjectRef, call: CallContext) -> EffectReply
HostAdapter.notify(notificationId: ID, payload: ObjectRef, call: CallContext) -> EffectReply
HostAdapter.resolveNotificationResponse(notificationId: ID) -> ID
HostAdapter.observeProcess(identity: ProcessIdentity, call: CallContext) -> ObservationBatch
HostAdapter.sleepAssertion(executionId: ID, acquire: Bool, call: CallContext) -> EffectReply
```

`CallContext = {operationId:ID,controllerEpoch:ID,deadline:Instant,profileId:ID|null,inputDigest:Digest}`. Adapter calls use the recorded operation ID for native idempotency/lookup where available. Productive sessions started by a bounded start call are observed afterward; the start deadline is not a lifetime deadline.

`CapabilitySet = {runtime:RuntimeKind,adapterVersion:Text,protocol:Int,evidence:[CapabilityEvidence]}`. `StartInput = {executionId:ID,generation:Int,workspaceId:ID,profileId:ID,promptObject:ID,reportGrantId:ID,purpose:Execution.purpose,peerReservationIds:[ID]}`. `ResumeInput = {start:StartInput,previousIdentity:NativeIdentity,conversationId:ID,checkpointId:ID|null}`. `DeliverInput = {executionId:ID,generation:Int,identity:NativeIdentity,textObject:ID,ownershipRevision:Rev}`.

`EffectReply = {outcome:acknowledged|refused|unknown|unsupported,nativeIdentity:NativeIdentity|null,receipt:Text|null,evidenceObjects:[ID],reason:Reason|null}`. Acknowledgement proves only the guarantee described by the adapter capability. `LookupReply = {outcome:found|proven_absent|ambiguous|unsupported,identities:[NativeIdentity],evidenceObjects:[ID]}`. No match in a non-authoritative list is ambiguous, not proven_absent. `ObservationBatch = {observations:[Observation],complete:Bool,failures:[Reason]}`. `ContextCapture = {objects:[ID],workspacePath:Path|null,unfinishedActions:[UnfinishedAction],completeness:complete_inventory|partial,reason:Reason|null}`. `RemoteTarget = {available:Bool,url:Text|null,expiresAt:Instant|null,limitations:[Text],reason:Reason|null}`. `SnapshotReply = {baselineId:ID|null,consistent:Bool,evidenceObjects:[ID],reason:Reason|null}`. Notification response resolves the Attention ID, not a native conversation selected by recency.

Both adapters need versioned conformance captures for start refusal/success/lost reply, observation uncertainty, input delivery/resume/fork distinctions, termination, missing/disabled reporting hooks, questions/waits, effective settings, ownership limitations and checkpoint continuation. Quota/remote/native resume can have different supported guarantees. For an operation requiring a missing hook, use a supported observed result stream or controlled fresh session if equivalent evidence exists. Installation must report actual available guarantees and selected protocol. Model/effort defaults come from the chosen validated runtime profile; the core does not assume V1 aliases or a cross-runtime model-name mapping.

### 6.6 Target-project contract

The target supplies only the selected location, authorized accessible contents, and the user's requested outcome or work source. Existing instructions remain in force within that work. Baton discovers project-specific tools/checks and prepares needed inputs. No target must implement the reporting schema, install hooks, host a service, expose a port, provide a resource manifest, contain a test suite, or make a Baton migration commit. Scoped reporting/configuration is injected into managed execution by Baton.

A target may have impossible-to-infer inputs or conflicting requirements. Baton must identify the exact gap and continue independent work. Trusted-host execution grants no authority to expand scope to changing other projects, bypass provider/OS restrictions, publish externally, or invent proof. Optional adopted-session support requires control evidence, not a new mandatory contract for ordinary targets.

## 7. EDGE CASES

Each case is required behaviour, not merely a test suggestion.

1. **Two projects share a basename/remote:** distinct IDs; no shared state, settings, destination or notifications by name.
2. **Symlink spelling or moved location:** reconcile filesystem/project identity; update location revision only after proof, ask about a specific ambiguous identity if needed.
3. **A directory is replaced at the same path:** detect identity mismatch and hold affected writes; do not attach old runs to new contents.
4. **Nested selection in a larger repository:** retain selected scope; repository discovery does not authorize sibling edits.
5. **Git branch is not main / detached / unborn:** capture actual state; use snapshot/clone when worktree base is unsuitable; never guess remote/default branch.
6. **Dirty index, unstaged and untracked files:** capture separately and preserve unrelated changes; verified output is a baseline-bound delta, not replacement of the checkout.
7. **Non-Git target:** snapshot without initializing Git; use journaled per-path application and explicit conflicts.
8. **Source changes while copied:** invalidate inconsistent capture, wait/probe stable input; never dispatch against a mixed snapshot.
9. **Submodules, LFS, filters and checkout hooks:** inspect effective configuration, track required preparation and authorized effects; absence is a concrete readiness issue.
10. **Ignored secret/config/cache trees:** discover required bindings; no wholesale copy. Generated substitutes/private copies may be prepared within authority.
11. **External symlink, socket, device, huge/binary file:** preserve link semantics or resource binding; report actual filesystem/capacity inability, no silent omission of required source.
12. **Case/Unicode/path-length collision on copied filesystem:** retain original evidence and report exact conflicting paths; no silent rename or overwrite.
13. **Path or prompt contains spaces, apostrophes, newlines, `$()`, backticks or a heredoc delimiter:** carry as exact data/argv, never generated shell source.
14. **No documentation or test suite:** discover preparation and derive criteria; absence alone cannot refuse intake or imply success.
15. **Baseline tests already fail:** record baseline failures and judge changed work against fixed criteria; never manufacture all-green results or waivers.
16. **Tests/recipe edited by coding session:** candidate changes are reviewable; original recipe remains authority until accepted proposal.
17. **No-change candidate:** may satisfy task with evidence; a commit is neither necessary nor sufficient.
18. **Two graph proposals race:** one expected-revision acceptance wins; stale proposal is superseded/rejected, not last-file-wins.
19. **Late old-generation ending:** stale receipt retained, no new park or successor advice.
20. **Duplicate message or changed metadata:** same parsed envelope/ID returns receipt despite formatting differences; changed logical envelope/ID conflicts; distinct new ending has distinct ID.
21. **Malformed report with no project identity:** retain under Submission ID, create unassigned attention with recheck/dismiss as appropriate.
22. **Partial `.tmp` handoff or receiver disk failure:** no acceptance; retry exact published bytes only after durable persistence is available.
23. **Candidate arrives while session still changes files:** independent freeze/quiescence validation; do not verify mutable output by a claimed inventory alone.
24. **Controller dies after integration but before closure:** inspect expected ref/files, record effect already occurred, then close once; no duplicate apply.
25. **Some non-Git files applied before crash:** classify each entry by pre/postimage, preserve divergence, resume only proven pending safe entries.
26. **Destination changes during combined verification:** recompose/reverify with new base; old verification never publishes over new user changes.
27. **Uncooperative outside writer cannot be excluded:** keep isolated verified result and surface application conflict; do not promise atomicity or release applied-result dependencies.
28. **Missing fleet listing/transcript, reused PID or stale timestamps:** observations are unknown; maintain ownership/reservations, reconcile authoritative identities.
29. **Failed first request with a live process:** route actual failure immediately; PID alone cannot mark progress or delay classification until stall timeout.
30. **Old ending followed by later resume crash:** new generation is independently crash-detectable; old ending neither suppresses it nor restarts its wait.
31. **Human takeover then disappearing row:** durable human ownership persists; no automatic rescue session.
32. **Question repeats identical text:** match actual addressed event/identity, not text-hash actor heuristics; replies resolve only their target.
33. **Local dialog, permission wait, worker wait and remote question:** classify independently of remote opt-in; all actionable questions appear locally.
34. **Claude allocation exhausted:** eligible Codex fallback uses fresh checkpoint continuation only after old effects settle; generic errors/missing telemetry do not trigger it.
35. **Both runtimes limited or Codex unavailable:** automatically wait/probe actual scopes; do not ask for budget setup, buy credits or spin identical attempts.
36. **Claude resets during productive Codex work:** let it continue; reevaluate later default starts rather than oscillating sessions.
37. **Two profiles may be the same account:** group unknown identity for accounting, do not manufacture quota holds or independent capacity.
38. **Pause/cancel races with launch:** unissued intent cancelled; issued/ambiguous launch remains reserved and reconciled; no automatic replacement.
39. **Terminal conversation wake forks:** new follow-up purpose/lineage, no stale completion obligation or reopened old unit.
40. **Existing external session cannot be exclusively adopted:** observe-only context import and offered fresh continuation; no fabricated prior dispatch.
41. **Notification delivery fails or an old notification is clicked:** retry same notification identity; click opens its durable attention even if session link expired; do not clear unrelated items.
42. **Host sleeps, clock moves or reboots:** elapsed deadlines use monotonic clocks while live; after restart reevaluate persisted waits against current observations. No timestamp-based identity or reservation release.
43. **Retained object changed/missing or database corrupt:** integrity failure; don't accept replay or execute without required evidence. Preserve diagnosis and use validated recovery.
44. **Upgrade/restore while native work remains:** pin profiles/releases, fence old epochs, reconcile before replay or replacement. Incompatible schema rollback is refused.
45. **Explicit deletion followed by stale reports:** tombstones retain identity retirement and reject them; body absence never permits a new acceptance.
46. **Cross-project dependency source needed:** provision/build accessible dependency within requested work, but don't start changing another project's independent plan.
47. **Productive task exceeds overnight/runtime duration:** no total-work timeout; only bounded control operations and actual resources/explicit user policies govern continuation.
48. **Destination request is patch-only:** completion delivers accepted patch/evidence; do not apply simply because O3 usually applies locally.
49. **Context window ends or compaction is impending:** checkpoint when observable, retain partial inventory when abrupt, reconcile actions before supported continuation; do not conflate context capacity with provider usage allocation.
50. **Repeated unfinished endings:** preserve cross-attempt failure history, use meaningful continuation or authorized in-scope graph revision; fresh contexts alone cannot reset the ineffective-action circuit.

## 8. FAILURE MODES

The following closed FailureCode values are used by Reason/stopped reports. Adapters map native errors into a category with original redacted evidence; unknown strings map to `unknown_runtime`, never invent a new transition. Multiple observations can share a category without being the same incident; incident fingerprints include scope, cause and ineffective action.

| FailureCode | Detection | What the user sees | Recovery |
|---|---|---|---|
| `invalid_input` | Schema/type/graph validation, ambiguous intent | Exact field/reference or behavioural question | Fix source/proposal or addressed answer; revalidate expected revision. |
| `source_unavailable` | Location/source access fails | Specific unreadable source and observed error | Automatic recheck for transient access; user supplies only unavailable authority/location. |
| `identity_mismatch` | Project/workspace/destination evidence differs | Expected and observed identity, held writes | Reconcile move/ownership or explicit identity ruling; never reuse by name. |
| `unstable_snapshot` | Capture inventories differ | Files changing and capture waiting | Retry after observed stability with backoff; preserve prior consistent baseline. |
| `preparation_missing` | Required readiness check absent/fails | Named tool/service/input and completed setup | Perform discoverable authorized setup; ask only for irreducible input. |
| `preparation_failed` | Setup activity definitively fails | Command, output, affected capabilities | Diagnose, changed-path retry or incident circuit breaker; reconcile external setup effects first. |
| `authentication` | Adapter/provider rejects current profile | Runtime/account reference and provider action needed, no secret values | Existing supported authentication restoration/probe; no exhaustion fallback from this alone. |
| `permission` | OS/runtime/managed policy refuses required action | Exact required grant/policy and supported alternative | Use an equivalent observed supported path or user grants actual missing authority. No bypass. |
| `capability_unavailable` | Versioned probe fails/required callback absent | Missing guarantee and operations affected | Reprobe, observed result-stream alternative or fresh controlled session; no whole-project refusal for optional features. |
| `usage_exhausted` | Current provider evidence identifies applicable exhausted allocation | Account/limit scope, reset if known, selected fallback/wait | O8 Codex fallback if eligible and predecessor settled; otherwise backoff/probe Claude automatically. |
| `rate_limited` | Transient throttle without proven allocation exhaustion | Waiting with supported retry/reset evidence | Scoped wait, capped backoff, scheduled probe; not automatic cross-runtime switch on assumption. |
| `provider_transient` | Supported overload/network/temporary server failure | Retry condition and last useful progress | Incident-bounded retry/probe, preserve unknown side effects; no lifetime retry-count reset request. |
| `startup_failed` | Definitive failed first request/start, including live failed PID | Failure stage/native evidence | Settle process, repair known cause or meaningful alternative; new attempt doesn't erase incident. |
| `unknown_runtime` | Unknown state/unsupported native output | Observation unknown, evidence and reduced guarantees | Bounded observation/compatibility recheck; attention if required interpretation unavailable. |
| `missing_report` | Observed generation ending without accepted report | Interrupted/missing handoff, retained workspace | Capture available checkpoint, reconcile unfinished work and use bounded continuation; never infer complete. |
| `invalid_report` | Bad schema/provenance/unknown enum | Immutable submission and exact diagnosis | Correct producer/integration, submit new message when payload changes; do not edit accepted bytes. |
| `stale_report` | Retired epoch/generation or stale authority | Stale receipt with original target | No lifecycle effect; current authorized generation may report separately. |
| `message_conflict` | Same logical ID, different parsed envelope | Both submission identities/digests | Preserve original receipt; repair producer identity usage, no replayed consequences. |
| `uncertain_effect` | Ack loss, invocation gap, ambiguous lookup | Operation ID, possible effect, held reservation | Native lookup/idempotency or explicit evidence-based resolution; no blind new start/delivery. |
| `crash` | Authoritative termination/failure observation | Failed generation, checkpoint availability | Reconcile actions, then admitted resume/fresh attempt; old endings don't suppress detection. |
| `context_limit` | Supported context-capacity/compaction boundary or rejection | Remaining work, checkpoint completeness, native-continuity availability | Checkpoint and reconcile; supported native or fresh same-runtime continuation, incident-bound if repeatedly ineffective. Not usage-exhaustion fallback by itself. |
| `unfinished` | Valid ending explicitly leaves objective incomplete | Completed work inventory and exact remainder | Continue from checkpoint or accept an authorized in-scope graph revision; preserve cross-attempt incident until real progress. |
| `stall` | No meaningful progress under supported observation | Last progress and uncertainty, not “dead” from age alone | Probe current action/worker; checkpoint/stop only when evidence permits; attention if no meaningful recovery path. |
| `input_required` | Explicit question/local dialog | Exact addressed question and context | Exact data-only answer, receipt/observation before closure; independent work may continue. |
| `ownership_uncertain` | Outside input/ambiguous actor evidence | Human stand-off or unknown owner | Explicit takeover/handback or authoritative mediation; no expiry into autonomy. |
| `resource_pressure` | Host/resource collision or actual capacity | Queued operation and resource reason | Adapt admission, isolate ports/services, automatically resume when pressure clears. |
| `verification_failed` | Required criterion unsatisfied/new check failure | Baseline versus candidate evidence | Repair candidate or specific explicit waiver; never all-green from unrelated pass. |
| `verification_unavailable` | Required check/hardware observation cannot execute | Exact missing proof | Prepare available capability or obtain specific observation/waiver; retain unrun status. |
| `destination_changed` | Expected ref/inventory no longer matches | Destination drift and reverify state | Recompose/reverify automatically if safe, otherwise conflict attention. |
| `application_conflict` | Divergent path/index, missing exclusive access | Exact conflicting paths and retained verified result | Recheck after conflict resolution; preserve unrelated changes; accepted-snapshot dependencies may continue. |
| `partial_application` | Some planned entries applied before interruption | Applied/pending/divergent path list, no atomic-success claim | Classify pre/postimages, reconcile before safe continuation or explicit guarded restoration. |
| `integrity` | Object hash/missing evidence/DB integrity failure | Affected object/store and dependent operations suspended | Validated backup/repair with retained diagnosis; never accept evidence-free replay. |
| `persistence` | Durable object/DB write fails, disk exhaustion | Persistence suspended, actual failed write | Restore capacity/access then reconcile; no eviction or effects without intent. |
| `notification_failed` | Transport returns failure or receipt missing | Durable attention plus failed/unknown delivery | Retry notification ID through supported transport; local work unaffected. |
| `controller_unhealthy` | Watchdog detects unloaded/stuck/nonprogressing tick | Local controller-health attention and last useful pass | Repair controller/scheduler and reconcile; watchdog never blindly restarts target work. |
| `release_incompatible` | Schema/protocol/profile incompatibility | Refused activation/rollback or drain required | Compatible release/migration and consistent backup; no mixed live environment. |
| `external_dependency` | Required independent-project output unavailable | Specific prerequisite beyond selected change scope | Prepare accessible dependency or obtain required source/output; no hidden cross-project plan. |

A repeatable failure is not permanently terminal just because a configured burst limit is reached. Its circuit stays observable and probeable. A confirmed nonrecoverable cause or truly missing authority/answer is attention; failure closure requires settlement of owned effects and explicit unmet-objective reporting. A missing phone, unknown quota, or long productive duration is never itself such a cause.

## 9. UX FLOWS

### 9.1 First run against an unseen project

1. The person invokes `baton start /absolute/project --stdin` and supplies the requested work, or names an existing source. No target registration or document preparation precedes this step. Host setup, if incomplete, creates the run/intake record where persistence is available and reports the precise missing host/runtime prerequisite through Baton.
2. Baton returns the run ID and shows “Discovering project,” selected location, default Claude Code policy, automatic local application, and trusted-host execution. These are visible standing settings, not an approval questionnaire. An explicit runtime or patch-only choice is shown instead when supplied.
3. Discovery captures the actual project identity and selected state. Dirty files, non-main branches and non-Git inputs are represented without requiring cleanup. Existing sources/instructions are captured with provenance. A bounded managed preparation session interprets prose only if necessary.
4. Status shows the understood scope and graph, source references, acceptance criteria and preparation actions. Valid unambiguous in-scope work advances automatically. If two intended behaviours are plausible, one addressed question asks for that distinction. Other authorized discovery/preparation continues.
5. Baton creates its owned isolated workspace, prepares required inputs/services/tools, captures baseline checks and fixes the recipe. Missing documentation alone does not cause a stop. Missing external access displays the specific input and what Baton already prepared.
6. Admission selects Claude Code unless explicit selection or confirmed exhaustion fallback applies. Baton stores the prompt/profile/grant and reservation before invoking the runtime. Status distinguishes queued, starting, running and uncertain launch.
7. The managed session receives the full reproducible context and scoped reporting route. Baton observes startup success/failure, questions and progress. A successful PID without a successful first request does not count as productive work.
8. Results follow verification/application below. No routine approval is inserted for verified local changes. The person gets evidence-linked completion or a concrete addressed recovery action, not a request to author Baton files.

### 9.2 Normal handoff and successor kickoff

1. Session checkpoints its work inventory, decisions and unresolved actions, then reports a candidate ending for its current generation. It supplies its own work only and does not merge the target or select successor dispositions.
2. Baton durably acknowledges receipt, validates identity/definition/baseline, freezes the snapshot and independently verifies it. Status separates “candidate received,” “verifying,” and “accepted.” Coding-process cleanup remains visible and reserved until observed terminated.
3. The integration queue composes the result with the current requested destination and verifies that combined result. Local application happens automatically when safe. Dirty unrelated user work is preserved; destination drift triggers recompose/reverify.
4. Baton records observed application, closes the unit/handoff with verified or waived evidence level, and makes dependency results available in the same transaction. Status links checks, changed paths, accepted snapshot and applied destination.
5. Each eligible successor is evaluated through admission using the accepted graph revision and required exact predecessor result. Its prompt and reservation include current peers. Its launch has its own durable operation ID; predecessor completion does not imply successor startup success.
6. With no required work remaining and no active/uncertain required effects, the run completes. Retained conversations/workspaces remain addressable. A later wake is follow-up purpose, not reopened completion reporting.

### 9.3 Claude allocation exhaustion and fallback

1. Adapter evidence identifies the Claude account/limit scope as exhausted. Baton displays the exhaustion/reset evidence, opens a scoped incident and captures accessible work/checkpoint state.
2. If an earlier launch/tool effect is uncertain, Baton reconciles it first. If the person owns the session, Baton stands off. Fallback is not a way around either condition.
3. When the predecessor is quiescent and Codex is authorized/capable, reserve a fresh Codex execution and record the exhaustion cause and checkpoint lineage. Display “Continuing in Codex from checkpoint,” not “conversation transferred.” No extra project setup is required.
4. Codex gets the same accepted work scope, fixed recipe, prepared inputs, actual current inventory and unresolved-action dispositions. Native conversation state is not fabricated. Incident closes only on productive progress or proven repaired cause.
5. If Codex is unavailable or also limited, preserve work and automatically wait/probe supported prerequisites. Do not buy capacity, request a personal reserve policy, or repeatedly launch identical failures. A later Claude reset does not interrupt productive Codex work.

### 9.4 Interrupted kickoff or handoff recovery

1. After restart, status immediately exposes last-known active/uncertain operations and health; a failed live listing remains unknown. Reconciliation reads current indexed state and pinned evidence, not a full historical replay.
2. For a start with lost acknowledgement, use operation lookup/native deduplication if proved available. Found work is attached to the recorded execution; proven absent work can execute its recorded intent. Ambiguity retains reservation and raises an addressed operation item with evidence and available resolution.
3. For an incomplete handoff file, preserve it as unaccepted staging and inspect the actual writer/generation. For an accepted receipt whose process died, resume its pending verification/application consequences without asking the session to send a different completion.
4. For partial application, show applied/pending/conflicting paths and preserved preimages. Reconcile actual destination before safe continuation. Never overwrite a divergent user change or report partial success as completed application.
5. The person uses the attention ID to answer/recheck/resolve. The command names one item and expected revision; multiple same-unit or projectless items remain individually actionable. Delivery acknowledgement and recovered progress, not the act of clicking, close the relevant incident.
6. A notification opens its own durable item even after the conversation link expires. Failed notifications remain retryable and do not prevent terminal/CLI recovery. Unknown actor evidence asks for ownership resolution rather than launching a replacement.

### 9.5 Maintenance and retained history

Release installation stages an immutable release and validates manifest, schema/protocol compatibility and executable paths before activation. Installed scheduling paths are generated for the actual user/home, never hardcoded to one account. Active executions pin their release/profile; old releases remain while referenced. Incompatible activation drains/suspends affected work and performs an explicit migration. Ordinary verification must not unexpectedly compile/sign/install host components.

Backups use a consistent SQLite snapshot plus all referenced retained evidence and consistent workspace snapshots, with manifest digests. Validate integrity before declaring success. Credential values and runtime authentication are re-resolved, not bundled. Restore executes under maintenance exclusion, creates a new controller epoch, fences pre-restore grants, reconciles old processes and effects, then permits admission. A restored native conversation may be unavailable; checkpoint continuation remains the truthful alternative.

Explicit deletion starts with a concrete manifest showing retained bodies/workspaces/releases and protected references. Execution rechecks revisions/reachability, refuses live required objects, and records deletion while retaining replay fences/tombstones. Cleanup of disposable temporaries/reproducible caches cannot delete kept workspace contents. Capacity warnings show actionable usage, but missing free-space estimates or arbitrary history size never impose a stop. Actual write failure suspends affected persistence and effects until repaired.

## 10. ACCEPTANCE CRITERIA

Each criterion is pass/fail with retained evidence. A fixture pass proves the exercised semantic contract; real runtime, installation, quota and notification claims additionally require the corresponding observed integration evidence. Failure-injection fixtures must inspect intermediate invariants, not just final golden output.

### Product and intake

- **AC01:** Starting a new relocated project using only location and plain work text creates a durable run and reaches managed work without a target-side Baton file, manual registration, seed artifact or migration commit.
- **AC02:** AC01 succeeds with both Claude Code and Codex as explicitly selected runtimes, with actual implemented adapters.
- **AC03:** With both ready and no runtime selection, the first managed session uses Claude Code. With confirmed applicable Claude allocation exhaustion, authorized fallback chooses Codex; missing quota telemetry and generic runtime failures do not trigger that fallback.
- **AC04:** A fallback preserves work/definition/recipe/checkpoint lineage, creates a fresh Codex conversation, and starts no replacement while predecessor productive effects or ownership are uncertain.
- **AC05:** Unavailable fallback leaves recoverable wait/probe state; a productive Codex session is not interrupted by Claude quota reset. No capacity purchase or reset-credit redemption occurs.
- **AC06:** Non-main, dirty, detached, unborn and non-Git fixtures enter preparation without forcing `main`, cleaning user changes, initializing Git, or writing sibling milestone worktrees.
- **AC07:** Same-basename/same-remote projects remain independent; moved/replaced locations are reconciled against identity evidence rather than silently merged.
- **AC08:** Invalid graph references/cycles/duplicate IDs/gates without authority are rejected before coding admission. Concurrent expected-revision proposals cannot silently replace one another.
- **AC09:** A dispatched session receives exactly the accepted source/context/definition and recipe snapshots, even if source files change afterward.
- **AC10:** Missing docs/tests do not reject a project. Missing external inputs/ambiguous desired behaviour produce the exact question while independent authorized preparation continues.

### Workspace, authority and verification

- **AC11:** Consistency tests that mutate source during capture cannot yield a falsely ready mixed baseline. Required ignored/local inputs are deliberately discovered, not wholesale copied.
- **AC12:** Workspace reuse refuses wrong project, baseline, branch/administration identity, ownership or preparation digest even when its path is a valid Git directory.
- **AC13:** Setup, coding and verification obey the trusted-host standing policy and actual runtime/OS/user restrictions without recurring Baton command approvals. No adversarial containment claim is made.
- **AC14:** Exact command/prompt text containing shell metacharacters, embedded newlines, quotes and delimiter lines is delivered as data unchanged and cannot execute as shell source through the transport.
- **AC15:** Private objects/settings/spool/DB are not made public by a permissive umask. Credential values are absent from public output, argv, notification payloads and ordinary recovery exports.
- **AC16:** A candidate consisting only of a valid old ancestor commit and unsupported completion claim does not close work. Acceptance requires the definition-bound candidate and required evidence.
- **AC17:** Candidate changes to tests/recipe cannot silently weaken the pre-dispatch acceptance contract. Independent checks run on the frozen candidate; semantic review cannot mark an unrun deterministic check passed.
- **AC18:** Baseline failures, introduced failures, unavailable checks and waivers remain distinguishable in stored and rendered results. No-change outcomes can pass with relevant evidence.
- **AC19:** A specific user waiver invokes the normal closure/accounting path but records waived success and unblocks only covered dependency requirements; ordinary answer/dismiss cannot manufacture a waiver.
- **AC20:** Two candidates sharing a destination serialize composition/verification/publication. Destination drift after checking forces recomposition/reverification before publication.
- **AC21:** Automatic local application occurs without routine merge approval when verified and safe. Unrelated dirty index/worktree changes remain intact; internal-ref publication cannot masquerade as checkout application.
- **AC22:** Crash injection at each non-Git application entry yields a recoverable applied/pending/conflicted inventory, never false atomic success. Divergent user content is not overwritten during continuation or guarded restoration.
- **AC23:** When exclusive directory application cannot be established, verified isolated output remains available and only applied-result dependencies remain blocked; no unsafe application guarantee is advertised.

### Lifecycle, durability and recovery

- **AC24:** Every external start, resume, delivery, setup/check/apply and notification effect has durable intent and required input references before invocation; fault injection cannot produce an intentionally unrecorded effect.
- **AC25:** Lost acknowledgements retain uncertain operations and reservations. Reconciliation finds the actual effect or proves absence; unavailable proof never causes blind duplicate launch/delivery.
- **AC26:** Same-value message retransmission, including reordered keys/whitespace or equivalent JSON escapes, creates no second semantic effect. Same-ID changed logical envelope conflicts; accepted IDs/generations remain fenced after explicit body deletion.
- **AC27:** Receipt, message authority, transition and resulting outbox work commit together. A crash at any file-move or post-commit point cannot lose accepted handoff consequences.
- **AC28:** A resumed native conversation gets a new generation, and an old ending cannot suppress its crash detection. A satisfied API wait never stops a productive resumed session again from its old timer.
- **AC29:** Repeated ineffective attempts, including unfinished/context-limit endings, share incident history and open a circuit; a new process/context window does not reset it. Periodic/boundary checkpoints preserve accessible work. Supported scheduled probes and changed prerequisites permit automatic recovery without lifetime retry-counter intervention.
- **AC30:** All start/retry/resume/manual/preparation/review/follow-up paths use common admission. Pending/uncertain starts, waiting live processes, cleanup and replacements remain correctly reserved.
- **AC31:** Same-batch prompts include committed peer reservations. Unknown target-resource effects serialize affected-project work; observed pressure queues and automatically resumes useful work.
- **AC32:** Missing/stale quota remains unknown and non-blocking; holds use evidenced runtime/account/limit scope, not model-name heuristics. No default personal reserve/budget/total-work ceiling blocks productive work.
- **AC33:** A live-PID failed first request becomes startup/provider/capability failure without waiting for generic age-based stall detection. Unknown runtime states and all question/dialog/worker waits are represented explicitly.
- **AC34:** Human takeover survives row disappearance/restart. Ambiguous actor evidence suppresses autonomous input. Direct-native interaction limitations are exposed when the runtime lacks mediated ordering.
- **AC35:** Pause, drain and cancellation races at each invocation boundary preserve durable intent and correct reservations. Cancellation suppresses automatic retries/fallback and never erases partial work.
- **AC36:** Terminal executions/attempts/units/handoffs/runs cannot reopen. A terminal conversation follow-up has new purpose/lineage and no inherited old handoff obligation.
- **AC37:** Every attention item, including two items for one unit and unassigned malformed input, has an individually addressable resolution path. Recheck evaluates the actual failed prerequisite.
- **AC38:** Adoption without identity/exclusive-control/report proof is observe-only and does not fabricate a dispatch; a fresh managed continuation remains available with captured context.

### Interfaces, health and maintenance

- **AC39:** CLI and API produce equivalent transitions and explanations. Expected-revision conflicts and changed command-ID payloads cause no new effects. Queries/preview do not reserve capacity or invoke model work.
- **AC40:** A deliberately hung external probe does not hold a database transaction, block status for that probe's duration, or prevent unaffected projects from reconciling. Every query/control call has a tested finite configured deadline.
- **AC41:** Failed/partial fleet reads remain unknown, not empty. Tick health distinguishes partial/failed/completed per component; independent watchdog detects unloaded/nonprogressing reconciliation without blindly restarting target work.
- **AC42:** Two simultaneous notification clicks open their own attention items, never a global newest target. Delivery failure retries by notification identity. OS acceptance does not become “person saw it” without observed action.
- **AC43:** Phone/remote/optional-independent-channel failures never block local work. An off-host outage guarantee is absent unless an independently operating supported channel is actually verified.
- **AC44:** Increasing retained terminal history does not cause ordinary status/admission/reconciliation to scan all logs, transcripts or objects. Demonstrate indexed queries with large irrelevant retained histories and bounded pagination.
- **AC45:** No age/size/closed-status cleanup removes prompts, rulings, artifacts, evidence, checkpoints or kept workspaces. Explicit deletion obeys its exact manifest and preserves retired namespaces.
- **AC46:** Interrupted release activation cannot expose mixed release files. Live executions retain pinned compatible profiles/releases. Incompatible schema rollback is refused.
- **AC47:** A validated backup/restore preserves consistent referenced evidence, fences old execution epochs and reconciles live effects before new work. Runtime authentication is re-resolved and unavailable native conversation continuity is reported truthfully.
- **AC48:** Injected disk-full/object-loss/database-integrity failures suspend affected writes/effects without deleting history, accepting evidence-free completion, or clearing uncertain reservations.
- **AC49:** Fresh-user macOS installation generates correct user/home paths and separately verifies scheduler, runtime authentication, settings/reporting and notification behaviour. Ordinary semantic checks do not implicitly compile/sign/install host components.
- **AC50:** Each adapter's supported-version claims have captured conformance evidence plus bounded real-runtime unseen-project start, question, handoff, verification/application and continuation trials. Simulated quota tests are labeled simulated until a real quota observation supports a live claim.

Verification must cover interleavings at every boundary in sections 4.6–4.8, independent state invariants, adapter captures, temporary relocated fixtures, isolated host installation, and bounded live trials. Tests must not require the canonical Baton checkout path, an unrelated target's live state, or production credentials. Under trusted-host mode, independent verification means separate operational control, not tamper-proof execution against malicious host code.

## 11. NON-GOALS

- Operating systems other than macOS, a multi-user hosted service, custom mobile application, or required external control plane.
- A requirement to modify target conventions, initialize Git, author Baton planning files, install target hooks/services, or configure budgets before work begins.
- Coordinating dependency graphs across independently managed projects. V2 can prepare accessible dependencies within the selected work but cannot silently start changing other projects.
- Transferring a live native conversation/private model state across hosts or runtimes. Accessible work/checkpoint continuation is supported and labeled accurately.
- Adversarial containment or tamper-proof control/evidence against unrestricted same-user trusted host code; a mandatory sandbox/VM is not part of ordinary execution.
- Guaranteeing exactly-once external effects without provider idempotency/authoritative lookup, or atomic multi-file application in the presence of uncontrolled writers.
- Proving correctness with unavailable criteria, hardware or credentials; fabricating verification, user authority, waivers, or a claimed successful check.
- Automatically buying capacity, creating credentials, redeeming reset credits, enforcing a default personal allowance reserve, or terminating productive work at a lifetime timer/retry count.
- General cross-runtime fallback on arbitrary errors. The standing fallback here is Claude Code allocation exhaustion to Codex, subject to explicit restrictions and reconciliation.
- Reopening a finished unit merely because a conversation is resumed/forked, or making a coding session authoritative over successor scheduling and local acceptance.
- Automatically publishing, pushing, deploying, sending external messages, or making unrelated destructive changes under the authority of local application alone.
- Guaranteeing phone receipt from OS transport acceptance, or detecting a powered-off host from a process running only on that host.
- Automatic history expiration, history-size eviction, pin renewal, or deletion of closed workspaces. Growth is an accepted tradeoff.
- Treating legacy V1/foundation source or saved logs as a parallel normative protocol or silently adopting historical execution authority. Legacy work can be inspected/adopted only through the evidence-based V2 boundaries.
- A third-party workflow framework, runtime-defined transition interpreter, embedded model-driven privileged command router, or copied provider branding. Baton uses its own identity and deterministic Swift semantic core.

## 12. DECISION TRACEABILITY

| Authority | Required specification coverage |
|---|---|
| C01 / O7 | Sections 1.1, 3.2, 5.1, 6.4: source-attributed revisioned graph and exact context; no target contract. |
| C02 / O2 | Sections 3.3, 3.6, 5.1, 7: stable identity, actual baselines, automatically prepared isolated workspaces. |
| C03 / O1 / O8 | Sections 1.3, 3.3, 6.5, 9.3: actual Claude/Codex adapters, profile evidence, exact default/exhaustion fallback. |
| C04 / O2 | Sections 1.1, 3.1, 5.1, 6.4: trusted host, explicit restrictions, scoped reports, private references, no containment claim. |
| C05 | Sections 2.2, 3.4, 4.6–4.8, 6.4: transactional inbox/outbox, stable identities, uncertain-effect reconciliation. |
| C06 / O4 | Sections 1.4, 3.4, 4.7: common admission, durable resource reservations, permissive quota/usage defaults. |
| C07 / O4 | Section 4 and 8: explicit generations/ownership, meaningful bounded recovery, attention, adoption, follow-up and control intents. |
| C08 / O3 | Sections 3.5, 4.6, 5.2–5.3: fixed verification, independent evidence, serialized integration, automatic safe local application. |
| C09 / O5 | Sections 2.3, 6.3, 8: bounded reconciliation, truthful health/admission, independent local watchdog. |
| C10 / O5 | Sections 1.4, 3.5, 6, 9.4: addressed commands/notifications, data-only input, optional native remote support. |
| C11 / O6 | Sections 3.1, 3.5, 6.4, 9.5: compatible immutable releases, consistent backup/restore, retained history and explicit deletion. |
| C12 / O7 | Sections 1.5, 2, 10: one typed deterministic semantic authority, explicit V1 inheritance, layered proof. |
| G4 / G5 deferrals | Section 11: no independently managed cross-project graph or live cross-host/runtime conversation transfer. |
