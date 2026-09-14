# Baton V2 validation

**Verdict: not ready to execute the milestone chain as written.** The graph is mechanically sound; several contracts that the graph connects are not. The most direct counterexample is a request to fix a failing test: the readiness transition requires baseline checks to pass before the coding session can start.

Validation date: 2026-09-14. Basis: the working-tree versions of `01-findings.md`, `02-decisions.md`, `03-spec-v2.md`, all **44 V2 briefs** (M09–M50, M10-b and M10-c), and `docs/MILESTONES.md`. HEAD is `f230a8037e4fd2aa341dac0d88dab1c671a28c99`; the V2 documents and most new briefs are untracked, and CLAUDE.md/the milestone index already have user changes. Those working-tree documents, not HEAD's older plan, are the subject of this review.

The review also checked the repository startup/close-out instructions, interface registry and existing test-runner boundary. Repeated milestone template text was compared mechanically; every brief's distinct preconditions, readings, scope, interfaces, checklist, acceptance, split and prompt content was reviewed. No product code, source document, gate or milestone status was changed. No compiler, test suite, installer, runtime session or live target was invoked. The only deliverable is this findings document. Runtime/filesystem scenarios below are **design counterexamples**, not claims of observed failures in an implemented V2.

References use repository-relative paths and one-based lines in these reviewed versions. `S` means `docs/v2/03-spec-v2.md`; `D` means `docs/v2/02-decisions.md`. `V01`–`V16` identify validation findings; they are explained in section 3. **P1** means a normal workflow, preservation guarantee or execution-chain invariant can fail; **P2** means a missing contract/proof or reproducibility defect requires an implementation choice the plan has not resolved. A future file's absence today is not itself a finding: it must be missing at the point its consumer needs it.

## 1. FRESH-SESSION SIMULATION

### Simulation rules and shared cold-start failures

For each entry below, assume the stated predecessor really completed, its source/tests/architecture facts are in the repository, and its required checks passed. The simulated session can inspect that repository and its own brief, including referenced spec/decision documents; it cannot borrow another session's memory or a sibling brief's completion appendix. Fixture graphs may stand in for future **data** where the plan explicitly permits that. They may not masquerade as implemented effects.

The current implementation gate is deliberately uncleared. M09 correctly requires a later implementation request and actual compile/test authority; this validation request grants neither. That is an intentional entry boundary, not a defect. Likewise, the absence today of Package.swift, Sources, tests/v2 and future evidence files is expected.

Three shared defects remain even after legitimate entry authority is supplied:

- **V12 — splitting can deadlock the chain.** The common procedure leaves an oversized parent incomplete, makes the remainder depend on that parent, and forbids completing the parent with unmet acceptance. It never says how acceptance is partitioned so the remainder becomes eligible. M10 additionally names the already-existing `M10-b.md` as its new split file. A cold session cannot perform that instruction literally while preserving the existing typed-model milestone.
- **V13 — the claimed repository-only close-out needs external skill definitions.** Every prompt requires `/review-2` then `/address`; the repository does not carry their implementations/instructions or a complete fallback. A session lacking the author's installed skills must improvise that mandatory procedure. This is separate from ordinary host prerequisites such as an authenticated runtime.
- **V13 — proposed paths become mandatory paths in the next brief.** Each §5 permits equivalent interfaces at other locations and tells the author to record actual paths, but successor §2 commands hard-require the proposed filenames and tell the session to stop on a missing prerequisite. For example, M12 may implement its command boundary elsewhere, but M13:11 requires `Sources/BatonCore/Commands.swift` and `Queries.swift`. The next session must choose between the recorded equivalent implementation and its literal entry test. Prompt refresh does not require refreshing these §2 commands.

### M09 — The portable V2 check boundary

**Entry:** V1 source/tests and the V2 specification, with no Swift package. **Walk:** inspect the installation scenarios, separate their compile/sign/install work, establish the executable and bootstrap runner, establish current-source provenance, run the authorized checks, then close out. This is a legitimate first implementation boundary: it does not require its own binary before creating it. **Break:** mandatory external review/address commands and the split procedure are not self-contained (V12/V13). The exact provenance mechanism is explicitly M09's engineering responsibility; its absence before M09 is not a forward dependency. See M09:11–13, 44–48, 56–57, 67, 98–103.

### M10 — Private objects and transactional state

**Entry:** M09's executable, runner and provenance mechanism. **Walk:** implement private objects, SQLite transactions, foundational types, configuration and audit; fault-test durability. **Break:** the prescribed overflow action creates `M10-b.md`, which already exists and owns the complete model contract. The session must overwrite it, reinterpret it or invent a different ID. The general incomplete-parent split deadlock also applies (V12). Configuration defaults/durability pragmas can reasonably be selected and recorded here; they are not missing product decisions. See M10:44–47, 67.

### M10-b — The complete typed V2 record contract

**Entry:** private storage and foundational types. **Walk:** inventory every §3 record and §6 shared value, define them once, construct representative in-memory graphs. **Break:** the promised complete contract has no identifiable baseline-check result to satisfy `CheckResult.baselineResultRef`, no defined preparation-plan/review-result payload, and no exact application preimage metadata shape (V03/V04/V10). A list of fields can pass while these producer/consumer relationships remain unusable. These are semantic contract holes, not a need for future lifecycle handlers. See M10-b:19, 44–47, 56–57.

### M10-c — Complete record persistence and fixture graphs

**Entry:** the complete model as M10-b actually defined it. **Walk:** map records, enforce references and immutability, insert mutually referring fixture graphs atomically, and retain fixture APIs. Atomic insertion of mutually referring records is explicitly owned here, so ordinary FK cycles are not a missing dependency. **Break:** it cannot prove a complete baseline-check reference relationship from the specified model, or demonstrate metadata restoration from unspecified preimage encoding (V04/V10). Inventing fixture-only reference conventions would make later fixtures pass against a contract that later producers must rediscover. See M10-c:44–47, 56–57.

### M11 — Exact wire values and logical identity

**Entry:** typed/persisted fixtures and private objects. **Walk:** implement strict parsing and the specified canonicalization, retain original bytes, exercise equivalent encodings and invalid tokens. **Result:** this slice can survive a cold start after the shared prerequisites. The canonicalization rules are unusually concrete, and changed timestamps are explicitly conflicts. **Inherited risk:** strict unknown-field rejection makes it impossible for later sessions to quietly add missing preparation/review/control payloads without a deliberate protocol decision (V03/V11). See M11:44–46, 55–56; S:538–550.

### M12 — Commands, queries and durable receipts

**Entry:** canonical wire values and stored records. **Walk:** establish execute/query, durable command IDs, projections, cursors and explicit unsupported handlers. **Result:** leaving future verbs unsupported is coherent and specifically required; it is not a stub falsely claiming a complete product. **Break:** the complete public verb set contains no operation for M38's requested restoration, so the command boundary cannot predeclare the future action M38 is expected to support (V11). Its acceptance also ambiguously asks for “changed-ID payload conflicts,” whereas the spec conflicts on a changed payload under the **same** ID (V13). The snapshot cursor implementation is a local engineering decision, with constraints supplied. See M12:44–47, 56; S:474, 484–507.

### M13 — Durable effects and uncertain outcomes

**Entry:** command boundary, transactions and fixture records. **Walk:** implement claim/invocation/observation state, reservations and evidence-based resolution using fake workers. **Result:** fake external effects are explicitly allowed and the uncertainty boundary is specified. No live adapter is required. **Break:** the proposed-file entry tests can reject an otherwise compliant M12 implementation (V13). Future command handlers must call this journal; this milestone alone cannot prove that all later callers do. See M13:11, 44–47, 56–57.

### M14 — Run, unit and handoff transitions

**Entry:** durable effects/reservations and valid fixture graphs. **Walk:** implement every listed edge, reject unlisted edges, exercise guards and atomic consequences. **Break:** implementing the tables faithfully prevents fixing a failing baseline and strands an already-prepared blocked unit when its guard clears (V01/V02). Its own exhaustive legal/illegal-edge test would then cement those defects. This milestone cannot both obey the table and implement the contradictory recovery/readiness behavior later demanded by M31. See M14:45, 56; S:294–301.

### M15 — Execution generations and operator ownership

