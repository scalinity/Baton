# Baton V2 design decisions

Decision basis: [01-findings.md](01-findings.md), read in full, against repository revision `f230a8037e4fd2aa341dac0d88dab1c671a28c99`, followed by the user's rulings on 2026-09-14. These are architectural decisions and their costs, not the V2 specification or an implementation schedule. They do not claim that the installed relay implements them. The rulings are recorded below and incorporated into the affected clusters; OPEN DECISIONS lists only matters still requiring user input.

The governing constraint is **an unfamiliar project, with no manual preparation of that project**. The ordinary input is a project location and the work the person wants done, or an existing source that identifies that work. Baton discovers, translates, prepares, and records what it needs. It must not require a migration commit, Baton documents, registration JSON, a permission file, a preinstalled target hook, a handwritten initial handover, or a target-side service. Installing/authenticating Baton and granting host access are host prerequisites, not project conventions; Baton must surface them through its own setup and capability checks.

This does not make missing information available. A request for an inaccessible credential, an ambiguous intended behavior, or permission to affect an external system must identify the specific missing fact or authority. “Prepare your project and try again” is not a recovery action. The records below explain the genuinely irreducible cases and what Baton can do without them.

The selected product posture is **maximum useful autonomy on the person's Mac**: Claude Code and Codex, trusted host execution for selected projects, automatic local application of verified changes, continued work when quota telemetry is unavailable, and retained history until explicit deletion. Mac controls are primary; native phone access is supported where available, with a simple independent notification channel optional. Missing optional telemetry, sandbox support, or remote connectivity must not become new prerequisites for local work. Work identity, verification, preservation of unrelated changes, and explicit user instructions still govern what Baton does.

## Decision clusters and coverage

`L` refers to the ranked LIMITATIONS, `G` to the separately numbered GAPS in 01. Both inventories are accounted for so their overlapping numbers cannot hide an omission. Each item has exactly one owning cluster or V3 deferral. Cross-references between decisions describe dependencies, not duplicate ownership. The architecture map, milestone-format examples, and UNKNOWNS in 01 are evidence and context, not additional numbered findings.

| Cluster | Architectural choice | Limitations owned | Gaps owned |
|---|---|---|---|
| C01 — Work definition without a project contract | Baton-owned, versioned work graph and context | L1, L3, L14, L19, L37 | G2 |
| C02 — Project identity and prepared workspaces | Automatic discovery and isolated workspace snapshots | L2, L4, L9, L21 | G3 |
| C03 — Runtime and host compatibility | Capability-based adapters and one explicit execution profile | L5, L6, L8, L10, L39 | — |
| C04 — Authority and confidential inputs | Trusted host execution and scoped reporting interfaces | L7, L11, L15, L50 | — |
| C05 — Durable commands and messages | Transactional run store, inbox/outbox, and reconciliation | L16, L17, L18, L20, L35, L38, L43, L44 | — |
| C06 — Admission and resource ownership | One admission controller with durable reservations | L22, L23, L24, L40 | G8 |
| C07 — Recovery and human ownership | Explicit lifecycle state machine with bounded recovery | L25, L26, L27, L28, L29, L30, L31, L32, L33, L49 | G1, G6, G7 |
| C08 — Evidence before integration | Independently checked candidates and a serialized integration queue | L13 | G9 |
| C09 — Reconciliation and explanation | Bounded operations and queryable admission/health results | L34, L36, L45 | G11, G12 |
| C10 — Operator communication | Addressed, data-only commands and separate notification delivery | L12, L46, L47, L48 | — |
| C11 — Maintenance of code and state | Versioned releases, indexed history, retention until explicit deletion | L41, L42 | G10 |
| C12 — Protocol authority and proof | One semantic core and layered conformance evidence | L51, L52, L53, L54 | — |

### Deferred to V3

- **G4 — Dependencies between independently managed projects.** V2 prepares the dependencies needed by the selected project, including local dependency source when accessible, but does not coordinate a distributed plan across several project histories. Cross-project completion barriers add failure propagation, authority, and cycle semantics beyond unfamiliar-project intake. An externally blocked dependency stays explicitly blocked; Baton can provision or build an existing dependency within the run, but cannot quietly start changing another project. No target contract or manual migration is required by this deferral.
- **G5 — Transfer of a live run/conversation between hosts or runtimes.** V2 retains portable work evidence and checkpoints, but promises runtime-native continuation only where its adapter can prove it. Translating private conversation state, pending tool calls, credentials, and host resources is a separate capability. A fresh session can continue from accessible work and a checkpoint without pretending to preserve the original conversation. There is no claim that exact transfer is impossible in principle; it is deferred because a truthful implementation needs explicit support from both ends.

No ranked limitation is deferred wholesale. O1 selects macOS with Claude Code and Codex; other operating systems are outside V2 scope. Each supported runtime must work with unfamiliar projects without target preparation. Supporting both does not require translating live conversations between them, which remains G5's separate deferral. L11's lack of adversarial containment and L41's continuing retained-data growth are explicit accepted tradeoffs under O2/O6; their identity, control, query-cost, and maintenance problems are still addressed.

## C01 — Work definition without a project contract

**Findings:** L1, L3, L14, L19, L37; G2.

**CONTEXT.** V1 requires project-authored tables, briefs, slot text, and a seed artifact before it can start; a valid brief pointer can still dispatch a different file. Its scheduling authority is split between a mutable plan, committed prompts, and the consumption order of predecessor advice, while syntactically accepted plans can contain impossible dependencies.

Source re-read: `CONTRACT.md:9–57`; `lib/plan.sh:26–69,141–197`; `lib/dispatch.sh:96–123,254–264`; `lib/candidates.sh:33–75`; M08 in full as reproduced in 01. The important tradeoff is authority, not a more permissive Markdown parser.

**OPTIONS.**

- **A — One managed unit per plain request, no graph (cheapest).** Baton stores the request and a continuation note externally; work runs serially until accepted. This is a credible small relay for tasks whose ordering remains with the person.
- **B — Import into a Baton-owned work graph.** Deterministic discovery reads existing sources; a bounded preparation session interprets prose when needed. Baton validates and versions the resulting work definition and constructs kickoff context from that same version.
- **C — Automatically generate a project-local Baton contract.** Baton writes the plan, briefs, and instructions itself, then uses a stricter version of V1. This provides familiar, Git-reviewable planning files without asking the user to author them.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest: one request, checkpoint, and acceptance record | Automatic dependency scheduling and coordinated multi-session plans | Large requests repeatedly rediscover scope; the person becomes the scheduler |
| B | An intake boundary, graph validation, revision control, and interpretation evidence | Treating arbitrary document edits or old handovers as immediate scheduling authority | Discovery can misunderstand scope or import stale source; revisions can conflict |
| C | Contract generation plus maintaining it alongside existing project documents | Keeping the target free of Baton-specific files and workflow changes | Generated instructions conflict with project rules; two planning systems drift |

**DECISION.** Choose B, using the established **anti-corruption layer** pattern: translate external conventions at intake, then operate on one internal representation. A plain request can produce one unit with no dependencies; a larger graph is justified only by the requested work. Each imported fact retains its source and revision, unresolved ambiguity stays visible, and graph acceptance checks references, cycles, uniqueness, and gate authority. Model interpretation runs as a bounded session under the same controls as coding; ADR 0001's deterministic relay remains intact.

This beats A because a build can progress across sessions without handing dependency bookkeeping back to the person. It beats C because automatic onboarding need not rewrite an unfamiliar project's conventions. Handovers report their own work and may propose graph changes; they never republish authoritative advice for every successor. A graph change is accepted against its expected revision, so late advice cannot roll scheduling backward. The exact brief/context selected at intake is the one captured for dispatch; file names and heading anatomy are not protocol identifiers.

