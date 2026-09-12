# ADR 0001 — Deterministic controller, explicit judgment sessions

Status: accepted; retained by the foundation audit. Governed by P-01 in `../GOVERNANCE.md`.
The controller and protocol changes are recorded as FND-001–FND-006; M03 integration governance
is GOV-001. This ADR governs the combined design, not a claim that every component is integrated.

## Decision

The controller embeds no model call. It derives candidate actions from explicit, validated inputs
and executes identified, recoverable operations. Coding and judgment are dispatched as sessions
with the same identity, ownership, artifact and completion rules. Human rulings remain explicit.
Deterministic integration and verification are controller responsibilities and do not violate this
boundary. Calling Baton a relay does not remove its state-management obligations.

The current completion contract is for Git-backed milestones. Future non-Git judgment jobs need
an explicit evidence/completion schema while retaining run, message and ownership accounting;
this ADR does not authorize a fabricated merge receipt or claim that a generic job type is implemented.

## Rationale and trade-offs

Deterministic policy can be tested without model quota and its action rules inspected directly.
A separate judgment session preserves a transcript, context and a human intervention path. This
separation does not prove that agents always judge correctly or that supervision costs nothing:
dispatched judgment sessions consume quota and are accounted for like other sessions.

The original prototype observations motivated avoiding an always-on model conductor. They are
local evidence, not a claim about every other orchestration design. Wider agent management can be
added without making scheduling state implicit inside a conversation.

## Reversal condition

If a recurrent, evidenced judgment point cannot be handled adequately by the current session,
a bounded judgment session or a human ruling, evaluate a separate decision under GOVERNANCE.md.
That evaluation must specify state ownership, failure/replay semantics, costs, migration and
acceptance criteria. An inline model call is not added as an undocumented convenience in a tick.
