# Repository-wide audit coverage

The user's audit authorization applies to the entire repository and its future program shape.
M03 is an active workstream to preserve, not the audit's boundary. This index maps the original
architectural findings and improvement opportunities to the owning documents, mechanisms and
remaining acceptance. It introduces no competing requirements or claim of universal completion.

The original audit examined the M01/M02 baseline at
`131205d9e68165cc48215983e30aa8eb2c34c001`. The foundation implementation and its captured 31
historical regression / 61 behavior-check result are documented in `validation/foundation.txt`
and `reviews/foundation.md`. That result does not certify the current M03 worktree, future
milestones, live provider behavior or an assembled release.

## Finding-to-layer map

| Audit area | Governing requirements | Owning layer/documents | Existing evidence and remaining acceptance |
|---|---|---|---|
| A-01 Completion proved only arbitrary ancestry | P-02/P-08; F-11/F-19–F-24 | CONTRACT §4; integration/receipt boundary in ARCHITECTURE; `lib/integrate.sh`, `lib/inbox.sh` | Foundation rejects old-ancestor completion and mismatched sessions; checked receipt/replay tests passed. Each target still needs its own standing-check and onboarding evidence. |
| A-02 Parallel worktrees shared an unsafe close-out | P-08; F-09/F-19–F-23/F-43 | CONTRACT; ARCHITECTURE; M06 | Foundation serializes integration and preserves human main advancement. Finer-grained leases and concurrent project workers are not implemented; M06 must amend conservative admission and prove its replacement. |
| A-03 Move/append and launch/record gaps lost decisions | P-04; F-02/F-03/F-14/F-15/F-27/F-28 | Journal, dispatch and processing boundaries | Foundation fault tests cover before/after acknowledgement and lost launch/promotion acknowledgements. Future delivery effects need the same proof in M04. Atomic replacement is not power-loss durability. |
| A-04 Mutable per-session pathname confused message identity | P-02/P-05; F-11–F-16/F-40 | CONTRACT §5–§7; publication/claim/archive | Foundation tests duplicate IDs, conflicting content, printed fallback and replacement after claim. Ordering/correlation of different endings across deliveries remains explicit M04 work; it is not solved by UUID filenames alone. |
| A-05 Failed observations became an empty fleet | P-03; F-04/F-05/F-35/F-44 | Adapter, admission and scheduler | Foundation distinguishes failure/incompatibility and validates safety fields. M03 must retain that boundary; new provider/version capabilities require M07 conformance evidence. |
| A-06 Redispatch erased escalation history | P-09; F-25/F-41 | Recovery policy; M04 | Cross-attempt ladder check passed. The full retry/delivery policy is pending and must distinguish transient/quota/configuration/unknown failures without silent model changes. |
| A-07 Several scheduling authorities and mixed revisions | P-06; F-06–F-08/F-40 | Plan, CONTRACT, SPEC; M03/M04 | Foundation validates committed graphs, gate approvals and forbidden handover scheduling fields. M03 must remove historical disposition selection; M04 must not recreate it through uncorrelated endings. |
| A-08 Hash-only takeover and action-before-ownership | P-07; F-16–F-18/F-39/F-42 | Ownership, read models and command boundary; M05 | Foundation consumes without stopping and tests same-text/new-UUID refusal. Direct typing remains best-effort; ruling delivery, management and any cancellation need explicit operation semantics. |
| A-09 A dead controller also disabled diagnostics | P-03/P-10; F-26/F-29/F-35/F-36 | Lock, status, notification and tick | Kernel-lock death/status tests passed. M03 delivery/partial-tick evidence is pending. A recovering controller's gap report is not an independent outage detector. |
| A-10 Shell/no-state slogans obscured state complexity | P-02/P-04/P-12; F-27/F-39/F-45 | GOVERNANCE; ARCHITECTURE lifecycle/storage boundaries; ADR 0002 | Current explicit JSON/journal boundaries are implemented. Typed transactional storage and power-loss guarantees remain future decisions driven by measured need, not file splitting or language alone. |
| A-11 A small-clause contract hid repeated prompt/close-out burden | P-01/P-06/P-12; F-06/F-19/F-39 | CLAUDE, CONTEXT, CONTRACT, all current briefs | Stable rules have one governing home; successor prompts are not recursively rewritten. Worker scope is distinct from repo-wide maintenance authorization. Historical fixtures/prompts remain evidence, not current instructions. |
| A-12 Deny patterns/allowlist overstated containment | P-11; F-31/F-42/F-44 | CONTRACT; SPEC limits; MIGRATION; M08 | Foundation requires explicit trusted-local choice and does not present allowlist widening as containment. OS-enforced isolation is not implemented; widening the trust boundary requires its own design and evidence. |
| A-13 Provider internals leaked into policy | P-03/P-11; F-05/F-40/F-41/F-44 | Adapter contract; M04/M07 | Calls/schema checks are isolated in foundation code. Live compatibility is not established by shim tests; copy-fork, delivery and remote capabilities must be proved for their actual adapter/version. |
| A-14 In-place install could mix releases/change active hooks | P-11; F-30/F-37/F-45 | Release boundary; MIGRATION; M03/M08 | Foundation stages and selects immutable releases and tests repeated installation. M03's signed-shell and host/service proofs must be incorporated. Rollback/restore cannot simply point old code at incompatible state. |
| A-15 Account-wide usage was treated as a model budget | P-03/P-12; F-09/F-41/F-43 | Resource policy; M06 | The scope/limitations are corrected; predictive quota behavior is not implemented. M06 must distinguish observed resources, reservations, stopped work and stale/unknown telemetry. |
| A-16 Governing documents could drift or overwrite parallel decisions | P-02/P-12; F-38/F-39 | GOVERNANCE; DECISIONS; ADRs; MILESTONES | Document roles, implementation/observation status, FND/GOV namespaces and M03 preservation are explicit. New changes must update affected layers and evidence together. |
| A-17 Golden snapshots were mistaken for recovery proof | P-04/P-10/P-12; F-14/F-23/F-28/F-40–F-45 | SPEC verification; tests/CASES; each milestone | Foundation adds independent fault/interleaving assertions. Future milestones own cross-layer and adapter conformance tests; old passing snapshots cannot certify new semantics. |
| A-18 Operational restoration could replay already-real effects | P-03/P-04/P-11; F-45 | MIGRATION recovery procedure; M08 | Operating rules now cover coherent restoration and external reconciliation. No automatic repair/restore command or validated power-loss recovery is claimed. M08 owns the simulation and target-specific operating evidence. |