**CONSEQUENCES.** Registration, seed artifacts, fixed brief readers, prompt refreshes on main, and disposition intersection are replaced by external work records and revisioned proposals. Project documents remain inputs; changes trigger reconsideration of affected work rather than silently replacing a running session's contract. Work already authorized and unambiguous needs no extra confirmation. Scope expansion or conflicting intentions needs a ruling through Baton, not a target edit.

The new failure mode is an internally valid but semantically wrong imported plan. Source attribution and a visible proposed scope make that diagnosable; structural validation alone cannot solve it. If two different intended behaviors fit the same repository and request, no repository inspection can distinguish them: the minimum missing input is the person's answer to that behavioral question, not a prepared plan file.

## C02 — Project identity and prepared workspaces

**Findings:** L2, L4, L9, L21; G3.

**CONTEXT.** V1 confuses project identity with a basename/path and workspace readiness with a successful Git command. It assumes main, a sibling directory, and a milestone-derived branch, and accepts an existing Git directory without proving that it belongs to the intended project or work.

Source re-read: `lib/dispatch.sh:35–59,235–266`; `install.sh:44–52`; `lib/tick.sh:120–141`; `CONTRACT.md:28–40`. The deliberate suppression of checkout hooks also means a fresh worktree may omit preparation the project normally gets.

**OPTIONS.**

- **A — Work in the selected directory, one writer at a time (cheapest).** Preserve its existing environment and record a before/after inventory; acquire exclusive Baton ownership while editing.
- **B — Baton-managed isolated snapshots with automatic preparation.** Use Git worktrees when their identity, baseline, and configuration are suitable; otherwise use an isolated copy/snapshot. Keep generated setup knowledge and workspace ownership outside the target.
- **C — Full isolated clone/copy and complete environment recreation on every attempt.** Avoid reuse and reconstruct dependencies and local services each time, as a clean-room execution environment.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Low; capture state and serialize access | Safe overlap with ordinary human edits and dependable rollback | User changes mix with session changes; setup scripts affect the original environment |
| B | Workspace identity, snapshot logic, preparation discovery, and invalidation | Assuming every directory is ready or reusing arbitrary existing paths | Stale dependency caches, missed local inputs, and copy-specific behavior |
| C | Highest storage/time cost; full provisioning each attempt | Cheap reuse of native state, large artifacts, and running local services | A clean environment cannot reproduce hidden inputs, hardware, or licensed tooling merely by being clean |

**DECISION.** Choose B, combining **workspace isolation** with a **reproducible preparation record**. Assign a stable Baton project ID; display names and current locations are attributes. For Git, identify repository/worktree relationships and capture the selected checkout's actual base; do not guess that main, a remote default, or an existing branch name is the intended destination. Dirty, detached, unborn, and non-Git projects remain admissible through snapshots. Baton captures dirty/untracked source separately from committed history and does not initialize Git in the target just to manage it.

B beats A by protecting the person's working copy and separating outputs from unrelated edits. It beats C by preserving reusable, measured setup knowledge and using native tooling when the work requires it. Workspaces live in Baton-controlled storage with opaque IDs, not beside the target. Reuse requires matching project, workspace, baseline, and ownership records; an existing path is never enough. A moved project can retain its ID after identity reconciliation; identical names or remotes alone cannot merge identities.

Preparation inspects instructions, manifests, lockfiles, CI/configuration, scripts, and needed local inputs. Baton executes authorized setup under C04's trusted host policy, records readiness by capability, and invalidates preparation when relevant inputs change. Existing scripts are inspected and run as tracked setup activities; their presence does not give them authority to change Baton's work definition. Baton can create dependencies, local configuration, disposable services, and private copies of required local files itself. It must not blindly copy ignored trees, caches, secrets, external symlink targets, or a host environment wholesale. If shared Git administration would interfere with the person's checkout, choose a separate clone/copy automatically. Workspace isolation separates changes; it is not a security sandbox in trusted host mode.

**CONSEQUENCES.** Git handling, branch naming, project lookup, prompt context, retry workspace reuse, and cleanup become consumers of the workspace record. Baton needs a baseline inventory even without Git; snapshot consistency must be checked while files change, and a directory that cannot be captured consistently remains explicitly waiting for stable input rather than being falsely declared ready. Unrelated submodules, LFS objects, filters, and large files require discovered preparation, not target-specific hand instructions.

The new failures are imperfect discovery, expensive copies, stale services, and tests that depend on the original absolute path. Baton can prepare a compatible layout or identify the actual missing capability. It cannot derive an absent private signing key or recover an inaccessible proprietary SDK from source: the minimum external contribution is access to that key/SDK or its authorized source. Baton performs the remaining setup. Missing target documentation by itself is not proof of impossibility and is not grounds to refuse intake.

## C03 — Runtime and host compatibility

**Findings:** L5, L6, L8, L10, L39.

**CONTEXT.** Claude output parsing, saved-session behavior, state locations, host utilities, and environment inheritance currently leak into many relay functions. Changing one executable or home variable does not select a coherent runtime, and malformed configuration can take effect only when some later shell expression fails.

Source re-read: `lib/dispatch.sh:13–29,137–210`; `install.sh:19–34,150–167`; `lib/waits.sh:182–266`; `docs/DECISIONS.md` D-005 and D-091; `bin/baton:6–16` as traced in 01.

**OPTIONS.**

- **A — Keep a single Claude/macOS integration, centralize and validate its profile (cheapest).** Pin supported behavior and parameterize paths without building a generic adapter surface.
- **B — Narrow runtime and host adapters around semantic capabilities.** The core requests operations such as starting work, observing it, delivering input, and stopping it; adapters report what they can actually guarantee.
- **C — Replace background sessions with an embedded provider SDK runner.** Baton owns the session process and message stream, gaining a more direct protocol at the cost of replacing existing runtime behavior.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest; profile validation and compatibility captures | Other runtimes and clean separation of host behavior | CLI changes still demand core changes; one profile cannot describe missing capabilities |
| B | Adapter contracts, capability probes, and per-version compatibility evidence | Pretending all runtimes have equivalent resume, hooks, ownership, or quota support | An adapter can overstate guarantees; failed probes leave particular operations unavailable |
| C | Session lifecycle, tool integration, provider authentication, and conversation ownership | Easy reuse of native background conversations and their existing UI | SDK/runtime divergence; missing native tools or continuation semantics |

**DECISION.** Choose B, the **ports-and-adapters** pattern, with a deliberately small boundary derived from actual relay operations. A is viable for V1-sized scope, but isolates too little of the behavior that already changes across Claude versions. C is viable when owning the entire execution loop is the product goal; it is a larger replacement than project portability requires. An SDK can later implement an adapter without being required by the core.

O1 selects two actual V2 runtime implementations, **Claude Code and Codex on macOS**, not merely an interface for a hypothetical second runtime. Both share the work, admission, verification, and recovery semantics. Runtime-native controls and conversation continuity remain adapter capabilities; one runtime's missing optional feature does not disable the other's or require a project to adopt different documents.

An execution profile binds Baton state/release, runtime binary/version, configuration root, account reference, workspace, environment policy, and capability evidence. Defaults are created once and validated; a missing optional value differs from a corrupt profile. Credentials are references resolved privately, not serialized profile values. Session-only inherited variables are removed by explicit classification, while necessary authentication/toolchain variables are deliberately passed. No blanket prefix deletion or dependency on whoever first started a shared background service is acceptable.

**CONSEQUENCES.** Row/transcript parsing and English-output compatibility belong in the Claude adapter. Host scheduling, notifications, sleep inhibition, path resolution, and process deadlines belong in host integration. Every external call uses an argument vector or structured input; if a runtime insists on a shell command string, one tested encoder owns that boundary. Paths and user text are data, not source fragments.

