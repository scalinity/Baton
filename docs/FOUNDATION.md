# Foundation hardening

The 2026-09-12 audit and the user's acceptance authorize this cross-milestone correction alongside
M03, which is already in progress in the `m03` worktree. This work does not claim combined M03
completion or install a live runtime. See `M03-RECONCILIATION.md` for the compatibility handoff.

## Governing principles

The audit's principles are now normative P-01–P-12 in `GOVERNANCE.md`, with testable requirements
in `SPEC.md` and protocol obligations in `CONTRACT.md`. This file is the foundation remediation
record, not a competing source of architectural policy.

## Implementation checklist

These checkboxes record the foundation implementation, not completion of every subsequent feature.
The repository-wide finding/layer/evidence map is `AUDIT-COVERAGE.md`; its pending acceptance
owners remain responsible for the behavior described by F-39–F-45 and other later requirements.

- [x] Kernel lifetime locking; coherent atomic journal writes and read snapshots.
- [x] Bounded provider adapter with tagged observations and version checks.
- [x] Committed plan snapshots, graph validation, revision provenance, strict worktree identity.
- [x] Durable dispatch intent, run identity, reconciliation, explicit legacy adoption.
- [x] Immutable message claim/validation/ack, replay deduplication, recovery and quarantine.
- [x] Explicit claim/release and ownership guards; no implicit stop on consumption.
- [x] Serialized integration and exact completion receipt; no automatic worktree deletion.
- [x] Recovery episodes preserve failure budget across redispatch.
- [x] Status exposes uncertainty, processing leftovers and provider errors without the mutator lock.
- [x] Atomic release installation, permission boundary and migration instructions.
- [x] Replace contradictory contracts, invariants and future milestone prompts.
- [x] Fault/interleaving regression tests and two independent review passes.

The implementation retains shell entry points and hooks for this release. It introduces no compiler, package, server or additional model. The typed JSON boundaries and explicit effect records are the migration seam for a future Swift core; a language change alone is not a correctness fix.

## Result

Implemented as M02-b, with current runtime fixes and rewritten M03–M08 acceptance requirements.
Validation passed: 31 retained historical regression scenarios and 61 foundation checks, including
process interruption, message interleaving, ownership, corrected integration retry, lost promotion
acknowledgement and immutable installation. See docs/reviews/foundation.md and
docs/validation/foundation.txt for scope and captured evidence. These results cover the foundation
checkpoint only; M03's branch and the future combined candidate require their own evidence.

This is a protocol migration, not a live deployment. The installed home and real sessions were not
changed. Power-loss durability and OS-enforced isolation remain explicitly outside the current
trusted, process-interruption-tested foundation; future versions must implement and prove stronger
mechanisms before claiming those guarantees.

## Repository-wide follow-through

The user's scope clarification is recorded as GOV-002. The current backbone applies the audit to
all layers and every remaining milestone, with 18 areas mapped in AUDIT-COVERAGE.md. Lifecycle,
delivery, recovery classification, management authority, resource accounting, provider conformance
and restoration obligations are explicit. F-39–F-45 name their implementation owners; they are not
newly checked implementation items above. See reviews/repository-docs.md and
validation/repository-docs.txt for the documentation review and structural validation.
