# Baton vocabulary

Baton is a deterministic local coding-agent orchestration tool. A restartable process does not mean
there is no state: state is durable evidence reduced into a current view.
Document authority and change procedure are defined in `docs/GOVERNANCE.md`.

| Term | Meaning |
|---|---|
| Project | A registered canonical Git checkout, committed plan and person-owned execution policy. |
| Milestone | A stable unit in the project's dependency graph, with a brief and acceptance evidence. |
| Plan snapshot | One committed revision supplying graph, gate declarations, brief and launch base. |
| Run | A unique prepared execution request for one project/milestone, independent of provider session identity. |
| Active run | An acknowledged run not yet complete or abandoned. This does not prove that its process is currently live, productive or free of a question. |
| Attempt | A numbered run at a milestone. Preparing another attempt does not erase its failure history. |
| Recovery episode | A failure budget spanning attempts until verified progress or an explicit reset. |
| Session | A provider conversation/process, acknowledged against a run. Process existence and conversation history are different observations. |
| Prepared | Durable request exists; the external launch has not been marked started. |
| Uncertain | Launch may have happened but its session has not been acknowledged. It reserves capacity. |
| Observation | Tagged success, unavailable, or incompatible response. Only successful observations can prove absence. |
| Execution condition | What current evidence says about running, waiting or needing a decision; separate from durable run phase and ownership. |
| Delivery | One identified prompt/ruling transmission and its acknowledgement. Detailed delivery implementation belongs to M04, not the current publish command. |
| Cancellation | A future identified stop request and confirmed outcome; not equivalent to closing tracking with abandon. |
| Claim/release | Explicit human ownership and acknowledgement of a specific typed-record boundary. |
| Handover | An immutable contract-2 message describing one ending, identified independently of its session and pathname. |
| Message ID | Stable identity reused on delivery retries and printed fallback; conflicting contents are rejected. |
| Processing | Claimed messages awaiting validation, acknowledgement or archival; restart resumes this work. |
| Integration operation | One exclusive attempt to merge and check a candidate in a separate worktree and promote its exact commit. |
| Integration receipt | Durable binding of run, candidate, expected main, checked commit and verified tree. |
| Completion | A matching run's immutable ending supported by that receipt and commit ancestry. |
| Escalation | A recorded need for human input. It remains visible after its artifact leaves the inbox. |
| Gate | A committed scheduling hold requiring a matching person-owned approval token before it opens. |
| Journal | Logically append-only events, physically replaced atomically under the kernel mutation lock. |
| Release | Immutable installed scripts selected by an atomic pointer; active sessions keep their pinned hook paths. |
| In progress | Work confirmed in a named workstream; separate from machine completion, integration, and live process evidence. |
| Combined candidate | A checkpoint containing both foundation and M03 adaptations, requiring its own test/review evidence. |
| Capacity reservation | Admission accounting for work that may consume resources. A future execution lease can release a proved-stopped worker's resources without forgetting its run. |
| Capability proof | An observation scoped to a host, executable/release, provider version and launch context; not a universal guarantee. |
| Provider adapter | Bounded calls and normalized observations; policy must not interpret provider wording itself. |
| Tick | Future scheduled reduction/reconciliation. It embeds no model call and executes no target scripts. |

A worktree is version-control isolation, not an OS sandbox. Tool deny patterns are not an enforced
boundary against a process running as the same account. No phrase in this glossary upgrades a
best-effort heuristic into an absolute guarantee.
