# Architectural governance

This document is the governing application of the accepted architectural audit. It defines how
Baton's principles, requirements, protocol, implementation and delivery evidence stay consistent.
It does not override the user's instructions or authorize builds, live actions or deployment.

## Repository-wide scope

The accepted audit applies to every current layer and every future milestone, not only M03.
`AUDIT-COVERAGE.md` is the traceability index; it records implementation evidence separately from
accepted design requirements. M03 reconciliation is one application of these principles.

“Implement only this milestone” bounds a dispatched worker's assignment. It does not restrict a
direct user-authorized repository-wide audit or maintenance task. Such a task may correct founding
documents, cross-cutting code and later briefs together. Preserve other workstreams and existing
user constraints; do not manufacture a new authorization requirement merely because a correction
crosses a milestone boundary.

## Authority and document roles

| Document | Owns | Cannot do |
|---|---|---|
| User instructions and project working rules | Authorized scope, constraints and human decisions | Be silently weakened by a brief or generated prompt |
| GOVERNANCE.md | Architectural principles, decision/change procedure and evidence rules | Claim that a principle is implemented merely because it is written |
| SPEC.md | Testable requirements and explicit guarantee limits | Treat unavailable evidence or future implementation as verified behavior |
| CONTRACT.md | Project-facing message, ownership and integration protocol | Be changed incompatibly without a version/migration decision |
| ARCHITECTURE.md | Mechanisms, module boundaries, current versus branch-local implementation | Turn an implementation shortcut into a new policy authority |
| MILESTONES.md | Committed dependency graph, delivered scope and separate progress notes | Put prose progress in machine Status cells, or infer runtime liveness from a branch |
| Milestone briefs | Bounded implementation scope, acceptance and evidence | Waive cross-cutting invariants or silently restore superseded assumptions |
| DECISIONS.md and adr/ | Rationale, alternatives, supersession and source provenance | Win simply by having the highest number or most recent timestamp |
| FOUNDATION.md, reviews/, validation/ | Remediation history and observations from named checks | Certify a different branch, live environment or protocol version |
| AUDIT-COVERAGE.md | Finding-to-requirement/evidence/workstream traceability | Replace the specification or mark an accepted future design as implemented |
| .scratch/ and historical prompts | Research/prototype evidence | Direct current execution without validation against the current contract |

Read the user instructions first. Use the current requirements and protocol together with these
principles. If those normative documents disagree, identify the conflict and correct the relevant
requirement/contract/decision before the affected external action. Do not silently select whichever
file is convenient. Unaffected development and read-only investigation can continue.

## Non-negotiable architectural principles

| ID | Principle | Consequence / evidence needed |
|---|---|---|
| P-01 | Deterministic control and explicit judgment | The controller selects effects by reviewable rules. Judgment sessions have the same run/message/ownership accounting as coding sessions. |
| P-02 | Identity precedes effects | Project/milestone, run, recovery episode, provider session, delivery, message and integration operation are distinct identities. A PID, path, display name or clock reading cannot substitute for all of them. |
| P-03 | Evidence retains uncertainty | Observations are successful, unavailable or incompatible. Missing evidence never proves absence, successful completion, restored capacity or human consent. |
| P-04 | Effects are recoverable | Persist intent before an effect and acknowledgement afterward. Unknown outcomes reserve their work. Retrying requires idempotence or reconciliation, not hope. |
| P-05 | Messages are immutable observations | Claim before validation; deduplicate by stable identity and content. A handover cannot create scheduling authority or authorize a process action. |
| P-06 | One committed scheduling authority | Graph/brief/base share a revision. Person-owned gate approvals are authorization, not a second dependency graph. Model-written advice cannot silently override either. |
| P-07 | Human ownership is explicit | Claim/release and ruling delivery are separate operations. New/unreadable intervention evidence holds automation; matching text cannot release ownership. |
| P-08 | Integration is exclusive and verified | Workers prepare candidates; an identified integration operation checks the combined tree and guards promotion. Completion is bound to that receipt, never merely any ancestor of main. |
| P-09 | Recovery budgets follow the work | Attempts and processes may change without erasing failure history. Reset requires verified progress or an explicit human disposition. |
| P-10 | Diagnostics survive failures | Read-only status must work during mutations and show pending operations, questions and uncertain outcomes. Notification intent is not proof of delivery. |
| P-11 | Trust, capabilities and releases are explicit | Same-account deny patterns are not OS isolation. Capability proofs name the host/runtime/release. Immutable release selection does not by itself certify executable signing or FDA. |
| P-12 | Complexity buys an explicit guarantee | Prefer the smallest mechanism that establishes the required property. A language rewrite, more models, or more services is not itself a correctness improvement. |

