# ADR 0002 — Durable orchestration boundaries

Status: accepted design; foundation primitives fixture-verified on their workstream; combined M03
acceptance pending. Decision sources: FND-001–FND-006 and GOV-001/GOV-002 in `../DECISIONS.md`.

## Context

The audit found that ancestry checks, mutable session filenames, move-before-log consumption,
post-launch recording, hash-only ownership, shared canonical close-out and attempt-scoped recovery
could not establish the stated guarantees. M03 was concurrently implementing the scheduled tick.
The corrections must preserve that work while changing the unsafe boundaries before activation.
Their scope is repository-wide. `AUDIT-COVERAGE.md` maps each finding to protocol, state,
integration, recovery, resource, provider, operating and verification layers. M03 coordination is
one workstream within that architecture, not the boundary of this decision.

## Decision

Apply P-01–P-12 from GOVERNANCE.md through SPEC.md and CONTRACT.md. Runs precede effects;
messages are immutable observations; provider errors remain uncertainty; human ownership is
explicit; integration is exclusive and receipt-bound; recovery budgets follow work across attempts;
and releases/capability proofs retain their identity and limits. These principles are defined once
in governance rather than independently restated as competing rules in each milestone prompt.

M03's useful implementation and measurements are adapted through M03-RECONCILIATION.md. Its
existing code is not discarded, presumed unstarted, or certified by the foundation-only test run.
A successful textual merge is insufficient evidence of protocol compatibility.

Later milestones also inherit explicit delivery ordering, separate lifecycle/ownership/liveness
facts, evidence-based recovery classification, resource-lease accounting, adapter conformance and
restoration rules. F-39–F-45 and each owning brief define their acceptance; recording them does
not claim those future behaviors already exist.

## Alternatives and consequences

Patching only individual symptoms would preserve ambiguous authority and replay. Rewriting into
Swift immediately would change the implementation language without itself proving the protocol.
The chosen foundation keeps local shell tools and explicit JSON boundaries, adds fault tests, and
makes a typed transactional core an intentional future migration. Current atomic replacement is
not advertised as power-loss durability; pattern denies are not advertised as OS isolation.

The protocol change requires project migration and combined M03 testing. Autonomous progress
continues within explicit ownership and capacity rules; uncertainty may hold a run for reconciliation.
There is no additional approval gate in this ADR and no authorization to interrupt an existing
session, alter live installation state or run an unapproved build.

## Acceptance and reversal

The foundation's captured tests support only their tested checkpoint. Combined acceptance requires
the active M03 checklist and host-specific evidence. A stronger storage/runtime/provider mechanism
may replace an implementation choice if the same fault/ownership/integration tests still hold and
new guarantees have explicit evidence. Weakening a principle requires a new recorded decision and
user-authorized scope, not a later brief that quietly omits the requirement.