## Documentation ownership and application

The backbone is `CLAUDE.md`, `CONTEXT.md`, `CONTRACT.md`, `GOVERNANCE.md`, `SPEC.md`,
`ARCHITECTURE.md`, `DECISIONS.md`, the ADRs, `MILESTONES.md`, every current milestone brief,
`MIGRATION.md` and `tests/CASES.md`. Each has been reviewed as part of the same program design.
Foundation remediation history belongs in `FOUNDATION.md`; M03-specific coordination belongs in
`M03-RECONCILIATION.md`. Neither narrows the authority of the repository-wide requirements.

M01/M02 completion records, `.scratch/` research/prototype material and contract-1 fixture data are
retained for provenance and regression purposes. Their old instructions are not made normative by
being present in the repository. Rewriting their captured outcomes to match today's design would
weaken evidence rather than apply the audit. Current entry documents and the test coverage guide
explicitly classify them.

## Acceptance ownership

| Workstream | Repository-wide obligations to prove |
|---|---|
| Foundation / M02-b | Existing identity, storage, observation, ownership, integration and release primitives at the captured checkpoint; do not claim later behavior. |
| M03, already in progress | Safe tick composition, observation generations, admission parity, partial completion, notification delivery and host/release capabilities. |
| M04 | Delivery correlation and replay; classified/bounded recovery across attempts; late endings and preserved model/scope. |
| M05 | Stable escalation resolution and ruling delivery; ownership-independent management commands; honest requested versus observed state. |
| M06 | Resource leases, fair scheduling order, explicit changes to admission, exclusive integration and conservative unknown-capacity handling. |
| M07 | Actual adapter/version/remote conformance without leaking provider-specific assumptions or widening trust silently. |
| M08 | Target-specific migration, verified unattended acceptance and restoration rehearsal against external effects. |
| Post-v1, explicitly scoped | Additional providers/management surfaces, typed transactional storage, stronger isolation or multi-host ownership; preserve the same protocol properties. |

Unimplemented acceptance remains pending even when the governing design has been corrected.
This is intentional evidence discipline, not a restriction of the audit to one milestone.