SPEC.md's F-* requirements and the reconciliation checklist turn these principles into acceptance
cases. A brief may refine them, but cannot defer an already required safety property behind an
unimplemented milestone. Extend resource/provider breadth only when the replacement invariant is proved.

Principles are distinct from implementation choices. For example, one open run per project is the
foundation's conservative admission policy; exclusive integration and accounted-for capacity are
the underlying properties. M06 may replace that policy only by explicitly amending F-09, its tests
and migration rules together. Similarly, shell/JSONL and fixed provider versions may change without
weakening ownership, identity or recovery. Do not turn a temporary mechanism into a permanent
constraint on the intended orchestration product.

## Change procedure

For a material architecture change, record: the concrete problem and affected P-/F- IDs; evidence
and its branch/runtime provenance; the proposed ownership/state transition; interruption and retry
behavior; human control and migration consequences; alternatives and the chosen trade-off; and the
acceptance cases that would disprove the guarantee. Update the protocol and requirements before
presenting a conflicting implementation as the current contract. Keep implementation descriptions
and milestone acceptance in the same change.

Every material decision names the layer that owns it and its delivery status: implemented and
tested at a named checkpoint, implemented but unverified, accepted design pending a named milestone,
or historical/superseded. Use the status to prevent a checked remediation list from becoming a claim
that all future orchestration behavior already exists. New scope without an implementation owner
is an unresolved requirement, not a delivered feature.

Observed provider behavior is versioned evidence, not a timeless architectural rule. A prototype
finding can be retained while its original implementation is replaced. Each decision should say
whether it is an accepted invariant, an implementation choice, a measured observation or a proposal.
Those categories have different reversal conditions.

## Concurrent work and decision identity

M03 is currently in progress on `m03` in `Baton-M03`; foundation work is on
`codex/architecture-foundation`. Neither branch is silently the other's integrated result. Preserve
committed and uncommitted work, re-read heads before integration, and reconcile overlapping modules
by invariant rather than choosing all of “ours” or “theirs”. The M03 bridge checklist is
`docs/M03-RECONCILIATION.md`.

M03 already allocated D-038 onward. Its IDs and evidence stay intact. Foundation decisions formerly
using D-038–D-043 now use FND-001–FND-006. This change's governance decision is GOV-001. Future
parallel work uses a unique workstream prefix for provisional decisions; one integration owner may
allocate canonical D-* IDs after checking the combined log. There is no global “next free D-number”
reservation while another workstream is allocating numbers. References spanning branches name their
workstream and commit/checkpoint. Preserve a mapping when renaming; never overwrite the other decision.

This documentation namespace does not alter the runtime gate grammar: committed gate clearance
still uses a D-* token and its matching person-owned approval. Finalize any decision intended to
clear a gate before requesting that authorization; no new gate is introduced by this document.

## Evidence, progress and completion

“In progress”, “implemented on a branch”, “integrated”, “fixture verified” and “live verified” are
separate claims. Record the relevant revision, dirty state, command/output and environment. An empty
brief evidence section does not prove that no implementation exists. A branch name does not prove a
live process exists. Read-only inspection of M03 is not a rerun of M03's tests or its live proofs.

Keep machine Status blank until completion criteria pass; use the ignored Progress column and prose
for ongoing work. A new dependency such as foundation compatibility is an acceptance/integration
prerequisite for an already-running milestone, not an instruction to restart it or launch a duplicate.

A combined candidate needs both the foundation fault suite and adapted M03 cases. Preserve useful
legacy cases, but never count version-1 mutation expectations as contract-2 proof. Mark unavailable
or unrun proofs explicitly. Progress reports do not grant deployment authority.

## Expansion after version 1

New providers implement the observation/effect boundary; management interfaces read projections and
submit identified commands. Neither writes independent state or schedules around the controller.
Multi-host execution needs ownership fencing and a durable shared protocol; stronger isolation needs
an OS boundary; power-loss recovery needs a synchronized transactional store. A typed core may be the
right implementation, but its acceptance is preservation or strengthening of these properties.
Autonomy is the result of trustworthy transitions and recovery, not the removal of human ownership
or verification to keep agents moving.