**Entry:** parent transitions and effect intents. **Walk:** implement generation authority, reservation transfer, sticky ownership and pause/drain/cancel races with fake workers. **Result:** fake stop intents and explicit terminal-process cleanup separation make this boundary implementable. **Inherited break:** continuing a paused run can reactivate the run while leaving its prepared unit in `blocked`, because no permitted unit edge restores readiness (V02). Native ownership evidence remains honestly deferred. See M15:44–47, 56–57; S:295–301, 352–360.

### M16 — Scoped reporting and transactional inbox

**Entry:** canonical wire parser, grants, generations and transactional transitions. **Walk:** validate all six report kinds, retain raw submissions, atomically record consequences, provide evidence upload/spool retry. **Break:** later preparation and review sessions lack specified result payloads and successful non-candidate ending semantics (V03). Treating arbitrary `progress` evidence as those results requires an additional documented decoder/authority/settlement contract. Implementing candidate receipt before freezing is legitimate: the brief explicitly leaves it a pending claim. See M16:44–47; S:223, 331–349, 542–557.

### M17 — Project intake and source provenance

**Entry:** commands, reports and lifecycle records. **Walk:** create the request/run, discover identity and sources, retain inaccessible-source attention, leave interpretation pending. **Break:** this is the first consumer of bounded real filesystem/Git/URL reads, while M13 only establishes fake workers and M22 later introduces the general bounded host invocation boundary. No earlier public bounded source-fetch contract is named. The session must implement and export that narrow primitive here, or reach forward into M22 (V14). Pending interpretation itself is an explicitly supported partial-product state. See M17:38, 44–47; M13:27, 38; M22:44–47.

### M18 — Consistent actual-state snapshots

**Entry:** project/source identity, capture intents and object storage. **Walk:** capture actual Git/directory state, preserve metadata, create manifests, detect concurrent mutation and collisions. **Break:** repeated inventory comparison is permitted as a consistency technique, yet acceptance requires that concurrent mutation *never* yield a mixed ready baseline. An ABA writer can defeat that technique (V05). The brief names staged/unstaged state but the exact manifest lacks a separate index-tree/stage encoding (V10). General bounded host calls still arrive later (V14). See M18:44–47, 56–57; S:250–256.

### M19 — Owned isolated workspaces

**Entry:** real snapshots and identity/ownership records. **Walk:** choose worktree/clone/copy, journal creation, verify reuse and leave preparation pending. **Break:** the snapshot may be representable in object storage but impossible to materialize under `H/workspaces` on the host filesystem; no compatible-volume allocation path is assigned (universal case 3). For nested selections/external relative dependencies, the session must settle the selected-root versus execution-root mapping, not simply preserve symlink text. The rules forbid silent widening but do not supply that mapping. See M19:44–47, 56; S:145–147, 165, 202, 254, 610–618.

### M20 — Revisioned work graphs and fixed definitions

**Entry:** sources, authorization, proposal receiver and lifecycle guards. **Walk:** validate graphs, freeze definitions and null-baseline recipes, reject revision races, bind dependency selectors. **Break:** the specification says to accept semantically unambiguous in-scope proposals but has not defined the managed interpreter's structured authority assessment (V03). Structural validation can run now; it cannot decide arbitrary prose meaning. A separate problem arises when multiple predecessor selectors supply conflicting versions of one path: M31 is told to consume exact results, but no conflict/composition rule is fixed here. This must remain explicit uncertainty rather than implicit last-result-wins. See M20:44–47, 57; S:176–178, 550.

### M21 — One admission decision for every operation

**Entry:** accepted graphs, ownership/intents and durable reservations. **Walk:** implement the common operation-specific guard matrix and pure preview; reserve peers transactionally. **Result:** synthetic quota/readiness/resource facts are valid inputs at this layer; future adapters are not required. **Inherited break:** a positive admission verdict does not supply the missing blocked-to-ready lifecycle transition (V02). Unknown-resource serialization must also be coordinated with service/process cleanup so a preparation/review does not wait on its own retained writer reservation; the fixtures need that composed case. See M21:44–47, 56–57; S:399–401.

### M22 — Coherent profiles and bounded host calls

**Entry:** admission and durable effects, plus earlier source/snapshot/workspace implementations. **Walk:** establish adapter ports, profiles, classified environments, secret resolution and bounded host invocation. **Break:** earlier real calls already needed this boundary (V14). Also, S:595 says model/effort defaults come from a validated profile, but RuntimeProfile:190 has no explicit model/effort fields or designated typed settings keys (V04). The session must settle that contract before the two adapters independently choose defaults. Merely implementing both choices in opaque settings would not make them discoverable without documenting the schema. See M22:44–47.

### M23 — Managed kickoff and launch reconciliation

**Entry:** adapter ports, graphs, workspaces, profiles and reports. **Walk:** assemble exact context, allocate grants/reservations, invoke fake adapters and reconcile launch uncertainty. **Result:** coding-purpose fixture launches are properly staged. **Break:** the common kickoff content requires fixed definition/recipe/unit/attempt context, while M29 will use this launcher to create that first definition. Execution permits null unit/attempt, but no separate preparation kickoff and successful result contract is specified (V03). Fixtures using an already-valid coding graph can miss this bootstrap gap. See M23:38, 44–47; S:195, 559.

### M24 — Checkpoints, incidents and meaningful recovery

**Entry:** generation-aware launch/report and effect reconciliation. **Walk:** capture inventory and unresolved actions, preserve incident history, cancel delivered wait timers and admit meaningful continuation. **Result:** the old V1 wait/attempt-reset defects have explicit replacement rules. **Break:** preparation/review/follow-up executions still lack a defined normal successful completion report distinct from coding candidates and failure endings (V03); a generic missing-report recovery could restart a successfully finished interpretation. Progress evidence must be validated against purpose, not only the existence of an uploaded object. See M24:44–47; S:338, 346–349, 399, 542–550.

### M25 — Addressed attention and exact replies

**Entry:** commands, ownership and delivery/recovery journal. **Walk:** store addressed questions, deliver exact replies, recheck actual causes, reject generic waivers. **Result:** assigned and unassigned attention can be tested without native notifications. **Break:** M38 later relies on an unspecified existing authority path for restoration. This brief defines answer as addressed input/cause resolution, not a typed restore action; the session has no reason to build that future behavior (V11). See M25:44–47; S:488–505.

### M26 — The Claude Code adapter

**Entry:** semantic ports, launch/report/checkpoint/attention services. **Walk:** inspect current permitted documentation/version/help, implement actual supported mappings and store labeled captures/simulations. **Break:** required reporting, ownership and launch/termination guarantees may first prove infeasible here, after seventeen foundation milestones; help text alone cannot establish them. The brief permits live product proof to wait until M47, so passing conformance fixtures does not settle the required capability floor (V15). This review makes no claim about current Claude flags or capability availability. See M26:44–47, 56–57, 66–67.

### M27 — The Codex adapter

**Entry:** common ports plus the actual repository contracts persisted through M26; no Claude-private behavior is inherited. **Walk:** independently map Codex calls and observations, retain versioned evidence and truthful unsupported results. **Break:** the same required-capability risk remains, with a different native runtime; full live proof is delayed to M48 (V15). Honest `unsupported` is correct for optional remote/lookup/native continuity, but cannot substitute for a demonstrated path to ordinary managed work. The brief does not identify an executable minimal required capability trial here. See M27:38, 44–47, 56–57.

### M28 — Allocation-aware fallback and optional budgets

**Entry:** both actual adapters, shared lifecycle, checkpoint continuation and quota records. **Walk:** classify scoped evidence, enforce the settled default/exhaustion policy, reconcile predecessors and implement only explicit budgets. **Result:** the decision and cause matrix are clear; simulated exhaustion is sufficient for this milestone's policy slice and is correctly labeled. **Inherited break:** fallback during the first preparation session still needs the missing purpose-specific context/result/ending contract (V03). Live evidence remains a separate obligation (V15), not a reason to force account exhaustion. See M28:44–47, 56–57.

### M29 — Managed interpretation and preparation recipes