Capability checks happen through Baton in the environment used for execution; they do not require modifying the target. If managed runtime policy disables a required hook, Baton can use an observed result stream or a fresh controlled session when supported. It must report reduced guarantees when no equivalent exists, blocking only operations whose required evidence/control is unavailable. Authentication grants controlled by the provider or OS cannot be self-issued; the minimum setup is the applicable host/provider authorization. Multi-runtime support adds independent compatibility evidence and failure handling for Claude Code and Codex; it does not imply identical hooks, session formats, or permission semantics.

## C04 — Authority and confidential inputs

**Findings:** L7, L11, L15, L50.

**CONTEXT.** A nonempty deny list under bypassPermissions is not containment, and effective settings can activate code Baton did not account for. Artifact acceptance currently proves the existence of a transcript and a project separately, while raw prompts and telemetry create additional, potentially readable copies outside the target.

Source re-read: `lib/dispatch.sh:74–94,167–198`; `lib/inbox.sh:103–138`; `install.sh:53–99`; `.scratch/baton/research/hooks.md:241–263`; `.scratch/baton/research/background-sessions.md:424–452`; `docs/SPEC.md:180–184`. Current Claude documentation explicitly limits its built-in OS sandbox to Bash and child processes, with separate tool permissions; it is not proof that hooks, MCP servers, and the whole runtime are confined. [Claude sandbox scope and limitations](https://code.claude.com/docs/en/sandboxing#limitations).

**OPTIONS.**

- **A — Trusted host execution for the selected project (cheapest).** Run setup and coding with the person's existing host access and record the effective runtime policy. The standing project trust decision permits ordinary in-scope tools without adding a Baton approval for each command.
- **B — Baton-owned execution boundary with scoped capabilities.** Confine target-controlled processes, isolate controller state, and grant only the filesystem, network, tool, and secret access the work needs.
- **C — Disposable VM per project.** Run the coding runtime and target tools in a separate operating system, exchanging only inputs, outputs, and approved services with the host.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Low; policy inspection, tracked execution, and ordinary runtime integration | A claim of containment against project/tool behavior | Project code and integrations can read or modify unrelated host or relay state |
| B | Confinement, capability grants, controlled reporting, and boundary probes | Unrestricted inheritance and silent fallback to host execution | Native tools may need unavailable resources; an omitted execution path weakens confinement |
| C | Highest provisioning, storage, and native integration cost | Transparent use of many host services, devices, caches, and credentials | VM setup differs from the real native environment; shared mounts can reopen the boundary |

**DECISION.** Choose A following the user's O2 selection of trusted host mode for the entire selected project. This supersedes the initial preference for B. A provides native tooling, local services, signing access, and discovered integrations without requiring a new sandbox implementation or a separate grant for each ordinary command. B offers stronger confinement but can turn missing native capabilities into repeated interruptions; C adds VM preparation and loses transparent host access. The user accepts A's broader access in exchange for autonomy on their own Mac.

Use the established **trusted execution** model with **separation of concerns**: the relay owns control state, and tracked execution activities do the project work. Preserve runtime/OS restrictions and explicit user instructions; project trust is not permission to bypass either or to expand the task. Baton selects an available runtime permission mode consistent with this standing policy and reports what it actually uses. Isolation may remain available when useful, but a confined first attempt or sandbox proof is not a prerequisite for trusted host work.

Each execution receives a reporting interface scoped to its current run, attempt, and execution generation. The receiver supplies or validates identity against the run record; a transcript ID, path, or name supplied by the model cannot logically authorize another lane. Reports remain claims to verify under C08. This prevents accidental cross-run routing and stale messages through supported interfaces. A token, private directory, or separate process is not authentication or containment against unrestricted same-user host code, which can tamper with those mechanisms.

**CONSEQUENCES.** Effective settings and execution paths remain observable so inherited hooks, Git filters, plugins/MCP servers, and environment changes can be diagnosed. Baton generates its run profile outside the target and configures required available integrations automatically within the selected work. Preparation, checks, and coding share the trusted host policy; no target-side permission file, mandatory sandbox, or recurring Baton trust prompt is required. Missing secrets, OS/provider authorization, and genuinely new scope still need the specific external input described above.

L11 is resolved as an explicit trust-model choice, not a new containment claim. A mistaken or malicious tool can affect unrelated files, Baton's own records, or network services accessible to the host account; independent verification does not turn a compromised host into a trustworthy one. Narrow reporting interfaces and workspace ownership remain useful for correctness under the accepted trust assumption. They are not a substitute for OS enforcement when adversarial isolation is required.

Private state uses restrictive access modes independently of the inherited umask. Secrets are injected through private references/channels, omitted from telemetry, command arguments, and notifications, and excluded from ordinary evidence copies. Exact prompts needed for recovery are private and subject to C11 retention; redaction is not a guarantee that arbitrary user text contains no secrets. Granted endpoints and the selected model provider still receive data needed for the work. No local boundary can make sending a secret to an authorized external endpoint confidential from that endpoint. The person must supply missing external authority or choose an alternative workflow; Baton performs any resulting configuration.

## C05 — Durable commands and messages

**Findings:** L16, L17, L18, L20, L35, L38, L43, L44.

**CONTEXT.** V1 launches before recording intent and moves messages before recording all their consequences. Mutable mailbox slots, content-equality replay checks, timestamp identities, and a separately written directory lock create failure windows that cannot be fixed by adding another successful-path log line.

Source re-read: `lib/dispatch.sh:266–292`; `lib/inbox.sh:217–469`; both stop hooks in full; `lib/derive.sh:185–196`; `docs/M03-FOUNDATION-HANDOFF.md:25–44`. The foundation's immutable-message proposal addresses part of this cluster, but it does not make external runtime effects transactional with local storage.

**OPTIONS.**

- **A — Immutable files, kernel lock, and a write-ahead intent journal (cheapest incremental path).** Keep shell/JSONL, assign IDs, write intents before effects, and reconcile files and receipts after interruption.
- **B — SQLite run store with transactional inbox/outbox.** Commit message receipt, state transitions, and pending effects together; execute effects outside the transaction and reconcile their results.
- **C — Event-sourced journal with rebuildable projections.** Make one durable, ordered event journal authoritative; derive inbox receipts, pending effects, and current state into disposable indexed projections. This favors replay and forensic reconstruction over directly stored lifecycle state.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Small initial change, substantial ongoing journal/replay engineering | Simple indexed queries and built-in multi-record transactions | Custom recovery misses an interleaving, torn write, or cross-file consistency condition |
| B | Database access, migrations, durability settings, and reconciliation | Editing authoritative run state with ordinary text tools | Disk exhaustion/corruption, transaction contention, or a broken reconciler stops progress |
| C | Event versioning, deterministic replay, projection rebuilds, and checkpoint validation | Straightforward schema changes to current state without historical event interpretation | A reducer change reconstructs a different state; a lost journal segment defeats recovery |

**DECISION.** Choose B: **transactional inbox/outbox**, **idempotent consumer**, and **write-ahead intent**. This replaces the custom mini-database that A would need to grow. C is attractive if replay under different policies is a principal feature, but Baton needs reliable current control more than historical recomputation; B can retain an audit trail without making every recovery depend on replaying old semantics. Store authoritative message contents and their receipt/state/effect references in one transaction; larger evidence objects are durably stored before a transaction references them. Missing or altered evidence is an integrity failure, not a reason to accept a replay.

Logical messages and commands have stable IDs independent of filenames, timestamps, or JSON formatting. Retransmission preserves identity; a changed payload under the same ID is a conflict. Distinct endings receive distinct generation-bound identities. The controller accepts only schema-valid, currently authorized transitions, and retains rejected bytes with their precise diagnosis under immutable identity. Database sequence/revision orders accepted decisions; UTC wall time describes events, and elapsed-time clocks govern live deadlines. No timestamp is an identity.

SQLite supplies atomic local transactions; it does not transact with Git, Claude, or the notification system. [SQLite transaction guarantees](https://www.sqlite.org/transactional.html). Durable intent and prompt references precede launch/delivery. A lost acknowledgement produces an **uncertain operation**, retaining its reservation until observation reconciles it. Without runtime-supported idempotency or a uniquely observable operation identity, Baton must not blindly replay a potentially successful launch or ruling.

**CONSEQUENCES.** Hooks become report producers rather than filesystem authorities; archive moves and JSONL cease determining whether work happened. Short database transactions replace stale-directory locking for state mutation. Detached external processes do not inherit ownership of the state transaction. Receipt deduplication survives deletion of optional artifact bodies because the necessary IDs and terminal generations remain.

Exactly-once external execution is impossible from local journaling alone: “the runtime accepted the command but the reply was lost” and “the runtime never accepted it” can leave identical local evidence. Retrying duplicates the first; refusing to retry strands the second. Minimum additional support is runtime deduplication or authoritative operation lookup, not a target hook installed in advance. Otherwise Baton preserves uncertainty, performs bounded reconciliation, and offers an explicit resolution. This is a deliberate availability cost in exchange for avoiding duplicate work.

## C06 — Admission and resource ownership

**Findings:** L22, L23, L24, L40; G8.

**CONTEXT.** Different V1 start/resume paths enforce different rules, and the configured cap omits several processes Baton creates. Shared-batch prompts miss newly started peers, while quota holds infer account scope from model names and sometimes treat absent telemetry as capacity.

Source re-read: `lib/tick.sh:231–277,326–375`; `lib/stops.sh:331–357`; `lib/dispatch.sh:307–324`; `lib/waits.sh:117–266`. These are competing views of admission and ownership, not just an off-by-one count.

**OPTIONS.**

- **A — Serialize all productive work globally (cheapest).** One active session, with recovery and operator continuation using that same slot; reactive quota waits.
- **B — One admission controller with durable resource reservations.** All effect-producing paths use common safety/ownership checks and operation-specific eligibility rules; reserve capacity before dispatch.
- **C — Independent per-project schedulers with divided quotas.** Allocate each project a fixed share and let it manage its own sessions and recovery.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest scheduling complexity | Useful parallelism between independent projects or isolated work | A long job or unresolved live session monopolizes the host; one parent can still spawn many children |
| B | Reservation accounting, resource scopes, and a common admission result | Back-door manual/recovery dispatches and optimistic capacity assumptions | Orphan reservations undercount usable capacity; unknown external consumption forces caution |
| C | Per-project controllers and allocation configuration | Efficient sharing without reallocation | Independent schedulers oversubscribe shared services or leave spare capacity idle |

**DECISION.** Choose B: **central admission control** and **leases/reservations**. It preserves the useful concurrency A gives up and avoids C's false independence on one host and account. Every start, retry, resume, verification/preparation session, and wake obtains the applicable reservation. A reply to an already reserved session does not consume a second slot, but still checks ownership and the current generation. A wake of a completed conversation is admitted as follow-up work, not by pretending the old unit is graph-eligible.

Admission is specific to the requested operation: preparation can run before coding readiness exists, and evidence collection can run before acceptance exists. Common authority, resource, and ownership controls still apply. This avoids turning readiness checks into a circular requirement that the person must first prepare the target.

Reservations include pending and uncertain starts, live waiting sessions, and replacement overlap. They are not released just because a timeout elapsed or a fleet listing failed. Completed conversations need not keep live processes; retained conversations and active execution have different lifetimes. The runtime/host adapter accounts for descendants where observable; a parent-session cap is never advertised as a CPU/memory bound, especially under O2's trusted host policy. Peer context comes from committed reservations, including the current batch, rather than an old fleet snapshot.

**CONSEQUENCES.** Scheduling, manual actions, recovery, and C08's checks share the admission result. Unknown resource effects default to serial work within the affected project; discovered ports, databases, devices, and integration destinations can be reserved without a user-authored resource manifest. Baton-created services get isolated instances or ports where possible. Arbitrary programs can acquire undeclared resources, so discovery is not a proof of global noninterference; denied or colliding access causes preparation/replanning rather than blind concurrency.

Quota evidence is keyed by runtime/account identity and the provider's actual limit scope, with provenance, age, and reset. Two model names do not prove an account-wide limit, and two credential profiles do not prove different accounts. Unknown shared identity is grouped for accounting without manufacturing a hold; stale/missing readings are shown as unknown and do not block productive work. Observed refusals hold only the supported limit scope. O4 selects this permissive policy by default: no fixed personal-usage reserve, total-work time limit, cost/token ceiling, or manual quota configuration is an entry requirement. A user may impose a specific budget later; delayed telemetry alone cannot enforce a strict account-wide monetary ceiling, which needs provider support.

Host capacity and interference still govern concurrent execution, but the admission controller should adapt useful concurrency to observed resource pressure and automatically resume queued work. A productive long task is not stopped merely for running overnight or passing a total-work timer. Rate limits and other temporary failures wait and probe automatically with backoff; absence of a quota API is not a reason to park. Consequences include less predictable usage and possible exhaustion of the person's available allowance. C07 bounds repeated ineffective recovery actions without making an arbitrary lifetime retry count a permanent barrier to recoverable work.

## C07 — Recovery and human ownership

**Findings:** L25, L26, L27, L28, L29, L30, L31, L32, L33, L49; G1, G6, G7.

**CONTEXT.** Recovery derives the meaning of a current execution from old attempt-wide events, so a delivered resume can remain in an API retry loop and an earlier ending can suppress a later crash. Ownership and park resolution are similarly inferred from transient rows, text hashes, timestamps, and selected file edits, leaving both repeated retries and unresolvable work.

Source re-read: `lib/derive.sh:121–145,185–247,305–339`; `lib/stops.sh:307–418,458–485`; `lib/escalate.sh:433–480`; `lib/answer.sh:160–222`; both stop hooks; `docs/milestones/M04.md:258–267`. The recorded failed first request with a live PID proves that PID liveness cannot be the lifecycle model.

**OPTIONS.**

- **A — Extend the existing derivations with generation markers and cross-attempt counters (cheapest).** Keep the present recovery architecture and fix each demonstrated reset/guard.
- **B — Explicit persisted lifecycle with separate ownership and recovery budgets.** Model work, attempt, execution generation, conversation lineage, and human ownership separately; transition on typed observations and commands.
- **C — Short disposable executions, always restart from checkpoints.** Avoid native resume and most long-lived session interpretation; use fresh sessions after boundaries or interruptions.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest migration cost, increasing historical-query complexity | A compact, inspectable source of current lifecycle truth | New interactions between endings, forks, and operator actions reopen old holes |
| B | Explicit transition rules and migration of derived state | Inferring authority from arbitrary text or treating missing observations as terminal | Missing transition coverage or wrong adapter observations can leave work uncertain |
| C | Checkpoint production and repeated setup/context costs | Cheap same-conversation continuity and many native interactive workflows | Checkpoints omit unfinished work; external side effects are repeated after a restart |

**DECISION.** Choose B, an **explicit state machine** with **bounded retry** and a separate **ownership state**. It makes the distinctions missing in A enforceable without throwing away native continuity as C does. Every successful start/resume establishes a new execution generation, even if the runtime session ID is unchanged. An ending affects that generation only. A wait becomes a single recovery operation when due; accepted delivery moves to recovery observation and cancels that wait's timer. Productive progress clears the incident; failure starts a new bounded incident. Missing acknowledgement is uncertain, not another permission to stop/resume.

Failure history belongs to the work unit across attempts and survives redispatch. A process start, transcript timestamp, or another attempt does not erase it. Under O4, use a **circuit breaker** to bound bursts of the same ineffective action: wait, observe, recheck changed prerequisites, or try a meaningfully different supported recovery path. Transient failures permit scheduled probes and automatic recovery without a user resetting a counter. Productive progress or evidence of a repaired cause can close the incident; a fresh attempt alone cannot. A confirmed nonrecoverable failure, missing authority, unresolved side effect, or exhausted set of meaningful recovery paths remains actionable attention, rather than an infinite loop of identical sessions. These rules bound waste, not the lifetime of otherwise productive work.

Startup failures, local dialogs, permissions, input questions, worker waits, and unknown states all receive an explicit interpretation or attention state. Transport choice does not suppress question handling. Stalls alone do not prove that killing a process is safe. Runtime/account changes must preserve the selected work's authorization and data policy; recovery cannot create credentials, purchase capacity, or pretend to transfer an unavailable live conversation.

**CONSEQUENCES.** Every park has a stable identity, scope, cause, and available resolution even when no session or project can be assigned. Recheck runs the failed capability check again; a newly created brief or repaired permission/service can therefore resolve its actual cause. Manual acceptance invokes the same closure/accounting transition as normal acceptance, with its different evidence level retained. Pause, drain, cancellation, and deregistration become explicit intentions; cancellation suppresses automatic recovery but does not erase work or free resources until termination is confirmed. Deregistration retires identity and preserves history.

Human ownership survives a disappearing row and does not expire into automated action. Explicit takeover/hand-back is authoritative. Adapter-detected outside input triggers stand-off; missing or ambiguous actor evidence suspends autonomous prompting. Where a runtime cannot atomically order human input and Baton delivery, an absolute no-overlap guarantee is impossible: the two can race after any read. The minimum support is runtime mediation or using Baton's control channel for ownership; absent that, this limitation must be exposed before native direct interaction is offered as fully protected.

Baton can discover an existing session and import its available workspace/transcript as context. Full adoption requires proving identity, exclusive control, and the necessary observation/reporting capability; otherwise it remains observe-only and Baton offers a fresh managed continuation from captured work. It does not forge a historical dispatch. Periodic/boundary checkpoints preserve work inventory, decisions, verification, and unresolved tool actions; incomplete actions are reconciled before repeat. A checkpoint cannot recover private model state or an unrecorded side effect after a sudden death. Finished-session forks inherit conversation lineage and follow-up purpose, not renewed milestone reporting obligations.

## C08 — Evidence before integration

**Findings:** L13; G9.

**CONTEXT.** The current completion check accepts any sufficiently named ancestor of main, including the project's first commit. The coding session also owns acceptance claims, merging, and combined-tree checks, so concurrent close-outs can publish unverified work or invalidate one another's evidence.

Source re-read: `lib/inbox.sh:33–58,139–167`; `CONTRACT.md:28–40`; `docs/SPEC.md:173–174`. Requiring a newer commit alone would still not establish that the requested work exists.

**OPTIONS.**

- **A — Stronger session attestation (cheapest).** Require a baseline-bound diff, candidate identity, check results, and evidence from the coding session; verify structural consistency before accepting it.
- **B — Controller-owned verification and serialized integration.** Freeze a candidate, independently execute applicable checks, and evaluate the combined result against its current destination before publication.
- **C — Human acceptance and integration for every unit.** Baton prepares a reviewable patch/evidence package and waits for the person to apply and close it.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Low; additional report shape and consistency checks | Independent evidence that the checks actually ran on the candidate | A plausible but false report still closes work; self-selected checks miss the objective |
| B | Independent execution, candidate snapshots, and integration reconciliation | Treating a report or any ancestor commit as sufficient completion | Flaky checks, incomplete acceptance, or destination drift prevent acceptance |
| C | Lowest automated integration risk, recurring human effort | Unattended progress through dependent units | A person is unavailable or accepts the same inadequate evidence; review becomes the bottleneck |

**DECISION.** Choose B: **verify before publish**, a **merge queue**, and **optimistic concurrency control**. It produces evidence A cannot independently establish and avoids making C's human review a universal prerequisite. The coding session proposes a candidate and explanation. Baton binds the candidate to the work definition, captured baseline, actual changed files, and execution provenance, then runs applicable verification in a separately controlled workspace. Semantic review, when needed, is another bounded session; it cannot manufacture missing deterministic evidence.

The verification recipe is tied to the accepted work definition and baseline before implementation; the coding session cannot silently weaken it by editing tests or reporting a different command. Changes to verification are themselves reviewed proposals. Baseline failures, newly introduced failures, unavailable checks, and explicit waivers stay distinct, so an already broken project can still receive useful work without a false all-green claim.

For Git, the queue tests a candidate combined with the current destination base, and publishes only if the expected destination still matches. Git supports comparing the old ref value during an update; that protects a ref, not a checked-out working tree. [Git update-ref](https://git-scm.com/docs/git-update-ref). If the base changes, recompose and reverify. Baton must not move a checked-out branch underneath a dirty index/worktree; use a safe integration destination and separately coordinate any application to the person's checkout. For non-Git projects, verify the proposed output snapshot and use baseline/file conflict checks on application. Partial file application is recoverable and never reported as atomic repository publication.

**CONSEQUENCES.** Session-authored complete becomes a proposal; accepted completion and verified integration are distinct recorded facts. O3 selects automatic local application/integration once the candidate passes verification and destination checks, with no routine extra approval. Dependencies consume the artifact/baseline their work actually needs. Git operations and checks are tracked execution activities under C04/C06; verification is operationally independent from the coding session, not secure against a malicious process with full host access. The database and filesystem/ref update are not one transaction: record integration intent, observe the resulting tree/ref, and reconcile before closing work. For ordinary directories, a hash check alone cannot prevent another application writing immediately afterward, and an advisory lock cannot stop an uncooperative writer. If exclusive application cannot be established, retain the verified snapshot/patch and surface that application conflict instead of claiming a safe multi-file update; ongoing work can still use the isolated accepted snapshot.

No existing test suite is required. Baton discovers checks and derives task-specific acceptance from the request; it may add tests as part of the authorized change when they are useful. A missing suite is not permission to substitute “commit exists.” Subjective behavior or inaccessible hardware may require a specific human observation; if no executable or observable criterion distinguishes right from wrong, universal proof of correctness is impossible. The minimum input is that criterion/observation. A no-code-change outcome can still be accepted if it satisfies the request with evidence. Automatic application covers the requested local changes, including non-Git outputs; it does not silently authorize push, deployment, destructive replacement, or unrelated dirty changes. Explicit instructions reserving an action for the person take precedence. Baton never invents a verification waiver; any waiver the person supplies remains distinguishable from verified success and unblocks only the dependencies that ruling covers.

## C09 — Reconciliation and explanation

**Findings:** L34, L36, L45; G11, G12.

**CONTEXT.** An unbounded external call can hold the same lock required by status and operator actions. Meanwhile a fresh tick marker can hide skipped safety checks, and a failed fleet read can look like no live work, so the relay cannot always explain why an eligible unit is idle.

Source re-read: `lib/tick.sh:326–396`; `lib/status.sh:164–225`; `tests/run.sh:126–189`; the lock/call ordering traced in 01. A richer status formatter cannot repair missing or conflated observations.

**OPTIONS.**

- **A — Bound calls and write one cached status snapshot (cheapest).** Retain the monolithic tick, add deadlines, and serve last-known status without taking its lock.
- **B — Short reconciliation passes over durable operations and observations.** External work runs outside state transactions with deadlines; each pass records its own health and admission explanations. Read-only views query that record directly.
- **C — Always-running reactive controller with an event bus.** Runtime events drive state and subscriptions immediately; timers and recovery run inside the controller service.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Low; cache format and deadline wrapper | Precise partial-progress explanations and independent operation ownership | Snapshot goes stale while one operation occupies the tick; timeout may leave a detached effect |
| B | Operation tracking, bounded probes, and structured query results | Treating one timestamp as proof that every check passed | Reconciliation bugs accumulate uncertain operations; observation freshness needs explicit handling |
| C | Service lifecycle, event ordering, subscriptions, and reconnection | The simplicity of restartable periodic work | Lost events or a dead controller still require periodic reconciliation |

**DECISION.** Choose B, a **reconciliation loop** with **bulkheads**. C's lower event latency is useful but does not remove reconciliation; A hides too much behind a summary snapshot. Keep the restartable tick model, but never hold a state transaction across Git, a runtime command, setup, or notification delivery. Control/probe calls have wall-clock deadlines and tracked ownership; a timeout triggers termination/observation as appropriate and remains uncertain if the external effect can survive it. Long-lived productive activities are observed independently rather than killed by a total-work timer. Per-project failures isolate that project, while unreadable authoritative admission/ownership state holds the operations depending on it. Quota telemetry is optional under O4; a failed reading is visible and does not hold work.

The same admission function produces both the actionable decision and its explanation: graph revision, waiting dependency, resource reservation, policy/capability failure, uncertain operation, or human ownership. A preview evaluates it without creating effects or promising that the reservation will still be available later. Status and inspection have a stable machine-readable form plus a human rendering; no API server is required for a local CLI to expose structured controls.

**CONSEQUENCES.** Tick health records distinguish started, partially reconciled, failed, and completed, with per-project/capability timestamps. Unknown fleet state stays unknown. Rejected messages, uncertain starts, missing receipts, queues, and operation failures remain inspectable even when a runtime or target is unavailable. Slow status readers must be bounded too; moving them outside a long lock must not create new transaction starvation.

A separate host watchdog observes controller progress independently and reports a stuck/unloaded relay through the local attention channel; it does not restart uncertain target work itself. It monitors useful progress, not merely a live PID. Both components can fail with the host, and no process on a powered-off/offline machine can notify another device by itself. Minimum additional support for an off-host outage guarantee is an independently running external observer/channel. O5 permits a simple optional integration for that capability; it is not a required service or a condition for Mac work to proceed.

## C10 — Operator communication

**Findings:** L12, L46, L47, L48.

**CONTEXT.** V1 enables Remote Control for every session but does not establish that the operator can reach it, and its notification log records intent rather than receipt. A click selects a global newest target, while wake messages pass through model-generated shell syntax before reaching a safer stdin interface.

Source re-read: `notify/Baton.applescript` in full; `lib/lifecycle.sh:137–155,325–353`; `install.sh:79–99`; `lib/dispatch.sh:74–88`. The heredoc problem sits before stdin handling and cannot be fixed by testing only the latter.

**OPTIONS.**

- **A — Local CLI and durable attention list (cheapest).** Remove the wake model; generic notifications tell the person to inspect the list and issue an explicitly addressed command.
- **B — Typed operator commands plus addressed notification transports.** Keep a local attention record as authority; optional native/remote channels carry event IDs and opaque message data through the same command boundary.
- **C — Baton-owned browser/phone control application.** Build an authenticated interface for reading sessions, answering questions, and managing all work directly.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest; no conversational router or new remote service | Direct notification navigation and convenient phone control | The person misses the list or must return to the Mac |
| B | Delivery state, per-event addressing, and limited native adapters | Equating native runtime connectivity with delivery or letting a model compose commands | Stale links, revoked permissions, and transport acknowledgements that stop short of human attention |
| C | Largest UI, authentication, synchronization, and deployment cost | A small local-only control surface | Control service/network failure becomes another reason the person cannot answer |

**DECISION.** Choose B: **command/query separation** with **addressed messaging** and a **delivery outbox**. A remains the fallback control path, but loses too much of Baton's existing operator convenience as the entire design. C creates a second product before a typed local boundary has been established. Rulings/wake input name a stable work/park/conversation identity and carry exact text as data; deterministic dispatch selects the operation. A model may help disambiguate a request, but has no role in quoting shell or deciding which privileged verb to run.

Notification intent, queued delivery, transport acceptance, failure, and observed operator action are different facts. Retries use notification identity, not once-only intent keys. A native click returns that notification's identity and opens its durable attention record; the record can then link to the current session. On macOS, UserNotifications provides request identifiers and response callbacks carrying the request, unlike the existing global-target applet. [Apple request identifiers](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier?language=objc), [notification response handling](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions?changes=_2).

**CONSEQUENCES.** The model-driven always-on wake session and fixed heredoc transport disappear. Session URLs become capabilities resolved by the runtime adapter; expired links still lead to useful local state. Multiple notifications neither redirect one another nor clear unrelated attention records. Use Baton's own identity/icon; the existing copied vendor mark adds no technical value and the repository does not establish permission for broader reuse.

O5 selects Mac-first controls with opt-in native remote access and phone notifications where the selected runtime/channel supports them. Baton records reachability and delivery failures; local execution continues when a phone is offline or no remote feature is available. Remote interaction remains separate from question interpretation. A simple independent notification/watchdog integration may add capability if it reuses an existing supported service or transport; a custom phone application, hosted control plane, or complex new infrastructure is not required by this choice. Failure or omission of that optional integration never holds local work.

OS acceptance cannot prove that a person saw a banner, and an online bridge does not prove phone delivery; only an observed action supports that narrower claim. Claude Code and Codex need not expose equivalent native remote features. The local attention record supplies consistent control, with each adapter exposing what is actually available. No remote choice requires installing or editing anything in the target project.

## C11 — Maintenance of code and state

**Findings:** L41, L42; G10.

**CONTEXT.** V1 repeatedly reads its entire history, retains every workspace and raw artifact, and overwrites installed scripts sequentially while keeping old settings. Recovery, upgrade, rollback, and relocation therefore depend on undocumented combinations of code, state, and retained files.

Source re-read: `install.sh` in full; `lib/derive.sh:121–145,185–247`; `lib/candidates.sh:33–75`; `CONTRACT.md:33–37`; `docs/DECISIONS.md` D-094. The notifier already has partial staging, but neither that nor a copied database alone gives a consistent recoverable installation.

**OPTIONS.**

- **A — Drain, back up, and reinstall in place; retain history (cheapest).** Stop admission, copy a consistent state set, replace files, and restart all managed work under one version.
- **B — Immutable versioned releases and managed state lifecycle.** Pin executions to compatible protocol/release versions, atomically select an installed release, and maintain indexed active state plus recoverable retained evidence.
- **C — Checkpoint-and-restart upgrades into a fresh state home.** Export active work and terminal evidence, then import them under the new release and continue in fresh sessions. Keep the old installation intact for inspection rather than migrating live run state.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Low code cost, disruptive maintenance and growing storage | Seamless continuation and bounded historical read cost | Partial replacement after interruption; missing old session settings; disk growth |
| B | Release compatibility, migration, backup manifests, and reachability-based cleanup | Manual deletion/copying of authoritative state as supported maintenance | Incorrect migration or cleanup can strand a run; rollback may need an older snapshot |
| C | Validated export/import and checkpoint reconstruction on each upgrade | Native session continuity and inexpensive frequent upgrades | A checkpoint omits unfinished actions, or imported work repeats an external side effect |

**DECISION.** Choose B: **immutable releases**, **schema migration**, **snapshot backup**, and **indexed active state**, with O6 selecting retention until explicit deletion. A is a reasonable emergency upgrade procedure, but does not solve sustained history costs and makes every maintenance action a session interruption. C is useful for a major incompatible protocol replacement, but making every upgrade a fresh-session boundary discards continuity and magnifies checkpoint omissions. SQLite indexes/current-state records bound ordinary reads to relevant work; the audit history remains available without replaying it for every status query. Retention size and current-query cost are separate decisions: the user accepts growing historical storage, not repeated whole-history scans.

Release activation is a controlled boundary between compatible code, protocol, policy, and state. Hooks/settings refer to the execution's pinned release/profile; old releases stay while referenced. An incompatible upgrade drains or suspends work rather than silently rewriting its saved environment. Existing policy grants are migrated explicitly; preserving a file is not evidence that it meets a newer policy. The selected storage mode must support bounded readers and durable writes on the local filesystem; WAL is an optional measured optimization, not a prerequisite. It adds checkpoint/backup obligations and cannot be treated as one standalone file. [SQLite WAL constraints](https://www.sqlite.org/wal.html).

**CONSEQUENCES.** Backups capture a consistent database and the evidence/workspace objects it references, with a manifest and integrity checks; SQLite's backup facility is a suitable database primitive. [SQLite backup API](https://www.sqlite.org/backup.html). Restore creates a new controller generation, fences old execution authority, and reconciles live processes before any operation can replay. Credentials and external runtime authentication are re-resolved, not bundled into recovery exports. A backup can preserve Baton's knowledge without promising to resurrect an unavailable native conversation.

Prompts, rulings, artifacts, evidence, checkpoints, and closed workspaces remain until the person explicitly deletes them. No age, size, or completion threshold silently removes that history; it needs no periodic renewal or pin. Routine cleanup is limited to disposable execution temporaries and reproducible caches that are not retained evidence or part of a kept workspace. Reachability checks govern safe explicit deletion and maintenance, not automatic expiration of retained content. Retired execution namespaces remain rejected even after an authorized deletion, so cleanup cannot turn stale messages into new work.

Continuing disk growth and longer backup operations are accepted costs of O6. Capacity observations notify early and offer concrete maintenance; a missing free-space estimate or an arbitrary history quota does not stop work. Actual inability to persist the next operation must suspend affected writes rather than delete retained history or operate without durable intent. Retaining a workspace improves later continuity but cannot guarantee that an external runtime retains its native conversation forever; C07 still offers checkpoint continuation when needed. Code/schema rollback is refused when incompatible instead of opening newer state with older readers.

## C12 — Protocol authority and proof

**Findings:** L51, L52, L53, L54.

**CONTEXT.** At the audited revision, lifecycle meanings are duplicated across fixed validation, routing, rendering, and recovery tables, and the repository simultaneously describes conflicting contract generations. The fixture suite captures useful behavior but also freezes deficiencies, depends on canonical paths and Apple build tools, and does not prove an unattended unfamiliar-project run.

Source re-read: the former foundation notice at `CLAUDE.md:3–7` at the audited revision; `docs/M03-FOUNDATION-HANDOFF.md` and ADR 0001 in full; `lib/plan.sh:141–182`; `lib/inbox.sh:103–195`; `tests/run.sh:126–189`; `tests/shim/claude:48–125`; `tests/scenarios/install/cmd`; `docs/milestones/M07.md:295–324`; M08's empty completion evidence in 01.

**OPTIONS.**

- **A — Keep the shell core, centralize tables, and repair fixtures (cheapest).** One shared taxonomy and protocol document, explicit old-document labels, and portable test paths.
- **B — Small typed semantic core with adapter conformance tests.** Define lifecycle meanings and validated inputs once, keep a finite state machine, and test invariants separately from rendered output and real integration.
- **C — Declarative internal transition model with an interpreter.** Define states, permitted transitions, reasons, and actions in one validated data model that drives execution, documentation, and tests. The model ships with Baton; target authors need not write it.

**TRADEOFFS.**

| Option | Complexity cost | What it forecloses | How it fails |
|---|---|---|---|
| A | Lowest change cost; still extensive shell/jq coordination | Strong control of invalid states across many callers | Updated tables and implicit shell behavior still disagree; snapshots normalize a defect |
| B | Typed core, explicit transitions, and a build/release artifact | Arbitrary runtime-defined lifecycle semantics | A shared semantic bug affects every view; compatibility evidence can become stale |
| C | Model/interpreter validation, expressive guards, generated views, and migration | Direct language-level checking and debugging of transition logic | Model and interpreter agree on the same wrong meaning; custom guards become a second programming language |

**DECISION.** Choose B: **functional core / imperative shell** and **contract testing**. A remains attractive for small hooks, but the current hundreds-of-lines modules and interdependent state queries have crossed D-005's stated threshold for a typed component. C could pay off for many independently maintained workflow families; Baton instead has one lifecycle whose difficult guards depend on real runtime and workspace evidence. Keeping those guards in ordinary typed code avoids maintaining an interpreter alongside them. Project-specific reasons may be descriptive data attached to a known lifecycle category; adding a new transition is a deliberate core change, not a string accepted in one table and forgotten in another.

Keep deterministic judgment placement from ADR 0001. Use a small Swift core for O1's macOS scope, with Claude Code and Codex adapters and shell only at simple boundaries. Multi-runtime support does not require a cross-platform controller or a provider-specific core. This is a design decision, not permission to run a compiler in this task. There is no reason to add a third-party workflow framework or a hosted service for it.

**CONSEQUENCES.** Protocol ownership and precedence must be explicit for each release. O7 makes these V2 decisions, as amended by the user's rulings, the forward design authority over conflicting V1/foundation choices. Historical briefs and the separate foundation tree remain evidence, not a parallel contract to implement or bulk-import. C05/C01 adopt independently justified ideas also present in that history. The obsolete foundation-precedence notice in CLAUDE.md is retired; existing V1 implementation records remain descriptive of that implementation. Future normative documentation must describe the selected protocol, and runtime capability output must say which one is actually active.

Verification uses independent layers: state-transition invariants and failure interleavings; adapter contracts against versioned captured inputs; temporary relocated project fixtures; isolated host installation checks; and bounded real-runtime unfamiliar-project trials. Critical invariants include one authorized active owner, no effect without recorded intent, no uncertain replay, and no accepted completion without the declared evidence. Golden output remains useful for presentation but cannot be the only oracle. Installation/signing checks are separated so ordinary checks do not unexpectedly compile or alter the host. Test fixtures must include targets without Baton files, non-main and non-Git inputs, dirty workspaces, unavailable setup inputs, and hostile/disabled settings.

Live quota recovery, fresh-user installation, and each runtime's behavior are claims only after corresponding observations, not after a shim passes. Under O2, confinement is not a claim or prerequisite for trusted host operation; any optional isolation mode requires its own evidence. Unobserved external behavior remains a named compatibility limitation; use the supported subset or an alternative observable path, and block only operations missing required control/evidence. This introduces ongoing evidence maintenance, but avoids paying for a large test inventory that proves only agreement with itself.

## USER RULINGS — 2026-09-14

The original O1–O7 identifiers are retained for traceability. These selections supersede the initial recommendations wherever they differ; the affected cluster decisions above describe the resulting design.

| Ruling | Selected policy | Affected clusters |
|---|---|---|
| O1 | B — macOS, with Claude Code and Codex confirmed as the runtime pair | C03, C12 |
| O2 | C — trusted host mode for the selected project | C02, C04, C06, C08, C12 |
| O3 | A — automatic local application/integration of verified work | C08 |
| O4 | Autonomy-first refinement: permissive by default, stricter budgets only if requested | C06, C07, C09 |
| O5 | B — native remote support alongside primary Mac controls; simple independent notification/watchdog capability optional | C09, C10 |
| O6 | C — retain history and closed workspaces until explicit deletion | C04, C11 |
| O7 | A — V2 decisions replace conflicting V1/foundation design authority | C12, CLAUDE.md notice |

### O1 — macOS with Claude Code and Codex

**Decision:** The user chose macOS with multiple runtimes, then explicitly named **Claude Code and Codex**. Both are in V2 scope. Other operating systems are not required; a merely replaceable executable or unimplemented second adapter does not satisfy this choice.

**Implications:** Use the shared Swift core and separate runtime adapters, preserving each runtime's supported features and reporting its actual guarantees. This costs more compatibility and live verification work than Claude-only support, but avoids baking one coding client into project intake, control state, or recovery. Live cross-runtime conversation transfer remains the separate G5 deferral; ordinary work can begin in either supported runtime without preparing the target.

### O2 — Trusted host execution for the selected project

**Decision:** The user's standing choice is whole-project trusted host mode. This is O2 option C, which maps to C04's revised host-execution option A, not C04's VM option C. It replaces the earlier confined-by-default selection and removes per-capability Baton approval as the ordinary workflow.

**Implications:** Native tooling and local services are available under the person's existing host access and runtime/OS policy. The selected project's instructions and tools are trusted for execution; Baton still owns scheduling decisions and preserves work identity. Project selection under this standing policy does not require a fresh trust questionnaire or a target configuration file. Broader host access and its possible consequences for unrelated data or Baton state are accepted; no adversarial containment or tamper-proof verification is claimed. Explicit user restrictions, unavailable OS/provider grants, and scope boundaries remain real constraints.

### O3 — Automatically apply verified local changes

**Decision:** Automatically apply/integrate work that passes its verification and destination checks within the original request. There is no routine review/merge approval inserted between successful verification and local application, for either Git or non-Git projects.

**Implications:** Baton can carry a build through dependent work unattended, while preserving unrelated dirty changes and reconciling integration failures. Explicit instructions to leave a patch or reserve an action for the person override the standing default. Automatic application does not silently authorize external publication, deployment, unrelated destructive changes, or fabricated verification. A person can supply a specific waiver, but Baton never generates one to remove a blocker; the record retains the missing guarantee and the ruling's dependency scope.

### O4 — Autonomy-first resource and recovery policy

**Decision:** The user accepted the recommendation with a stronger controlling preference: choose the behavior that provides the most autonomy without introducing another onboarding or operating limitation. Use permissive operation by default; strict reserve/cost/token/time policies remain optional only when the person requests them. Choosing or configuring a budget is not a prerequisite to using Baton.

**Implications:** Missing or stale quota telemetry means unknown capacity, not a park. A productive run can continue without a total-work timer or arbitrary spending ceiling, subject to actual provider limits and host resources. Known transient limits cause automatic waits, backoff, and probes; they do not require a person to restart work or reset a lifetime retry counter. Adaptive admission queues work when host resources are constrained and resumes it automatically. Circuit breakers prevent rapid repetition of an ineffective action, while observations, changed prerequisites, and supported alternative recovery paths can restore progress automatically.

This accepts less predictable resource use and the possibility of spending the person's available allowance. It does not authorize purchasing capacity, inventing credentials, bypassing provider controls, duplicate uncertain launches, or endless identical failing attempts. When further progress actually requires missing information, authority, or resolution of an ambiguous side effect, Baton explains that specific need. These are limits of available evidence or execution, not requirements to prepare the project.

### O5 — Mac-first capability, native phone access, optional simple off-host support

**Decision:** The person mostly works on the Mac and values phone notifications. Keep local controls fully capable, support opt-in native runtime remote access where available, and permit a simple independent notification/watchdog integration as an optional extension. This adopts O5 B and C's useful additional capability conditionally; it does not adopt C's remote-health requirement as a default admission gate.

**Implications:** A phone or remote service being unavailable never prevents local work. Independent delivery/outage detection is worth adding when an existing supported transport/service can provide it with modest integration effort. A custom mobile application, hosted control plane, or substantial new infrastructure exceeds the intended optional scope; defer that integration if it needs those, without holding the rest of V2. Exact transport feasibility is an engineering question to investigate, not an unresolved request for the user to choose a service now. Until proved, Baton claims neither guaranteed phone receipt nor off-host outage detection. Any external account access follows its actual authorization boundary.

### O6 — Retain until explicit deletion

**Decision:** Retain prompts, rulings, artifacts, evidence, checkpoints, and closed workspaces until the person explicitly deletes them. No automatic expiry, history-size eviction, or periodic pin/renewal requirement applies.

**Implications:** Long-term recall and recovery take priority over minimizing storage. Indexed queries and active-state projections avoid processing all retained history on each tick. Safe disposable temporary/cache cleanup is still possible, but cannot be used to remove retained evidence or workspace contents indirectly. Increasing storage, backup cost, and continued presence of confidential project content are accepted. Capacity warnings and user-directed cleanup are appropriate; silently deleting history is not. Actual disk exhaustion remains a physical inability to persist work, not a policy budget Baton can waive.

### O7 — One forward V2 authority

**Decision:** The user accepted the recommendation that these V2 decisions replace conflicting V1/foundation design choices. Preserve the foundation and M03 histories as evidence, adopt mechanisms on their merits, and retire the old foundation-precedence notice in CLAUDE.md.

**Implications:** There is one forward design authority, not a dual-protocol requirement or a requirement to reconcile the entire separate foundation branch before designing V2. Existing V1 source and historical requirements still describe the implementation that actually exists; accepting a design does not implement, deploy, or validate it. The current task remains design decisions only.

## OPEN DECISIONS

None currently requiring user input. O1–O8 are settled, including the runtime pair and the default/fallback policy below. Adapter compatibility, preparation discovery, and the effort needed for optional independent phone/outage notifications require technical evidence rather than another preference question. The optional integration remains conditional on modest complexity and cannot become a prerequisite for local use. If later evidence forces a material change to these selected policies, record the concrete tradeoff as a new open decision instead of silently narrowing autonomy or adding target-side preparation.

### O8 — Default runtime selection and automatic runtime fallback

**Status:** RESOLVED — identified while writing the V2 specification and answered by the user on 2026-09-14. O1–O7 remain settled. The original question below is retained as decision history.

**Decision needed:** When a request supplies only a project location and work, both Claude Code and Codex are authenticated and capable, and no existing user preference selects a runtime, how does Baton choose? After that selection, may Baton automatically start a fresh continuation in the other runtime when the selected runtime cannot currently make progress, or must it keep waiting/recovering within the selected runtime until the person requests a change?

**Why the existing decisions do not answer it:** O1 requires both adapters but does not select a default or routing policy. C03 binds each execution to a runtime/profile but does not determine that binding. O4 requires autonomy and automatic transient recovery, while C07 requires runtime/account changes to preserve authorization and data policy; neither specifies whether automatic cross-runtime fallback is part of that authorization. G5 defers live conversation transfer but expressly permits fresh checkpoint continuation, so that deferral does not decide which runtime may receive a fresh continuation.

**Concrete case:** On a Mac with both runtimes ready and no saved preference, the person points Baton at a new directory and asks it to fix a bug. Baton must select a runtime before even a model-assisted intake session can begin. Later, that runtime reaches a confirmed temporary provider limit while the other remains available. Capability probes can establish availability and continuity guarantees; they cannot establish the person's preferred provider or standing permission to switch providers. The choice affects which provider receives project context, which available allowance is consumed, and whether Baton waits or continues elsewhere.

**Decision:** Default to **Claude Code**. Baton may automatically fall back to **Codex when Claude Code has exhausted its usage allocation**. Missing/stale telemetry, an unavailable executable, authentication failure, a permission problem, or an ambiguous launch does not by itself establish exhaustion. An explicit user runtime selection or data restriction remains authoritative.

**Constraints already settled:** This must not become mandatory per-project configuration or a recurring runtime questionnaire. Both runtimes remain implemented and usable. Explicit user runtime/data restrictions take precedence. Any authorized fallback uses a fresh session and retained work/checkpoint context; it does not claim live conversation transfer. Uncertain earlier launches, ownership, and unfinished side effects must be reconciled before replacement work can start. Missing quota telemetry alone remains non-blocking. The user's ruling grants fallback authority for the stated exhaustion condition within these constraints.

**Specification impact:** Unblocks specification drafting. Default selections use Claude Code unless the exhaustion fallback applies. Record fallback cause, profiles, checkpoint, and fresh conversation lineage. A productive Codex continuation is not interrupted just because Claude allocation resets; subsequent default selections reevaluate current exhaustion evidence. If Codex is unavailable, retain automatic Claude wait/probe recovery under O4. Fallback does not authorize new credentials or purchased capacity.

**User answer:** “it should default to Claude Code, and it may fallback to Codex if Claude Code has ran out of its usage allocation”