**Entry:** intake, graph validation, workspaces, both adapters and preparation-purpose launch. **Walk:** inspect an unseen project, launch interpretation where necessary, accept executable preparation/input/service/check proposals. **Break:** the first such session needs no accepted graph yet, but the inherited common prompt assumes one; its six-kind reporting schema has no preparation recipe payload, and `Preparation.recipe` is an opaque ObjectRef with no specified executable plan structure. A cold author must invent the producer/validator/consumer contract that M30 will execute (V03). Discovery of ordinary script semantics is expected work; inventing a cross-session protocol is the missing boundary. See M29:38, 44–47, 66; S:187, 542–559.

### M30 — Tracked setup and readiness invalidation

**Entry:** whatever accepted plan format M29 actually exported, host invocation and reservations. **Walk:** execute tracked setup, bind private/generated inputs, start services, invalidate dependent readiness. **Break:** if M29 only met the written opaque-object contract, this session has no defined action order, success predicate, retry/reconciliation rule, service-stop policy or generated-input dependency encoding to consume (V03). Scripts may have non-repeatable side effects; the operation journal cannot infer a script-specific completion test. Purposeful private input copies also create the retained-secret backup conflict encountered in M43 (V09). See M30:38, 44–47.

### M31 — Baseline checks and automatic coding kickoff

**Entry:** accepted graphs and prepared workspaces, with candidate/acceptance/application producers still future. Valid predecessor-result fixtures are explicitly available from M10-c. **Walk:** run baseline checks, bind immutable recipes, connect intake to coding, compose exact dependency inputs. **Break:** the required `preparing → ready` pass condition contradicts this brief's instruction to retain baseline failures without universal refusal (V01). A ready unit blocked by a temporary guard cannot become ready again (V02). Baseline-result storage/reference identity is undefined (V04). Combining conflicting predecessor selectors is also unspecified. See M31:44–47, 56–57; S:297, 434, 248.

### M32 — Freeze candidates before verification

**Entry:** dispatch, scoped candidate claims, snapshots and definitions. **Walk:** independently capture/diff output, validate provenance and scope, freeze it, retain no-change candidates for verification. **Break:** it inherits the unsupported strong consistency claim from repeated inventories (V05). Pinning a recipe containing only argv does not pin the test runner/configuration transitively executed by those arguments (V06). Rejecting every test-related edit would instead block legitimate changes without a defined reviewed amendment path. See M32:44–47, 56–57; S:246, 436.

### M33 — Independent deterministic verification

**Entry:** frozen candidates, recipes, baseline outputs and workspace provisioning. **Walk:** materialize an independent candidate workspace, execute checks, classify results and retain every attempt. **Break:** candidate workspaces need the prepared private inputs/services/configuration, yet the checklist jumps from candidate materialization to check invocation without requiring readiness for that new workspace. Running in the coding workspace would defeat the independent-workspace contract. The fixed argv still may execute candidate-weakened test infrastructure, and baseline evidence joins are unspecified (V04/V06). See M33:38, 44–46, 56–57; S:186–187, 246–248, 436.

### M34 — Reviewed evidence, waivers and accepted results

**Entry:** deterministic results, attention and managed review-purpose executions. **Walk:** obtain semantic/human evidence, validate specific waivers, create accepted results and close patch-only units. **Break:** there is no exact review-result payload mapping verdicts to candidate/criterion/snapshot, nor a normal successful review ending. The session must add a private evidence schema, alter reporting or parse free prose (V03). A frozen candidate needing a legitimate test-recipe amendment also lacks a defined safe amendment/continuation route through the existing immutable definition lifecycle (V06). See M34:38, 44–47; S:233, 246–248, 542–550.

### M35 — Serialized combined-result integration

**Entry:** accepted isolated results, destination resources and independent verification. **Walk:** serialize the actual destination, compose its current state with the candidate, reverify and leave publication unsupported. **Result:** leaving physical application for M36/M38 is explicitly correct. **Break:** combined verification inherits M33's independent preparation and check-implementation gaps (V06). The resource identity algorithm must treat overlapping nested destinations, not merely equal Destination IDs/strings, as conflicting where paths overlap; neither the brief's acceptance nor the record contract specifies that case. See M35:44–47, 56–57, 66; S:442–452.

### M36 — Safe Git application to the requested destination

**Entry:** verified combined results and expected destination evidence. **Walk:** distinguish ref publication from checkout application, preserve staged/unstaged state, apply deltas and reconcile lost acknowledgements. **Break:** the design has not named a host mechanism proving safe checkout access against outside writers (V07). It also needs per-path/index/metadata recovery before M37 introduces the general application classifier (V10/V14). A session must implement that recovery itself here or leave dirty-checkout publication unsupported; a successful non-checked-out ref update does not satisfy its acceptance. See M36:44–47, 56–57; M37:44–45.

### M37 — Directory application plans and reconciliation

**Entry:** integration and durable objects; synthetic destinations are expressly permitted. **Walk:** persist each action and classify before/after/divergence, including rename and metadata interruptions. **Break:** ApplicationEntry has no before/after mode, kind or link-target fields; its referenced preimage/postimage object encoding is undefined. A mode-only operation can have identical content digests before and after. The author must correct or supplement M10-b/M10-c's promised complete record contract, not infer completion from matching bytes (V10). See M37:44–45, 56; S:236, 248–252.

### M38 — Guarded directory application and restoration

**Entry:** the application plan/classifier and destination ownership. **Walk:** establish applicable exclusivity, publish per-entry effects, reconcile interruptions and honor explicit restoration requests. **Break:** no practical arbitrary-directory exclusivity mechanism is specified (V07); fixture-only exclusivity cannot prove it. Restoration is required, but a new rollback command is explicitly forbidden and no existing exact command accepts a restoration plan/action (V11). Content-only postimage checks would also misclassify metadata changes unless V10 is settled. See M38:27, 44–47, 56–57.

### M39 — Retained conversations, follow-up and adoption

**Entry:** both adapters, retained workspaces/checkpoints and durable control. **Walk:** resolve addressed conversations, preserve terminal units, create new productive follow-up authority, import external sessions only with proof. **Result:** observe-only fallback and refusal to fabricate historical dispatch are specified. **Break:** deciding whether arbitrary follow-up text is productive work needs managed interpretation; successful informational follow-up has no defined non-candidate result/ending contract (V03). The old run must not be reopened merely to receive the result. See M39:44–47; S:193, 338–349, 497.

### M40 — Bounded reconciliation and independent health

**Entry:** operation handlers through conversations/application, with notifications and release maintenance still future. **Walk:** wire due-work passes, health, independent watchdog, process cleanup and sleep observations. **Break:** it claims to consume “all operation handlers” and wire delivery, but native notification/release/backup/delete handlers do not yet exist. Those must remain explicit unsupported/extension points, not be borrowed from future sessions. More seriously, no earlier milestone owns a complete invocation driver for the asynchronous product commands, so cold authors must know which earlier direct fixture calls now need registration here (V14). Later handlers must be tested through this real path, not only called directly (V15). See M40:38, 44–47.

### M41 — Local notifications with addressed actions

**Entry:** attention, watchdog and effect/reconciliation machinery. **Walk:** implement native presentation and ID-specific response routing, retry delivery, investigate optional channels. **Result:** choosing no independent transport when modest supported integration is unavailable is explicitly allowed, not a coverage defect. **Break:** the watchdog must still get useful local diagnosis when the controller's own DB is corrupt/unwritable; writing an Attention to that same broken store and enqueueing a normal notification is insufficient. The out-of-band degraded path is not specified (V16). Live OS presentation/signing remains deliberately unproved until M49. See M41:44–47; S:122–128, 242, 689–695.

### M42 — Immutable releases and relocatable installation

**Entry:** complete local runtime/reconciliation/notification components. **Walk:** package explicitly built artifacts, switch compatible releases, pin references, generate actual-home scheduling paths. **Result:** synthetic schema migrations and isolated installation fixtures can leave V1 intact; production activation is correctly out of scope. **Break:** release/maintenance ownership during a dead or corrupt controller requires a durable coordination mechanism beyond the DB being replaced or repaired (V08/V16). “Atomic current selection plus Controller reconciliation” states the invariant, but its cold-start implementation must define the authority order, including a worker holding an older selection. See M42:44–47, 56–57.

### M43 — Consistent retained-state backups

**Entry:** object/snapshot integrity, releases and maintenance effects. **Walk:** snapshot DB, capture referenced objects/releases/workspaces, exclude secrets, validate reference closure and digests. **Break:** copied secret inputs and exact confidential request/report bytes can already exist inside retained workspaces/objects/database BLOBs. The brief simultaneously requires complete referenced content, unchanged digest closure and zero exported credential values, without a sanitized-copy/rebinding contract (V09). A SecretReference exclusion list alone cannot remove embedded bytes. See M43:44–47, 56–57; S:164, 188–189, 209–210, 561.

### M44 — Restore with old-execution fencing

**Entry:** a valid backup, releases, ownership and adapter lookup. **Walk:** validate, exclude writers, replace state, create a fresh epoch and reconcile old native effects. **Break:** restoring an older DB can erase the records of executions, invocations, deletion fences and accepted commands created *after* that backup. A fresh epoch blocks their reports but does not reconstruct their resource claims or prevent a previously accepted operator command being retried after its identity disappeared. No carry-forward manifest/monotonic authority outside the restored snapshot is specified (V08). See M44:44–47, 56–57; S:241–243, 743–749.

### M45 — Project maintenance and explicit deletion

**Entry:** restore fencing, ownership/drain and object reference machinery. **Walk:** reconcile moves, drain retirement, preview/revalidate deletion and retain tombstones. **Result:** direct deletion tests can prove stale reports remain fenced in the current database. **Break:** a later restore of an older backup can reintroduce the deleted body and discard the newer tombstone; the deletion and restore contracts do not specify how explicit deletion survives that operation (V08). Also, deleting terminal object bodies must preserve inspectable missing/deleted distinctions without violating foreign keys; M10-c's immutable mappings need a defined tombstone/reference policy, not ad hoc row removal. See M45:44–47; S:183, 210, 243, 563.

### M46 — Bounded retained-history queries and integrity isolation

**Entry:** all query/reconciliation/maintenance paths. **Walk:** compare indexed work at 1,000/100,000 retained records, inject persistence/integrity failures, repair demonstrated defects. **Result:** structural query-plan checks are more useful than timing-only pass claims. **Break:** a corrupt/unwritable controller cannot necessarily report or resume its own maintenance through the normal DB command path (V16). The allowed repair scope names Queries.swift and Store.swift; a scale defect in admission/reconciliation/adapter transcript scanning can require the shared split procedure, whose eligibility deadlock is unresolved (V12). See M46:27, 31, 44–47, 56–57.

### M47 — Claude Code unseen-project live acceptance

**Entry:** M46 source/release and actually authorized Claude trial access. **Walk:** create a relocated dirty non-main target, start real work, answer an actual question, observe independent application and continuation, retain a reproducible transcript. **Break:** the exact trial is authored by the session being judged; no fixed task, expected result, workload or required successor chain is supplied. A single successful tiny project can satisfy the explicit acceptance without proving a fresh successor receives the complete preparation/definition state (V15). The new empty test home is queried for capabilities before any required setup sequence is specified (V13). The evidence file is a deliverable, so its absence on entry alone is not a failure. See M47:15, 46–49, 57–59.

### M48 — Codex unseen-project live acceptance

**Entry:** independently sufficient current Codex access and implementation, plus M47 complete by the serial graph. **Walk:** run dirty Git and non-Git projects through question, results and continuation. **Break:** the non-Git trial explicitly passes with retained output plus application conflict. Thus V2 can pass its only named live directory trial without ever demonstrating successful real directory application (V07/V15). No Claude non-Git live trial or Codex-only cold host trial is required. Fresh-home initialization and self-authored trial-oracle problems recur (V13/V15). See M48:15, 40, 46–49, 58–59.

### M49 — Fresh-user macOS installation acceptance

**Entry:** actual fresh-user access, explicit install/signing authority and the current signed release. **Walk:** install, run setup for both profiles, verify scheduled work/watchdog and click addressed notifications. **Result:** a fake HOME cannot replace this prerequisite, correctly stated. **Break:** querying a newly allocated home before its setup again lacks an executable ordering (V13). A stuck/unloaded fixture scheduler is tested, but a corrupt/unwritable state store's independent local diagnostic path is not (V16). Mandatory credentials/grants may require human acts; these are legitimate host boundaries, not target preparation. See M49:15, 40, 46–49, 58–59.

### M50 — V2 recovery and unattended acceptance

**Entry:** every prior implementation and current live evidence. **Walk:** create the acceptance ledger, exercise composed fault boundaries, observe overnight work and label quota simulation accurately. **Break:** an unattended workload ending in “a specific evidenced attention state” passes the explicit trial condition, even if no autonomous fresh-session successor completes. The blanket all-AC requirement does not name a live multi-unit cold-context oracle that excludes that easy outcome (V15). If a defect is found, the required repair child depends on an incomplete M50 unless the split contract is changed (V12). No production cutover is promised here; its absence is intentional. See M50:46–51, 59–61, 70–71.

## 2. COVERAGE

### Every original limitation

No L-number is missing from the decision-cluster ownership table. That is **nominal coverage**, not proof of a usable resolution. The following trace independently connects each finding to normative behavior and actual milestone ownership. “Gap” identifies where that chain loses substance. Implementation ownership does not claim that the implementation exists today.

| Finding in 01 | Resolving decision | Spec contract / acceptance | Implementing milestones; remaining gap |
|---|---|---|---|
| L1 target-side contract | C01 | §1.1, §5.1, §6.6; AC01/10 | M17, M20, M29–M31; preparation handoff V03, readiness V01 |
| L2 Git/main/sibling assumption | C02 | §3.3/3.6, §5.1/5.3; AC06/21–23 | M18–M19, M36–M38; application capability V07, case/layout limits |
| L3 ignored brief pointer | C01 | §3.2 Source/UnitDefinition, §6.4; AC09 | M17, M20, M23; exact context replaces fixed paths |
| L4 unprepared workspace | C02 | §5.1; AC11–13 | M18–M19, M29–M31; V03 and independent verification preparation V06 |
| L5 one Claude protocol | C03 | §1.3, §6.5; AC02/50 | M22–M23, M26–M27; required capability proof delayed, V15 |
| L6 one Mac user's paths | C03/O1 | §1.5, §9.5; AC49 | M09, M22, M42, M49; non-macOS deliberately excluded |
| L7 inherited settings | C04/O2 | §5.1, §6.5; AC13/50 | M22, M26–M27, M29–M30; simulated restrictions lack required broad live matrix, V15 |
| L8 incoherent profile | C03 | §3.3 RuntimeProfile, §5.1; AC13–15 | M22, M26–M28; default model/effort contract V04 |
| L9 path/name identity | C02 | §3.2 Project, §3.6; AC07 | M17, M19, M45; explicit identity reconciliation specified |
| L10 generated shell quoting | C03 | §6.2/6.5; AC14 | M11–M12, M22, M25–M27; data transport specified |
| L11 inadequate containment | C04/O2 | §1.1, §6.4, §11; AC13 | M16, M22, M26–M30; adversarial containment explicitly not promised |
| L12 compulsory unproved remote | C10/O5 | §1.4, §6.2/6.5; AC43 | M17, M26–M27, M41, M49; opt-in/reduced guarantees specified |
| L13 ancestry-only completion | C08 | §4.6, §5.2/5.3; AC16–23 | M32–M38; V04/V06/V07/V10 leave verification/application gaps |
| L14 inconsistent input snapshots | C01 | §3.2, §4.1, §6.4; AC08–09 | M17, M20, M23; snapshot consistency still V05 |
| L15 weak report provenance | C04 | §3.3 ReportGrant, §6.4; AC26–27 | M15–M16, M23; scoped identities specified, trusted-host limitation explicit |
| L16 launch before durable record | C05 | §2.2, §4.7/4.8; AC24–25 | M13, M23–M24; cross-handler proof deferred, V14/V15 |
| L17 move/event split | C05 | §2.2, §4.6, §6.4; AC27 | M10/M10-c, M13–M16; receipt/outbox atomicity specified |
| L18 mutable ending slot | C05 | §3.4, §6.4; AC26–28 | M11, M15–M16; immutable submission/generation identity specified |
| L19 late scheduling advice | C01 | §3.2, §4.6, §6.4; AC08–09/27 | M14, M16, M20, M31; successor authority moved to graph |
| L20 body-dependent deduplication | C05 | §2.2, §6.4; AC26/45 | M11, M16, M45; newer fences can be lost by old restore, V08 |
| L21 arbitrary worktree reuse | C02 | §3.3 Workspace, §3.6; AC12 | M18–M19, M30; identity and preparation checks specified |
| L22 different admission paths | C06 | §2.1/2.3, §4.7; AC30 | M21, M23–M25, M28–M39; full composed-path test late, V14/V15 |
| L23 incomplete process cap | C06 | §3.4 Reservation, §4.4/4.7; AC30–31 | M13, M15, M21–M24, M30, M39–M40; no claim of hard descendant containment |
| L24 missing same-batch peers | C06 | §2.3, §6.4; AC31 | M21, M23, M31; committed peer reservation context specified |
| L25 old wait interrupts recovery | C07 | §4.4/4.7; AC28–29 | M15, M23–M24; productive observation cancels old cycle |
| L26 old ending hides new crash | C07 | §4.4; AC28 | M15, M23–M24; explicit generations specified |
| L27 retry ladder resets | C07/O4 | §4.7, §8; AC29 | M24, M28; persistent incident/circuit history specified |
| L28 repaired cause stays parked | C07 | §4.2/4.3, §6.2 recheck; AC37 | M14, M24–M25, M30–M31; blocked-unit restoration V02 |
| L29 live PID/failed first request | C07 | §4.4/4.8, §8 startup_failed; AC33 | M23, M26–M27, M40; required live refusal coverage not concrete, V15 |
| L30 incomplete wait taxonomy | C07 | §4.4, §8; AC33 | M15, M23, M25–M27; native mapping requires current evidence |
| L31 transient takeover protection | C07 | §4.5; AC34 | M15, M25–M27, M39; mediated/direct limitation explicit |
| L32 manual done does not close lane | C07/C08 | §4.3/4.6, §5.2; AC19/36 | M14–M15, M34; one closure/accounting path specified |
| L33 unresolvable parks | C07 | §3.5 Attention, §6.2/6.3; AC37 | M16, M25; restoration V11 and corrupt-store controls V16 remain |
| L34 global hung-call lock | C09 | §2.2/2.3, §6.3/6.5; AC40 | M10, M12–M13, M22, M40; early source-call boundary V14 |
| L35 stale directory lock | C05 | §2.2, §4.7; AC24–25 | M10, M13; maintenance replacement authority still V08/V16 |
| L36 fresh marker hides partial failure | C09 | §2.3, §3.5, §8; AC41 | M40, M49; corrupt-store independent reporting V16 |
| L37 invalid dependency graph | C01 | §3.2, §5.1; AC08 | M20, M29; structural checks specified; reachable lifecycle still V02 |
| L38 shallow artifact types | C05 | §3, §6.4; AC26–27/39 | M10-b/M10-c, M11, M16; unresolved payload/reference contracts V03/V04/V10 |
| L39 unvalidated configuration | C03 | §3.2 EngineConfiguration, §3.3; AC13/40 | M10, M22; profile model/effort vocabulary V04 |
| L40 coarse quota identity | C06/O4/O8 | §1.3, §3.4, §9.3; AC03–05/32 | M21–M22, M26–M28; scope/freshness/default policy specified |
| L41 whole-history cost/growth | C11/O6 | §6.3, §9.5; AC44–45/48 | M10/M10-c, M12, M40, M43–M46; growth accepted, deletion/restore V08 |
| L42 mixed installation versions | C11 | §3.5 Release, §9.5; AC46/49 | M42, M44, M49; degraded maintenance authority V08/V16 |
| L43 overwritten rejected evidence | C05 | §3.4 Submission, §6.4; AC27/37 | M10, M16; immutable submission storage specified |
| L44 timestamp park identity | C05 | §3.1/3.4/3.5; AC37 | M10-b/M10-c, M13, M16, M25; UUID/revision/sequence specified |
| L45 incomplete status explanation | C09 | §2.3, §6.3; AC39–41/44 | M12, M21, M25, M40, M46; degraded-store path V16 |
| L46 notification intent is not delivery | C10 | §3.5 Notification, §6.5; AC42 | M41, M49; distinct delivery/action states specified |
| L47 global notification click target | C10 | §6.5, §9.4; AC42 | M41, M49; per-notification attention IDs specified |
| L48 model-authored shell delivery | C10 | §6.1/6.2/6.5; AC14 | M11–M12, M22, M25, M39; restoration must not reintroduce prose command routing, V11 |
| L49 finished fork's stale obligations | C07 | §4.4, §6.2 followup; AC36/38 | M15–M16, M39; non-coding successful ending remains V03 |
| L50 retained content secrecy | C04/C11/O6 | §3.1, §6.4, §9.5; AC15/47 | M10, M16, M22, M30, M43; known retained secret/export conflict V09 |
| L51 duplicated workflow semantics | C12 | §2.1, §3/§4, §11; AC36/39 | M10-b/M10-c, M14–M16; finite core is intentional, but missing shared contracts V03/V04/V10 |
| L52 nonportable standing check | C12 | §9.5; AC49 | M09, M42, M49; portable repository-only close-out still V13 |
| L53 conflicting normative instructions | C12/O7 | §1.5, §11 | CLAUDE.md notice, each V2 brief; future typed/spec/prompt consistency V01–V04/V12/V13 |
| L54 fixtures do not prove actual workflow | C12 | §10 and AC50 | M26–M27, M47–M50; insufficient fixed live/cold-chain oracle V15 |

### Every original capability gap

| Gap in 01 | Decision | Spec contract / acceptance | Implementation or disposition |
|---|---|---|---|
| G1 adopt an existing session | C07 | §6.2 adopt, §6.5; AC38 | M39; observe-only is an explicit supported limitation |
| G2 plain task/source intake | C01 | §1.1, §5.1, §6.2; AC01/10 | M17, M20, M29–M31; V03. Issue-tracker integration deliberately unnecessary; accessible text/URL suffices |
| G3 onboarding/provisioning | C02 | §5.1; AC06/11–13 | M18–M19, M29–M31; V01/V03/V05/V06 and layout/filesystem limits |
| G4 cross-project dependencies | Explicit V3 deferral | §7 item 46, §11 | No independent-project graph implementation promised; local accessible dependency preparation M29–M30 |
| G5 host/runtime conversation transfer | Explicit V3 deferral; O8 permits checkpoint fallback | §1.3, §9.3, §11 | M24, M28, M39, M43–M44 preserve accessible context; no live-state translation promised |
| G6 pause/drain/cancel/deregister | C07 | §4.5, §6.2; AC35 | M15, M45; blocked readiness V02 and maintenance recovery V08/V16 |
| G7 pre-boundary checkpoints | C07 | §3.3, §4.4/4.7; AC29 | M24, M26–M27; partial capture honestly allowed; non-coding completion V03 |
| G8 budgets/resources | C06/O4 | §3.4, §4.7, §6.2; AC30–32 | M13, M21, M28, M30, M40; budgets opt-in, no hard unseen-descendant resource guarantee |
| G9 independent checks/merge coordination | C08 | §5.2/5.3; AC16–23 | M31–M38; V01/V04/V06/V07/V10/V11 |
| G10 backup/restore/migration | C11 | §9.5; AC46–48 | M42–M45; V08/V09/V16 |
| G11 machine controls/preview | C09 | §6.1–6.3; AC39/44 | M12, M21, M25; local CLI intentionally suffices, no server/subscription required; V11/V16 |
| G12 independent controller monitor | C09/O5 | §2.3, §3.5; AC41/43 | M40–M41, M49; corrupt-store notification/control path V16; powered-off host guarantee deliberately absent |

### What drops out despite complete ID coverage

1. **Baseline-aware useful work** appears in C08 and S §5.2 but is forbidden by the literal ready transition: L4/L13/G3/G9 lose their operational resolution (V01).
2. **Recovery after an actual prerequisite clears** has no complete unit path: L28/G6 remain vulnerable even with correct recheck detection (V02).
3. **Managed interpretation/review as real sessions** is repeatedly named but lacks a complete result/ending/preparation-plan contract across the strict reporting boundary: L1/L4/L38/L49/G2/G3/G9 (V03).
4. **Baseline evidence, exact check implementation and full filesystem metadata** are promised without complete record/executor semantics: L13/L38/G9 (V04/V06/V10).
5. **Automatic local directory application** becomes “verified output plus conflict” at its live acceptance boundary. That is a truthful supported fallback, but it does not prove O3's ordinary successful directory path: L2/L13/G9 (V07/V15).
6. **Preservation across restore** is not tested against post-backup actors/IDs/deletions; **secret-free complete backups** are not reconciled with deliberate private inputs and exact retained bytes: L20/L41/L50/G10 (V08/V09).
7. **Repository-only autonomous development handoff** still assumes external skills and contradictory split/path procedures: L52/L53/L54 (V12/V13).
8. **A real fresh-session successor chain** is not a named live acceptance oracle. A same-conversation continuation, a tiny one-unit target and an overnight attention state can satisfy the listed trials without that proof: L54 (V15).

The original UNKNOWNS are not silently counted as resolved findings. O1/O2/O6/O7/O8 now settle scope, trust, retention, authority and runtime preference. The actual installed V1 state and the user's prior failed Reclaim attempt remain outside this validation. Current runtime/settings/quota/OS behavior still requires the planned captures; privacy/rights are not proved by an architecture statement. No current provider capability or licensing violation is asserted here.

## 3. CONTRADICTIONS AND MISSING CONTRACTS

### V01 — P1: fixing a failing baseline requires it to pass first

S:297 permits `preparing → ready` only when “Required preparation and baseline checks pass.” S:434 and C08 instead require prior failures to remain distinguishable without universally refusing work; M31:44–47 explicitly implements that permissive baseline behavior. Consider a requested bug fix whose existing regression test fails on the selected baseline and is a required check in the accepted recipe. The literal transition never admits coding. Waiting/rechecking repeats the unchanged failing test; asking for a waiver adds an unnecessary user decision and changes verification authority. The transition guard and its owning M14/M31 acceptance must agree about successful **execution/recording** of baseline checks versus a successful baseline **result**.

### V02 — P1: a prepared blocked unit has no legal recovery edge

S:295 can move a ready unit to `blocked` for graph/intent guards. Once the gate or pause clears, S:296 only permits `blocked → preparing` when preparation is needed/invalidated; S:299 only starts from `ready`; S:301 handles `waiting/attention` with an existing attempt. There is no edge returning an already-prepared blocked unit to ready. S:262 forbids unlisted transitions, and M14:45/56 requires rejecting them. M21's restored positive admission verdict and M15's continue command cannot repair the absent state edge. A recheck can correctly report the cause repaired while the unit still cannot run—the V1 symptom L28 in a new state model.

### V03 — P2: non-coding managed work has no complete wire/settlement contract

Execution explicitly permits preparation/review/follow-up purposes and nullable unit/attempt (S:195). However, the common kickoff requires fixed definition/recipe context (S:559); the report union has only checkpoint/question/candidate/stopped/progress/graph_proposal (S:223, 542–550); the normal terminal path refers to candidate/stopped endings (S:338). A first interpretation creates the initial definition; a review must return criterion-bound judgments; a successful informational follow-up should not manufacture a coding candidate or stopped failure. Neither a successful purpose-specific result nor its closure rule is defined.

Separately, `Preparation.recipe` is an ObjectRef (S:187), but no exact preparation action/service/input dependency schema is provided. M29:46 must produce executable plans that M30:38/44 executes. A private JSON object carried as evidence is a possible engineering approach, but its schema, validation authority, result decoder and successful settlement have to be explicitly owned and persisted. They are not supplied by “all six report payloads” or “complete typed model.” This is a missing handoff contract, not a demand for a framework or a new target file.

### V04 — P2: the complete model cannot identify its baseline results

`CheckResult` is an embedded value with no `id`; it carries `baselineResultRef:ID?` (S:248). The only typed container of check results is Verification, which requires `candidateId` (S:233). M31 produces baseline checks before any candidate exists; M33 consumes and joins those outputs. No standalone baseline-result identity, container or target meaning for that ID is defined. The operation/output objects can retain bytes, but that is not an exact referential contract. M10-b/M10-c cannot prove the advertised complete relationships without choosing an undocumented interpretation.

The same profile vocabulary has a smaller omission: S:595 assigns model/effort defaults to the validated RuntimeProfile, while S:190 defines no such fields or typed settings keys. Both adapters can therefore claim compliance while selecting differently from unversioned native defaults. A named immutable settings schema could settle this; none is presently specified.

### V05 — P1: repeated inventories do not prove the promised capture consistency

S:254 and M18:46 permit repeated inventory comparison; M18:57 and AC11 require no falsely ready mixed baseline under concurrent mutation. Equal sequential inventories are not proof that the copied bytes came from any single source state. For example, let two files cycle through `(old,old) → (new,old) → (new,new) → (new,old) → (old,old)`. Schedule each inventory scan and the copy to read the first file at the first state and the second at the third. Every collected manifest can agree on `(old,new)`, including the copied bytes, although that source state never existed. Repeating a finite number of scans does not exclude this ABA schedule.

The spec also allows a supported consistent snapshot primitive, which can avoid this particular attack if its actual guarantee is established. The defect is allowing the weaker method to certify the stronger invariant. M18, M32, M43 and their consumers need an exact distinction between proved consistency, best-effort observations and unavailable consistency; the report does not claim that every snapshot implementation must fail.

### V06 — P1: a fixed command is not a fixed verification implementation

CheckSpec pins argv, cwd, environment reference and criterion links (S:246); it does not pin the content/closure of test scripts/configuration invoked by those arguments. A recipe invoking a project test script can stay byte-identical while a candidate edits that script or its config to skip the relevant tests. S:436 and M33:46/56 forbid that weakening, but no algorithm/contract specifies which prior verification inputs are materialized, how candidate tests are separated from trusted acceptance inputs, or how a legitimate test change is reviewed without silently changing an immutable active definition.

There is another practical gap: M33:44 creates a new verification workspace and immediately invokes checks. M30 prepares a particular workspace; its input/service bindings are workspace-specific. The verification and combined-integration workspaces need their own readiness/provisioning using the fixed candidate and accepted preparation plan. Otherwise ignored local configuration, generated inputs or services work during coding and disappear during independent checks. Returning `unavailable` honestly still strands an otherwise preparable project. Merely calling a separate workspace “independent verification” does not establish either condition.

### V07 — P1 feasibility gap: safe local application has no established general host path

C08/O3 select automatic local application, including non-Git projects. S:444–446 correctly refuses unsafe checkout or directory updates and explicitly says an advisory lock plus hashes is insufficient against an uncooperative writer. M36:45 and M38:44 are told to implement applicable coordination/exclusivity, but no selected host primitive, supported filesystem envelope or evidence protocol is established. Owning a Baton Resource record does not exclude an editor, sync process or other native writer.

This is not a request to promise impossible atomicity, nor a claim that the spec hides its conflict fallback. The fallback is explicit and correct. The unresolved product feasibility is whether ordinary user directories have any demonstrated successful automatic path. M48:48/59 allows the live non-Git test to pass entirely via conflict, so every directory application could be unavailable while that milestone still passes. A successful isolated fixture is insufficient evidence for the universal application claim.

### V08 — P1: restoring an old snapshot can erase the very fences recovery needs

C05/C11 require durable replay identities and reconciliation of live effects; S:243 and AC26/45 require permanent retired namespaces. M44:44–47 replaces state from a backup and creates a new epoch, but does not specify preservation of the newer current controller's execution/operation/resource/tombstone/command inventory.

Concrete interleaving: take backup B; accept command C and launch execution E afterward; explicitly delete an older body afterward; restore B while E remains live. B contains neither C/E nor the newer deletion fence. A new epoch rejects E's reports, but it does not reserve E's still-occupied destination or remember that retrying C is a duplicate. Native lookup of only identities restored from B cannot discover the omitted record. The design must define how current/post-backup effects and permanent identity retirements survive rollback, and what happens when the current store is too damaged to enumerate them. New epoch alone is not that mechanism.

### V09 — P1: complete exact backups conflict with secret exclusion

C04/C11 and AC15/47 forbid credential values in ordinary recovery exports. S:189/202 and M30 authorize private copies of needed local secret inputs; exact request/report bytes are also retained, including Message.envelopeBytes inside the DB (S:210). M43:45–47 requires all referenced retained objects, consistent workspaces, reference closure and digest validation, while its acceptance requires secret sentinels absent from content exports.

A workspace with an explicitly copied `.env` credential defeats a naive complete snapshot; an exact user report containing that credential can also reside inside the DB backup. Excluding SecretReference locators does not remove those other copies. Silently redacting them changes the referenced digests and restored input state. The missing contract is the sanitized backup representation, exclusions and post-restore rebinding/readiness semantics. Arbitrary prose cannot be guaranteed secret-free, a limit the decisions already acknowledge; the backup acceptance must not promise otherwise while requiring exact copies.

### V10 — P2: content hashes cannot reconstruct index, rename and metadata state

The manifest has mode/kind/link text (S:252), but no explicit Git index tree/stages versus working-tree snapshot representation. `dirtyManifest` is another ObjectRef without a separate format contract. ApplicationEntry has content/object refs and expected digests but no specified before/after typed metadata object (S:236). M18:56 must reproduce staged/unstaged state; M36:56 must preserve it; M37:44–45 and M38:56 must classify every metadata/rename interruption.

Two files with the same bytes but different executable modes have the same byte digest. A mode-only operation therefore cannot be classified by those digests. Renames also need expected absence/kind/metadata for both names, including a destination that already existed. These facts could be stored in typed pre/postimage objects, but their schema and comparison semantics are absent. A complete fixture graph of opaque ObjectRefs does not settle them.

### V11 — P2: guarded restoration has no defined public operation

S:450 and M38:47 require explicit user-directed, postimage-guarded restoration. M38:27 prohibits a new public rollback command and says to use existing authority/evidence paths. The exact command table (S:484–507) defines `restore` only as restoring Baton state from a backup; `answer` carries text to attention; `resolve_operation` records whether an effect occurred. None selects application entries/preimages for a new restore effect. M25 does not define a restoration action through answer. A cold M38 author must invent an undocumented text command grammar, expand an existing command or violate its non-goal. Text routing by a model would also undermine C10's deterministic addressed command boundary.

### V12 — P1: the escape hatch for oversized milestones cannot advance

The common split instruction says to keep unmet acceptance incomplete, create a dependent remainder, and use the existing split rule. `docs/MILESTONES.md`'s Split rule explicitly records `stopped/unfinished` for the parent and makes the remainder depend on it. Neither rule partitions the parent's acceptance/definition of done into a independently completable prefix. The child waits for a parent that cannot be completed until the child's work exists. M50 hits the same trap when acceptance discovers a required repair.

M10:67 is a separate definite collision: it says create `M10-b.md`, already present in the graph. The scoped suffix recommendations in M10-b/M10-c avoid that particular collision, but do not repair the general completion/dependency problem. This is especially material because the plan explicitly expects size pressure in its foundations, adapters and checkout integration.

### V13 — P2: reproducibility relies on conventions outside the cold-start contract

All prompts require external `/review-2` and `/address` procedures without repository definitions or an explicit fallback. Equivalent source locations are permitted, then hardcoded as successor entry tests. Live milestones M47–M50 allocate a fresh private test home and direct the session to query its capabilities/attention as preconditions, while S §6.3 says queries cannot probe or mutate; the setup that would populate those records is not ordered before those checks. These are avoidable cold-start guesses, distinct from legitimate requirements for build permission, authentication or fresh-user access. The repository must say how a session establishes those facts, not depend on the previous author's local environment.

M12:56 also names “changed-ID payload conflicts” in its acceptance vector. S:474 defines conflict for a changed logical request under the same command ID; a distinct command ID can legitimately carry a new request. A cold fixture author must resolve this wording against the spec rather than implementing the literal wrong conflict case.

### V14 — P2: physical effect boundaries arrive after their first consumers

M17 already requires bounded tracked Git/URL/source reads; M18/M19 perform real capture/worktree creation. The general bounded HostAdapter invocation implementation is introduced by M22, after M13's explicitly fake-only workers. Earlier milestones can implement narrow real primitives themselves, but no ownership/reuse contract tells the later host-adapter author which already-existing call paths to absorb and verify. This is a dependency-contract gap, not proof that compilation before M22 is impossible.

Similarly, M36 needs crash-safe dirty checkout/file/index handling before M37's general per-entry classifier. M40 first wires the overall reconciler and says it consumes all handlers while later notification/maintenance handlers are absent. The plan allows partial product slices, so unsupported future handlers are legitimate; the missing obligation is to enumerate and test every handler's connection to the final journal/admission/reconciliation path. Passing direct-call fixtures before/after M40 does not prove that connection.

### V15 — P1 proof gap: the final evidence can miss Baton's defining handoff

C12/L54 demand evidence beyond fixtures agreeing with themselves. M26/M27 can establish mappings from version/help plus captured/simulated conformance without a small live required-capability probe. The first complete live discovery occurs at M47/M48 after almost the entire product has been built. Their exact task/transcript/oracle is written during the trial. Neither requires two independently cold coding sessions, a verified predecessor result, and a fresh successor that consumes only its persisted definition/preparation/checkpoint inputs.

M48 permits directory conflict as its successful non-Git outcome; M50:60 permits an overnight attention outcome. Those may be correct results for individual scenarios, but neither proves autonomous handoff to completed dependent work. M50's catch-all ledger cannot make this a concrete oracle retroactively. Nor do the named live trials require both runtimes across the non-Git, restricted-settings, missing-local-input and unusual-layout cases. Do not replace the quota policy's truthful simulation allowance with forced exhaustion; the missing evidence is ordinary actual cold-chain operation and a minimum runtime capability floor.

### V16 — P2: the independent health/recovery path still depends on the failed store

S §3.5 stores WatchdogObservation, Attention, Notification and Maintenance in the authoritative DB. S §6.1 requires commands to persist before effects. M40/M41 implement watchdog-to-attention-to-notification through those records; M44 restores state through maintenance; M46 injects database corruption and persistence loss. When that same DB cannot open or commit, the normal path cannot persist either a diagnostic notification or the restore command needed to repair it.

A local stderr error is possible and should not be confused with autonomous watchdog delivery. The plan needs a defined degraded diagnostic/maintenance authority outside the broken store, with explicit ordering and reconciliation after recovery. The present unloaded-scheduler tests do not exercise that condition. This does not require a hosted service or off-host guarantee.

## 4. THE UNIVERSAL CLAIM

These are three concrete, different target projects that the current design does not carry through its ordinary autonomous outcome. They use the intended macOS host and supported runtime pair; none relies on demanding Linux support or unavailable private model-state transfer.

### Target A: an undocumented Rust monorepo with the bug already captured by a failing test

**Project:** `/Projects/ledger`, branch `develop`, a workspace with `crates/parser` and `crates/app`. The toolchain and dependencies are already accessible. The user selects the repository, authorizes the necessary test execution, and asks: “Fix parser's empty-input panic; keep the existing regression test and make it pass.” There is an unrelated staged documentation edit. No Baton files exist.

**Execution:** M17 accepts the request and M18/M19 preserve the actual dirty baseline. M29 reasonably selects the existing regression test as a required deterministic acceptance check. M30 can prepare the environment. M31 runs that test on the baseline and records its failure. M14's literal S:297 readiness guard now prevents the unit becoming ready, so M23 never launches the coding work that could repair it. Rechecks reproduce the same failure. No credential, scope answer or host grant is missing. A waiver or human repair is an artificial preparation requirement caused by V01.

If the author bypasses that guard to make the demonstration pass, the implementation contradicts the state table. Selecting only unrelated passing baseline checks evades the task's existing acceptance evidence. This is a direct design contradiction, not an acknowledged environmental impossibility.

### Target B: a non-Git Julia analysis directory with an ordinary outside writer

**Project:** `/Projects/spectra`, containing `analysis.jl`, `parameters.toml` and a generated report template. Julia and local data are available. A native editor keeps autosaving the template; it does not participate in Baton's locks. The user requests a coordinated local update to the analysis and parameters while preserving other edits. There is no target service or Baton configuration.

**Execution:** discovery, preparation and isolated coding can succeed. Baton can freeze and verify the isolated result. At M38 application, its own destination reservation does not exclude the editor. S:446 correctly prohibits certifying exclusive application from an advisory lock and hashes. No specified supported mechanism establishes the stronger condition, so the result remains accepted in isolation and application enters conflict. Applied-result successors and requested run completion stay blocked. Closing the editor/rearranging the workflow becomes manual intervention; the controller cannot prove that an arbitrary future writer is excluded merely because the current process list is quiet.

**What this breaks:** the broad “no manual preparation” reading for automatic local directory application. It does **not** invalidate the spec's honest conflict fallback: the case is explicitly within that fallback, and M48 can pass with precisely this result. That is why acceptance must distinguish demonstrated universal intake from a proven ordinary application path, rather than treating the fallback as proof of the latter.

### Target C: a case-sensitive source volume and a case-insensitive Baton workspace volume

**Project:** `/Volumes/Research/lexer`, an existing valid project on a case-sensitive volume, with distinct `fixtures/Token.txt` and `fixtures/token.txt` required by its test corpus. The person's default Baton home is on a case-insensitive filesystem. Both files and the toolchain are readable, and there is no missing authority or dependency. The user requests a lexer fix using both fixtures.

**Execution:** flat opaque object storage can preserve both contents and their original path identities. Materializing the required workspace under the mandated `H/workspaces/<id>` cannot represent the two distinct names on that filesystem. M18/M19 must report the exact collision and refuse a falsely faithful workspace. They have no specified automatic compatible-volume/workspace allocation path; clone versus copy versus worktree does not change the destination filesystem's name semantics. Changing global `--home` is a coherent installation/profile move, not an already-defined per-project workspace adaptation.

**What this breaks:** the ability to run an otherwise accessible unseen project without user storage reconfiguration. Reporting the collision is correct preservation behavior, but no milestone owns an automatic recovery despite a compatible source volume already being accessible. The accepted host-filesystem envelope must be explicit or the provisioning contract must carry that choice. Silently renaming one fixture would violate S:254 and the target's semantics.

### Attacks that the written policy already withstands

Missing quota telemetry does not permit fallback or a fabricated hold; explicit runtime-only policy overrides O8. Same-ID reordered JSON is handled by an exact canonicalization contract. Same-basename projects are explicitly independent. A missing `main` branch alone does not defeat the snapshot/workspace policy. Human takeover plus a disappearing row remains sticky. An unacknowledged launch is explicitly uncertain, not a license to duplicate it. A malicious same-user process is outside the accepted containment claim. These are not reported as new defects. The failures above concern gaps that remain after granting those safeguards.

## 5. DEPENDENCY ORDER AND WORKING REPOSITORY

The authoritative table contains exactly **44 unique V2 milestones** in the declared order, each depending on the immediately preceding V2 row except M09. All 44 referenced brief files exist. There is no graph cycle, missing milestone or accidental M08/Reclaim prerequisite. M10-b before M10-c before M11 is a sensible distinction between types, stored fixture graphs and wire parsing; the fixture-graph approach resolves many superficial forward references.

The stronger claim—each milestone can complete its own contract and leave a coherent passing repository—is not established:

| Boundary | Assessment |
|---|---|
| M09 | Can leave V1 plus an isolated help/version executable working, subject to authorized current-source verification. Existing installation tests must actually be separated, as the brief requires. |
| M10 / all size-driven splits | **Cannot follow the prescribed split literally:** ID collision at M10 and incomplete-parent dependency deadlock throughout (V12). |
| M10-b / M10-c | **Cannot prove the advertised complete semantic/reference contract** without settling the missing baseline/result/preimage shapes (V03/V04/V10). |
| M14 → M31 | **Contradictory acceptance:** strict table implementation makes normal broken-baseline work and resumed prepared work impossible (V01/V02). M31 must change its predecessor's semantics or violate its own requirements. |
| M17–M19 → M22 | **Undeclared physical-interface dependency:** bounded real source/Git/capture work precedes the shared host-call owner (V14). Narrow earlier implementations can be coherent only if explicitly carried forward. |
| M23/M16 → M29/M30/M34/M39 | **Incomplete cross-session contract:** valid coding fixtures do not supply graphless preparation, executable preparation plans, semantic-review or informational-follow-up completion (V03). |
| M31 → M33 → M35 | **Incomplete evidence/environment handoff:** baseline result identity, fixed verification implementation and preparation of each independent workspace remain unspecified (V04/V06). |
| M36 → M37/M38 | **Recovery primitive ordered after a consumer:** M36 must already recover checked-out files/index safely; a ref-only implementation cannot satisfy its dirty-checkout acceptance (V10/V14). General directory application also awaits feasibility evidence (V07). |
| M38 | **Required behavior has no command:** guarded restoration cannot be reached through the specified exact public surface (V11). |
| M40 → M41–M45 | A bounded reconciler with explicit unsupported future handlers is a valid increment. Its final handler registration/admission/effect coverage must be demonstrated, not assumed from direct-call tests (V14/V15). |
| M43 | **Conflicting acceptance obligations** for exact complete referenced data versus secret-free export unless a sanitized backup contract is defined (V09). |
| M44/M45 | **Insufficient rollback boundary:** old restore can lose new actors/fences/deletion history (V08). |
| M46 | Can test indexed query scale, but normal control-store failure leaves independent diagnosis/repair undefined (V16). |
| M47–M50 | External access requirements are explicit and legitimate. **Product proof remains insufficiently specified**, and a required repair cannot use the current split rule without deadlocking (V12/V15). |

M11–M13, M15–M16, M20–M28 and the other incremental slices are not rejected merely because the whole product is unfinished at their exit. The index expressly allows separately runnable fixture milestones alongside V1. Nor does this review claim a future compile failure from code that does not exist. The failures named above are contradictory obligations, missing semantic boundaries and unproved effects—not measurements of future binaries.

No fresh-session simulation should assume production V2 installation or running all live trials before their specified owners. Conversely, a simulator must not use future handler code to make an earlier acceptance test pass. The lack of a production activation milestone is intentional and does not break the stated design/implementation scope.

## 6. VERDICT

**Not ready to execute.** Required changes, ordered by severity and earliest affected boundary:

1. **Make the lifecycle executable for ordinary work:** reconcile baseline failures with readiness and supply the legal return path for prepared blocked units (V01/V02; before M14's transition tests).
2. **Resolve preservation guarantees that cannot presently be implemented as stated:** define provable snapshot consistency, post-backup effect/fence preservation, and a secret-aware consistent backup representation (V05/V08/V09; before their foundations become permanent).
3. **Make the independent acceptance contract concrete:** baseline-check identities, fixed verification implementation, preparation of verification/integration workspaces and reviewed recipe amendment semantics (V04/V06).
4. **Establish a supported successful local application path and its exact recovery evidence:** checkout/directory coordination, index/metadata/rename preimages and a typed route for explicit guarded restoration (V07/V10/V11). Do not count permanent directory conflict as proof of successful automatic directory application.
5. **Specify the non-coding session handoffs:** graphless preparation kickoff, executable preparation-plan payloads, criterion-bound review results and successful preparation/review/informational-follow-up settlement (V03). Make producer and consumer ownership explicit.
6. **Repair the milestone chain's own cold-start mechanics:** partition acceptance when splitting, allocate unused IDs, make equivalent implementation paths valid entry evidence, and supply repository-contained review/address procedures or a complete fallback (V12/V13).
7. **Assign real effect and degraded-maintenance boundaries before their consumers:** bounded source/Git reads, shared application recovery, registration with the reconciler, and diagnosis/restore when the main store cannot persist (V14/V16).
8. **Replace permissive proof shortcuts with fixed observed scenarios:** establish each runtime's minimum live capability floor early; require a real multi-unit fresh-session chain using persisted preparation/results; add successful directory application and hostile-but-supported project-layout/settings/input trials; initialize each trial home before read-only capability checks (V13/V15 and section 4).

These are findings and prerequisite contract changes only. This document does not amend the decisions/specification, fix briefs, authorize implementation, clear gates or certify any live V2 behavior.
